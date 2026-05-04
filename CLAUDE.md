# CLAUDE.md — fsi-kor-ai-benchmark

> Claude Code의 프로젝트 진입점. 이 파일을 먼저 읽고 작업을 시작하세요.
> Entry point for Claude Code. Read this first before working in this repo.

## 한 줄 요약 / TL;DR

AWS Bedrock 위에서 한국어 LLM의 **모델 교체 전후 안전성(jailbreak) 회귀**를 자동 검증하는
A/B 벤치마크 러너. 입력은 JailbreakBench(KR) 300건, 산출물은 FSI 제출 스키마에 맞춘 JSONL + 비교 리포트.

A/B safety regression harness for Korean LLMs on Amazon Bedrock. Runs the
JailbreakBench (KR) 300-prompt dataset against a "before" and "after" model
and produces an FSI-compliant submission package + comparison report.

## 기술 스택 / Tech Stack

| Area | Choice |
|---|---|
| Language | Python 3.9+ (single-file CLI: `fsi_bench.py`) |
| Entry point | `run_benchmark.sh` — interactive bash wrapper |
| Cloud | Amazon Bedrock (`bedrock-runtime` via `boto3`) |
| Auth | `AWS_BEARER_TOKEN_BEDROCK` (preferred) or standard IAM creds |
| Default region | `ap-northeast-2` |
| Dataset | `doc/jailbreakbench.jsonl` — 300 Korean jailbreak prompts (read-only) |
| Output schema | FSI submission format — `모델변경전.jsonl` / `모델변경후.jsonl` |

## 프로젝트 구조 / Layout

```text
.
├── fsi_bench.py        # Python CLI runner — Bedrock invocation, retry, classify, report
├── run_benchmark.sh    # Interactive shell entrypoint (preset menu, smoke test, --quick/--report/--submit)
├── doc/                # READ-ONLY spec — never write here
│   ├── jailbreakbench.jsonl   # 300 input prompts
│   └── output_format/         # Submission skeleton (placeholder JSONL)
├── output/             # WRITABLE — all generated artifacts land here
│   ├── 모델변경전.jsonl / 모델변경후.jsonl   # The two FSI deliverables
│   ├── *.metadata.jsonl                      # stop_reason / token-count sidecar
│   ├── *.progress.jsonl                      # Resume-state file
│   ├── comparison_report.md                  # A/B regression report
│   └── submission_*.zip                      # Validated submission packages
├── docs/               # Project docs (architecture, ADRs, runbooks)
├── tests/              # smoke.sh — light smoke check (no full TAP harness)
└── .claude/            # Claude Code config (hooks, settings)
```

## 핵심 명령 / Key Commands

```bash
# 인터랙티브 실행 (프리셋 메뉴 → 스모크 → 600건 호출 → 리포트)
./run_benchmark.sh

# 5건 dry-run (모델 호환 확인)
./run_benchmark.sh --quick

# 리포트만 재생성 (모델 호출 없음)
./run_benchmark.sh --report

# 제출 zip만 생성
./run_benchmark.sh --submit

# 직접 호출 (CI 등)
python3 fsi_bench.py \
  --before-model global.anthropic.claude-sonnet-4-5-20250929-v1:0 \
  --after-model  global.anthropic.claude-sonnet-4-6 \
  --before-region ap-northeast-2 --after-region ap-northeast-2

# 의존성 설치
pip install -r requirements.txt
```

## 핵심 모듈 / Key Modules in fsi_bench.py

