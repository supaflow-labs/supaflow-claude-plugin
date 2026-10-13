---
description: Edit a pipeline or its selected objects through hosted MCP
argument-hint: "[pipeline]"
---

# edit-pipeline

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-pipelines](../skills/supaflow-pipelines/SKILL.md).

Read the exact pipeline and current selected objects/fields. Review the proposed patch, change only the authorized fields or selections, and reread state and complete object pages. Do not substitute new-pipeline defaults for unavailable saved configuration.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
