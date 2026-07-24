import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0
import FileIO 3.0

// ============================================================
// 8단계 통합 메모: 이 파일은 stage7/Stage7_VoicingEditor.qml을
// 그대로 복사해 menuPath/description만 정식 배치용으로 바꾼 것이다.
// 로직은 변경하지 않았다(이미 사용자가 직접 테스트해 검증된 상태).
// stage7/ 쪽 원본은 개발 이력 보존을 위해 그대로 남겨둔다.
// ============================================================

// ============================================================
// 7단계 — Voicing Editor (운지 편집기, 마지막 단계)
//
// 기획서 5절 원칙:
//   사용자가 코드별 운지를 직접 수정할 수 있다. 하나의 코드에 여러
//   운지(Open, Barre, Jazz 등)를 저장할 수 있으며, 기본 운지를
//   지정할 수 있다.
//
// 6단계(패턴 편집기)와의 차이:
//   패턴은 "악보에서 실제로 연주된 리듬을 읽어서" 저장했지만, 운지는
//   악보에서 자동으로 역추적할 수 없다(같은 음이라도 여러 프렛
//   조합이 가능하므로). 그래서 이번엔 프렛 번호를 사용자가 직접
//   입력하는 방식이다.
//
// 사용법:
//   1) 코드 이름(예: C, Am, G7), 운지 이름(예: Open, Barre, Jazz)을
//      입력하고, 6개 현의 프렛 번호를 낮은 E현부터 높은 e현 순서로
//      공백으로 구분해 입력한다 (뮤트는 -1, 개방현은 0).
//      예) -1 3 2 0 1 0  ->  C 코드의 표준 Open 운지
//   2) "미리보기"를 누르면 프렛보드 그림과 실제 음(피치)이 표시된다.
//   3) "저장"을 누르면 ErayChord/data/voicings/user_voicings.json에
//      저장된다. 같은 코드에 여러 운지를 저장할 수 있다.
//   4) "기본 운지로 저장" 체크박스를 켜면, 그 코드의 다른 운지들의
//      기본 지정은 자동으로 해제되고 이번 것만 기본이 된다.
//   5) 코드/운지 드롭다운에서 골라 "불러오기"로 다시 불러와 수정하거나
//      "삭제"할 수 있다.
//
// 지금까지 검증된 것을 재사용한다:
//   - Qt.resolvedUrl(".")로 플러그인 자신의 폴더 위치를 알아내
//     data/voicings 폴더 경로를 계산한다 (6단계와 동일한 방식).
//   - Canvas 크기 확정 타이밍 버그 대응: 명시적 width를 가진 Column +
//     Qt.callLater 워밍업 (6단계에서 확인된 해법).
//   - MU4에서는 Qt.quit() 대신 quit()을 쓴다.
//   - 프로퍼티 이름은 ALL_CAPS를 피한다.
//
// 한계 (알고 하는 단순화):
//   - 표준 튜닝(E2-A2-D3-G3-B3-E4) 고정.
//   - 여기서 저장한 운지 라이브러리는 4~5단계의 내장 운지 라이브러리와
//     아직 자동으로 연결되어 있지 않다 (수동으로 data/voicings/
//     파일을 참고해서 4단계 코드에 반영하거나, 추후 통합 작업 필요).
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Voicing Editor"
    description: "ErayChord 운지 편집기 — 코드별 운지를 직접 입력/저장/불러오기합니다."
    version: "0.1"
    requiresScore: false
    pluginType: "dialog"
    width: 620
    height: 720

    property string resultText: "코드 이름, 운지 이름, 프렛 번호를 입력하고 '미리보기'를 눌러주세요."
    property var currentFrets: [-1, -1, -1, -1, -1, -1]
    property bool currentValid: false

    property var libraryChordNames: []
    property var voicingsForChord: []      // [{name, frets, default}, ...]
    property var voicingsForChordNames: []

    FileIO {
        id: voicingFile
        onError: function (msg) { resultText = "FileIO 오류: " + msg; }
    }

    // ---- 플러그인 자신의 폴더 위치 -> ErayChord/data/voicings 계산 (6단계와 동일 방식) ----
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

    function voicingsDir() {
        var dir = urlToLocalFile(Qt.resolvedUrl("."));
        if (dir.charAt(dir.length - 1) === "/") dir = dir.substring(0, dir.length - 1);
        return dir + "/../data/voicings";
    }

    function voicingsFilePath() {
        return voicingsDir() + "/user_voicings.json";
    }

    function readVoicingsLibrary() {
        voicingFile.source = voicingsFilePath();
        var content = "";
        try { content = voicingFile.read(); } catch (e) {}
        var lib = {};
        try {
            var parsed = JSON.parse(content);
            if (parsed && typeof parsed === "object") lib = parsed;
        } catch (e2) {}
        return lib;
    }

    function writeVoicingsLibrary(lib) {
        voicingFile.source = voicingsFilePath();
        return voicingFile.write(JSON.stringify(lib, null, 2));
    }

    function refreshChordNames() {
        var lib = readVoicingsLibrary();
        var names = Object.keys(lib);
        names.sort();
        libraryChordNames = names;
        if (names.length > 0) refreshVoicingsForChord(names[0]);
        else { voicingsForChord = []; voicingsForChordNames = []; }
    }

    function refreshVoicingsForChord(chordName) {
        var lib = readVoicingsLibrary();
        var list = lib[chordName] ? lib[chordName].slice() : [];
        voicingsForChord = list;
        var names = [];
        for (var i = 0; i < list.length; i++) {
            names.push(list[i].name + (list[i].default ? " (기본)" : ""));
        }
        voicingsForChordNames = names;
    }

    onRun: {
        try {
            refreshChordNames();
        } catch (err) {
            resultText = "운지 목록을 불러오는 중 오류: " + err;
        }
    }

    // ---- 프렛 텍스트 파싱 ("-1 3 2 0 1 0" -> [-1,3,2,0,1,0]) ----
    function parseFrets(text) {
        if (!text) return null;
        var parts = text.trim().split(/\s+/);
        if (parts.length !== 6) return null;
        var frets = [];
        for (var i = 0; i < 6; i++) {
            var n = parseInt(parts[i], 10);
            if (isNaN(n) || n < -1 || n > 24) return null;
            frets.push(n);
        }
        return frets;
    }

    function openStringPitches() {
        return [40, 45, 50, 55, 59, 64]; // E2 A2 D3 G3 B3 E4
    }

    function fretsToPitches(frets) {
        var strings = openStringPitches();
        var pitches = [];
        for (var i = 0; i < frets.length; i++) {
            if (frets[i] === -1) continue;
            pitches.push(strings[i] + frets[i]);
        }
        return pitches;
    }

    function pitchToName(p) {
        var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        var octave = Math.floor(p / 12) - 1;
        return names[((p % 12) + 12) % 12] + octave;
    }

    // ---- 미리보기 ----
    function previewVoicing(fretsText) {
        var frets = parseFrets(fretsText);
        if (!frets) {
            currentValid = false;
            return "프렛 번호를 낮은 E현부터 순서대로 6개, 공백으로 구분해서 입력하세요.\n예: -1 3 2 0 1 0  (뮤트=-1, 개방현=0)";
        }
        currentFrets = frets;
        currentValid = true;
        canvasFretboard.requestPaint();

        var pitches = fretsToPitches(frets);
        var names = [];
        for (var i = 0; i < pitches.length; i++) names.push(pitchToName(pitches[i]));

        var lines = [];
        lines.push("=== ErayChord 7단계: 운지 미리보기 ===");
        lines.push("프렛(낮은 E → 높은 e): " + frets.join(" "));
        lines.push("실제 음: " + names.join(" "));
        lines.push("");
        lines.push("문제 없어 보이면 '저장'을 누르세요.");
        return lines.join("\n");
    }

    // ---- 저장 (같은 코드+운지 이름이면 덮어쓰기, 기본 지정 처리) ----
    function saveVoicing(chordName, voicingName, fretsText, isDefault) {
        var frets = parseFrets(fretsText);
        if (!frets) {
            return "프렛 번호가 올바르지 않습니다. 낮은 E현부터 6개, 공백으로 구분해서 입력하세요.";
        }
        var chord = (chordName && chordName.length > 0) ? chordName : null;
        var vname = (voicingName && voicingName.length > 0) ? voicingName : null;
        if (!chord || !vname) {
            return "코드 이름과 운지 이름을 모두 입력해야 합니다.";
        }

        var lib = readVoicingsLibrary();
        if (!lib[chord]) lib[chord] = [];

        var existingIdx = -1;
        for (var i = 0; i < lib[chord].length; i++) {
            if (lib[chord][i].name === vname) { existingIdx = i; break; }
        }

        if (isDefault) {
            for (var j = 0; j < lib[chord].length; j++) lib[chord][j].default = false;
        }

        var entry = { name: vname, frets: frets, default: !!isDefault };
        if (existingIdx >= 0) lib[chord][existingIdx] = entry;
        else lib[chord].push(entry);

        var ok = writeVoicingsLibrary(lib);
        refreshChordNames();
        refreshVoicingsForChord(chord);

        var lines = [];
        lines.push("=== ErayChord 7단계: 저장 완료 ===");
        lines.push("");
        lines.push("저장 결과: " + ok);
        lines.push("코드: " + chord + " / 운지: " + vname + (isDefault ? " (기본 운지로 지정됨)" : ""));
        lines.push("경로: " + voicingsFilePath());
        return lines.join("\n");
    }

    function loadVoicingIntoFields(chordName, voicingName) {
        var lib = readVoicingsLibrary();
        var list = lib[chordName] || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === voicingName) {
                fretsField.text = list[i].frets.join(" ");
                defaultCheck.checked = !!list[i].default;
                resultText = previewVoicing(fretsField.text);
                return "불러오기 완료: " + chordName + " / " + voicingName;
            }
        }
        return "해당 운지를 찾지 못했습니다.";
    }

    function deleteVoicing(chordName, voicingName) {
        var lib = readVoicingsLibrary();
        if (!lib[chordName]) return "해당 코드가 없습니다.";
        var list = lib[chordName];
        var newList = [];
        var removed = false;
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === voicingName) { removed = true; continue; }
            newList.push(list[i]);
        }
        if (!removed) return "해당 운지를 찾지 못했습니다.";

        if (newList.length === 0) delete lib[chordName];
        else lib[chordName] = newList;

        var ok = writeVoicingsLibrary(lib);
        refreshChordNames();

        return "삭제 완료: " + chordName + " / " + voicingName + " (저장 결과: " + ok + ")";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord — 7단계 Voicing Editor"
            font.bold: true
            font.pixelSize: 16
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "코드 이름" }
            TextField {
                id: chordNameField
                Layout.preferredWidth: 100
                placeholderText: "예: C"
                text: "C"
            }

            Label { text: "운지 이름" }
            TextField {
                id: voicingNameField
                Layout.preferredWidth: 100
                placeholderText: "예: Open"
                text: "Open"
            }

            CheckBox {
                id: defaultCheck
                text: "기본 운지로 저장"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "프렛(낮은E→높은e)" }
            TextField {
                id: fretsField
                Layout.fillWidth: true
                placeholderText: "예: -1 3 2 0 1 0  (뮤트=-1, 개방현=0)"
                text: "-1 3 2 0 1 0"
            }

            Button {
                text: "미리보기"
                onClicked: {
                    try {
                        resultText = previewVoicing(fretsField.text);
                    } catch (err) {
                        resultText = "!!! 오류 !!!\n\n" + err;
                    }
                }
            }

            Button {
                text: "저장"
                onClicked: {
                    try {
                        resultText = saveVoicing(chordNameField.text, voicingNameField.text, fretsField.text, defaultCheck.checked);
                    } catch (err) {
                        resultText = "!!! 저장 중 오류 !!!\n\n" + err;
                    }
                }
            }
        }

        Label { text: "프렛보드 미리보기" }

        Column {
            width: 260
            height: 170

            Canvas {
                id: canvasFretboard
                width: 260
                height: 170

                onWidthChanged: requestPaint()
                Component.onCompleted: Qt.callLater(function () { requestPaint(); })

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);

                    var stringsCount = 6;
                    var fretsToShow = 4;
                    var marginLeft = 24;
                    var marginTop = 26;
                    var stringSpacing = (width - marginLeft * 2) / (stringsCount - 1);
                    var fretSpacing = (height - marginTop - 16) / fretsToShow;

                    // 세로선(현)
                    ctx.strokeStyle = "#555";
                    ctx.lineWidth = 1;
                    for (var s = 0; s < stringsCount; s++) {
                        var x = marginLeft + s * stringSpacing;
                        ctx.beginPath();
                        ctx.moveTo(x, marginTop);
                        ctx.lineTo(x, marginTop + fretSpacing * fretsToShow);
                        ctx.stroke();
                    }
                    // 가로선(프렛) - 첫 줄(너트)은 굵게
                    for (var f = 0; f <= fretsToShow; f++) {
                        var y = marginTop + f * fretSpacing;
                        ctx.lineWidth = (f === 0) ? 3 : 1;
                        ctx.beginPath();
                        ctx.moveTo(marginLeft, y);
                        ctx.lineTo(marginLeft + stringSpacing * (stringsCount - 1), y);
                        ctx.stroke();
                    }

                    if (!currentValid) return;

                    for (var i = 0; i < currentFrets.length; i++) {
                        var fret = currentFrets[i];
                        var sx = marginLeft + i * stringSpacing;

                        if (fret === -1) {
                            ctx.strokeStyle = "#aa2222";
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            ctx.moveTo(sx - 5, marginTop - 15);
                            ctx.lineTo(sx + 5, marginTop - 5);
                            ctx.moveTo(sx + 5, marginTop - 15);
                            ctx.lineTo(sx - 5, marginTop - 5);
                            ctx.stroke();
                        } else if (fret === 0) {
                            ctx.strokeStyle = "#2255aa";
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            ctx.arc(sx, marginTop - 10, 5, 0, Math.PI * 2);
                            ctx.stroke();
                        } else if (fret <= fretsToShow) {
                            var fy = marginTop + (fret - 1) * fretSpacing + fretSpacing / 2;
                            ctx.fillStyle = "#333333";
                            ctx.beginPath();
                            ctx.arc(sx, fy, 6, 0, Math.PI * 2);
                            ctx.fill();
                        } else {
                            // 4프렛보다 위쪽이면 숫자로 표시
                            ctx.fillStyle = "#333333";
                            ctx.font = "10px sans-serif";
                            ctx.fillText(String(fret), sx - 4, marginTop + fretSpacing * fretsToShow + 12);
                        }
                    }
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

        Label { text: "저장된 운지 불러오기 / 삭제" }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "코드" }
            ComboBox {
                id: chordCombo
                Layout.preferredWidth: 100
                model: libraryChordNames
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < libraryChordNames.length) {
                        refreshVoicingsForChord(libraryChordNames[currentIndex]);
                    }
                }
            }

            Label { text: "운지" }
            ComboBox {
                id: voicingCombo
                Layout.fillWidth: true
                model: voicingsForChordNames
            }

            Button {
                text: "불러오기"
                enabled: voicingsForChord.length > 0
                onClicked: {
                    try {
                        var idx = voicingCombo.currentIndex;
                        if (idx >= 0 && idx < voicingsForChord.length) {
                            chordNameField.text = libraryChordNames[chordCombo.currentIndex];
                            voicingNameField.text = voicingsForChord[idx].name;
                            resultText = loadVoicingIntoFields(chordNameField.text, voicingNameField.text);
                        }
                    } catch (err) {
                        resultText = "!!! 불러오기 오류 !!!\n\n" + err;
                    }
                }
            }

            Button {
                text: "삭제"
                enabled: voicingsForChord.length > 0
                onClicked: {
                    try {
                        var idx2 = voicingCombo.currentIndex;
                        if (idx2 >= 0 && idx2 < voicingsForChord.length) {
                            var cName = libraryChordNames[chordCombo.currentIndex];
                            var vName = voicingsForChord[idx2].name;
                            resultText = deleteVoicing(cName, vName);
                        }
                    } catch (err) {
                        resultText = "!!! 삭제 중 오류 !!!\n\n" + err;
                    }
                }
            }

            Button {
                text: "목록 새로고침"
                onClicked: {
                    try { refreshChordNames(); } catch (err) { resultText = "!!! 오류 !!!\n\n" + err; }
                }
            }
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
