# Supaflow CLI Reference

## JSON Output Contract

All commands with `--json` follow this contract:

- **List commands**: `{ "data": [...], "total": N, "limit": N, "offset": N }`
- **Get/create/edit commands**: the raw object
- **Errors**: `{ "error": { "code": "ERROR_CODE", "message": "..." } }` with non-zero exit code

**When parsing JSON with python3, ALWAYS check for errors first:**
```python
d = json.load(sys.stdin)
if 'error' in d: print(d['error']['message']); sys.exit(1)
```

### Job cancellation

`supaflow jobs cancel <job-id> --json` accepts a UUID and returns:

```json
{ "id": "<job-id>", "job_status": "cancelled" }
```

The command makes one atomic `cancel_job(p_job_id)` RPC call after local UUID validation. The RPC handles authorization, workspace access, active-state validation, cancellation, and the actor-stamped status message. A terminal, inaccessible, or missing job returns the same generic CLI error.

## Global Flags

| Flag | Description |
|------|-------------|
| `--json` | Machine-readable JSON output (always use for agent workflows) |
| `--workspace <id>` | Override the active workspace for this command |
| `--api-key <key>` | Override the stored API key for this command |
| `--verbose` | Enable debug output |

## Identifier Resolution

Most commands accept either a UUID or an `api_name` as the identifier:
```bash
supaflow datasources get 8a3f1b2c-...
supaflow datasources get my_postgres
```
Exception: schedules resolve by **name** (not api_name).

## Authentication

OAuth or API-key credentials are stored in `~/.supaflow/config.json` (mode 0600). Environment variables:

| Variable | Description |
|----------|-------------|
| `SUPAFLOW_API_KEY` | Optional headless/CI API key; overrides stored OAuth |
| `SUPAFLOW_WORKSPACE_ID` | Workspace UUID (alternative to `supaflow workspaces select`) |

To authenticate (the user runs this in their own terminal -- never pass an API key through the agent or chat):
```bash
supaflow auth login            # opens browser OAuth with PKCE (CLI 0.8.0+)
supaflow workspaces select <name-or-uuid>
```

> **Agent note:** never log in on the user's behalf with a key pasted into chat. The non-interactive `--key <value>` flag is a local convenience for the user's own terminal only -- not an agent workflow. A secret in the transcript is treated as compromised.

Browser login stores refreshable OAuth credentials. Local stdio MCP shares this login; hosted OAuth remains separate. Existing API-key logins stay valid. If an older CLI prompts for a key, offer an approved upgrade to CLI 0.8.0 or newer.

API keys remain an option for headless use or explicit user preference. API keys start with `ak_` and are created at https://app.supa-flow.io > Settings > API Keys.

## Error Codes

| Code | Exit | Meaning |
|------|------|---------|
| `NOT_AUTHENTICATED` | 2 | Not logged in or invalid credentials |
| `NO_WORKSPACE` | 2 | No workspace selected |
| `NOT_FOUND` | 1 | Resource not found |
| `INVALID_INPUT` | 1 | Bad request data |
| `FORBIDDEN` | 1 | Insufficient permissions |
| `API_ERROR` | 1 | Server error |

## Available Connectors

```bash
supaflow connectors list --json
```
Returns connector `type` (used in `--connector` flag), `name`, `version`, and `capabilities`.
