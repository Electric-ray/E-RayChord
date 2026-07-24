import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// 진단용: 로직 전혀 없이 UI만 뜨는지 확인하기 위한 최소 테스트.
// 이것도 빈 창으로 뜨면 캐싱/파일 인식 문제이고,
// 이것도 안 뜨면 pluginType dialog 자체에 다른 문제가 있는 것.

MuseScore {
    menuPath: "Plugins.ErayChord.Stage3_MinimalTest"
    description: "빈 창 문제 진단용 최소 테스트"
    version: "1.0"
    requiresScore: true
    pluginType: "dialog"
    width: 400
    height: 200

    Rectangle {
        anchors.fill: parent
        color: "#ffe0e0"

        Text {
            anchors.centerIn: parent
            text: "이 글자가 보이면 UI는 정상 동작합니다"
            font.pixelSize: 18
        }
    }
}
