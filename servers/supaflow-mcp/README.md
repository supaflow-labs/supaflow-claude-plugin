# supaflow-mcp (prototype stdio MCP server)

A thin local **stdio** MCP server that exposes the Supaflow CLI as
`mcp__supaflow__*` tools by shelling out to `supaflow … --json`. This is the
step-2 prototype; if it proves out it folds into the CLI as `supaflow mcp`.

## Why this exists

The plugin's slash commands call the CLI via `Bash(supaflow *)`. That works in
terminal Claude Code (the CLI is on `PATH`), but **fails in Claude Desktop**:
Desktop runs Claude Code inside an ephemeral **cowork VM** where the host's
`supaflow` binary doesn't exist. An MCP server fixes this — but **only if it
runs on the host**.

## CRITICAL: register on the HOST, not as a plugin `.mcp.json`

Where the server runs decides everything:

| Registration | Runs | Sees host `supaflow`? |
|---|---|---|
| `claude_desktop_config.json` (host) | on your Mac | **Yes** — and Desktop bridges its tools into the cowork VM (verified: Playwright works this way) |
| plugin `.mcp.json` (`${CLAUDE_PLUGIN_ROOT}/…`) | inside the cowork VM | **No** — same wall as the bash path |

So for Desktop, this server **must** be registered host-side. The host server
reuses the host's `~/.supaflow/config.json`, so there is **no per-session
install and no per-session login**.

## Setup

1. Install deps (once):
   ```bash
   cd servers/supaflow-mcp && npm install
   ```
2. Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "supaflow": {
         "command": "node",
         "args": ["/ABSOLUTE/PATH/TO/supaflow-claude-plugin/servers/supaflow-mcp/server.mjs"],
         "env": { "PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" }
       }
     }
   }
   ```
   - Use an **absolute** path to `server.mjs` (no `${CLAUDE_PLUGIN_ROOT}` — that
     only resolves inside the VM).
   - If Desktop can't find `node`, use the absolute `/opt/homebrew/bin/node`.
   - **Auth:** running host-side, it reuses your existing `~/.supaflow/config.json`
     automatically. To be explicit/portable instead, add to `env`:
     `"SUPAFLOW_API_KEY": "ak_…", "SUPAFLOW_WORKSPACE_ID": "…"` (the CLI reads
     these). Put the key in this config file yourself — never via chat.
3. Restart Claude Desktop. The tools appear as `mcp__supaflow__auth_status`, etc.

## Tools (prototype slice)

- `auth_status` — auth + selected workspace.
- `datasources_list` — datasources in the active workspace (`limit`, capped 200).
- `jobs_status` — job status by `job_id`.

(Expand to pipelines / projects / sync / schedules once the round-trip is
confirmed in Desktop.)

## Smoke test (host)

```bash
node -e 'import("@modelcontextprotocol/sdk/client/index.js")' # deps present?
```
Or drive it with any MCP client pointed at `node server.mjs`. Verified locally:
`tools/list` returns the three tools and `auth_status` returns the live CLI JSON.
