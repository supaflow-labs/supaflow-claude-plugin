# Supaflow Code

Operate [Supaflow](https://www.supa-flow.io) from Claude Code using the local Supaflow CLI and its CLI-backed MCP server. This GitHub edition preserves local datasource configuration workflows, pipeline setup, sync monitoring, schedules, diagnostics, and private Docker-agent lifecycle support.

Use this package only in **Claude Code with a local shell**. For Claude web, Desktop chat, or Cowork, install the hosted-MCP-only **Supaflow** edition instead. Do not try to solve a sandbox/PATH limitation by installing this package there.

## Install from GitHub

```bash
claude plugin marketplace add https://github.com/supaflow-labs/supaflow-claude-plugin.git
claude plugin install supaflow-code@supaflow
```

For a per-session development test after explicit authorization:

```bash
claude --plugin-dir ./plugins/supaflow-code
```

The repository root is not an installable plugin. Install one edition for a workflow; local CLI identity and hosted OAuth identity are not interchangeable.

## Enable access before local login

An organization administrator or personal-account owner must select the intended account in [Supaflow Settings > API Keys](https://app.supa-flow.io/settings/api-keys), open **Permissions**, check **Enable API access** and **Supaflow CLI** under **OAuth applications**, then click **Save changes**, review, and **Save access settings**. Access is off by default; administrator status alone does not enable it. API keys are not required for browser OAuth.

For explicitly chosen key-based/headless use, enable **Allow API keys** instead and create a key in the **Keys** tab. Existing keys need this permission too. Local stdio MCP reuses the CLI's login and access settings; selecting hosted **Claude** or **ChatGPT** does not authorize this local path. A key can still be used by the CLI when CLI OAuth is unchecked.

On access denial, have the user or their administrator check the active account and saved permissions before reconnecting. Never change access settings automatically, request credentials in chat, or switch authentication methods to work around a denial. Existing agent identities and dashboard-issued OTP enrollment/recovery remain independent of these settings; CLI-managed operations still need permitted CLI authentication. See the [API access guide](https://www.supa-flow.io/docs/settings/api-keys#enable-api-access-first).

## Local prerequisites

- Node.js 18 or newer, Python 3 for the local hook/JSON parsers, and Supaflow CLI 0.8.0 or newer.
- Install/update the CLI yourself, or explicitly approve the assistant doing so:
  `npm install -g @getsupaflow/cli`.
- Authenticate in your own terminal with `supaflow auth login`, then select a workspace with `supaflow workspaces select <name-or-uuid>`. CLI 0.8.0+ login opens your browser for PKCE sign-in and consent. API keys remain optional for headless use through `SUPAFLOW_API_KEY`, which overrides stored OAuth. Existing keys work only while API access and API keys remain enabled. Older CLI releases may prompt for a key; upgrade to CLI 0.8.0 or newer. Never paste credentials into chat.
- Docker is required only for local private-agent lifecycle operations.

The package's `.mcp.json` launches `supaflow mcp` in Claude Code. That stdio server comes from the existing CLI and uses its local credentials and selected workspace. A SessionStart hook reports setup issues and injects the entry rules; it never installs dependencies or logs in for the user. Read the setup gate even if the hook did not run.

If the local MCP server is unavailable, the setup gate can route to local CLI commands. A timeout after a mutation is not permission to repeat it through the other surface: reconcile state first.

## Commands and skills

| Command | Purpose |
| --- | --- |
| `/supaflow-code:create-datasource` | Guided configuration and credential-safe datasource creation |
| `/supaflow-code:edit-datasource` | Local configuration export/edit/submit |
| `/supaflow-code:create-pipeline` | Duplicate checks, actual defaults, and reviewed object selection |
| `/supaflow-code:edit-pipeline` | Reviewed configuration/object edits |
| `/supaflow-code:delete-pipeline` | Confirmed deletion |
| `/supaflow-code:check-job` | Status and terminal results |
| `/supaflow-code:explain-job-failure` | Stored response/log diagnosis |
| `/supaflow-code:sync-pipeline` | Normal sync and job monitoring |
| `/supaflow-code:create-schedule` | Reviewed cadence/timezone and recurring sync |

The `supaflow-agents` skill manages local enrollment, status, logs, upgrade, stop, and removal through the existing CLI/local MCP capabilities. Enrollment approval changes tenant job routing; never activate an agent without an explicit request. Upgrade stops and replaces a container, and purging an identity volume requires explicit confirmation.

Command `allowed-tools` fields preapprove matching local tools during invocation; they are not a restriction on available tools or a bypass for destructive-action confirmation or managed permissions. Local setup and mutation safeguards still apply.

## Data and security

The CLI contacts the configured Supaflow service using the locally authenticated account; the plugin does not provide a second hosted server. Local configuration files and credential-bearing exports stay on the user's machine and must not be echoed into chat. Local MCP results and requested diagnostic details can be included in Claude's conversation context; summarize safe identifiers and redact secrets. Never request passwords, API keys, tokens, or private keys in chat.

Use only the requested account/workspace and review mutation targets before executing. Deletion, cancellation, full resync, destination resets, installs, and local-agent lifecycle changes require explicit confirmation.

Documentation: https://www.supa-flow.io/docs

Support: support@supa-flow.io

License: MIT
