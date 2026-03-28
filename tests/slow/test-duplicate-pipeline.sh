#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing /create-pipeline duplicate handling..."

output=$(run_claude "/create-pipeline" 300)

assert_contains "$output" "pipelines list\|existing pipeline\|already" "checks for existing pipelines"

print_summary
