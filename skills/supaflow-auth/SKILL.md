---
name: supaflow-auth
description: This skill should be used when the user asks to "authenticate with Supaflow", "log in to Supaflow", "set up Supaflow CLI", "install Supaflow CLI", "select a workspace", "switch workspace", "check auth status", "configure Supaflow API key", or mentions Supaflow authentication, workspace selection, or CLI setup. Provides guidance for authenticating the @getsupaflow/cli and selecting the active workspace.
---

# Supaflow Authentication and Workspace Setup

Authenticate the Supaflow CLI and select a workspace before running any other commands. All Supaflow CLI operations require a valid API key and an active workspace.

## Prerequisites

### Node.js 18+

Check if Node.js is installed and meets the minimum version:

```bash
node --version
# Requires v18.x.x or higher
```

If Node.js is missing or too old, install it:

```bash
# macOS (Homebrew)
brew install node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Windows (winget)
winget install OpenJS.NodeJS.LTS
```

### Supaflow CLI

Install the CLI globally via npm:

```bash
npm install -g @getsupaflow/cli
supaflow --version
```

If `supaflow` is not found after install, verify the npm global bin directory is on the PATH:

```bash
npm bin -g
# Add the output directory to PATH if needed
```

### Supaflow Account and API Key

These steps require the user to act in a browser. Guide them through each step:

1. **Sign up** (skip if already have an account):
   - Open `https://app.supa-flow.io/sign-up`
   - Create an account with email or SSO
   - Verify email if prompted
   - On first login, the app creates a default workspace automatically

2. **Create an API key**:
   - Open `https://app.supa-flow.io` and log in
   - Click the gear icon in the top-right corner (next to your profile avatar) to open **Settings**
   - Click **API Keys** in the settings menu
   - Click **Create key**
   - Enter a name (e.g., "CLI Access") and click **Create**
   - Copy the key immediately -- it starts with `ak_` and is only shown once

API keys are scoped to the organization that is active when created. To access a different organization's workspaces, switch to that organization in the web app first, then create a separate key.

If the user already has an API key, skip straight to authentication below.

## Authentication Flow

```bash
supaflow auth login
# Paste API key when prompted
```

Verify authentication:

```bash
supaflow auth status --json
```

Successful output:

```json
{ "authenticated": true, "source": "config" }
```

The API key is stored in `~/.supaflow/config.json` with user-only file permissions (mode 0600). To avoid storing the key on disk, set `SUPAFLOW_API_KEY` as an environment variable instead.

### Select a Workspace

List available workspaces and select one:

```bash
supaflow workspaces list --json
```

```json
{
  "data": [
    { "id": "uuid-here", "name": "My Workspace" }
  ],
  "total": 1,
  "limit": 25,
  "offset": 0
}
```

Select the workspace by name, api_name, or UUID (non-interactive, agent-friendly):

```bash
# By name
supaflow workspaces select Dev

# By api_name
supaflow workspaces select DEV

# By UUID
supaflow workspaces select 0ca8d04f-340d-4546-97f2-311f5662f2db

# Interactive (prompts user -- avoid in agent workflows)
supaflow workspaces select
```

All subsequent commands operate within the selected workspace.

## Environment Variables

For non-interactive use (scripts, CI/CD, agents), set environment variables instead of running interactive login/select:

| Variable | Description |
|----------|-------------|
| `SUPAFLOW_API_KEY` | API key (alternative to `supaflow auth login`) |
| `SUPAFLOW_WORKSPACE_ID` | Workspace UUID (alternative to `supaflow workspaces select`) |
| `SUPAFLOW_APP_URL` | Override app URL (default: `https://app.supa-flow.io`) |
| `SUPAFLOW_SUPABASE_URL` | Direct Supabase project URL (bypasses bootstrap entirely) |
| `SUPAFLOW_SUPABASE_ANON_KEY` | Supabase anon key (required when using `SUPAFLOW_SUPABASE_URL` or `--supabase-url`) |

When `SUPAFLOW_API_KEY` and `SUPAFLOW_WORKSPACE_ID` are set, skip the login and workspace select steps entirely.

### Direct Supabase Override (Dev/Testing)

When the bootstrap endpoint at `app.supa-flow.io` is unavailable or when testing against a non-standard environment, bypass it entirely by providing the Supabase connection directly:

```bash
export SUPAFLOW_SUPABASE_URL=https://your-project.supabase.co
export SUPAFLOW_SUPABASE_ANON_KEY=eyJ...
export SUPAFLOW_API_KEY=<jwt-token>   # must be a valid JWT, not an ak_ key
```

Or per-command via the `--supabase-url` flag (still requires `SUPAFLOW_SUPABASE_ANON_KEY` env var):

```bash
supaflow pipelines list --supabase-url https://your-project.supabase.co --json
```

**Priority order**: env var override > `--supabase-url` flag > bootstrap endpoint. When using the direct override path, `SUPAFLOW_API_KEY` must contain a valid JWT (not an `ak_` API key), because the bootstrap token-exchange step is skipped.

## Logout

```bash
supaflow auth logout
```

Removes stored credentials from `~/.supaflow/config.json`.

## Global Flags

Every Supaflow CLI command supports these flags:

| Flag | Description |
|------|-------------|
| `--json` | Machine-readable JSON output (always use for agent workflows) |
| `--workspace <id>` | Override the active workspace for this command |
| `--api-key <key>` | Override the stored API key for this command |
| `--supabase-url <url>` | Override Supabase project URL (requires `SUPAFLOW_SUPABASE_ANON_KEY` env var) |
| `--verbose` | Enable debug output |
| `--no-color` | Suppress ANSI colors |

Always pass `--json` when invoking commands programmatically so output can be parsed and reasoned about.

## JSON Output Contract

All commands with `--json` follow this contract:

- **List commands**: `{ "data": [...], "total": N, "limit": N, "offset": N }`
- **Get/create/edit commands**: the raw object
- **Errors**: `{ "error": { "code": "ERROR_CODE", "message": "..." } }` with non-zero exit code

Error codes and exit codes:

| Code | Exit | Meaning |
|------|------|---------|
| `NOT_AUTHENTICATED` | 2 | Not logged in or bad key |
| `NO_WORKSPACE` | 2 | No workspace selected |
| `NOT_FOUND` | 1 | Resource not found |
| `INVALID_INPUT` | 1 | Bad request data |
| `FORBIDDEN` | 1 | Insufficient permissions |
| `API_ERROR` | 1 | Server error |
| `NETWORK_ERROR` | 1 | Cannot reach server |
| `RATE_LIMITED` | 1 | Too many requests |

## Identifier Resolution

Most commands accept either a UUID or an `api_name` as the identifier:

```bash
# These are equivalent
supaflow datasources get 8a3f1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c
supaflow datasources get my_postgres
```

Exception: schedules resolve by **name** (not api_name), since schedule names are unique per workspace.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| "Not authenticated" | Run `supaflow auth login` or set `SUPAFLOW_API_KEY` |
| "No workspace selected" | Run `supaflow workspaces select` or set `SUPAFLOW_WORKSPACE_ID` |
| "Invalid, revoked, or expired API key" | Create a new key in Settings > API Keys |
| "Bootstrap endpoint unavailable" | Network issue reaching `app.supa-flow.io`. Set `SUPAFLOW_SUPABASE_URL` and `SUPAFLOW_SUPABASE_ANON_KEY` to bypass bootstrap |

## Available Connectors

After authenticating, list available connector types:

```bash
supaflow connectors list --json
```

This returns connector type identifiers (used in `--connector` flag for datasource creation), display names, and versions.
