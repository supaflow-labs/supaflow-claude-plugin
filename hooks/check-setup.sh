#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: inject using-supaflow skill content into Claude's
# system context, plus setup warnings if CLI is not properly configured.

# Ensure Homebrew is on PATH for this script's own checks.
# Claude Code Desktop runs hooks with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin).
if [ -z "${_SUPAFLOW_HOOK_TEST:-}" ]; then
  if [ -d /opt/homebrew/bin ]; then
    export PATH="/opt/homebrew/bin:$PATH"
  elif [ -d /usr/local/bin ]; then
    export PATH="/usr/local/bin:$PATH"
  fi
fi

MIN_CLI_VERSION="0.1.12"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Read using-supaflow skill content ---
using_supaflow_content=$(cat "$PLUGIN_ROOT/skills/using-supaflow/SKILL.md" 2>/dev/null || echo "Error reading using-supaflow skill")

# --- Setup checks ---
warnings=()

# 1. Check Node.js
if ! command -v node &>/dev/null; then
  warnings+=("[SETUP] Node.js is not installed. Install Node.js 18+ first (brew install node on macOS, or see https://nodejs.org).")
else
  node_major=$(node --version 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
  if [ "${node_major:-0}" -lt 18 ]; then
    warnings+=("[SETUP] Node.js $(node --version) is too old. Upgrade to v18 or later.")
  fi
fi

# 2. Check supaflow CLI
if ! command -v supaflow &>/dev/null; then
  warnings+=("[SETUP] The Supaflow CLI is not installed. Run: npm install -g @getsupaflow/cli")
else
  cli_version=$(supaflow --version 2>/dev/null || echo "0.0.0")
  if [ "$(printf '%s\n' "$MIN_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$MIN_CLI_VERSION" ]; then
    warnings+=("[SETUP] The Supaflow CLI v${cli_version} is outdated. This plugin requires v${MIN_CLI_VERSION}+. Run: npm install -g @getsupaflow/cli")
  fi

  # 3. Check auth and workspace
  auth_output=$(supaflow auth status --json 2>/dev/null || echo '{}')
  authenticated=$(echo "$auth_output" | grep -o '"authenticated"[[:space:]]*:[[:space:]]*true' || true)
  if [ -z "$authenticated" ]; then
    warnings+=("[SETUP] The Supaflow CLI is not authenticated. The user needs an API key from https://app.supa-flow.io > Settings > API Keys, then run: supaflow auth login")
  else
    workspace_id=$(echo "$auth_output" | grep -o '"workspace_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
      warnings+=("[SETUP] No workspace selected. Run: supaflow workspaces select <name>")
    fi
  fi
fi

# --- Build context ---
context="$using_supaflow_content"
if [ ${#warnings[@]} -gt 0 ]; then
  context="${context}

## Setup Issues

Fix these before proceeding with any Supaflow operations:"
  for w in "${warnings[@]}"; do
    context="${context}
${w}"
  done
fi

# --- Escape and output structured JSON ---
escaped=$(printf '%s' "$context" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read())[1:-1])")

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped"

exit 0
