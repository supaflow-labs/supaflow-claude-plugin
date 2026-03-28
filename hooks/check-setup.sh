#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: verify @getsupaflow/cli is installed, meets minimum
# version, is authenticated, and has a workspace selected.
# Outputs structured JSON so the Claude harness injects context into the session.

MIN_CLI_VERSION="0.1.9"

OPERATING_RULES="Supaflow CLI Operating Rules:
- Always run datasources list before asking for credentials or creating datasources.
- Always run pipelines list before creating a new pipeline.
- Match projects by warehouse_datasource_id, not warehouse_name.
- Parse JSON output with python3 -c -- never dump full JSON into conversation.
- Use jobs status for polling (4 fields: id, job_status, status_message, job_response). Use jobs get only after terminal state.
- jobs get fields: execution_duration_ms, ended_at, job_response, object_details. Never use: duration, completed_at, objects, rows_read.
- pipelines list fields: nested source.name, destination.name, source.datasource_id. Never use flat guessed fields.
- pipelines schema list field: use object, not fully_qualified_name or name.
- datasources catalog field: use fully_qualified_name, not guessed schema.name.
- Never invent fields not present in CLI output.
- Never silently rename or retry after a duplicate constraint error. Stop and ask.
- Never ask for passwords or secrets in chat. Tell the user to edit the env file.
- Wait for explicit user confirmation before pipelines create.
- For datasources catalog, use --output <file> and parse locally. Never dump into conversation.
- On failed job, use jobs get + jobs logs before diagnosing. Never blindly retry."

warnings=()

# 1. Check Node.js
if ! command -v node &>/dev/null; then
  warnings+=("Node.js is not installed. Install Node.js 18+ first (brew install node on macOS, or see https://nodejs.org).")
else
  node_major=$(node --version 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
  if [ "${node_major:-0}" -lt 18 ]; then
    warnings+=("Node.js $(node --version) is too old. Upgrade to v18 or later.")
  fi
fi

# 2. Check supaflow CLI is installed
if ! command -v supaflow &>/dev/null; then
  warnings+=("The Supaflow CLI is not installed. Run: npm install -g @getsupaflow/cli")
else
  # 2b. Check minimum version
  cli_version=$(supaflow --version 2>/dev/null || echo "0.0.0")
  if [ "$(printf '%s\n' "$MIN_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$MIN_CLI_VERSION" ]; then
    warnings+=("The Supaflow CLI v${cli_version} is outdated. This plugin requires v${MIN_CLI_VERSION}+. Run: npm install -g @getsupaflow/cli")
  fi

  # 3. Check authentication and workspace
  auth_output=$(supaflow auth status --json 2>/dev/null || echo '{}')
  authenticated=$(echo "$auth_output" | grep -o '"authenticated"[[:space:]]*:[[:space:]]*true' || true)
  if [ -z "$authenticated" ]; then
    warnings+=("The Supaflow CLI is not authenticated. The user needs an API key from https://app.supa-flow.io > Settings > API Keys, then run: supaflow auth login")
  else
    # 3b. Check workspace is selected
    workspace_id=$(echo "$auth_output" | grep -o '"workspace_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
      warnings+=("No workspace selected. Run: supaflow workspaces select <name>")
    fi
  fi
fi

# Build context: always start with operating rules, append any setup warnings
context="$OPERATING_RULES"
if [ ${#warnings[@]} -gt 0 ]; then
  for w in "${warnings[@]}"; do
    context="${context}
[SETUP] ${w}"
  done
fi

# Escape context string for JSON using python3 (reliable across bash versions)
escaped=$(printf '%s' "$context" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read())[1:-1])")

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped"

exit 0
