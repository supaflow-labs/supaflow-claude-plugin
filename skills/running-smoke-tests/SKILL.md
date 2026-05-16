---
name: running-smoke-tests
description: Run the end-to-end Supaflow smoke test suite against local dev -- create pipelines, sync by destination, verify job logs, and compare destination data against source staging files (CSV or JSONL, including `_supa_id` / `_supa_index` passthrough parity)
---

# Running Smoke Tests in Dev

Use this skill when the user asks to run smoke tests, validate a release end-to-end, sync "all pipelines", verify the smoke test matrix, or compare source vs destination data for the smoke pipelines. This skill is workflow-oriented -- follow the steps in order.

**Do not skip validation.** A passing job status is not enough. The release is only green when:
1. All jobs reach `PASS` in `verify_smoke_jobs.py`, AND
2. Destination data matches source -- per-object format picks the validator: `validate_*.py` for CSV; `validate_snowflake_jsonl.py` for JSONL on Snowflake. JSONL on Glue/Postgres has no full-data validator yet -- report that coverage gap, do not count its SKIPs as a pass, AND
3. For every dlt Python source (all are JSONL-certified as of 2026-05-16: Jira, MongoDB, MySQL, Stripe, Shopify, GitHub, GA4), `_supa_id` + `_supa_index` byte-parity is verified via `validate_supa_passthrough.py` (handles CSV and JSONL staging; `--destination` snowflake / glue-iceberg / postgres).

---

## 0. Prerequisites

All smoke test operations run against **local dev** (Next.js app on `localhost:3000` + local agent). Confirm the environment before touching anything.

### Local dev server

```bash
cd supaflow-app && npm run dev
```

### Agent (choose one)

**Local Java agent** (fast iteration, laptop host) -- run from `supaflow-platform/` after `mvn clean install`.

**Docker agent** (required to validate runtime deps like per-connector venvs, Python wheel bundling, memory limits):

```bash
cd supaflow-platform && mvn clean install
cd supaflow-docker/scripts
./build-and-run-agent.sh clean-build
./build-and-run-agent.sh run
./build-and-run-agent.sh status       # verify "Container is running"
./build-and-run-agent.sh logs         # tail to confirm venv build per connector
```

**Always use the Docker agent for the release smoke test** -- it exercises the same runtime path as prod.

### CLI auth for local dev

The `SUPAFLOW_APP_URL` env var must be exported in the shell. Without it every CLI call falls back to production bootstrap.

```bash
export SUPAFLOW_APP_URL=http://localhost:3000
supaflow auth login --key ak_NRS6Y7FHDQAJ27RKNEQBWD660DK007PA
supaflow workspaces select Dev
```

Dev API key: `ak_NRS6Y7FHDQAJ27RKNEQBWD660DK007PA` (from `supaflow-cli/dev.env`, verified working against the Dev workspace `28fbe838-3246-48b7-859a-618aca8b35b5`).

---

## 1. Scripts (all in `supaflow-platform/scripts/smoke/`)

**Run every Python smoke script through `scripts/smoke/run.sh`.** (Shell helpers like `docker_regression_run.sh` are run directly, not wrapped by `run.sh`.) It is a thin dispatcher that fixes the environment once instead of per-invocation: `cd`s to the repo root, selects the repo `python/.venv` (has `duckdb` + `boto3`; fails fast with a `setup-dev-env.sh` hint if absent), sources `export.env` if present, sets `PYTHONPATH=python`, and defaults `SUPAFLOW_APP_URL` to `http://localhost:3000` when unset (a value already exported wins). Then it `exec`s the venv python on the target with all args forwarded.

```bash
cd supaflow-platform
scripts/smoke/run.sh --list                       # list available scripts
scripts/smoke/run.sh verify_smoke_jobs.py <job-id>
scripts/smoke/run.sh validate_snowflake_jsonl.py --job-id <id> --datasource mysql
```

Most direct Python smoke-script invocations (`python3 scripts/smoke/X.py ...` or `PYTHONPATH=python python3 ...`) should be replaced by `scripts/smoke/run.sh X.py ...`; the bare-`python3` forms still work if you set up the env yourself. Keep any caller-shell setup that feeds extra exported variables into the child process, such as the Postgres `DEV_SUPABASE_DB_*` remap in section 6. This wrapper removes the recurring "cd away from `supaflow-platform/` breaks relative paths" and "ran under system python -> `ModuleNotFoundError: duckdb`" failure classes.

