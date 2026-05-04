#!/usr/bin/env bash
# tests/test_smoke.sh — light smoke test for fsi-kor-ai-benchmark.
#
# This is intentionally NOT a TAP harness. The project is small (one Python
# file + one bash wrapper); a full test framework would dwarf the code under
# test. This script just guards the surfaces that have broken in practice:
#   1. Bash wrapper parses cleanly
#   2. Python runner imports and `--help` works (catches syntax errors)
#   3. Required input dataset is present and parses as JSONL
#   4. boto3 is importable
#
# Run:
#   bash tests/test_smoke.sh
#
# Exits non-zero on first failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pass=0
fail=0

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  FAIL %s\n' "$name"
    fail=$((fail + 1))
  fi
}

echo "fsi-kor-ai-benchmark smoke test"
echo "---"

check "run_benchmark.sh parses (bash -n)" \
  bash -n run_benchmark.sh

check "fsi_bench.py compiles" \
  python3 -m py_compile fsi_bench.py

check "python3 fsi_bench.py --help works" \
  python3 fsi_bench.py --help

check "boto3 is importable" \
  python3 -c "import boto3"

check "input dataset exists" \
  test -f doc/jailbreakbench.jsonl

check "input dataset parses as JSONL (300 lines)" \
  bash -c 'lines=$(wc -l < doc/jailbreakbench.jsonl); [ "$lines" -eq 300 ]'

check "repair_input() produces valid JSONL" \
  python3 -c "
import os, sys, tempfile, json
sys.path.insert(0, '.')
from fsi_bench import repair_input
with tempfile.TemporaryDirectory() as d:
    dst = os.path.join(d, 'fixed.jsonl')
    repair_input('doc/jailbreakbench.jsonl', dst, verbose=False)
    with open(dst, encoding='utf-8') as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            json.loads(line)  # raises on failure
"

check "classify() edge cases" \
  python3 tests/test_classify.py

check "secret-scan hook contract" \
  bash tests/test_secret_scan.sh

check "FSI submission schema is valid JSON Schema" \
  python3 -c "
import json
with open('docs/submission-schema.json') as f:
    s = json.load(f)
required = {'\$schema', 'type', 'required', 'properties'}
assert required.issubset(s.keys()), f'missing keys: {required - s.keys()}'
assert s['required'] == ['Index', 'model', 'response'], f'unexpected required fields: {s[\"required\"]}'
"

check "ADR-0001 model-id constraint matches DEFAULT_*_MODEL constants" \
  python3 -c "
import re, sys
sys.path.insert(0, '.')
import fsi_bench
allowed = re.compile(r'^(eu|us|global|apac)\.')
for name in ('DEFAULT_BEFORE_MODEL', 'DEFAULT_AFTER_MODEL'):
    val = getattr(fsi_bench, name)
    assert allowed.match(val), f'{name}={val!r} violates ADR-0001 (no inference profile prefix)'
"

check "docs cross-references resolve" \
  python3 -c "
import re, os, sys
files = ['CLAUDE.md', 'README.md', 'docs/architecture.md',
         'docs/decisions/ADR-0001-inference-profile-only.md',
         'docs/runbooks/bedrock-model-access-denied.md']
md_link = re.compile(r'\]\(([^)#]+\.md)([^)]*)\)')
errors = []
for f in files:
    if not os.path.isfile(f): continue
    base = os.path.dirname(f)
    with open(f, encoding='utf-8') as fh:
        for i, line in enumerate(fh, 1):
            for m in md_link.finditer(line):
                target = m.group(1)
                if target.startswith('http'): continue
                resolved = os.path.normpath(os.path.join(base, target))
                if not os.path.isfile(resolved):
                    errors.append(f'{f}:{i}  -> missing {resolved}')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
"

echo "---"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
