#!/usr/bin/env node
/**
 * Build both delivery packages from the single source tree.
 * Every package is rebuilt from scratch so a shipped directory can never drift from
 * the working copy that the tests exercised.
 */
import {cpSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const workspace = dirname(fileURLToPath(import.meta.url));
const nativeVersion = JSON.parse(readFileSync(join(workspace, 'client-plugin', 'char-observer', '.minimax-plugin', 'plugin.json'), 'utf8')).version;
const version = JSON.parse(readFileSync(join(workspace, 'adapter-version.json'), 'utf8')).version;
const iconPath = join(workspace, 'icons', 'minimax-code.png');

const packages = [
  {
    directory: 'minimax-code-cli.charintegration',
    id: 'minimax.code.cli',
    name: 'MiniMax Code CLI',
    bundleIdentifier: 'dev.warp.Warp-Stable',
    clientInterface: 'cli',
    workEnd: 'minimaxcode.cli',
    surface: 'cli',
    capabilities: ['monitor', 'visit', 'lifecycle'],
  },
  {
    directory: 'minimax-code-desktop.charintegration',
    id: 'minimax.code.desktop',
    name: 'MiniMax Code',
    bundleIdentifier: 'com.minimax.agent.cn',
    clientInterface: 'desktop',
    workEnd: 'minimaxcode.desktop',
    surface: 'desktop',
    capabilities: ['monitor', 'visit', 'lifecycle'],
  },
];

for (const spec of packages) {
  const target = join(workspace, 'packages', spec.directory);
  rmSync(target, {recursive: true, force: true});
  mkdirSync(target, {recursive: true});
  cpSync(join(workspace, 'adapter'), join(target, 'adapter'), {recursive: true});
  cpSync(join(workspace, 'native-adapter', 'build', 'minimax-monitor'), join(target, 'adapter', 'minimax-monitor'));
  cpSync(join(workspace, 'client-plugin', 'char-observer'), join(target, 'native-plugin'), {recursive: true});
  cpSync(iconPath, join(target, 'icon.png'));
  const manifest = {
    schemaVersion: 3,
    id: spec.id,
    name: spec.name,
    bundleIdentifier: spec.bundleIdentifier,
    version,
    clientInterface: spec.clientInterface,
    workEnd: spec.workEnd,
    icon: 'icon.png',
    adapter: {
      protocolVersion: 1,
      runtime: 'executable',
      entrypoint: 'adapter/minimax-monitor',
      capabilities: spec.capabilities,
      configuration: {
        surface: spec.surface,
        bundleIdentifier: spec.bundleIdentifier,
        pluginPackageName: 'char-observer',
        cliBinary: 'mcode',
        nativePluginVersion: nativeVersion,
      },
    },
  };
  writeFileSync(join(target, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  const bytes = sizeOf(target);
  if (bytes > 8 * 1024 * 1024) throw new Error(`${spec.directory} exceeds the 8 MiB package limit: ${bytes}`);
  process.stdout.write(`${target} (${bytes} bytes)\n`);
}

function sizeOf(root) {
  let total = 0;
  for (const entry of readdirSync(root)) total += entrySize(join(root, entry));
  return total;
}

function entrySize(path) {
  const stats = statSync(path);
  if (stats.isDirectory()) {
    let total = 0;
    for (const entry of readdirSync(path)) total += entrySize(join(path, entry));
    return total;
  }
  return stats.size;
}