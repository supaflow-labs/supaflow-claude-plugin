#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../test-helpers.sh"   # sets $PLUGIN_ROOT, exports helpers

echo "Testing terminal-path plugin .mcp.json..."

MCP_JSON="$PLUGIN_ROOT/.mcp.json"

# Server is declared under the documented "mcpServers" key and launches `supaflow mcp`.
# assert_json_has_field fails on an exception; `or sys.exit(1)` turns a false comparison
# into the non-zero exit the helper reports as FAIL.
assert_json_has_field "$MCP_JSON" "data['mcpServers']['supaflow']['command'] == 'supaflow' or sys.exit(1)" \
  "mcp.json: supaflow server command is 'supaflow'"
assert_json_has_field "$MCP_JSON" "data['mcpServers']['supaflow']['args'] == ['mcp'] or sys.exit(1)" \
  "mcp.json: supaflow server args are ['mcp']"

# Local stdio belongs to Code, not the hosted marketplace edition.
assert_file_contains "$PLUGIN_ROOT/skills/using-supaflow/setup-preamble.md" \
  "not the installation path for Desktop chat" "local stdio is restricted to Code"
assert_file_contains "$MCP_PLUGIN_ROOT/.mcp.json" \
  'https://app.supa-flow.io/mcp' "hosted package points at production MCP"

print_summary
