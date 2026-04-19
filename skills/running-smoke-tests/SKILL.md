---
name: running-smoke-tests
description: Run the end-to-end Supaflow smoke test suite against local dev -- create pipelines, sync by destination, verify job logs, and compare destination data against source staging CSVs (including `_supa_id` / `_supa_index` passthrough parity)
---

# Running Smoke Tests in Dev

Use this skill when the user asks to run smoke tests, validate a release end-to-end, sync "all pipelines", verify the smoke test matrix, or compare source vs destination data for the smoke pipelines. This skill is workflow-oriented -- follow the steps in order.

**Do not skip validation.** A passing job status is not enough. The release is only green when:
1. All jobs reach `PASS` in `verify_smoke_jobs.py`, AND
2. Destination data matches source CSV (row counts + column aggregates) via the per-destination `validate_*.py` script, AND
3. For dlt-based sources (Jira, Stripe), `_supa_id` + `_supa_index` byte-parity is verified via `validate_supa_passthrough.py`.

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

| Script | Purpose |
|---|---|
| `create_smoke_pipelines.py` | Creates pipelines for every source x destination combo. Idempotent -- skips existing by `api_name`. Uses source label for pipeline prefix to avoid collisions. Has `SKIP_COMBOS` (pg-to-pg excluded) and `DESTINATION_PREFIX_QUALIFIER` (Parquet/Polaris need unique prefixes because they share the same S3 bucket). |
| `sync_smoke_pipelines.py <destination>` | Triggers sync on all smoke pipelines matching the destination substring. Supports `--full-resync`, `--reset-target`, `--poll`. Has a `SKIP_SOURCE_PREFIXES` map for dead/rate-limited sources (Airtable, SQL Server). |
| `verify_smoke_jobs.py <job-id>...` | Reads local agent logs. Reports per-job status/counts/deviation/warnings/errors + memory stats. Flags unknown warnings (known ones filtered by `KNOWN_WARNINGS` list). |
| `validate_snowflake.py --job-id <id>` | DuckDB-based column-level comparison of Snowflake tables vs source CSV. COUNT(*), COUNT(DISTINCT) for text cols, SUM() for numeric cols. Skips `_supa_*` columns. |
| `validate_glue_iceberg.py --job-id <id>` | Same comparison for Glue Iceberg tables via DuckDB's `iceberg` extension. Requires AWS creds (`source export.env`). |
| `validate_glue_parquet.py --job-id <id>` | Same comparison for Glue Parquet tables. Requires AWS creds. |
| `validate_supa_passthrough.py --destination {snowflake\|glue-iceberg\|postgres} --job-id <id>` | Byte-parity check on `_supa_id` + `_supa_index` between staging CSV and destination table. Joins on `_supa_id`, compares `_supa_index` values, validates 1..N contiguity in CSV. **Use this for dlt sources (Jira, Stripe) to catch `_supa_*` regressions.** |

**There is no `validate_postgres.py` for data comparison yet** -- Postgres data validation is not covered; fall back to manual spot checks or add the script before declaring PG green. `validate_supa_passthrough.py --destination postgres` DOES work and covers the `_supa_*` columns.

---

## 2. Create pipelines

```bash
export SUPAFLOW_APP_URL=http://localhost:3000
python3 supaflow-platform/scripts/smoke/create_smoke_pipelines.py
```

Creates up to ~70 pipelines (14 sources x 5 destinations, minus pg-to-pg). Idempotent. Output summary shows `Created`, `Skipped`, `Failed`. If any fail, stop and show the user the error -- never silently retry or rename.

**Before creating:** if the sources include new connectors (e.g., Jira, Stripe), verify the datasource `api_name` values in the script's `SOURCES` tuple against the actual dev datasources:

```bash
supaflow datasources list --limit 200 --json | \
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); [print(x['api_name'], x['name']) for x in d.get('data', [])]"
```

Update `SOURCES` in `create_smoke_pipelines.py` if api_names differ.

---

## 3. Sync by destination

