# ADR-0002 — Two-stage pipeline (guardrail → guarded service)

- **Status**: Accepted
- **Date**: 2026-05-04
- **Deciders**: 메인테이너
- **Supersedes / Related**: ADR-0001 (inference-profile-only)

## Context

금융위원회는 2026.4.15. 정례회의에서 「생성형 AI 모델 변경 시 혁신금융서비스 변경
절차 개선 방안」을 확정했다 (https://sandbox.fintech.or.kr/support/notice_detail.do?lang=ko&id=3791).
금융회사가 모델을 변경할 때 **서면확인서**를 한국핀테크지원센터에 제출하면
금융보안원이 보안 영향도에 따라 ①경미 / ②보통 / ③상당으로 분류해 처리 절차를
결정한다. 분류의 핵심 기준은 "모델 변경 전후 입력 정보의 범위·형식 및 답변·처리
결과의 변화 정도"이며, 평가는 **회사 production 스택 (가드레일 + system prompt가
적용된 서비스)** 응답 기준이다.

기존 `fsi_bench.py`는 Bedrock `invoke_model`을 직접 호출해 raw foundation model
응답만 산출했다. 이는:
- 회사 production 가드레일이 catch하는 위험 질문조차 모델까지 흘려 거절율이
  실제 배포보다 낮게 보인다.
- 서면확인서 첨부 자료로 그대로 쓰면 평가자가 보는 응답이 실제 사용자 경험과
  괴리된다.

## Decision

`fsi_bench.py`의 한-prompt 처리를 두 stage로 확장한다:

1. **Stage 1 — Guardrail**: `guardrail_check(prompt, region)` 호출. 차단 시 모델
   호출을 skip하고 가드레일이 준 거절 메시지(또는 fallback 표준 문구)를 응답으로
   기록한다.
2. **Stage 2 — Guarded service**: `build_system_prompt(side)`로 system prompt를
   주입한 `_invoke_one()` 호출.

차단 정보(`blocked_by`, `guardrail_reason`)는 **sidecar에만** 기록한다. FSI 제출
양식의 메인 JSONL은 `{Index, model, response}` 세 필드 고정으로 유지한다.

가드레일과 system prompt는 회사마다 다르므로 **fork-and-edit reference
implementation** 패턴을 채택한다. 회사가 손대는 곳은 정확히 두 함수
(`guardrail_check`, `build_system_prompt`)의 본체뿐이다.

## Consequences

**Positive**:
- harness 출력이 FSI 평가자가 실제로 보는 응답과 동등 — 서면확인서 첨부 자료의
  의미가 분명해진다.
- `comparison_report.md`에 "양쪽 모두 guardrail_blocked" 카운트가 추가되어
  ①경미 등급의 결정적 증거가 된다.
- 5-class classifier는 응답 텍스트만 보는 순수 함수로 유지된다 — 단위 테스트
  변경 zero.

**Negative / trade-offs**:
- prompt당 네트워크 호출이 1회 → 최대 2회로 증가 (가드레일 차단 시 1회).
- 회사가 fork할 때 본 repo의 두 함수 본체와 충돌 가능 — 다만 본 repo는 라이브러리가
  아닌 reference이므로 큰 부담 아님.
- sidecar 스키마에 `blocked_by` / `guardrail_reason` 두 필드가 추가되어 기존
  resume 데이터가 새 필드로 자동 마이그레이션되지 않음 (graceful degradation:
  필드 누락 시 `guardrail_pass`로 가정).

**Neutral**:
- FSI 메인 JSONL 스키마 불변 — 외부 호환성 깨지지 않음.
- 가드레일 차단 record의 `model` 필드는 `side.model_id`로 유지 (어느 side
  결과인지 식별 보존). 차단 사실은 sidecar에 격리.

## Alternatives considered

- **별도 도구 `submit_pipeline.py`로 분리**: 코드 중복 + 도구 두 개 운영 부담. 채택 X.
- **Classifier에 6번째 class `guardrail_blocked` 추가**: `classify()` 시그니처가
  사이드카 인자를 받아야 해 순수성이 깨진다. 채택 X — 대신 두 번째 축(layer)으로
  분리.
- **CLI로 외부 명령 위임 (`--guardrail-cmd "python my_guardrail.py"`)**: 언어 무관
  플러그인 모델로는 매력적이나, 본 repo의 reference 사용 패턴과 결이 안 맞고
  프로세스 spawn 비용이 600회 발생. 채택 X.

## Implementation Notes

- **Stage 1 dispatch (`FSI_GUARDRAIL_MODE`)**: 본 ADR 채택 후 `guardrail_check()`
  본체에 dispatch 분기가 추가되었다. `FSI_GUARDRAIL_MODE=sample` 설정 시
  `samples/local_guardrail.py` 의 로컬 패턴 매칭 가드레일로 라우팅. 비어있으면
  레퍼런스 Bedrock 분기 사용. 알 수 없는 값은 fail-safe 하게 Bedrock 분기로
  fall-through (env-var 오타가 무인지 차단으로 이어지지 않게). 새 결정이 아니라
  본 ADR 의 fork-and-edit 패턴을 demo/smoke 시나리오로 확장한 것이므로 별도
  ADR 을 만들지 않았다.
- **`samples/` 디렉토리**: leaf 모듈로 격리되어 있어 회사 fork 가 본 repo 의
  fsi_bench.py 본체와 merge conflict 없이 자체 가드레일을 추가할 수 있다.
  `fsi_bench.guardrail_check` 가 sample 모듈을 lazy import 하므로 미사용 fork
  에서는 import 자체가 발생하지 않는다.

## References

- 공지: https://sandbox.fintech.or.kr/support/notice_detail.do?lang=ko&id=3791
- Spec: `docs/superpowers/specs/2026-05-04-two-stage-pipeline-design.md`
- ADR-0001 (inference-profile-only): `docs/decisions/ADR-0001-inference-profile-only.md`
- Runbook (operations): `docs/runbooks/running-the-benchmark.md`
