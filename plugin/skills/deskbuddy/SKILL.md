---
name: deskbuddy
description: >
  DeskBuddy(macOS 화면 위 플로팅 캐릭터)로 사용자에게 말풍선 알림을 보내고 할 일을 관리한다.
  다음 상황에서 사용한다: (1) 오래 걸린 작업(빌드·테스트·마이그레이션·배포·긴 분석)이 끝나
  사용자에게 결과를 알릴 때 (2) 사용자가 "알려줘", "리마인드해줘", "deskbuddy" 를 언급할 때
  (3) 사용자의 할 일을 추가·조회·완료 처리할 때 ("할 일 추가해줘", "내 할 일 뭐 있지",
  "이거 완료 처리해줘"). macOS 전용.
---

# DeskBuddy 연동

DeskBuddy 는 화면 위에 항상 떠 있는 캐릭터 앱이다. CLI 로 말풍선 알림을 보내거나
할 일을 관리할 수 있고, 사용자는 어떤 앱을 쓰고 있든 캐릭터를 통해 즉시 확인한다.

## CLI 위치

1. `command -v deskbuddy` — PATH 에 있으면 그걸 사용
2. 없으면 이 스킬이 설치된 플러그인의 `scripts/deskbuddy` 사용
   (이 SKILL.md 기준 `../../scripts/deskbuddy`)
3. 둘 다 없으면 DeskBuddy 앱이 설치되지 않은 것 — 사용자에게
   https://github.com/snghnl/deskbuddy 안내

## 명령

```sh
deskbuddy notify "메시지"               # 말풍선 (사용자가 클릭할 때까지 유지)
deskbuddy notify "메시지" --autohide 8   # 8초 후 자동 닫힘 (가벼운 알림용)
deskbuddy add "제목"                     # 할 일 추가
deskbuddy add "제목" --memo "설명"       # 메모와 함께 추가
deskbuddy list                           # 남은 할 일 (id 앞자리 + 제목)
deskbuddy list --json                    # 전체 데이터 JSON (파싱용)
deskbuddy done <id앞자리|제목 일부>       # 완료 처리
deskbuddy toggle                         # 할 일 목록 패널 열기/닫기
```

앱이 꺼져 있어도 명령을 보내면 자동으로 실행된다 (list 제외 — list 는 데이터 파일을
직접 읽으므로 앱 실행 여부와 무관).

## 사용 지침

- **작업 완료 보고**: 사용자가 자리를 비웠을 수 있는 긴 작업(수 분 이상)이 끝나면
  `notify` 로 핵심 결과를 알린다. 예: `deskbuddy notify "✅ 마이그레이션 완료 — 37개 파일, 테스트 통과"`
- **실패·확인 필요**: 작업이 실패했거나 사용자 판단이 필요하면 autohide 없이 보낸다
  (클릭 전까지 유지되므로 놓치지 않는다). 예: `deskbuddy notify "⚠️ 배포 실패 — 로그 확인 필요"`
- **가벼운 진행 알림**: 중간 진행 상황은 `--autohide 8` 로 보내 방해를 줄인다.
- **메시지는 짧고 구체적으로**: 한 줄 요약 + 필요한 다음 행동. 긴 로그를 넣지 않는다.
- **할 일 처리 플로우**: `list` 로 확인 → 작업 수행 → `done <id>` → `notify` 로 보고.
  `done` 은 제목 일부로도 매칭되지만 여러 개가 걸리면 실패하므로 id 앞자리를 우선 사용한다.
- **남용 금지**: 모든 턴마다 notify 하지 않는다. 사용자가 터미널을 보고 있는 짧은
  대화형 작업에서는 불필요하다.
