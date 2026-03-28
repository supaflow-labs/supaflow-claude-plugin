#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

FIXTURES="$SCRIPT_DIR/../medium/fixtures"

echo "Testing live CLI output shapes against fixtures..."
echo "(Requires: supaflow CLI authenticated with workspace)"
echo ""

# Skip if CLI not available or not authenticated
if ! command -v supaflow &>/dev/null; then
    echo "SKIP: supaflow CLI not found"
    exit 0
fi

auth_check=$(supaflow auth status --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('ok') if d.get('authenticated') and d.get('workspace_id') else print('fail')
" 2>/dev/null || echo "fail")

if [ "$auth_check" != "ok" ]; then
    echo "SKIP: supaflow CLI not authenticated or no workspace"
    exit 0
fi

# Helper to compare top-level keys
assert_keys_match() {
    local cmd="$1"
    local fixture="$2"
    local test_name="$3"
    local is_list="${4:-false}"

    local live_output
    live_output=$(eval "$cmd" 2>/dev/null || echo '{}')

    local result
    result=$(python3 -c "
import json, sys
with open('$fixture') as f:
    fixture_data = json.load(f)
live = json.loads(sys.argv[1])
if $is_list:
    if not live.get('data'):
        print('skip_empty')
        sys.exit(0)
    fixture_keys = set(fixture_data['data'][0].keys())
    live_keys = set(live['data'][0].keys())
else:
    fixture_keys = set(fixture_data.keys())
    live_keys = set(live.keys())
missing = fixture_keys - live_keys
if missing:
    print(f'missing: {missing}')
else:
    print('match')
" "$live_output" 2>/dev/null || echo "error")

    if [ "$result" = "match" ]; then
        echo "  [PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [ "$result" = "skip_empty" ]; then
        echo "  [SKIP] $test_name (no data returned)"
    else
        echo "  [FAIL] $test_name ($result)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_keys_match "supaflow datasources list --json" "$FIXTURES/datasources-list.json" "datasources list shape" "True"
assert_keys_match "supaflow projects list --json" "$FIXTURES/projects-list.json" "projects list shape" "True"
assert_keys_match "supaflow pipelines list --json" "$FIXTURES/pipelines-list.json" "pipelines list shape" "True"

print_summary
