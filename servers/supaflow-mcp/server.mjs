#!/usr/bin/env node
// Supaflow stdio MCP server.
//
// Exposes the Supaflow CLI as mcp__supaflow__* tools by shelling out to the
// host `supaflow` binary. Runs ON THE HOST (register in claude_desktop_config.json),
// where the CLI and ~/.supaflow/config.json already live -- so no per-session
// install and no per-session `auth login`. Tools are bridged into Claude
// Desktop's cowork VM the same way Playwright is.
//
// The TOOLS table mirrors `supaflow` 1:1 (verified against the CLI source, since
// `supaflow <group> <sub> --help` is broken in v0.1.13). Every data/action tool
// runs with `--json`; `docs` returns markdown.
//
// Deliberately NOT exposed:
//   - auth login   (its --key would pass your API key through a tool call)
//   - auth logout  (would clear the host auth this server relies on)
//   - encrypt      (local env-file utility, not a workspace operation)
// Auth is taken from SUPAFLOW_API_KEY/SUPAFLOW_WORKSPACE_ID (this server's env)
// or the host ~/.supaflow/config.json.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

// Ensure `supaflow` and its `#!/usr/bin/env node` shebang resolve under a
// minimal/GUI PATH (the caller's PATH still takes precedence).
const CHILD_ENV = {
  ...process.env,
  PATH: ["/opt/homebrew/bin", "/usr/local/bin", process.env.PATH || ""]
    .filter(Boolean)
    .join(":"),
};

// ---- argv builder helpers (keep the table declarative + exact) ----
const S = (v) => String(v);
function opt(argv, flag, val) {
  if (val !== undefined && val !== null && val !== "") argv.push(flag, S(val));
}
function bool(argv, flag, val) {
  if (val === true) argv.push(flag);
}
function multi(argv, flag, vals) {
  if (Array.isArray(vals)) for (const v of vals) argv.push(flag, S(v));
}

const idSchema = (label = "UUID or api_name") => ({
  type: "object",
  properties: { identifier: { type: "string", description: label } },
  required: ["identifier"],
  additionalProperties: false,
});
const jobIdSchema = {
  type: "object",
  properties: { id: { type: "string", description: "Job UUID" } },
  required: ["id"],
  additionalProperties: false,
};

