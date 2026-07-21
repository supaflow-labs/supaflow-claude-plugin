# Supaflow Setup Gate

This is the **single** setup gate for every Supaflow operation. It is injected at session start, ahead of the `using-supaflow` skill, and it owns ALL setup policy. The entry skill, MCP workflows, and slash commands defer to it -- do not duplicate or contradict this policy elsewhere.

**It is BLOCKING.** Run it before any datasource / pipeline / job / schedule action. If a check fails, resolve it (or hand the user the exact fix) and STOP. Do NOT proceed to the user's request with an unmet prerequisite. Apply the SAME policy every time -- the behavior must never be a coin-flip.

## 0. Choose the execution surface first

Before any Supaflow action, inspect the tools available in this conversation.

### Desktop MCP path -- preferred when present

If `mcp__supaflow__auth_status` is available, this is the active Supaflow surface. Use `mcp__supaflow__*` tools for Supaflow operations. Do NOT fall back to `Bash(supaflow *)` for Supaflow work in this path; Claude Desktop may run Bash inside a cowork VM that cannot see the host CLI or host auth.

Run the MCP gate below.

### Terminal CLI path -- fallback when MCP is absent

If no `mcp__supaflow__*` tools are available, use the CLI gate below. The slash commands are CLI workflows and remain valid in terminal Claude Code sessions where `Bash(supaflow *)` can see the local CLI.

In terminal Claude Code, this plugin's `.mcp.json` auto-launches the host `supaflow mcp` server, so `mcp__supaflow__*` tools are normally present here too and are preferred over `Bash(supaflow *)`. The CLI gate is the fallback for when they are not yet available -- e.g. before the CLI is installed, or pending a session restart after install.

### No valid surface

If neither MCP tools nor a working CLI path are available, STOP. For Desktop, tell the user to install `@getsupaflow/cli` (0.5.0+) and register `supaflow mcp` in `claude_desktop_config.json` (`{ "mcpServers": { "supaflow": { "command": "supaflow", "args": ["mcp"] } } }`), then restart Claude Desktop; do NOT suggest plugin `.mcp.json` for Desktop because that runs inside the cowork VM. (Terminal Claude Code is different: there the plugin `.mcp.json` runs on the host and is the intended MCP surface -- the no-plugin-`.mcp.json` rule is specific to Claude Desktop.)

## 1. MCP gate (Desktop)

Run in order when `mcp__supaflow__auth_status` is available.

### 1A. MCP server reachable

Call `mcp__supaflow__auth_status` with no arguments.

If the tool is missing, errors before returning JSON, or reports that `supaflow` cannot be found, STOP. Tell the user the host-side MCP server is not correctly registered or cannot see the host Supaflow CLI. The fix is host-side: install/update `@getsupaflow/cli` to 0.5.0+, register `supaflow mcp` in `claude_desktop_config.json`, then restart Claude Desktop.

### 1B. Authenticated -- the user logs in; no API key in chat

Parse the JSON text returned by `mcp__supaflow__auth_status`. Use `authenticated`.

If not authenticated, you **MUST**:
1. Ask the user to run `supaflow auth login` **in their own terminal**. The API key must NOT be pasted into chat -- it would persist in the transcript. They get the key from https://app.supa-flow.io > Settings > API Keys.
2. Wait for them to confirm, then call `mcp__supaflow__auth_status` again.

Never accept, request, or echo an API key in the conversation.

### 1C. Workspace selected

Parse `workspace_id` from `mcp__supaflow__auth_status`.

If none:
1. Call `mcp__supaflow__workspaces_list`.
2. Ask the user which workspace to use.
3. Call `mcp__supaflow__workspaces_select` only after the user selects or explicitly confirms the workspace.
4. Call `mcp__supaflow__auth_status` again.

Changing the workspace affects subsequent host-side MCP calls, so do not infer workspace selection from a partial answer.

## 2. CLI gate (terminal fallback)

Run in order only when `mcp__supaflow__auth_status` is not available.

### 2A. Node.js >= 18 -- cannot auto-install

Detect: `node --version`.

If missing or below v18: you **cannot** install Node for the user. Tell them to install Node 18+ (`brew install node` on macOS, or https://nodejs.org) and STOP until it is present.

### 2B. Supaflow CLI (`@getsupaflow/cli`) -- offer, then confirm, then install

Detect: `supaflow --version` (the SessionStart check reports whether it is missing or below the required minimum -- trust that signal for the CLI path).

If missing or outdated, you **MUST**:
1. Ask the user, in plain words: "The Supaflow CLI is <missing | outdated>. Want me to run `npm install -g @getsupaflow/cli`?"
2. Run that command **only after an explicit yes**. NEVER install or upgrade silently.
3. If the user declines, give them the command to run themselves and STOP.
4. Re-check `supaflow --version` after the install before continuing.

**Restricted-command note:** slash commands are tool-restricted to `Bash(supaflow *)` and cannot run `npm`. The install offer therefore happens at the session level, before a command runs -- never from inside a command. If the CLI is still missing once inside a command, STOP and surface the fix.

### 2C. Authenticated -- the user logs in; no API key in chat

Detect: `supaflow auth status --json`, parse `authenticated`.

If not authenticated, you **MUST**:
1. Ask the user to run `supaflow auth login` **in their own terminal**. The API key must NOT be pasted into chat -- it would persist in the transcript.
2. Wait for them to confirm, then re-check `supaflow auth status`.

Never accept, request, or echo an API key in the conversation.

### 2D. Workspace selected

Detect: `workspace_id` from `supaflow auth status --json`.

If none: tell the user to run `supaflow workspaces select <name>`, then re-check.

## Resume loop

After any install / login / workspace-select / MCP-config fix, **re-run the active gate from the top** and only continue to the user's request once every check in that gate passes. Never assume a fix worked -- verify it.

## Hard stops (non-negotiable)

- Prefer MCP tools when `mcp__supaflow__auth_status` is available.
- In Desktop MCP mode, never use `Bash(supaflow *)` as a fallback for Supaflow operations.
- Never run `npm install` (or any environment-mutating install/upgrade) without explicit user confirmation.
- Never auto-install Node.
- Never accept or echo an API key in chat -- the user runs `supaflow auth login` themselves.
- Never proceed to the user's request while the active gate is failing.
