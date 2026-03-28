#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

COMMANDS="$SCRIPT_DIR/../../commands"

echo "=== Command guardrail tests ==="
echo ""

# --- create-pipeline.md ---
echo "-- create-pipeline.md --"
F="$COMMANDS/create-pipeline.md"
assert_file_contains "$F" "pipelines init" "create-pipeline: contains 'pipelines init'"
assert_file_contains "$F" "pipelines list" "create-pipeline: contains 'pipelines list'"
assert_file_contains "$F" "warehouse_datasource_id" "create-pipeline: contains 'warehouse_datasource_id'"
assert_file_contains "$F" "NEVER silently rename" "create-pipeline: contains 'NEVER silently rename'"
assert_file_contains "$F" "explicit confirmation" "create-pipeline: contains explicit confirmation language"
assert_file_contains "$F" "o\['object'\]" "create-pipeline: uses o['object'] for schema list field"
assert_file_contains "$F" "\-\-name" "create-pipeline: create uses --name flag"
assert_file_contains "$F" "\-\-source" "create-pipeline: create uses --source flag"
assert_file_contains "$F" "\-\-project" "create-pipeline: create uses --project flag"
assert_file_contains "$F" "\-\-objects" "create-pipeline: create uses --objects flag"
assert_file_contains "$F" "d.get('pipeline_prefix'" "create-pipeline: reads pipeline_prefix from top level"
assert_file_contains "$F" "fully_qualified_name.*selected.*fields" "create-pipeline: objects file uses {fully_qualified_name, selected, fields} shape"
assert_file_contains "$F" "Object Scope" "create-pipeline: contains Object Scope section"
assert_file_contains "$F" "all discovered objects.*choose a subset\|all objects.*subset" "create-pipeline: asks all-vs-subset question"
assert_file_contains "$F" "Which objects do you want to include" "create-pipeline: subset asks INCLUDE not exclude"
assert_file_contains "$F" "does NOT mean exclude" "create-pipeline: warns against include/exclude misinterpretation"
assert_file_contains "$F" "Typo check on custom prefix" "create-pipeline: flags typos in permanent prefix"
echo ""

# --- create-datasource.md ---
echo "-- create-datasource.md --"
F="$COMMANDS/create-datasource.md"
assert_file_contains "$F" "datasources list" "create-datasource: contains 'datasources list'"
assert_file_contains "$F" "sensitive" "create-datasource: contains language about sensitive fields"
assert_file_contains "$F" "NEVER ask for passwords" "create-datasource: contains language about not asking for passwords in chat"
assert_file_contains "$F" "supaflow docs" "create-datasource: fetches connector docs"
assert_file_contains "$F" "prerequisites" "create-datasource: validates prerequisites"
assert_file_contains "$F" "confirmed complete\|explicitly deferred" "create-datasource: gates on prerequisite confirmation"
echo ""

# --- check-job.md ---
echo "-- check-job.md --"
F="$COMMANDS/check-job.md"
assert_file_contains "$F" "jobs list --filter" "check-job: contains 'jobs list --filter' for pipeline name resolution"
assert_file_contains "$F" "job_status" "check-job: contains 'job_status' field name"
assert_file_contains "$F" "status_message" "check-job: contains 'status_message' field name"
assert_file_contains "$F" "job_response" "check-job: contains 'job_response' field name"
assert_file_contains "$F" "NEVER reference" "check-job: contains forbidden field language"
echo ""

# --- explain-job-failure.md ---
echo "-- explain-job-failure.md --"
F="$COMMANDS/explain-job-failure.md"
assert_file_contains "$F" "jobs get" "explain-job-failure: contains 'jobs get'"
assert_file_contains "$F" "jobs logs" "explain-job-failure: contains 'jobs logs'"
assert_file_contains "$F" "blindly retry" "explain-job-failure: contains language about not blindly retrying"
echo ""

# --- edit-pipeline.md ---
echo "-- edit-pipeline.md --"
F="$COMMANDS/edit-pipeline.md"
assert_file_contains "$F" "o\['object'\]" "edit-pipeline: uses o['object'] for schema list field"
echo ""

# --- delete-pipeline.md ---
echo "-- delete-pipeline.md --"
F="$COMMANDS/delete-pipeline.md"
assert_file_contains "$F" "explicit confirmation" "delete-pipeline: contains explicit confirmation language"
echo ""

# --- create-schedule.md ---
echo ""
echo "-- create-schedule.md --"
F="$COMMANDS/create-schedule.md"
assert_file_contains "$F" "schedules list" "create-schedule: checks for existing schedules"
assert_file_contains "$F" "schedules create" "create-schedule: contains schedules create"
assert_file_contains "$F" "confirm\|Confirm\|Create this schedule" "create-schedule: contains confirmation language"
assert_file_contains "$F" "\-\-pipeline" "create-schedule: uses --pipeline flag"
assert_file_contains "$F" "\-\-cron" "create-schedule: uses --cron flag"
assert_file_contains "$F" "cron_schedule" "create-schedule: uses cron_schedule for list/verify (not cron)"
assert_file_contains "$F" "d\['cron'\]" "create-schedule: create response uses d['cron'] (not cron_schedule)"

# --- sync-pipeline.md ---
echo ""
echo "-- sync-pipeline.md --"
F="$COMMANDS/sync-pipeline.md"
assert_file_contains "$F" "pipelines sync" "sync-pipeline: contains pipelines sync"
assert_file_contains "$F" "job_id" "sync-pipeline: captures job_id from response"
assert_file_contains "$F" "jobs status" "sync-pipeline: polls with jobs status"
assert_file_contains "$F" "job_status" "sync-pipeline: uses job_status variable (not status)"
assert_file_contains "$F" "explain-job-failure" "sync-pipeline: references /explain-job-failure on failure"
assert_file_contains "$F" "full-resync" "sync-pipeline: documents full resync option"
assert_file_contains "$F" "MUST run.*jobs get" "sync-pipeline: jobs get is mandatory after polling"
assert_file_contains "$F" "only for polling" "sync-pipeline: jobs status is only for polling"
assert_file_contains "$F" "total_rows_source" "sync-pipeline: final summary includes total_rows_source"
assert_file_contains "$F" "total_rows_destination" "sync-pipeline: final summary includes total_rows_destination"
assert_file_contains "$F" "object_details" "sync-pipeline: final summary uses object_details"

print_summary
