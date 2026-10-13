# Regression Index

Known failure modes from real sessions, tied to the tests that now cover them.

## Parser/Field Regressions

| Failure | Session | Test |
|---|---|---|
| pipelines list used flat source/destination fields | Early plugin sessions | medium/test-parsers.sh: pipelines list contract |
| pipelines schema list treated import-ready CLI mappings as a display-row envelope | Legacy fixture drift | medium/test-parsers.sh: raw array with fully_qualified_name/selected/fields |
| jobs status invented phase, duration, completed_at, progress fields | Early plugin sessions | medium/test-parsers.sh: jobs status contract |
| jobs get used duration instead of execution_duration_ms | Early plugin sessions | medium/test-parsers.sh: jobs get contract |
| projects matched by warehouse_name instead of warehouse_datasource_id | Early plugin sessions | medium/test-command-guardrails.sh: create-pipeline uses warehouse_datasource_id |

## Workflow Regressions

| Failure | Session | Test |
|---|---|---|
| Skipped datasources list and asked for credentials immediately | Early plugin sessions | medium/test-command-guardrails.sh: create-datasource mentions datasources list |
| Guessed pipeline defaults without running pipelines init | Early plugin sessions | medium/test-command-guardrails.sh: create-pipeline mentions pipelines init |
| Silently renamed pipeline after duplicate constraint | Early plugin sessions | medium/test-command-guardrails.sh: create-pipeline has duplicate stop language |
| Blindly retried failed job with "transient issue" explanation | Early plugin sessions | medium/test-command-guardrails.sh: explain-job-failure has no blind retry language |
| Treated partial edit as blanket approval | Early plugin sessions | plugins/supaflow-code/commands/create-pipeline.md and hosted-workflows.mjs: final configuration approval |
| Defaulted to all objects without asking | Session 6c4fbb21 | medium/test-command-guardrails.sh: create-pipeline contains Object Scope |
| Used nonexistent `jobs run` command for sync | Session 6c4fbb21 | medium/test-command-guardrails.sh: sync-pipeline contains pipelines sync |

## Package and hosted MCP boundaries

| Failure | Test |
| --- | --- |
| Submitted the repository root instead of one installable edition | fast/package-boundaries.mjs: catalog root and contained package sources |
| Shipped a local executable, hook, or CLI command in the hosted edition | fast/package-boundaries.mjs: exact HTTP config and runtime leakage checks |
| Assumed the hosted connection selected the local CLI workspace/account | fast/test-mcp-skill-gate.sh and medium/hosted-workflows.mjs: separate identity/workspace gates |
| Used CLI nested fields or job_status in hosted results | medium/hosted-workflows.mjs: hosted wrapper/camel-case fixture contracts |
| Stopped selected-object pagination on a short/empty page | medium/hosted-workflows.mjs: sparse middle page with has_more true |
| Invented saved pipeline configuration or zero rows from missing metrics | medium/hosted-workflows.mjs: metadata-only config and null metric response rules |
| Repeated a timed-out mutation using another execution surface | Code entry and hosted safety tests: reconcile before retry |
| Kept polling a skipped job as if it were still running | medium/hosted-workflows.mjs: exact terminal-state set and skipped status/details fixtures |
| Passed a schedule/old execution ID to job tools after a schedule trigger | medium/hosted-workflows.mjs: trigger-without-job-ID, baseline/history correlation, and unresolved/concurrent execution guards |

Fixtures are synthetic examples. These tests check package contents, instruction invariants, and documented contracts; they do not execute a language model or prove a live replication run.
