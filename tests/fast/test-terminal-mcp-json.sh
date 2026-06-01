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

# The Desktop-specific rejection of plugin .mcp.json must still be present (terminal-only feature).
assert_file_contains "$PLUGIN_ROOT/skills/using-supaflow/setup-preamble.md" \
  "do NOT suggest plugin \`.mcp.json\`" "Desktop rule still present"

print_summary
