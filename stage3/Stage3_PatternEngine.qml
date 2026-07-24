import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// 3단계 — Pattern Engine (GoGo 패턴으로 코드 진행에 반주 생성)
//
// 개발순서.txt 3단계 원칙:
//   "패턴을 코드에 박아 넣지 않는다."
//   Pattern(리듬: 언제 베이스/언제 코드) 과 Voicing/코드(실제 음)을
//   분리하고, 둘은 이 파일의 생성 로직에서만 만난다.
//
//   패턴은 코드 변경 시점과 무관하게 계속 "반복"된다. 각 패턴 슬롯
//   위치에서 "그 시점에 활성화된 코드가 뭔지"를 찾아 음을 정한다.
//   (2단계 MVP는 "코드당 4분음표 하나"라는 패턴이 코드에 박혀 있던
//    상태였는데, 이번엔 그 패턴을 데이터로 분리했다)
//
// 지금까지 실제 악보 테스트로 검증된 것을 그대로 재사용한다:
//   - 코드(Harmony)는 트랙으로 필터링해서 읽는다 (segment.next 순회).
//   - 마디 n의 시작 tick = (n-1) * 1920  (4/4, 4분음표=480 고정 가정으로
//     이번 곡 데이터에서 실측 확인됨)
//   - 임의의 tick에 정확히 도달 못 하면(그 트랙에 경계가 없으면)
//     표준 길이 쉼표로 gap을 정확히 채워 강제 정렬한다.
//     (setDuration(num, den)은 "온음표 기준 분수" — (1,4)=4분음표.
//      이 계산을 거꾸로 하면 크게 밀려나므로 주의)
//   - addNote(pitch, true)로 화음을 쌓을 때 커서가 벗어나는 버그가
//     있어, 음 하나 넣을 때마다 같은 tick으로 rewindToTick 한다.
//   - MU4에서는 Qt.quit() 대신 quit()을 쓴다.
//
// 한계 (다음 단계에서 개선 예정):
//   - 4/4 박자만 가정한다 (다른 박자는 미지원).
//   - 패턴은 지금 코드에 GoGo 하나만 내장(추후 JSON 파일 실제 로딩으로 교체 예정).
//   - triad는 근음+3도+5도뿐, 실제 기타 운지는 4단계에서 대체.
//   - 패턴 슬롯 길이가 표준 음표 길이로 안 떨어지는 극단적인 경우는
//     가장 가까운 표준 길이로 반올림(내림)한다.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Stage3_PatternEngine"
    description: "3단계: 코드 진행에 리듬 패턴(GoGo)을 반복 적용해 반주를 생성합니다."
    version: "0.5"
    requiresScore: true
    pluginType: "dialog"
    width: 620
    height: 480

    property string resultText: "실행 대기 중..."
    property var patternEvents: []
    property int targetTrack: -1
    property bool applied: false

    // MuseScore 고정 tick 해상도: 4분음표 = 480 tick.
    property int quarterTicks: 480

    // ---- 내장 패턴: GoGo Basic (data/patterns/gogo_basic.json과 동일 형식) ----
    // 3단계에서는 코드로 내장해두고, 실제 파일 로딩(FileIO)은 이후
    // 패턴 편집기(6단계)와 함께 붙일 예정.
    // (복잡한 중첩 객체를 property 기본값으로 바로 선언하면 QML 파싱
    //  모호성으로 창 전체가 비어버리는 문제가 있어, 함수로 대체함)
    function getPattern() {
        return {
            name: "GoGo Basic",
            timeSignature: "4/4",
            length: 1,
            events: [
                { beat: 1, type: "bass" },
                { beat: 2, type: "chord" },
                { beat: 3, type: "bass" },
                { beat: 4, type: "chord" }
            ]
        };
    }

    onRun: {
        try {
            resultText = buildPreview();
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
        var baseOctaveRoot = 48; // C3 근처, 4단계에서 실제 운지로 대체 예정
        var root = baseOctaveRoot + parsed.pc;
        var third = root + (parsed.isMinor ? 3 : 4);
        var fifth = root + 7;
        return [root, third, fifth];
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
                        events.push({ tick: segment.tick, chordName: ann.text, pitches: triadPitches(ann.text) });
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

    // ---- 패턴 x 코드 진행 -> 실제 이벤트 목록 생성 ----
    function buildPatternEvents(selInfo) {
        var pattern = getPattern();
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

                var chord = findActiveChord(tick, selInfo.chordEvents);
                var pitches = null;
                if (chord && chord.pitches) {
                    pitches = (slot.type === "bass") ? [chord.pitches[0] - 12] : chord.pitches;
                }

                events.push({
                    tick: tick,
                    duration: duration,
                    type: slot.type,
                    chordName: chord ? chord.chordName : null,
                    pitches: pitches
                });
            }
        }
        events.sort(function (a, b) { return a.tick - b.tick; });
        return events;
    }

    // ---- 미리보기 ----
    function buildPreview() {
        var selInfo = readChordEvents();
        if (selInfo === null) {
            return "선택된 영역이 없거나 열려있는 악보가 없습니다.\n마디를 선택한 뒤 다시 실행하세요.";
        }
        if (selInfo.chordEvents.length === 0) {
            return "선택 범위(Track " + selInfo.track + ")에서 코드 기호를 찾지 못했습니다.";
        }

        var events = buildPatternEvents(selInfo);
        patternEvents = events;

        var lines = [];
        lines.push("=== ErayChord 3단계: 패턴(" + getPattern().name + ") 미리보기 (아직 악보에 쓰지 않았습니다) ===");
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
        lines.push("=== ErayChord 3단계: 악보에 쓰기 완료 ===");
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
            text: "ErayChord — 3단계 Pattern Engine (GoGo)"
            font.bold: true
            font.pixelSize: 16
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
