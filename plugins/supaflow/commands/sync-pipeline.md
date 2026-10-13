---
description: Run one normal Supaflow sync and monitor it through hosted MCP
argument-hint: "[pipeline]"
---

# sync-pipeline

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-pipelines](../skills/supaflow-pipelines/SKILL.md).

Resolve the exact pipeline and workspace. For a clear normal-sync request, call `pipelines_sync` once with `full_resync: false` and `reset_target: false`, capture `job_id`, and follow the jobs skill to poll `jobs_status` until terminal, then retrieve `jobs_get` and `jobs_logs`. Reconcile an ambiguous response before any retry. Full resync or target reset requires explicit confirmation immediately before the call.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
