#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing /check-job workflow..."

output=$(run_claude "/check-job" 120)

assert_contains "$output" "job.*id\|pipeline.*name\|which.*job\|which.*pipeline" "asks for job ID or pipeline name"
assert_not_contains "$output" "phase:" "does not use invented phase field"
assert_not_contains "$output" "progress:" "does not use invented progress field"

print_summary
