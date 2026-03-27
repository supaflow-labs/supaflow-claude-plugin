#!/bin/bash
set -euo pipefail

# SessionStart hook: verify @getsupaflow/cli is installed, meets minimum
# version, is authenticated, and has a workspace selected.
# Outputs setup guidance to stdout (shown in transcript) so Claude can
# proactively help the user fix any issues.

MIN_CLI_VERSION="0.1.7"

messages=()

# 1. Check Node.js
if ! command -v node &>/dev/null; then
  messages+=("- Node.js is not installed. Install Node.js 18+ first (brew install node on macOS, or see https://nodejs.org).")
else
  node_major=$(node --version 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
  if [ "${node_major:-0}" -lt 18 ]; then
    messages+=("- Node.js $(node --version) is too old. Upgrade to v18 or later.")
  fi
fi

# 2. Check supaflow CLI is installed
if ! command -v supaflow &>/dev/null; then
  messages+=("- The Supaflow CLI is not installed. Run: npm install -g @getsupaflow/cli")
else
  # 2b. Check minimum version
  cli_version=$(supaflow --version 2>/dev/null || echo "0.0.0")
  # Compare versions: strip leading v, compare with sort -V
  if [ "$(printf '%s\n' "$MIN_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$MIN_CLI_VERSION" ]; then
    messages+=("- The Supaflow CLI v${cli_version} is outdated. This plugin requires v${MIN_CLI_VERSION}+. Run: npm install -g @getsupaflow/cli")
  fi

  # 3. Check authentication and workspace
  auth_output=$(supaflow auth status --json 2>/dev/null || echo '{}')
  authenticated=$(echo "$auth_output" | grep -o '"authenticated"[[:space:]]*:[[:space:]]*true' || true)
  if [ -z "$authenticated" ]; then
    messages+=("- The Supaflow CLI is not authenticated. The user needs an API key from https://app.supa-flow.io > Settings > API Keys, then run: supaflow auth login")
  else
    # 3b. Check workspace is selected
    workspace_id=$(echo "$auth_output" | grep -o '"workspace_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
      messages+=("- No workspace selected. Run: supaflow workspaces select <name>")
    fi
  fi
fi

# If everything is fine, exit silently
if [ ${#messages[@]} -eq 0 ]; then
  exit 0
fi

# Output to stdout so it appears in the session transcript
combined=$(printf '%s\n' "${messages[@]}")
cat <<EOF
[supaflow-claude-plugin] Setup issues detected:
${combined}

Fix these issues by executing the commands above directly via Bash (do NOT ask the user to run them manually). Then proceed with the user's request. The supaflow-auth skill has detailed setup instructions if needed.
EOF
