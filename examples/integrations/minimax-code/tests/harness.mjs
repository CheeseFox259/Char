// Shared helpers for the MiniMax Code adapter tests: an isolated client data root and
// a real adapter process that speaks the Char v1 capability protocol.
import {spawn, spawnSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {appendFileSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

export const workspace = dirname(dirname(fileURLToPath(import.meta.url)));
export const cliPackage = join(workspace, 'packages', 'minimax-code-cli.charintegration');
export const desktopPackage = join(workspace, 'packages', 'minimax-code-desktop.charintegration');

/** Isolated client data root plus Char support directory; nothing touches the real HOME. */
export function isolatedEnvironment(label = 'minimax-test') {
  const root = mkdtempSync(join(tmpdir(), `${label}-`));
  const dataDir = join(root, '.minimax');
  const supportDir = join(root, 'support');
  mkdirSync(dataDir, {recursive: true});
  mkdirSync(supportDir, {recursive: true});
  return {
    root,
    dataDir,
    supportDir,
    spool: join(dataDir, 'v2', 'plugin-data', 'hooks', 'char-observer', 'events.ndjson'),
    pluginDir: join(dataDir, 'plugins', 'char-observer'),
    marker: join(dataDir, 'plugins', 'char-observer.char-owner.json'),
    cleanup: () => removeTree(root),
  };
}

/**
 * Remove an isolated root. The client writes a Hook cache while a discovery check is
 * still draining, so removal is retried before the leftover path is reported.
 */
export function removeTree(root) {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    try {
      // The client materialises its Hook cache read-only, so restore owner access first.
      spawnSync('/bin/chmod', ['-R', 'u+rwX', root], {stdio: 'ignore'});
      rmSync(root, {recursive: true, force: true, maxRetries: 5, retryDelay: 40});
      return true;
    } catch (error) {
      if (attempt === 5) {
        process.stderr.write(`could not remove ${root}: ${error.message}\n`);
        throw error;
      }
      spawnSync('/bin/sleep', ['0.2']);
    }
  }
  return false;
}

export function spoolDirectory(environment) {
  return dirname(environment.spool);
}

/** Write one native Hook record the way the client plugin does. */
export function appendRecord(environment, record) {
  mkdirSync(spoolDirectory(environment), {recursive: true});
  appendFileSync(environment.spool, `${JSON.stringify(record)}\n`);
}

export function appendRaw(environment, text) {
  mkdirSync(spoolDirectory(environment), {recursive: true});
  appendFileSync(environment.spool, text);
}

export function hookRecord(overrides = {}) {
  return {
    v: 1,
    ts: new Date().toISOString(),
    ev: 'UserPromptSubmit',
    signal: 'running',
    state: 'running',
    sid: `mvs_${randomUUID().replace(/-/g, '')}`,
    cwd: '/private/tmp/example',
    surface: 'cli',
    pid: process.pid,
    ...overrides,
  };
}

/** Run one adapter process exactly as the Char host does. */
export class AdapterProcess {
  constructor(packageDirectory, environment, {workEnd, pluginID, reference = process.env.CHAR_MINIMAX_REFERENCE_NODE === '1'} = {}) {
    const manifest = JSON.parse(readFileSync(join(packageDirectory, 'manifest.json'), 'utf8'));
    this.manifest = manifest;
    this.workEnd = workEnd ?? manifest.workEnd;
    const executable = !reference && manifest.adapter.runtime === 'executable' ? join(packageDirectory, manifest.adapter.entrypoint) : process.execPath;
    const args = executable === process.execPath ? [join(packageDirectory, 'adapter/adapter.mjs')] : [];
    this.child = spawn(executable, args, {
      env: {
        ...process.env,
        HOME: join(environment.root, 'home'),
        MINIMAX_DATA_DIR: environment.dataDir,
        CHAR_SUPPORT_DIRECTORY: environment.supportDir,
        CHAR_PLUGIN_DIRECTORY: packageDirectory,
        CHAR_PLUGIN_ID: pluginID ?? manifest.id,
        CHAR_PLUGIN_VERSION: manifest.version,
        CHAR_WORK_END: this.workEnd,
        CHAR_PLUGIN_CONFIG: JSON.stringify(manifest.adapter.configuration),
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    this.buffer = '';
    this.responses = new Map();
    this.events = [];
    this.unmatched = [];
    this.stderr = '';
    this.pending = new Map();
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (chunk) => this.consume(chunk));
    this.child.stderr.setEncoding('utf8');
    this.child.stderr.on('data', (chunk) => { this.stderr += chunk; });
    this.exited = new Promise((resolve) => this.child.on('close', (code, signal) => resolve({code, signal})));
  }

  consume(chunk) {
    this.buffer += chunk;
    let index = this.buffer.indexOf('\n');
    while (index >= 0) {
      const line = this.buffer.slice(0, index).trim();
      this.buffer = this.buffer.slice(index + 1);
      index = this.buffer.indexOf('\n');
      if (!line) continue;
      let frame;
      try {
        frame = JSON.parse(line);
      } catch {
        this.unmatched.push(line);
        continue;
      }
      if (frame.event) {
        this.events.push(frame.event);
        continue;
      }
      const pending = this.pending.get(frame.id);
      if (pending) {
        this.pending.delete(frame.id);
        pending(frame);
      } else {
        this.unmatched.push(line);
      }
    }
  }

  send(method, params = {}, timeoutMs = 5000) {
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`no response for ${method} within ${timeoutMs}ms`));
      }, timeoutMs);
      this.pending.set(id, (frame) => {
        clearTimeout(timer);
        resolve(frame);
      });
      this.child.stdin.write(`${JSON.stringify({version: 1, id, method, params})}\n`);
    });
  }

  async call(method, params = {}, timeoutMs = 5000) {
    const frame = await this.send(method, params, timeoutMs);
    if (frame.error) throw new Error(`${method} failed: ${frame.error}`);
    return frame.result ?? {};
  }

  /** Wait until `count` events have been observed or the deadline passes. */
  async waitForEvents(count, timeoutMs = 8000) {
    const deadline = Date.now() + timeoutMs;
    while (this.events.length < count && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    return this.events.length;
  }

  closeStdin() {
    this.child.stdin.end();
  }

  async stop(signal = 'SIGTERM') {
    if (this.child.exitCode === null && this.child.signalCode === null) this.child.kill(signal);
    return this.exited;
  }
}

export function rotateSpool(environment) {
  mkdirSync(spoolDirectory(environment), {recursive: true});
  renameSync(environment.spool, `${environment.spool}.1`);
}

export function writeForeignDirectory(environment, name, files = {'keep.txt': 'user file\n'}) {
  const directory = join(environment.dataDir, 'plugins', name);
  mkdirSync(directory, {recursive: true});
  for (const [file, contents] of Object.entries(files)) {
    writeFileSync(join(directory, file), contents);
  }
  return directory;
}

export function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));