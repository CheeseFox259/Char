#!/usr/bin/env node
/**
 * Char capability adapter for MiniMax Code.
 *
 * One package serves one work end: `minimaxcode.cli` observes sessions whose native
 * Hook ran under the terminal-hosted `mcode` client, `minimaxcode.desktop` observes
 * sessions whose Hook ran under the MiniMax Code desktop app. Both packages share this
 * source and the same native plugin; only the manifest decides which one is loaded.
 *
 * stdout carries protocol frames only. Diagnostics go to stderr, which the host drops.
 */
import {createInterface} from 'node:readline';
import {pluginConfig, surfaceFor, spoolPath, pluginDataDirectory} from './lib/config.mjs';

const env = process.env;
const config = pluginConfig(env);
const workEnd = env.CHAR_WORK_END ?? '';
const surface = surfaceFor(config, workEnd, 'cli');
const packageRoot = env.CHAR_PLUGIN_DIRECTORY ?? process.cwd();
const pluginID = env.CHAR_PLUGIN_ID ?? 'minimax.code';
const packageVersion = config.nativePluginVersion ?? env.CHAR_PLUGIN_VERSION ?? '0.0.0';
const bundleIdentifier = config.bundleIdentifier ?? '';

function diagnostic(message) {
  process.stderr.write(`[minimax-code:${workEnd}] ${message}\n`);
}

function write(frame) {
  process.stdout.write(`${JSON.stringify(frame)}\n`);
}

let monitor = null;

async function monitorForMethod() {
  if (monitor) return monitor;
  const {Monitor} = await import('./lib/monitor.mjs');
  monitor = new Monitor({
    workEnd,
    surface,
    spool: spoolPath(config, env),
    directory: pluginDataDirectory(config, env),
    onEvent: (event) => write({version: 1, event}),
    onDiagnostic: diagnostic,
  });
  return monitor;
}

const methods = {
  async hello() {
    return {protocolVersion: 1};
  },

  async inspect() {
    const {inspectInstallation} = await import('./lib/client.mjs');
    return inspectInstallation({config, env, packageRoot, packageVersion, pluginID, bundleIdentifier});
  },

  async start() {
    (await monitorForMethod()).start();
    diagnostic(`monitoring ${surface} sessions from ${spoolPath(config, env)}`);
    return {};
  },

  async stop() {
    monitor?.stop();
    return {};
  },

  async visit(params) {
    const {visitSession} = await import('./lib/visit.mjs');
    return visitSession({surface, bundleIdentifier, nativeID: params?.nativeID, processID: params?.processID});
  },

  async install() {
    const {installNative} = await import('./lib/client.mjs');
    return installNative({config, env, packageRoot, packageVersion, pluginID, bundleIdentifier});
  },

  async update() {
    const {updateNative} = await import('./lib/client.mjs');
    return updateNative({config, env, packageRoot, packageVersion, pluginID, bundleIdentifier});
  },

  async uninstall() {
    const {uninstallNative} = await import('./lib/client.mjs');
    return uninstallNative({config, env, packageRoot, pluginID});
  },
};

async function handle(request) {
  if (!request || request.version !== 1 || typeof request.method !== 'string') {
    throw new Error('unsupported protocol request');
  }
  const method = methods[request.method];
  if (!method) throw new Error(`unknown method: ${request.method}`);
  return method(request.params ?? {});
}

function shutdown() {
  monitor?.stop();
  monitor = null;
}

const reader = createInterface({input: process.stdin, crlfDelay: Infinity});
let queue = Promise.resolve();

reader.on('line', (line) => {
  if (!line.trim()) return;
  queue = queue.then(async () => {
    let request;
    try {
      request = JSON.parse(line);
    } catch {
      write({version: 1, id: null, error: 'malformed request'});
      return;
    }
    const id = typeof request?.id === 'string' ? request.id : null;
    try {
      const result = await handle(request);
      write({version: 1, id, result: result ?? {}});
    } catch (error) {
      diagnostic(`${request?.method ?? 'request'} failed: ${error?.message ?? error}`);
      write({version: 1, id, error: String(error?.message ?? error)});
    }
  });
});

reader.on('close', () => {
  queue.finally(() => { shutdown(); process.exit(0); });
});

process.on('SIGTERM', () => {
  shutdown();
  process.exit(0);
});
process.on('SIGINT', () => {
  shutdown();
  process.exit(0);
});