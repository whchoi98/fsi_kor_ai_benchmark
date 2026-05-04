#!/usr/bin/env bash
# PreToolUse hook — block Bash commands containing AWS / Bedrock secrets.
#
# Protocol:
#   stdin  : JSON event from Claude Code (tool_input.command for Bash)
#   stdout : ignored on success
#   stderr : reason shown to the model on block
#   exit 0 : allow
#   exit 2 : BLOCK and surface stderr to the model
#
# Why this project needs it:
#   .claude/settings.local.json was previously seen carrying a literal
#   AWS_BEARER_TOKEN_BEDROCK value inside an `allow` entry. This hook
#   prevents Bash invocations from carrying that pattern forward.

set -euo pipefail

# Read the full event from stdin. Use jq if available, fall back to grep.
INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
else
  # Crude fallback: pull the "command" string. Good enough for the patterns below.
  CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//')
fi

[ -z "$CMD" ] && exit 0

block() {
  printf 'secret-scan: %s\n' "$1" >&2
  printf '  detected pattern in command: %s\n' "$2" >&2
  printf '  fix: move the secret to an env var loaded from .env (gitignored), then re-run.\n' >&2
  exit 2
}

# --- Pattern 1: Bedrock bearer token literal (base64-looking, prefixed ABSK)
# The key seen in this repo's history started with "ABSK". Block any literal
# beginning with that prefix in a command line.
if printf '%s' "$CMD" | grep -qE '\bABSK[A-Za-z0-9+/=]{20,}'; then
  block "Bedrock bearer token literal in command" "ABSK…"
fi

# --- Pattern 2: AWS access key ID (AKIA / ASIA prefix + 16 chars)
if printf '%s' "$CMD" | grep -qE '\b(AKIA|ASIA)[0-9A-Z]{16}\b'; then
  block "AWS access key ID in command" "AKIA/ASIA…"
fi

# --- Pattern 3: AWS secret access key assigned literally
# Match: AWS_SECRET_ACCESS_KEY=<40 base64 chars>
if printf '%s' "$CMD" | grep -qE 'AWS_SECRET_ACCESS_KEY=[A-Za-z0-9/+=]{40}'; then
  block "AWS secret access key literal" "AWS_SECRET_ACCESS_KEY=…"
fi

# --- Pattern 4: Bedrock bearer token assigned literally
# Match: AWS_BEARER_TOKEN_BEDROCK='<anything not empty / not $VAR>'
if printf '%s' "$CMD" | grep -qE "AWS_BEARER_TOKEN_BEDROCK=['\"]?[A-Za-z0-9+/=]{30,}"; then
  block "Bedrock bearer token assigned literally" "AWS_BEARER_TOKEN_BEDROCK=…"
fi

exit 0
