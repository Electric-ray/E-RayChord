.pragma library

// ============================================================
// ChordReader.js
//
// 역할: SelectionReader가 읽은 선택 범위 안에서, 지정된 트랙에 붙은
//   코드(Harmony) 심볼을 전부 읽어 [{ tick, chord }, ...] 형태로
//   시간 순 반환한다.
//
// 검증 이력: poc/Test2_ReadChords.qml, stage6의 readTargetChordEvents()에서
//   확인된 조건을 그대로 사용한다.
//   - annotations 중 ann.name === "Harmony" 이고 ann.track이 대상 트랙과
//     같은 것만 코드로 인정한다.
//   - 코드 표기 텍스트는 harmony.text 속성을 그대로 사용한다(별도 파싱 없음).
//
// 8단계 통합 메모(수정): SelectionReader.js와 같은 이유로 ".import"를
//   제거하고, Cursor.SELECTION_START 값을 호출 쪽에서 파라미터로
//   받는다(cursorSelStart).
// ============================================================

function readChords(curScore, selInfo, cursorSelStart) {
    if (typeof curScore === 'undefined' || curScore === null || !selInfo) return [];

    var cursor = curScore.newCursor();
    cursor.rewind(cursorSelStart);
    var segment = cursor.segment;
    var events = [];

    while (segment && segment.tick < selInfo.endTick) {
        var annotations = segment.annotations;
        if (annotations) {
            for (var i = 0; i < annotations.length; i++) {
                var ann = annotations[i];
                var annName = "?";
                try { annName = ann.name; } catch (e) {}
                var annTrack = -1;
                try { annTrack = ann.track; } catch (e2) {}
                if (annName === "Harmony" && annTrack === selInfo.track) {
                    events.push({ tick: segment.tick, chord: ann.text });
                }
            }
        }
        segment = segment.next;
    }
    return events;
}
