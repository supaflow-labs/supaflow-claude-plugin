#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS ships without `timeout`; prefer gtimeout from coreutils if available
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD=gtimeout
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD=timeout
else
  TIMEOUT_CMD=""
fi

# Default settings
RUN_FAST=true
RUN_MEDIUM=false
RUN_SLOW=false
RUN_LIVE=false
VERBOSE=false
SPECIFIC_TEST=""
TEST_TIMEOUT=60

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --medium        Run fast + medium test suites
  --slow          Run fast + medium + slow test suites
  --live          Run fast + medium + live test suites
  --all           Run all test suites (fast + medium + slow + live)
  --verbose       Show verbose output
  --test FILE     Run a specific test file
  --timeout SECS  Timeout per test file (default: 60)
  --help          Show this help message

Default: runs only the fast/ test suite
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --medium)
      RUN_MEDIUM=true
      shift
      ;;
    --slow)
      RUN_MEDIUM=true
      RUN_SLOW=true
      shift
      ;;
    --live)
      RUN_MEDIUM=true
      RUN_LIVE=true
      shift
      ;;
    --all)
      RUN_MEDIUM=true
      RUN_SLOW=true
      RUN_LIVE=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --test)
      SPECIFIC_TEST="$2"
      shift 2
      ;;
    --timeout)
      TEST_TIMEOUT="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_TESTS=()

run_test_file() {
  local test_file="$1"
  local suite_name="$2"
  local test_basename
  test_basename="$(basename "$test_file")"

  echo "[${suite_name}] ${test_basename}"

  local output
  local exit_code=0

  if [ -n "$TIMEOUT_CMD" ]; then
    output=$($TIMEOUT_CMD "$TEST_TIMEOUT" bash "$test_file" 2>&1) && exit_code=0 || exit_code=$?
  elif output=$(bash "$test_file" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    echo "$output"
  fi

  # Parse pass/fail counts from output
  local passed=0
  local failed=0
  if echo "$output" | grep -q "^Results:"; then
    local results_line
    results_line="$(echo "$output" | grep "^Results:" | tail -n 1)"
    passed="$(echo "$results_line" | grep -oE '[0-9]+/[0-9]+ passed' | grep -oE '^[0-9]+')" || passed=0
    failed="$(echo "$results_line" | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+')" || failed=0
  fi

  if [[ $exit_code -ne 0 ]] || [[ "$failed" -gt 0 ]]; then
    echo "  FAILED (exit=$exit_code, failed=$failed)"
    if [[ "$VERBOSE" != "true" ]]; then
      echo "$output" | grep -E "^(FAIL|PASS|Results):" || true
    fi
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    FAILED_TESTS+=("[${suite_name}] ${test_basename}")
  else
    echo "  passed ($passed assertions)"
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  fi
}

collect_and_run_suite() {
  local suite="$1"
  local suite_dir="$TESTS_DIR/$suite"

  if [[ ! -d "$suite_dir" ]]; then
    return
  fi

  local test_files=()
  while IFS= read -r -d '' f; do
    test_files+=("$f")
  done < <(find "$suite_dir" -maxdepth 1 -name "test-*.sh" -print0 2>/dev/null | sort -z)

  for test_file in "${test_files[@]+"${test_files[@]}"}"; do
    run_test_file "$test_file" "$suite"
  done
}

echo "=== Supaflow Claude Plugin Tests ==="
echo ""

if [[ -n "$SPECIFIC_TEST" ]]; then
  # Run a single specific test file
  if [[ ! -f "$SPECIFIC_TEST" ]]; then
    echo "Error: test file not found: $SPECIFIC_TEST"
    exit 1
  fi
  suite_name="$(basename "$(dirname "$SPECIFIC_TEST")")"
  run_test_file "$SPECIFIC_TEST" "$suite_name"
else
  # Run suites based on flags
  collect_and_run_suite "fast"

  if [[ "$RUN_MEDIUM" == "true" ]]; then
    collect_and_run_suite "medium"
  fi

  if [[ "$RUN_SLOW" == "true" ]]; then
    collect_and_run_suite "slow"
  fi

  if [[ "$RUN_LIVE" == "true" ]]; then
    collect_and_run_suite "live"
  fi
fi

echo ""
echo "=== Summary ==="
echo "Test files: $((TOTAL_PASSED + TOTAL_FAILED)) total, $TOTAL_PASSED passed, $TOTAL_FAILED failed"

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
fi

if [[ $TOTAL_FAILED -gt 0 ]]; then
  exit 1
fi

exit 0
