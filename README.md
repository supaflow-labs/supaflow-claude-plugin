# Supaflow Plugin for Claude Code

Official Claude Code plugin for [Supaflow](https://www.supa-flow.io), the unified data movement platform. Manage datasources, pipelines, schedules, and job monitoring through natural language backed by the `@getsupaflow/cli`.

## Install

### From GitHub (recommended)

Register the repo as a marketplace, then install:

```bash
claude plugin marketplace add https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude plugin install supaflow-claude-plugin
```

### Local development (per-session)

Clone the repo and load with `--plugin-dir`:

```bash
git clone https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude --plugin-dir ./supaflow-claude-plugin
```

`--plugin-dir` loads the plugin for the current session only, without permanent installation. Use this for development and testing.

## Architecture

The plugin is organized in three layers:

**`using-supaflow` skill** - Injected at session start. Establishes session policy, tool restrictions, and routes incoming requests to the correct command or domain skill.

**Commands** - Execution layer. Each command maps to one user-facing workflow, enforces guardrails (e.g., blocks destructive actions in activation pipelines), and restricts which tools may run.

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
| `/create-schedule` | Schedule recurring pipeline syncs |

## Domain Skills

| Skill | Content |
|---|---|
| `supaflow-datasources` | Connector properties, env file format, credential catalog |
| `supaflow-pipelines` | Pipeline config fields, schema management, sync modes |
| `supaflow-jobs` | Job lifecycle, metrics schema, log analysis patterns |
| `supaflow-schedules` | Cron syntax, timezone handling, schedule constraints |

Domain skills are loaded automatically when a command needs them. They are not invoked directly.

## Setup

On first session after install, the plugin verifies:

- Node.js 18+ is installed
- Supaflow CLI v0.1.10+ is installed (`npm install -g @getsupaflow/cli`)
- CLI is authenticated with a valid API key (`supaflow auth login`)
- A workspace is selected (`supaflow workspaces select`)

If anything is missing, Claude will guide you through the setup. An API key can be generated at `https://app.supa-flow.io` under Settings > API Keys.

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