**Run destination-by-destination, not all at once.** Agent concurrency and memory headroom are limited. Between batches, verify and investigate any failures before moving on.

```bash
export SUPAFLOW_APP_URL=http://localhost:3000

# Snowflake (no target reset needed for first run)
python3 supaflow-platform/scripts/smoke/sync_smoke_pipelines.py snowflake --full-resync

# S3 Data Lake (Glue) -- needs --reset-target to drop stale Iceberg tables from prior runs
python3 supaflow-platform/scripts/smoke/sync_smoke_pipelines.py s3_data_lake --full-resync --reset-target

# S3 Data Lake Parquet -- same
python3 supaflow-platform/scripts/smoke/sync_smoke_pipelines.py s3_dl_parquet --full-resync --reset-target

# S3 DL Polaris -- needs --reset-target AND Snowflake Open Catalog setup (credentials + network)
python3 supaflow-platform/scripts/smoke/sync_smoke_pipelines.py s3_dl_polaris --full-resync --reset-target

# PostgreSQL destination
python3 supaflow-platform/scripts/smoke/sync_smoke_pipelines.py postgresql --full-resync
```

**Save the printed job IDs.** `verify_smoke_jobs.py` and the validators need them. The sync script writes them to stdout after submitting the batch.

### Destination-filter gotcha

