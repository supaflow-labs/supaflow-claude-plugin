# Supaflow Plugin for Claude Code

Official Claude Code plugin for [Supaflow](https://www.supa-flow.io), the unified data movement platform. Manage datasources, pipelines, schedules, job monitoring, and local Docker agents through natural language backed by the host-side Supaflow MCP server in Claude Desktop, or by the `@getsupaflow/cli` in terminal Claude Code.

## Install

### From GitHub (recommended)

Register the repo as a marketplace, then install:

```bash
claude plugin marketplace add https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude plugin install supaflow
```

### Local development (per-session)

Clone the repo and load with `--plugin-dir`:

```bash
git clone https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude --plugin-dir ./supaflow-claude-plugin
```

`--plugin-dir` loads the plugin for the current session only, without permanent installation. Use this for development and testing.

## Architecture

The plugin is organized in four layers:

**`using-supaflow` skill** - Injected at session start. Establishes the setup gate, chooses Desktop MCP vs terminal CLI, and routes incoming requests to the correct workflow or domain skill.

**Desktop MCP server** - Ships inside `@getsupaflow/cli` (v0.5.0+) as `supaflow mcp`, registered host-side in `claude_desktop_config.json` (see Setup). It exposes `mcp__supaflow__*` tools by shelling out to the host `supaflow` CLI, so Claude Desktop uses the host CLI and `~/.supaflow/config.json` instead of the cowork VM. Guided tools return structured JSON and keep host-side temp files inside MCP.

**Commands** - Terminal CLI execution layer and workflow specs. Each command maps to one user-facing workflow and preserves tested guardrails for confirmations, parser contracts, and destructive actions.

**Domain skills** - Reference material. Loaded on demand to supply connector properties, config schemas, log patterns, and cron syntax without polluting the base context.

## Available Commands

| Command | Description |
|---|---|
| `/create-datasource` | Create a new datasource with guided credential setup |
| `/edit-datasource` | Edit datasource configuration |
| `/create-pipeline` | Create a pipeline from source to destination |
| `/edit-pipeline` | Edit pipeline config or object selection |
| `/delete-pipeline` | Delete a pipeline permanently |
| `/check-job` | Check job status or latest sync |
| `/explain-job-failure` | Diagnose a failed job |
| `/sync-pipeline` | Trigger a sync and poll for completion |
| `/create-schedule` | Schedule recurring pipeline syncs |

Local Docker agent operations do not use a slash command. The `supaflow-agents` skill routes them to `supaflow agent start|upgrade|stop|status|logs|remove` in terminal Claude Code or the corresponding `agent_*` MCP tools in Claude Desktop. The upgrade flow requires CLI 0.5.0+ and explicit confirmation because it stops and replaces the running container, while preserving its identity volume and automatically attempting rollback if the replacement does not start successfully.

## Domain Skills

| Skill | Content |
|---|---|
| `supaflow-datasources` | Connectors, credentials, and catalog |
| `supaflow-pipelines` | Pipeline setup, schema, and sync modes |
| `supaflow-jobs` | Look up job status, metrics, or logs |
| `supaflow-schedules` | Cron schedules and timezone handling |
| `supaflow-agents` | Local Docker agent enrollment, safe upgrades (CLI 0.5.0+), resume, status, logs, approval, and re-enrollment |

Domain skills are loaded automatically when a command needs them. They are not invoked directly.

## Setup

### Claude Desktop

Desktop usage should use the host-side MCP server that ships with the CLI (`@getsupaflow/cli` 0.5.0+). Register it in `claude_desktop_config.json`; do not use a plugin `.mcp.json` for Desktop, because that runs inside the cowork VM where the host CLI and `~/.supaflow/config.json` are not visible.

```json
{
  "mcpServers": {
    "supaflow": {
      "command": "supaflow",
      "args": ["mcp"]
    }
  }
}
```

Then restart Claude Desktop. The server reuses the host's `~/.supaflow/config.json`, so there is no per-session install or login. If Desktop cannot find `supaflow` on its PATH, use the absolute path to the binary (the output of `which supaflow`) as `command`.

### Terminal Claude Code

When MCP tools are not available, the plugin falls back to CLI checks. On first session after install, the plugin verifies:

- Node.js 18+ is installed
- Supaflow CLI v0.5.0+ is installed (`npm install -g @getsupaflow/cli`)
- CLI is authenticated with a valid API key (`supaflow auth login`)
- A workspace is selected (`supaflow workspaces select`)

If anything is missing, Claude will guide you through the setup. The user runs `supaflow auth login` in their own terminal; API keys must not be pasted into chat. An API key can be generated at `https://app.supa-flow.io` under Settings > API Keys.

## Testing

```bash
cd tests
./run-tests.sh              # run fast unit tests (default)
./run-tests.sh --medium     # include medium integration tests
./run-tests.sh --slow       # include slow end-to-end tests
./run-tests.sh --live       # run against a live Supaflow workspace
./run-tests.sh --all        # run everything
```

## License

MIT
