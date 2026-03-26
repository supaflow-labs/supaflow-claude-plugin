#!/bin/bash
set -euo pipefail

# SessionStart hook: verify @getsupaflow/cli is installed and authenticated.
# Outputs setup guidance to stdout (shown in transcript) so Claude can
# proactively help the user fix any issues.

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

# 2. Check supaflow CLI
if ! command -v supaflow &>/dev/null; then
  messages+=("- The Supaflow CLI is not installed. Run: npm install -g @getsupaflow/cli")
else
  # 3. Check authentication
  auth_output=$(supaflow auth status --json 2>/dev/null || echo '{}')
  authenticated=$(echo "$auth_output" | grep -o '"authenticated"[[:space:]]*:[[:space:]]*true' || true)
  if [ -z "$authenticated" ]; then
    messages+=("- The Supaflow CLI is not authenticated. The user needs an API key from https://app.supa-flow.io > Settings > API Keys, then run: supaflow auth login")
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

Guide the user through fixing these before running any supaflow commands. The supaflow-auth skill has detailed setup instructions.
EOF
