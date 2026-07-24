import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// Test 2. 선택 범위 안의 코드(Harmony) 심볼 읽기  (v0.3)
//
// v0.2 -> v0.3 변경 사유:
//   cursor.next()는 "다음 ChordRest(음표/쉼표)"로만 이동한다.
//   앞마디에서 타이로 이어진 음이 있으면, 새 마디 첫 박에는
//   "새로 시작하는 ChordRest"가 없기 때문에 커서가 그 위치의
//   세그먼트를 건너뛸 수 있다 -> 그 위치에 붙은 코드(Harmony)도
//   함께 건너뛰어진다. (실제로 이 문제로 특정 코드가 누락된 사례 확인됨)
//
//   그래서 이번 버전은 Cursor.next()로 이동하지 않고,
//   Segment 자체의 next를 이용해 "모든" 세그먼트를 하나씩 순회한다.
//   이러면 타이로 이어진 위치의 세그먼트도 빠짐없이 검사된다.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Test2_ReadChords"
    description: "선택 범위 안의 코드(Harmony) 심볼을 창에 표시합니다. (v0.5, 트랙 필터 추가)"
    version: "0.5"
    requiresScore: true
    pluginType: "dialog"
    width: 480
    height: 380

    property string resultText: "실행 대기 중..."

    onRun: {
        resultText = runTest();
    }

    function runTest() {
        if (typeof curScore === 'undefined' || curScore === null) {
            return "열려있는 악보가 없습니다.";
        }

        var startCursor = curScore.newCursor();
        startCursor.rewind(Cursor.SELECTION_START);
        if (!startCursor.segment) {
            return "선택된 영역이 없습니다.\n마디를 선택한 뒤 다시 실행하세요.";
        }
        // curScore.firstSegment / curScore.lastSegment 는 실제로 존재하는지
        // 검증되지 않은 속성이라 v0.3에서 순회가 아예 시작조차 안 되는
        // 회귀가 발생했다. 대신 이미 확실히 동작하는 cursor.segment를
        // 그대로 순회 시작점으로 사용한다 (v0.4).
        var startSegment = startCursor.segment;
        var targetTrack = startCursor.track;

        var endCursor = curScore.newCursor();
        endCursor.rewind(Cursor.SELECTION_END);
        var endTick = endCursor.segment ? endCursor.segment.tick : Number.MAX_VALUE;

        var lines = [];
        lines.push("=== Test2: 코드(Harmony) 읽기 결과 (v0.5) ===");
        lines.push("선택한 트랙(Track " + targetTrack + ")에 붙은 코드만 표시합니다.");
        lines.push("");

        var found = 0;

        // Cursor.next()가 아니라 Segment 자체의 next로 순회한다
        // (모든 세그먼트 타입을 빠짐없이 검사하기 위함).
        var segment = startSegment;

        while (segment && segment.tick < endTick) {
            var annotations = segment.annotations;
            if (annotations) {
                for (var i = 0; i < annotations.length; i++) {
                    var ann = annotations[i];
                    var annName = "?";
                    try { annName = ann.name; } catch (e) {}

                    var isHarmony =
                        (annName === "Harmony") ||
                        (ann.type !== undefined && Element.HARMONY !== undefined && ann.type === Element.HARMONY);

                    // 악보 하나에 코드가 여러 스태프(보컬용/기타용 등) 위에
                    // 중복으로 입력되어 있는 경우가 흔하다. 이 경우 같은
                    // 위치(tick)에 트랙이 다른 Harmony가 여러 개 붙어있으므로,
                    // 우리가 실제로 반주를 생성할 대상 트랙의 것만 남긴다.
                    var annTrack = -1;
                    try { annTrack = ann.track; } catch (e3) {}
                    var isTargetTrack = (annTrack === targetTrack);

                    if (isHarmony && isTargetTrack) {
                        found++;
                        var measureNo = "?";
                        try {
                            if (segment.parent && segment.parent.no !== undefined) {
                                measureNo = segment.parent.no + 1;
                            }
                        } catch (e2) {}
                        lines.push("Measure " + measureNo + " (tick " + segment.tick + ") : " + ann.text);
                    }
                }
            }
            segment = segment.next;
        }

        if (found === 0) {
            lines.push("(코드 기호를 찾지 못했습니다.)");
            lines.push("");
            lines.push("체크리스트:");
            lines.push("- 선택한 마디에 코드 기호가 실제로 입력되어 있는지");
            lines.push("- 코드가 선택한 트랙(Track " + targetTrack + ")이 아닌");
            lines.push("  다른 스태프에만 입력되어 있는 건 아닌지");
        }

        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord PoC — Test2 (v0.5)"
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
                text: "닫기"
                // MU4에서는 Qt.quit()이 무반응이거나 앱 전체를 종료시킬 수 있어
                // plugin-scope의 quit()를 우선 사용한다 (MU3 호환용 폴백 포함).
                onClicked: (typeof(quit) === "undefined" ? Qt.quit : quit)()
            }
        }
    }
}
