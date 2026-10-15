# Supaflow Code Setup Gate

This is the single setup gate for the GitHub-installed Supaflow Code edition. Read it before local operations even when the SessionStart hook did not run. It does not apply to the hosted-MCP-only Supaflow marketplace package.

## 0. Confirm the execution environment

This edition is supported only in Claude Code with a local shell. In web chat, Desktop chat, or Cowork, stop and direct the user to the hosted Supaflow edition. Do not troubleshoot shell PATHs or install local programs in those environments.

Choose the local CLI-backed stdio MCP path when that server is available; otherwise use the terminal CLI path in Claude Code. Do not treat hosted OAuth `auth_status` as proof that the local CLI is authenticated: the accounts and workspace state can differ.

Names such as `mcp__supaflow__auth_status` are shorthand. Resolve the actual tool names exposed by the local server, including any plugin prefix. Its local tools expose the CLI selected-workspace contract and local capabilities such as `workspaces_select` or `pipelines_init` file output. Never apply this contract to the hosted URL server.

## 1. Local MCP gate

1. Call the local server's `auth_status`. If it is missing, cannot reach the local executable, or returns a transport error, do not retry a mutation through another path; resolve the setup issue first.
2. Parse `authenticated`. If false, ask the user to run `supaflow auth login` in their own terminal, then wait and recheck. CLI 0.8.0+ login opens browser OAuth with PKCE; the user reviews and approves the account, organization, permissions, and return destination. Never accept, request, or echo an API key in chat.
3. Parse the local `workspace_id`. If absent, call `workspaces_list`, ask which workspace to use, call `workspaces_select` only after the user's selection, then reread `auth_status`. Changing local selected-workspace state affects subsequent calls; do not infer it from an unrelated answer.
4. Require the exact local capability before using it, especially `agent_upgrade` and `jobs_cancel`. If missing, explain that the local CLI/server may need an upgrade and a fresh client session; do not invent an equivalent tool.
5. Use the local MCP workflows and safe executor. Do not copy hosted wrapper fields or OAuth assumptions into this path.

The plugin's `.mcp.json` launches `supaflow mcp` locally in Claude Code. It is not a hosted connector and is not the installation path for Desktop chat.

## 2. Terminal CLI gate

Run these checks when the local MCP surface is unavailable, before invoking a CLI workflow.

### Node and CLI

- Check `node --version`; require Node.js 18 or newer. Never auto-install Node. If absent or too old, give the user the official Node installation guidance and stop.
- Check `supaflow --version`; require CLI 0.8.0 or newer. If missing or outdated, offer `npm install -g @getsupaflow/cli` and wait for explicit confirmation before running it. If declined, provide the command for the user and stop.
- Recheck after installation/upgrade. SessionStart warnings describe local setup only and do not authorize an install.

### Authentication and workspace

- Run `supaflow auth status --json`; check `authenticated` and `workspace_id`.
- If unauthenticated, the user runs `supaflow auth login` in their own terminal. On CLI 0.8.0+, browser OAuth with PKCE is the default; do not ask them to create an API key for normal interactive setup.
- If no workspace is selected, ask the user to choose from `supaflow workspaces list --json`; select only that workspace and reread auth status.
- Do not print the CLI's credential file, environment variables, or key values. When multiple accounts/workspaces are plausible, confirm the local account/workspace rather than reusing hosted-connection IDs.

## 3. Resume and command permissions

After any setup fix, rerun the active gate and continue only when it passes. Do not assume a fresh OAuth connection authenticated the local CLI.

The command frontmatter's `allowed-tools` field preapproves matching calls during invocation; it does not restrict other tools or authorize installing dependencies. CLI install/upgrade still needs the user's explicit confirmation, and destructive-action confirmation still applies. Resolve prerequisites before starting the operation, not halfway through a command.

Never silently fall back from the hosted edition to this edition, start private agents merely because they are offline, or restart user-managed services as a setup convenience.


## Authentication choices and compatibility

- The local CLI stores its OAuth credentials and refreshes access tokens automatically; local stdio MCP invokes that same CLI and reuses its login. Do not add OAuth tokens or API keys to `.mcp.json`, or reuse a hosted connector's OAuth grant as a local credential.
- API keys remain an option for headless/CI use or when explicitly chosen. The user configures `SUPAFLOW_API_KEY` securely in their own environment; it takes precedence over stored OAuth. Never ask for the value or print the environment or credential file. Keys can be created in Supaflow Settings > API Keys.
- Existing API-key logins remain valid; do not force migration or log out a working user. Browser login replaces a stored API key; API-key login replaces stored OAuth. Do not remove either without the user's intent.
- Updated `auth_status` reports `method: oauth` or `method: api_key`; older releases may omit `method`. Gate on `authenticated` and verify remote access with `workspaces_list` or `supaflow workspaces list --json`, not by looking for `api_key` in a file. Do not equate configured credentials with verified workspace access.
- If `auth login` prompts for a key, the CLI lacks the browser-login default. Explain the version mismatch and offer an approved upgrade to CLI 0.8.0 or newer.
- Never initiate login through an MCP tool, approve browser consent for the user, or silently switch to API keys after an OAuth error. Have the user finish login, then recheck auth status and workspace access. Hosted OAuth remains a separate connection.
