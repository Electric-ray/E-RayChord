import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2

// MainDialog.qml
//
// 8단계 통합 메모: 계획 단계(기술설계서 9절)에서는 UI를 이 파일로
// 분리할 예정이었지만, 실제로는 plugin.qml 하나에 전체 UI를 직접
// 넣는 방식(1~7단계에서 검증된, 위험이 적은 단일 파일 구조)을
// 그대로 따랐다. 그래서 이 파일은 최종적으로 쓰이지 않는다.
//
// 실제 메인 생성기 UI는 ErayChord/plugin.qml 안의 ColumnLayout을
// 참고할 것. 이 파일은 초기 기획 문서와의 연결점으로만 남겨둔다.

Rectangle {
    width: 360
    height: 200
    color: "#f0f0f0"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        Text {
            text: "실제 UI는 plugin.qml에 구현되어 있습니다 (8단계 통합 메모 참고)."
            wrapMode: Text.WordWrap
        }
    }
}
