#!/usr/bin/env bash
# tests/test_secret_scan.sh — contract test for the PreToolUse secret-scan hook.
#
# The hook is the only active runtime security control in the harness, so it
# MUST have a test. We synthesize JSON events on stdin and assert exit codes:
#
#   exit 2  -> blocked (hook detected a secret pattern)
#   exit 0  -> allowed
#
# Trick: we never embed literal secret patterns in this file as contiguous
# substrings — they are reassembled at runtime via Python string concatenation
# so that future grep-based audits don't false-positive on the test fixture.
#
# Run: bash tests/test_secret_scan.sh
# Returns 0 if all assertions pass, 1 on first failure.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/.claude/hooks/secret-scan.sh"
cd "$ROOT"

[ -x "$HOOK" ] || { echo "FAIL: hook not executable: $HOOK" >&2; exit 1; }

pass=0
fail=0

run_hook() {
  # Pipe given JSON to the hook, return its exit code.
  printf '%s' "$1" | "$HOOK" >/dev/null 2>&1
  echo $?
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  ok   %-50s (exit=%s)\n' "$name" "$actual"
    pass=$((pass + 1))
  else
    printf '  FAIL %-50s (expected=%s, got=%s)\n' "$name" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

echo "secret-scan hook contract test"
echo "---"

# ── BLOCK cases (expect exit 2) ────────────────────────────────────────────────

# Pattern 1: Bedrock bearer token (ABSK + 30 base64 chars)
json_absk=$(python3 <<'PY'
import json
p = 'A' + 'B' + 'S' + 'K'
tok = p + 'X' * 30 + '='
print(json.dumps({"tool_input": {"command": f"export AWS_BEARER_TOKEN_BEDROCK={tok}"}}))
PY
)
assert_exit "blocks Bedrock bearer token literal" 2 "$(run_hook "$json_absk")"

# Pattern 2: AWS access key ID (AKIA prefix)
json_akia=$(python3 <<'PY'
import json
k = 'A' + 'K' + 'IA' + 'IOSFOD' + 'NN7EX' + 'AMPLE'
print(json.dumps({"tool_input": {"command": f"echo {k}"}}))
PY
)
assert_exit "blocks AKIA access key" 2 "$(run_hook "$json_akia")"

# Pattern 3: AWS temporary access key ID (ASIA prefix)
json_asia=$(python3 <<'PY'
import json
k = 'A' + 'S' + 'IA' + 'TESTKEY' + 'TESTKEY' + '12'
print(json.dumps({"tool_input": {"command": f"export AWS_ACCESS_KEY_ID={k}"}}))
PY
)
assert_exit "blocks ASIA temporary access key" 2 "$(run_hook "$json_asia")"

# Pattern 4: AWS_SECRET_ACCESS_KEY assigned literally (40 b64 chars)
json_aks=$(python3 <<'PY'
import json
v = 'X' * 40
print(json.dumps({"tool_input": {"command": f"AWS_SECRET_ACCESS_KEY={v} aws s3 ls"}}))
PY
)
assert_exit "blocks AWS_SECRET_ACCESS_KEY literal" 2 "$(run_hook "$json_aks")"

# ── ALLOW cases (expect exit 0) ────────────────────────────────────────────────

assert_exit "allows benign ls" 0 \
  "$(run_hook '{"tool_input":{"command":"ls -la"}}')"

assert_exit "allows env-var-deref bearer export" 0 \
  "$(run_hook '{"tool_input":{"command":"export AWS_BEARER_TOKEN_BEDROCK=$MY_TOKEN"}}')"

assert_exit "allows project script invocation" 0 \
  "$(run_hook '{"tool_input":{"command":"python3 fsi_bench.py --help"}}')"

assert_exit "allows AKIA-mention inside grep regex (no actual key)" 0 \
  "$(run_hook '{"tool_input":{"command":"grep AKIA logs"}}')"

assert_exit "allows tool_input with no command field" 0 \
  "$(run_hook '{"tool_input":{}}')"

assert_exit "allows non-Bash event (no tool_input.command)" 0 \
  "$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"foo"}}')"

echo "---"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
