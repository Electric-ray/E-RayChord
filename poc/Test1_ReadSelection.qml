import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// Test 1. 선택한 마디 범위 읽기
//
// 변경 사항 (v0.2):
//   MuseScore 4는 console.log를 확인할 방법이 마땅치 않아서
//   (MU3의 Plugin Creator 콘솔이 MU4에는 없음), 결과를
//   콘솔이 아니라 "이 플러그인 창 안"에 직접 텍스트로 보여준다.
//   플러그인을 실행하면 바로 이 창이 뜨고, 그 안의 텍스트가 결과다.
//
// 사용법:
//   1) MuseScore에서 임의의 마디 범위를 마우스로 선택
//   2) 플러그인 실행 -> 뜨는 창에서 결과 확인
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Test1_ReadSelection"
    description: "선택한 마디의 시작/끝 번호와 트랙을 창에 표시합니다."
    version: "0.3"
    requiresScore: true
    pluginType: "dialog"
    width: 480
    height: 300

    property string resultText: "실행 대기 중..."

    onRun: {
        resultText = runTest();
    }

    function runTest() {
        if (typeof curScore === 'undefined' || curScore === null) {
            return "열려있는 악보가 없습니다.";
        }

        var cursor = curScore.newCursor();
        cursor.rewind(Cursor.SELECTION_START);

        if (!cursor.segment) {
            return "선택된 마디가 없습니다.\n마디를 선택한 뒤 다시 실행하세요.";
        }

        var startMeasureNo = cursor.measure.no + 1; // 0-based -> 1-based
        var startTrack = cursor.track;

        cursor.rewind(Cursor.SELECTION_END);

        var endMeasureNo;
        if (cursor.segment) {
            // Test2 결과로 확인됨: SELECTION_END로 이동한 커서는
            // 선택 범위 "다음"이 아니라 선택 범위 안의 마지막 위치를
            // 가리킨다. 따라서 Start와 동일하게 0-based -> 1-based
            // 변환(+1)이 필요하다. (이전 버전에서 이 변환이 빠져 있었음)
            endMeasureNo = cursor.measure.no + 1;
            if (endMeasureNo < startMeasureNo) {
                endMeasureNo = startMeasureNo;
            }
        } else {
            endMeasureNo = curScore.nmeasures;
        }

        var lines = [];
        lines.push("=== Test1: 선택 영역 읽기 결과 ===");
        lines.push("");
        lines.push("Start Measure : " + startMeasureNo);
        lines.push("End Measure   : " + endMeasureNo);
        lines.push("Track         : " + startTrack);
        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord PoC — Test1"
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
