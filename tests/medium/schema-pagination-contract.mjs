import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import readline from 'node:readline';
import path from 'node:path';

// Test oracle for synthetic fixtures and real Claude tool-call transcripts.
// This is not shipped in either plugin and never calls a service.
export function assertSequentialSchemaPages(pages) {
  assert(pages.length > 0, 'No schema pages observed');
  const first = pages[0].request;
  const limit = first.limit ?? 25;
  let nextOffset = 0;
  for (const [index, { request, response }] of pages.entries()) {
    assert.equal(request.offset ?? 0, nextOffset, 'Schema offsets must advance sequentially');
    assert.equal(request.limit ?? 25, limit, 'Schema page limit changed');
    for (const key of ['workspace_id', 'identifier']) assert.equal(request[key], first[key]);
    for (const key of ['all', 'with_fields']) assert.equal(request[key] ?? false, first[key] ?? false);
    assert.equal(response.offset, nextOffset);
    assert.equal(response.limit, limit);
    assert(Array.isArray(response.objects));
    assert.equal(typeof response.has_more, 'boolean');
    if (index < pages.length - 1) assert.equal(response.has_more, true, 'Traversal continued after completion');
    nextOffset += limit;
  }
  assert.equal(pages.at(-1).response.has_more, false, 'Schema traversal is incomplete');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const requests = new Map();
  const pages = [];
  let result;
  let parseError;
  for await (const line of readline.createInterface({ input: process.stdin })) {
    try {
      const event = JSON.parse(line);
      if (event.type === 'assistant') {
        for (const block of event.message?.content ?? []) {
          if (block.type !== 'tool_use') continue;
          if (block.name.endsWith('__pipelines_schema_list')) requests.set(block.id, block.input);
          console.log(JSON.stringify({ tool: block.name, input: block.input }));
        }
      }
      if (event.type === 'user') {
        for (const block of event.message?.content ?? []) {
          if (block.type !== 'tool_result' || !requests.has(block.tool_use_id)) continue;
          assert(!block.is_error, 'Schema tool failed');
          const response = JSON.parse(block.content);
          pages.push({ request: requests.get(block.tool_use_id), response });
        }
      }
      if (event.type === 'result') result = event;
    } catch (error) {
      parseError = error;
    }
  }
  try {
    assert(!parseError, 'Could not validate a transcript event');
    assert(result && !result.is_error, 'Claude test did not complete successfully');
    assert.equal(result.permission_denials?.length ?? 0, 0, 'Unexpected tool permission denial');
    assert.equal(requests.size, pages.length, 'Missing schema tool response');
    assertSequentialSchemaPages(pages);
    console.log(`PASS: sequential schema offsets ${pages.map(({ request }) => request.offset ?? 0).join(', ')}`);
    console.log(result.result);
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    process.exitCode = 1;
  }
}
