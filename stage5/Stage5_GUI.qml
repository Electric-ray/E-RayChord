import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// 5단계 — GUI (패턴/운지 선택 드롭다운)
//
// 개발순서.txt 5단계: "이때서야 예쁜 UI를 만든다."
// 지금까지는 패턴이 GoGo 하나로 코드에 박혀 있었다. 5단계에서는
// 패턴을 여러 개(GoGo, Ballad) 중에서 드롭다운으로 고를 수 있게 하고,
// 운지 라이브러리도 같은 방식으로 구조를 잡는다 (지금은 Open 하나뿐).
//
// UI 구성: Pattern ▼ / Voicing ▼ / 미리보기 생성 버튼 / 악보에 쓰기 버튼
//
// 지금까지 실제 악보 테스트로 검증된 것을 그대로 재사용한다:
//   - 코드(Harmony)는 트랙으로 필터링해서 읽는다 (segment.next 순회).
//   - 마디 n의 시작 tick = (n-1) * 1920  (4/4, 4분음표=480 고정 가정)
//   - 임의의 tick에 정확히 도달 못 하면 표준 길이 쉼표로 gap을 채운다.
//   - addNote(pitch, true)로 화음을 쌓을 때 음 하나 넣을 때마다 같은
//     tick으로 rewindToTick 한다.
//   - MU4에서는 Qt.quit() 대신 quit()을 쓴다.
//   - 프로퍼티 이름은 ALL_CAPS를 피한다 (이름 충돌로 창이 안 뜬 적 있음).
//   - 복잡한 중첩 객체는 property 기본값이 아니라 함수로 반환한다.
//
// 한계 (다음 단계에서 개선 예정):
//   - 4/4 박자만 가정한다.
//   - 패턴은 GoGo/Ballad 2개, 운지는 Open 1개만 내장 (실제 파일
//     로딩 및 사용자 정의 추가는 6~7단계 편집기에서 다룸).
//
// v0.2 수정: 패턴 슬롯 길이(예: Ballad의 온음표 한 칸)보다 실제 코드
// 진행이 더 빨리 바뀌면, 그 슬롯을 코드 변경 지점 기준으로 쪼개서
// 코드가 무시되지 않게 했다 (splitByChordChanges).
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Stage5_GUI"
    description: "5단계: 패턴/운지를 드롭다운으로 선택해 반주를 생성합니다."
    version: "0.2"
    requiresScore: true
    pluginType: "dialog"
    width: 620
    height: 520

    property string resultText: "실행 대기 중..."
    property var patternEvents: []
    property int targetTrack: -1
    property bool applied: false
    property var patternNames: []
    property var voicingNames: []

    // MuseScore 고정 tick 해상도: 4분음표 = 480 tick.
    property int quarterTicks: 480

    // ---- 내장 패턴 라이브러리 (data/patterns/*.json과 동일 형식) ----
    // 복잡한 중첩 객체를 property 기본값으로 바로 선언하면 QML 파싱
    // 모호성으로 창 전체가 비어버리는 문제가 있어, 함수로 반환한다.
    function getPatternLibrary() {
        return {
            "GoGo Basic": {
                name: "GoGo Basic",
                timeSignature: "4/4",
                length: 1,
                events: [
                    { beat: 1, type: "bass" },
                    { beat: 2, type: "chord" },
                    { beat: 3, type: "bass" },
                    { beat: 4, type: "chord" }
                ]
            },
            "Ballad Simple": {
                name: "Ballad Simple",
                timeSignature: "4/4",
                length: 1,
                events: [
                    { beat: 1, type: "chord" }
                ]
            }
        };
    }

    // 지금은 운지 라이브러리가 하나뿐이지만, 5단계 UI 구조를 미리
    // 드롭다운 형태로 잡아둔다 (6~7단계에서 여러 개로 확장 예정).
    function getVoicingLibraryNames() {
        return ["Open Chords"];
    }

    onRun: {
        try {
            patternNames = Object.keys(getPatternLibrary());
            voicingNames = getVoicingLibraryNames();
            resultText = buildPreview(patternNames[0]);
        } catch (err) {
            var msg = "!!! 실행 중 오류 발생 !!!\n\n";
            try { msg += "message: " + err.message + "\n"; } catch (e1) {}
            try { msg += "전체: " + err + "\n"; } catch (e2) {}
            try { msg += "stack: " + err.stack + "\n"; } catch (e3) {}
            resultText = msg;
        }
    }

    // ---- 코드 이름 -> triad pitch 배열 (2단계와 동일 로직) ----
    function parseChordRoot(name) {
        var m = name.match(/^([A-G])([#b]?)/);
        if (!m) return null;
        var letterToPc = { C:0, D:2, E:4, F:5, G:7, A:9, B:11 };
        var pc = letterToPc[m[1]];
        if (m[2] === "#") pc += 1;
        if (m[2] === "b") pc -= 1;
        pc = ((pc % 12) + 12) % 12;
        var rest = name.substring(m[0].length);
        var isMinor = (rest.indexOf("m") === 0 && rest.indexOf("maj") !== 0);
        return { pc: pc, isMinor: isMinor };
    }

    function triadPitches(chordName) {
        var parsed = parseChordRoot(chordName);
        if (!parsed) return null;
        var baseOctaveRoot = 48; // C3 근처, 라이브러리에 없는 코드의 대체(fallback)용
        var root = baseOctaveRoot + parsed.pc;
        var third = root + (parsed.isMinor ? 3 : 4);
        var fifth = root + 7;
        return [root, third, fifth];
    }

    // ---- 운지 라이브러리 (data/voicings/open_chords.json과 동일 형식) ----
    // 3단계의 getPattern()과 같은 이유로, 실제 파일 로딩 대신 함수로
    // 내장해둔다 (복잡한 중첩 리터럴을 property 기본값으로 쓰면 창이
    // 안 뜨는 문제가 있었음).
    function getVoicingLibrary() {
        return {
            "C":  { frets: [-1, 3, 2, 0, 1, 0] },
            "G":  { frets: [3, 2, 0, 0, 0, 3] },
            "Am": { frets: [-1, 0, 2, 2, 1, 0] },
            "F":  { frets: [1, 3, 3, 2, 1, 1] },
            "Dm": { frets: [-1, -1, 0, 2, 3, 1] },
            "G7": { frets: [3, 2, 0, 0, 0, 1] },
            "Em": { frets: [0, 2, 2, 0, 0, 0] }
        };
    }

    // 표준 튜닝 개방현 pitch (낮은 E부터): E2 A2 D3 G3 B3 E4
    function openStringPitches() {
        return [40, 45, 50, 55, 59, 64];
    }

    function voicingToPitches(voicing) {
        var strings = openStringPitches();
        var pitches = [];
        for (var i = 0; i < voicing.frets.length; i++) {
            var fret = voicing.frets[i];
            if (fret === -1) continue; // 뮤트된 현
            pitches.push(strings[i] + fret);
        }
        return pitches;
    }

    // 코드 이름 -> 실제 기타 운지 pitch 배열. 라이브러리에 없는 코드는
    // triad(근음+3도+5도)로 대체한다.
    function getVoicing(chordName) {
        var lib = getVoicingLibrary();
        if (lib[chordName]) {
            return voicingToPitches(lib[chordName]);
        }
        return triadPitches(chordName);
    }

    function pitchToName(p) {
        var names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
        var octave = Math.floor(p / 12) - 1;
        return names[((p % 12) + 12) % 12] + octave;
    }

    // ---- 선택 범위에서 코드(Harmony) 읽기 (트랙 필터 포함, 검증된 로직) ----
    function readChordEvents() {
        if (typeof curScore === 'undefined' || curScore === null) return null;

        var startCursor = curScore.newCursor();
        startCursor.rewind(Cursor.SELECTION_START);
        if (!startCursor.segment) return null;

        var track = startCursor.track;
        var startTick = startCursor.segment.tick;
        var startMeasureNo = startCursor.measure.no + 1;

        var endCursor = curScore.newCursor();
        endCursor.rewind(Cursor.SELECTION_END);
        var endTick, endMeasureNo;
        if (endCursor.segment) {
            endTick = endCursor.segment.tick;
            endMeasureNo = endCursor.measure.no + 1;
        } else {
            endTick = Number.MAX_VALUE;
            endMeasureNo = curScore.nmeasures;
        }
        // 선택 범위 끝은 "마지막으로 포함된 위치"이므로, 그 마디의 끝까지
        // 포함시키기 위해 마디 하나만큼 여유를 둔다 (다음 마디 시작 전까지).
        var inclusiveEndTick = endMeasureNo * 1920;

        var events = [];
        var segment = startCursor.segment;
        while (segment && segment.tick < inclusiveEndTick) {
            var annotations = segment.annotations;
            if (annotations) {
                for (var i = 0; i < annotations.length; i++) {
                    var ann = annotations[i];
                    var annName = "?";
                    try { annName = ann.name; } catch (e) {}
                    var annTrack = -1;
                    try { annTrack = ann.track; } catch (e2) {}

                    if (annName === "Harmony" && annTrack === track) {
                        events.push({ tick: segment.tick, chordName: ann.text, pitches: getVoicing(ann.text) });
                    }
                }
            }
            segment = segment.next;
        }

        targetTrack = track;
        return {
            track: track,
            startTick: startTick,
            endTick: inclusiveEndTick,
            startMeasureNo: startMeasureNo,
            endMeasureNo: endMeasureNo,
            chordEvents: events
        };
    }

    function findActiveChord(tick, chordEvents) {
        var active = null;
        for (var i = 0; i < chordEvents.length; i++) {
            if (chordEvents[i].tick <= tick) active = chordEvents[i];
            else break;
        }
        return active;
    }

    // 주어진 [tick, tick+duration) 구간을, 그 사이에 코드가 바뀌는
    // 지점이 있으면 그 지점 기준으로 쪼갠다. (패턴 슬롯 길이는 "최대
    // 길이"일 뿐, 그 안에서 실제로 코드가 바뀌면 그 지점에서 잘라야
    // 그 코드가 무시되지 않는다)
    function splitByChordChanges(tick, duration, chordEvents) {
        var endTick = tick + duration;
        var boundaries = [tick];
        for (var i = 0; i < chordEvents.length; i++) {
            var ct = chordEvents[i].tick;
            if (ct > tick && ct < endTick) boundaries.push(ct);
        }
        boundaries.push(endTick);
        boundaries.sort(function (a, b) { return a - b; });

        var chunks = [];
        for (var j = 0; j < boundaries.length - 1; j++) {
            var segStart = boundaries[j];
            var segEnd = boundaries[j + 1];
            if (segEnd > segStart) chunks.push({ tick: segStart, duration: segEnd - segStart });
        }
        return chunks;
    }

    // ---- 패턴 x 코드 진행 -> 실제 이벤트 목록 생성 ----
    function buildPatternEvents(selInfo, patternName) {
        var pattern = getPatternLibrary()[patternName];
        var patternLengthTicks = pattern.length * 1920; // 4/4 가정

        var sortedSlots = pattern.events.slice().sort(function (a, b) { return a.beat - b.beat; });
        var slots = [];
        for (var i = 0; i < sortedSlots.length; i++) {
            var offset = (sortedSlots[i].beat - 1) * quarterTicks;
            var nextOffset = (i + 1 < sortedSlots.length)
                ? (sortedSlots[i + 1].beat - 1) * quarterTicks
                : patternLengthTicks;
            slots.push({ offset: offset, duration: nextOffset - offset, type: sortedSlots[i].type });
        }

        var events = [];
        for (var measureNo = selInfo.startMeasureNo; measureNo <= selInfo.endMeasureNo; measureNo++) {
            var measureStartTick = (measureNo - 1) * 1920;
            for (var s = 0; s < slots.length; s++) {
                var slot = slots[s];
                var tick = measureStartTick + slot.offset;
                if (tick < selInfo.startTick || tick >= selInfo.endTick) continue;

                var duration = slot.duration;
                if (tick + duration > selInfo.endTick) {
                    duration = selInfo.endTick - tick;
                }
                if (duration <= 0) continue;

                var chunks = splitByChordChanges(tick, duration, selInfo.chordEvents);
                for (var c = 0; c < chunks.length; c++) {
                    var chunk = chunks[c];
                    var chord = findActiveChord(chunk.tick, selInfo.chordEvents);
                    var pitches = null;
                    if (chord && chord.pitches && chord.pitches.length > 0) {
                        // 베이스 슬롯: 운지에서 가장 낮은 현(뮤트 제외) 하나만.
                        // (triad 시절엔 근음을 옥타브 낮췄지만, 이제 실제 기타
                        //  운지의 가장 낮은 현이 이미 적절한 베이스 음역이라
                        //  그대로 쓴다)
                        pitches = (slot.type === "bass") ? [chord.pitches[0]] : chord.pitches;
                    }

                    events.push({
                        tick: chunk.tick,
                        duration: chunk.duration,
                        type: slot.type,
                        chordName: chord ? chord.chordName : null,
                        pitches: pitches
                    });
                }
            }
        }
        events.sort(function (a, b) { return a.tick - b.tick; });
        return events;
    }

    // ---- 미리보기 ----
    function buildPreview(patternName) {
        var selInfo = readChordEvents();
        if (selInfo === null) {
            return "선택된 영역이 없거나 열려있는 악보가 없습니다.\n마디를 선택한 뒤 다시 실행하세요.";
        }
        if (selInfo.chordEvents.length === 0) {
            return "선택 범위(Track " + selInfo.track + ")에서 코드 기호를 찾지 못했습니다.";
        }

        var events = buildPatternEvents(selInfo, patternName);
        patternEvents = events;

        var lines = [];
        lines.push("=== ErayChord 5단계: 운지 적용 (패턴=" + patternName + ") 미리보기 (아직 악보에 쓰지 않았습니다) ===");
        lines.push("대상 트랙: " + selInfo.track + " / 코드 " + selInfo.chordEvents.length + "개 / 생성된 이벤트 " + events.length + "개");
        lines.push("");

        for (var i = 0; i < events.length; i++) {
            var ev = events[i];
            var noteStr = "(쉼표)";
            if (ev.pitches) {
                var names = [];
                for (var p = 0; p < ev.pitches.length; p++) names.push(pitchToName(ev.pitches[p]));
                noteStr = names.join(" ");
            }
            lines.push("tick " + ev.tick + " (" + ev.type + ", 코드=" + (ev.chordName || "-") + ") -> " + noteStr);
        }

        lines.push("");

        var lib = getVoicingLibrary();
        var fallbackChords = [];
        for (var c = 0; c < selInfo.chordEvents.length; c++) {
            var cn = selInfo.chordEvents[c].chordName;
            if (!lib[cn] && fallbackChords.indexOf(cn) === -1) fallbackChords.push(cn);
        }
        if (fallbackChords.length > 0) {
            lines.push("(참고: 운지 라이브러리에 없어 triad로 대체된 코드: " + fallbackChords.join(", ") + ")");
            lines.push("");
        }

        lines.push("문제 없어 보이면 아래 '악보에 쓰기' 버튼을 누르세요.");
        return lines.join("\n");
    }

    function restCandidateList() {
        return [
            { num: 1, den: 1,  ticks: quarterTicks * 4 },
            { num: 1, den: 2,  ticks: quarterTicks * 2 },
            { num: 1, den: 4,  ticks: quarterTicks },
            { num: 1, den: 8,  ticks: quarterTicks / 2 },
            { num: 1, den: 16, ticks: quarterTicks / 4 },
            { num: 1, den: 32, ticks: quarterTicks / 8 },
            { num: 1, den: 64, ticks: quarterTicks / 16 }
        ];
    }

    function pickDuration(ticks) {
        var candidates = restCandidateList();
        for (var k = 0; k < candidates.length; k++) {
            if (candidates[k].ticks <= ticks) return candidates[k];
        }
        return candidates[candidates.length - 1];
    }

    function fillGapWithRests(cursor, targetTick) {
        var guard = 0;
        while (cursor.segment && cursor.tick < targetTick && guard < 1000) {
            var gap = targetTick - cursor.tick;
            var chosen = pickDuration(gap);
            cursor.setDuration(chosen.num, chosen.den);
            cursor.addRest();
            guard++;
        }
    }

    // ---- 실제 쓰기 (2단계에서 검증된 next()+되돌리기+쉼표채우기+rewindToTick 로직 재사용) ----
    function applyToScore() {
        if (!patternEvents || patternEvents.length === 0) {
            return "쓸 내용이 없습니다. 먼저 코드가 있는 범위를 선택하고 다시 실행하세요.";
        }

        var writtenCount = 0;
        var skipped = [];


        curScore.startCmd();

        var writeCursor = curScore.newCursor();
        writeCursor.track = targetTrack;
        writeCursor.rewind(Cursor.SELECTION_START);

        for (var i = 0; i < patternEvents.length; i++) {
            var pe = patternEvents[i];

            while (writeCursor.segment && writeCursor.tick < pe.tick) {
                writeCursor.next();
            }
            if (writeCursor.segment && writeCursor.tick > pe.tick) {
                writeCursor.prev();
                if (writeCursor.tick < pe.tick) fillGapWithRests(writeCursor, pe.tick);
            }
            if (!writeCursor.segment || writeCursor.tick !== pe.tick) {
                var reachedTick = writeCursor.segment ? writeCursor.tick : "없음";
                skipped.push("tick " + pe.tick + " (" + pe.type + ", 도달=" + reachedTick + ")");
                continue;
            }

            var durInfo = pickDuration(pe.duration);
            writeCursor.setDuration(durInfo.num, durInfo.den);

            if (!pe.pitches || pe.pitches.length === 0) {
                writeCursor.addRest();
            } else {
                writeCursor.rewindToTick(pe.tick);
                writeCursor.setDuration(durInfo.num, durInfo.den);
                writeCursor.addNote(pe.pitches[0]);
                for (var p = 1; p < pe.pitches.length; p++) {
                    writeCursor.rewindToTick(pe.tick);
                    writeCursor.setDuration(durInfo.num, durInfo.den);
                    writeCursor.addNote(pe.pitches[p], true);
                }
            }
            writtenCount++;
        }

        curScore.endCmd();
        applied = true;

        var lines = [];
        lines.push("=== ErayChord 5단계: 악보에 쓰기 완료 ===");
        lines.push("");
        lines.push("입력된 이벤트 수: " + writtenCount + " / " + patternEvents.length);
        if (skipped.length > 0) {
            lines.push("");
            lines.push("건너뛴 항목:");
            for (var j = 0; j < skipped.length; j++) lines.push("  - " + skipped[j]);
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
            text: "ErayChord — 5단계 GUI (패턴/운지 선택)"
            font.bold: true
            font.pixelSize: 16
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "Pattern" }
            ComboBox {
                id: patternCombo
                model: patternNames
                Layout.preferredWidth: 160
            }

            Label { text: "Voicing" }
            ComboBox {
                id: voicingCombo
                model: voicingNames
                Layout.preferredWidth: 160
            }

            Button {
                text: "미리보기 생성"
                onClicked: {
                    try {
                        applied = false;
                        resultText = buildPreview(patternCombo.currentText);
                    } catch (err) {
                        var msg = "!!! 실행 중 오류 발생 !!!\n\n";
                        try { msg += "message: " + err.message + "\n"; } catch (e1) {}
                        try { msg += "전체: " + err + "\n"; } catch (e2) {}
                        resultText = msg;
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
                text: applied ? "다시 쓰기" : "악보에 쓰기"
                enabled: patternEvents.length > 0
                onClicked: {
                    try {
                        resultText = applyToScore();
                    } catch (err) {
                        var msg = "!!! 쓰기 중 오류 발생 !!!\n\n";
                        try { msg += "message: " + err.message + "\n"; } catch (e1) {}
                        try { msg += "전체: " + err + "\n"; } catch (e2) {}
                        try { msg += "stack: " + err.stack + "\n"; } catch (e3) {}
                        resultText = msg;
                    }
                }
            }

            Button {
                text: "닫기"
                onClicked: (typeof(quit) === "undefined" ? Qt.quit : quit)()
            }
        }
    }
}
