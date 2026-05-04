#!/usr/bin/env bash
# PreToolUse hook — block `git commit` commands that add Claude as a contributor.
#
# Protocol:
#   stdin  : JSON event from Claude Code (tool_input.command for Bash)
#   stdout : ignored on success
#   stderr : reason shown to the model on block
#   exit 0 : allow
#   exit 2 : BLOCK and surface stderr to the model
#
# Why:
#   Maintainer (whchoi98@gmail.com) does not want Claude listed as a
#   co-author on commits in this repo. Block at commit creation time —
#   `git push` only ships existing commit objects, so blocking commit
#   is sufficient.

set -euo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
else
  CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//')
fi

[ -z "$CMD" ] && exit 0

# Only inspect git commit invocations. `git push` carries no commit message.
case "$CMD" in
  *"git commit"*|*"git "*"commit"*) ;;
  *) exit 0 ;;
esac

block() {
  printf 'no-claude-coauthor: %s\n' "$1" >&2
  printf '  detected pattern: %s\n' "$2" >&2
  printf '  fix: remove the Claude co-author trailer / Generated-with line from the commit message, then retry.\n' >&2
  exit 2
}

# Pattern 1: Co-Authored-By trailer naming Claude (case-insensitive).
if printf '%s' "$CMD" | grep -qiE 'co-authored-by:[[:space:]]*claude'; then
  block "Co-Authored-By: Claude trailer in commit message" "Co-Authored-By: Claude"
fi

# Pattern 2: Anthropic noreply email (the canonical Claude Code co-author email).
if printf '%s' "$CMD" | grep -qiE 'noreply@anthropic\.com'; then
  block "Claude Code noreply email in commit message" "noreply@anthropic.com"
fi

# Pattern 3: "Generated with Claude Code" tagline.
if printf '%s' "$CMD" | grep -qiE 'generated with[^\n]*claude'; then
  block "'Generated with Claude Code' tagline in commit message" "Generated with … Claude"
fi

exit 0
