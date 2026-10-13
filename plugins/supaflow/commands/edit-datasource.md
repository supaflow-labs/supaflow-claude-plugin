---
description: Edit a datasource through hosted Supaflow MCP
argument-hint: "[datasource]"
---

# edit-datasource

This is a hosted-MCP workflow, not a local command. Follow [the connection and workspace gate](../skills/using-supaflow/SKILL.md) and [safety rules](../skills/using-supaflow/safety.md), then read [supaflow-datasources](../skills/supaflow-datasources/SKILL.md).

Read the exact datasource, review only the requested safe configuration changes, apply `datasources_edit` within that authorization, and verify state and any test job. Credential changes without a supported encrypted flow must be completed in the Supaflow dashboard.

Use only the actual Supaflow connector tools, passing the resolved `workspace_id` on every scoped call. If the connection or required capability is unavailable, stop and guide the user to the connector UI or Supaflow dashboard. Do not use a shell or local-agent fallback.
