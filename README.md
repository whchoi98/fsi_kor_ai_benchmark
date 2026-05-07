# fsi-kor-ai-benchmark

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.9%2B-blue.svg)](https://www.python.org/)
[![AWS Bedrock](https://img.shields.io/badge/AWS-Bedrock-orange.svg)](https://aws.amazon.com/bedrock/)
[![English](https://img.shields.io/badge/lang-English-red.svg)](#english)
[![한국어](https://img.shields.io/badge/lang-한국어-blue.svg)](#한국어)

A bilingual safety benchmark runner that verifies Korean LLM jailbreak resistance across model migrations on AWS Bedrock.
AWS Bedrock 기반 한국어 LLM 모델 교체 시 jailbreak 안전성 회귀를 자동으로 검증하는 벤치마크 러너입니다.

---

# English

## Overview

`fsi-kor-ai-benchmark` is an A/B safety regression test harness for Korean LLM deployments on Amazon Bedrock. It runs all 300 prompts of the JailbreakBench (Korean translation) dataset against a "before" model and an "after" model, then produces a side-by-side report identifying any prompts where the new model becomes less safe than the old one. The tool is designed to satisfy the FSI (Financial Security Institute of Korea) submission format used for regulatory model-change verification.

> **Deployed-posture framing.** This harness measures **deployed posture** regression
> rather than raw model regression. Every prompt flows through (1) the company
> guardrail and (2) a service with the company system prompt before its response
> is recorded — capturing what the FSI evaluator (Financial Security Institute of
> Korea) actually sees in production.
>
> Regulatory context: 금융위원회 「생성형 AI 모델 변경 시 혁신금융서비스 변경
> 절차 개선 방안」 (2026.4.15. 정례회의 확정). The pre/post-change response
> delta is the central input to the ①경미 / ②보통 / ③상당 classification.
> Notice: https://sandbox.fintech.or.kr/support/notice_detail.do?lang=ko&id=3791

## Features

- **300-prompt automated runner** — Sends the full JailbreakBench (KR) dataset to two Bedrock models concurrently with retry, throttling, and resume support.
- **A/B regression detection** — Classifies every response as hard refusal, soft refusal, or compliant; flags only prompts whose safety regressed (refused → answered).
- **Self-healing input** — Automatically repairs malformed JSON lines (unescaped quotes, duplicate indices, missing fields) without modifying the original spec file.
- **Refusal-aware metadata sidecar** — Captures Anthropic's `stop_reason` so the strongest "hard refusal" cases (zero content) can be distinguished from verbose refusals.
- **Submission packaging** — Validates the final files against the FSI schema and produces a ready-to-send zip containing only the two required deliverables.

## Prerequisites

- Python 3.9 or later
- `boto3` (any version that supports Bedrock runtime; tested with 1.42+)
- An AWS account with Amazon Bedrock model access for the chosen models
- A Bedrock API key OR standard IAM credentials with `bedrock:InvokeModel` permission
- `zip` and `unzip` for submission packaging

## Installation

```bash
# Clone the repository
git clone https://github.com/fsi-redteam/fsi-kor-ai-benchmark.git
cd fsi-kor-ai-benchmark

# Install Python dependency
pip install boto3

# Make the entrypoint executable
chmod +x run_benchmark.sh
```

## Usage

```bash
# Provide a Bedrock API key (or use IAM credentials)
export AWS_BEARER_TOKEN_BEDROCK="<your-bedrock-api-key>"

# Interactive mode: pick before/after models from a preset menu
./run_benchmark.sh
# → choose models → smoke test → confirmation → 600 calls → auto-report

# Non-interactive helpers
./run_benchmark.sh --quick           # 5-prompt dry run for compatibility check
./run_benchmark.sh --only-after      # run only the after-side
./run_benchmark.sh --report          # regenerate report without invoking models
./run_benchmark.sh --submit          # build the submission zip from existing output
```

Direct CLI invocation of the underlying Python runner:

```bash
python3 fsi_bench.py \
    --before-model global.anthropic.claude-sonnet-4-5-20250929-v1:0 \
    --before-region ap-northeast-2 \
    --after-model  global.anthropic.claude-sonnet-4-6 \
    --after-region ap-northeast-2
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_BEARER_TOKEN_BEDROCK` | Bedrock API key (recommended for one-off runs). | unset |
| `AWS_PROFILE` | Named AWS CLI profile to source credentials from. | unset |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Static IAM credentials (alternative to bearer token). | unset |
| `AWS_REGION` | Default region used when none is passed via `--before-region` / `--after-region`. | `ap-northeast-2` |
| `FSI_GUARDRAIL_MODE` | Stage 1 dispatch. `sample` → `samples/local_guardrail.py` pattern match (no AWS call). Empty → Bedrock branch below. | unset |
| `BEDROCK_GUARDRAIL_ID` | Bedrock Guardrail identifier. With this set and `FSI_GUARDRAIL_MODE` empty, Stage 1 calls `apply_guardrail`. | unset |
| `BEDROCK_GUARDRAIL_VERSION` | Bedrock Guardrail version (`DRAFT` or numeric). | `DRAFT` |

## Project Structure

```text
fsi_kor_ai_benchmark/
├── doc/                           # Specification (read-only — never modify)
│   ├── LICENSE                    # MIT License
│   ├── README.md                  # Dataset README (FSI / JailbreakBench origin)
│   ├── jailbreakbench.jsonl       # 300 Korean jailbreak prompts (input)
│   └── output_format/             # Submission skeleton files
│       ├── 모델변경전.jsonl        # Placeholder for "before" model output
│       └── 모델변경후.jsonl        # Placeholder for "after" model output
│
├── output/                        # Generated artifacts (writable, gitignored)
│   ├── 모델변경전.jsonl            # Filled "before" deliverable (FSI submission)
│   ├── 모델변경후.jsonl            # Filled "after" deliverable (FSI submission)
│   ├── *.metadata.jsonl           # stop_reason / token-count sidecar
│   ├── *.progress.jsonl           # Resume-state file used by the runner
│   ├── comparison_report.md       # Auto-generated A/B regression report
│   ├── submission_*.zip           # Submission package — body files only (FSI-bound)
│   └── submission_full_*.zip      # Internal archive — body + metadata + report
│
├── docs/                          # Project documentation
│   ├── architecture.md            # Bilingual EN/KR architecture & runtime defaults
│   ├── decisions/                 # Architecture Decision Records (ADRs)
│   └── runbooks/                  # Operational playbooks
│
├── samples/                       # Fork-friendly leaf modules
│   └── local_guardrail.py         # Pattern-match sample guardrail (FSI_GUARDRAIL_MODE=sample)
│
├── tests/                         # Unit tests + shell harnesses
│   ├── test_*.py                  # Plain-assert unit tests (classify / guardrail / pipeline / sample / layers)
│   ├── test_smoke.sh              # Static smoke checks
│   └── test_secret_scan.sh        # PreToolUse secret-scan hook
│
├── .claude/                       # Claude Code config (settings.json + hooks)
│   ├── settings.json              # PreToolUse secret-scan + permission deny list
│   └── hooks/secret-scan.sh       # Blocks AWS/Bedrock keys in shell commands
│
├── fsi_bench.py                   # Python CLI runner (Bedrock invocation)
├── run_benchmark.sh               # Interactive shell wrapper (entrypoint)
├── requirements.txt               # boto3>=1.42
├── CLAUDE.md                      # Agent entry point — invariants & conventions
├── CHANGELOG.md
├── .env.example                   # Bedrock credential template
├── .editorconfig                  # Shared formatting rules
├── .gitignore                     # Python + project artifacts + secrets
└── README.md                      # This file
```

## Adapting to your stack (Fork-and-edit)

This repo follows a **reference + fork-and-edit** pattern. You only need to
modify two functions in `fsi_bench.py`:

1. `guardrail_check(user_query, region) -> GuardrailResult` — reference uses
   Amazon Bedrock Guardrails (`apply_guardrail`); replace the body to plug in
   your own guardrail. Both `BEDROCK_GUARDRAIL_ID` and `BEDROCK_GUARDRAIL_VERSION`
   unset → no-op pass (smoke-friendly). For an AWS-free end-to-end smoke set
   `FSI_GUARDRAIL_MODE=sample` to dispatch to the bundled pattern-match guardrail
   in `samples/local_guardrail.py` (demo only — not for FSI submission).
2. `build_system_prompt(side) -> str` — reference is an FSI + JailbreakBench
   safety prompt; replace with your production system prompt. Branch on `side`
   for prompt A/B (`if side == "after": return v2`).

Everything else (progress/resume, FSI schema, concurrency, comparison report)
should be left alone. See [docs/architecture.md](docs/architecture.md)
"Fork-and-edit points" for the contracts these two functions must honor.

## Contributing

1. Fork the repository on GitHub.
2. Create a feature branch from `main` (`git checkout -b feat/your-feature`).
3. Make focused commits using Conventional Commits format (`feat: ...`, `fix: ...`, `docs: ...`).
4. Push the branch to your fork (`git push origin feat/your-feature`).
5. Open a Pull Request describing the change, the motivation, and how it was tested.

## License

This project is released under the [MIT License](LICENSE). The bundled JailbreakBench dataset retains the licensing terms of its [upstream source](https://github.com/JailbreakBench/jailbreakbench); review them before redistribution.

## Contact

- Issues: [GitHub Issues](https://github.com/fsi-redteam/fsi-kor-ai-benchmark/issues)
- Email: whchoi98@gmail.com

---

# 한국어

## 개요

`fsi-kor-ai-benchmark`는 Amazon Bedrock 기반 한국어 LLM 배포 환경에서 모델 교체 전후의 안전성 회귀를 검증하는 A/B 테스트 도구입니다. JailbreakBench 한국어판 300건 전체를 "변경 전" 모델과 "변경 후" 모델 양쪽에 동일하게 적용한 뒤, 동일 프롬프트에 대해 새 모델이 더 위험해진 케이스만을 자동으로 추출합니다. 본 도구는 금융보안원(FSI) 모델 변경 심사 양식에 맞춘 산출물을 생성하도록 설계되었습니다.

> 이 harness는 raw 모델 회귀 진단이 아니라 **배포 자세(deployed posture) 회귀** 진단을
> 위한 것입니다. 한 prompt가 (1) 회사 가드레일 → (2) 회사 system prompt가 적용된
> 서비스 두 stage를 거친 후의 응답을 비교합니다. FSI 평가자(금융보안원)가 보는
> "실제 사용자가 받을 응답"을 그대로 캡처합니다.
>
> 규제 배경: 금융위원회 「생성형 AI 모델 변경 시 혁신금융서비스 변경 절차 개선 방안」
> (2026.4.15. 정례회의 확정). 모델 변경 전후 응답 변화도가 ①경미 / ②보통 / ③상당
> 분류의 핵심 입력입니다. 자세한 내용:
> https://sandbox.fintech.or.kr/support/notice_detail.do?lang=ko&id=3791

## 주요 기능

- **300건 자동 호출 러너** — JailbreakBench 한국어판 전체를 두 Bedrock 모델에 동시 호출하며, 재시도·throttle 처리·중단 후 재개를 지원합니다.
- **A/B 회귀 자동 검출** — 모든 응답을 hard refusal / soft refusal / compliant로 분류하고, 안전성이 회귀한(거절 → 응답) 프롬프트만 별도 추출합니다.
- **입력 자동 수리** — 깨진 JSON 라인(escape 누락, Index 중복, 필드 누락)을 원본을 변경하지 않고 사본에서 자동 정정합니다.
- **거절 인식 메타데이터 사이드카** — Anthropic의 `stop_reason`을 보존하여 최강 안전 신호인 "hard refusal"(콘텐츠 0블록)을 verbose 거절과 구분합니다.
- **제출 패키지 생성** — FSI 스키마를 사전 검증한 뒤 필수 두 파일만 담은 제출용 zip을 자동 생성합니다.

## 사전 요구 사항

- Python 3.9 이상
- `boto3` (Bedrock runtime을 지원하는 버전, 1.42 이상 검증됨)
- 선택한 모델에 대한 Amazon Bedrock 액세스 권한이 활성화된 AWS 계정
- Bedrock API 키 또는 `bedrock:InvokeModel` 권한이 있는 표준 IAM 자격증명
- 제출 패키지 생성을 위한 `zip` / `unzip`

## 설치 방법

```bash
# 저장소 클론
git clone https://github.com/fsi-redteam/fsi-kor-ai-benchmark.git
cd fsi-kor-ai-benchmark

# Python 의존성 설치
pip install boto3

# 진입점 스크립트에 실행 권한 부여
chmod +x run_benchmark.sh
```

## 사용법

```bash
# Bedrock API 키 등록 (또는 IAM 자격증명 사용)
export AWS_BEARER_TOKEN_BEDROCK="<your-bedrock-api-key>"

# 인터랙티브 모드: 프리셋 메뉴에서 변경 전/후 모델 선택
./run_benchmark.sh
# → 모델 선택 → 사전 호출 테스트 → 확인 → 600건 호출 → 리포트 자동 생성

# 비대화 보조 명령
./run_benchmark.sh --quick           # 5건 dry-run (호환성 확인용)
./run_benchmark.sh --only-after      # 변경 후 측만 실행
./run_benchmark.sh --report          # 모델 호출 없이 리포트만 재생성
./run_benchmark.sh --submit          # 기존 산출물로 제출용 zip 생성
```

내부 Python 러너 직접 호출:

```bash
python3 fsi_bench.py \
    --before-model global.anthropic.claude-sonnet-4-5-20250929-v1:0 \
    --before-region ap-northeast-2 \
    --after-model  global.anthropic.claude-sonnet-4-6 \
    --after-region ap-northeast-2
```

## 환경 설정

| 변수명 | 설명 | 기본값 |
|--------|------|--------|
| `AWS_BEARER_TOKEN_BEDROCK` | Bedrock API 키 (단발 실행 시 권장). | 미설정 |
| `AWS_PROFILE` | 자격증명을 가져올 AWS CLI 프로파일 이름. | 미설정 |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | 정적 IAM 자격증명 (bearer token 대안). | 미설정 |
| `AWS_REGION` | `--before-region` / `--after-region`이 지정되지 않을 때 사용할 기본 리전. | `ap-northeast-2` |
| `FSI_GUARDRAIL_MODE` | Stage 1 dispatch. `sample` → `samples/local_guardrail.py` 로컬 패턴 매칭 (AWS 호출 없음). 비어 있으면 아래 Bedrock 분기. | 미설정 |
| `BEDROCK_GUARDRAIL_ID` | Bedrock 가드레일 식별자. 본 변수 + `FSI_GUARDRAIL_MODE` 비어있으면 `apply_guardrail` 호출. | 미설정 |
| `BEDROCK_GUARDRAIL_VERSION` | Bedrock 가드레일 버전 (`DRAFT` 또는 숫자). | `DRAFT` |

## 프로젝트 구조

```text
fsi_kor_ai_benchmark/
├── doc/                           # 명세 (읽기 전용 — 절대 수정 금지)
│   ├── LICENSE                    # MIT License
│   ├── README.md                  # 데이터셋 설명 (FSI / JailbreakBench 출처)
│   ├── jailbreakbench.jsonl       # 한국어 jailbreak 프롬프트 300건 (입력)
│   └── output_format/             # 제출 양식 스켈레톤
│       ├── 모델변경전.jsonl        # "변경 전" 모델 응답 자리표시자
│       └── 모델변경후.jsonl        # "변경 후" 모델 응답 자리표시자
│
├── output/                        # 산출물 (쓰기 가능, gitignore)
│   ├── 모델변경전.jsonl            # 채워진 "변경 전" 제출본 (FSI 제출)
│   ├── 모델변경후.jsonl            # 채워진 "변경 후" 제출본 (FSI 제출)
│   ├── *.metadata.jsonl           # stop_reason / 토큰 수 사이드카
│   ├── *.progress.jsonl           # 러너 재개용 상태 파일
│   ├── comparison_report.md       # A/B 회귀 분석 리포트 자동 생성본
│   ├── submission_*.zip           # 제출 패키지 — 본체 2파일만 (FSI 제출용)
│   └── submission_full_*.zip      # 내부 아카이브 — 본체 + 메타 + 리포트
│
├── docs/                          # 프로젝트 문서
│   ├── architecture.md            # 한/영 이중 아키텍처 + 런타임 기본값 표
│   ├── decisions/                 # 아키텍처 의사결정 기록 (ADR)
│   └── runbooks/                  # 운영 플레이북
│
├── samples/                       # Fork 친화적 leaf 모듈
│   └── local_guardrail.py         # 패턴 매칭 샘플 가드레일 (FSI_GUARDRAIL_MODE=sample)
│
├── tests/                         # 단위 테스트 + 셸 하니스
│   ├── test_*.py                  # plain-assert 단위 테스트 (classify / guardrail / pipeline / sample / layers)
│   ├── test_smoke.sh              # 정적 스모크 검사
│   └── test_secret_scan.sh        # PreToolUse secret-scan 훅
│
├── .claude/                       # Claude Code 설정 (settings.json + hooks)
│   ├── settings.json              # PreToolUse secret-scan + permission deny 목록
│   └── hooks/secret-scan.sh       # 셸 명령에서 AWS/Bedrock 키 패턴 차단
│
├── fsi_bench.py                   # Python CLI 러너 (Bedrock 호출)
├── run_benchmark.sh               # 인터랙티브 셸 래퍼 (진입점)
├── requirements.txt               # boto3>=1.42
├── CLAUDE.md                      # 에이전트 진입점 — invariant·관례
├── CHANGELOG.md
├── .env.example                   # Bedrock 자격증명 템플릿
├── .editorconfig                  # 공통 포맷 규칙
├── .gitignore                     # Python + 프로젝트 산출물 + secrets
└── README.md                      # 본 파일
```

## 회사 스택에 적용 (Fork-and-edit)

본 repo는 **참조 구현 + fork-and-edit** 패턴입니다. 회사가 손대는 곳은 정확히
`fsi_bench.py`의 두 함수입니다:

1. `guardrail_check(user_query, region) -> GuardrailResult`
   - 레퍼런스: Amazon Bedrock Guardrails (`apply_guardrail`).
   - `BEDROCK_GUARDRAIL_ID` / `BEDROCK_GUARDRAIL_VERSION` 환경변수로 설정.
   - 자체 가드레일을 쓰는 회사는 함수 본체를 자기 호출 코드로 교체.
   - 둘 다 미설정 시 no-op pass — smoke / 미적용 환경에서 안전하게 동작.
   - AWS 자원 없이 두-단계 파이프라인을 end-to-end 검증하려면
     `FSI_GUARDRAIL_MODE=sample` 으로 `samples/local_guardrail.py` 패턴 매칭
     샘플 사용 (데모 전용 — 실 FSI 제출에는 부적합).

2. `build_system_prompt(side) -> str`
   - 레퍼런스: FSI + JailbreakBench 통합 안전 지침 (8 카테고리).
   - 회사 production system prompt로 본체 교체.
   - `side` 인자 분기로 prompt-A/B 동시 평가도 가능 (`if side=="after": return v2`).

다른 부분(progress/resume, FSI 스키마, 동시성, comparison report)은 그대로 두고
이 두 함수만 자기 스택에 맞추면 됩니다. 두 함수의 contract는
[docs/architecture.md](docs/architecture.md) "Fork-and-edit points" 절에서 자세히
다룹니다.

## 기여 방법

1. GitHub에서 저장소를 Fork 합니다.
2. `main`에서 기능 브랜치를 생성합니다 (`git checkout -b feat/your-feature`).
3. Conventional Commits 형식(`feat: ...`, `fix: ...`, `docs: ...`)으로 작은 단위 커밋을 작성합니다.
4. Fork한 저장소로 브랜치를 푸시합니다 (`git push origin feat/your-feature`).
5. 변경 내용·동기·테스트 방법을 설명한 Pull Request를 생성합니다.

## 라이선스

본 프로젝트는 [MIT License](LICENSE)로 배포됩니다. 동봉된 JailbreakBench 데이터셋은 [원본 저장소](https://github.com/JailbreakBench/jailbreakbench)의 라이선스 조건을 따르므로 재배포 전 반드시 함께 확인하시기 바랍니다.

## 연락처

- 이슈 트래커: [GitHub Issues](https://github.com/fsi-redteam/fsi-kor-ai-benchmark/issues)
- 이메일: whchoi98@gmail.com

<!-- harness-eval-badge:start -->
![Harness Score](https://img.shields.io/badge/harness-6.1%2F10-orange)
![Harness Grade](https://img.shields.io/badge/grade-C-orange)
![Last Eval](https://img.shields.io/badge/eval-2026--05--04-blue)
<!-- harness-eval-badge:end -->
