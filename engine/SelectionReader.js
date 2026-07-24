.pragma library

// ============================================================
// SelectionReader.js
//
// 역할: 현재 사용자가 선택한 마디 범위를 읽어
//   { track, startTick, endTick, startMeasureNo, endMeasureNo }
//   형태로 반환한다.
//
// 검증 이력: poc/Test1_ReadSelection.qml에서 처음 확인했고,
//   stage6(Stage6_PatternRecorder.qml)의 readTargetChordEvents() 안에서
//   실제로 코드 진행을 읽어내는 데 동일한 로직을 재사용해 검증했다.
//
// 8단계 통합 메모(수정): 처음에는 이 파일 안에서 ".import MuseScore 3.0"
//   으로 Cursor enum을 직접 가져다 썼는데, 실기 테스트 결과 이 방식으로
//   접근한 enum이 기대한 값과 다르게 동작하는 정황(뮤트/액센트 표시 실패)이
//   확인됐다. 그래서 enum 값 자체를 plugin.qml(거기서는 일반적인
//   "import MuseScore 3.0"으로 확실하게 접근 가능)에서 만들어 파라미터로
//   넘겨받는 방식으로 바꿨다. 이 파일은 이제 MuseScore API를 전혀
//   import하지 않는, 순수하게 주입받은 값만 쓰는 모듈이다.
//
// 한계(TODO, 향후 확장 대상):
//   마디 길이를 4/4(분음표=480틱 기준 1마디=1920틱)로 고정 가정한다.
//   다른 박자표를 지원하려면 curScore의 TimeSig 정보를 읽어 마디 길이를
//   동적으로 계산하도록 확장해야 한다.
//
// cursorSelStart / cursorSelEnd: 호출 쪽에서 넘겨주는
//   Cursor.SELECTION_START / Cursor.SELECTION_END 값.
// ============================================================

function readSelection(curScore, cursorSelStart, cursorSelEnd) {
    if (typeof curScore === 'undefined' || curScore === null) return null;

    var startCursor = curScore.newCursor();
    startCursor.rewind(cursorSelStart);
    if (!startCursor.segment) return null;

    var track = startCursor.track;
    var startTick = startCursor.segment.tick;
    var startMeasureNo = startCursor.measure.no + 1;

    var endCursor = curScore.newCursor();
    endCursor.rewind(cursorSelEnd);
    var endTick, endMeasureNo;
    if (endCursor.segment) {
        endTick = endCursor.segment.tick;
        endMeasureNo = endCursor.measure.no + 1;
    } else {
        endTick = Number.MAX_VALUE;
        endMeasureNo = curScore.nmeasures;
    }

    return {
        track: track,
        startTick: startTick,
        startMeasureNo: startMeasureNo,
        endMeasureNo: endMeasureNo,
        endTick: endMeasureNo * 1920
    };
}
