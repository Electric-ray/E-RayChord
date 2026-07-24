.pragma library

// ============================================================
// VoicingEngine.js
//
// 역할: 코드 이름(예: "C")에 해당하는 기타 운지를 운지 라이브러리에서
//   가져와 실제 음(피치, MIDI 노트번호) 배열로 변환한다.
//
// 설계 원칙(개발순서.txt): VoicingEngine은 Pattern이 무엇인지 몰라야 한다.
//   이 파일은 MuseScore API도, 패턴도 전혀 참조하지 않는 순수 데이터 모듈이다.
//   실제 JSON 파일 읽기(FileIO)는 plugin.qml이 담당하고, 이미 파싱된
//   라이브러리 객체만 이 모듈에 전달한다.
//
// 라이브러리 형식(예, data/voicings/open_chords.json과 동일):
//   { "C": [ { "name": "Open", "frets": [-1,3,2,0,1,0], "default": true } ], ... }
//   frets는 낮은 E현 -> 높은 e현 순서, 뮤트=-1, 개방현=0.
// ============================================================

function openStringPitches() {
    return [40, 45, 50, 55, 59, 64]; // E2 A2 D3 G3 B3 E4 (표준 튜닝 고정)
}

function frettedPitches(frets) {
    var strings = openStringPitches();
    var pitches = [];
    for (var i = 0; i < frets.length; i++) {
        if (frets[i] === -1) continue;
        pitches.push(strings[i] + frets[i]);
    }
    return pitches;
}

// 기본 제공 라이브러리(builtinLib)와 사용자 라이브러리(userLib, 7단계
// 운지 편집기가 저장한 것)를 코드 이름 기준으로 합친다.
function mergeLibraries(builtinLib, userLib) {
    var merged = {};
    var chord;
    if (builtinLib) {
        for (chord in builtinLib) merged[chord] = builtinLib[chord].slice();
    }
    if (userLib) {
        for (chord in userLib) {
            if (!merged[chord]) merged[chord] = [];
            merged[chord] = merged[chord].concat(userLib[chord]);
        }
    }
    return merged;
}

// voicingName이 주어지면 그 이름을 우선 찾고, 없으면 기본(default) 운지,
// 그것도 없으면 목록의 첫 운지를 쓴다.
function pickVoicing(mergedLib, chordName, voicingName) {
    var list = mergedLib[chordName];
    if (!list || list.length === 0) return null;
    if (voicingName) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === voicingName) return list[i];
        }
    }
    for (var j = 0; j < list.length; j++) {
        if (list[j].default) return list[j];
    }
    return list[0];
}

function parseChordRoot(name) {
    var m = name.match(/^([A-G])([#b]?)/);
    if (!m) return null;
    var letterToPc = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
    var pc = letterToPc[m[1]];
    if (m[2] === "#") pc += 1;
    if (m[2] === "b") pc -= 1;
    pc = ((pc % 12) + 12) % 12;
    var rest = name.substring(m[0].length);
    var isMinor = (rest.indexOf("m") === 0 && rest.indexOf("maj") !== 0);
    return { pc: pc, isMinor: isMinor };
}

// 라이브러리에 없는 코드에 대한 폴백: 3화음(triad)을 계산해서 반환한다.
// (개발순서 2단계 MVP에서부터 쓰던 폴백을 그대로 재사용)
function triadPitches(chordName) {
    var parsed = parseChordRoot(chordName);
    if (!parsed) return null;
    var baseOctaveRoot = 48;
    var root = baseOctaveRoot + parsed.pc;
    var third = root + (parsed.isMinor ? 3 : 4);
    var fifth = root + 7;
    return [root, third, fifth];
}

// 코드 이름 -> 실제 피치 배열 (라이브러리 우선, 없으면 triad 폴백)
function getVoicingPitches(mergedLib, chordName, voicingName) {
    var v = pickVoicing(mergedLib, chordName, voicingName);
    if (v) return frettedPitches(v.frets);
    return triadPitches(chordName);
}
