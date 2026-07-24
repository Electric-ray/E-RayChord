.pragma library

// ============================================================
// NoteGenerator.js
//
// 역할: Pattern(리듬) * 코드 진행(ChordReader 결과 + VoicingEngine으로 구한
//   피치) 을 조합해 실제로 악보에 입력할 음표 이벤트 목록을 생성한다.
//   Pattern과 Voicing은 이 모듈(Generator)에서만 서로 만난다
//   (개발순서.txt의 설계 원칙).
//
// 검증 이력: stage6(Stage6_PatternRecorder.qml)의 buildApplyEvents() /
//   splitByChordChanges() / findActiveChord()에서 이미 검증된 로직을
//   그대로 옮겼다(코드 진행 중간에 코드가 바뀌는 경우, 슬롯을 코드 경계에서
//   쪼개는 부분 포함).
//
// 입력:
//   selInfo     : SelectionReader.readSelection()의 결과
//   pattern     : PatternEngine이 정리한 Pattern 객체
//   chordEvents : [{ tick, chord, pitches }, ...] (pitches는 호출 쪽에서
//                 VoicingEngine.getVoicingPitches()로 미리 채워서 전달)
//   quarterTicks: 보통 480
//
// 한계(TODO, 향후 확장 대상):
//   - 마디 길이를 4/4(1마디=quarterTicks*4)로 고정 가정한다.
//   - "arpeggio"처럼 코드를 구성음별로 순차 연주하는 주법은 아직 지원하지
//     않는다(모든 슬롯은 "한 번에 울리는 화음" 또는 "단음"만 표현 가능).
//     이 두 가지는 8단계 이후 별도 확장 작업으로 남겨둔다.
// ============================================================

function findActiveChord(tick, chordEvents) {
    var active = null;
    for (var i = 0; i < chordEvents.length; i++) {
        if (chordEvents[i].tick <= tick) active = chordEvents[i];
        else break;
    }
    return active;
}

function splitByChordChanges(tick, duration, chordEvents) {
    var endTick = tick + duration;
    var boundaries = [tick];
    for (var i = 0; i < chordEvents.length; i++) {
        var ct = chordEvents[i].tick;
        if (ct > tick && ct < endTick) boundaries.push(ct);
    }
    boundaries.push(endTick);
    boundaries.sort(function (a, b) { return a - b; });

    var chunks = [];
    for (var j = 0; j < boundaries.length - 1; j++) {
        var segStart = boundaries[j];
        var segEnd = boundaries[j + 1];
        if (segEnd > segStart) chunks.push({ tick: segStart, duration: segEnd - segStart });
    }
    return chunks;
}

function generateEvents(selInfo, pattern, chordEvents, quarterTicks) {
    var qt = quarterTicks || 480;
    var sortedSlots = pattern.events.slice().sort(function (a, b) { return a.beat - b.beat; });
    var slots = [];
    for (var i = 0; i < sortedSlots.length; i++) {
        var offset = (sortedSlots[i].beat - 1) * qt;
        var durBeats = sortedSlots[i].durationBeats;
        if (durBeats === undefined || durBeats <= 0) durBeats = 1;
        var durTicks = durBeats * qt;
        slots.push({ offset: offset, duration: durTicks, type: sortedSlots[i].type, accent: !!sortedSlots[i].accent });
    }

    var events = [];
    var measureTicks = qt * 4; // TODO: 4/4 고정 가정
    for (var measureNo = selInfo.startMeasureNo; measureNo <= selInfo.endMeasureNo; measureNo++) {
        var measureStartTick = (measureNo - 1) * measureTicks;
        for (var s = 0; s < slots.length; s++) {
            var slot = slots[s];
            var tick = measureStartTick + slot.offset;
            if (tick < selInfo.startTick || tick >= selInfo.endTick) continue;

            var duration = slot.duration;
            if (tick + duration > selInfo.endTick) duration = selInfo.endTick - tick;
            if (duration <= 0) continue;

            var chunks = splitByChordChanges(tick, duration, chordEvents);
            for (var c = 0; c < chunks.length; c++) {
                var chunk = chunks[c];
                var chord = findActiveChord(chunk.tick, chordEvents);
                var pitches = null;

                if (slot.type === "rest") {
                    pitches = null;
                } else if (slot.type === "mute") {
                    if (chord && chord.pitches && chord.pitches.length > 0) pitches = chord.pitches.slice();
                } else if (chord && chord.pitches && chord.pitches.length > 0) {
                    pitches = (slot.type === "bass") ? [chord.pitches[0]] : chord.pitches;
                }

                events.push({
                    tick: chunk.tick,
                    duration: chunk.duration,
                    type: slot.type,
                    chordName: chord ? chord.chord : null,
                    pitches: pitches,
                    accent: slot.accent
                });
            }
        }
    }
    events.sort(function (a, b) { return a.tick - b.tick; });
    return events;
}
