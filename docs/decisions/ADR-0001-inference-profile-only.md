# ADR-0001 — Bedrock 모델 호출은 Inference Profile로만 한다

- **Status**: Accepted
- **Date**: 2026-05-04
- **Deciders**: FSI AI Red Team

## Context

벤치마크가 호출하는 Anthropic 모델(Claude Sonnet 4.x 계열)은 Amazon Bedrock에서 두 가지 식별자 형태가 존재합니다:

1. **Direct foundation model ID** — 예: `anthropic.claude-sonnet-4-20250514-v1:0`
2. **Inference profile ID** — 예: `eu.anthropic.claude-sonnet-4-20250514-v1:0`, `global.anthropic.claude-sonnet-4-6`

`list-foundation-models` API는 양쪽 다 노출하기 때문에 직관적으로는 어느 것이든 호출 가능해 보이지만, 실제로는 그렇지 않습니다.

2026-05-04 검증 시 다음을 확인:

```
direct foundation ID 4.0:
  ValidationException: Invocation of model ID anthropic.claude-sonnet-4-20250514-v1:0
  with on-demand throughput isn't supported. Retry your request with the ID or ARN
  of an inference profile that contains this model.
```

이는 **on-demand 호출 시 cross-region Anthropic 모델은 inference profile만 받아들인다**는 Bedrock의 구조적 제약입니다. 직접 foundation ID는 provisioned throughput 환경에서만 의미가 있고, 우리 벤치마크는 모두 on-demand로 동작합니다.

## Decision

**프로젝트의 모든 Bedrock 모델 호출은 inference profile ID만 사용한다.** Direct foundation model ID는 코드, 설정, 문서, 사용자 입력 어느 곳에서도 받아들이지 않는다.

허용되는 prefix:
- `eu.…` — EU region 그룹 내 라우팅
- `us.…` — US region 그룹 내 라우팅
- `global.…` — 전역 라우팅
- `apac.…` — APAC region 그룹 내 라우팅

금지되는 형태:
- `anthropic.claude-…` 식의 prefix-less foundation ID

## Consequences

### Positive
- `ValidationException` 형태의 런타임 오류를 사전 차단.
- 모델 변경 시 가용 region 풀이 자동으로 따라옴 (profile이 region routing을 책임짐) — 단일 region 다운 시에도 라우팅으로 흡수.
- DEFAULT 모델 ID를 보면 routing 의도가 즉시 드러남 (`eu.…` vs `global.…`).

### Negative / Trade-offs
- Provisioned throughput으로 전환할 일이 생기면 본 ADR을 superseding하는 새 ADR 필요.
- Profile은 AWS가 통제하는 system-defined 자원이라, 새 모델이 출시돼도 profile이 등록되기 전까지는 호출 불가 — 약간의 시차 존재.

### Neutral
- direct ID와 profile ID가 외형은 비슷하지만 (`anthropic.…` vs `eu.anthropic.…`) 실질은 다른 자원 — 코드 리뷰 시 이 prefix를 명시적으로 확인.

## Alternatives Considered

1. **Direct foundation ID 허용**: 호출 시점에 `ValidationException` 발생 — UX 측면에서 실패 시점이 너무 늦음. 입력 검증 단계에서 거르는 게 나음.
2. **혼용 허용 + 자동 fallback**: direct ID로 호출 실패 시 같은 모델의 inference profile로 재시도. 복잡성 증가, 라우팅 의도가 코드에서 가려짐. 거부.
3. **Profile ID를 코드에 hardcode 하지 않고 환경변수로만**: 유연하지만 기본값이 여러 곳에 분산되면 검토 비용 증가. 거부.

## Implementation Notes

- `fsi_bench.py`의 `DEFAULT_BEFORE_MODEL`, `DEFAULT_AFTER_MODEL` 상수가 이미 `global.…` profile 형태이므로 코드 변경 불필요.
- 향후 입력 검증 추가 시: model_id가 `^(eu|us|global|apac)\.` 패턴으로 시작하지 않으면 `parse_args()` 단계에서 거부할 것.
- `tests/smoke.sh`에 정규식 검증을 추가하면 회귀 방지 가능 (선택적).

## References

- Related code: `fsi_bench.py` `parse_args()` (line 624 부근), `_invoke_one()` (line 263 부근)
- Related architecture doc: [docs/architecture.md](../architecture.md) "Key Design Decisions" 항목 — "Inference profiles only — never direct foundation IDs"
- Related runbook: [docs/runbooks/bedrock-model-access-denied.md](../runbooks/bedrock-model-access-denied.md)
- AWS docs: [Bedrock cross-region inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/cross-region-inference.html)
