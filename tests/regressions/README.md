# Regression Index

Known failure modes from real sessions, tied to the tests that now cover them.

## Parser/Field Regressions

| Failure | Session | Test |
|---|---|---|
| pipelines list used flat source/destination fields | Early plugin sessions | medium/test-parsers.sh: pipelines list contract |
| pipelines schema list used fully_qualified_name instead of object | Early plugin sessions | medium/test-parsers.sh: pipelines schema list contract |
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
| Treated partial edit as blanket approval | Early plugin sessions | commands/create-pipeline.md: explicit confirmation guardrail |
