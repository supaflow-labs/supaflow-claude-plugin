---
description: Get started with the hosted Supaflow connection and workspace
argument-hint: "[workspace-name]"
---

# setup

Invoke the bundled `supaflow:supaflow-setup` skill through the host's skill invocation tool to verify the account, resolve a workspace, and inspect available connections. The [hosted onboarding instructions](../skills/supaflow-setup/SKILL.md) belong to that packaged skill, not a `.claude/skills` folder in the user's working directory. Setup is read-only; it does not authorize resource changes or pipeline execution. Use only the actual hosted Supaflow tools, never a shell or local-agent fallback.
