# AGENTS.md — fsi-kor-ai-benchmark

> Kiro 에이전트 진입점. 이 파일을 먼저 읽고 작업을 시작하세요.
> Entry point for Kiro agents. Read this first before working in this repo.

## 한 줄 요약 / TL;DR

AWS Bedrock 위에서 한국어 LLM의 **모델 교체 전후 안전성(jailbreak) 회귀**를 자동 검증하는
A/B 벤치마크 러너. 입력은 JailbreakBench(KR) 300건, 산출물은 FSI 제출 스키마에 맞춘 JSONL + 비교 리포트.

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
├── tests/              # smoke.sh, test_classify.py
├── .kiro/              # Kiro agent config (steering rules, agents, docs)
│   ├── steering/       # Project rules & conventions (auto-loaded)
│   ├── agents/         # Project-specific agent configs
│   └── docs/           # Architecture & reference indexes
└── .claude/            # Claude Code config (hooks, settings) — legacy
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
| `repair_input()` | 깨진 JSONL 자동 복구 (escape 누락·index 중복·필드 누락) |
| `_invoke_one()` | Bedrock `invoke_model` 호출, throttle 재시도, `stop_reason` 캡처 |
| `run_side()` | 한 모델(side) 전체 300건 실행, progress 파일 쓰기, 재개 지원 |
| `classify()` | 5-class 분류: `hard_refusal` / `soft_refusal` / `complied` / `empty` / `error` |
| `validate_side()` | FSI 스키마 적합성 검사 + `classify()` 적용해 클래스 분포 산출 |
| `write_comparison_report()` | A/B 회귀 케이스 추출 마크다운 리포트 생성 |

## Reference

- Full bilingual README: [README.md](README.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- ADRs: [docs/decisions/](docs/decisions/)
  - [ADR-0001 — Inference Profile Only](docs/decisions/ADR-0001-inference-profile-only.md)
- Runbooks: [docs/runbooks/](docs/runbooks/)
  - [bedrock-model-access-denied](docs/runbooks/bedrock-model-access-denied.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Steering rules: [.kiro/steering/](.kiro/steering/) — 프로젝트 관례, 보안, 동기화 규칙
