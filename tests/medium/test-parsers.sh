#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

FIXTURES="$SCRIPT_DIR/fixtures"

echo "=== Parser fixture tests ==="
echo ""

# --- jobs-status.json ---
echo "-- jobs-status --"
F="$FIXTURES/jobs-status.json"
assert_json_has_field "$F" "data['id']" "jobs-status: has id"
assert_json_has_field "$F" "data['job_status']" "jobs-status: has job_status"
assert_json_has_field "$F" "data['status_message']" "jobs-status: has status_message"
assert_json_has_field "$F" "data['job_response']" "jobs-status: has job_response"
assert_json_missing_field "$F" "data.get('phase')" "jobs-status: missing phase"
assert_json_missing_field "$F" "data.get('duration')" "jobs-status: missing duration"
assert_json_missing_field "$F" "data.get('completed_at')" "jobs-status: missing completed_at"
assert_json_missing_field "$F" "data.get('progress')" "jobs-status: missing progress"
echo ""

# --- jobs-get.json ---
echo "-- jobs-get --"
F="$FIXTURES/jobs-get.json"
assert_json_has_field "$F" "data['execution_duration_ms']" "jobs-get: has execution_duration_ms"
assert_json_has_field "$F" "data['ended_at']" "jobs-get: has ended_at"
assert_json_has_field "$F" "data['job_response']" "jobs-get: has job_response"
assert_json_has_field "$F" "data['object_details']" "jobs-get: has object_details"
assert_json_has_field "$F" "data['object_details'][0]['fully_qualified_source_object_name']" "jobs-get: has object_details[0].fully_qualified_source_object_name"
assert_json_has_field "$F" "data['object_details'][0]['ingestion_metrics']" "jobs-get: has object_details[0].ingestion_metrics"
assert_json_missing_field "$F" "data.get('duration')" "jobs-get: missing duration"
assert_json_missing_field "$F" "data.get('completed_at')" "jobs-get: missing completed_at"
assert_json_missing_field "$F" "data.get('objects')" "jobs-get: missing objects"
assert_json_missing_field "$F" "data.get('rows_read')" "jobs-get: missing rows_read"
echo ""

# --- pipelines-list.json ---
echo "-- pipelines-list --"
F="$FIXTURES/pipelines-list.json"
assert_json_has_field "$F" "data['data'][0]['source']['name']" "pipelines-list: has data[0].source.name"
assert_json_has_field "$F" "data['data'][0]['source']['datasource_id']" "pipelines-list: has data[0].source.datasource_id"
assert_json_has_field "$F" "data['data'][0]['source']['connector_name']" "pipelines-list: has data[0].source.connector_name"
assert_json_has_field "$F" "data['data'][0]['destination']['name']" "pipelines-list: has data[0].destination.name"
assert_json_has_field "$F" "data['data'][0]['destination']['datasource_id']" "pipelines-list: has data[0].destination.datasource_id"
assert_json_has_field "$F" "data['data'][0]['project']['id']" "pipelines-list: has data[0].project.id"
assert_json_has_field "$F" "data['data'][0]['project']['name']" "pipelines-list: has data[0].project.name"
assert_json_missing_field "$F" "data['data'][0].get('source_name')" "pipelines-list: missing flat source_name"
assert_json_missing_field "$F" "data['data'][0].get('destination_name')" "pipelines-list: missing flat destination_name"
echo ""

# --- pipelines-schema-list.json ---
echo "-- pipelines-schema-list --"
F="$FIXTURES/pipelines-schema-list.json"
assert_json_has_field "$F" "data['data'][0]['object']" "pipelines-schema-list: has data[0].object"
assert_json_has_field "$F" "data['data'][0]['selected']" "pipelines-schema-list: has data[0].selected"
assert_json_has_field "$F" "data['data'][0]['total_fields']" "pipelines-schema-list: has data[0].total_fields"
assert_json_has_field "$F" "data['data'][0]['selected_fields']" "pipelines-schema-list: has data[0].selected_fields"
assert_json_missing_field "$F" "data['data'][0].get('fully_qualified_name')" "pipelines-schema-list: missing data[0].fully_qualified_name"
assert_json_missing_field "$F" "data['data'][0].get('name')" "pipelines-schema-list: missing data[0].name"
echo ""

# --- projects-list.json ---
echo "-- projects-list --"
F="$FIXTURES/projects-list.json"
assert_json_has_field "$F" "data['data'][0]['warehouse_datasource_id']" "projects-list: has data[0].warehouse_datasource_id"
assert_json_has_field "$F" "data['data'][0]['warehouse_name']" "projects-list: has data[0].warehouse_name"
assert_json_has_field "$F" "data['data'][0]['warehouse_connector_name']" "projects-list: has data[0].warehouse_connector_name"
assert_json_has_field "$F" "data['data'][0]['pipeline_count']" "projects-list: has data[0].pipeline_count"
echo ""

# --- datasources-get.json ---
echo "-- datasources-get --"
F="$FIXTURES/datasources-get.json"
assert_json_has_field "$F" "data['configs']" "datasources-get: has configs"
assert_json_has_field "$F" "data['configs']['host']" "datasources-get: has configs.host"
assert_json_has_field "$F" "data['configs']['password']" "datasources-get: has configs.password"
echo ""

# --- datasources-catalog.json ---
echo "-- datasources-catalog --"
F="$FIXTURES/datasources-catalog.json"
assert_json_has_field "$F" "data['data'][0]['fully_qualified_name']" "datasources-catalog: has data[0].fully_qualified_name"
assert_json_missing_field "$F" "data['data'][0].get('schema')" "datasources-catalog: missing data[0].schema"
assert_json_missing_field "$F" "data['data'][0].get('name')" "datasources-catalog: missing data[0].name"
echo ""

print_summary
