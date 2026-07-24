.pragma library

// ============================================================
// PatternEngine.js
//
// 역할: 패턴 라이브러리(JSON)에서 선택한 주법을 Pattern 객체로 다루기
//   위한 순수 데이터 유틸리티. 실제 파일 목록/내용 읽기는 plugin.qml의
//   FileIO가 담당하고, 이 모듈은 그 결과를 정리/보정하는 역할만 한다.
//
// 설계 원칙(개발순서.txt): PatternEngine은 Voicing이 무엇인지 몰라야 한다.
//   여기서는 코드 이름이나 운지 정보를 전혀 다루지 않는다.
//
// Pattern 형식(예, data/patterns/gogo_basic.json과 동일):
//   { "name": "GoGo Basic", "timeSignature": "4/4", "length": 1,
//     "events": [ { "beat": 1, "type": "bass", "durationBeats": 1,
//                   "accent": false }, ... ] }
//   type: "bass" | "chord" | "mute" | "rest"
// ============================================================

// 기본 제공 패턴 목록(builtinIndex.patterns)과 사용자가 6단계(패턴 편집기)로
// 저장한 패턴 목록(userIndex.patterns)을 하나의 콤보박스용 목록으로 합친다.
function combinePatternLists(builtinIndex, userIndex) {
    var out = [];
    var builtinList = (builtinIndex && builtinIndex.patterns) ? builtinIndex.patterns : [];
    var userList = (userIndex && userIndex.patterns) ? userIndex.patterns : [];

    for (var i = 0; i < builtinList.length; i++) {
        var b = builtinList[i];
        out.push({ name: b.name, category: b.category || "기본 제공", file: b.file, builtin: true });
    }
    for (var j = 0; j < userList.length; j++) {
        var u = userList[j];
        out.push({ name: u.name, category: u.category || "미분류", file: u.file, builtin: false });
    }
    return out;
}

// 옛 형식 호환: durationBeats/accent가 없는 이벤트를 보정한다.
function normalizeEvents(events, gridStepBeats) {
    var step = gridStepBeats || 1;
    var evs = events ? events.slice() : [];
    for (var i = 0; i < evs.length; i++) {
        if (evs[i].durationBeats === undefined || evs[i].durationBeats <= 0) {
            evs[i].durationBeats = step;
        }
        if (evs[i].accent === undefined) evs[i].accent = false;
    }
    return evs;
}
