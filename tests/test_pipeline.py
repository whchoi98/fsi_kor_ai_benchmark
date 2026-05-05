"""tests/test_pipeline.py — integration tests for the two-stage pipeline.

Run: python3 tests/test_pipeline.py
Exits 0 on success, 1 on first failure.

Pattern follows test_classify.py and test_guardrail.py.
"""
import os, sys, json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fsi_bench import build_system_prompt

FAIL = 0

def check(desc, cond):
    global FAIL
    if cond:
        print(f"  PASS  {desc}")
    else:
        print(f"  FAIL  {desc}")
        FAIL += 1

# --- Section A: build_system_prompt -----------------------------------------
def test_system_prompt_returns_nonempty():
    p = build_system_prompt("before")
    check("returns str", isinstance(p, str))
    check("non-empty", len(p) > 0)

def test_system_prompt_covers_required_categories():
    """Reference prompt must explicitly mention the FSI-critical categories.
    Companies are free to replace this; the reference is what ships in the repo
    and shapes the FSI ①경미 evaluation expectations."""
    p = build_system_prompt("before")
    check("mentions 시스템 프롬프트 비노출", "시스템 프롬프트" in p or "지침" in p)
    check("mentions 개인신용정보 / PII", "개인신용정보" in p or "신상정보" in p)
    check("mentions 해킹 / 무단 접근", "해킹" in p or "무단" in p or "악성코드" in p)
    check("mentions 허위정보 / 가짜뉴스", "허위" in p or "가짜" in p)

def test_system_prompt_side_invariant_by_default():
    """Reference impl should not branch on `side` — same prompt for both."""
    check("before == after by default",
          build_system_prompt("before") == build_system_prompt("after"))

# --- Section B: _invoke_one accepts system_prompt ---------------------------
from unittest.mock import MagicMock
from fsi_bench import _invoke_one

def _make_fake_rt(text="ok"):
    """Fake bedrock-runtime client capturing the body sent to invoke_model."""
    rt = MagicMock()
    captured = {}
    def fake_invoke(modelId, body):
        captured["modelId"] = modelId
        captured["body"] = json.loads(body)
        # mimic Bedrock response shape
        class FakeBody:
            def read(self_):
                return json.dumps({
                    "content": [{"text": text}],
                    "stop_reason": "end_turn",
                    "usage": {"input_tokens": 10, "output_tokens": 2},
                }).encode()
        return {"body": FakeBody()}
    rt.invoke_model.side_effect = fake_invoke
    return rt, captured

def test_invoke_one_passes_system_prompt_in_body():
    rt, captured = _make_fake_rt()
    _invoke_one(rt, "model-x", "001", "hello",
                system_prompt="YOU ARE A BANK BOT",
                max_tokens=100, temperature=0.0, max_retries=1)
    check("body has 'system' field",
          captured["body"].get("system") == "YOU ARE A BANK BOT")
    check("body has anthropic_version",
          captured["body"].get("anthropic_version") == "bedrock-2023-05-31")

def test_invoke_one_omits_system_when_empty():
    rt, captured = _make_fake_rt()
    _invoke_one(rt, "model-x", "001", "hello",
                system_prompt="",
                max_tokens=100, temperature=0.0, max_retries=1)
    check("empty system_prompt omitted from body",
          "system" not in captured["body"])

# --- Section C: _process_one (per-prompt pipeline) ---------------------------
from unittest.mock import patch
from fsi_bench import _process_one, GuardrailResult, Side

def _make_side(label="before", model_id="model-x", region="ap-northeast-2"):
    return Side(label=label, target_nfc=f"모델변경{('전' if label=='before' else '후')}.jsonl",
                model_id=model_id, region=region)

def test_process_one_pass_path_calls_model():
    """guardrail passes → _invoke_one is called and result fields populated."""
    side = _make_side()
    rt, captured = _make_fake_rt(text="안전한 답변")
    with patch("fsi_bench._invoke_guardrail_one",
               return_value=GuardrailResult(blocked=False, response_text=None, reason=None)):
        rec, meta = _process_one(side, rt, "001", "오늘 날씨",
                                 max_tokens=100, temperature=0.0, max_retries=1,
                                 no_guardrail=False)
    check("rec Index", rec["Index"] == "001")
    check("rec model", rec["model"] == "model-x")
    check("rec response from model", rec["response"] == "안전한 답변")
    check("meta blocked_by None", meta["blocked_by"] is None)
    check("meta guardrail_reason None", meta["guardrail_reason"] is None)
    check("meta stop_reason populated", meta["stop_reason"] == "end_turn")
    check("meta input_tokens populated", meta["input_tokens"] == 10)

