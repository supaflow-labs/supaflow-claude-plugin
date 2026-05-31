#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

echo "Testing MCP tool contract..."

facts=$(cd "$PLUGIN_ROOT" && node --input-type=module <<'NODE'
import {
  TOOLS,
  applyConfigPatch,
  applyObjectSelection,
  buildPipelineCreateFromPlanArgv,
  buildSupaflowArgv,
  listToolDefinitions,
  normalizeObjectPreviewLimit,
} from "./servers/supaflow-mcp/server.mjs";

const names = TOOLS.map((t) => t.name);
const defs = listToolDefinitions();
const byName = new Map(TOOLS.map((t) => [t.name, t]));
const defByName = new Map(defs.map((t) => [t.name, t]));

const emit = (key, value) => console.log(`${key}=${value}`);
const argv = (name, args) => buildSupaflowArgv(name, args).join("\u001f");

emit("tool_count", TOOLS.length);
emit("tool_names_unique", new Set(names).size === names.length);
emit("has_pipelines_prepare_create", names.includes("pipelines_prepare_create"));
emit("has_pipelines_create_from_plan", names.includes("pipelines_create_from_plan"));
emit("has_auth_login", names.includes("auth_login"));
emit("has_auth_logout", names.includes("auth_logout"));
emit("has_encrypt", names.includes("encrypt"));
emit("all_schemas_closed", defs.every((t) => t.inputSchema && t.inputSchema.additionalProperties === false));

emit("auth_status_readonly", defByName.get("auth_status").annotations.readOnlyHint);
emit("pipelines_prepare_create_readonly", defByName.get("pipelines_prepare_create").annotations.readOnlyHint);
emit("pipelines_create_from_plan_readonly", defByName.get("pipelines_create_from_plan").annotations.readOnlyHint);
emit("pipelines_prepare_create_has_output_schema", !!defByName.get("pipelines_prepare_create").outputSchema);
emit("pipelines_create_from_plan_has_output_schema", !!defByName.get("pipelines_create_from_plan").outputSchema);
emit("pipelines_prepare_create_preview_default",
  defByName.get("pipelines_prepare_create").inputSchema.properties.object_preview_limit.default);
emit("object_preview_limit_clamps",
  normalizeObjectPreviewLimit(undefined) === 1000 &&
  normalizeObjectPreviewLimit(618) === 618 &&
  normalizeObjectPreviewLimit(5000) === 1000 &&
  normalizeObjectPreviewLimit(0) === 1);
emit("datasources_get_readonly", defByName.get("datasources_get").annotations.readOnlyHint);
emit("datasources_catalog_readonly", defByName.get("datasources_catalog").annotations.readOnlyHint);
emit("docs_readonly", defByName.get("docs").annotations.readOnlyHint);
emit("pipelines_create_readonly", defByName.get("pipelines_create").annotations.readOnlyHint);
emit("pipelines_delete_destructive", defByName.get("pipelines_delete").annotations.destructiveHint);
emit("datasources_delete_destructive", defByName.get("datasources_delete").annotations.destructiveHint);
emit("schedules_delete_destructive", defByName.get("schedules_delete").annotations.destructiveHint);

emit("datasources_get_argv", argv("datasources_get", { identifier: "pg", output_file: "/tmp/pg.env" }));
emit("datasources_catalog_argv", argv("datasources_catalog", {
  identifier: "pg",
  output_file: "/tmp/objects.json",
  refresh: true,
  with_fields: true,
}));
emit("docs_argv", argv("docs", { topic: "postgres", output_file: "/tmp/postgres-docs.md", refresh: true }));
emit("pipelines_delete_argv", argv("pipelines_delete", { identifier: "orders" }));
emit("pipelines_sync_reset_argv", argv("pipelines_sync", {
  identifier: "orders",
  full_resync: true,
  reset_target: true,
}));
emit("guided_create_argv", buildPipelineCreateFromPlanArgv({
  name: "Orders",
  description: "Test create",
  source: "sql_server",
  project: "postgres_project",
  configFile: "/tmp/config.json",
  objectsFile: "/tmp/objects.json",
}).join("\u001f"));

emit("delete_wording_requires_skill_confirmation",
  /skill must get explicit user confirmation before this tool call/i.test(byName.get("pipelines_delete").description));
emit("delete_wording_no_mcp_confirmation_only",
  !/MCP approval prompt is the confirmation/i.test(byName.get("pipelines_delete").description));

const patched = applyConfigPatch({ pipeline_prefix: "postgres", ingestion_mode: "incremental" }, { pipeline_prefix: "analytics" });
emit("config_patch_sets_custom_prefix", patched.pipeline_prefix === "analytics" && patched.is_custom_prefix === true);

const selection = applyObjectSelection(
  [{ fully_qualified_name: "public.accounts" }, { fully_qualified_name: "public.orders" }],
  { mode: "subset", include: ["public.orders"] },
);
emit("object_subset_selection", selection.objects.map((o) => `${o.fully_qualified_name}:${o.selected}`).join(","));
let unknownObjectBlocked = false;
try {
  applyObjectSelection([{ fully_qualified_name: "public.accounts" }], { mode: "subset", include: ["public.missing"] });
} catch {
  unknownObjectBlocked = true;
}
emit("unknown_object_blocked", unknownObjectBlocked);
NODE
)

