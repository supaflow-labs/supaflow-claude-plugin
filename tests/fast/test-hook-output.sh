#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing hook output..."

# Run hook with a fully controlled PATH.
# Only mock_dir + /usr/bin + /bin are on PATH, plus python3 is symlinked into mock_dir.
# This ensures removing a mock truly simulates a missing command.
run_hook_with_mocks() {
    local mock_dir="$1"
    # Symlink python3 into mock dir so the hook's escape function works
    local python3_path
    python3_path="$(command -v python3)"
    ln -sf "$python3_path" "$mock_dir/python3"
    # Also need printf, sed, sort, head, grep, bash from system
    ORIGINAL_PATH="$PATH"
    export PATH="$mock_dir:/usr/bin:/bin"
    local output
    output=$(bash "$PLUGIN_ROOT/hooks/check-setup.sh" 2>/dev/null || true)
    export PATH="$ORIGINAL_PATH"
    rm -rf "$mock_dir"
    echo "$output"
}

# Scenario 1: Healthy env - valid JSON shape, correct hookEventName, has Operating Rules, no [SETUP]
mock_dir=$(create_mock_cli)
output=$(run_hook_with_mocks "$mock_dir")

json_shape=$(echo "$output" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    h = d['hookSpecificOutput']
    assert h['hookEventName'] == 'SessionStart'
    assert isinstance(h['additionalContext'], str)
    print('valid_shape')
except Exception as e:
    print('invalid: ' + str(e))
" 2>/dev/null || echo "parse_error")
assert_contains "$json_shape" "^valid_shape$" "healthy env: output is valid JSON with correct hookSpecificOutput shape"

hook_event=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['hookSpecificOutput']['hookEventName'])" 2>/dev/null || echo "")
assert_contains "$hook_event" "SessionStart" "healthy env: hookEventName is SessionStart"

additional_ctx=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['hookSpecificOutput']['additionalContext'])" 2>/dev/null || echo "")
assert_contains "$additional_ctx" "Operating Rules" "healthy env: additionalContext contains Operating Rules"

assert_not_contains "$output" "\[SETUP\]" "healthy env: no [SETUP] warnings"

# Scenario 2: Missing CLI - supaflow not on PATH
mock_dir=$(create_mock_cli)
rm -f "$mock_dir/supaflow"
output=$(run_hook_with_mocks "$mock_dir")
assert_contains "$output" "\[SETUP\]" "missing CLI: output contains [SETUP]"
assert_contains "$output" "not installed" "missing CLI: output contains 'not installed'"

# Scenario 3: Old CLI version
mock_dir=$(create_mock_cli)
export MOCK_CLI_VERSION="0.0.1"
output=$(run_hook_with_mocks "$mock_dir")
unset MOCK_CLI_VERSION
assert_contains "$output" "outdated" "old CLI version: output contains 'outdated'"

# Scenario 4: Unauthenticated
mock_dir=$(create_mock_cli)
export MOCK_AUTH_STATUS='{"authenticated":false}'
output=$(run_hook_with_mocks "$mock_dir")
unset MOCK_AUTH_STATUS
assert_contains "$output" "not authenticated" "unauthenticated: output contains 'not authenticated'"

# Scenario 5: No workspace selected
mock_dir=$(create_mock_cli)
export MOCK_AUTH_STATUS='{"authenticated":true,"workspace_id":null}'
output=$(run_hook_with_mocks "$mock_dir")
unset MOCK_AUTH_STATUS
assert_contains "$output" "No workspace" "no workspace: output contains 'No workspace'"

# Scenario 6: Missing Node.js
mock_dir=$(create_mock_cli)
rm -f "$mock_dir/node"
output=$(run_hook_with_mocks "$mock_dir")
assert_contains "$output" "Node.js" "missing node: output contains 'Node.js'"

print_summary
