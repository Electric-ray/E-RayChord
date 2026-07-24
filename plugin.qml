import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0
import FileIO 3.0

import "engine/SelectionReader.js" as SelectionReader
import "engine/ChordReader.js" as ChordReader
import "engine/PatternEngine.js" as PatternEngine
import "engine/VoicingEngine.js" as VoicingEngine
import "engine/NoteGenerator.js" as NoteGenerator
import "engine/Writer.js" as Writer

// ============================================================
// ErayChord — Guitar Accompaniment Generator (8단계: 실제 동작 버전)
//
// 지금까지 poc/ ~ stage7/ 에서 하나씩 검증한 것들을 여기서 하나로
// 연결한다. 흐름(기술설계서 5절과 동일):
//
//   선택 영역 읽기(SelectionReader)
//     -> 코드 읽기(ChordReader)
//     -> 운지 라이브러리에서 코드별 피치 구하기(VoicingEngine,
//        4단계 내장 라이브러리 + 7단계 사용자 운지 편집기 결과 병합)
//     -> 패턴 라이브러리에서 리듬 불러오기(PatternEngine,
//        기본 제공 패턴 + 6단계 패턴 편집기로 저장한 사용자 패턴 병합)
//     -> 음표 이벤트 생성(NoteGenerator)
//     -> 악보에 쓰기(Writer)
//
// 패턴을 새로 녹음하거나(패턴 편집기) 운지를 추가/수정하려면
// (운지 편집기) 아래 두 플러그인을 따로 실행한다:
//   - Plugins > ErayChord > Pattern Editor  (ui/PatternEditor.qml)
//   - Plugins > ErayChord > Voicing Editor  (ui/VoicingEditor.qml)
// 여기서 저장한 내용은 이 메인 플러그인이 "라이브러리 새로고침"을
// 누르면 바로 반영된다.
//
// 검증 필요 항목(수정 완료, 2차 테스트 필요):
//   처음에는 engine/*.js 안에서 ".import MuseScore 3.0"으로 Cursor/Element/
//   SymId/NoteHeadGroup enum을 직접 가져다 썼는데, 실기 테스트 결과
//   뮤트 노트헤드(X머리 음표)와 액센트 아티큘레이션이 표시되지 않는
//   문제가 확인됐다(Pattern Editor는 같은 로직을 단일 파일로 써서 정상
//   동작했음 — 즉 문제는 로직이 아니라 별도 .js 파일에서의 enum 접근
//   방식이었다). 그래서 engine/*.js에서 MuseScore enum을 직접 참조하는
//   부분을 전부 제거하고, 이 파일(plugin.qml, 보통의 "import MuseScore 3.0"
//   으로 enum에 확실히 접근 가능한 곳)에서 enum 값을 만들어 파라미터로
//   주입하는 방식으로 바꿨다. 다시 테스트해서 뮤트/액센트가 정상적으로
//   보이는지 확인해달라.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord"
    description: "코드(Symbol) 기반 기타 반주 자동 생성"
    version: "0.8.0"
    requiresScore: true
    pluginType: "dialog"
    width: 640
    height: 720

    property string resultText: "먼저 코드가 입력된 마디를 선택한 뒤, 패턴을 고르고 '읽기 + 미리보기'를 눌러주세요."

    property var patternList: []            // combinePatternLists() 결과 (전체)
    property var patternCategories: []       // 카테고리 이름 목록
    property var patternsInCategory: []      // 현재 선택된 카테고리 안의 패턴 목록
    property var patternsInCategoryNames: [] // 콤보박스 표시용
    property var loadedPattern: null         // 현재 선택된 패턴의 실제 내용(JSON)

    property var pendingSelInfo: null
    property var pendingEvents: null
    property int pendingTrack: -1

    FileIO { id: builtinPatternIndexFile }
    FileIO { id: userPatternIndexFile }
    FileIO { id: patternContentFile }
    FileIO { id: builtinVoicingFile }
    FileIO { id: userVoicingFile }

    // ---- 플러그인 자신의 폴더 위치 -> ErayChord/data 경로 계산 ----
    // (6·7단계와 동일한 방식. 단, 이 파일은 ErayChord/ 바로 밑에 있으므로
    //  "../data"가 아니라 "data"를 그대로 쓴다.)
    function urlToLocalFile(url) {
        var s = url.toString();
        if (s.indexOf("file:///") === 0) {
            s = s.substring(8);
            if (/^[A-Za-z]:/.test(s)) return s;
            return "/" + s;
        } else if (s.indexOf("file://") === 0) {
            return s.substring(7);
        }
        return s;
    }

    function baseDir() {
        var dir = urlToLocalFile(Qt.resolvedUrl("."));
        if (dir.charAt(dir.length - 1) === "/") dir = dir.substring(0, dir.length - 1);
        return dir;
    }

    function patternsDir() { return baseDir() + "/data/patterns"; }
    function voicingsDir() { return baseDir() + "/data/voicings"; }

    function readJsonFile(fio, path, fallback) {
        fio.source = path;
        var content = "";
        try { content = fio.read(); } catch (e) {}
        try {
            var parsed = JSON.parse(content);
            if (parsed) return parsed;
        } catch (e2) {}
        return fallback;
    }

    // ---- 패턴 라이브러리 (카테고리 -> 패턴 2단계) ----
    // 8-3단계 통합 메모: 처음에는 "[카테고리] 이름"을 한 줄로 이어붙인
    // 콤보박스 하나만 뒀는데, 패턴 편집기(6단계)처럼 카테고리를 먼저
    // 고르고 그 안에서 패턴을 고르는 2단계 콤보박스로 바꿨다. 패턴을
    // 고르면 아래 미리보기 캔버스에 리듬 그림이 바로 그려진다.
    function refreshPatternList() {
        var builtinIdx = readJsonFile(builtinPatternIndexFile, patternsDir() + "/_builtin_index.json", { patterns: [] });
        var userIdx = readJsonFile(userPatternIndexFile, patternsDir() + "/_index.json", { patterns: [] });
        var combined = PatternEngine.combinePatternLists(builtinIdx, userIdx);
        patternList = combined;

        var cats = [];
        for (var i = 0; i < combined.length; i++) {
            var c = combined[i].category || "미분류";
            if (cats.indexOf(c) === -1) cats.push(c);
        }
        patternCategories = cats;

        updatePatternsInCategory(cats.length > 0 ? cats[0] : null);
    }

    function updatePatternsInCategory(category) {
        if (category === null) {
            patternsInCategory = [];
            patternsInCategoryNames = [];
            loadedPattern = null;
            if (patternPreviewCanvas) patternPreviewCanvas.requestPaint();
            return;
        }
        var list = [];
        for (var i = 0; i < patternList.length; i++) {
            var p = patternList[i];
            var c = p.category || "미분류";
            if (c === category) list.push(p);
        }
        patternsInCategory = list;

        var names = [];
        for (var j = 0; j < list.length; j++) {
            names.push(list[j].name + (list[j].builtin ? "" : " (사용자)"));
        }
        patternsInCategoryNames = names;

        if (list.length > 0) loadPatternFromEntry(list[0]);
        else loadedPattern = null;

        if (patternPreviewCanvas) patternPreviewCanvas.requestPaint();
    }

    function loadPatternFromEntry(entry) {
        var parsed = readJsonFile(patternContentFile, patternsDir() + "/" + entry.file, null);
        if (!parsed) {
            loadedPattern = null;
            resultText = "패턴 파일을 읽지 못했습니다: " + entry.file;
            if (patternPreviewCanvas) patternPreviewCanvas.requestPaint();
            return;
        }
        parsed.events = PatternEngine.normalizeEvents(parsed.events, 1);
        loadedPattern = parsed;
        if (patternPreviewCanvas) patternPreviewCanvas.requestPaint();
    }

    // ---- 운지 라이브러리 ----
    function loadMergedVoicingLibrary() {
        var builtinLib = readJsonFile(builtinVoicingFile, voicingsDir() + "/open_chords.json", {});
        var userLib = readJsonFile(userVoicingFile, voicingsDir() + "/user_voicings.json", {});
        return VoicingEngine.mergeLibraries(builtinLib, userLib);
    }

    onRun: {
        try {
            refreshPatternList();
        } catch (err) {
            resultText = "라이브러리를 불러오는 중 오류: " + err;
        }
    }

    // ---- 읽기 + 미리보기 ----
    function readAndPreview() {
        if (!loadedPattern) return "먼저 패턴을 선택하세요.";

        var selInfo = SelectionReader.readSelection(curScore, Cursor.SELECTION_START, Cursor.SELECTION_END);
        if (!selInfo) return "선택된 영역이 없습니다. 코드가 붙은 마디를 선택한 뒤 다시 시도하세요.";

        var rawChords = ChordReader.readChords(curScore, selInfo, Cursor.SELECTION_START);
        if (rawChords.length === 0) {
            return "선택 범위(Track " + selInfo.track + ")에서 코드 기호를 찾지 못했습니다.\n" +
                   "코드(Symbol)가 붙어 있는 마디를 선택했는지 확인하세요.";
        }

        var mergedLib = loadMergedVoicingLibrary();
        var voicingPref = voicingNameField.text.trim();
        if (voicingPref.length === 0) voicingPref = null;

        var chordEvents = [];
        for (var i = 0; i < rawChords.length; i++) {
            var c = rawChords[i];
            chordEvents.push({
                tick: c.tick,
                chord: c.chord,
                pitches: VoicingEngine.getVoicingPitches(mergedLib, c.chord, voicingPref)
            });
        }

        var events = NoteGenerator.generateEvents(selInfo, loadedPattern, chordEvents, 480);

        pendingSelInfo = selInfo;
        pendingEvents = events;
        pendingTrack = selInfo.track;

        var lines = [];
        lines.push("=== ErayChord: 미리보기 ===");
        lines.push("패턴: " + loadedPattern.name + " / 운지 우선순위: " + (voicingPref || "(기본)"));
        lines.push("마디 " + selInfo.startMeasureNo + " ~ " + selInfo.endMeasureNo + " / Track " + selInfo.track);
        lines.push("코드 진행: " + rawChords.map(function (c) { return c.chord; }).join(" - "));
        lines.push("생성된 이벤트: " + events.length + "개");
        lines.push("");
        for (var j = 0; j < events.length; j++) {
            var ev = events[j];
            var noteStr = "(쉼표/뮤트)";
            if (ev.pitches) noteStr = ev.pitches.join(" ");
            lines.push("tick " + ev.tick + " (" + ev.type + (ev.accent ? ", accent" : "") +
                        ", 코드=" + (ev.chordName || "-") + ") -> " + noteStr);
        }
        lines.push("");
        lines.push("문제 없어 보이면 '악보에 쓰기'를 누르세요.");
        return lines.join("\n");
    }

    // ---- 악보에 쓰기 ----
    function writeToScore() {
        if (!pendingEvents || pendingEvents.length === 0) {
            return "쓸 내용이 없습니다. 먼저 '읽기 + 미리보기'를 눌러주세요.";
        }

        var msEnums = {
            cursorSelStart: Cursor.SELECTION_START,
            elementArticulation: Element.ARTICULATION,
            symIdAccent: SymId.articAccentAbove,
            noteHeadGroupCross: NoteHeadGroup.HEAD_CROSS,
            newElementFn: newElement
        };

        var result = Writer.writeEvents(curScore, pendingTrack, pendingEvents, 480, msEnums);

        var lines = [];
        lines.push("=== ErayChord: 악보에 쓰기 완료 ===");
        lines.push("");
        lines.push("입력된 이벤트: " + result.writtenCount + " / " + result.totalCount);
        lines.push("액센트 적용: " + result.accentCount + "개");
        if (result.skipped.length > 0) {
            lines.push("");
            lines.push("건너뛴 항목:");
            for (var i = 0; i < result.skipped.length; i++) lines.push("  - " + result.skipped[i]);
        }
        if (result.muteFailed && result.muteFailed.length > 0) {
            lines.push("");
            lines.push("뮤트(X머리) 적용 실패:");
            for (var m = 0; m < result.muteFailed.length; m++) lines.push("  - " + result.muteFailed[m]);
        }
        if (result.accentFailed.length > 0) {
            lines.push("");
            lines.push("액센트 적용 실패:");
            for (var j = 0; j < result.accentFailed.length; j++) lines.push("  - " + result.accentFailed[j]);
        }
        lines.push("");
        lines.push("악보를 확인하세요. 마음에 안 들면 Ctrl+Z로 한 번에 되돌릴 수 있습니다.");
        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord — Guitar Accompaniment Generator"
            font.bold: true
            font.pixelSize: 16
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "카테고리" }
            ComboBox {
                id: categoryCombo
                Layout.preferredWidth: 140
                model: patternCategories
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < patternCategories.length) {
                        try { updatePatternsInCategory(patternCategories[currentIndex]); }
                        catch (err) { resultText = "카테고리 로딩 오류: " + err; }
                    }
                }
            }

            Label { text: "패턴(주법)" }
            ComboBox {
                id: patternCombo
                Layout.fillWidth: true
                model: patternsInCategoryNames
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < patternsInCategory.length) {
                        try { loadPatternFromEntry(patternsInCategory[currentIndex]); }
                        catch (err) { resultText = "패턴 로딩 오류: " + err; }
                    }
                }
            }
        }

        Label {
            text: "미리보기 (위 = 코드, 아래 = 베이스, X = 뮤트, 주황 = 액센트)"
            font.pixelSize: 11
            color: "#666"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            color: "#ffffff"
            border.color: "#ddd"

            Canvas {
                id: patternPreviewCanvas
                anchors.fill: parent
                anchors.margins: 1

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    if (!loadedPattern || !loadedPattern.events || loadedPattern.events.length === 0) {
                        ctx.fillStyle = "#999";
                        ctx.font = "12px sans-serif";
                        ctx.fillText("미리보기 없음 (패턴을 선택하세요)", 10, height / 2);
                        return;
                    }

                    var totalBeats = (loadedPattern.length || 1) * 4; // 엔진의 4/4 고정 가정과 동일
                    var marginX = 8;
                    var usableWidth = width - marginX * 2;
                    var midY = height / 2;

                    ctx.strokeStyle = "#ccc";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(marginX, midY);
                    ctx.lineTo(width - marginX, midY);
                    ctx.stroke();

                    ctx.fillStyle = "#aaa";
                    ctx.font = "9px sans-serif";
                    for (var b = 1; b <= totalBeats + 1; b++) {
                        var bx = marginX + ((b - 1) / totalBeats) * usableWidth;
                        ctx.beginPath();
                        ctx.moveTo(bx, midY - 4);
                        ctx.lineTo(bx, midY + 4);
                        ctx.stroke();
                        if (b <= totalBeats) ctx.fillText(String(b), bx - 2, height - 3);
                    }

                    var events = loadedPattern.events;
                    for (var i = 0; i < events.length; i++) {
                        var ev = events[i];
                        var x = marginX + ((ev.beat - 1) / totalBeats) * usableWidth;
                        var dur = ev.durationBeats || 1;
                        var w = Math.max(3, (dur / totalBeats) * usableWidth - 2);

                        if (ev.type === "chord") {
                            ctx.fillStyle = ev.accent ? "#e08a2e" : "#4488aa";
                            ctx.fillRect(x, midY - 28, w, 26);
                        } else if (ev.type === "bass") {
                            ctx.fillStyle = ev.accent ? "#e08a2e" : "#666666";
                            ctx.fillRect(x, midY + 2, w, 26);
                        } else if (ev.type === "mute") {
                            ctx.strokeStyle = "#aa3333";
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            ctx.moveTo(x, midY - 7);
                            ctx.lineTo(x + w, midY + 7);
                            ctx.moveTo(x + w, midY - 7);
                            ctx.lineTo(x, midY + 7);
                            ctx.stroke();
                        }
                        // rest는 그리지 않는다(빈 칸으로 표시).
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "운지 이름 우선순위" }
            TextField {
                id: voicingNameField
                Layout.fillWidth: true
                placeholderText: "비워두면 기본(default) 운지 사용. 예: 오픈, 바레(E폼), 바레(A폼)"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "읽기 + 미리보기"
                onClicked: {
                    try { resultText = readAndPreview(); }
                    catch (err) { resultText = "!!! 오류 !!!\n\n" + err; }
                }
            }

            Button {
                text: "악보에 쓰기"
                onClicked: {
                    try { resultText = writeToScore(); }
                    catch (err) { resultText = "!!! 쓰기 중 오류 !!!\n\n" + err; }
                }
            }

            Button {
                text: "라이브러리 새로고침"
                onClicked: {
                    try {
                        refreshPatternList();
                        resultText = "라이브러리를 다시 불러왔습니다.\n(Pattern Editor / Voicing Editor에서 저장한 내용이 반영됩니다.)";
                    } catch (err) { resultText = "!!! 오류 !!!\n\n" + err; }
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                id: resultArea
                readOnly: true
                wrapMode: TextArea.Wrap
                selectByMouse: true
                text: resultText
                font.family: "monospace"
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: 11
            color: "#666"
            text: "패턴을 더 만들려면 'Plugins > ErayChord > Pattern Editor'를, " +
                  "운지를 추가/수정하려면 'Plugins > ErayChord > Voicing Editor'를 실행하세요. " +
                  "저장 후 여기서 '라이브러리 새로고침'을 누르면 바로 목록에 나타납니다."
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Button {
                text: "전체 복사"
                onClicked: {
                    resultArea.selectAll();
                    resultArea.copy();
                    resultArea.deselect();
                }
            }

            Button {
                text: "닫기"
                onClicked: (typeof(quit) === "undefined" ? Qt.quit : quit)()
            }
        }
    }
}
