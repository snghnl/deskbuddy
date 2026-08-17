# DeskBuddy

macOS용 플로팅 todo 캐릭터. 화면에 항상 떠 있는 캐릭터를 클릭하면 todo 리스트가 펼쳐진다. 모든 Spaces와 풀스크린 앱 위에서도 보인다.

## 빌드 & 실행

```sh
./make-app.sh          # build/DeskBuddy.app 생성
open build/DeskBuddy.app
```

개발 중에는 `swift run`으로 바로 실행할 수 있다.

## 기능

- **캐릭터 3종 + 커스텀**: 슬라임·유령·고양이 중 선택하거나, 이미지를 추가해 나만의 캐릭터로 사용 (설정에서 이름 지정·변경 가능).
  내장 캐릭터는 눈 깜빡임·표정 변화 지원, 남은 할 일 개수 뱃지 표시
- **클릭 → 리스트 토글**: 캐릭터를 클릭하면 옆에 todo 리스트 패널이 열리고, 드래그하면 캐릭터가 이동 (리스트도 따라옴)
- **던지기**: 캐릭터를 잡고 휙 놓으면 관성으로 날아가 화면 가장자리에 튕기다 착지. 날아가는 중에 클릭하면 잡아챌 수 있음 (설정에서 끄기 가능)
- **글로벌 단축키**: 설정에서 단축키를 등록하면 어느 앱에서든 목록을 열고 바로 입력 (Carbon 핫키 — 접근성 권한 불필요)
- **설정 창**: 캐릭터 선택/추가, 던지기·자유 이동 토글, 단축키 등록 (우클릭 메뉴 또는 메뉴바 → 설정…)
- **우클릭 메뉴**: 목록 열기/닫기, 자유롭게 돌아다니기 토글, 제자리로 보내기, 설정, 캐릭터 숨기기, 종료 (control-클릭도 동일)
- **자유 이동**: 켜면 화면 안에서 스스로 목표 지점을 골라 걸어다니고 잠깐씩 쉰다. 진행 방향으로 몸을 돌리고 통통 튀는 걸음 모션.
  목록이 열려 있거나, 캐릭터를 잡고 있거나, 우클릭 메뉴가 떠 있는 동안에는 멈춘다
- **항상 위**: `NSPanel` + `.floating` 레벨, 모든 Spaces·풀스크린 위에 표시
- **비활성화 패널**: 클릭해도 현재 작업 중인 앱의 포커스를 뺏지 않음 (`.nonactivatingPanel`)
- 할 일 추가(Enter), 체크, 호버 시 X로 삭제, 드래그로 순서 변경
- **할 일 / 완료 / 달력 탭**: 체크한 항목은 완료 탭으로 이동해 날짜별(오늘/어제/…)로 최신순 그룹핑, 완료 시각 표시.
  메뉴의 '완료 기록 비우기'(2단계 확인)로 일괄 삭제. 목록이 떠 있을 때 ⌘1/⌘2/⌘3 으로 탭 전환
- **달력 탭**: 월 그리드에 완료 히트맵(많이 한 날일수록 진하게) + 일정 있는 날 점 표시.
  날짜를 누르면 그날의 일정과 완료 항목을 함께 보여줌
- **캘린더 연동 (EventKit)**: macOS 캘린더에 연결된 계정(구글 포함)의 일정을 읽음 — OAuth 불필요.
  오늘 일정에는 "진행 중"/"N분 후" 뱃지. 연동·표시 설정은 설정 창의 '연동' 섹션에서
- **일정 알림 (말풍선)**: 일정 시작 5/10/15/30분 전(설정 가능)에 캐릭터 머리 위에 말풍선으로 알림.
  클릭할 때까지 유지되고, 캐릭터를 끌거나 배회 중에도 따라다님. 일정당 한 번만 알림
- **추가 시점 툴팁**: 항목에 마우스를 올리면 "8월 9일 오후 2:30 추가 · 3시간 전" 형태로 표시
- **상세 페이지**: 항목 제목을 클릭하면 상세로 진입 — 제목 수정, 추가 시각(절대+상대), 메모 작성
- 캐릭터 위치는 재시작 후에도 기억
- 메뉴바 체크리스트 아이콘: 캐릭터 보이기/숨기기, 종료 (Dock 아이콘 없음)
- 데이터: `~/Library/Application Support/DeskBuddy/todos.json` (300ms 디바운스 자동 저장)

## 로그인 시 자동 시작

시스템 설정 → 일반 → 로그인 항목에 `build/DeskBuddy.app` 추가.

## 구조

- `Sources/DeskBuddy/App.swift` — 진입점, 캐릭터/리스트 패널(NSPanel 서브클래스), 클릭·드래그·던지기 구분, 메뉴바, 설정 창, 위치 저장
- `Sources/DeskBuddy/CharacterView.swift` — 캐릭터 3종 드로잉(Shape) + 애니메이션, 커스텀 이미지 렌더링
- `Sources/DeskBuddy/CustomCharacters.swift` — 커스텀 캐릭터 이미지 관리 + 이름 매핑 + 이미지 캐시
- `Sources/DeskBuddy/WanderController.swift` — 자유 이동 (목표 지점 선정 → 이동 → 휴식 루프)
- `Sources/DeskBuddy/ThrowController.swift` — 던지기 물리 (중력·반발·마찰)
- `Sources/DeskBuddy/HotKeyCenter.swift` — Carbon 글로벌 단축키
- `Sources/DeskBuddy/SettingsView.swift` — 설정 화면 (캐릭터 선택·토글·단축키 녹화)
- `Sources/DeskBuddy/Bubble.swift` — 말풍선 패널 + 일정 알림 감시 (EventNotifier)
- `Sources/DeskBuddy/CalendarService.swift` — EventKit 연동 (권한·일정 조회·변경 감지)
- `Sources/DeskBuddy/CalendarView.swift` — 달력 탭 (월 그리드 히트맵 + 일정/완료 목록)
- `Sources/DeskBuddy/TodoListView.swift` — 리스트(할 일/완료/달력 탭) + 상세 페이지 UI
- `Sources/DeskBuddy/TodoStore.swift` — 모델 + JSON 영속화