`sync_smoke_pipelines.py postgresql` also matches pipelines where **PostgreSQL is the source** (e.g., `postgresql_to_snowflake_smoke_test`). That's a substring match in `api_name`. Those pipelines will re-run even if they've been verified against another destination. Not harmful, but you may see duplicate coverage and out-of-band failures for mis-scoped combos (e.g., `postgresql_to_s3_dl_polaris_smoke_test` failing because Polaris isn't set up). Filter the job-ID list before handing them to `verify_smoke_jobs.py` if you want a cleaner per-destination report.

### Known source skips

`SKIP_SOURCE_PREFIXES` in `sync_smoke_pipelines.py` excludes:

- `airtable` -- rate-limited for the month (Airtable's free tier allows a limited number of API calls per month)
- `sql_server` -- Azure SQL test instance is dead

Check and update this map before a smoke run if any source is known-broken.

### Running a subset of source pipelines for one destination

`sync_smoke_pipelines.py` filters by **destination** only -- no `--sources` flag. When the release scope calls for "just the dlt sources (Jira + Stripe) against PG and S3 Data Lake" (e.g., re-running after a fix that only affects those), do not try to shoehorn this into the batch script. Invoke `supaflow pipelines sync` one pipeline at a time:

```bash
export SUPAFLOW_APP_URL=http://localhost:3000

# Postgres -- no --reset-target (destination merge handles existing tables)
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
python3 supaflow-platform/scripts/smoke/verify_smoke_jobs.py <job-id-1> <job-id-2> ...
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

**Anything outside this list is a real issue.** Do not ignore.

### Release criteria for this step

- `FAIL: 0` across the batch (excluding known source skips like Airtable/SQL Server)
- `deviation: 0` on every passing job (source_rows == dest_rows)
- No unknown ERRORs reported
- Memory headroom > 0 (if container peak == limit, flag it even if jobs pass -- we're one load-spike away from OOM)

---

## 5. Validate data (destination vs source CSV)

For each destination, run the corresponding validator for the jobs that passed verification. These compare actual destination data against the source staging CSVs using DuckDB aggregates.

All validators expect to be run **from `supaflow-platform/`** (their relative paths like `scripts/smoke/` and `data/tenants/` resolve from there).

```bash
cd supaflow-platform

# Snowflake (no env needed beyond snow CLI config)
python3 scripts/smoke/validate_snowflake.py --job-id <job-id>
python3 scripts/smoke/validate_snowflake.py --job-id <job-id> --objects Customer Event  # subset

# Glue Iceberg (needs AWS creds)
source export.env
PYTHONPATH=python python3 scripts/smoke/validate_glue_iceberg.py --job-id <job-id>

# Glue Parquet (needs AWS creds)
source export.env
PYTHONPATH=python python3 scripts/smoke/validate_glue_parquet.py --job-id <job-id>
```

Output:
- Per object: PASS | FAIL | SKIP | ERROR, csv_rows vs dest_rows, number of compared columns, elapsed time
- On FAIL: up to 5 mismatches printed (which column, which aggregate, source vs destination value)

### Known asymmetries (NOT validator bugs)

- **Snowflake empty-string -> NULL**: Snowflake's default CSV file format uses `EMPTY_FIELD_AS_NULL=TRUE`, so empty CSV fields get coerced to NULL on `COPY INTO`. The validator surfaces this as a `COUNT(DISTINCT)` diff of 1 when a STRING column has a genuine empty string. See `TODO.md` P0-59 for the fix plan. Do not silently suppress.
- **Glue column name truncation**: 128-char Glue column name limit triggers WARN; content is truncated as expected.
- **HubSpot property_history.value off-by-1 distinct count**: type-coercion artifact, known.

---

## 6. Validate `_supa_id` / `_supa_index` passthrough (dlt sources only)

For dlt-based sources (Jira, Stripe as of 2026-04), the Python SDK emits source-owned `_supa_id` and `_supa_index` values. These MUST be preserved byte-for-byte through staging CSV -> destination table. Run:

```bash
cd supaflow-platform

# Snowflake -- no env needed beyond snow CLI config
python3 scripts/smoke/validate_supa_passthrough.py --destination snowflake --job-id <id>

# Glue Iceberg -- needs AWS creds from export.env + S3 prefix
source export.env
python3 scripts/smoke/validate_supa_passthrough.py --destination glue-iceberg \
    --job-id <id> --s3-prefix-path "${AWS_S3_PREFIX_PATH:-supa-prefix}"

# PostgreSQL destination -- requires a remap step, see below
```

**Postgres credential remap (GOTCHA):** the validator reads `DEV_SUPABASE_DB_{HOST,PORT,USER,PASSWORD,NAME}`, which by name looks like it should come from `supaflow-sql-scripts/.../schema-deploy/.env`. It does NOT -- those vars point at the **control-plane** Supabase (platform metadata), not the actual Postgres **destination** warehouse. The destination credentials live in `supaflow-platform/export.env` under `POSTGRES_*`. You have to remap before running the validator:

```bash
cd supaflow-platform
source export.env
export DEV_SUPABASE_DB_HOST="$POSTGRES_HOST"
export DEV_SUPABASE_DB_PORT="$POSTGRES_PORT"
export DEV_SUPABASE_DB_USER="$POSTGRES_USER"
export DEV_SUPABASE_DB_PASSWORD="$POSTGRES_PASSWORD"
export DEV_SUPABASE_DB_NAME="$POSTGRES_DATABASE"
python3 scripts/smoke/validate_supa_passthrough.py --destination postgres --job-id <id>
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

## 7. Known-broken / in-flight issues (as of 2026-04-19)

Watch for these; do not treat them as "unknown" failures:

| Issue | Scope | Tracked |
|---|---|---|
| Migration 065 strips `_supa_*` on new-field discovery for `BLOCK_ALL` pipelines | S3 Data Lake / Parquet / Polaris pipelines created before catalog v3 | `TODO.md` P1-11L |
| `PostgresLoader.createStageTable` emits duplicate `_supa_id` DDL for dlt sources | Jira → PG, Stripe → PG | Active fix in progress |
| `DestinationTableHandling=FAIL` blocks recreated pipelines if Glue tables already exist | Any recreated pipeline | Workaround: `--reset-target` on first sync |
| Soft-deleted pipeline rows leave orphaned `pipeline_metadata_mappings` | DB queries | Filter by `state='active'` when counting/comparing |
| Docker agent memory at 100% ceiling on 4GB limit when running wide Python batches | Docker only | Monitor; file if OOMs occur |

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

---

## 9. Reporting format

When reporting smoke test results to the user, use this layout:

```
Batch: <destination>
Jobs submitted: N
Jobs passed:    M (log verify)
Data validated: K (destination vs source CSV)
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
