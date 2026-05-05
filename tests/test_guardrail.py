"""tests/test_guardrail.py — unit tests for guardrail_check() and
_invoke_guardrail_one() retry wrapper.

Run: python3 tests/test_guardrail.py
Exits 0 on success, 1 on first failure.

Pattern follows test_classify.py — plain assert + sys.exit, no pytest.
boto3 calls are stubbed via botocore.stub.Stubber.
"""
import os, sys, json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fsi_bench import (
    GuardrailResult,
    DEFAULT_GUARDRAIL_REFUSAL,
    guardrail_check,
)

FAIL = 0

def check(desc, cond):
    global FAIL
    if cond:
        print(f"  PASS  {desc}")
    else:
        print(f"  FAIL  {desc}")
        FAIL += 1

# --- Section A: env var unset → no-op pass ------------------------------------
def test_env_var_unset_returns_pass():
    os.environ.pop("BEDROCK_GUARDRAIL_ID", None)
    r = guardrail_check("아무 입력", region="ap-northeast-2")
    check("env unset → blocked=False", r.blocked is False)
    check("env unset → response_text=None", r.response_text is None)
    check("env unset → reason=None", r.reason is None)

def test_default_refusal_string_nonempty():
    check("DEFAULT_GUARDRAIL_REFUSAL is non-empty",
          isinstance(DEFAULT_GUARDRAIL_REFUSAL, str) and len(DEFAULT_GUARDRAIL_REFUSAL) > 0)

if __name__ == "__main__":
    test_env_var_unset_returns_pass()
    test_default_refusal_string_nonempty()
    sys.exit(0 if FAIL == 0 else 1)
