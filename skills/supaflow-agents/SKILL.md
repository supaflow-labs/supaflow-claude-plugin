---
name: supaflow-agents
description: Manage a local Docker Supaflow agent from the CLI/MCP -- start (enroll or resume), upgrade, stop, status, logs, remove. Use when the user wants to run pipelines on their own machine or network via a private agent, deploy/install or upgrade a local agent, check why their agent is offline, or re-enroll after revoking an agent.
---

# Supaflow Local Docker Agents

A private agent runs the user's pipelines inside their own network; only encrypted metadata reaches Supaflow Cloud. The `supaflow agent` command family manages a local Docker agent end to end. MCP tools: `agent_start`, `agent_upgrade`, `agent_stop`, `agent_status`, `agent_logs`, `agent_remove`.

## Availability gate (run FIRST, per execution surface)

The plugin requires CLI 0.5.0+ for all agent lifecycle operations. The agent-upgrade flow must still be checked by capability so a stale MCP server cannot be mistaken for the current one. The check depends on the active Supaflow surface (see the setup gate):

- **MCP path active** (`mcp__supaflow__*` tools present): require the exact tool for the requested operation. In particular, do not attempt an upgrade unless `mcp__supaflow__agent_upgrade` is present. An already-running MCP server can predate newly installed agent tools. If the required tool is absent: tell the user to upgrade the host CLI (`npm install -g @getsupaflow/cli`) and restart the MCP client/session so the server reloads, then STOP.
- **Terminal CLI path** (no MCP tools): the setup gate establishes CLI 0.5.0+. Before an upgrade, also run `supaflow agent upgrade --help`; if the capability check fails, tell the user to upgrade the CLI and STOP.

Never improvise raw docker commands as a fallback on either surface; the deployment wizard on Settings > Agents is the supported alternative.

## Hard rules

1. **Approval changes tenant job routing.** Once a private agent is approved, the tenant's jobs run on it. NEVER pass `approve=true` (or run `agent start --approve`) unless the user explicitly asked to approve/activate the agent. Default to leaving it pending and telling the user to approve on Settings > Agents (or to rerun with `--approve`).
2. **`remove --purge` is destructive and identity-losing.** It deletes the identity volume; the next start enrolls a brand-new agent that needs re-approval, and the old agent record must be deactivated on Settings > Agents. Confirm with the user before purging.
3. **A kept identity volume outranks a new registration token** (deliberate: restart policies re-run containers with a spent token in their env). To re-enroll after revoking an agent, `agent remove --purge` FIRST -- do not mint tokens hoping they win.
4. **Enrollment requires an org:admin API key.** If `agent_start` fails with an admin error, tell the user to use an API key created by an org admin; do not retry with workarounds.
5. **An upgrade stops and replaces the current container.** Read `agent_status` first, show the resolved container name and requested image, explain the brief interruption, and get explicit user confirmation before `agent_upgrade` or `supaflow agent upgrade`. MCP approval is not the workflow confirmation. Never use `pull=false` / `--no-pull` unless the user explicitly wants an image already present on the host.

## What `agent start` does

Doctor preflight (docker binary, daemon, ~5 GB free disk, image, container/volume state), then automatically:

- **Nothing exists** -> enroll: mints a single-use registration token, runs the agent container with a persistent identity volume, waits for registration (~1 minute; first start generates encryption keys locally).
- **Container stopped** -> `docker start`; the agent reconnects in seconds, no token, no re-approval.
- **Container gone, identity volume present** -> recreates the container and resumes the SAME agent.
- Corrupt identity in the volume -> fails with recovery guidance (`remove --purge`); it never silently re-enrolls.

Useful flags: `--name <container>` (parallel agents; volume is `<name>-data`), `--image <ref>`, `--api-url <url>` (local dev app), `--timeout <seconds>`.

If an existing container uses a different image than `agent start` requested, `start` refuses to replace it. Use the upgrade workflow instead.

## What `agent upgrade` does (CLI 0.5.0+)

Use `agent_upgrade` on MCP or `supaflow agent upgrade` in the terminal. It:

- Requires the existing container and its named identity/keystore volume.
- Preserves the container's `SUPAFLOW_API_URL`; for a legacy container without that value, pass `api_url` / `--api-url` explicitly.
- Pulls the requested image and validates the persisted identity before stopping the current container.
- Starts the replacement and checks its Docker startup state. If replacement startup fails, it removes the failed container and attempts to restore the previous immutable image while keeping the identity volume intact.

Useful flags: `--name <container>`, `--image <ref>`, `--api-url <url>`, `--no-pull` (only for an image already present locally). After the operation, re-read `agent_status` and report the verified container and agent state.

## Diagnosing

- `agent status` joins docker state with the server record: `lifecycle_status` (registered / pending_approval / approved / active / suspended / terminated / deactivated), `connectivity_status`, `last_heartbeat_at`.
- Container running but lifecycle `registered` -> it is waiting for approval, not broken.
- `agent logs --tail 200` for boot/registration errors; a 403 "not active (status: deactivated)" means the agent was deactivated server-side -- re-enroll with `remove --purge` + `start`.

## JSON mode

Nothing prompts under `--json`: `start` leaves the agent pending unless `--approve` was passed, and `remove` requires `--yes`.
