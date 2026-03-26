# supaflow-claude-plugin

Claude Code plugin for managing [Supaflow](https://www.supa-flow.io) data pipelines through natural language. Wraps the `@getsupaflow/cli` so Claude Code can create datasources, build pipelines, schedule syncs, and monitor jobs.

## Install

Add the Supaflow marketplace, then install the plugin:

```bash
claude plugin marketplace add https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude plugin install supaflow-claude-plugin
```

For local development, use `--plugin-dir` instead:

```bash
claude --plugin-dir /path/to/supaflow-claude-plugin
```

On first session after install, a setup hook checks whether the Supaflow CLI is installed and authenticated. If anything is missing, Claude will guide you through the setup automatically.

### Manual Setup (if needed)

The plugin requires Node.js 18+, the Supaflow CLI, and a Supaflow account:

```bash
# 1. Install Node.js 18+ (skip if already installed)
brew install node          # macOS
# See https://nodejs.org for other platforms

# 2. Install the Supaflow CLI
npm install -g @getsupaflow/cli
supaflow --version

# 3. Authenticate (requires an API key from https://app.supa-flow.io > Settings > API Keys)
supaflow auth login
supaflow workspaces select
```

## What This Plugin Provides

Six skills that teach Claude Code how to manage Supaflow resources through the CLI:

| Skill | Purpose |
|-------|---------|
| `supaflow-auth` | Authentication, workspace selection, environment variables, troubleshooting |
| `supaflow-datasources` | Datasource lifecycle: init, create, edit, test, catalog, refresh, delete, disable, enable |
| `supaflow-pipelines` | Pipeline lifecycle: create, edit, sync, schema selection, delete, disable, enable |
| `supaflow-schedules` | Schedule management: create, edit, run, history, delete, disable, enable |
| `supaflow-jobs` | Job monitoring: list, get, logs, failure diagnosis |
| `supaflow-quickstart` | End-to-end walkthrough: auth through scheduled pipeline in the correct order |

Skills activate automatically based on what you ask Claude to do. No slash commands required.

## How It Works

1. You describe what you want in natural language (e.g., "Set up a pipeline from my Postgres database to Snowflake")
2. Claude loads the relevant skill(s) to understand the CLI commands needed
3. Claude generates and runs `supaflow` CLI commands with `--json` for structured output
4. Claude parses the results and guides you through the workflow

The plugin never reimplements CLI logic -- it teaches Claude the correct commands, flags, and workflows.

## Environment Variables

For non-interactive use (CI/CD, scripts, agent automation):

| Variable | Description |
|----------|-------------|
| `SUPAFLOW_API_KEY` | API key (alternative to `supaflow auth login`) |
| `SUPAFLOW_WORKSPACE_ID` | Workspace UUID (alternative to `supaflow workspaces select`) |
| `SUPAFLOW_APP_URL` | Override app URL (default: `https://app.supa-flow.io`) |
| `SUPAFLOW_SUPABASE_URL` | Direct Supabase project URL (bypasses bootstrap) |
| `SUPAFLOW_SUPABASE_ANON_KEY` | Supabase anon key (required with `SUPAFLOW_SUPABASE_URL` or `--supabase-url`) |

## Quick Example

```
You: Set up a pipeline to sync my Postgres database to Snowflake every hour

Claude: I'll walk you through the full setup...
        1. Creates source datasource (scaffolds env file, you fill in creds, creates)
        2. Creates destination datasource (same flow for Snowflake)
        3. Creates a project linking to the destination
        4. Exports the catalog, you select objects
        5. Creates the pipeline
        6. Runs the first sync
        7. Creates an hourly schedule
```

## License

MIT
