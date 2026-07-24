import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0
import FileIO 3.0

// ============================================================
// Test 6. JSON 파일 읽기 / 쓰기 (FileIO 모듈)
//
// 결과는 창에 표시된다 (Test1 상단 주석 참고).
// 이 테스트는 고정 경로(tempPath())에 JSON을 쓰고 다시 읽어
// 왕복(round-trip)이 되는지 확인한다.
//
// 참고: tempPath()가 실제로 어느 폴더로 잡히는지도 결과 창에
// 함께 표시하므로, 파일탐색기로 직접 가서 파일이 생겼는지
// 확인해볼 수도 있다.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Test6_JsonFileIO"
    description: "고정 경로에 JSON을 쓰고 다시 읽어 왕복 여부를 확인합니다."
    version: "0.2"
    requiresScore: false
    pluginType: "dialog"
    width: 520
    height: 420

    property string resultText: "실행 대기 중..."

    FileIO {
        id: testFile
        source: tempPath() + "/eraychord_test_pattern.json"
        onError: function(msg) {
            resultText = "FileIO 오류: " + msg;
        }
    }

    onRun: {
        resultText = runTest();
    }

    function runTest() {
        var lines = [];
        lines.push("=== Test6: JSON FileIO 확인 ===");
        lines.push("");
        lines.push("대상 파일: " + testFile.source);
        lines.push("");

        var sample = {
            name: "GoGo Basic",
            timeSignature: "4/4",
            length: 1,
            events: [
                { type: "bass", beat: 1 },
                { type: "chord", beat: 2 },
                { type: "bass", beat: 3 },
                { type: "chord", beat: 4 }
            ]
        };

        var jsonOut = JSON.stringify(sample, null, 2);

        var writeOk = testFile.write(jsonOut);
        lines.push("쓰기 결과(writeOk): " + writeOk);
        lines.push("");

        var jsonIn = testFile.read();
        lines.push("읽어온 내용:");
        lines.push(jsonIn);
        lines.push("");

        try {
            var parsed = JSON.parse(jsonIn);
            lines.push("파싱 성공. pattern name = " + parsed.name +
                        ", events 개수 = " + parsed.events.length);
        } catch (e) {
            lines.push("JSON 파싱 실패: " + e);
        }

        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord PoC — Test6"
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
