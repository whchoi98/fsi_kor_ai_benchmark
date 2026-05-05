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

if __name__ == "__main__":
    test_system_prompt_returns_nonempty()
    test_system_prompt_covers_required_categories()
    test_system_prompt_side_invariant_by_default()
    sys.exit(0 if FAIL == 0 else 1)
