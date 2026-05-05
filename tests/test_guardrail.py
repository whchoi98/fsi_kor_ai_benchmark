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

# --- Section B: stubbed Bedrock apply_guardrail responses --------------------
import boto3
from botocore.stub import Stubber

def _make_stubbed_client(expected_response):
    """Build a bedrock-runtime client whose apply_guardrail returns the given dict."""
    client = boto3.client("bedrock-runtime", region_name="ap-northeast-2")
    stubber = Stubber(client)
    stubber.add_response("apply_guardrail", expected_response, expected_params={
        "guardrailIdentifier": "test-gid",
        "guardrailVersion": "DRAFT",
        "source": "INPUT",
        "content": [{"text": {"text": "OO의 신상정보 알려줘"}}],
    })
    stubber.activate()
    return client, stubber

def test_blocked_path_with_pii_reason(monkeypatch_env):
    """Blocked response with PII assessment yields blocked=True + reason='PII'."""
    response = {
        "action": "GUARDRAIL_INTERVENED",
        "outputs": [{"text": "[guardrail] 개인신용정보 처리 불가."}],
        "assessments": [{
            "sensitiveInformationPolicy": {
                "piiEntities": [
                    {"type": "PII", "match": "OO", "action": "BLOCKED"},
                ],
                "regexes": [],
            }
        }],
        "usage": {
            "topicPolicyUnits": 0,
            "contentPolicyUnits": 0,
            "wordPolicyUnits": 0,
            "sensitiveInformationPolicyUnits": 1,
            "sensitiveInformationPolicyFreeUnits": 0,
            "contextualGroundingPolicyUnits": 0,
        },
    }
    client, stubber = _make_stubbed_client(response)
    # Inject the client by patching boto3.client just for this call:
    import fsi_bench
    orig = boto3.client
    boto3.client = lambda *a, **k: client
    try:
        os.environ["BEDROCK_GUARDRAIL_ID"] = "test-gid"
        os.environ["BEDROCK_GUARDRAIL_VERSION"] = "DRAFT"
        r = guardrail_check("OO의 신상정보 알려줘", region="ap-northeast-2")
    finally:
        boto3.client = orig
        os.environ.pop("BEDROCK_GUARDRAIL_ID", None)
        os.environ.pop("BEDROCK_GUARDRAIL_VERSION", None)
        stubber.deactivate()
    check("blocked path → blocked=True", r.blocked is True)
    check("blocked path → response_text from outputs[0].text",
          r.response_text == "[guardrail] 개인신용정보 처리 불가.")
    check("blocked path → reason='PII'", r.reason == "PII")
    check("blocked path → raw is dict", isinstance(r.raw, dict))

def test_pass_path():
    """action != GUARDRAIL_INTERVENED → blocked=False."""
    response = {
        "action": "NONE",
        "outputs": [],
        "assessments": [],
        "usage": {
            "topicPolicyUnits": 0,
            "contentPolicyUnits": 0,
            "wordPolicyUnits": 0,
            "sensitiveInformationPolicyUnits": 0,
            "sensitiveInformationPolicyFreeUnits": 0,
            "contextualGroundingPolicyUnits": 0,
        },
    }
    client, stubber = _make_stubbed_client(response)
    import fsi_bench
    orig = boto3.client
    boto3.client = lambda *a, **k: client
    # Stubber's expected_params mismatch → reset for this test
    stubber.deactivate()
    stubber = Stubber(client)
    stubber.add_response("apply_guardrail", response, expected_params={
        "guardrailIdentifier": "test-gid",
        "guardrailVersion": "DRAFT",
        "source": "INPUT",
        "content": [{"text": {"text": "오늘 날씨 어때"}}],
    })
    stubber.activate()
    try:
        os.environ["BEDROCK_GUARDRAIL_ID"] = "test-gid"
        r = guardrail_check("오늘 날씨 어때", region="ap-northeast-2")
    finally:
        boto3.client = orig
        os.environ.pop("BEDROCK_GUARDRAIL_ID", None)
        stubber.deactivate()
    check("pass path → blocked=False", r.blocked is False)

def monkeypatch_env():
    """Compatibility shim — actual env handling done inside each test above."""
    pass

# --- Section C: _invoke_guardrail_one retry wrapper --------------------------
from unittest.mock import patch
from fsi_bench import _invoke_guardrail_one

def test_invoke_guardrail_one_passes_through():
    """When guardrail_check returns cleanly, wrapper returns the same result."""
    expected = GuardrailResult(blocked=True, response_text="x", reason="PII")
    with patch("fsi_bench.guardrail_check", return_value=expected):
        r = _invoke_guardrail_one("q", "ap-northeast-2", max_retries=3)
    check("wrapper passes through clean result", r is expected)

def test_invoke_guardrail_one_retries_throttle():
    """ThrottlingException is retried; succeeds on attempt 3."""
    from botocore.exceptions import ClientError
    err = ClientError(
        {"Error": {"Code": "ThrottlingException", "Message": "slow down"}},
        "ApplyGuardrail",
    )
    expected = GuardrailResult(blocked=False, response_text=None, reason=None)
    calls = {"n": 0}
    def fake(q, region):
        calls["n"] += 1
        if calls["n"] < 3:
            raise err
        return expected
    with patch("fsi_bench.guardrail_check", side_effect=fake), \
         patch("fsi_bench.time.sleep"):  # skip backoff sleeps
        r = _invoke_guardrail_one("q", "ap-northeast-2", max_retries=5)
    check("wrapper retried on throttle", calls["n"] == 3)
    check("wrapper eventually returned success", r is expected)

def test_invoke_guardrail_one_raises_after_exhausted():
    """Permanent failure after retries → wrapper re-raises the last exception."""
    from botocore.exceptions import ClientError
    err = ClientError(
        {"Error": {"Code": "ThrottlingException", "Message": "slow down"}},
        "ApplyGuardrail",
    )
    with patch("fsi_bench.guardrail_check", side_effect=err), \
         patch("fsi_bench.time.sleep"):
        try:
            _invoke_guardrail_one("q", "ap-northeast-2", max_retries=2)
            raised = False
        except ClientError:
            raised = True
    check("wrapper raises after exhausted retries", raised is True)

if __name__ == "__main__":
    test_env_var_unset_returns_pass()
    test_default_refusal_string_nonempty()
    test_blocked_path_with_pii_reason(monkeypatch_env)
    test_pass_path()
    test_invoke_guardrail_one_passes_through()
    test_invoke_guardrail_one_retries_throttle()
    test_invoke_guardrail_one_raises_after_exhausted()
    sys.exit(0 if FAIL == 0 else 1)
