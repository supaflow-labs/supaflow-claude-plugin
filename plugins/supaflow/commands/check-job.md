---
description: Inspect a Supaflow job through hosted MCP
argument-hint: "[job-id-or-pipeline]"
---

# check-job

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-jobs](../skills/supaflow-jobs/SKILL.md).

Resolve the exact job or latest job for the requested pipeline. Use `jobs_status` for current status, and `jobs_get` plus `jobs_logs` for terminal detail. Report only returned fields and metrics; do not run a pipeline or count historical jobs as separate pipelines.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
