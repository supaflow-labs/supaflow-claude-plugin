import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertSequentialSchemaPages } from './schema-pagination-contract.mjs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(dir, '../../plugins/supaflow');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');
const entry = read('skills/using-supaflow/SKILL.md');
const safe = read('skills/using-supaflow/safety.md');
const contracts = read('skills/using-supaflow/response-contracts.md');
const pipelines = read('skills/supaflow-pipelines/SKILL.md');
const jobs = read('skills/supaflow-jobs/SKILL.md');
const datasources = read('skills/supaflow-datasources/SKILL.md');
const schedules = read('skills/supaflow-schedules/SKILL.md');
const fixture = JSON.parse(fs.readFileSync(path.join(dir, 'fixtures/hosted-results.json'), 'utf8'));
let passed = 0;
let failed = 0;
function check(name, fn) {
  try { fn(); passed += 1; console.log(`PASS: ${name}`); }
  catch (error) { failed += 1; console.log(`FAIL: ${name} (${error.message})`); }
}
function contains(name, source, pattern) { check(name, () => assert.match(source, pattern)); }
function terminalStates(source) {
  const list = source.match(/Terminal states are ([^.]+)\./);
  assert(list, 'job skill must declare its terminal-state set');
  return [...list[1].matchAll(/`([^`]+)`/g)].map((match) => match[1]);
}

console.log('Testing hosted workflow instructions and synthetic contract fixtures...');
contains('identity is checked before using resources', entry, /auth_status[\s\S]*user_id[\s\S]*organization_id/);
contains('personal tenant null organization is valid', entry, /null `organization_id` is valid/);
contains('workspace choice is explicit', entry, /otherwise ask the user to choose/);
contains('all scoped calls pass a workspace ID', entry, /workspace_id` explicitly on every workspace-scoped call/);
contains('host-prefixed names are resolved, not assumed', entry, /actual names exposed by the host/);
contains('reconnect invalidates previous identity/workspace assumptions', entry, /After reconnecting or changing accounts, rerun this gate/);
contains('no hosted selected-workspace mutation', entry, /no hosted `workspaces_select` operation/);
contains('host approvals are not packaged grants', entry, /Do not change the host's tool permissions/);
contains('local agent lifecycle stays outside hosted', entry, /hosted server cannot install, start, stop, upgrade/);
contains('normal sync can be authorized by the direct request', entry, /clear request to run one normal sync authorizes that run/);
contains('mutation retries reconcile first', safe, /Never blindly repeat create, edit, sync/);
contains('read retries require an explicit retryable error', entry, /only when `retryable: true`/);
contains('read retries respect backoff', entry, /retry_after_ms/);
contains('destructive actions require immediate confirmation', safe, /explicit confirmation immediately before the call/);
contains('plaintext credentials never go through the client', entry, /Never send plaintext credentials/);
contains('encrypted envelopes must not be fabricated', safe, /fabricate encrypted envelopes/);

contains('datasource init comes before creation', datasources, /datasources_init\(connector\)/);
contains('server-side datasource copy is supported', datasources, /copy_from_identifier/);
contains('catalog inspection does not refresh', datasources, /refresh: false/);
contains('catalog reset waits for restoration, not job terminal alone', datasources, /catalog_reset\.maintenance_active` is false[\s\S]*terminal job alone is insufficient/);

contains('pipeline duplicates use hosted ID fields', pipelines, /sourceDatasourceId.*destinationDatasourceId/);
contains('pipeline plans use actual config, not local config_summary', pipelines, /actual `config`, `object_count_total`, `objects_preview`, and `object_preview_truncated`/);
contains('truncated plan subset names come from catalog pages', pipelines, /Page `datasources_catalog` to resolve exact/);
contains('pipeline creation is explicitly confirmed', pipelines, /confirmed: true` only after that final approval/);
contains('signed plans cannot cross account/workspace or expiry', pipelines, /expired or different-user\/workspace plan/);
contains('creation requires live verification, not invented verification wrapper', pipelines, /Reread `pipelines_get` and the complete selected-object pages/);
contains('saved config is not guessed from init', contracts, /Do not call `pipelines_init` to pretend/);
contains('sparse schema pages cannot terminate early', contracts, /while `has_more` is true, even if `objects` is empty or shorter than limit/);
contains('schema offsets advance by raw page size', contracts, /Advance offset by limit/);
contains('cursor inventory mode is capability checked', contracts, /loaded .*schema advertises `sort` and `after_id`/);
contains('ordinary sync never full-resyncs or resets', pipelines, /full_resync: false`.*reset_target: false/);
contains('full resync or reset is not automatic recovery', pipelines, /Never turn these flags on as an automatic failure-recovery step/);

contains('job monitoring uses exact ID and status tool', jobs, /Call `jobs_status\(id\)` and read `job.status`/);
contains('terminal details are required', jobs, /Once terminal, call `jobs_get\(id\)` before the final summary/);
check('all backend terminal job states, including skipped, are represented', () => {
  assert.deepEqual(terminalStates(jobs).sort(),
    ['completed', 'completed_with_warning', 'failed', 'cancelled', 'timed_out', 'skipped'].sort());
});
contains('skipped jobs stop polling and are not automatically retried', jobs,
  /A skipped job[\s\S]*report its returned reason[\s\S]*stop polling[\s\S]*do not automatically rerun/);
contains('jobs and pipelines are not conflated', jobs, /Do not count jobs as pipelines/);
contains('null response does not invent logs', jobs, /Null response means no further stored detail/);
contains('missing rows are unavailable, not zero', jobs, /Missing row counts are unavailable, not zero/);
contains('empty details do not prove zero rows', jobs, /empty details list alone does not prove/);
contains('cancellation requires current state and confirmation', jobs, /explicit confirmation immediately before `jobs_cancel`/);
contains('schedule timezone is reviewed', schedules, /do not silently assume the user's local timezone or UTC/);
contains('schedule create/list cron names remain distinct', schedules, /schedule.cron`.*`cron_schedule`/);
contains('schedule history baseline is captured before triggering', schedules,
  /Before triggering, read `schedules_history[\s\S]*record the existing `execution_id` values as a baseline/);
contains('schedule trigger response is not a job-ID response', schedules,
  /schedule.status: "triggered"`[\s\S]*does not return a job ID/);
contains('schedule/execution IDs cannot be passed to job tools', schedules,
  /Never pass the schedule ID or an execution ID to `jobs_status`, `jobs_get`, or `jobs_logs`/);
contains('new execution is correlated with the pre-trigger baseline', schedules,
  /actual `execution_id` and `triggered_at`, comparing with the pre-trigger baseline/);
contains('monitoring follows the resolved execution, not the latest job', schedules,
  /monitor that same execution through `schedules_history`, matching its `execution_id` on every poll/);
contains('job polling requires an explicit execution/job association', schedules,
  /Poll job tools only if an actual returned response explicitly links a real job ID to that resolved execution/);
contains('missing or concurrent execution history is reported as unresolved', schedules,
  /no new execution, multiple new executions cannot be correlated unambiguously[\s\S]*cannot be resolved\/monitored/);
contains('unresolved schedule monitoring never retriggers or claims completion', schedules,
  /do not claim completion, invent an associated job, widen to another workspace, or rerun the schedule/);
contains('safety guidance does not imply every schedule returns a job ID', safe,
  /Schedule runs return only a trigger acknowledgement[\s\S]*only for an explicitly associated job ID/);
contains('response reference documents the trigger and history wrappers', contracts,
  /`schedules_run`[^\n]*no job ID[\s\S]*`schedules_history`[^\n]*`schedule_id`, `executions`/);

check('fixture: personal identity and datasource/project linkage', () => {
  assert.equal(fixture.auth_status.organization_id, null);
  assert.equal(fixture.datasources_list.total, fixture.datasources_list.datasources.length);
  assert.equal(fixture.projects_list.projects[0].destinationDatasourceId,
    fixture.datasources_list.datasources[1].id);
  assert(contracts.includes('organization_id'));
  assert(contracts.includes('destinationDatasourceId'));
});
check('fixture: hosted inventory is not the CLI data/nested contract', () => {
  const p = fixture.pipelines_list.pipelines[0];
  assert.equal(fixture.pipelines_list.total, 1);
  assert.equal(p.sourceDatasourceId, fixture.datasources_list.datasources[0].id);
  assert.equal(p.destinationDatasourceId, fixture.datasources_list.datasources[1].id);
  assert.equal(p.source, undefined);
  assert.equal(fixture.pipelines_list.data, undefined);
  for (const key of ['pipelines', 'sourceDatasourceId', 'destinationDatasourceId']) assert(contracts.includes(key));
});
check('fixture: truncated preview has no local plan files or old count keys', () => {
  const p = fixture.pipelines_prepare_create;
  assert(p.object_preview_truncated && p.object_count_returned < p.object_count_total);
  assert.equal(p.host_files, undefined);
  assert.equal(p.config_summary, undefined);
  for (const key of Object.keys(p)) assert(contracts.includes(key), `undocumented hosted plan field: ${key}`);
});
check('fixture: empty middle schema page still has more selected objects', () => {
  const pages = fixture.pipelines_schema_pages;
  assert.equal(pages[1].objects.length, 0);
  assert.equal(pages[1].has_more, true);
  assert.equal(pages[2].has_more, false);
  assert.equal(pages[2].offset, pages[1].offset + pages[1].limit);
  assert.deepEqual(pages.flatMap((p) => p.objects.map((o) => o.fully_qualified_name)), ['Account', 'Contact']);
});
check('schema traversal accepts short and empty pages only with sequential offsets', () => {
  const pages = fixture.pipelines_schema_pages.map((response) => ({
    request: { workspace_id: 'workspace-test', identifier: 'pipeline-test', limit: response.limit, offset: response.offset },
    response,
  }));
  assertSequentialSchemaPages(pages);
});
check('regression: distant terminal probes cannot hide skipped schema pages', () => {
  const page = (offset, has_more) => ({
    request: { workspace_id: 'workspace-test', identifier: 'pipeline-test', limit: 200, offset },
    response: { limit: 200, offset, objects: [], has_more },
  });
  assert.throws(() => assertSequentialSchemaPages([page(0, true), page(200, true), page(9800, false)]), /sequentially/);
  assert.throws(() => assertSequentialSchemaPages([page(0, true), page(200, true), page(100, false)]), /sequentially/);
  assert.throws(() => assertSequentialSchemaPages([page(0, true)]), /incomplete/);
  assert.throws(() => assertSequentialSchemaPages([page(0, false), page(200, false)]), /after completion/);
});
check('fixture: enqueue ID matches monitored job', () => {
  const id = fixture.pipelines_sync.job_id;
  for (const key of ['jobs_status', 'jobs_get', 'jobs_logs']) assert.equal(fixture[key].job.id, id);
  assert.equal(fixture.pipelines_sync.status, 'queued');
  assert.equal(fixture.jobs_status.job.status, 'completed');
  assert.equal(fixture.jobs_status.job_status, undefined);
  for (const key of ['job.status', 'job.statusMessage', 'executionDurationMs']) assert(contracts.includes(key));
});
check('fixture: terminal metrics use actual hosted response and object fields', () => {
  const object = fixture.jobs_get.job.object_details[0];
  assert.equal(object.ingestion_metrics.output_row_count, 12);
  assert.equal(fixture.jobs_logs.job.response.total_rows_destination, 12);
  for (const key of ['object_details', 'fully_qualified_source_object_name', 'output_row_count']) assert(jobs.includes(key));
});
check('fixture: failed/no-metric response stays unavailable and preserves zero duration', () => {
  assert.equal(fixture.failed_jobs_get.job.executionDurationMs, 0);
  assert.deepEqual(fixture.failed_jobs_get.job.object_details, []);
  assert.equal(fixture.failed_jobs_logs.job.response, null);
});
check('fixture: a skipped status terminates monitoring and preserves its actual reason', () => {
  const status = fixture.skipped_jobs_status.job;
  assert(terminalStates(jobs).includes(status.status));
  assert.equal(status.status, 'skipped');
  for (const name of ['skipped_jobs_get', 'skipped_jobs_logs']) {
    assert.equal(fixture[name].job.id, status.id);
    assert.equal(fixture[name].job.status, status.status);
  }
  assert.equal(fixture.skipped_jobs_get.job.statusMessage, status.statusMessage);
  assert.equal(fixture.skipped_jobs_logs.job.response, null);
});
check('regression: omitting skipped would leave that fixture nonterminal', () => {
  const oldList = jobs.replace(', and `skipped`', '');
  assert(!terminalStates(oldList).includes(fixture.skipped_jobs_status.job.status));
});
check('fixture: schedule creation is reconciled with inventory by ID and cron', () => {
  const created = fixture.schedules_create.schedule;
  const saved = fixture.schedules_list.schedules[0];
  assert.equal(created.id, saved.id);
  assert.equal(created.cron, saved.cron_schedule);
  assert.equal(created.target_id, saved.target_id);
});
check('fixture: schedule trigger has neither a job ID nor an execution ID', () => {
  const run = fixture.schedules_run;
  assert.deepEqual(run, { schedule: { id: fixture.schedules_list.schedules[0].id, status: 'triggered' } });
  assert.equal(run.job_id, undefined);
  assert.equal(run.schedule.job_id, undefined);
  assert.equal(run.schedule.execution_id, undefined);
});
check('fixture: baseline separates the new execution from older completed history', () => {
  const before = fixture.schedules_history_before;
  const after = fixture.schedules_history_after;
  assert.equal(before.schedule_id, fixture.schedules_run.schedule.id);
  assert.equal(after.schedule_id, before.schedule_id);
  const oldIds = new Set(before.executions.map((row) => row.execution_id));
  const fresh = after.executions.filter((row) => !oldIds.has(row.execution_id));
  assert.equal(fresh.length, 1);
  assert(fresh[0].triggered_at > before.executions[0].triggered_at);
  assert.equal(fresh[0].status, 'running');
  const completed = fixture.schedules_history_completed.executions.find((row) => row.execution_id === fresh[0].execution_id);
  assert.equal(completed.status, 'completed');
  assert(completed.completed_at);
  assert.notEqual(fresh[0].execution_id, fixture.schedules_run.schedule.id);
});
check('fixture: history monitoring can complete without inventing a linked job ID', () => {
  const history = fixture.schedules_history_completed;
  assert.equal(history.schedule_id, fixture.schedules_run.schedule.id);
  const execution = history.executions[0];
  assert.equal(execution.job_id, undefined);
  assert.equal(execution.status, 'completed');
  assert.equal(execution.entries_completed, execution.entries_total);
  assert.notEqual(execution.execution_id, fixture.jobs_get.job.id);
});
check('fixture: missing and concurrent new executions cannot establish one monitored run', () => {
  assert.deepEqual(fixture.schedules_history_empty.executions, []);
  const oldIds = new Set(fixture.schedules_history_before.executions.map((row) => row.execution_id));
  const candidates = fixture.schedules_history_ambiguous.executions.filter((row) => !oldIds.has(row.execution_id));
  assert.equal(candidates.length, 2);
  assert.equal(candidates[0].triggered_at, candidates[1].triggered_at);
  assert(candidates.every((row) => row.job_id === undefined));
});

console.log(`\nResults: ${passed}/${passed + failed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
