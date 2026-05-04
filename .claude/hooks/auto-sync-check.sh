#!/usr/bin/env bash
# PostToolUse hook — emit auto-sync reminder when source files are edited.
#
# Maps the Auto-Sync Rules in CLAUDE.md to actual file changes:
#   fsi_bench.py changes  → CLAUDE.md (Key Modules / Key Commands) +
#                           docs/architecture.md (Components / Runtime Defaults)
#   run_benchmark.sh      → CLAUDE.md (Key Commands)
#   new ADR/runbook       → CLAUDE.md Reference section cross-link
#   docs/architecture.md  → check that Key Design Decisions still reflect code
#
# Protocol:
#   stdin   : JSON event from Claude Code (tool_name + tool_input.file_path)
#   stderr  : reminder shown to model after the tool call
#   stdout  : ignored
#   exit 0  : always (PostToolUse cannot block — purely advisory)
#
# This is a forward-leaning, non-blocking nudge. False positives are cheap;
# false negatives mean docs drift. So we err on the side of nudging.

set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
  FPATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
else
  TOOL=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"/\1/')
  FPATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"/\1/')
fi

# Only react to file mutations
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

[ -z "$FPATH" ] && exit 0

remind() {
  printf 'auto-sync: %s\n' "$1" >&2
}

base=$(basename -- "$FPATH")
case "$FPATH" in
  *fsi_bench.py)
    remind "fsi_bench.py changed — review:"
    remind "  • CLAUDE.md  '핵심 명령' / '핵심 모듈'"
    remind "  • docs/architecture.md  Components by Layer / Runtime Defaults / Key Design Decisions"
    ;;
  *run_benchmark.sh)
    remind "run_benchmark.sh changed — review CLAUDE.md '핵심 명령' for new flags or workflow"
    ;;
  */docs/decisions/ADR-*.md)
    remind "ADR changed — verify CLAUDE.md 'Reference' section has the correct cross-link"
    ;;
  */docs/runbooks/*.md)
    case "$base" in
      .template.md) ;;  # ignore template
      *) remind "Runbook changed — verify CLAUDE.md 'Reference' section lists this runbook" ;;
    esac
    ;;
  */docs/architecture.md)
    remind "architecture.md changed — verify the change is still consistent with fsi_bench.py and CLAUDE.md 'Auto-Sync Rules'"
    ;;
esac

exit 0
