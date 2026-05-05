# Runbook — Guardrail troubleshooting

진단 대상: `fsi_bench.py`의 Stage 1 (`guardrail_check` / `_invoke_guardrail_one`).

## Symptom: 모든 record가 `blocked_by=null`인데 production에서는 차단되어야 함

가능한 원인:

1. **`BEDROCK_GUARDRAIL_ID` 환경변수 미설정** — `guardrail_check()`은 ID가 비어
   있으면 즉시 `blocked=False` 반환 (no-op pass). 의도된 fallback이지만,
   production 평가에서는 잘못된 결과를 만든다.
   - 확인: `env | grep BEDROCK_GUARDRAIL_`
   - 수정: `.env`에 `BEDROCK_GUARDRAIL_ID=<your-guardrail>` 추가 후 `source .env`.

2. **`--no-guardrail` 플래그가 켜져 있음** — `run_benchmark.sh` 또는 직접 호출에
   이 플래그가 들어가면 stage 1이 완전히 bypass된다.
   - 확인: 스크립트 인자 / shell history.

3. **가드레일 정책이 `INPUT` source를 평가하지 않도록 설정됨** —
   `apply_guardrail` 호출 시 `source="INPUT"`만 보내는데, 회사 가드레일이 OUTPUT
   전용으로 설정되어 있으면 항상 통과한다.
   - 확인: 콘솔에서 가드레일의 input/output filter 설정 검토.

## Symptom: `<<ERROR:guardrail:AccessDeniedException...>>`

원인: IAM 권한 누락. `apply_guardrail`은 `bedrock:ApplyGuardrail` 액션을
요구한다.

수정:
1. 사용자/role 정책에 추가:
   ```json
   {
     "Effect": "Allow",
     "Action": "bedrock:ApplyGuardrail",
     "Resource": "arn:aws:bedrock:<region>:<account>:guardrail/<id>"
   }
   ```
2. `AWS_BEARER_TOKEN_BEDROCK`을 쓰는 경우 token이 가드레일 권한을 포함하는지
   확인.

## Symptom: 가드레일 호출이 throttle 되어 진행이 매우 느림

`_invoke_guardrail_one()`은 exponential backoff (`2 ** attempt`)로 재시도한다.
지속 throttle 시:

1. `--workers`를 줄여 동시 호출 수를 낮춘다 (기본 8 → 4).
2. 영구 throttle은 결국 `last_err`을 raise하고 record는 `error` 클래스로
   분류된다. progress 파일을 통해 재실행 시 해당 index만 재시도된다.
3. 빠른 우회: `--no-guardrail`로 stage 1을 임시 skip하고 모델 응답만 측정한
   뒤, 가드레일 quota가 풀린 후 다시 실행. (단 결과는 production posture가 아닌
   raw model 응답이 되므로 FSI 제출용 아님.)

## Symptom: sidecar의 `guardrail_reason`이 자유문이거나 회사 정책 ID가 들어감

원칙: `guardrail_reason`은 **표준 카테고리 라벨만** 들어가야 한다 (예: `PII`,
`JAILBREAK`). 자유문이나 정책 ID가 들어가면 정보 누출 위험이 있고 sidecar 통계도
의미를 잃는다.

수정:
- `guardrail_check()`의 reason 추출 로직이 `cat.get("type") or cat.get("name")`
  외의 필드를 읽지 않는지 확인.
- 회사가 자체 가드레일로 fork했을 때 `GuardrailResult.reason`에 자유문을
  넣지 않도록 코드 검토.

## 관련 파일

- `fsi_bench.py:guardrail_check()` — 레퍼런스 구현 (EDIT-ME #1)
- `fsi_bench.py:_invoke_guardrail_one()` — 재시도 래퍼
- `tests/test_guardrail.py` — 단위 테스트
- `docs/decisions/ADR-0002-two-stage-pipeline.md` — 설계 의사결정
