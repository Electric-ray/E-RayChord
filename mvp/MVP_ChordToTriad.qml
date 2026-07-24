import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// 2단계 MVP — Chord To Triad (최소 기능)
//
// 목적: "마디 선택 -> 코드 읽기 -> 코드당 4분음표 triad(root-3rd-5th)
//        하나씩 -> 선택한 트랙에 입력" 만 되는, 주법이 하나뿐인 최소
//        버전. 개발순서.txt 2단계 원칙을 그대로 따른다.
//
// PoC(1단계)에서 검증된 사실을 그대로 재사용한다:
//   - SELECTION_END로 이동한 커서는 선택 영역 "다음"이 아니라
//     선택 영역 안의 마지막 위치를 가리킨다.
//   - 코드(Harmony)를 읽을 때는 트랙(스태프)으로 반드시 필터링해야
//     한다 (보컬/기타 등에 코드가 중복 입력된 악보가 흔함).
//   - cursor.next()가 아니라 segment.next로 순회해야 특정 위치가
//     누락되지 않는다.
//   - 임의의 tick으로 정확히 이동하려면 cursor.next()로 점프시키지 말고
//     cursor.rewindToTick(tick)을 쓴다 (그 tick에 세그먼트가 존재하기만
//     하면 정확히 그 위치로 이동함 — MuseScore 공식 문서 확인됨).
//   - addNote(pitch, true)로 화음을 쌓을 때, 두 번째/세 번째 음을 넣으면
//     커서가 원래 자리를 벗어나는 버그가 보고되어 있다. 그래서 음을
//     하나 넣을 때마다 같은 tick으로 rewindToTick을 다시 해준다.
//   - MU4에서는 Qt.quit() 대신 quit()을 쓴다.
//
// 사용법:
//   1) 코드 기호가 입력된 마디 범위를 선택 (기타 트랙 위의 코드를
//      직접 선택하는 것을 권장 — 지금은 "선택한 트랙에서 코드를 읽어
//      같은 트랙에 쓴다"는 가장 단순한 가정으로 동작한다)
//   2) 플러그인 실행 -> 미리보기 창에서 어떤 코드가 어떤 음으로
//      변환될지 확인
//   3) "악보에 쓰기" 버튼을 눌러야 실제로 입력된다 (누르기 전까지는
//      악보가 전혀 바뀌지 않는다)
//   4) 마음에 안 들면 Ctrl+Z 한 번으로 전부 되돌릴 수 있다
//      (모든 입력을 하나의 startCmd/endCmd로 묶었기 때문)
//
// 한계 (알고 하는 단순화, 이후 단계에서 개선 예정):
//   - triad는 근음(root) + 장/단3도 + 완전5도 뿐이다.
//     7th, sus4 등 확장 코드는 무시하고 3화음으로만 처리한다.
//   - 음역대는 임시로 고정(대략 C3 근처)이며, 실제 기타 운지는
//     4단계(운지 라이브러리)에서 대체된다.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.MVP_ChordToTriad"
    description: "2단계 MVP: 코드 진행을 읽어 4분음표 triad로 입력합니다."
    version: "0.5"
    requiresScore: true
    pluginType: "dialog"
    width: 560
    height: 460

    property string resultText: "실행 대기 중..."
    property var chordEvents: []   // 미리보기 시점에 계산해둔 {tick, measureNo, chordName, pitches, ok}
    property int targetTrack: -1
    property bool applied: false

    onRun: {
        resultText = buildPreview();
    }

    // ---- 코드 이름 -> 근음 pitch class 파싱 (단순 major/minor만) ----
    function parseChordRoot(name) {
        var m = name.match(/^([A-G])([#b]?)/);
        if (!m) return null;

        var letterToPc = { C:0, D:2, E:4, F:5, G:7, A:9, B:11 };
        var pc = letterToPc[m[1]];
        if (m[2] === "#") pc += 1;
        if (m[2] === "b") pc -= 1;
        pc = ((pc % 12) + 12) % 12;

        var rest = name.substring(m[0].length);
        // "Am" -> minor, "Cmaj7" -> "m"으로 시작하지만 "maj"라 major로 처리
        var isMinor = (rest.indexOf("m") === 0 && rest.indexOf("maj") !== 0);

        return { pc: pc, isMinor: isMinor };
    }

    function triadPitches(chordName) {
        var parsed = parseChordRoot(chordName);
        if (!parsed) return null;

        var baseOctaveRoot = 48; // C3 근처. 4단계 운지 라이브러리에서 실제 기타 음역으로 대체 예정.
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

    // ---- 선택 영역에서 코드(Harmony) 읽기 (Test2 v0.5 로직 재사용) ----
    function readChordEvents() {
        if (typeof curScore === 'undefined' || curScore === null) {
            return null;
        }

        var startCursor = curScore.newCursor();
        startCursor.rewind(Cursor.SELECTION_START);
        if (!startCursor.segment) {
            return null;
        }

        var track = startCursor.track;
        var startSegment = startCursor.segment;

        var endCursor = curScore.newCursor();
        endCursor.rewind(Cursor.SELECTION_END);
        var endTick = endCursor.segment ? endCursor.segment.tick : Number.MAX_VALUE;

        var events = [];
        var segment = startSegment;

        while (segment && segment.tick < endTick) {
            var annotations = segment.annotations;
            if (annotations) {
                for (var i = 0; i < annotations.length; i++) {
                    var ann = annotations[i];
                    var annName = "?";
                    try { annName = ann.name; } catch (e) {}
                    var annTrack = -1;
                    try { annTrack = ann.track; } catch (e2) {}

                    if (annName === "Harmony" && annTrack === track) {
                        var measureNo = "?";
                        try {
                            if (segment.parent && segment.parent.no !== undefined) {
                                measureNo = segment.parent.no + 1;
                            }
                        } catch (e3) {}

                        events.push({
                            tick: segment.tick,
                            measureNo: measureNo,
                            chordName: ann.text
                        });
                    }
                }
            }
            segment = segment.next;
        }

        targetTrack = track;
        return events;
    }

    // ---- 미리보기 텍스트 구성 (악보는 건드리지 않음) ----
    function buildPreview() {
        var events = readChordEvents();
        if (events === null) {
            return "선택된 영역이 없거나 열려있는 악보가 없습니다.\n마디를 선택한 뒤 다시 실행하세요.";
        }
        if (events.length === 0) {
            return "선택 범위(Track " + targetTrack + ")에서 코드 기호를 찾지 못했습니다.\n" +
                   "코드가 입력된 트랙을 선택했는지 확인하세요.";
        }

        var lines = [];
        lines.push("=== ErayChord MVP: 미리보기 (아직 악보에 쓰지 않았습니다) ===");
        lines.push("대상 트랙: " + targetTrack);
        lines.push("");

        for (var i = 0; i < events.length; i++) {
            var ev = events[i];
            var pitches = triadPitches(ev.chordName);
            ev.pitches = pitches;

            var line = "Measure " + ev.measureNo + " (tick " + ev.tick + ") : " + ev.chordName + "  ->  ";
            if (pitches) {
                line += pitchToName(pitches[0]) + " " + pitchToName(pitches[1]) + " " + pitchToName(pitches[2]);
            } else {
                line += "(코드 이름을 해석하지 못해 건너뜁니다)";
            }
            lines.push(line);
        }

        lines.push("");
        lines.push("문제 없어 보이면 아래 '악보에 쓰기' 버튼을 누르세요.");
        chordEvents = events;
        return lines.join("\n");
    }

    // ---- 실제로 악보에 쓰기 ----
    function applyToScore() {
        if (!chordEvents || chordEvents.length === 0) {
            return "쓸 내용이 없습니다. 먼저 코드가 있는 범위를 선택하고 다시 실행하세요.";
        }

        var writtenCount = 0;
        var skipped = [];

        // MuseScore 고정 tick 해상도: 4분음표 = 480 tick.
        // (이전 실측 데이터 - 960/2040 등 - 가 이 값 기준으로만 정확히
        //  맞아떨어지는 것으로 재확인함)
        var TICKS_PER_QUARTER = 480;

        // setDuration(num, den)은 "온음표 기준 분수"다 (예: 4분음표=1/4 -> (1,4)).
        // *** 이전 버전(v0.3)의 결정적 버그: 온음표를 (4,1)로 지정해서
        //     실제로는 "온음표 4개 분량"이 되어 gap을 메꾼다면서 오히려
        //     더 크게 밀려나 버렸다. 아래는 올바르게 (1, den) 형태로 수정함. ***
        var restCandidates = [
            { num: 1, den: 1,  ticks: TICKS_PER_QUARTER * 4 },  // 온음표
            { num: 1, den: 2,  ticks: TICKS_PER_QUARTER * 2 },  // 2분음표
            { num: 1, den: 4,  ticks: TICKS_PER_QUARTER },      // 4분음표
            { num: 1, den: 8,  ticks: TICKS_PER_QUARTER / 2 },  // 8분음표
            { num: 1, den: 16, ticks: TICKS_PER_QUARTER / 4 },  // 16분음표
            { num: 1, den: 32, ticks: TICKS_PER_QUARTER / 8 },  // 32분음표
            { num: 1, den: 64, ticks: TICKS_PER_QUARTER / 16 }  // 64분음표 (최후 안전장치)
        ];

        // 목표 tick까지 정확한 길이의 쉼표를 채워서 강제로 도달시킨다.
        // (이 트랙에 그 tick과 정확히 일치하는 ChordRest 경계가 아예
        //  없는 경우에만 필요한 보완 로직 — 대부분은 next()로 충분함)
        function fillGapWithRests(cursor, targetTick) {
            var guard = 0;
            while (cursor.segment && cursor.tick < targetTick && guard < 1000) {
                var gap = targetTick - cursor.tick;
                var chosen = null;
                for (var k = 0; k < restCandidates.length; k++) {
                    if (restCandidates[k].ticks <= gap) {
                        chosen = restCandidates[k];
                        break;
                    }
                }
                if (!chosen) break;
                cursor.setDuration(chosen.num, chosen.den);
                cursor.addRest();
                guard++;
            }
        }

        curScore.startCmd();

        // 하나의 커서로 tick 오름차순으로 진행한다. 대부분의 위치는
        // next()로 자연스럽게(기존 쉼표를 쪼개며) 도달 가능하다 — 실제로
        // 15개 중 14개는 이 방식만으로 정확히 성공했다. next()가 목표를
        // 지나쳐버리는 예외적인 경우에만 한 칸 되돌린 뒤 정확한 길이의
        // 쉼표로 gap을 메워 강제로 정렬한다.
        var writeCursor = curScore.newCursor();
        writeCursor.track = targetTrack;
        writeCursor.rewind(Cursor.SELECTION_START);

        for (var i = 0; i < chordEvents.length; i++) {
            var ev = chordEvents[i];

            while (writeCursor.segment && writeCursor.tick < ev.tick) {
                writeCursor.next();
            }

            if (writeCursor.segment && writeCursor.tick > ev.tick) {
                // 지나쳐버렸다 -> 한 칸 되돌린 뒤 정확한 길이로 gap을 메운다.
                writeCursor.prev();
                if (writeCursor.tick < ev.tick) {
                    fillGapWithRests(writeCursor, ev.tick);
                }
            }

            if (!writeCursor.segment || writeCursor.tick !== ev.tick) {
                var reachedTick = writeCursor.segment ? writeCursor.tick : "없음";
                skipped.push(ev.chordName + "(measure " + ev.measureNo +
                              ", 목표 tick=" + ev.tick + ", 도달한 tick=" + reachedTick + ")");
                continue;
            }

            if (!ev.pitches) {
                skipped.push(ev.chordName + "(measure " + ev.measureNo + ", 이름 해석 실패)");
                continue;
            }

            writeCursor.setDuration(1, 4);

            // 알려진 문제: addNote(pitch, true)로 화음을 쌓을 때 두 번째/
            // 세 번째 음을 넣으면 커서가 원래 자리를 벗어나는 경우가 있다
            // (MuseScore 커뮤니티에 보고된 버그). 우회법은 음을 하나 넣을
            // 때마다 같은 tick으로 다시 rewindToTick 하는 것이다.
            writeCursor.rewindToTick(ev.tick);
            writeCursor.addNote(ev.pitches[0]);

            writeCursor.rewindToTick(ev.tick);
            writeCursor.addNote(ev.pitches[1], true);

            writeCursor.rewindToTick(ev.tick);
            writeCursor.addNote(ev.pitches[2], true);

            writtenCount++;
        }

        curScore.endCmd();
        applied = true;

        var lines = [];
        lines.push("=== ErayChord MVP: 악보에 쓰기 완료 ===");
        lines.push("");
        lines.push("입력된 코드 수: " + writtenCount + " / " + chordEvents.length);
        if (skipped.length > 0) {
            lines.push("");
            lines.push("건너뛴 항목:");
            for (var j = 0; j < skipped.length; j++) {
                lines.push("  - " + skipped[j]);
            }
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
            text: "ErayChord — 2단계 MVP (Chord To Triad)"
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
                enabled: chordEvents.length > 0
                onClicked: {
                    resultText = applyToScore();
                }
            }

            Button {
                text: "닫기"
                onClicked: (typeof(quit) === "undefined" ? Qt.quit : quit)()
            }
        }
    }
}
