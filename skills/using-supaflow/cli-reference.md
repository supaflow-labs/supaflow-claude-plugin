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

Credentials stored in `~/.supaflow/config.json` (mode 0600). Environment variables:

| Variable | Description |
|----------|-------------|
| `SUPAFLOW_API_KEY` | API key (alternative to `supaflow auth login`) |
| `SUPAFLOW_WORKSPACE_ID` | Workspace UUID (alternative to `supaflow workspaces select`) |

To authenticate:
```bash
supaflow auth login --key <api-key>
supaflow workspaces select <name-or-uuid>
```

API keys start with `ak_` and are created at https://app.supa-flow.io > Settings > API Keys.

## Error Codes

| Code | Exit | Meaning |
|------|------|---------|
| `NOT_AUTHENTICATED` | 2 | Not logged in or bad key |
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