def test_process_one_blocked_path_skips_model():
    """guardrail blocks → _invoke_one not called; response uses guardrail text."""
    side = _make_side()
    rt = MagicMock()
    rt.invoke_model.side_effect = AssertionError("must not be called")
    gr = GuardrailResult(blocked=True,
                         response_text="[guardrail] PII 차단",
                         reason="PII")
    with patch("fsi_bench._invoke_guardrail_one", return_value=gr):
        rec, meta = _process_one(side, rt, "002", "OO의 신용정보",
                                 max_tokens=100, temperature=0.0, max_retries=1,
                                 no_guardrail=False)
    check("rec response from guardrail", rec["response"] == "[guardrail] PII 차단")
    check("rec model preserved (side.model_id)", rec["model"] == "model-x")
    check("meta blocked_by", meta["blocked_by"] == "guardrail")
    check("meta guardrail_reason", meta["guardrail_reason"] == "PII")
    check("meta stop_reason None", meta["stop_reason"] is None)
    check("meta tokens None", meta["input_tokens"] is None and meta["output_tokens"] is None)

def test_process_one_blocked_uses_default_refusal_when_text_missing():
    """guardrail blocks but response_text=None → fall back to DEFAULT_GUARDRAIL_REFUSAL."""
    side = _make_side()
    rt = MagicMock()
    rt.invoke_model.side_effect = AssertionError("must not be called")
    gr = GuardrailResult(blocked=True, response_text=None, reason="JAILBREAK")
    from fsi_bench import DEFAULT_GUARDRAIL_REFUSAL
    with patch("fsi_bench._invoke_guardrail_one", return_value=gr):
        rec, _meta = _process_one(side, rt, "003", "q",
                                  max_tokens=100, temperature=0.0, max_retries=1,
                                  no_guardrail=False)
    check("falls back to DEFAULT_GUARDRAIL_REFUSAL",
          rec["response"] == DEFAULT_GUARDRAIL_REFUSAL)

def test_process_one_no_guardrail_bypasses_stage1():
    """no_guardrail=True → guardrail not consulted; goes straight to model."""
    side = _make_side()
    rt, _captured = _make_fake_rt(text="ok")
    called = {"n": 0}
    def must_not_be_called(*a, **kw):
        called["n"] += 1
    with patch("fsi_bench._invoke_guardrail_one", side_effect=must_not_be_called):
        rec, meta = _process_one(side, rt, "004", "q",
                                 max_tokens=100, temperature=0.0, max_retries=1,
                                 no_guardrail=True)
    check("guardrail bypassed", called["n"] == 0)
    check("model called (response set)", rec["response"] == "ok")
    check("meta blocked_by None", meta["blocked_by"] is None)

def test_process_one_guardrail_error_records_error():
    """Permanent guardrail failure → record with error= prefix 'guardrail:'."""
    side = _make_side()
    rt = MagicMock()
    rt.invoke_model.side_effect = AssertionError("must not be called")
    from botocore.exceptions import ClientError
    err = ClientError(
        {"Error": {"Code": "AccessDeniedException", "Message": "no perms"}},
        "ApplyGuardrail",
    )
    with patch("fsi_bench._invoke_guardrail_one", side_effect=err):
        rec, meta = _process_one(side, rt, "005", "q",
                                 max_tokens=100, temperature=0.0, max_retries=1,
                                 no_guardrail=False)
    check("response carries error marker", rec["response"].startswith("<<ERROR:"))
    check("error message has guardrail: prefix",
          "guardrail:" in rec["response"])
    check("meta stop_reason='error'", meta["stop_reason"] == "error")
    check("meta blocked_by None (it's a runner error, not a guardrail block)",
          meta["blocked_by"] is None)

def test_process_one_passes_system_prompt_to_model():
    """When stage 1 passes, build_system_prompt(side.label) is plumbed to _invoke_one."""
    side = _make_side(label="after")
    rt, captured = _make_fake_rt()
    with patch("fsi_bench._invoke_guardrail_one",
               return_value=GuardrailResult(blocked=False, response_text=None, reason=None)):
        _process_one(side, rt, "006", "q",
                     max_tokens=100, temperature=0.0, max_retries=1,
                     no_guardrail=False)
    check("body has 'system' (system_prompt was injected)",
          isinstance(captured["body"].get("system"), str) and
          len(captured["body"]["system"]) > 0)

# --- Section D: --no-guardrail CLI flag --------------------------------------
import subprocess

def test_cli_help_mentions_no_guardrail():
    """`fsi_bench.py --help` should advertise the new flag."""
    result = subprocess.run(
        [sys.executable, "fsi_bench.py", "--help"],
        capture_output=True, text=True, timeout=10,
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    )
    check("--help exits 0", result.returncode == 0)
    check("--help mentions --no-guardrail",
          "--no-guardrail" in result.stdout)

if __name__ == "__main__":
    test_system_prompt_returns_nonempty()
    test_system_prompt_covers_required_categories()
    test_system_prompt_side_invariant_by_default()
    test_invoke_one_passes_system_prompt_in_body()
    test_invoke_one_omits_system_when_empty()
    test_process_one_pass_path_calls_model()
    test_process_one_blocked_path_skips_model()
    test_process_one_blocked_uses_default_refusal_when_text_missing()
    test_process_one_no_guardrail_bypasses_stage1()
    test_process_one_guardrail_error_records_error()
    test_process_one_passes_system_prompt_to_model()
    test_cli_help_mentions_no_guardrail()
    sys.exit(0 if FAIL == 0 else 1)
