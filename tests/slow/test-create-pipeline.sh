#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing /create-pipeline workflow..."
# Requires: Claude Code CLI, API key, Supaflow auth

output=$(run_claude "/create-pipeline" 300)

assert_contains "$output" "datasources list\|existing datasource" "lists datasources first"
assert_contains "$output" "pipelines init\|initializ" "runs pipelines init"
assert_contains "$output" "confirm\|proceed\|approve" "asks for confirmation"
assert_not_contains "$output" "auto-generated prefix" "does not say auto-generated prefix without value"

print_summary