// ---- the tool table: 1:1 with the CLI ----
const TOOLS = [
  // ---------- read-only ----------
  {
    name: "auth_status",
    description: "Show current authentication status and the active workspace.",
    readOnly: true,
    build: () => ["auth", "status"],
  },
  {
    name: "workspaces_list",
    description: "List accessible workspaces.",
    readOnly: true,
    build: () => ["workspaces", "list"],
  },
  {
    name: "connectors_list",
    description: "List available connector types (use the `type` for datasource init).",
    readOnly: true,
    build: () => ["connectors", "list"],
  },
  {
    name: "datasources_list",
    description: "List datasources in the active workspace. Returns { data, total, limit, offset }.",
    readOnly: true,
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "number", description: "Max results (default 25; CLI caps at 200).", default: 25 },
        offset: { type: "number", description: "Pagination offset.", default: 0 },
        filter: { type: "array", items: { type: "string" }, description: "field=value filters (repeatable)." },
      },
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["datasources", "list"];
      opt(v, "--limit", a.limit);
      opt(v, "--offset", a.offset);
      multi(v, "--filter", a.filter);
      return v;
    },
  },
  {
    name: "datasources_get",
    description: "Get datasource details by UUID or api_name.",
    readOnly: true,
    inputSchema: idSchema(),
    build: (a) => ["datasources", "get", a.identifier],
  },
  {
    name: "datasources_catalog",
    description:
      "List discovered objects for a datasource. Can be large -- pass output_file to write objects.json to disk instead of returning it inline.",
    readOnly: true,
    timeoutMs: 180000,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Datasource UUID or api_name" },
        output_file: { type: "string", description: "Write selectable objects JSON to this host path (for pipeline creation)." },
        refresh: { type: "boolean", description: "Trigger a schema refresh before listing." },
        with_fields: { type: "boolean", description: "Include full per-object field-level metadata (large)." },
      },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["datasources", "catalog", a.identifier];
      opt(v, "--output", a.output_file);
      bool(v, "--refresh", a.refresh);
      bool(v, "--with-fields", a.with_fields);
      return v;
    },
  },
  {
    name: "pipelines_list",
    description: "List pipelines in the active workspace. Returns { data, total, limit, offset }.",
    readOnly: true,
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "number", default: 25 },
        offset: { type: "number", default: 0 },
        state: { type: "string", description: "Filter by state (e.g. active, inactive)." },
        sort: { type: "string", description: "name | state | created_at | updated_at | last_sync_at", default: "name" },
        order: { type: "string", enum: ["asc", "desc"], default: "asc" },
      },
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["pipelines", "list"];
      opt(v, "--limit", a.limit);
      opt(v, "--offset", a.offset);
      opt(v, "--state", a.state);
      opt(v, "--sort", a.sort);
      opt(v, "--order", a.order);
      return v;
    },
  },
  {
    name: "pipelines_get",
    description: "Get pipeline details by UUID or api_name.",
    readOnly: true,
    inputSchema: idSchema(),
    build: (a) => ["pipelines", "get", a.identifier],
  },
  {
    name: "pipelines_schema_list",
    description: "List a pipeline's selectable objects (raw array of { fully_qualified_name, selected, fields }).",
    readOnly: true,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Pipeline UUID or api_name" },
        all: { type: "boolean", description: "Include deselected objects." },
      },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["pipelines", "schema", "list", a.identifier];
      bool(v, "--all", a.all);
      return v;
    },
  },
  {
    name: "projects_list",
    description: "List projects in the active workspace.",
    readOnly: true,
    build: () => ["projects", "list"],
  },
  {
    name: "jobs_list",
    description: "List jobs in the active workspace.",
    readOnly: true,
    inputSchema: {
      type: "object",
      properties: {
        filter: { type: "array", items: { type: "string" }, description: "status=<v>, type=<v>, pipeline=<uuid> (repeatable)." },
        limit: { type: "number", default: 25 },
        offset: { type: "number", default: 0 },
      },
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["jobs", "list"];
      multi(v, "--filter", a.filter);
      opt(v, "--limit", a.limit);
      opt(v, "--offset", a.offset);
      return v;
    },
  },
  {
    name: "jobs_status",
    description: "Lightweight job status by id (for polling). Returns id, job_status, status_message, job_response.",
    readOnly: true,
    inputSchema: jobIdSchema,
    build: (a) => ["jobs", "status", a.id],
  },
  {
    name: "jobs_get",
    description: "Get a job by UUID including per-object metrics (execution_duration_ms, ended_at, object_details).",
    readOnly: true,
    inputSchema: jobIdSchema,
    build: (a) => ["jobs", "get", a.id],
  },
  {
    name: "jobs_logs",
    description: "Show stored job response/logs for a job.",
    readOnly: true,
    inputSchema: jobIdSchema,
    build: (a) => ["jobs", "logs", a.id],
  },
  {
    name: "schedules_list",
    description: "List schedules in the active workspace. Uses cron_schedule, target_type, target_id.",
    readOnly: true,
    inputSchema: {
      type: "object",
      properties: { state: { type: "string", description: "Filter by state (active, inactive)." } },
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["schedules", "list"];
      opt(v, "--state", a.state);
      return v;
    },
  },
  {
    name: "schedules_history",
    description: "View execution history for a schedule.",
    readOnly: true,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Schedule UUID or name" },
        limit: { type: "number", description: "Number of executions to show.", default: 10 },
      },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["schedules", "history", a.identifier];
      opt(v, "--limit", a.limit);
      return v;
    },
  },
  {
    name: "docs",
    description: "Show Supaflow documentation for a connector or topic (returns markdown). Use list:true to list topics.",
    readOnly: true,
    json: false,
    inputSchema: {
      type: "object",
      properties: {
        topic: { type: "string", description: "Connector or topic name." },
        list: { type: "boolean", description: "List all available topics." },
      },
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["docs"];
      if (a.topic) v.push(a.topic);
      bool(v, "--list", a.list);
      return v;
    },
  },

  // ---------- write / action ----------
  {
    name: "datasources_init",
    description: "Scaffold a .env file for a new datasource (writes a template; you fill in credentials).",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        connector: { type: "string", description: "Connector type (e.g. postgres, snowflake, s3)." },
        name: { type: "string", description: "Datasource name." },
        output_file: { type: "string", description: "Output .env path (default <api_name>.env)." },
      },
      required: ["connector", "name"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["datasources", "init", "--connector", a.connector, "--name", a.name];
      opt(v, "--output", a.output_file);
      return v;
    },
  },
  {
    name: "datasources_create",
    description: "Create a datasource from a (user-prepared) env file; tests the connection first.",
    write: true,
    timeoutMs: 120000,
    inputSchema: {
      type: "object",
      properties: { from_file: { type: "string", description: "Path to the env file." } },
      required: ["from_file"],
      additionalProperties: false,
    },
    build: (a) => ["datasources", "create", "--from", a.from_file],
  },
  {
    name: "datasources_edit",
    description: "Update a datasource from an env file.",
    write: true,
    timeoutMs: 120000,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Datasource UUID or api_name" },
        from_file: { type: "string", description: "Path to the env file." },
        skip_test: { type: "boolean", description: "Save without testing the connection." },
      },
      required: ["identifier", "from_file"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["datasources", "edit", a.identifier, "--from", a.from_file];
      bool(v, "--skip-test", a.skip_test);
      return v;
    },
  },
  {
    name: "datasources_test",
    description: "Test the connection for an existing datasource.",
    write: true,
    timeoutMs: 120000,
    inputSchema: idSchema("Datasource UUID or api_name"),
    build: (a) => ["datasources", "test", a.identifier],
  },
  {
    name: "datasources_enable",
    description: "Enable a datasource (set state to active).",
    write: true,
    inputSchema: idSchema("Datasource UUID or api_name"),
    build: (a) => ["datasources", "enable", a.identifier],
  },
  {
    name: "datasources_disable",
    description: "Disable a datasource (set state to inactive).",
    write: true,
    inputSchema: idSchema("Datasource UUID or api_name"),
    build: (a) => ["datasources", "disable", a.identifier],
  },
  {
    name: "datasources_delete",
    description: "Delete a datasource.",
    write: true,
    destructive: true,
    inputSchema: idSchema("Datasource UUID or api_name"),
    build: (a) => ["datasources", "delete", a.identifier],
  },
  {
    name: "datasources_refresh",
    description: "Trigger a schema refresh for a datasource (waits for completion).",
    write: true,
    timeoutMs: 180000,
    inputSchema: idSchema("Datasource UUID or api_name"),
    build: (a) => ["datasources", "refresh", a.identifier],
  },
  {
    name: "pipelines_init",
    description: "Generate a pipeline config file from source + project destination capabilities. ALWAYS use before pipelines_create.",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string", description: "Source datasource (UUID or api_name)." },
        project: { type: "string", description: "Project (UUID or api_name; destination resolved from project)." },
        output_file: { type: "string", description: "Output path (default pipeline-config.json).", default: "pipeline-config.json" },
      },
      required: ["source", "project"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["pipelines", "init", "--source", a.source, "--project", a.project];
      opt(v, "--output", a.output_file);
      return v;
    },
  },
  {
    name: "pipelines_create",
    description: "Create a new pipeline. Use pipelines_init first and present config + object scope for confirmation.",
    write: true,
    timeoutMs: 120000,
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Pipeline name." },
        source: { type: "string", description: "Source datasource (UUID or api_name)." },
        project: { type: "string", description: "Project (UUID or api_name; destination comes from project)." },
        config_file: { type: "string", description: "JSON file with pipeline config overrides." },
        objects_file: { type: "string", description: "JSON file with object selections (default: select all discovered)." },
        description: { type: "string", description: "Pipeline description." },
      },
      required: ["name", "source", "project"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["pipelines", "create", "--name", a.name, "--source", a.source, "--project", a.project];
      opt(v, "--config", a.config_file);
      opt(v, "--objects", a.objects_file);
      opt(v, "--description", a.description);
      return v;
    },
  },
  {
    name: "pipelines_edit",
    description: "Update pipeline configuration.",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Pipeline UUID or api_name" },
        config_file: { type: "string", description: "JSON file with config overrides." },
        name: { type: "string", description: "Update pipeline name." },
        description: { type: "string", description: "Update pipeline description." },
      },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["pipelines", "edit", a.identifier];
      opt(v, "--config", a.config_file);
      opt(v, "--name", a.name);
      opt(v, "--description", a.description);
      return v;
    },
  },
  {
    name: "pipelines_schema_select",
    description: "Set a pipeline's object selection from a JSON file (use the output of pipelines_schema_list with all:true).",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Pipeline UUID or api_name" },
        from_file: { type: "string", description: "JSON file with object selections." },
      },
      required: ["identifier", "from_file"],
      additionalProperties: false,
    },
    build: (a) => ["pipelines", "schema", "select", a.identifier, "--from", a.from_file],
  },
  {
    name: "pipelines_schema_add",
    description: "Add a single object to a pipeline's selection.",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Pipeline UUID or api_name" },
        object: { type: "string", description: "Fully-qualified object name to add." },
      },
      required: ["identifier", "object"],
      additionalProperties: false,
    },
    build: (a) => ["pipelines", "schema", "add", a.identifier, a.object],
  },
  {
    name: "pipelines_enable",
    description: "Enable a pipeline (set state to active).",
    write: true,
    inputSchema: idSchema("Pipeline UUID or api_name"),
    build: (a) => ["pipelines", "enable", a.identifier],
  },
  {
    name: "pipelines_disable",
    description: "Disable a pipeline (set state to inactive).",
    write: true,
    inputSchema: idSchema("Pipeline UUID or api_name"),
    build: (a) => ["pipelines", "disable", a.identifier],
  },
  {
    name: "pipelines_delete",
    description: "Delete a pipeline (soft delete). The MCP approval prompt is the confirmation.",
    write: true,
    destructive: true,
    inputSchema: idSchema("Pipeline UUID or api_name"),
    build: (a) => ["pipelines", "delete", a.identifier, "--yes"],
  },
  {
    name: "pipelines_sync",
    description: "Trigger a pipeline sync. Returns the job; poll with jobs_status.",
    write: true,
    timeoutMs: 120000,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Pipeline UUID or api_name" },
        full_resync: { type: "boolean", description: "Reset cursors and re-sync all data from scratch." },
        reset_target: { type: "boolean", description: "Drop and recreate destination tables (use with full_resync)." },
      },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["pipelines", "sync", a.identifier];
      bool(v, "--full-resync", a.full_resync);
      bool(v, "--reset-target", a.reset_target);
      return v;
    },
  },
  {
    name: "projects_create",
    description: "Create a new project (links pipelines to a destination warehouse).",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Project name." },
        destination: { type: "string", description: "Destination datasource UUID or api_name." },
        type: { type: "string", enum: ["pipeline", "ingestion", "transformation", "activation"], default: "pipeline" },
      },
      required: ["name", "destination"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["projects", "create", "--name", a.name, "--destination", a.destination];
      opt(v, "--type", a.type);
      return v;
    },
  },
  {
    name: "schedules_create",
    description: "Create a schedule (cron is 5-field, UTC). Target one of pipeline/task/orchestration.",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Schedule name." },
        cron: { type: "string", description: "Cron expression (5-field, UTC)." },
        pipeline: { type: "string", description: "Target pipeline (UUID or api_name)." },
        task: { type: "string", description: "Target task (UUID or api_name)." },
        orchestration: { type: "string", description: "Target orchestration (UUID or api_name)." },
        timezone: { type: "string", description: "Display timezone (e.g. America/New_York).", default: "UTC" },
        description: { type: "string" },
      },
      required: ["name", "cron"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["schedules", "create", "--name", a.name, "--cron", a.cron];
      opt(v, "--pipeline", a.pipeline);
      opt(v, "--task", a.task);
      opt(v, "--orchestration", a.orchestration);
      opt(v, "--timezone", a.timezone);
      opt(v, "--description", a.description);
      return v;
    },
  },
  {
    name: "schedules_edit",
    description: "Update a schedule.",
    write: true,
    inputSchema: {
      type: "object",
      properties: {
        identifier: { type: "string", description: "Schedule UUID or name" },
        name: { type: "string" },
        cron: { type: "string" },
        timezone: { type: "string" },
        description: { type: "string" },
        pipeline: { type: "string" },
        task: { type: "string" },
        orchestration: { type: "string" },
      },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => {
      const v = ["schedules", "edit", a.identifier];
      opt(v, "--name", a.name);
      opt(v, "--cron", a.cron);
      opt(v, "--timezone", a.timezone);
      opt(v, "--description", a.description);
      opt(v, "--pipeline", a.pipeline);
      opt(v, "--task", a.task);
      opt(v, "--orchestration", a.orchestration);
      return v;
    },
  },
  {
    name: "schedules_delete",
    description: "Delete a schedule.",
    write: true,
    destructive: true,
    inputSchema: idSchema("Schedule UUID or name"),
    build: (a) => ["schedules", "delete", a.identifier],
  },
  {
    name: "schedules_enable",
    description: "Enable a schedule (set state to active).",
    write: true,
    inputSchema: idSchema("Schedule UUID or name"),
    build: (a) => ["schedules", "enable", a.identifier],
  },
  {
    name: "schedules_disable",
    description: "Disable a schedule (set state to inactive).",
    write: true,
    inputSchema: idSchema("Schedule UUID or name"),
    build: (a) => ["schedules", "disable", a.identifier],
  },
  {
    name: "schedules_run",
    description: "Trigger immediate execution of a schedule.",
    write: true,
    timeoutMs: 120000,
    inputSchema: idSchema("Schedule UUID or name"),
    build: (a) => ["schedules", "run", a.identifier],
  },
  {
    name: "workspaces_select",
    description: "Set the active workspace (by UUID, api_name, or name). Changes host CLI state for subsequent calls.",
    write: true,
    inputSchema: {
      type: "object",
      properties: { identifier: { type: "string", description: "Workspace UUID, api_name, or name." } },
      required: ["identifier"],
      additionalProperties: false,
    },
    build: (a) => ["workspaces", "select", a.identifier],
  },
];

