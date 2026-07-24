import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// Test 3. 단일 음표 입력 (C4 4분음표)
//
// 결과는 창에 표시된다 (Test1 상단 주석 참고).
// 실제로 음표가 들어갔는지는 악보를 직접 눈으로 봐야 확인 가능하다.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Test3_AddNote"
    description: "선택 위치에 C4 4분음표 하나를 입력합니다."
    version: "0.2"
    requiresScore: true
    pluginType: "dialog"
    width: 480
    height: 260

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
            return "선택된 위치가 없습니다.\n마디를 선택한 뒤 다시 실행하세요.";
        }

        var measureNo = cursor.measure.no + 1;
        var track = cursor.track;

        curScore.startCmd();
        cursor.setDuration(1, 4); // 4분음표
        cursor.addNote(60);       // MIDI pitch 60 = C4
        curScore.endCmd();

        var lines = [];
        lines.push("=== Test3: 음표 입력 완료 ===");
        lines.push("");
        lines.push("위치: Measure " + measureNo + ", Track " + track);
        lines.push("");
        lines.push("악보를 확인해서 C4 4분음표가 실제로 생겼는지 확인하세요.");
        lines.push("Ctrl+Z로 되돌려지는지도 함께 확인하세요.");
        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord PoC — Test3"
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
