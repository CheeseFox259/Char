// Explicit local acceptance: real Pi CLI -> extension -> real char-hook -> normalized event stream.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

const [piBinary, hookBinary] = process.argv.slice(2);
assert(piBinary && hookBinary, 'Usage: node integrations/pi/native-cli.test.mjs /absolute/pi /absolute/char-hook');
const root = await mkdtemp(join(tmpdir(), 'char-pi-native-'));
let failure = false;
let requests = 0;
const server = createServer(async (request, response) => {
  requests++;
  assert.equal(request.url, '/v1/chat/completions');
  // Consume but never persist the fixture prompt or Pi-generated system prompt.
  for await (const chunk of request) { }
  if (failure) {
    response.writeHead(400, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ error: { message: 'controlled fixture failure', type: 'invalid_request_error' } }));
    return;
  }
  response.writeHead(200, { 'Content-Type': 'text/event-stream' });
  const chunk = (delta, finish_reason = null) => ({ id: 'char-local', object: 'chat.completion.chunk', created: 1, model: 'fixture', choices: [{ index: 0, delta, finish_reason }] });
  response.write(`data: ${JSON.stringify(chunk({ role: 'assistant', content: 'local fixture complete' }))}\n\n`);
  response.write(`data: ${JSON.stringify(chunk({}, 'stop'))}\n\n`);
  response.end('data: [DONE]\n\n');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  const agentDir = join(root, 'agent');
  const working = join(root, 'project');
  await mkdir(agentDir);
  await mkdir(working);
  const port = server.address().port;
  await writeFile(join(agentDir, 'models.json'), JSON.stringify({ providers: { 'char-local': {
    baseUrl: `http://127.0.0.1:${port}/v1`, api: 'openai-completions', apiKey: 'fixture-only',
    models: [{ id: 'fixture', name: 'Char fixture', reasoning: false, input: ['text'],
      contextWindow: 16384, maxTokens: 1000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
  } } }));
  await writeFile(join(agentDir, 'settings.json'), JSON.stringify({ retry: { enabled: false }, cacheWarming: { enabled: false } }));
  const events = join(root, 'events.jsonl');
  const extension = join(root, 'extension');
  execFileSync('python3', [resolve('integrations/pi/install.py'), '--extension-dir', extension,
    '--hook-binary', resolve(hookBinary), '--events-file', events]);
  async function run() {
    const child = spawn(resolve(piBinary), ['--offline', '--no-extensions', '--no-skills', '--no-prompt-templates',
      '--no-themes', '--no-context-files', '--no-approve', '--no-tools', '--no-session',
      '--extension', join(extension, 'index.js'), '--provider', 'char-local', '--model', 'fixture',
      '--print', 'Harmless local fixture.'], {
      cwd: working, env: { PATH: process.env.PATH, HOME: root, PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1', TERM: 'dumb' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let output = '';
    child.stdout.on('data', data => { output += data; });
    child.stderr.on('data', data => { output += data; });
    const timer = setTimeout(() => child.kill('SIGTERM'), 15000);
    const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('exit', resolve); });
    clearTimeout(timer);
    assert.equal(code, failure ? 1 : 0, output);
    assert(!output.includes('Char:'), output);
  }
  await run();
  failure = true;
  await run();
  const records = (await readFile(events, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(requests, 2, 'real CLI did not reach only the two localhost requests');
  assert.deepEqual(records.map(r => Object.keys(r.state)[0]), ['running', 'stopped', 'closed', 'running', 'stopped', 'closed']);
  assert.deepEqual(records.filter(r => r.state.stopped).map(r => r.state.stopped._0), ['turnEnded', 'failure']);
  assert(records.every(r => r.key.workEnd === 'pi' && r.target.bundleIdentifier === 'dev.warp.Warp-Stable' && !r.target.tmuxPaneID));
  assert.notEqual(records[0].key.nativeID, records[3].key.nativeID);
  const stream = await readFile(events, 'utf8');
  assert(!stream.includes('fixture complete') && !stream.includes('fixture failure') && !stream.includes('Harmless'), 'private content persisted');
  console.log('Pi native CLI localhost acceptance: completed and failed runs, native session identity, direct Warp metadata, closure and private-content exclusion passed');
} finally {
  await new Promise(resolve => server.close(resolve));
  await rm(root, { recursive: true, force: true });
}
