# Runbook — Bedrock Model Access Denied (Legacy / Inactive Model)

- **Owner**: FSI AI Red Team
- **Severity**: SEV-2 (벤치마크 실행 차단되지만 데이터 손실은 없음)
- **Last verified**: 2026-05-04

## When to use this runbook

다음 증상 중 하나가 보일 때 사용:

- `ResourceNotFoundException: ... Access denied. This Model is marked by provider as Legacy and you have not been actively using the model in the last 30 days. Please upgrade to an active model on Amazon Bedrock`
- `ValidationException: Invocation of model ID ... with on-demand throughput isn't supported. Retry your request with the ID or ARN of an inference profile that contains this model.`
- `AccessDeniedException` on `bedrock:InvokeModel`
- `run_benchmark.sh`가 모든 프롬프트에 대해 즉시 동일 에러로 실패하는 경우

## Pre-checks (do not skip)

- [ ] 자격증명 유효성: `aws sts get-caller-identity` 가 200 응답 + 의도한 account ID 반환
- [ ] 모델이 region에 listed 되어 있는지: `aws bedrock list-foundation-models --region <REGION> --query "modelSummaries[?contains(modelId, '<MODEL>')]"`
- [ ] Inference profile이 listed 되어 있는지: `aws bedrock list-inference-profiles --region <REGION> --query "inferenceProfileSummaries[?contains(inferenceProfileId, '<MODEL>')]"`
- [ ] 사용 중인 model id가 `^(eu|us|global|apac)\.` prefix를 갖는지 (ADR-0001 참조)
- [ ] `output/` 디렉터리에 진행 중인 다른 실행이 없는지 (`ls -la output/*.progress.jsonl` mtime이 1분 이내가 아닌지)

## Diagnosis

각 단계는 yes/no 답을 준다.

### 1. 어느 에러 패턴인가?

| 에러 메시지 키워드 | 진단 |
|---|---|
| "marked by provider as Legacy" | **Case A**: LEGACY 30일 게이트. 계정이 30일 내 해당 모델을 호출한 이력이 없음. |
| "with on-demand throughput isn't supported" | **Case B**: direct foundation ID로 호출 중. Inference profile 필요 (ADR-0001). |
| "AccessDeniedException" 단독 | **Case C**: IAM 권한 부족. Role/policy 확인. |
| "ThrottlingException" | 본 runbook 대상 아님. throttle-recovery runbook 참조. |

### 2. Case A 추가 진단

- [ ] 다른 자격증명(다른 account의 bearer token)으로도 동일 에러 발생? → Yes면 모델이 광범위하게 LEGACY 차단됨.
- [ ] 같은 region에서 다른 ACTIVE 모델(예: 4.5 또는 4.6)은 호출 성공? → Yes면 region/role/auth 모두 정상 → LEGACY 게이트 확정.

### 3. Case B 추가 진단

- 사용한 model id 확인:
  ```bash
  grep -E "(--before-model|--after-model|DEFAULT_BEFORE|DEFAULT_AFTER)" fsi_bench.py run_benchmark.sh
  ```
- 출력에 prefix가 없는 ID(`anthropic.claude-...`)가 있다면 그것이 원인.

## Mitigation

### Case A — LEGACY 게이트 해제

순서대로 시도:

```bash
# 1) Bedrock Console에서 model access 재신청
#    Console > Bedrock > Model access > Manage model access > 해당 모델 체크 > Save
#    (브라우저 작업이라 CLI 명령 없음)

# 2) AWS Support case 생성
#    Console > Support Center > Create case > Service: Amazon Bedrock
#    Subject: "Anthropic Claude Sonnet X.X LEGACY 30일 게이트 해제 요청"
#    Body: account ID, model ID, 마지막 호출 일자, 비즈니스 사유
```

해결될 때까지의 임시 워크어라운드 — 벤치마크 설계 변경:

```bash
# ACTIVE 모델로 BEFORE 변경 (4.5를 BEFORE로, 4.6을 AFTER로 사용)
./run_benchmark.sh \
  --before-model global.anthropic.claude-sonnet-4-5-20250929-v1:0 \
  --after-model  global.anthropic.claude-sonnet-4-6
```

### Case B — Inference profile로 전환

```bash
# 1) 사용 가능한 profile 조회
aws bedrock list-inference-profiles --region <REGION> \
  --query "inferenceProfileSummaries[?contains(inferenceProfileId, '<MODEL_PARTIAL>')].inferenceProfileId"

# 2) 가장 적절한 profile 선택 (region 그룹 일치하는 것 우선):
#    - eu-* region 호출이면 eu.… 우선
#    - us-* region 호출이면 us.… 우선
#    - 그 외 또는 cross-region 분산이면 global.…

# 3) fsi_bench.py 호출 시 --before-model / --after-model 인자에 profile ID로 전달
```

### Case C — IAM 권한

```bash
# 현재 자격증명의 권한 확인
aws sts get-caller-identity
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names bedrock:InvokeModel \
  --resource-arns "arn:aws:bedrock:<REGION>::foundation-model/<MODEL>" \
  --region us-east-1   # IAM is global, region for endpoint only
```

`bedrock:InvokeModel` 결과가 `EXPLICIT_DENY` 또는 `IMPLICIT_DENY`이면 role/policy에 추가 필요.

## Verification

해결 후 확인:

```bash
# 5건 dry-run으로 reachability 검증
./run_benchmark.sh --quick \
  --before-model <BEFORE_PROFILE> \
  --after-model  <AFTER_PROFILE>
```

- [ ] 5건 모두 응답 받음 (`stop_reason=end_turn` 또는 `refusal`)
- [ ] `output/runner.log`에 `<<ERROR` 시작 라인이 0건
- [ ] 두 모델 모두 latency 5초 이내 (5초 초과 시 throttle 가능성)

## Post-incident

- [ ] 본 incident가 LEGACY-게이트 풀린 직후의 단발 케이스가 아니라 **재발 가능한 패턴**인지 판단:
  - 새 분기마다 새 모델 출시 → 30일 후 자동 LEGACY 전환 패턴이라면 quarterly로 access 재확인 절차 추가
- [ ] 30일 카운터 추적이 필요하면 `output/runner.log`의 마지막 호출 일자를 모델 ID별로 grep해 monitor

## See also

- [ADR-0001 — Inference Profile Only](../decisions/ADR-0001-inference-profile-only.md)
- [docs/architecture.md — Key Design Decisions](../architecture.md)
- AWS docs: [Bedrock pricing & model lifecycle](https://docs.aws.amazon.com/bedrock/latest/userguide/model-lifecycle.html)
