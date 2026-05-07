# Runbook — Running the benchmark (벤치마크 실행)

- **Owner**: 회사 AI 운영팀 (FSI 산출물 작성 담당)
- **Severity**: Routine
- **Last verified**: 2026-05-07

> 명령어 중심 운영 가이드입니다. **무엇을 / 왜** (전략·법규·서면확인서 작성) 는
> [fsi-submission-guide.md](../fsi-submission-guide.md) 를 참조하세요. 본 문서는
> "어떤 명령을 어떤 순서로, 실패 시 어떻게 복구할지" 에 집중합니다.

---

## When to use

다음 중 하나라도 해당하면:

- 처음 환경을 세팅하고 풀런까지 가져가야 할 때
- 풀런이 throttle / 네트워크 오류로 중단된 후 재개할 때
- `sample` mode 와 Bedrock 가드레일 모드를 비교 실행할 때
- 제출 zip 만들기 전 검증 게이트를 다시 확인할 때
- 단일 record 가 `<<ERROR>>` 로 끝나서 부분 재시도가 필요할 때

상위 워크플로(Step 4 의 3회 실행 권장, 사람 검토, 서면확인서 작성)는 본 문서의
범위 밖 — fsi-submission-guide.md 에서 다룹니다.

---

## Pre-checks (실행 전 1분)

- [ ] 프로젝트 루트(`fsi_kor_ai_benchmark/`) 안에서 작업 중 (`pwd` 확인)
- [ ] Python 3.9+ + `pip install -r requirements.txt` 완료
- [ ] AWS 자격증명 사용 가능 (`aws sts get-caller-identity` 통과 또는 `AWS_BEARER_TOKEN_BEDROCK` 설정)
- [ ] `output/` 디렉토리 쓰기 가능 + ~100MB 여유 공간
- [ ] 동시 실행 중인 다른 run 없음 (`pgrep -af fsi_bench`)
- [ ] (Bedrock 가드레일 모드) `BEDROCK_GUARDRAIL_ID` 가 valid

---

## Phase 0 — 일회성 셋업 (~10 분)

### 0.1 의존성

```bash
cd /path/to/fsi_kor_ai_benchmark
pip install -r requirements.txt
python3 -c "import boto3; print('boto3', boto3.__version__)"
```

### 0.2 자격증명 (택일)

옵션 A — Bedrock API bearer token (단발 / 데모):

```bash
export AWS_BEARER_TOKEN_BEDROCK=<token>
```

옵션 B — 표준 IAM (권장, 운영 환경):

```bash
aws sts get-caller-identity        # 어떤 ID 로 동작하는지 확인
# 이후는 AWS_PROFILE / AWS_ACCESS_KEY_ID / IMDS role 중 하나만 잡혀 있으면 됨
```

### 0.3 .env 작성

```bash
cp .env.example .env
$EDITOR .env
# 필수: AWS_BEARER_TOKEN_BEDROCK 또는 AWS 표준 키
# 선택: FSI_GUARDRAIL_MODE / BEDROCK_GUARDRAIL_ID / BEDROCK_GUARDRAIL_VERSION

set -a && source .env && set +a   # 셸에 로드
```

### 0.4 셋업 검증 — 모델 호출 1건

```bash
python3 -c "
import boto3, json
rt = boto3.client('bedrock-runtime', region_name='ap-northeast-2')
r = rt.invoke_model(
    modelId='global.anthropic.claude-sonnet-4-6',
    body=json.dumps({'anthropic_version':'bedrock-2023-05-31','max_tokens':16,
                     'messages':[{'role':'user','content':'한 단어로: 안녕'}]}))
print(json.loads(r['body'].read())['content'][0]['text'])
"
```

응답이 한 단어로 오면 OK. 에러 시 → [bedrock-model-access-denied](bedrock-model-access-denied.md).

---

## Phase 1 — Smoke (5 건, ~30 초)

목적: 모델 호환성 + 가드레일 dispatch 검증. 풀런 비용 쓰기 전 게이트.

### 시나리오 A — Sample 가드레일 (회사 가드레일 미준비 시)

```bash
FSI_GUARDRAIL_MODE=sample ./run_benchmark.sh --quick
```

JailbreakBench 적중률이 ~14.7% 라 5건 샘플에서는 0~1 건 차단이 정상.

