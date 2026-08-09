# DeskBuddy

macOS용 플로팅 todo 캐릭터. 화면에 항상 떠 있는 슬라임 캐릭터를 클릭하면 todo 리스트가 펼쳐진다. 모든 Spaces와 풀스크린 앱 위에서도 보인다.

## 빌드 & 실행

```sh
./make-app.sh          # build/DeskBuddy.app 생성
open build/DeskBuddy.app
```

개발 중에는 `swift run`으로 바로 실행할 수 있다.

## 기능

- **캐릭터**: 눈 깜빡임·둥실거림 애니메이션이 있는 슬라임. 남은 할 일 개수 뱃지 표시, 리스트가 열리면 표정이 바뀜
- **클릭 → 리스트 토글**: 캐릭터를 클릭하면 옆에 todo 리스트 패널이 열리고, 드래그하면 캐릭터가 이동 (리스트도 따라옴)
- **항상 위**: `NSPanel` + `.floating` 레벨, 모든 Spaces·풀스크린 위에 표시
- **비활성화 패널**: 클릭해도 현재 작업 중인 앱의 포커스를 뺏지 않음 (`.nonactivatingPanel`)
- 할 일 추가(Enter), 체크(완료 시 목록 아래로), 호버 시 X로 삭제, 메뉴에서 완료 항목 일괄 정리
- **추가 시점 툴팁**: 항목에 마우스를 올리면 "8월 9일 오후 2:30 추가 · 3시간 전" 형태로 표시
- **상세 페이지**: 항목 제목을 클릭하면 상세로 진입 — 제목 수정, 추가 시각(절대+상대), 메모 작성
- 캐릭터 위치는 재시작 후에도 기억
- 메뉴바 체크리스트 아이콘: 캐릭터 보이기/숨기기, 종료 (Dock 아이콘 없음)
- 데이터: `~/Library/Application Support/DeskBuddy/todos.json` (300ms 디바운스 자동 저장)

## 로그인 시 자동 시작

시스템 설정 → 일반 → 로그인 항목에 `build/DeskBuddy.app` 추가.

## 구조

- `Sources/DeskBuddy/App.swift` — 진입점, 캐릭터/리스트 패널(NSPanel 서브클래스), 클릭·드래그 구분, 메뉴바, 위치 저장
- `Sources/DeskBuddy/CharacterView.swift` — 슬라임 캐릭터 (Shape 직접 드로잉 + 애니메이션)
- `Sources/DeskBuddy/TodoListView.swift` — 리스트 + 상세 페이지 UI
- `Sources/DeskBuddy/TodoStore.swift` — 모델 + JSON 영속화
