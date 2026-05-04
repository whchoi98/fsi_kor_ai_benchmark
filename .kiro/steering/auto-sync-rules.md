# Auto-Sync Rules

AGENTS.md와 docs/architecture.md를 코드 변경에 맞춰 동기화해야 하는 규칙.

## AGENTS.md 갱신 트리거

| 변경 대상 | 갱신할 섹션 |
|---|---|
| `fsi_bench.py`의 CLI 인자(`parse_args()`) | "핵심 명령" |
| 새 출력 파일 추가 | "프로젝트 구조"의 `output/` 트리 |
| 새 모듈/스크립트 추가 | 루트 트리와 "핵심 모듈" 표 |
| 새 환경변수 도입 | "기술 스택"의 Auth/region 표 |
| `classify()` 클래스 추가/변경 | "핵심 모듈" 표의 classify 행 |
| 새 ADR/Runbook 작성 | "Reference" 섹션의 하위 목록 |

## docs/architecture.md 갱신 트리거

| 변경 대상 | 갱신할 섹션 |
|---|---|
| `classify()` 클래스 추가/변경 | 분류기 설명·디자인 결정 |
| `--workers`/`--retries`/`--max-tokens`/`--temperature` 기본값 변경 | "Runtime Defaults" 표 |
| 새 컴포넌트 추가 | "Components by Layer" |

## 동시 갱신 규칙

- `classify()` 변경 시 → AGENTS.md + docs/architecture.md **동시** 갱신.
- 새 ADR 작성 시 → AGENTS.md Reference + `.kiro/docs/adr-index.md` 동시 갱신.
- 새 Runbook 작성 시 → AGENTS.md Reference + `.kiro/docs/runbook-index.md` 동시 갱신.
