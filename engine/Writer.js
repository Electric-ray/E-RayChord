.pragma library

// ============================================================
// Writer.js
//
// 역할: NoteGenerator가 만든 음표 이벤트 목록을 실제 악보(Guitar 트랙)에
//   기록한다. Cursor.addNote / addToChord, 뮤트 노트헤드 표시,
//   액센트 아티큘레이션 표시를 담당한다.
//
// 검증 이력: 뼈대는 poc/Test3_AddNote.qml, poc/Test4_AddChord.qml에서
//   확인했고, 실제 쓰기 루프(빈 구간 쉼표 채우기, 뮤트/액센트 처리)는
//   stage6(Stage6_PatternRecorder.qml)의 applyPatternToScore()에서
//   검증된 그대로다.
//
// 주의(PoC Test5 결과 반영): 새 Guitar 트랙을 코드로 생성하는 기능은
//   안정적으로 지원되는지 확인되지 않아, 기본 동작은 "사용자가 미리
//   선택해 둔 기존 트랙에 쓰기"다. 새 트랙 생성은 여기서 다루지 않는다.
//
// 8단계 통합 메모(수정): 처음에는 이 파일 안에서
//   ".pragma library" + ".import MuseScore 3.0 as MS"로 Cursor/Element/
//   SymId/NoteHeadGroup enum을 직접 가져다 썼는데, 실기 테스트에서
//   뮤트 노트헤드와 액센트 아티큘레이션이 표시되지 않는 문제가 확인됐다
//   (Pattern Editor(=stage6, 같은 로직을 단일 파일로 씀)에서는 정상 표시).
//   즉, 별도 .js 파일에서 ".import"로 가져온 이 enum들이 기대한 값으로
//   풀리지 않는 것으로 보인다. 그래서 이 파일에서 MuseScore enum을
//   직접 참조하는 부분을 전부 제거하고, 실제 값은 plugin.qml(거기서는
//   보통의 "import MuseScore 3.0"으로 확실히 접근 가능 — stage6와 동일한
//   방식)에서 만들어 파라미터로 주입받도록 바꿨다.
// ============================================================

function restCandidateList(quarterTicks) {
    var qt = quarterTicks || 480;
    return [
        { num: 1, den: 1,  ticks: qt * 4 },
        { num: 1, den: 2,  ticks: qt * 2 },
        { num: 1, den: 4,  ticks: qt },
        { num: 1, den: 8,  ticks: qt / 2 },
        { num: 1, den: 16, ticks: qt / 4 },
        { num: 1, den: 32, ticks: qt / 8 },
        { num: 1, den: 64, ticks: qt / 16 }
    ];
}

function pickDuration(ticks, quarterTicks) {
    var candidates = restCandidateList(quarterTicks);
    for (var k = 0; k < candidates.length; k++) {
        if (candidates[k].ticks <= ticks) return candidates[k];
    }
    return candidates[candidates.length - 1];
}

function fillGapWithRests(cursor, targetTick, quarterTicks) {
    var guard = 0;
    while (cursor.segment && cursor.tick < targetTick && guard < 1000) {
        var gap = targetTick - cursor.tick;
        var chosen = pickDuration(gap, quarterTicks);
        cursor.setDuration(chosen.num, chosen.den);
        cursor.addRest();
        guard++;
    }
}

// events       : NoteGenerator.generateEvents()의 결과
// msEnums      : plugin.qml에서 넘겨주는 MuseScore enum/함수 묶음
//   {
//     cursorSelStart      : Cursor.SELECTION_START,
//     elementArticulation : Element.ARTICULATION,
//     symIdAccent         : SymId.articAccentAbove,
//     noteHeadGroupCross  : NoteHeadGroup.HEAD_CROSS,
//     newElementFn        : newElement 함수 그 자체
//   }
function writeEvents(curScore, track, events, quarterTicks, msEnums) {
    var writtenCount = 0;
    var skipped = [];
    var accentCount = 0;
    var accentFailed = [];
    var muteFailed = [];

    curScore.startCmd();

    var writeCursor = curScore.newCursor();
    writeCursor.track = track;
    writeCursor.rewind(msEnums.cursorSelStart);

    for (var i = 0; i < events.length; i++) {
        var pe = events[i];

        while (writeCursor.segment && writeCursor.tick < pe.tick) writeCursor.next();
        if (writeCursor.segment && writeCursor.tick > pe.tick) {
            writeCursor.prev();
            if (writeCursor.tick < pe.tick) fillGapWithRests(writeCursor, pe.tick, quarterTicks);
        }
        if (!writeCursor.segment || writeCursor.tick !== pe.tick) {
            var reachedTick = writeCursor.segment ? writeCursor.tick : "없음";
            skipped.push("tick " + pe.tick + " (" + pe.type + ", 도달=" + reachedTick + ")");
            continue;
        }

        var durInfo = pickDuration(pe.duration, quarterTicks);
        writeCursor.setDuration(durInfo.num, durInfo.den);

        if (!pe.pitches || pe.pitches.length === 0) {
            writeCursor.addRest();
        } else {
            writeCursor.rewindToTick(pe.tick);
            writeCursor.setDuration(durInfo.num, durInfo.den);
            writeCursor.addNote(pe.pitches[0]);
            for (var p = 1; p < pe.pitches.length; p++) {
                writeCursor.rewindToTick(pe.tick);
                writeCursor.setDuration(durInfo.num, durInfo.den);
                writeCursor.addNote(pe.pitches[p], true);
            }

            if (pe.type === "mute") {
                try {
                    writeCursor.rewindToTick(pe.tick);
                    var chordEl = writeCursor.element;
                    if (chordEl && chordEl.notes) {
                        for (var mi = 0; mi < chordEl.notes.length; mi++) {
                            chordEl.notes[mi].headGroup = msEnums.noteHeadGroupCross;
                        }
                    }
                } catch (eh) {
                    muteFailed.push("tick " + pe.tick);
                }
            }

            if (pe.accent) {
                try {
                    writeCursor.rewindToTick(pe.tick);
                    var artic = msEnums.newElementFn(msEnums.elementArticulation);
                    artic.symbol = msEnums.symIdAccent;
                    writeCursor.add(artic);
                    accentCount++;
                } catch (ea) {
                    accentFailed.push("tick " + pe.tick);
                }
            }
        }
        writtenCount++;
    }

    curScore.endCmd();

    return {
        writtenCount: writtenCount,
        totalCount: events.length,
        accentCount: accentCount,
        skipped: skipped,
        accentFailed: accentFailed,
        muteFailed: muteFailed
    };
}