### 시나리오 B — Bedrock 가드레일 (실 제출 회차에 사용)

```bash
unset FSI_GUARDRAIL_MODE
export BEDROCK_GUARDRAIL_ID=<회사 guardrail id>
export BEDROCK_GUARDRAIL_VERSION=DRAFT
./run_benchmark.sh --quick
```

### 시나리오 C — 회사 자체 가드레일 (`guardrail_check()` fork 한 경우)

```bash
unset FSI_GUARDRAIL_MODE BEDROCK_GUARDRAIL_ID
./run_benchmark.sh --quick
```

### 시나리오 D — 가드레일 완전 bypass (raw 모델 회귀만 보고 싶을 때)

```bash
python3 fsi_bench.py --limit 5 --no-guardrail
```

### 1.1 Smoke 결과 확인

```bash
# 리포트 핵심 영역
awk '/Layer × Class/,/Layer transition/' output/comparison_report.md

# error / blocked 빠른 카운트
grep -c '<<ERROR' output/모델변경전.jsonl output/모델변경후.jsonl
grep -c '"blocked_by":"guardrail"' output/*.metadata.jsonl
```

게이트:

- [ ] 양 side 5/5 record 작성
- [ ] `error` 클래스 0
- [ ] (가드레일 활성화 시) `guardrail_blocked` 행 카운트 ≥ 0 (5건 샘플은 0 도 정상)
- [ ] 응답이 production 챗봇 톤과 비슷 (system prompt 적용 확인)

---

## Phase 2 — Full A/B (300 × 2 = 600 호출, 5~15 분)

스모크가 깨끗하면 진입.

### 2.1 인터랙티브 (권장)

```bash
./run_benchmark.sh
```

메뉴: before / after 모델 선택 → 모델 ping → 600 호출 → 리포트 → 제출 zip 생성 제안.

### 2.2 비대화 (CI / 자동화)

```bash
python3 -u fsi_bench.py \
  --before-model global.anthropic.claude-sonnet-4-5-20250929-v1:0 \
  --after-model  global.anthropic.claude-sonnet-4-6 \
  --before-region ap-northeast-2 --after-region ap-northeast-2 \
  --workers 8 --retries 6 --reset \
  2>&1 | tee output/runner.log
```

### 2.3 비용·시간 예측

| 항목 | 값 (Sonnet 4.5/4.6 기준 추정) |
|---|---|
| 호출 수 | 600 (BEFORE 300 + AFTER 300) |
| 입력 토큰 (총) | ~150 K (평균 입력 250 tok 가정) |
| 출력 토큰 (총) | ~300 K (`max_tokens 4096`, 평균 ~500 tok) |
| Bedrock 모델 비용 | ~$1–5 |
| 가드레일 호출 비용 | 별도 (모델·정책별 가이드 참조) |
| 소요 시간 | 5–15 분 (`--workers 8` + throttle 발생 여부) |

정확한 비용은 사후에 사이드카로 계산:

```bash
python3 -c "
import json
i = o = 0
for f in ('output/모델변경전.jsonl.metadata.jsonl', 'output/모델변경후.jsonl.metadata.jsonl'):
    for line in open(f, encoding='utf-8'):
        m = json.loads(line)
        i += m.get('input_tokens') or 0
        o += m.get('output_tokens') or 0
print(f'total input_tokens={i:,}  output_tokens={o:,}')
"
```

---

## Phase 3 — 실패 복구

### 3.1 도중 중단 (throttle / 네트워크) → 재개

`*.progress.jsonl` 가 보존됐다면 그대로 이어가기:

```bash
./run_benchmark.sh --resume        # progress 보존
# 또는 한쪽만
python3 fsi_bench.py --only after --no-repair
```

### 3.2 일부 record 가 `<<ERROR>>` 로 끝남 → 해당 record 만 재시도

영구 throttle / 일시 access 거부 등으로 record 가 error 마커로 끝난 경우. progress
에서 error record 만 제거하면 다음 실행에서 자동 재시도됩니다.

```bash
python3 -c "
import json, os
for side in ('모델변경전', '모델변경후'):
    p = f'output/{side}.jsonl.progress.jsonl'
    if not os.path.exists(p): continue
    keep = []
    with open(p, encoding='utf-8') as f:
        for line in f:
            r = json.loads(line)
            if not r['response'].startswith('<<ERROR'):
                keep.append(line)
    with open(p, 'w', encoding='utf-8') as f:
        f.writelines(keep)
    print(f'{p}: kept {len(keep)} records (errors removed)')
"
./run_benchmark.sh --resume
```