| Script | Purpose |
|---|---|
| `run.sh <script[.py]> [args...]` | Generic dispatcher (above). `--list` prints available scripts. Use it for Python smoke scripts below unless a section explicitly requires caller-shell setup before invoking the script. |
| `create_smoke_pipelines.py` | Creates pipelines for every source x destination combo. Idempotent -- skips existing by `api_name`. Uses source label for pipeline prefix to avoid collisions. Has `SKIP_COMBOS` (pg-to-pg excluded) and `DESTINATION_PREFIX_QUALIFIER` (Parquet/Polaris need unique prefixes because they share the same S3 bucket). |
| `sync_smoke_pipelines.py <destination>` | Triggers sync on all smoke pipelines whose api_name ends with `_to_<destination>_smoke_test` (suffix-anchored, so a destination like `postgresql` does NOT pull in source-side `postgresql_to_*` pipelines — that prior substring-match gotcha was fixed in commit eba917b9). Supports `--full-resync`, `--reset-target`, `--poll`. Has a `SKIP_SOURCE_PREFIXES` map for sources that are verifiably broken / quota-exhausted (currently empty as of 2026-05-09; add an entry with a reason and an expected un-skip date when needed). |
| `verify_smoke_jobs.py <job-id>...` | Reads local agent logs. Reports per-job status/counts/deviation/warnings/errors + memory stats. Flags unknown warnings (known ones filtered by `KNOWN_WARNINGS` list). **`source_rows == dest_rows` here is from the loader's own counters** -- it does NOT compare CSV rows vs the actual destination row count. For that, use the per-destination `validate_*.py` scripts below. |
| `validate_snowflake.py --job-id <id>` | DuckDB-based column-level comparison of Snowflake tables vs source CSV. COUNT(*), COUNT(DISTINCT) for text cols, SUM() for numeric cols. Skips `_supa_*` columns. Quote/escape on the snow CLI export was fixed in commit 75ee2ea2 -- previous AUDIT_TRAIL-style false-doubling on tables with multi-line text fields no longer happens. |
| `validate_snowflake_jsonl.py --job-id <id> {--datasource <api>\|--source-catalog <path>}` | JSONL counterpart of `validate_snowflake.py` for pipelines whose `StageFormatDecision` selected JSONL (all dlt Python connectors are JSONL-certified -- confirm per job, do not assume by connector). Compares source JSONL staging vs Snowflake: field-set strict equality, row count, per-column value-frequency multiset, numeric SUM -- typed from the **source** catalog so source->dest type-mapping bugs can't be masked. `--datasource <api_name>` auto-exports + caches the catalog at `scripts/smoke/.smoke-run/catalogs/<api_name>.json` (gitignored), exporting only when absent; `--refresh-catalog` re-fetches the local cache from Supabase (the platform's already-discovered catalog -- it does NOT trigger datasource schema discovery; use it when the smoke flow re-ran discovery and the local cache is now stale); `--source-catalog <path>` is an explicit override. Exactly one of `--datasource`/`--source-catalog` is required. |
| `validate_glue_iceberg.py --job-id <id>` | Same comparison for Glue Iceberg tables via DuckDB's `iceberg` extension. Multi-part staging CSVs are aggregated via UNION ALL (commit 75ee2ea2) so chunked sources count correctly. Requires AWS creds (`source export.env`). |
| `validate_glue_parquet.py --job-id <id>` | Same comparison for Glue Parquet tables. Same multi-part fix as iceberg. Requires AWS creds. |
| `validate_postgres.py --job-id <id>` | DuckDB-based column-level comparison of PostgreSQL destination tables vs source CSV. Uses DuckDB's `postgres` extension to query the destination. Reads `POSTGRES_*` env vars from `export.env` directly (no `DEV_SUPABASE_DB_*` remap). Added in commit 0b4ec70d. |
| `validate_supa_passthrough.py --destination {snowflake\|glue-iceberg\|postgres} --job-id <id>` | Byte-parity check on `_supa_id` + `_supa_index` between the staging file and destination table. Reads **CSV or JSONL** staging (`success_part_*.{csv,jsonl}`, detected per object from disk), joins on `_supa_id`, compares `_supa_index`, validates 1..N contiguity. **Use this for every dlt Python source (Jira, MongoDB, MySQL, Stripe, Shopify, GitHub, GA4) to catch `_supa_*` regressions** -- it is the only `_supa_*` validator that works on JSONL staging for all three destinations. (`glue-parquet` is not covered -- see note at the end of section 6.) For Postgres, this script still reads `DEV_SUPABASE_DB_*` env vars (latent naming bug) -- remap from `POSTGRES_*` in `export.env` before running. |
| `cleanup_postgres_destination.py` | Drops every Postgres-destination schema matching `%smoke_test%` (uses `POSTGRES_*` from `export.env`). Default is dry-run; pass `--apply` to actually drop. Reports DB size before/after. Run as the last step of the postgres-destination smoke flow once both `validate_postgres.py` and `validate_supa_passthrough.py` are green. Pattern is the SQL `LIKE` pattern -- override with `--pattern` if needed. |
| `cleanup_s3_destination.py` | S3 counterpart to the postgres cleanup. Enumerates top-level dirs under `s3://<bucket>/<root_prefix>/` matching `*smoke_test*` (default; pattern overridable) and, with `--apply`, deletes every object beneath them. Captures both `supaflowpy_*` (Iceberg) and `supaflowparquet_*` (Parquet) layouts in one pass without consulting Glue or the CLI. **Mandatory before re-syncing any S3-destination smoke pipeline whose pipeline state was reset** -- the S3 connector's `_enforce_empty_destination_on_first_run` safety check fails loud on a non-empty `<schema>/<table>/` prefix (the gold-standard contract; the smoke harness owns cleanup). Reads `AWS_S3_*` env vars from `export.env`; `AWS_S3_EXTERNAL_ID` is optional. Requires boto3 -- `scripts/smoke/run.sh cleanup_s3_destination.py [...]` covers it (the repo `python/.venv` has boto3 and `run.sh` sources `export.env`), superseding the older S3-connector-venv glob (`data/supaflow-agent/global/connector-envs/.../supaflow-connector-s3-python/.../venv/bin/python3`), which is still a valid fallback if the dev venv is unavailable. |