assert_contains "$facts" "^tool_count=44$" "mcp: exposes 44 tools"
assert_contains "$facts" "^tool_names_unique=true$" "mcp: tool names are unique"
assert_contains "$facts" "^has_pipelines_prepare_create=true$" "mcp: exposes guided prepare-create tool"
assert_contains "$facts" "^has_pipelines_create_from_plan=true$" "mcp: exposes guided create-from-plan tool"
assert_contains "$facts" "^has_auth_login=false$" "mcp: does not expose auth login"
assert_contains "$facts" "^has_auth_logout=false$" "mcp: does not expose auth logout"
assert_contains "$facts" "^has_encrypt=false$" "mcp: does not expose encrypt"
assert_contains "$facts" "^all_schemas_closed=true$" "mcp: all input schemas reject extra properties"

assert_contains "$facts" "^auth_status_readonly=true$" "mcp: auth_status is read-only"
assert_contains "$facts" "^pipelines_prepare_create_readonly=false$" "mcp: guided prepare-create is not read-only because it writes host plan files"
assert_contains "$facts" "^pipelines_create_from_plan_readonly=false$" "mcp: guided create-from-plan is not read-only"
assert_contains "$facts" "^pipelines_prepare_create_has_output_schema=true$" "mcp: guided prepare-create has output schema"
assert_contains "$facts" "^pipelines_create_from_plan_has_output_schema=true$" "mcp: guided create-from-plan has output schema"
assert_contains "$facts" "^pipelines_prepare_create_preview_default=1000$" "mcp: guided prepare-create returns up to 1000 object names by default"
assert_contains "$facts" "^object_preview_limit_clamps=true$" "mcp: object preview limit clamps to 1..1000"
assert_contains "$facts" "^datasources_get_readonly=false$" "mcp: datasources_get is not annotated read-only because it can export env files"
assert_contains "$facts" "^datasources_catalog_readonly=false$" "mcp: datasources_catalog is not annotated read-only because it can refresh/write files"
assert_contains "$facts" "^docs_readonly=false$" "mcp: docs is not annotated read-only because it can refresh/write files"
assert_contains "$facts" "^pipelines_create_readonly=false$" "mcp: pipelines_create is not read-only"
assert_contains "$facts" "^pipelines_delete_destructive=true$" "mcp: pipelines_delete is destructive"
assert_contains "$facts" "^datasources_delete_destructive=true$" "mcp: datasources_delete is destructive"
assert_contains "$facts" "^schedules_delete_destructive=true$" "mcp: schedules_delete is destructive"

assert_contains "$facts" $'^datasources_get_argv=datasources\x1fget\x1fpg\x1f--output\x1f/tmp/pg.env\x1f--json$' \
  "mcp: datasources_get supports --output"
assert_contains "$facts" $'^datasources_catalog_argv=datasources\x1fcatalog\x1fpg\x1f--output\x1f/tmp/objects.json\x1f--refresh\x1f--with-fields\x1f--json$' \
  "mcp: datasources_catalog supports output/refresh/fields"
assert_contains "$facts" $'^docs_argv=docs\x1fpostgres\x1f--output\x1f/tmp/postgres-docs.md\x1f--refresh$' \
  "mcp: docs supports --output and --refresh without --json"
assert_contains "$facts" $'^pipelines_delete_argv=pipelines\x1fdelete\x1forders\x1f--yes\x1f--json$' \
  "mcp: pipelines_delete argv is explicit"
assert_contains "$facts" $'^pipelines_sync_reset_argv=pipelines\x1fsync\x1forders\x1f--full-resync\x1f--reset-target\x1f--json$' \
  "mcp: pipelines_sync reset argv is exact"
assert_contains "$facts" $'^guided_create_argv=pipelines\x1fcreate\x1f--name\x1fOrders\x1f--source\x1fsql_server\x1f--project\x1fpostgres_project\x1f--config\x1f/tmp/config.json\x1f--objects\x1f/tmp/objects.json\x1f--description\x1fTest create\x1f--json$' \
  "mcp: guided create always passes prepared objects file"

assert_contains "$facts" "^delete_wording_requires_skill_confirmation=true$" \
  "mcp: delete description requires skill-side confirmation"
assert_contains "$facts" "^delete_wording_no_mcp_confirmation_only=true$" \
  "mcp: delete description does not delegate confirmation to MCP prompt"
assert_contains "$facts" "^config_patch_sets_custom_prefix=true$" \
  "mcp: config patch marks changed pipeline_prefix as custom"
assert_contains "$facts" "^object_subset_selection=public.accounts:false,public.orders:true$" \
  "mcp: subset object selection keeps only included objects"
assert_contains "$facts" "^unknown_object_blocked=true$" \
  "mcp: subset object selection rejects unknown objects"

print_summary
