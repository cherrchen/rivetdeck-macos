// TEST ONLY: real official DSH + Swift transport, with a deterministic local model.
// This is not a real DeepSeek answer and is never loaded by the application.
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const probe = process.argv[2];
assert(probe, 'Usage: node Tests/Integration/model-fixture.mjs /path/to/dsh-probe');
let calls = 0;
const fixtureText = 'RIVETDECK_FIXTURE_OK';
const server = createServer(async (request, response) => {
 if (request.method !== 'POST' || request.url !== '/v1/messages') { response.writeHead(404); response.end(); return; }
 let body = ''; for await (const chunk of request) body += chunk;
 const query = JSON.parse(body); calls++;
 assert(query.stream, 'DSH must request a stream');
 const tool = calls === 1;
 const events = [
  { type: 'message_start', message: { id: `fixture-${calls}`, type: 'message', role: 'assistant', model: query.model, content: [], usage: { input_tokens: 4, output_tokens: 0 } } },
  { type: 'content_block_start', index: 0, content_block: tool ? { type: 'tool_use', id: 'fixture-cwd', name: 'working_directory', input: {} } : { type: 'text', text: '' } },
  ...(tool ? [{ type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: '{}' } }] : [{ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: fixtureText } }]),
  { type: 'content_block_stop', index: 0 },
  { type: 'message_delta', delta: { stop_reason: tool ? 'tool_use' : 'end_turn' }, usage: { output_tokens: 2 } },
  { type: 'message_stop' },
 ];
 response.writeHead(200, { 'content-type': 'text/event-stream' });
 for (const event of events) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
 response.end();
});
server.listen(0, '127.0.0.1'); await once(server, 'listening');
const home = await mkdtemp(resolve(tmpdir(), 'rivetdeck-model-fixture-'));
let child;
try {
 child = spawn(probe, [process.execPath, resolve('runtime'), resolve(home, 'home'), home, '--fixture'], {
  env: { ...process.env, RIVETDECK_TEST_BASE_URL: `http://127.0.0.1:${server.address().port}` }, stdio: ['ignore', 'pipe', 'pipe'],
 });
 let output = '', errors = '';
 child.stdout.on('data', chunk => { output += chunk; }); child.stderr.on('data', chunk => { errors += chunk; });
 const timer = setTimeout(() => child.kill('SIGTERM'), 45000);
 const [code] = await once(child, 'exit'); clearTimeout(timer);
 process.stdout.write(output);
 assert.equal(code, 0, errors);
 assert(output.includes(`Message assistant: ${fixtureText}`), 'Missing actual DSH assistant/message');
 assert(output.includes('Tool: working_directory'), 'Missing actual DSH tool/call');
 assert(calls >= 2, 'Expected tool execution followed by an assistant turn');
 console.log('PASS: official DSH + Swift + local TEST model fixture: real tool call, result, assistant event. No paid API.');
} finally {
 child?.kill('SIGTERM'); server.closeAllConnections(); server.close(); await rm(home, { recursive: true, force: true });
}
