import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import MuseScore 3.0
import FileIO 3.0

// ============================================================
// 8단계 통합 메모: 이 파일은 stage6/Stage6_PatternRecorder.qml을
// 그대로 복사해 menuPath/description만 정식 배치용으로 바꾼 것이다.
// 로직은 변경하지 않았다(이미 사용자가 직접 테스트해 검증된 상태).
// stage6/ 쪽 원본은 개발 이력 보존을 위해 그대로 남겨둔다.
// ============================================================

// ============================================================
// 6단계 — Pattern Recorder (패턴 편집기) — 읽기 + 쓰기
//
// 기획서/기술 설계서 원칙:
//   "패턴은 코드 이름을 저장하지 않는다. 리듬 정보와 연주 방식만
//    저장한다." 사용자가 빈 트랙에 직접 리듬을 입력하면, 그 리듬을
//    읽어서 이름을 붙여 패턴 라이브러리에 저장한다.
//
// v0.9: 리듬 악보(캔버스)와 버튼 격자가 서로 다른 계산식으로 배치돼서
// 줄이 안 맞는다는 지적을 반영해, 둘을 하나의 스크롤 영역 안에 완전히
// 같은 "칸 너비(slotWidth)" 기준으로 다시 배치했다. 이제 캔버스의
// 동그라미/X와 그 아래 버튼 열이 정확히 세로로 줄맞춰진다. 안내 라벨
// ("패턴 편집 (0.25박 단위...)")은 필요 없어서 제거함.
//
//   - 칸마다 4개 버튼(C/B/M/S)을 가로로 나열하던 걸 세로로 쌓아서
//     전체 너비를 줄임 (스크롤 부담 완화).
//   - C/B/M 버튼 배경색을 캔버스에서 쓰는 색과 맞춤(코드=빨강,
//     베이스=파랑, 뮤트=검정). S(지속)는 캔버스에 따로 그려지는
//     색이 없어(직전 이벤트에 병합되므로) 기본 스타일 그대로 둠.
//   - "파일로 저장" 버튼을 맨 아래 버튼 줄에서 패턴 편집기 바로
//     아래로 옮김.
//   - 버그 수정: 추출 이후 이름/카테고리만 바꾸고 재추출 없이 저장하면,
//     파일명은 새 이름으로 만들어지는데 인덱스에는 recordedPattern.name
//     (마지막 추출 시점 이름)이 그대로 남아 드롭다운에 옛 이름이 계속
//     나오는 문제가 있었다. 저장 시점에 입력창 값으로 항상 최신화하도록 수정.
//
// v0.95: 액센트가 캔버스/미리보기엔 잘 나오는데 실제 악보 쓰기엔
// 반영이 안 되는 버그 수정. 원인: articulation 기호를 지정하는
// 프로퍼티 이름을 "symbolId"로 잘못 씀 (실제로는 "symbol"). 존재하지
// 않는 프로퍼티라 에러도 안 나고 조용히 아무 효과가 없었다.
//
//   - 캔버스 잘림 버그를 마침내 완전히 잡음. Canvas를 감싸는 컨테이너를
//     ColumnLayout 대신 명시적 width를 가진 Column으로 바꾸고, 워밍업
//     그리기도 Qt.callLater로 한 번 더 감쌌다 (ChatGPT가 찾은 해법을
//     반영함 — Canvas의 폭 바인딩이 확정되는 시점과 최초 페인트 시점이
//     어긋나는 문제였던 것으로 보임).
//   - 액센트(>) 토글 버튼을 C/B/M/S 버튼 위에 추가. 베이스/코드/뮤트와
//     완전히 독립적인 토글이라 어떤 타입 위에도 켤 수 있다. 캔버스에도
//     작은 삼각형(>)으로 표시되고, 실제 악보에 쓸 때 accent
//     articulation(articAccentAbove)이 붙는다.
//
// v0.7: 큰 개편.
//   - 캔버스 표기를 슬래시에서 채운 동그라미(●)로 바꿈.
//   - 편집을 "이벤트 목록"이 아니라 "0.25박(16분음표) 간격의 고정
//     격자"로 바꿨다. 각 칸 아래에 코드(C)/베이스(B)/뮤트(M)/지속(S)
//     버튼 4개를 두고, 그 밑에 범례를 한 줄 표시한다.
//     - "지속(S)"은 새 음을 만들지 않고 직전 칸을 그대로 이어서
//       늘린다(서스테인). 직전 칸도 지속이었다면 자연히 그 이전
//       음까지 계속 이어진다.
//   - 뮤트가 한 음이 아니라 코드 전체(운지의 모든 음)를 뮤트하도록 수정.
//
// 사용법 (두 단계):
//   [1. 패턴 추출]
//     1) 빈 트랙(코드 이름 없이)에 1~2마디 정도 리듬을 직접 입력한다.
//        - 음표 한 개(단음) = "베이스" 슬롯
//        - 화음(여러 음 동시에) = "코드" 슬롯
//        - 음표머리를 x(크로스헤드)로 바꾼 음 = "뮤트" 슬롯
//        - 쉼표 = "쉼표" 슬롯
//     2) 그 마디(들)를 선택하고 "패턴 추출" 클릭 -> 리듬만 기억됨
//        (코드 이름은 저장하지 않음)
//     3) "파일로 저장" -> ErayChord/data/patterns/ 폴더에 JSON으로 저장,
//        "저장된 패턴" 드롭다운에서 언제든 "불러오기"로 다시 불러올 수 있음
//
//   [2. 이 패턴 적용]
//     4) 악보에서 실제 코드가 붙어있는 다른 마디 범위를 선택
//        (기타 트랙처럼 코드가 붙어있는 트랙)
//     5) "이 패턴으로 미리보기 생성" 클릭 -> 방금 추출/불러온 패턴을
//        그 코드 진행에 반복 적용해 반주를 미리보기
//     6) "악보에 쓰기" -> 실제로 입력. Ctrl+Z로 되돌리기 가능.
//        뮤트 슬롯은 x 노트헤드 음표로 들어간다.
//
// v0.2 수정 (계속 유효):
//   - tempPath()는 FileIO 타입에 속한 함수라 patternFile.tempPath()로 호출.
//   - note.headGroup === NoteHeadGroup.HEAD_CROSS 로 뮤트 판별.
//
// 지금까지 검증된 것을 재사용한다:
//   - 트랙 필터링, segment/cursor 처리 방식, 마디 n 시작 tick=(n-1)*1920
//   - 패턴 슬롯이 코드 변경 지점보다 길면 그 지점 기준으로 쪼갠다
//     (splitByChordChanges, 5단계에서 검증됨)
//   - addNote(pitch, true) 화음 쌓기 버그는 매번 rewindToTick으로 우회
//   - MU4에서는 Qt.quit() 대신 quit()을 쓴다.
//   - 프로퍼티 이름은 ALL_CAPS를 피한다.
//   - 복잡한 중첩 객체는 property 기본값이 아니라 함수/지역변수로 다룬다.
//
// 한계 (알고 하는 단순화):
//   - 4/4 박자만 가정 (마디 길이 1920 tick 고정).
//   - 플러그인 폴더 경로는 Qt.resolvedUrl(".")를 file:// URL -> 일반
//     경로로 변환해서 얻는다. 이 방식이 모든 OS/설치 환경에서 완벽히
//     검증된 것은 아니라서, 안 되면 알려달라고 요청할 예정.
//   - 뮤트 음표의 실제 피치는 코드의 가장 낮은 현 음을 그대로 쓰고
//     노트헤드만 x로 바꾼다 (연주 정보 표기 목적, 실제 음향에는 영향).
// ============================================================