**`validate_postgres.py` exists** (added 2026-04-27, commit 0b4ec70d). Mirrors the snowflake/iceberg validators: parses the job log for `<schema>.<table>` mappings, reads multi-part staging CSV with RFC-4180 quoting, queries postgres via DuckDB's `postgres` extension, compares row count + per-column COUNT(DISTINCT) + numeric SUM. `validate_supa_passthrough.py --destination postgres` is still the path for `_supa_*` byte-parity (dlt sources). When using passthrough on postgres, remap `POSTGRES_*` env vars to `DEV_SUPABASE_DB_*` first -- latent naming bug in that script.

---

## 2. Create pipelines

```bash
# run.sh defaults SUPAFLOW_APP_URL + sources export.env; auth login (section 0) is the prerequisite.
supaflow-platform/scripts/smoke/run.sh create_smoke_pipelines.py
```

Creates up to ~70 pipelines (14 sources x 5 destinations, minus pg-to-pg). Idempotent. Output summary shows `Created`, `Skipped`, `Failed`. If any fail, stop and show the user the error -- never silently retry or rename.

**Before creating:** if the sources include new connectors (e.g., Jira, Stripe), verify the datasource `api_name` values in the script's `SOURCES` tuple against the actual dev datasources:

```bash
# Bare `supaflow` CLI (not a smoke script) -- export the URL yourself; run.sh does not wrap this.
export SUPAFLOW_APP_URL=http://localhost:3000
supaflow datasources list --limit 200 --json | \
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); [print(x['api_name'], x['name']) for x in d.get('data', [])]"
```

Update `SOURCES` in `create_smoke_pipelines.py` if api_names differ.

---

## 3. Sync by destination

**Run destination-by-destination, not all at once.** Agent concurrency and memory headroom are limited. Between batches, verify and investigate any failures before moving on.

```bash
# run.sh defaults SUPAFLOW_APP_URL + sources export.env; auth login (section 0) is the prerequisite.

# Snowflake (no target reset needed for first run)
supaflow-platform/scripts/smoke/run.sh sync_smoke_pipelines.py snowflake --full-resync

# S3 Data Lake (Glue) -- needs --reset-target to drop stale Iceberg tables from prior runs
supaflow-platform/scripts/smoke/run.sh sync_smoke_pipelines.py s3_data_lake --full-resync --reset-target

# S3 Data Lake Parquet -- same
supaflow-platform/scripts/smoke/run.sh sync_smoke_pipelines.py s3_dl_parquet --full-resync --reset-target

# S3 DL Polaris -- needs --reset-target AND Snowflake Open Catalog setup (credentials + network)
supaflow-platform/scripts/smoke/run.sh sync_smoke_pipelines.py s3_dl_polaris --full-resync --reset-target

# PostgreSQL destination
supaflow-platform/scripts/smoke/run.sh sync_smoke_pipelines.py postgresql --full-resync
```

**Save the printed job IDs.** `verify_smoke_jobs.py` and the validators need them. The sync script writes them to stdout after submitting the batch.

### Destination filter (suffix-anchored as of 2026-04-27)

`sync_smoke_pipelines.py <dest>` matches api_names ending with `_to_<dest>_smoke_test` (commit eba917b9). So `postgresql` cleanly returns only `*_to_postgresql_smoke_test` pipelines and does NOT pull in `postgresql_to_*` source-side pipelines. Earlier sessions had the substring-match version of this filter and accidentally swept up source-side pipelines (e.g. `postgresql_to_s3_dl_polaris_smoke_test`) -- if you see that pattern in old logs, it's pre-fix.

### Known source skips

`SKIP_SOURCE_PREFIXES` in `sync_smoke_pipelines.py` excludes:

- (currently empty as of 2026-05-09 -- airtable was returned to the matrix once its monthly quota reset)
- `sql_server` was previously skipped (Azure SQL test instance dead) but is back live (use `sql_server_qdvbd4` datasource).

Check and update this map before a smoke run if any source is known-broken.

### Docker Jira + Stripe regression helper

`docker_regression_run.sh` is a **narrow** pre-baked helper -- it queues **only Jira + Stripe** against Snowflake, Postgres, and S3 Data Lake (6 jobs) with the right flags (`--full-resync` on SF/PG, `--full-resync --reset-target` on S3 Data Lake), writing the job IDs to `.docker_regression_jobs.txt` (gitignored):

```bash
cd supaflow-platform
./scripts/smoke/docker_regression_run.sh   # shell helper -- run directly, not via run.sh
```

It does **NOT** cover the other JSONL-certified dlt sources (MongoDB, MySQL, Shopify, GitHub, GA4), so it is **not** a full release smoke -- it is only a fast Jira/Stripe regression check. A green release per the criteria at the top of this skill requires the full matrix (sections 2-3) across every dlt Python source; use this helper only for a targeted Jira/Stripe re-run.

### Running a subset of source pipelines for one destination

`sync_smoke_pipelines.py` filters by **destination** only -- no `--sources` flag. When the release scope calls for "just a subset of dlt sources (e.g. Jira + Stripe) against PG and S3 Data Lake" (e.g., re-running after a fix that only affects those), do not try to shoehorn this into the batch script. Invoke `supaflow pipelines sync` one pipeline at a time:

```bash
export SUPAFLOW_APP_URL=http://localhost:3000

# Postgres -- MERGE handles existing tables, but --reset-target IS supported and
# triggers DROP+recreate (DestinationTableHandling=DROP) on the loader side.
# Use --reset-target when validating CREATE-TABLE-path bugs (e.g. column-name
# truncation collisions); use without it when proving MERGE idempotency.
supaflow pipelines sync jira_to_postgresql_smoke_test   --full-resync --json
supaflow pipelines sync stripe_to_postgresql_smoke_test --full-resync --json

# S3 Data Lake -- --reset-target drops stale Iceberg tables before writing
supaflow pipelines sync jira_to_s3_data_lake_smoke_test   --full-resync --reset-target --json
supaflow pipelines sync stripe_to_s3_data_lake_smoke_test --full-resync --reset-target --json
```

**Don't** wrap these in a shell `for` loop with `$flags` containing multiple space-separated args -- zsh/bash will word-split the variable inside the sync command unreliably and the CLI may receive the wrong flags, producing non-JSON output that breaks downstream parsing. Single invocations with the flags written literally on the command line are the safe form.

Capture the printed `job_id` from each response and feed them into `verify_smoke_jobs.py` + the appropriate `validate_*.py` + `validate_supa_passthrough.py` as in sections 4-6.

---

## 4. Verify jobs (log analysis)

Once a batch completes, run the verifier against **all** job IDs from that destination. It parses local agent logs at `data/tenants/c42614a7-a6a8-4b34-a0ea-83efa6c08a30/jobs/<job-id>/logs/job.log`.

```bash
supaflow-platform/scripts/smoke/run.sh verify_smoke_jobs.py <job-id-1> <job-id-2> ...
```

Output:
- Per-job line: status (PASS/WARN/FAIL/NO_LOG/NOT_FINISHED), objects, source_rows, dest_rows, **deviation** (row count mismatch), failed count, warn/err counts
- "Issues (excluding known warnings)" section lists unknown warnings/errors per job
- Memory summary: per-Python-process peak RSS, container peak vs limit

### Known acceptable warnings

These are filtered out by the script's `KNOWN_WARNINGS` list. If you see them in the raw log, they are not release blockers:

- **HubSpot**: "Failed to fetch archived records" (5 objects don't support archived-records paging; active records still sync fine)
- **SFMC**: "SOAP Create failed" (data-extension not-found retries; objects eventually succeed)
- **SQL Server**: "null TABLE_CATALOG" (known JDBC driver behavior, handled by `DB_NAME()` fallback)
- **Airtable**: "rate limit" (expected retries)
- **Oracle TM**: "Failed to convert" (date-to-instant, falls through to name-based heuristic)

### Other known-benign warnings (not in filter list but OK)

- `[_supa_id] No PK or unique fields found for object '...', using ALL N data fields for hash (merge may produce duplicates)` -- expected on flat-file sources (SFTP CSV/JSON/JSONL/XLSX, Google Drive CSV) that have no declared PKs
- `[DEV MODE] Unexpected fields detected for object '<x>' (not in schema): [...]. These fields will be dropped during processing` -- happens on HubSpot `marketing_email` and SFMC `event`. The drop is the intended behavior in dev mode
- `[python] ... WARNING dlt.validate.verify_normalized_table:113 ... In schema 'jira': The following columns in...` -- dlt's own normalize-table validator, two per job for Jira. Benign
- `[python] WARNING connectors.supaflow_connector_sftp.table_mapping: Ignored N file(s) above table folder depth 1 under /home/sftptest/data` -- expected test setup
- **Salesforce**: "OAuth token may expire during job execution. Token remaining life: N minutes, Estimated job duration: M minutes" -- advisory only
- **SFMC**: `[V2] Object <name> routed to sync fallback (async not supported)` -- intentional scope-out from commit `ddb26342` (async JSONL + materialized children fall back to sync ingestion). Working as designed; not a regression
- **`[V2] WritePlanFeatureFlags: ...`** and **`[V2] StageFormatDecision for X: selected=... reason=...`** -- INFO lines (added in `b410d0f6`) that make every job log self-describing for the four-flag matrix and per-object format choice. Not warnings; useful for triage (see section 7's "Common diagnostic pitfalls")

**Anything outside this list is a real issue.** Do not ignore.

### Release criteria for this step

- `FAIL: 0` across the batch (excluding any sources currently in `SKIP_SOURCE_PREFIXES`)
- `deviation: 0` on every passing job (source_rows == dest_rows)
- No unknown ERRORs reported
- Memory headroom > 0 (if container peak == limit, flag it even if jobs pass -- we're one load-spike away from OOM)

---

## 5. Validate data (destination vs source staging)

For each destination, run the corresponding validator for the jobs that passed verification. These compare actual destination data against the source staging files (CSV or JSONL) using DuckDB aggregates.

All validators expect to be run **from `supaflow-platform/`** (their relative paths like `scripts/smoke/` and `data/tenants/` resolve from there).

> **JSONL pipelines (`StageFormatDecision ... selected=JSONL`).** Whether a pipeline stages `.jsonl` or `.csv` is a per-job runtime decision, NOT a fixed connector property -- **do not rely on a static connector list** (this guidance has drifted before). As of 2026-05-16 every dlt Python connector is `use_full_normalize=True` + `jsonl_certified=True` (Jira, MongoDB, MySQL, Stripe, Shopify, GitHub, GA4), so with the cert flag on in local dev they select JSONL; only legacy/Java-runtime connectors stay CSV. Decide per job from the log, not from memory:
> ```bash
> grep '\[V2\] StageFormatDecision' data/tenants/c42614a7-.../jobs/<job-id>/logs/job.log | head
> ```
> - `selected=JSONL` + **Snowflake** destination: use `validate_snowflake_jsonl.py` (`--datasource <api>` auto-exports the source catalog) -- full source-vs-destination comparison.
> - `selected=JSONL` + **Glue or Postgres** destination: no **full-data** validator yet -- `validate_glue_*.py` / `validate_postgres.py` are CSV-only and report `SKIP (no source CSV)`, and the section-5b SQL is Snowflake-only. **But `validate_supa_passthrough.py` still applies** -- it reads `.jsonl` staging and supports `--destination glue-iceberg` / `postgres`, so run it for `_supa_id` / `_supa_index` parity. Treat only the missing full-data comparison as a **coverage gap: report it**, and do not count the full-data-validator SKIPs as a pass.
> - `selected=CSV`: use the CSV validators normally.

```bash
cd supaflow-platform

# Snowflake -- CSV pipelines
scripts/smoke/run.sh validate_snowflake.py --job-id <job-id>
scripts/smoke/run.sh validate_snowflake.py --job-id <job-id> --objects Customer Event  # subset

# Snowflake -- JSONL pipelines (any source whose StageFormatDecision=JSONL)
scripts/smoke/run.sh validate_snowflake_jsonl.py --job-id <job-id> --datasource <api_name>

# Glue Iceberg / Parquet (run.sh sources export.env + sets PYTHONPATH)
scripts/smoke/run.sh validate_glue_iceberg.py --job-id <job-id>
scripts/smoke/run.sh validate_glue_parquet.py --job-id <job-id>
```

Output:
- Per object: PASS | FAIL | SKIP | ERROR, csv_rows vs dest_rows, number of compared columns, elapsed time
- On FAIL: up to 5 mismatches printed (which column, which aggregate, source vs destination value)

### Known asymmetries (NOT validator bugs)

- **Snowflake empty-string -> NULL**: Snowflake's default CSV file format uses `EMPTY_FIELD_AS_NULL=TRUE`, so empty CSV fields get coerced to NULL on `COPY INTO`. The validator surfaces this as a `COUNT(DISTINCT)` diff of 1 when a STRING column has a genuine empty string. See `TODO.md` P0-59 for the fix plan. Do not silently suppress.
- **Glue column name truncation**: 128-char Glue column name limit triggers WARN; content is truncated as expected.
- **HubSpot property_history.value off-by-1 distinct count**: type-coercion artifact, known.

---

## 5b. Direct-Snowflake sanity SQL for JSONL pipelines

For Snowflake JSONL pipelines `validate_snowflake_jsonl.py` (section 5) is the primary validator; this direct sanity query is a deeper byte-structure cross-check on top of it. **It queries Snowflake tables only (`SUPA_DB.<schema>.<table>`) -- it cannot validate a Glue or Postgres destination.** JSONL pipelines on Glue/Postgres have no destination validator today; report that coverage gap rather than substituting this SQL. For any Snowflake pipeline whose `[V2] StageFormatDecision` was `selected=JSONL`, it checks four invariants per object:

1. `COUNT(*)` matches the expected source row count.
2. `COUNT(DISTINCT _supa_id) == COUNT(*)` (no collisions, no nulls).
3. `MIN/MAX(LENGTH(_supa_id)) == 64` (every hash is the full SHA-256 hex; no truncation, no malformed entries).
4. `MIN(_supa_index) == 1` and `MAX(_supa_index) == COUNT(*)` (Workstream C contiguity contract).

Template -- one `UNION ALL` row per table; reserved keyword `ROWS` aliased to `ROW_COUNT`:

```bash
snow sql --connection dev -q "
SELECT 'users' AS t, COUNT(*) AS row_count, COUNT(DISTINCT _supa_id) AS uniq, MIN(LENGTH(_supa_id)) AS min_len, MAX(LENGTH(_supa_id)) AS max_len, MIN(_supa_index) AS min_idx, MAX(_supa_index) AS max_idx FROM SUPA_DB.JIRA_SMOKE_TEST.USERS
UNION ALL SELECT 'issues', COUNT(*), COUNT(DISTINCT _supa_id), MIN(LENGTH(_supa_id)), MAX(LENGTH(_supa_id)), MIN(_supa_index), MAX(_supa_index) FROM SUPA_DB.JIRA_SMOKE_TEST.ISSUES
-- ... one row per object ...
ORDER BY t;
"
```

Cross-check the `users` row against the Phase 4 Task 12 gold reference recorded in `memory/project_mapped_record_write_plan.md` (19 rows, 19 unique `_supa_id`, all 64-char hex, contiguous 1..19). If `users` matches, the spool + JSONL emitter + Snowflake JSON COPY chain has produced the same byte structure as the proven A/B run.

Whichever path you use (`validate_snowflake_jsonl.py` or this SQL), do NOT mark a JSONL run "validated" on the strength of `verify_smoke_jobs.py` alone -- that script reads loader counters, not destination state.

---

## 6. Validate `_supa_id` / `_supa_index` passthrough (dlt sources only)

Every dlt Python source emits source-owned `_supa_id` and `_supa_index` values (as of 2026-05-16: Jira, MongoDB, MySQL, Stripe, Shopify, GitHub, GA4 -- all JSONL-certified). These MUST be preserved byte-for-byte through the staging file (CSV or JSONL) -> destination table. `validate_supa_passthrough.py` detects the staging format per object, so it applies regardless of `StageFormatDecision`. Run:

```bash
# run.sh sources export.env + selects the venv. Snowflake also needs snow CLI config.
supaflow-platform/scripts/smoke/run.sh validate_supa_passthrough.py --destination snowflake --job-id <id>

# Glue Iceberg -- pass the S3 prefix literally (it lives in export.env as AWS_S3_PREFIX_PATH;
# the arg is expanded by YOUR shell before run.sh runs, so don't rely on $AWS_S3_PREFIX_PATH here).
supaflow-platform/scripts/smoke/run.sh validate_supa_passthrough.py --destination glue-iceberg \
    --job-id <id> --s3-prefix-path <s3-prefix-path>

# PostgreSQL destination -- requires a remap step, see below
```

**Postgres credential remap (GOTCHA):** the validator reads `DEV_SUPABASE_DB_{HOST,PORT,USER,PASSWORD,NAME}`, which by name looks like it should come from `supaflow-sql-scripts/.../schema-deploy/.env`. It does NOT -- those vars point at the **control-plane** Supabase (platform metadata), not the actual Postgres **destination** warehouse. The destination credentials live in `supaflow-platform/export.env` under `POSTGRES_*`. You have to remap before running the validator:

```bash
cd supaflow-platform
# The remap must be exported in YOUR shell -- run.sh re-sources export.env (which does
# not define DEV_SUPABASE_DB_*), so these inherited exports survive into the child.
source export.env
export DEV_SUPABASE_DB_HOST="$POSTGRES_HOST"
export DEV_SUPABASE_DB_PORT="$POSTGRES_PORT"
export DEV_SUPABASE_DB_USER="$POSTGRES_USER"
export DEV_SUPABASE_DB_PASSWORD="$POSTGRES_PASSWORD"
export DEV_SUPABASE_DB_NAME="$POSTGRES_DATABASE"
scripts/smoke/run.sh validate_supa_passthrough.py --destination postgres --job-id <id>
```

If the destination read fails with `relation "<pipeline_prefix>.<table>" does not exist`, you are almost certainly pointed at the control-plane Supabase instead of the PG destination -- re-export from `POSTGRES_*` and retry. The `validate_supa_passthrough.py` envvar naming is a latent bug; when fixed the remap step goes away.

**`.env` files without `export` prefixes:** `schema-deploy/.env` sets vars as plain `KEY=VALUE` lines, so `source .env` puts them in the shell but does NOT export them to child processes. Python subprocesses see nothing. Use one of:

```bash
# Option A: auto-export around the source
set -a && source supaflow-sql-scripts/src/tools/schema-deploy/.env && set +a

# Option B: explicit export of the specific vars needed
source supaflow-sql-scripts/src/tools/schema-deploy/.env
export DEV_SUPABASE_DB_HOST DEV_SUPABASE_DB_PORT DEV_SUPABASE_DB_USER DEV_SUPABASE_DB_PASSWORD DEV_SUPABASE_DB_NAME
```

`export.env` already uses `export KEY=VALUE` and works directly with `source`.

Per object, the validator asserts:

1. `set(_supa_id in CSV) == set(_supa_id in destination)` -- no overwrites, no drops, no extras
2. For every common `_supa_id`, the mapped `_supa_index` is byte-identical
3. CSV `_supa_index` forms a contiguous `1..N` sequence (Workstream C contract)

**A passing data validator with a failing supa-passthrough validator means: row count and values are right, but `_supa_id` got rewritten somewhere.** That is exactly the signal you want on the dlt integration path.

Glue Parquet destination is not yet covered by this script (add the reader if needed; the pattern mirrors `read_supa_cols_from_glue_iceberg`).

---

## 6b. Reclaim Postgres destination space (postgres-destination runs only)

The Postgres-destination smoke flow writes per-source schemas (`oracle_tm_smoke_test`, `salesforce_smoke_test`, `airtable_smoke_test_<base>`, etc.) into the warehouse pointed at by `POSTGRES_*` in `export.env`. None of the validators clean these up, so the database accumulates ~880 MB per matrix run and eventually trips the Supabase free-tier 500 MB cap (real incident on STAGE 2026-05-04).

Once steps 5 (and 6 if dlt sources are in scope) are green for the entire postgres batch, run:

```bash
# run.sh sources export.env (POSTGRES_*) + selects the venv.
supaflow-platform/scripts/smoke/run.sh cleanup_postgres_destination.py            # dry-run: lists matching schemas
supaflow-platform/scripts/smoke/run.sh cleanup_postgres_destination.py --apply    # drops every schema matching '%smoke_test%'
```

The script:
- Reads `POSTGRES_HOST/PORT/USER/PASSWORD/DATABASE` (same env as `validate_postgres.py`)
- Lists every schema where `schema_name LIKE '%smoke_test%'` (covers `<source>_smoke_test`, `airtable_smoke_test_<base>` with spaces/`&`, `sqlserver_smoke_test_supa_dbo`, etc.)
- Shows DB size before/after on `--apply`
- Defaults to dry-run for safety; pass `--pattern '<like>'` to override

**Order matters.** Run cleanup *after* `validate_supa_passthrough.py` for any dlt-source pg jobs in the batch -- passthrough validation reads the destination tables. If validation fails, leave schemas in place for diagnosis and re-run cleanup once the issue is resolved.

---

## 6c. Wipe S3 destination prefixes (S3-destination resets only)

The S3 connector's first-run safety check (`_enforce_empty_destination_on_first_run` in Python `connector.py`; mirrored in Java `S3Connector.enforceEmptyDestinationOnFirstRun`) refuses to write when `<schema>/<table>/` already contains data. This is the **gold-standard contract** -- two pipelines accidentally pointing at the same prefix would silently orphan each other's data without it. **Don't try to bypass it from the connector with versioned paths or any other hack** (we tried that 2026-05-08 with a `v_<ts>_<jdid>` segment and reverted; the smoke harness owns cleanup).

When a smoke flow recreates a pipeline under a deterministic prefix (every smoke pipeline does), the previous run's files are still in S3, so the next first-run sync fails the empty-prefix check. The smoke harness handles this with `cleanup_s3_destination.py`:

```bash
# run.sh sources export.env (AWS_S3_*) and uses python/.venv (has boto3).

# Dry-run -- list which top-level prefixes match `*smoke_test*` and total size
supaflow-platform/scripts/smoke/run.sh cleanup_s3_destination.py

# Wipe them
supaflow-platform/scripts/smoke/run.sh cleanup_s3_destination.py --apply -y

# Scope to one pipeline / one pattern (e.g. just the parquet variants)
supaflow-platform/scripts/smoke/run.sh cleanup_s3_destination.py \
    --pattern '*parquet_smoke_test*' --apply -y
```

(The older S3-connector-venv glob -- `data/supaflow-agent/global/connector-envs/.../supaflow-connector-s3-python/.../venv/bin/python3` -- is a valid fallback only if `python/.venv` is unavailable.)

The script:
- Enumerates `s3://<bucket>/<root_prefix>/*` via `ListObjectsV2(Delimiter='/')` and filters dir names against `--pattern`. Captures both `supaflowpy_*` (Iceberg) and `supaflowparquet_*` (Parquet) layouts in one pass without consulting Glue or the CLI.
- Reads `AWS_S3_BUCKET / AWS_S3_PREFIX_PATH / AWS_S3_REGION / AWS_S3_ROLE_ARN` from env (`source export.env`); `AWS_S3_EXTERNAL_ID` is optional.
- Default dry-run; `--apply` deletes; `-y` skips the confirmation prompt.

**When to run it:** any time a smoke flow involves `--reset-target` + an S3 destination + a recreated pipeline (which is essentially every smoke iteration). Verified end-to-end 2026-05-09: wiping 11942 objects across 68 prefixes (1.3 GB), then 16 sources × 3 destinations (Snowflake / Glue Iceberg / Parquet) all re-synced PASS deviation=0 against the restored gold-standard check.

**Order matters.** Run cleanup *after* validators on the prior batch (validators read S3 data); leave the prefix in place if validation failed and re-run cleanup once the issue is resolved.

---

## 7. Known-broken / in-flight issues

Watch for these; do not treat them as "unknown" failures:

| Issue | Scope | Tracked |
|---|---|---|
| Migration 065 strips `_supa_*` on new-field discovery for `BLOCK_ALL` pipelines | S3 Data Lake / Parquet / Polaris pipelines created before catalog v3 | `TODO.md` P1-11L |
| `validate_glue_iceberg.py` flags numeric columns as FAIL when CSV text representation has more distinct strings than the numeric column's distinct values (e.g. `"1.0"` vs `"1.00"` collapse to one number) | Any numeric column on Iceberg side | Validator-only false-FAIL; classify by destination type, not source CSV pg-type header |
| Soft-deleted pipeline rows leave orphaned `pipeline_metadata_mappings` | DB queries | Filter by `state='active'` when counting/comparing |
| Docker agent memory at 100% ceiling on 4GB limit when running wide Python batches | Docker only | Monitor; file if OOMs occur |
| `lib_clone.sh` cache appears wiped between docker container restarts (every restart rebuilds all venvs, "0 cached, N new") | Docker agent | Debug log added in commit 0fb1700b; root cause TBD |

### Common diagnostic pitfalls (lessons from prior runs)

- **`wc -l` is NOT a CSV row count.** Staging CSVs with multi-line text fields (HTML email bodies, JSON, audit-trail descriptions) have many file lines per logical row. Use Python's `csv.reader` or DuckDB's `read_csv` with explicit `quote='"', escape='"'` for an RFC-4180-aware count. Mistaking file lines for row count caused a false "release blocker" alarm on 2026-04-27 (claimed Postgres COPY truncation when COPY was actually loading every row correctly).
- **The verifier's `deviation=0` is loader-internal.** It compares the loader's own "rows read" vs "rows written" counters -- it does NOT see the staging CSV row count vs the actual destination COUNT(*). Use the per-destination `validate_*.py` scripts to catch CSV-vs-destination divergence (e.g. dedup-via-MERGE losing rows, COPY parsing failing silently).
- **`--reset-target` to test CREATE-path fixes.** Some bugs only trigger when the loader runs CREATE TABLE / DDL paths -- subsequent runs into existing tables work fine. The HubSpot 63-char column-collision bug was one of these: the failing tables already existed in Postgres from prior runs, so the second run's MERGE-into-existing path masked the bug. When validating any schema/DDL fix, run with `--full-resync --reset-target` to force the CREATE path.
- **For docker-vs-local divergence, diff the agent log lines.** The successful run on the local Java agent vs the failed run on docker will surface the missing code path. Example: `[managed-oauth] refreshed OAuth access token via TokenRefreshService` appearing only on local explained why GA4 was failing on docker -- the docker image's agent fat-JAR predated the managed-OAuth feature.
- **`[V2] StageFormatDecision` is the JSONL-vs-CSV triage signal.** When a dlt source's destination outcome surprises you (e.g. CSV-side `EMPTY_FIELD_AS_NULL` distinct-count diffs, or a CSV validator reporting `SKIP (no source CSV)`), grep the job log for the per-object decision:
  ```bash
  grep '\[V2\] StageFormatDecision' data/tenants/c42614a7-.../jobs/<job-id>/logs/job.log | head
  ```
  `selected=JSONL` -> validate via section 5 / 5b (Snowflake) or report the Glue/Postgres gap. `selected=CSV reason=LEGACY_CSV_RUNTIME_NOT_PYTHON` -> this pipeline ran the legacy CSV (Java-runtime) path, so the CSV validators apply. As of 2026-05-16 every dlt Python connector is `use_full_normalize=True` + `jsonl_certified=True`, so for them the format is decided by the four-flag / cert rollout state in the environment, not by a static connector list -- always read the actual `StageFormatDecision` line, do not infer from the connector name.
- **Do NOT pipe per-job validator runs through `tail -N` in batch loops.** A loop like `for jid in $jobs; do supaflow-platform/scripts/smoke/run.sh validate_snowflake.py --job-id "$jid" | tail -8; done` clips the per-object FAIL/SKIP rows -- you only see the trailing summary line. Either tee the full output to a per-destination log (`... | tee scripts/smoke/.last_<dest>_validate.log`) and grep details from there, or skip the tail and accept the larger output.
- **`cd` away from `supaflow-platform/` will silently break the next validator call.** The smoke scripts use relative paths (`scripts/smoke/...`, `data/tenants/...`) that resolve from `supaflow-platform/`. After running anything in `supaflow-docker/scripts/` or `supaflow-app/`, either `cd /Users/puneetgupta/supaflow-workspace/supaflow-platform` back, or use absolute paths in subsequent commands. Symptom: `No such file or directory` on a script that was working five minutes ago.

---

## 8. Hard rules

1. **Read memory first.** `memory/project_smoke_testing.md` has the per-session status, fix log, and connector-specific quirks. Re-read before reporting anything.
2. **Docker agent for release runs.** Local Java agent is fine for iterating on individual connectors, but release smoke must use Docker to exercise the real runtime path.
3. **One destination at a time.** Do not kick off multiple destination batches in parallel -- agent semaphore is bounded and memory is tight.
4. **Save job IDs before moving on.** Write them to `scripts/smoke/.last_<destination>_jobs.txt` (convention) so `verify_smoke_jobs.py` and the validators can be re-run without re-syncing.
5. **Never declare green until step 5 (data validation) passes.** Step 4 (log verify) is necessary but not sufficient.
6. **For dlt sources, add step 6 (`_supa_id`/`_supa_index` parity).** A data-only check would miss loader-side overwrites of these system columns.
7. **Show errors verbatim.** If a create/sync/validate command fails, show the full error and ask the user what to do. Never silently rename, retry, or auto-recover.
8. **Don't add defaults for decisions.** Object scope (all vs subset), destination selection, and `--reset-target` behavior are required user choices -- ask, don't assume.
9. **Always run `cleanup_postgres_destination.py --apply` after a green postgres-destination batch.** Smoke schemas accumulate at ~880 MB per matrix run and will trip Supabase free-tier limits within a few cycles. Skip cleanup only if validation failed and you need the destination state for diagnosis -- in which case re-run cleanup once the issue is resolved.
10. **Always run `cleanup_s3_destination.py --apply -y` before re-syncing S3 destinations on a recreated pipeline.** The connector's `_enforce_empty_destination_on_first_run` check is gold standard and intentionally fails loud on a non-empty prefix; the smoke harness owns cleanup. Skip cleanup only if you've left destination state in place on purpose for diagnosis -- in which case re-run cleanup once the issue is resolved. Do NOT propose changing the connector to bypass the check (we tried; reverted).

---

## 9. Reporting format

When reporting smoke test results to the user, use this layout:

```
Batch: <destination>
Jobs submitted: N
Jobs passed:    M (log verify)
Data validated: K (destination vs source staging; note JSONL-on-Glue/Postgres full-data gap)
Supa parity:    P (dlt sources only)

Failures:
  <job-id> <pipeline-name>: <error summary>

Memory:
  Container peak: XMB / YMB (Z%)
  Highest per-process Python RSS: XMB

Unknown warnings/errors:
  <brief per-job summary>
```

Keep the summary under ~15 lines. Dump the raw verifier output only if the user asks for it.