| Function | Role |
|---|---|
| `repair_input()` | 깨진 JSONL(escape 누락·index 중복·필드 누락)을 사본에서 자동 복구 |
| `_invoke_one()` | Bedrock `invoke_model` 호출, throttle 재시도, `stop_reason` 캡처 |
| `run_side()` | 한 모델(side) 전체 300건 실행, progress 파일 쓰기, 재개 지원 |
| `classify()` | 응답을 5-class로 분류: `hard_refusal`(Anthropic `stop_reason="refusal"`) / `soft_refusal`(키워드 매칭) / `complied`(거절 키워드 없음) / `empty`(빈 응답) / `error`(러너 측 오류) |
| `validate_side()` | FSI 스키마 적합성 검사(필수 필드·index 1..300 커버리지·중복) **+ 모든 레코드에 `classify()` 적용**해 클래스 분포 산출 |
| `write_comparison_report()` | A/B 회귀(거절 → 응답) 케이스만 추출한 마크다운 리포트 생성 |

## 작업 시 관례 / Conventions

- **`doc/`는 읽기 전용**. 입력 데이터/스펙은 절대 수정하지 말 것. 복구가 필요하면 `repair_input()`이 사본을 만들어 처리한다.
- **응답 산출물은 한글 파일명**(`모델변경전.jsonl`, `모델변경후.jsonl`). NFC 정규화 사용 — 파일 시스템 호환성 때문에 `find_or_create_target()`이 검색을 처리한다. 직접 경로 하드코딩 금지.
- **재개(resume) 우선**. 중간 실패 시 `*.progress.jsonl`을 읽어 이어가도록 설계됨. 재시도 로직을 추가할 때는 progress 쓰기 순서를 깨지 말 것.
- **stop_reason은 메타데이터 사이드카에만**. 산출물 JSONL에는 FSI 스키마 외 필드 추가 금지.
- **Bedrock 키는 환경변수로만**. `AWS_BEARER_TOKEN_BEDROCK`을 코드/설정 파일에 절대 박지 말 것.
- **커밋 메시지**: Conventional Commits (`feat:`, `fix:`, `docs:`).

## 보안 주의 / Security Notes

- `output/`의 `submission_*.zip`은 모델 응답(잠재적으로 jailbreak 응답 포함)을 담고 있음. 외부 공유 금지 — FSI 제출 채널 외 유출 주의.
- `.claude/settings.local.json`은 절대 커밋하지 말 것 (`.gitignore`에 등록됨). 과거에 이 파일에 Bedrock bearer token이 평문으로 들어간 이력이 있음.
- PreToolUse 훅(`.claude/hooks/secret-scan.sh`)이 명령에 포함된 Bedrock/AWS 키 패턴을 차단함.

## Auto-Sync Rules

이 CLAUDE.md를 업데이트해야 하는 변경:

- `fsi_bench.py`의 CLI 인자(`parse_args()`) 변경 → "핵심 명령" 섹션 갱신
- 새 출력 파일 추가 → "프로젝트 구조"의 `output/` 트리 갱신
- 새 모듈/스크립트 추가 → 루트 트리와 "핵심 모듈" 표 갱신
- 새 환경변수 도입 → "기술 스택"의 Auth/region 표 갱신
- `classify()` 클래스 추가/변경 → 본 파일의 `classify()` 행과 `docs/architecture.md`의 분류기 설명·디자인 결정 동시 갱신
- `--workers`/`--retries`/`--max-tokens`/`--temperature` 기본값 변경 → `docs/architecture.md`의 "Runtime Defaults" 표 갱신
- 새 ADR(`docs/decisions/ADR-NNNN-*.md`) 또는 runbook(`docs/runbooks/*.md`) 작성 → 본 파일 "Reference" 섹션의 ADR/Runbook 하위 목록에 cross-reference 추가

## Reference

- Full bilingual README: [README.md](README.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- ADRs: [docs/decisions/](docs/decisions/)
  - [ADR-0001 — Inference Profile Only](docs/decisions/ADR-0001-inference-profile-only.md) (Bedrock direct foundation ID 사용 금지)
- Runbooks: [docs/runbooks/](docs/runbooks/)
  - [bedrock-model-access-denied](docs/runbooks/bedrock-model-access-denied.md) (LEGACY 게이트 / inference-profile / IAM 진단)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