MuseScore {
    menuPath: "Plugins.ErayChord.Pattern Editor"
    description: "ErayChord 패턴 편집기 — 리듬을 읽어 패턴으로 저장/불러오고, 그 패턴을 다른 마디에 적용합니다."
    version: "0.96"
    requiresScore: true
    pluginType: "dialog"
    width: 680
    height: 980

    property string resultText: "패턴 이름을 입력하고 '패턴 추출'을 눌러주세요."
    property var recordedPattern: null
    property int quarterTicks: 480

    // ---- 화면에서 직접 편집 가능한 패턴 상태 ----
    // v0.7: 실제로 입력된 이벤트 목록 대신, 0.25박(16분음표) 간격의
    // 고정 격자로 다루고 각 칸에 타입(코드/베이스/뮤트/지속/쉼표)을
    // 배정하는 방식으로 바꿨다. editEvents는 이 격자를 압축한 결과다.
    property var patternGrid: []            // [{beat, type}, ...] 0.25박 간격 고정 격자
    property var editEvents: []             // [{beat, type, durationBeats}, ...] (patternGrid를 병합해서 만듦)
    property string editPatternName: ""
    property string editPatternCategory: ""
    property string editTimeSignature: "4/4"
    property int editLengthMeasures: 1
    property real gridStepBeats: 0.25
    property real slotWidth: 34   // 캔버스와 버튼 격자가 공유하는 칸(0.25박) 너비(px)

    // ---- 적용(쓰기) 단계용 상태 ----
    property var applyEvents: []
    property int applyTargetTrack: -1
    property bool applyApplied: false

    // ---- 저장된 패턴 목록(불러오기용) ----
    property var availablePatterns: []      // [{name, file}, ...]
    property var availablePatternNames: []  // 콤보박스 표시용

    FileIO {
        id: patternFile
        onError: function (msg) {
            resultText = "FileIO 오류: " + msg;
        }
    }

    FileIO {
        id: indexFile
        onError: function (msg) {
            // 처음 실행이면 인덱스 파일이 아직 없을 수 있어 조용히 무시
        }
    }

    // ---- file:// URL을 FileIO가 쓸 수 있는 일반 경로 문자열로 변환 ----
    function urlToLocalFile(url) {
        var s = url.toString();
        if (s.indexOf("file:///") === 0) {
            s = s.substring(8);
            if (/^[A-Za-z]:/.test(s)) return s;   // Windows: C:/...
            return "/" + s;                        // Unix: /home/...
        } else if (s.indexOf("file://") === 0) {
            return s.substring(7);
        }
        return s;
    }

    // 이 QML 파일은 ErayChord/stage6/ 안에 있으므로, 상위(ErayChord/)의
    // data/patterns 폴더를 실제 저장/로딩 위치로 쓴다.
    function patternsDir() {
        var dir = urlToLocalFile(Qt.resolvedUrl("."));
        if (dir.charAt(dir.length - 1) === "/") dir = dir.substring(0, dir.length - 1);
        return dir + "/../data/patterns";
    }

    function indexFilePath() {
        return patternsDir() + "/_index.json";
    }

    function sanitizeForFileName(s) {
        // 파일 시스템에서 실제로 문제되는 문자만 치환한다 (한글 등 유니코드는 그대로 유지)
        var safe = (s && s.length > 0) ? s : "untitled";
        safe = safe.replace(/[\\\/:*?"<>|]/g, "_");
        safe = safe.replace(/\s+/g, "_");
        safe = safe.trim();
        if (safe.length === 0) safe = "untitled";
        return safe;
    }

    function safeFileName(category, name) {
        var cat = sanitizeForFileName(category && category.length > 0 ? category : "미분류");
        var nm = sanitizeForFileName(name);
        return "pattern_" + cat + "_" + nm + ".json";
    }

    function readIndex() {
        indexFile.source = indexFilePath();
        var content = "";
        try { content = indexFile.read(); } catch (e) {}
        var idx = { patterns: [] };
        try {
            var parsed = JSON.parse(content);
            if (parsed && parsed.patterns) idx = parsed;
        } catch (e2) {}
        return idx;
    }

    function writeIndex(idx) {
        indexFile.source = indexFilePath();
        indexFile.write(JSON.stringify(idx, null, 2));
    }

    property var patternCategories: []       // 저장된 고유 카테고리 목록
    property var patternsInCategory: []      // 선택된 카테고리 안의 {name, file, category} 목록
    property var patternsInCategoryNames: [] // 콤보박스 표시용

    function refreshAvailablePatterns() {
        var idx = readIndex();
        availablePatterns = idx.patterns;

        var cats = [];
        for (var i = 0; i < idx.patterns.length; i++) {
            var c = idx.patterns[i].category || "미분류";
            if (cats.indexOf(c) === -1) cats.push(c);
        }
        patternCategories = cats;

        var names = [];
        for (var j = 0; j < idx.patterns.length; j++) {
            names.push(idx.patterns[j].name + "  (" + idx.patterns[j].file + ")");
        }
        availablePatternNames = names;

        updatePatternsInCategory(cats.length > 0 ? cats[0] : null);
    }

    function updatePatternsInCategory(category) {
        var list = [];
        for (var i = 0; i < availablePatterns.length; i++) {
            var p = availablePatterns[i];
            var c = p.category || "미분류";
            if (category === null || c === category) list.push(p);
        }
        patternsInCategory = list;

        var names = [];
        for (var j = 0; j < list.length; j++) names.push(list[j].name);
        patternsInCategoryNames = names;
    }

    function loadPatternFromFile(fileName) {
        patternFile.source = patternsDir() + "/" + fileName;
        var content = "";
        try { content = patternFile.read(); } catch (e) {}
        try {
            var parsed = JSON.parse(content);
            editPatternName = parsed.name || "Untitled Pattern";
            editPatternCategory = parsed.category || "미분류";
            editTimeSignature = parsed.timeSignature || "4/4";
            editLengthMeasures = parsed.length || 1;

            var evs = parsed.events ? parsed.events.slice() : [];
            for (var i = 0; i < evs.length; i++) {
                if (evs[i].durationBeats === undefined || evs[i].durationBeats <= 0) {
                    evs[i].durationBeats = gridStepBeats; // 옛 형식 호환 (durationBeats 없던 파일)
                }
                if (evs[i].accent === undefined) evs[i].accent = false; // 옛 형식 호환 (accent 없던 파일)
            }
            patternGrid = buildGridFromEvents(evs, editLengthMeasures); // -> onPatternGridChanged에서 나머지 자동 갱신

            return "=== 패턴 불러오기 완료: " + editPatternName + " ===\n\n" + JSON.stringify(recordedPattern, null, 2);
        } catch (e2) {
            return "패턴 파일을 읽는 중 오류가 발생했습니다.\n경로: " + patternFile.source + "\n오류: " + e2;
        }
    }

    onRun: {
        try {
            refreshAvailablePatterns();
        } catch (err) {
            resultText = "패턴 목록을 불러오는 중 오류: " + err;
        }
    }

    onRecordedPatternChanged: {
        // requestPaint()를 바로 부르면 캔버스 크기(width)가 아직
        // 확정되기 전에 그려져서 처음 한 번은 잘려 보이는 문제가 있었다.
        // Qt.callLater로 한 박자 늦춰서, 현재 이벤트 루프가 다 끝나고
        // 레이아웃/크기가 확정된 뒤에 그리도록 한다.
        Qt.callLater(function () {
            if (patternCanvas) patternCanvas.requestPaint();
        });
    }

    onPatternGridChanged: {
        editEvents = buildEventsFromGrid(patternGrid);
        syncRecordedPatternFromEdits();
    }

    // editEvents(+이름/카테고리/길이)를 하나의 패턴 객체로 합쳐서
    // recordedPattern에 반영한다 (저장/적용/캔버스 미리보기가 전부
    // recordedPattern을 기준으로 동작하므로, 편집할 때마다 호출).
    function syncRecordedPatternFromEdits() {
        recordedPattern = {
            name: editPatternName,
            category: editPatternCategory,
            timeSignature: editTimeSignature,
            length: editLengthMeasures,
            events: editEvents
        };
    }

    // 압축된 이벤트 목록({beat, type, durationBeats}) -> 0.25박 간격의
    // 고정 격자로 펼친다. 각 이벤트의 시작 칸은 그 타입 그대로,
    // 그 뒤로 이어지는 칸들은 "sustain"(지속)으로 채운다.
    function buildGridFromEvents(events, lengthMeasures) {
        var totalSlots = Math.max(1, Math.round(lengthMeasures * 4 / gridStepBeats));
        var grid = [];
        for (var i = 0; i < totalSlots; i++) {
            grid.push({ beat: 1 + i * gridStepBeats, type: "rest", accent: false });
        }

        var sorted = events.slice().sort(function (a, b) { return a.beat - b.beat; });
        for (var e = 0; e < sorted.length; e++) {
            var ev = sorted[e];
            var startIdx = Math.round((ev.beat - 1) / gridStepBeats);
            var dur = (ev.durationBeats === undefined || ev.durationBeats <= 0) ? gridStepBeats : ev.durationBeats;
            var span = Math.max(1, Math.round(dur / gridStepBeats));
            for (var k = 0; k < span; k++) {
                var idx = startIdx + k;
                if (idx < 0 || idx >= grid.length) continue;
                grid[idx].type = (k === 0) ? ev.type : "sustain";
                grid[idx].accent = (k === 0) ? !!ev.accent : false;
            }
        }
        return grid;
    }

    // 고정 격자 -> 압축된 이벤트 목록으로 되돌린다. "sustain" 칸은
    // 새 이벤트를 만들지 않고 직전 이벤트의 길이를 늘린다 (직전이
    // sustain으로 이미 늘어난 상태였다면 그 이전 음까지 자연히 이어짐).
    // 액센트는 이벤트의 "시작 칸"에만 의미가 있으므로, sustain으로
    // 병합될 때는 무시하고 시작 칸의 값만 그대로 가져간다.
    function buildEventsFromGrid(grid) {
        var events = [];
        for (var i = 0; i < grid.length; i++) {
            var slot = grid[i];
            if (slot.type === "sustain" && events.length > 0) {
                events[events.length - 1].durationBeats += gridStepBeats;
            } else {
                var t = (slot.type === "sustain") ? "rest" : slot.type; // 맨 앞이 sustain인 예외 케이스 보호
                events.push({ beat: slot.beat, type: t, durationBeats: gridStepBeats, accent: !!slot.accent });
            }
        }
        return events;
    }

    function updateGridType(idx, newType) {
        var arr = patternGrid.slice();
        if (idx < 0 || idx >= arr.length) return;
        arr[idx] = { beat: arr[idx].beat, type: newType, accent: arr[idx].accent };
        patternGrid = arr;
    }

    // 액센트는 베이스/코드/뮤트와 완전히 독립적인 토글이다 (타입은
    // 그대로 두고 accent만 켜고 끈다).
    function updateGridAccent(idx, newAccent) {
        var arr = patternGrid.slice();
        if (idx < 0 || idx >= arr.length) return;
        arr[idx] = { beat: arr[idx].beat, type: arr[idx].type, accent: newAccent };
        patternGrid = arr;
    }

    // ---- 선택 범위에서 리듬(베이스/코드/쉼표)만 읽기 ----
    function readPatternFromSelection() {
        if (typeof curScore === 'undefined' || curScore === null) return null;

        var startCursor = curScore.newCursor();
        startCursor.rewind(Cursor.SELECTION_START);
        if (!startCursor.segment) return null;

        var track = startCursor.track;
        var startTick = startCursor.segment.tick;
        var startMeasureNo = startCursor.measure.no + 1;

        var endCursor = curScore.newCursor();
        endCursor.rewind(Cursor.SELECTION_END);
        var endMeasureNo = endCursor.segment ? (endCursor.measure.no + 1) : curScore.nmeasures;

        var lengthMeasures = endMeasureNo - startMeasureNo + 1;
        if (lengthMeasures < 1) lengthMeasures = 1;
        var patternEndTick = startTick + lengthMeasures * 1920; // 4/4 가정

        var cursor = curScore.newCursor();
        cursor.track = track;
        cursor.rewind(Cursor.SELECTION_START);

        var events = [];
        var guard = 0;
        while (cursor.segment && cursor.tick < patternEndTick && guard < 500) {
            var el = cursor.element;
            var noteCount = 0;
            var isRest = true;
            var isMuted = false;

            if (el) {
                try {
                    if (el.notes && el.notes.length > 0) {
                        noteCount = el.notes.length;
                        isRest = false;

                        // 음표머리가 전부 x(크로스헤드)면 뮤트(스트로크 뮤트)로 판별
                        var allCross = true;
                        for (var ni = 0; ni < el.notes.length; ni++) {
                            var hg = -1;
                            try { hg = el.notes[ni].headGroup; } catch (eh) {}
                            if (hg !== NoteHeadGroup.HEAD_CROSS) { allCross = false; break; }
                        }
                        isMuted = allCross;
                    }
                } catch (e) {}
            }

            var thisTick = cursor.tick;
            var offsetTicks = thisTick - startTick;
            var beat = (offsetTicks / quarterTicks) + 1;
            var type = isRest ? "rest" : (isMuted ? "mute" : (noteCount === 1 ? "bass" : "chord"));

            cursor.next();
            guard++;

            var nextTick = (cursor.segment && cursor.tick > thisTick) ? cursor.tick : patternEndTick;
            var durationBeats = (nextTick - thisTick) / quarterTicks;
            if (durationBeats <= 0) durationBeats = 1;

            events.push({ beat: beat, type: type, durationBeats: durationBeats });

            if (cursor.tick === thisTick) break; // 안전장치: 더 이상 못 나아가면 중단
        }

        return {
            track: track,
            startMeasureNo: startMeasureNo,
            endMeasureNo: endMeasureNo,
            length: lengthMeasures,
            timeSignature: "4/4",
            events: events
        };
    }

    function extractPattern(category, name) {
        var pat = readPatternFromSelection();
        if (pat === null) {
            resultText = "선택된 영역이 없거나 열려있는 악보가 없습니다.\n리듬을 입력한 마디를 선택한 뒤 다시 실행하세요.";
            recordedPattern = null;
            return;
        }
        if (pat.events.length === 0) {
            resultText = "선택 범위(Track " + pat.track + ")에서 읽을 리듬이 없습니다.";
            recordedPattern = null;
            return;
        }

        editPatternName = (name && name.length > 0) ? name : "Untitled Pattern";
        editPatternCategory = (category && category.length > 0) ? category : "미분류";
        editTimeSignature = pat.timeSignature;
        editLengthMeasures = pat.length;
        patternGrid = buildGridFromEvents(pat.events, pat.length); // -> onPatternGridChanged에서 editEvents/recordedPattern 자동 갱신

        var lines = [];
        lines.push("=== ErayChord 6단계: 패턴 추출 결과 ===");
        lines.push("카테고리: " + editPatternCategory + " / 이름: " + editPatternName);
        lines.push("트랙: " + pat.track + " / 마디 " + pat.startMeasureNo + "~" + pat.endMeasureNo +
                    " (길이 " + pat.length + "마디) / 이벤트 " + pat.events.length + "개");
        lines.push("");
        for (var j = 0; j < pat.events.length; j++) {
            var ev = pat.events[j];
            lines.push("beat " + ev.beat.toFixed(2) + " : " + ev.type + " (길이 " + ev.durationBeats.toFixed(2) + "박)");
        }
        lines.push("");
        lines.push("아래 리듬 악보 미리보기와 격자 편집에서 타입을 직접 바꿀 수 있습니다.");
        lines.push("문제 없어 보이면 '파일로 저장'을 누르세요.");
        resultText = lines.join("\n");
    }

    function saveToFile(category, name) {
        if (!recordedPattern) {
            return "먼저 '패턴 추출'을 눌러서 패턴을 읽어야 합니다.";
        }

        // 저장 시점에 입력창에 있는 이름/카테고리를 항상 최신으로 반영한다.
        // (예전 버그: 추출 이후 이름만 바꾸고 재추출 없이 저장하면,
        //  파일명은 새 이름으로 만들어지는데 인덱스에 적히는 이름은
        //  recordedPattern.name(마지막 추출 시점 이름)을 그대로 써서
        //  드롭다운에 옛날 이름이 계속 나오는 문제가 있었다.)
        editPatternName = (name && name.length > 0) ? name : "Untitled Pattern";
        editPatternCategory = (category && category.length > 0) ? category : "미분류";
        syncRecordedPatternFromEdits();

        var fileName = safeFileName(editPatternCategory, editPatternName);
        var path = patternsDir() + "/" + fileName;

        patternFile.source = path;
        var ok = patternFile.write(JSON.stringify(recordedPattern, null, 2));

        // 인덱스 갱신 (같은 파일명이 이미 있으면 갱신, 없으면 추가)
        var idx = readIndex();
        var existingIdx = -1;
        for (var i = 0; i < idx.patterns.length; i++) {
            if (idx.patterns[i].file === fileName) { existingIdx = i; break; }
        }
        var entry = { name: recordedPattern.name, category: recordedPattern.category, file: fileName };
        if (existingIdx >= 0) idx.patterns[existingIdx] = entry;
        else idx.patterns.push(entry);
        writeIndex(idx);
        refreshAvailablePatterns();

        var lines = [];
        lines.push("=== ErayChord 6단계: 파일로 저장 완료 ===");
        lines.push("");
        lines.push("저장 결과: " + ok);
        lines.push("경로: " + path);
        lines.push("인덱스 갱신: " + indexFilePath());
        lines.push("");
        lines.push("이제 아래 '카테고리 -> 패턴' 목록에서 바로 불러올 수 있습니다.");
        return lines.join("\n");
    }

    // ============================================================
    // 여기부터 "2. 이 패턴 적용" 기능 — 3~5단계에서 검증된 엔진을 재사용
    // ============================================================

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

    function triadPitches(chordName) {
        var parsed = parseChordRoot(chordName);
        if (!parsed) return null;
        var baseOctaveRoot = 48;
        var root = baseOctaveRoot + parsed.pc;
        var third = root + (parsed.isMinor ? 3 : 4);
        var fifth = root + 7;
        return [root, third, fifth];
    }

    function getVoicingLibrary() {
        return {
            "C":  { frets: [-1, 3, 2, 0, 1, 0] },
            "G":  { frets: [3, 2, 0, 0, 0, 3] },
            "Am": { frets: [-1, 0, 2, 2, 1, 0] },
            "F":  { frets: [1, 3, 3, 2, 1, 1] },
            "Dm": { frets: [-1, -1, 0, 2, 3, 1] },
            "G7": { frets: [3, 2, 0, 0, 0, 1] },
            "Em": { frets: [0, 2, 2, 0, 0, 0] }
        };
    }

    function openStringPitches() {
        return [40, 45, 50, 55, 59, 64];
    }

    function voicingToPitches(voicing) {
        var strings = openStringPitches();
        var pitches = [];
        for (var i = 0; i < voicing.frets.length; i++) {
            var fret = voicing.frets[i];
            if (fret === -1) continue;
            pitches.push(strings[i] + fret);
        }
        return pitches;
    }

    function getVoicing(chordName) {
        var lib = getVoicingLibrary();
        if (lib[chordName]) return voicingToPitches(lib[chordName]);
        return triadPitches(chordName);
    }

    // ---- 코드 진행이 있는 "적용 대상" 선택 범위 읽기 ----
    function readTargetChordEvents() {
        if (typeof curScore === 'undefined' || curScore === null) return null;

        var startCursor = curScore.newCursor();
        startCursor.rewind(Cursor.SELECTION_START);
        if (!startCursor.segment) return null;

        var track = startCursor.track;
        var startTick = startCursor.segment.tick;
        var startMeasureNo = startCursor.measure.no + 1;

        var endCursor = curScore.newCursor();
        endCursor.rewind(Cursor.SELECTION_END);
        var endTick, endMeasureNo;
        if (endCursor.segment) {
            endTick = endCursor.segment.tick;
            endMeasureNo = endCursor.measure.no + 1;
        } else {
            endTick = Number.MAX_VALUE;
            endMeasureNo = curScore.nmeasures;
        }
        var inclusiveEndTick = endMeasureNo * 1920;

        var events = [];
        var segment = startCursor.segment;
        while (segment && segment.tick < inclusiveEndTick) {
            var annotations = segment.annotations;
            if (annotations) {
                for (var i = 0; i < annotations.length; i++) {
                    var ann = annotations[i];
                    var annName = "?";
                    try { annName = ann.name; } catch (e) {}
                    var annTrack = -1;
                    try { annTrack = ann.track; } catch (e2) {}
                    if (annName === "Harmony" && annTrack === track) {
                        events.push({ tick: segment.tick, chordName: ann.text, pitches: getVoicing(ann.text) });
                    }
                }
            }
            segment = segment.next;
        }

        applyTargetTrack = track;
        return {
            track: track,
            startTick: startTick,
            endTick: inclusiveEndTick,
            startMeasureNo: startMeasureNo,
            endMeasureNo: endMeasureNo,
            chordEvents: events
        };
    }

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

    // ---- 추출된 패턴(recordedPattern) x 대상 코드 진행 -> 실제 이벤트 생성 ----
    function buildApplyEvents(selInfo, patternObj) {
        var sortedSlots = patternObj.events.slice().sort(function (a, b) { return a.beat - b.beat; });
        var slots = [];
        for (var i = 0; i < sortedSlots.length; i++) {
            var offset = (sortedSlots[i].beat - 1) * quarterTicks;
            var durBeats = sortedSlots[i].durationBeats;
            if (durBeats === undefined || durBeats <= 0) durBeats = 1; // 옛 형식 호환
            var durTicks = durBeats * quarterTicks;
            slots.push({ offset: offset, duration: durTicks, type: sortedSlots[i].type, accent: !!sortedSlots[i].accent });
        }

        var events = [];
        for (var measureNo = selInfo.startMeasureNo; measureNo <= selInfo.endMeasureNo; measureNo++) {
            var measureStartTick = (measureNo - 1) * 1920;
            for (var s = 0; s < slots.length; s++) {
                var slot = slots[s];
                var tick = measureStartTick + slot.offset;
                if (tick < selInfo.startTick || tick >= selInfo.endTick) continue;

                var duration = slot.duration;
                if (tick + duration > selInfo.endTick) duration = selInfo.endTick - tick;
                if (duration <= 0) continue;

                var chunks = splitByChordChanges(tick, duration, selInfo.chordEvents);
                for (var c = 0; c < chunks.length; c++) {
                    var chunk = chunks[c];
                    var chord = findActiveChord(chunk.tick, selInfo.chordEvents);
                    var pitches = null;

                    if (slot.type === "rest") {
                        pitches = null;
                    } else if (slot.type === "mute") {
                        // 뮤트: 한 음이 아니라 코드 전체(운지의 모든 음)를 그대로 쓰되,
                        // 쓰기 단계에서 노트헤드를 전부 x(크로스)로 바꿔서 코드 전체
                        // 뮤트 표기로 만든다.
                        if (chord && chord.pitches && chord.pitches.length > 0) {
                            pitches = chord.pitches.slice();
                        }
                    } else if (chord && chord.pitches && chord.pitches.length > 0) {
                        pitches = (slot.type === "bass") ? [chord.pitches[0]] : chord.pitches;
                    }

                    events.push({
                        tick: chunk.tick,
                        duration: chunk.duration,
                        type: slot.type,
                        chordName: chord ? chord.chordName : null,
                        pitches: pitches,
                        accent: slot.accent
                    });
                }
            }
        }
        events.sort(function (a, b) { return a.tick - b.tick; });
        return events;
    }

    function buildApplyPreview() {
        if (!recordedPattern) {
            return "먼저 위에서 '패턴 추출'을 눌러 패턴을 만들어야 합니다.";
        }
        var selInfo = readTargetChordEvents();
        if (selInfo === null) {
            return "선택된 영역이 없거나 열려있는 악보가 없습니다.\n코드가 붙은 마디를 선택한 뒤 다시 시도하세요.";
        }
        if (selInfo.chordEvents.length === 0) {
            return "선택 범위(Track " + selInfo.track + ")에서 코드 기호를 찾지 못했습니다.";
        }

        var events = buildApplyEvents(selInfo, recordedPattern);
        applyEvents = events;
        applyApplied = false;

        var lines = [];
        lines.push("=== ErayChord 6단계: '" + recordedPattern.name + "' 패턴 적용 미리보기 ===");
        lines.push("대상 트랙: " + selInfo.track + " / 코드 " + selInfo.chordEvents.length + "개 / 이벤트 " + events.length + "개");
        lines.push("");
        for (var i = 0; i < events.length; i++) {
            var ev = events[i];
            var noteStr = "(쉼표/뮤트)";
            if (ev.pitches) {
                var names = [];
                for (var p = 0; p < ev.pitches.length; p++) names.push(ev.pitches[p]);
                noteStr = names.join(" ");
            }
            lines.push("tick " + ev.tick + " (" + ev.type + (ev.accent ? ", accent" : "") + ", 코드=" + (ev.chordName || "-") + ") -> " + noteStr);
        }
        lines.push("");
        lines.push("문제 없어 보이면 '악보에 쓰기'를 누르세요.");
        return lines.join("\n");
    }

    function restCandidateList() {
        return [
            { num: 1, den: 1,  ticks: quarterTicks * 4 },
            { num: 1, den: 2,  ticks: quarterTicks * 2 },
            { num: 1, den: 4,  ticks: quarterTicks },
            { num: 1, den: 8,  ticks: quarterTicks / 2 },
            { num: 1, den: 16, ticks: quarterTicks / 4 },
            { num: 1, den: 32, ticks: quarterTicks / 8 },
            { num: 1, den: 64, ticks: quarterTicks / 16 }
        ];
    }

    function pickDuration(ticks) {
        var candidates = restCandidateList();
        for (var k = 0; k < candidates.length; k++) {
            if (candidates[k].ticks <= ticks) return candidates[k];
        }
        return candidates[candidates.length - 1];
    }

    function fillGapWithRests(cursor, targetTick) {
        var guard = 0;
        while (cursor.segment && cursor.tick < targetTick && guard < 1000) {
            var gap = targetTick - cursor.tick;
            var chosen = pickDuration(gap);
            cursor.setDuration(chosen.num, chosen.den);
            cursor.addRest();
            guard++;
        }
    }

    function applyPatternToScore() {
        if (!applyEvents || applyEvents.length === 0) {
            return "쓸 내용이 없습니다. 먼저 '이 패턴으로 미리보기 생성'을 눌러주세요.";
        }

        var writtenCount = 0;
        var skipped = [];
        var accentCount = 0;
        var accentFailed = [];

        curScore.startCmd();

        var writeCursor = curScore.newCursor();
        writeCursor.track = applyTargetTrack;
        writeCursor.rewind(Cursor.SELECTION_START);

        for (var i = 0; i < applyEvents.length; i++) {
            var pe = applyEvents[i];

            while (writeCursor.segment && writeCursor.tick < pe.tick) writeCursor.next();
            if (writeCursor.segment && writeCursor.tick > pe.tick) {
                writeCursor.prev();
                if (writeCursor.tick < pe.tick) fillGapWithRests(writeCursor, pe.tick);
            }
            if (!writeCursor.segment || writeCursor.tick !== pe.tick) {
                var reachedTick = writeCursor.segment ? writeCursor.tick : "없음";
                skipped.push("tick " + pe.tick + " (" + pe.type + ", 도달=" + reachedTick + ")");
                continue;
            }

            var durInfo = pickDuration(pe.duration);
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

                // 뮤트 슬롯은 방금 넣은 음표의 노트헤드를 x(크로스)로 바꾼다.
                if (pe.type === "mute") {
                    try {
                        writeCursor.rewindToTick(pe.tick);
                        var chordEl = writeCursor.element;
                        if (chordEl && chordEl.notes) {
                            for (var mi = 0; mi < chordEl.notes.length; mi++) {
                                chordEl.notes[mi].headGroup = NoteHeadGroup.HEAD_CROSS;
                            }
                        }
                    } catch (eh) {}
                }

                // 액센트가 켜져 있으면 실제 accent articulation을 붙인다.
                // (베이스/코드/뮤트와 독립적인 표시라, 타입과 무관하게 처리)
                if (pe.accent) {
                    try {
                        writeCursor.rewindToTick(pe.tick);
                        var artic = newElement(Element.ARTICULATION);
                        // 문자열("articAccentAbove")로 대입하면 조용히 실패하는 것으로
                        // 보여, NoteHeadGroup.HEAD_CROSS와 같은 방식으로 enum 값 자체를
                        // 참조하도록 변경 (SymId 전역 enum이 플러그인에 노출되어 있음).
                        try {
                            artic.symbol = SymId.articAccentAbove;
                        } catch (esym) {
                            artic.symbol = "articAccentAbove"; // 혹시 enum이 없으면 문자열로 폴백
                        }
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
        applyApplied = true;

        var lines = [];
        lines.push("=== ErayChord 6단계: 악보에 쓰기 완료 ===");
        lines.push("");
        lines.push("입력된 이벤트 수: " + writtenCount + " / " + applyEvents.length);
        lines.push("액센트 적용: " + accentCount + "개");
        if (skipped.length > 0) {
            lines.push("");
            lines.push("건너뛴 항목:");
            for (var j = 0; j < skipped.length; j++) lines.push("  - " + skipped[j]);
        }
        if (accentFailed.length > 0) {
            lines.push("");
            lines.push("액센트 적용 실패:");
            for (var k = 0; k < accentFailed.length; k++) lines.push("  - " + accentFailed[k]);
        }
        lines.push("");
        lines.push("악보를 확인하세요. 마음에 안 들면 Ctrl+Z로 한 번에 되돌릴 수 있습니다.");
        return lines.join("\n");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: "ErayChord — Pattern Editor"
            font.bold: true
            font.pixelSize: 16
        }

        Label { text: "1. 패턴 추출 (빈 트랙에 리듬을 입력하고 선택 후 실행)"; font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "카테고리" }
            TextField {
                id: categoryField
                Layout.preferredWidth: 140
                placeholderText: "예: 고고"
                text: "고고"
            }

            Label { text: "패턴 이름" }
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "예: 고고1"
                text: "고고1"
            }

            Button {
                text: "패턴 추출"
                onClicked: {
                    try {
                        extractPattern(categoryField.text, nameField.text);
                    } catch (err) {
                        var msg = "!!! 오류 발생 !!!\n\n";
                        try { msg += "message: " + err.message + "\n"; } catch (e1) {}
                        try { msg += "전체: " + err + "\n"; } catch (e2) {}
                        resultText = msg;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "카테고리" }
            ComboBox {
                id: categoryCombo
                Layout.preferredWidth: 140
                model: patternCategories
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < patternCategories.length) {
                        updatePatternsInCategory(patternCategories[currentIndex]);
                    }
                }
            }

            Label { text: "패턴" }
            ComboBox {
                id: patternInCategoryCombo
                Layout.fillWidth: true
                model: patternsInCategoryNames
            }

            Button {
                text: "불러오기"
                enabled: patternsInCategory.length > 0
                onClicked: {
                    try {
                        var idx = patternInCategoryCombo.currentIndex;
                        if (idx >= 0 && idx < patternsInCategory.length) {
                            var entry = patternsInCategory[idx];
                            resultText = loadPatternFromFile(entry.file);
                            categoryField.text = entry.category || "미분류";
                            nameField.text = entry.name;
                        }
                    } catch (err) {
                        resultText = "!!! 불러오기 오류 !!!\n\n" + err;
                    }
                }
            }

            Button {
                text: "목록 새로고침"
                onClicked: {
                    try {
                        refreshAvailablePatterns();
                    } catch (err) {
                        resultText = "!!! 목록 새로고침 오류 !!!\n\n" + err;
                    }
                }
            }
        }

        Label { text: "리듬 악보 미리보기 (선 위 = 코드, 선 아래 = 베이스, X = 뮤트) — 아래 버튼과 칸 위치가 그대로 맞춰집니다" }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
            clip: true

            Column {
                spacing: 2
                width: Math.max(patternGrid.length * slotWidth, 50)

                Canvas {
                    id: patternCanvas
                    width: Math.max(patternGrid.length * slotWidth, 50)
                    height: 110

                    // 패턴 길이가 바뀌면 캔버스 너비도 바뀌는데, 그 크기 변경이
                    // 실제로 적용되기 전에 첫 그리기가 일어나면 잘려 보이는
                    // 문제가 있었다. width가 바뀔 때마다 다시 그리도록 해서 해결.
                    onWidthChanged: requestPaint()

                    // 캔버스가 생성되자마자(패턴이 아직 없는 빈 상태에서) 한 번
                    // 미리 그려서 "워밍업"해둔다. 그래야 실제로 패턴을 처음
                    // 추출/불러올 때 캔버스가 이미 정상 상태라 바로 잘림 없이
                    // 그려진다 (캔버스가 태어나서 처음 그리는 순간 자체에
                    // 크기 확정 타이밍 문제가 있었던 것으로 보임).
                    Component.onCompleted: Qt.callLater(function(){ requestPaint(); })

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);

                        var midY = height / 2;

                        // 기준선은 패턴 유무와 상관없이 항상 먼저 그린다
                        // (버튼 격자와 같은 slotWidth 기준으로 그려서 아래
                        // 버튼 열과 정확히 줄맞춤되도록 한다)
                        ctx.strokeStyle = "#999999";
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(0, midY);
                        ctx.lineTo(width, midY);
                        ctx.stroke();

                        var pat = recordedPattern;
                        if (!pat || !pat.events || pat.events.length === 0) {
                            ctx.fillStyle = "#999";
                            ctx.font = "12px sans-serif";
                            ctx.fillText("(추출하거나 불러온 패턴이 없습니다)", 10, height / 2 - 20);
                            return;
                        }
                        var sorted = pat.events.slice().sort(function (a, b) { return a.beat - b.beat; });

                        for (var i = 0; i < sorted.length; i++) {
                            var ev = sorted[i];
                            var slotIdx = Math.round((ev.beat - 1) / gridStepBeats);
                            var x = slotIdx * slotWidth + slotWidth / 2;

                            if (ev.type === "bass") {
                                ctx.fillStyle = "#2255aa";
                                ctx.beginPath();
                                ctx.arc(x, midY + 18, 6, 0, Math.PI * 2);
                                ctx.fill();
                            } else if (ev.type === "chord") {
                                ctx.fillStyle = "#aa2222";
                                ctx.beginPath();
                                ctx.arc(x, midY - 18, 6, 0, Math.PI * 2);
                                ctx.fill();
                            } else if (ev.type === "mute") {
                                ctx.strokeStyle = "#333333";
                                ctx.lineWidth = 2.5;
                                ctx.beginPath();
                                ctx.moveTo(x - 7, midY - 25);
                                ctx.lineTo(x + 7, midY - 11);
                                ctx.moveTo(x + 7, midY - 25);
                                ctx.lineTo(x - 7, midY - 11);
                                ctx.stroke();
                            }
                            // rest는 표시 안 함 (빈 칸)

                            // 액센트: 코드/베이스/뮤트 위에 작은 ">" 삼각형 표시
                            // (베이스/코드/뮤트와 독립적인 별도 표기)
                            if (ev.accent && ev.type !== "rest") {
                                var accentY = (ev.type === "bass") ? midY + 18 - 15 : midY - 18 - 15;
                                ctx.fillStyle = "#e8a800";
                                ctx.beginPath();
                                ctx.moveTo(x - 5, accentY - 4);
                                ctx.lineTo(x + 5, accentY);
                                ctx.lineTo(x - 5, accentY + 4);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }
                }

                RowLayout {
                    spacing: 0

                    Repeater {
                        model: patternGrid.length
                        delegate: ColumnLayout {
                            Layout.preferredWidth: slotWidth
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 1

                            // 액센트: 베이스/코드/뮤트와 완전히 독립적인 토글.
                            // 어떤 타입 위에도 켤 수 있다 (코드에 액센트,
                            // 베이스에 액센트 등).
                            Button {
                                id: btnAccent
                                text: ">"
                                checkable: true
                                checked: patternGrid[index].accent === true
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: slotWidth - 6
                                implicitHeight: 16
                                font.pixelSize: 9
                                font.bold: true
                                background: Rectangle {
                                    color: btnAccent.checked ? "#e8a800" : "#e0e0e0"
                                    radius: 3
                                }
                                contentItem: Text {
                                    text: btnAccent.text
                                    color: btnAccent.checked ? "white" : "#888"
                                    font: btnAccent.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onToggled: updateGridAccent(index, checked)
                            }

                            Button {
                                id: btnC
                                text: "C"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: slotWidth - 6
                                implicitHeight: 20
                                font.pixelSize: 9
                                highlighted: patternGrid[index].type === "chord"
                                background: Rectangle { color: "#aa2222"; radius: 3 }
                                contentItem: Text {
                                    text: btnC.text
                                    color: "white"
                                    font: btnC.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: updateGridType(index, "chord")
                            }
                            Button {
                                id: btnB
                                text: "B"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: slotWidth - 6
                                implicitHeight: 20
                                font.pixelSize: 9
                                highlighted: patternGrid[index].type === "bass"
                                background: Rectangle { color: "#2255aa"; radius: 3 }
                                contentItem: Text {
                                    text: btnB.text
                                    color: "white"
                                    font: btnB.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: updateGridType(index, "bass")
                            }
                            Button {
                                id: btnM
                                text: "M"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: slotWidth - 6
                                implicitHeight: 20
                                font.pixelSize: 9
                                highlighted: patternGrid[index].type === "mute"
                                background: Rectangle { color: "#333333"; radius: 3 }
                                contentItem: Text {
                                    text: btnM.text
                                    color: "white"
                                    font: btnM.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: updateGridType(index, "mute")
                            }
                            Button {
                                text: "S"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: slotWidth - 6
                                implicitHeight: 20
                                font.pixelSize: 9
                                highlighted: patternGrid[index].type === "sustain"
                                onClicked: updateGridType(index, "sustain")
                            }

                            Label {
                                text: patternGrid[index].beat.toFixed(2)
                                font.pixelSize: 8
                                Layout.alignment: Qt.AlignHCenter
                                color: "#777"
                            }
                        }
                    }
                }
            }
        }

        Label {
            text: "범례: > = 액센트(베이스/코드/뮤트와 독립적인 토글, 노란색이면 켜짐)  ·  C = 코드(선 위 ●, 빨강)  ·  B = 베이스(선 아래 ●, 파랑)  ·  M = 뮤트(코드 전체를 X 표기, 검정)  ·  S = 지속(바로 이전 음을 이어서 서스테인 — 이전이 지속이었으면 그 이전 음까지 계속 이어짐)"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: 11
            color: "#555"
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Button {
                text: "파일로 저장"
                enabled: recordedPattern !== null
                onClicked: {
                    try {
                        resultText = saveToFile(categoryField.text, nameField.text);
                    } catch (err) {
                        var msg = "!!! 저장 중 오류 발생 !!!\n\n";
                        try { msg += "message: " + err.message + "\n"; } catch (e1) {}
                        resultText = msg;
                    }
                }
            }
        }

        Label { text: "2. 이 패턴 적용 (코드가 붙은 다른 마디를 선택하고 실행)"; font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: recordedPattern ? ("추출된 패턴: " + recordedPattern.name) : "(아직 추출된 패턴 없음)"
            }

            Button {
                text: "이 패턴으로 미리보기 생성"
                enabled: recordedPattern !== null
                onClicked: {
                    try {
                        resultText = buildApplyPreview();
                    } catch (err) {
                        var msg = "!!! 오류 발생 !!!\n\n";
                        try { msg += "message: " + err.message + "\n"; } catch (e1) {}
                        try { msg += "전체: " + err + "\n"; } catch (e2) {}
                        resultText = msg;
                    }
                }
            }
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
                text: applyApplied ? "다시 쓰기" : "악보에 쓰기"
                enabled: applyEvents.length > 0
                onClicked: {
                    try {
                        resultText = applyPatternToScore();
                    } catch (err) {
                        var msg = "!!! 쓰기 중 오류 발생 !!!\n\n";
                        try { msg += "message: " + err.message + "\n"; } catch (e1) {}
                        resultText = msg;
                    }
                }
            }

            Button {
                text: "닫기"
                onClicked: (typeof(quit) === "undefined" ? Qt.quit : quit)()
            }
        }
    }
}