const BY_NAME = new Map(TOOLS.map((t) => [t.name, t]));

async function runSupaflow(spec, args) {
  const argv = spec.build(args || {});
  if (spec.json !== false) argv.push("--json");
  const { stdout } = await execFileP("supaflow", argv, {
    env: CHILD_ENV,
    maxBuffer: 32 * 1024 * 1024,
    timeout: spec.timeoutMs || 60000,
  });
  return stdout;
}

const server = new Server(
  { name: "supaflow", version: "0.2.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS.map((t) => ({
    name: t.name,
    description: t.description,
    inputSchema: t.inputSchema || { type: "object", properties: {}, additionalProperties: false },
    annotations: {
      readOnlyHint: !!t.readOnly,
      destructiveHint: !!t.destructive,
      idempotentHint: !!t.readOnly,
      openWorldHint: true,
    },
  })),
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args = {} } = req.params;
  const spec = BY_NAME.get(name);
  if (!spec) {
    return { isError: true, content: [{ type: "text", text: `Unknown tool: ${name}` }] };
  }
  try {
    const out = await runSupaflow(spec, args);
    return { content: [{ type: "text", text: out || "(no output)" }] };
  } catch (err) {
    // CLI errors emit {"error":{code,message}} on stdout with a non-zero exit.
    const body =
      err?.stdout?.toString?.().trim() ||
      err?.stderr?.toString?.().trim() ||
      err?.message ||
      String(err);
    return { isError: true, content: [{ type: "text", text: body }] };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
