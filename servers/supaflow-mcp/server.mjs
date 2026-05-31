#!/usr/bin/env node
// Supaflow stdio MCP server (prototype).
//
// Exposes a few Supaflow CLI operations as MCP tools by shelling out to the
// host `supaflow` binary with `--json`. Designed to run ON THE HOST (registered
// in claude_desktop_config.json), where the CLI and ~/.supaflow/config.json
// already live -- so no per-session install and no per-session `auth login`.
//
// Auth precedence (handled by the CLI itself, we just pass env through):
//   1. SUPAFLOW_API_KEY / SUPAFLOW_WORKSPACE_ID from this server's env block
//      (set in the MCP config -> non-interactive, persistent).
//   2. Otherwise the host's ~/.supaflow/config.json from `supaflow auth login`.
//
// This is a thin wrapper (step 2). If it proves out, fold it into the CLI as
// `supaflow mcp`.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

// Ensure the CLI and its `#!/usr/bin/env node` shebang resolve even under a
// minimal/GUI PATH. Prepend the usual npm-global bin dirs; the caller's PATH
// still wins for anything already present.
const EXTRA_BIN = ["/opt/homebrew/bin", "/usr/local/bin"];
const CHILD_ENV = {
  ...process.env,
  PATH: [...EXTRA_BIN, process.env.PATH || ""].filter(Boolean).join(":"),
};

// Run `supaflow <args> --json` and return raw stdout (already JSON).
async function runSupaflow(args) {
  const { stdout } = await execFileP("supaflow", [...args, "--json"], {
    env: CHILD_ENV,
    maxBuffer: 16 * 1024 * 1024,
  });
  return stdout;
}

const TOOLS = [
  {
    name: "auth_status",
    description:
      "Check Supaflow CLI authentication and the selected workspace. Returns authenticated, workspace_id, workspace_name.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "datasources_list",
    description:
      "List datasources in the active workspace. Returns { data, total, limit, offset }.",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Max rows (CLI hard-caps at 200).",
          default: 200,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "jobs_status",
    description:
      "Get the status of a Supaflow job by id. Returns id, job_status, status_message, job_response.",
    inputSchema: {
      type: "object",
      properties: {
        job_id: { type: "string", description: "The job id to look up." },
      },
      required: ["job_id"],
      additionalProperties: false,
    },
  },
];

const server = new Server(
  { name: "supaflow", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args = {} } = req.params;
  try {
    let out;
    switch (name) {
      case "auth_status":
        out = await runSupaflow(["auth", "status"]);
        break;
      case "datasources_list":
        out = await runSupaflow([
          "datasources",
          "list",
          "--limit",
          String(args.limit ?? 200),
        ]);
        break;
      case "jobs_status":
        if (!args.job_id) throw new Error("job_id is required");
        out = await runSupaflow(["jobs", "status", String(args.job_id)]);
        break;
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
    return { content: [{ type: "text", text: out }] };
  } catch (err) {
    const msg = err?.stderr?.toString?.() || err?.message || String(err);
    return { isError: true, content: [{ type: "text", text: msg }] };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
