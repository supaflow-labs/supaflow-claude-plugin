#!/usr/bin/env bash
set -euo pipefail

# Shared test utilities for supaflow-claude-plugin tests

# Counter variables
TESTS_PASSED=0
TESTS_FAILED=0

# Plugin root derived from script location (parent of tests/)
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# assert_contains "output" "pattern" "test name"
assert_contains() {
  local output="$1"
  local pattern="$2"
  local test_name="$3"
  if echo "$output" | grep -q "$pattern"; then
    echo "PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL: $test_name (expected to find: $pattern)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
export -f assert_contains

# assert_not_contains "output" "pattern" "test name"
assert_not_contains() {
  local output="$1"
  local pattern="$2"
  local test_name="$3"
  if ! echo "$output" | grep -q "$pattern"; then
    echo "PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL: $test_name (expected NOT to find: $pattern)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
export -f assert_not_contains

# assert_json_has_field "file" "python_expr" "test name"
assert_json_has_field() {
  local file="$1"
  local python_expr="$2"
  local test_name="$3"
  if python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
_ = $python_expr
sys.exit(0)
" 2>/dev/null; then
    echo "PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL: $test_name (python expr returned falsy or error: $python_expr)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
export -f assert_json_has_field

# assert_json_missing_field "file" "python_expr" "test name"
assert_json_missing_field() {
  local file="$1"
  local python_expr="$2"
  local test_name="$3"
  if python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
result = $python_expr
if result is None or result == False:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    echo "PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL: $test_name (python expr returned truthy but expected missing: $python_expr)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
export -f assert_json_missing_field

# assert_file_contains "filepath" "pattern" "test name"
assert_file_contains() {
  local filepath="$1"
  local pattern="$2"
  local test_name="$3"
  if grep -q "$pattern" "$filepath" 2>/dev/null; then
    echo "PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL: $test_name (expected to find in file $filepath: $pattern)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
export -f assert_file_contains

# assert_file_not_contains "filepath" "pattern" "test name"
assert_file_not_contains() {
  local filepath="$1"
  local pattern="$2"
  local test_name="$3"
  if ! grep -q "$pattern" "$filepath" 2>/dev/null; then
    echo "PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL: $test_name (expected NOT to find in file $filepath: $pattern)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
export -f assert_file_not_contains

# create_mock_cli - creates temp dir with mock node and supaflow scripts
# Returns the mock dir path via echo
create_mock_cli() {
  local mock_dir
  mock_dir="$(mktemp -d)"

  local node_version="${MOCK_NODE_VERSION:-v20.0.0}"
  local cli_version="${MOCK_CLI_VERSION:-0.1.10}"
  local auth_status="${MOCK_AUTH_STATUS:-authenticated+workspace}"

  # Mock node script
  cat > "$mock_dir/node" <<'NODE_EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "${MOCK_NODE_VERSION:-v20.0.0}"
fi
exit 0
NODE_EOF
  chmod +x "$mock_dir/node"

  # Mock supaflow script
  # Supports MOCK_CLI_VERSION for --version and MOCK_AUTH_STATUS for raw JSON passthrough
  cat > "$mock_dir/supaflow" <<'SUPAFLOW_EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "${MOCK_CLI_VERSION:-0.1.10}"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" && "${3:-}" == "--json" ]]; then
  echo "${MOCK_AUTH_STATUS:-{\"authenticated\":true,\"workspace_id\":\"ws-test-123\",\"workspace_name\":\"Test Workspace\"}}"
  exit 0
fi
exit 0
SUPAFLOW_EOF
  chmod +x "$mock_dir/supaflow"

  echo "$mock_dir"
}
export -f create_mock_cli

# setup_path_with_mocks "dir" - saves ORIGINAL_PATH, prepends mock dir
setup_path_with_mocks() {
  local mock_dir="$1"
  ORIGINAL_PATH="$PATH"
  export PATH="$mock_dir:$PATH"
}
export -f setup_path_with_mocks

# cleanup_mocks "dir" - restores PATH, removes mock dir
cleanup_mocks() {
  local mock_dir="$1"
  if [[ -n "${ORIGINAL_PATH:-}" ]]; then
    export PATH="$ORIGINAL_PATH"
    unset ORIGINAL_PATH
  fi
  rm -rf "$mock_dir"
}
export -f cleanup_mocks

# run_claude "prompt" [timeout] - runs claude -p "prompt" with timeout, captures output
run_claude() {
  local prompt="$1"
  local timeout_secs="${2:-30}"
  local timeout_cmd=""
  if command -v gtimeout &>/dev/null; then
    timeout_cmd=gtimeout
  elif command -v timeout &>/dev/null; then
    timeout_cmd=timeout
  fi
  if [ -n "$timeout_cmd" ]; then
    $timeout_cmd "$timeout_secs" claude -p "$prompt" 2>&1 || true
  else
    claude -p "$prompt" 2>&1 || true
  fi
}
export -f run_claude

# get_frontmatter_field "file.md" "field" - extracts YAML frontmatter field value
get_frontmatter_field() {
  local file="$1"
  local field="$2"
  # Extract content between first --- markers
  awk '/^---$/{if(NR==1){found=1;next}if(found){exit}} found{print}' "$file" \
    | grep "^${field}:" \
    | sed "s/^${field}:[[:space:]]*//"
}
export -f get_frontmatter_field

# has_frontmatter "file.md" - checks if file starts with ---
has_frontmatter() {
  local file="$1"
  local first_line
  first_line="$(head -n 1 "$file" 2>/dev/null || true)"
  [[ "$first_line" == "---" ]]
}
export -f has_frontmatter

# print_summary - prints results line, returns 1 if any failures
print_summary() {
  local total=$((TESTS_PASSED + TESTS_FAILED))
  echo ""
  echo "Results: $TESTS_PASSED/$total passed, $TESTS_FAILED failed"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    return 1
  fi
  return 0
}
export -f print_summary
