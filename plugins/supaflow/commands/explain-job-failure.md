---
description: Diagnose a failed Supaflow job through hosted MCP
argument-hint: "[job-id]"
---

# explain-job-failure

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-jobs](../skills/supaflow-jobs/SKILL.md).

Read `jobs_get` and `jobs_logs` for the same job. Explain the returned root-cause message and failed object/stage without exposing secrets or inventing missing log details. Suggest a next action; do not automatically retry, reset, refresh, or change configuration.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