### 3.3 한쪽 모델만 access denied → 살아있는 쪽 먼저 진행

```bash
# 살아있는 쪽 끝내기
python3 fsi_bench.py --only after

# access 복구 후 나머지
python3 fsi_bench.py --only before
```

진단: [bedrock-model-access-denied](bedrock-model-access-denied.md).

### 3.4 처음부터 완전 재실행

⚠️ 파괴적 — 기존 진행 상태 모두 삭제됩니다.

```bash
rm -f output/*.progress.jsonl output/*.metadata.jsonl
python3 fsi_bench.py --reset
```

### 3.5 throttle 이 지속되면 동시성 절반

```bash
python3 fsi_bench.py --workers 4    # 기본 8 → 4
# 그래도 안 풀리면
python3 fsi_bench.py --workers 2
```

---

## Phase 4 — 결과 검증

### 4.1 자동 검증 (호출 없음)

```bash
./run_benchmark.sh --report
# 또는
python3 fsi_bench.py --report-only
```

### 4.2 검증 게이트

| 체크 | 명령 | 정상 |
|---|---|---|
| 레코드 수 | `wc -l output/모델변경전.jsonl output/모델변경후.jsonl` | 양쪽 300 |
| 스키마 청결 | `head -1 output/모델변경전.jsonl` | `Index, model, response` 키 3개만 |
| Index 누락/중복 | `--report-only` 출력 | "structure clean" |
| `error` 클래스 | `grep -c '<<ERROR' output/모델변경*.jsonl` | 0 |
| 가드레일 차단 (Bedrock 모드) | `grep -c '"blocked_by":"guardrail"' output/*.metadata.jsonl` | > 0 |
| 회귀 (거절→응답) | `grep -A2 "회귀 (거절→응답)" output/comparison_report.md` | 0 이상적 |

### 4.3 회귀 케이스 빠른 추출

```bash
grep -A 20 '🚨 \*\*회귀' output/comparison_report.md | head -100
```

회귀가 0 보다 크면 → fsi-submission-guide.md Step 5 (사람 검토) 진입.

### 4.4 Layer × Class cross-tab 단독 보기

```bash
awk '/Layer × Class/,/Layer transition/' output/comparison_report.md
```

해석:

- 양 side `guardrail_blocked` 카운트 일치 → 가드레일이 1차 방어선으로 동등하게
  동작 입증 → ①경미 등급 강력 근거.
- `guardrail_blocked → guardrail_pass` transition 행이 0 이 아니면 → 회사
  가드레일이 모델 변경에 따라 동작이 바뀐 것이므로 회사 가드레일 자체 회귀 의심.

---

## Phase 5 — 제출 패키지 생성

```bash
./run_benchmark.sh --submit
```

생성:

- `output/submission_<timestamp>.zip` — **FSI 제출용** (메인 2 파일만)
- `output/submission_full_<timestamp>.zip` — 회사 보관용 (사이드카·리포트 포함)

### 5.1 제출 전 안전 체크

```bash
# 사이드카에 회사 정책 ID 누출 없나
grep -iE "policy|internal|secret|company" output/*.metadata.jsonl   # 비어야 OK

# 메인 zip 안에 system prompt 평문 없나
unzip -p output/submission_2*.zip | grep -iE "system_prompt|회사명|영업비밀" | head
# (출력 비어 있어야 OK; full zip이 아닌 메인 zip만 검사)

# 적어도 1건 가드레일 차단이 있는지 (Bedrock/회사 가드레일 모드인 경우)
grep -c '"blocked_by":"guardrail"' output/*.metadata.jsonl
```

마지막 카운트가 0 인데 가드레일을 켰다면 → [guardrail-troubleshooting](guardrail-troubleshooting.md)
"모든 record 가 blocked_by=null" 섹션.

---

## 시나리오별 한 줄 요약

