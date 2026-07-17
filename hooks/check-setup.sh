#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: inject using-supaflow skill content into Claude's
# system context, plus CLI-path setup warnings if CLI is not properly configured.

# Ensure Homebrew is on PATH for this script's own checks.
# Claude Code Desktop runs hooks with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin).
if [ -z "${_SUPAFLOW_HOOK_TEST:-}" ]; then
  if [ -d /opt/homebrew/bin ]; then
    export PATH="/opt/homebrew/bin:$PATH"
  elif [ -d /usr/local/bin ]; then
    export PATH="/usr/local/bin:$PATH"
  fi
fi

MIN_CLI_VERSION="0.4.1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Read setup gate + using-supaflow skill content (gate first) ---
setup_preamble_content=$(cat "$PLUGIN_ROOT/skills/using-supaflow/setup-preamble.md" 2>/dev/null || echo "Error reading setup-preamble")
using_supaflow_content=$(cat "$PLUGIN_ROOT/skills/using-supaflow/SKILL.md" 2>/dev/null || echo "Error reading using-supaflow skill")

# --- CLI-path setup checks ---
# The hook cannot see Claude Desktop's active MCP tools. These warnings apply to
# the terminal CLI fallback path; the injected setup gate chooses MCP first when
# mcp__supaflow__auth_status is available.
warnings=()

# 1. Check Node.js
if ! command -v node &>/dev/null; then
  warnings+=("[SETUP:CLI] Node.js is not installed (need v18+). Resolve via the CLI gate above before using the terminal CLI path.")
else
  node_major=$(node --version 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
  if [ "${node_major:-0}" -lt 18 ]; then
    warnings+=("[SETUP:CLI] Node.js $(node --version) is too old (need v18+). Resolve via the CLI gate above before using the terminal CLI path.")
  fi
fi

# 2. Check supaflow CLI
if ! command -v supaflow &>/dev/null; then
  warnings+=("[SETUP:CLI] The Supaflow CLI is not installed. Resolve via the CLI gate above (offer to install, run only on confirmation) before using the terminal CLI path.")
else
  cli_version=$(supaflow --version 2>/dev/null || echo "0.0.0")
  if [ "$(printf '%s\n' "$MIN_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$MIN_CLI_VERSION" ]; then
    warnings+=("[SETUP:CLI] The Supaflow CLI v${cli_version} is outdated (requires v${MIN_CLI_VERSION}+). Resolve via the CLI gate above (offer to upgrade, run only on confirmation) before using the terminal CLI path.")
  fi

  # 3. Check auth and workspace
  auth_output=$(supaflow auth status --json 2>/dev/null || echo '{}')
  authenticated=$(echo "$auth_output" | grep -o '"authenticated"[[:space:]]*:[[:space:]]*true' || true)
  if [ -z "$authenticated" ]; then
    warnings+=("[SETUP:CLI] The Supaflow CLI is not authenticated. Resolve via the CLI gate above (user runs 'supaflow auth login' themselves; no API key in chat) before using the terminal CLI path.")
  else
    workspace_id=$(echo "$auth_output" | grep -o '"workspace_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
      warnings+=("[SETUP:CLI] No workspace selected. Resolve via the CLI gate above (run: supaflow workspaces select <name>) before using the terminal CLI path.")
    fi
  fi
fi

# --- Build context (setup gate first, then the entry skill) ---
context="${setup_preamble_content}

${using_supaflow_content}"
if [ ${#warnings[@]} -gt 0 ]; then
  context="${context}

## CLI Path Setup Issues (detected this session)

These apply only when the CLI fallback path is active. If mcp__supaflow__auth_status is available, run the MCP gate instead:"
  for w in "${warnings[@]}"; do
    context="${context}
${w}"
  done
fi

# --- Escape and output structured JSON ---
escaped=$(printf '%s' "$context" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read())[1:-1])")

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped"

exit 0
