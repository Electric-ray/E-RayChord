import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0

// ============================================================
// Test 5. 기존 Guitar 트랙에 입력 가능한지 확인 (v0.3, 진단 강화판)
//
// v0.2에서 "입력 완료"라고는 표시됐지만 실제로는 음표가 안 들어간
// 사례가 보고되어, 이번 버전은 입력 "전"과 "후"의 해당 위치 요소를
// 비교해서 실제로 뭔가 바뀌었는지까지 보여준다.
//
// 실행 전에 반드시:
//   - 이전 테스트들에서 입력된 음표가 남아있다면 Ctrl+Z로 전부 되돌리거나
//     악보를 다시 열어서 "깨끗한 상태"에서 실행해볼 것을 권장.
//   - 선택 위치는 음표가 아직 없는(쉼표) 마디로.
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Test5_ExistingGuitarTrack"
    description: "트랙(파트) 목록 확인 + 입력 전/후 비교로 실제 입력 여부를 진단합니다."
    version: "0.3"
    requiresScore: true
    pluginType: "dialog"
    width: 520
    height: 420

    property string resultText: "실행 대기 중..."

    onRun: {
        resultText = runTest();
    }

    function runTest() {
        if (typeof curScore === 'undefined' || curScore === null) {
            return "열려있는 악보가 없습니다.";
        }

        var lines = [];
        lines.push("=== Test5: 트랙 목록 확인 (v0.3) ===");
        lines.push("");

        var guitarPartIdx = -1;
        for (var i = 0; i < curScore.parts.length; i++) {
            var part = curScore.parts[i];
            var partName = "";
            try { partName = part.longName; } catch (e) {}
            if (!partName) {
                try { partName = part.partName; } catch (e) {}
            }
            lines.push("Part " + i + " : " + partName);
            if (partName && partName.toLowerCase().indexOf("guitar") !== -1) {
                guitarPartIdx = i;
            }
        }

        lines.push("");
        if (guitarPartIdx === -1) {
            lines.push("(이름에 'Guitar'가 포함된 파트를 찾지 못했습니다. 현재 선택된 트랙으로 진행합니다.)");
        } else {
            lines.push("Guitar로 추정되는 파트 인덱스: " + guitarPartIdx);
        }

        lines.push("");
        lines.push("--- 입력 테스트 ---");

        var cursor = curScore.newCursor();
        cursor.rewind(Cursor.SELECTION_START);

        if (!cursor.segment) {
            lines.push("선택된 위치가 없어 음표 입력 테스트는 건너뜁니다.");
            return lines.join("\n");
        }

        var measureNo = cursor.measure.no + 1;
        var track = cursor.track;
        var tick = cursor.tick;
        lines.push("선택 위치 -> Measure " + measureNo + ", Track " + track + ", Tick " + tick);

        var beforeType = "(없음/알 수 없음)";
        try {
            if (cursor.element) beforeType = cursor.element.name;
        } catch (e) {}
        lines.push("입력 전 이 위치 요소 : " + beforeType);

        curScore.startCmd();
        cursor.setDuration(1, 4);
        cursor.addNote(67); // G4
        curScore.endCmd();

        // 같은 위치를 다시 읽어서 실제로 바뀌었는지 확인
        var verifyCursor = curScore.newCursor();
        verifyCursor.rewind(Cursor.SELECTION_START);
        var afterType = "(없음/알 수 없음)";
        var afterPitch = "-";
        try {
            if (verifyCursor.element) {
                afterType = verifyCursor.element.name;
                if (verifyCursor.element.notes && verifyCursor.element.notes.length > 0) {
                    afterPitch = verifyCursor.element.notes[0].pitch;
                }
            }
        } catch (e) {}

        lines.push("입력 후 이 위치 요소 : " + afterType + "  (pitch=" + afterPitch + ")");
        lines.push("");

        if (afterType === beforeType && afterPitch !== 67) {
            lines.push("⚠ 입력 전/후 요소가 그대로입니다. 실제로 음표가 안 들어간 것 같습니다.");
            lines.push("   -> curScore.startCmd()/endCmd() 또는 addNote() 관련 문제일 수 있습니다.");
        } else {
            lines.push("입력 후 요소/피치가 바뀐 것으로 보아 음표가 들어간 것 같습니다.");
        }
        lines.push("악보를 직접 확인해서 G4 음표가 실제로 생겼는지도 확인해 주세요.");

        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord PoC — Test5 (v0.3)"
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
