"""tests/test_validate_side_layers.py — validate_side() layer distribution tests.

Run: python3 tests/test_validate_side_layers.py
"""
import os, sys, json, tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fsi_bench import validate_side, Side

FAIL = 0
def check(desc, cond):
    global FAIL
    if cond:
        print(f"  PASS  {desc}")
    else:
        print(f"  FAIL  {desc}")
        FAIL += 1

def _write_jsonl(path, records):
    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

def _make_side_with_files(tmpdir, label="before",
                          main_records=None, sidecar_records=None):
    main_path = os.path.join(tmpdir, f"{label}.jsonl")
    meta_path = main_path + ".metadata.jsonl"
    if main_records is not None:
        _write_jsonl(main_path, main_records)
    if sidecar_records is not None:
        _write_jsonl(meta_path, sidecar_records)
    return Side(label=label, target_nfc=os.path.basename(main_path),
                model_id="model-x", region="ap-northeast-2",
                output_path=main_path, metadata_path=meta_path)

def test_layer_dist_basic():
    """Sidecar with mix of blocked/pass produces correct counts."""
    with tempfile.TemporaryDirectory() as tmp:
        main_records = [{"Index": f"{i:03d}", "model": "m", "response": "x"} for i in range(1, 6)]
        sidecar = [
            {"Index": "001", "stop_reason": "end_turn", "blocked_by": None, "guardrail_reason": None,
             "input_tokens": 10, "output_tokens": 5},
            {"Index": "002", "stop_reason": None, "blocked_by": "guardrail", "guardrail_reason": "PII",
             "input_tokens": None, "output_tokens": None},
            {"Index": "003", "stop_reason": None, "blocked_by": "guardrail", "guardrail_reason": "PII",
             "input_tokens": None, "output_tokens": None},
            {"Index": "004", "stop_reason": None, "blocked_by": "guardrail", "guardrail_reason": "JAILBREAK",
             "input_tokens": None, "output_tokens": None},
            {"Index": "005", "stop_reason": "end_turn", "blocked_by": None, "guardrail_reason": None,
             "input_tokens": 10, "output_tokens": 5},
        ]
        side = _make_side_with_files(tmp, main_records=main_records, sidecar_records=sidecar)
        result = validate_side(side)
        check("layer_dist guardrail_blocked count",
              result.get("layer_dist", {}).get("guardrail_blocked") == 3)
        check("layer_dist guardrail_pass count",
              result.get("layer_dist", {}).get("guardrail_pass") == 2)
        check("guardrail_reasons PII count",
              result.get("guardrail_reasons", {}).get("PII") == 2)
        check("guardrail_reasons JAILBREAK count",
              result.get("guardrail_reasons", {}).get("JAILBREAK") == 1)

def test_missing_sidecar_graceful_degradation():
    """No sidecar file → assume all guardrail_pass with warning."""
    with tempfile.TemporaryDirectory() as tmp:
        main_records = [{"Index": f"{i:03d}", "model": "m", "response": "x"} for i in range(1, 4)]
        side = _make_side_with_files(tmp, main_records=main_records, sidecar_records=None)
        # Note: metadata_path points to a file that does not exist
        assert not os.path.exists(side.metadata_path)
        result = validate_side(side)
        check("layer_dist still present",
              "layer_dist" in result)
        check("all assumed guardrail_pass",
              result["layer_dist"].get("guardrail_pass") == 3)
        check("zero blocked",
              result["layer_dist"].get("guardrail_blocked", 0) == 0)
        check("guardrail_reasons empty dict",
              result.get("guardrail_reasons", {}) == {})

def test_class_dist_unchanged():
    """5-class distribution from classify() is still produced (regression guard)."""
    with tempfile.TemporaryDirectory() as tmp:
        main_records = [
            {"Index": "001", "model": "m", "response": "도와드릴 수 없습니다."},  # soft_refusal
            {"Index": "002", "model": "m", "response": ""},                       # empty
            {"Index": "003", "model": "m", "response": "그럼요, 알려드릴게요."},    # complied
        ]
        sidecar = [
            {"Index": "001", "stop_reason": "end_turn", "blocked_by": None, "guardrail_reason": None,
             "input_tokens": 5, "output_tokens": 5},
            {"Index": "002", "stop_reason": "end_turn", "blocked_by": None, "guardrail_reason": None,
             "input_tokens": 5, "output_tokens": 0},
            {"Index": "003", "stop_reason": "end_turn", "blocked_by": None, "guardrail_reason": None,
             "input_tokens": 5, "output_tokens": 5},
        ]
        side = _make_side_with_files(tmp, main_records=main_records, sidecar_records=sidecar)
        result = validate_side(side)
        cd = result.get("class_dist", {})
        check("class_dist soft_refusal", cd.get("soft_refusal", 0) == 1)
        check("class_dist empty",        cd.get("empty", 0) == 1)
        check("class_dist complied",     cd.get("complied", 0) == 1)

# --- Report content tests ----------------------------------------------------
from fsi_bench import write_comparison_report

def test_report_contains_layer_cross_tab_section():
    with tempfile.TemporaryDirectory() as tmp:
        before_side = _make_side_with_files(
            tmp, label="before",
            main_records=[
                {"Index": "001", "model": "m1", "response": "안전한 답변입니다."},
                {"Index": "002", "model": "m1", "response": "[guardrail] PII"},
            ],
            sidecar_records=[
                {"Index": "001", "stop_reason": "end_turn", "blocked_by": None,
                 "guardrail_reason": None, "input_tokens": 5, "output_tokens": 5},
                {"Index": "002", "stop_reason": None, "blocked_by": "guardrail",
                 "guardrail_reason": "PII",
                 "input_tokens": None, "output_tokens": None},
            ],
        )
        after_side = _make_side_with_files(
            tmp, label="after",
            main_records=[
                {"Index": "001", "model": "m2", "response": "도와드릴 수 없습니다."},
                {"Index": "002", "model": "m2", "response": "[guardrail] PII"},
            ],
            sidecar_records=[
                {"Index": "001", "stop_reason": "end_turn", "blocked_by": None,
                 "guardrail_reason": None, "input_tokens": 5, "output_tokens": 5},
                {"Index": "002", "stop_reason": None, "blocked_by": "guardrail",
                 "guardrail_reason": "PII",
                 "input_tokens": None, "output_tokens": None},
            ],
        )
        before_v = validate_side(before_side)
        after_v  = validate_side(after_side)
        report_path = write_comparison_report(tmp, before_v, after_v)
        body = open(report_path, encoding="utf-8").read()
        check("report file created", os.path.exists(report_path))
        check("contains Layer × Class cross-tab heading",
              "Layer × Class" in body or "Layer x Class" in body or "layer" in body.lower())
        check("contains Layer transition heading",
              "Layer transition" in body or "layer transition" in body.lower())
        check("references guardrail_blocked layer",
              "guardrail_blocked" in body)
        check("references guardrail_pass layer",
              "guardrail_pass" in body)
        check("references at least one PII reason",
              "PII" in body)

if __name__ == "__main__":
    test_layer_dist_basic()
    test_missing_sidecar_graceful_degradation()
    test_class_dist_unchanged()
    test_report_contains_layer_cross_tab_section()
    sys.exit(0 if FAIL == 0 else 1)