| 목적 | 명령 |
|---|---|
| 처음 + sample 가드레일 dry-run | `cp .env.example .env && set -a && source .env && set +a && FSI_GUARDRAIL_MODE=sample ./run_benchmark.sh --quick` |
| 정식 풀런 (Bedrock 가드레일) | `unset FSI_GUARDRAIL_MODE && export BEDROCK_GUARDRAIL_ID=<id> && ./run_benchmark.sh` |
| 중단 후 이어가기 | `./run_benchmark.sh --resume` |
| 한쪽만 재실행 | `python3 fsi_bench.py --only after --reset` |
| 리포트만 재생성 | `./run_benchmark.sh --report` |
| 제출 zip 생성 | `./run_benchmark.sh --submit` |
| error record 만 재시도 | Phase 3.2 의 1줄 Python → `./run_benchmark.sh --resume` |
| 동시성 절반 (throttle 회피) | `python3 fsi_bench.py --workers 4` |
| 처음부터 완전 재실행 | `rm -f output/*.progress.jsonl output/*.metadata.jsonl && python3 fsi_bench.py --reset` |
| 가드레일 완전 bypass | `python3 fsi_bench.py --no-guardrail` |

---

## 트러블슈팅 빠른 참조

| 증상 | 1차 진단 |
|---|---|
| `AccessDeniedException` (모델 ID) | [bedrock-model-access-denied](bedrock-model-access-denied.md) — LEGACY 게이트 / inference profile / IAM |
| `<<ERROR:guardrail:...>>` | [guardrail-troubleshooting](guardrail-troubleshooting.md) — env / IAM / region |
| `ThrottlingException` 반복 | Phase 3.5 — `--workers 4` 또는 `--workers 2` |
| `blocked_by` 가 모두 null인데 production 에서는 차단되어야 함 | guardrail-troubleshooting "모든 record 가 blocked_by=null" 섹션 |
| 한글 파일명이 `?` 으로 깨짐 | `find_or_create_target` NFC 처리는 자동 — 직접 경로 하드코딩 금지 |
| 결과가 run 마다 다름 (회귀 9건 → 13건) | Bedrock 비결정성 — fsi-submission-guide.md Step 4 (3회 run 합집합) |
| dispatch 동작 자체 의심 | `FSI_GUARDRAIL_MODE=sample ./run_benchmark.sh --quick` 으로 차단 1건 이상 만들어 dispatch 정상 입증 |
| `guardrail_reason` 에 자유문 / 정책 ID 노출 | guardrail-troubleshooting "sidecar의 guardrail_reason이 자유문" 섹션 |

---

## Verification

본 런북 종료 시점 체크:

- [ ] 양쪽 jsonl 모두 300 record + 3-field 스키마
- [ ] `comparison_report.md` 의 Layer × Class cross-tab 정상 (가드레일 모드별)
- [ ] error 클래스 0
- [ ] 모든 단위 테스트 green:
      ```bash
      for t in tests/test_*.py; do python3 "$t" || echo "  FAIL $t"; done
      bash tests/test_smoke.sh
      bash tests/test_secret_scan.sh
      ```
- [ ] (Bedrock 모드) sidecar 에 `blocked_by="guardrail"` 1건 이상

---

## Post-incident

- [ ] runner.log 보관: `mv output/runner.log output/runner_$(date +%Y%m%d_%H%M).log`
- [ ] 비결정성 대응 — 단일 run 으로 게이트하지 말 것 (3회 run 합집합 권장,
      fsi-submission-guide.md Step 4)
- [ ] 반복 발생 이슈는 본 런북 또는 별도 ADR 로 기록
- [ ] FSI 제출 후 30 일까지는 `output_run_*` 백업 유지 (재요청 가능성)

---

## 관련 문서

- [README.md](../../README.md) — 프로젝트 개요
- [CLAUDE.md](../../CLAUDE.md) — Claude Code 진입점
- [docs/fsi-submission-guide.md](../fsi-submission-guide.md) — 전략 가이드
  (Step 0~8 + 서면확인서 작성)
- [docs/architecture.md](../architecture.md) — 시스템 구조 + fork-and-edit
  points + Runtime Defaults 표
- [ADR-0001 — Inference profile only](../decisions/ADR-0001-inference-profile-only.md)
- [ADR-0002 — Two-stage pipeline](../decisions/ADR-0002-two-stage-pipeline.md)
- [Runbook: bedrock-model-access-denied](bedrock-model-access-denied.md)
- [Runbook: guardrail-troubleshooting](guardrail-troubleshooting.md)
