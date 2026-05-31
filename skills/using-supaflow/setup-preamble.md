# Supaflow Setup Gate

This is the **single** setup gate for every Supaflow operation. It is injected at session start, ahead of the `using-supaflow` skill, and it owns ALL setup policy. The entry skill and every slash command defer to it -- do not duplicate or contradict this policy elsewhere.

**It is BLOCKING.** Run it before any datasource / pipeline / job / schedule action. If a check fails, resolve it (or hand the user the exact fix) and STOP. Do NOT proceed to the user's request with an unmet prerequisite. Apply the SAME policy every time -- the behavior must never be a coin-flip.

## The gate (run in order)

### 1. Node.js >= 18 -- cannot auto-install

Detect: `node --version`.

If missing or below v18: you **cannot** install Node for the user. Tell them to install Node 18+ (`brew install node` on macOS, or https://nodejs.org) and STOP until it is present.

### 2. Supaflow CLI (`@getsupaflow/cli`) -- offer, then confirm, then install

Detect: `supaflow --version` (the SessionStart check reports whether it is missing or below the required minimum -- trust that signal).

If missing or outdated, you **MUST**:
1. Ask the user, in plain words: "The Supaflow CLI is <missing | outdated>. Want me to run `npm install -g @getsupaflow/cli`?"
2. Run that command **only after an explicit yes**. NEVER install or upgrade silently.
3. If the user declines, give them the command to run themselves and STOP.
4. Re-check `supaflow --version` after the install before continuing.

**Restricted-command note:** the slash commands are tool-restricted to `Bash(supaflow *)` and cannot run `npm`. The install offer therefore happens at the session level, before a command runs -- never from inside a command. If the CLI is still missing once inside a command, STOP and surface the fix.

### 3. Authenticated -- the user logs in; no API key in chat

Detect: `supaflow auth status --json`, parse `authenticated`.

If not authenticated, you **MUST**:
1. Ask the user to run `supaflow auth login` **in their own terminal**. The API key must NOT be pasted into chat -- it would persist in the transcript. They get the key from https://app.supa-flow.io > Settings > API Keys.
2. Wait for them to confirm, then re-check `supaflow auth status`.

Never accept, request, or echo an API key in the conversation.

### 4. Workspace selected

Detect: `workspace_id` from `supaflow auth status --json`.

If none: tell the user to run `supaflow workspaces select <name>`, then re-check.

## Resume loop

After any install / login / workspace-select, **re-run the gate from the top** (it is cheap) and only continue to the user's request once all four checks pass. Never assume a fix worked -- verify it.

## Hard stops (non-negotiable)

- Never run `npm install` (or any environment-mutating install/upgrade) without explicit user confirmation.
- Never auto-install Node.
- Never accept or echo an API key in chat -- the user runs `supaflow auth login` themselves.
- Never proceed to the user's request while any of the four checks is failing.
