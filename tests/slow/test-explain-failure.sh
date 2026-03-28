#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing /explain-job-failure workflow..."

output=$(run_claude "/explain-job-failure" 120)

assert_contains "$output" "job.*id\|which.*job\|provide.*id" "asks for job ID"

print_summary
