import { createInterface } from 'node:readline';
import { readFile, writeFile, mkdir, copyFile, unlink, stat, chmod } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { spawn } from 'node:child_process';
const env = process.env;
const children = new Set();
function shutdown() { for (const child of children) child.kill(); process.exit(0); }
process.on('SIGTERM', shutdown);
const configuration = JSON.parse(env.CHAR_PLUGIN_CONFIG || '{}');
const family = ['kimiCLI', 'kimiDesktop'].includes(env.CHAR_WORK_END) ? 'kimi' : env.CHAR_WORK_END;
const home = env.HOME;
const native = env.CHAR_NATIVE_ROOT;
const binary = env.CHAR_HOOK_BINARY;
const events = env.CHAR_HOOK_EVENTS;
const piDir = configuration.extensionDirectory || join(home, '.pi/agent/extensions/char');
const kimiConfig = configuration.settingsFile || join(env.KIMI_CODE_HOME || join(home, '.kimi-code'), 'config.toml');
const deepPatch = configuration.profilePatch || join(home, '.dsh/profiles/desktop/cordis.patch.yml');
const text = path => readFile(path, 'utf8').catch(error => { if (error.code === 'ENOENT') return ''; throw error; });
async function runPython(args) {
  const child = spawn('python3', args, { env, stdio: ['ignore', 'pipe', 'pipe'] });
  children.add(child); child.on('close', () => children.delete(child));
  let output = ''; child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.resume();
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
  if (code !== 0) throw new Error('Native integration command failed; check Python 3.11+ and client configuration.');
  return output;
}
function deepEntry(source) {
  const marker = '    - id: char-desktop-observer\n';
  const first = source.indexOf(marker);
  if (first < 0) return null;
  if (source.indexOf(marker, first + marker.length) >= 0) throw new Error('More than one Char Desktop mount exists.');
  const next = source.slice(first + marker.length).search(/^(?:    - id:|\S)/m);
  const end = next < 0 ? source.length : first + marker.length + next;
  return { start: first, end, block: source.slice(first, end) };
}
async function inspect() {
  await stat(binary);
  if (family === 'pi') {
    const marker = JSON.parse(await text(join(piDir, 'package.json')) || '{}');
    const index = await text(join(piDir, 'index.js'));
    const source = await text(join(piDir, 'observer.mjs'));
    const matches = marker.name === 'char-pi-observer' && index.includes(JSON.stringify(binary))
      && index.includes(JSON.stringify(events)) && source === await text(join(native, 'pi/observer.mjs'));
    return { status: matches ? 'ready' : 'notInstalled', detail: matches ? 'Configuration matches; reload existing Pi sessions.' : 'Install or update the Char Pi extension.' };
  }
  if (family === 'kimi') return JSON.parse(await runPython([join(native, 'kimi/install.py'), '--action', 'inspect', '--settings', kimiConfig, '--hook-binary', binary, '--events-file', events]));
  if (family === 'deepseekDesktop') {
    const entry = deepEntry(await text(deepPatch));
    const matches = entry?.block.includes(`hookBinary: ${binary}\n`) && entry.block.includes(`name: ${join(native, 'deepseek/index.js')}\n`) && entry.block.includes(`eventsFile: ${events}\n`);
    return { status: matches ? 'ready' : 'notInstalled', detail: matches ? 'Configuration matches; Desktop reload is required after changes.' : 'Install or update the Char Desktop mount.' };
  }
  return { status: 'unavailable', detail: 'No native lifecycle adapter for this client.' };
}
async function backup(paths) {
  const directory = join(env.CHAR_SUPPORT_DIRECTORY, 'integration-backups', `${Date.now()}-${env.CHAR_PLUGIN_ID}`);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  for (let i = 0; i < paths.length; i++) {
    try { const target = join(directory, `${i}-${paths[i].split('/').at(-1)}`); await copyFile(paths[i], target); await chmod(target, 0o600); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return directory;
}
async function mutate(method, params) {
  const uninstall = method === 'uninstall';
  if (uninstall && params.retainSharedIntegration) return { status: 'ready', detail: 'Shared integration retained for another enabled Kimi client.' };
  if (family === 'pi') {
    await backup(['index.js', 'observer.mjs', 'package.json'].map(name => join(piDir, name)));
    if (uninstall) {
      const marker = JSON.parse(await text(join(piDir, 'package.json')) || '{}');
      if (marker.name === 'char-pi-observer') {
        for (const name of ['index.js', 'observer.mjs', 'package.json']) await unlink(join(piDir, name)).catch(error => { if (error.code !== 'ENOENT') throw error; });
      }
    } else await runPython([join(native, 'pi/install.py'), '--extension-dir', piDir, '--hook-binary', binary, '--events-file', events]);
  } else if (family === 'kimi') {
    await backup([kimiConfig]);
    await runPython([join(native, 'kimi/install.py'), '--action', uninstall ? 'uninstall' : 'install', '--settings', kimiConfig, '--hook-binary', binary, '--events-file', events]);
  } else if (family === 'deepseekDesktop') {
    await backup([deepPatch]);
    const source = await text(deepPatch), entry = deepEntry(source);
    let result = source;
    if (uninstall && entry) {
      let start = entry.start;
      if (source.slice(0, start).endsWith('- insert:\n') && !source.slice(entry.end).startsWith('    - id:')) start -= '- insert:\n'.length;
      result = source.slice(0, start) + source.slice(entry.end);
    } else if (!uninstall) {
      const block = `    - id: char-desktop-observer\n      name: ${join(native, 'deepseek/index.js')}\n      config:\n        hookBinary: ${binary}\n        eventsFile: ${events}\n`;
      result = entry ? source.slice(0, entry.start) + block + source.slice(entry.end) : source + '\n- insert:\n' + block;
    }
    await mkdir(dirname(deepPatch), { recursive: true, mode: 0o700 });
    const temporary = deepPatch + '.char-updating';
    await writeFile(temporary, result, { mode: (await stat(deepPatch).catch(() => null))?.mode & 0o777 || 0o600 });
    const { rename } = await import('node:fs/promises'); await rename(temporary, deepPatch);
  } else throw new Error('Native integration is unsupported.');
  return { status: uninstall ? 'notInstalled' : 'reloadRequired', detail: uninstall ? 'Owned integration removed; reload the client.' : 'Integration updated; reload or restart the client.' };
}
let pending = Promise.resolve();
createInterface({ input: process.stdin }).on('close', shutdown).on('line', line => {
  pending = pending.then(async () => {
    let request;
    try {
      request = JSON.parse(line);
      if (request.version !== 1) throw new Error('Unsupported protocol.');
      let result;
      if (request.method === 'hello') result = { protocolVersion: 1 };
      else if (request.method === 'inspect') result = await inspect();
      else if (['install', 'update', 'uninstall'].includes(request.method)) result = await mutate(request.method, request.params || {});
      else throw new Error('Unsupported native lifecycle method.');
      process.stdout.write(JSON.stringify({ version: 1, id: request.id, result }) + '\n');
    } catch (error) { process.stdout.write(JSON.stringify({ version: 1, id: request?.id, error: error.message }) + '\n'); }
  });
});
