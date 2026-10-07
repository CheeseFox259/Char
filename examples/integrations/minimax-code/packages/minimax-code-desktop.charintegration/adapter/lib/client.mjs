// Inspect and maintenance of the native MiniMax Code plugin shared by both packages.
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {
  cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, sep} from 'node:path';
import {
  localPluginDirectory, ownerRegistryPath, pluginDataDirectory, pluginPackageDirectory, spoolPath,
} from './config.mjs';

const OWNER_MARKER_SUFFIX = '.char-owner.json';
const DISCOVERY_TIMEOUT_MS = 6000;

/**
 * Content digest of a directory tree, so install can tell "our own package" from a
 * foreign directory that merely shares the name.
 */
export function digestDirectory(root) {
  const hash = createHash('sha256');
  for (const relativePath of walk(root)) {
    hash.update(relativePath.split(sep).join('/'));
    hash.update('\0');
    hash.update(readFileSync(join(root, relativePath)));
    hash.update('\0');
  }
  return hash.digest('hex');
}

function walk(root, prefix = '') {
  let entries;
  try {
    entries = readdirSync(join(root, prefix), {withFileTypes: true});
  } catch {
    return [];
  }
  const files = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) files.push(...walk(root, relativePath));
    else if (entry.isFile()) files.push(relativePath);
  }
  return files;
}

/** The native plugin template shipped inside the Char package. */
export function nativeTemplateDirectory(packageRoot) {
  return join(packageRoot, 'native-plugin');
}

function readOwnerRegistry(path) {
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf8'));
    if (!parsed || typeof parsed !== 'object' || typeof parsed.owners !== 'object') return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeOwnerRegistry(path, registry) {
  writeFileSync(path, `${JSON.stringify(registry, null, 2)}\n`);
}

function ownerMarkerPath(config, env) {
  return `${pluginPackageDirectory(config, env)}${OWNER_MARKER_SUFFIX}`;
}

function lastSpoolWrite(path) {
  try {
    return new Date(statSync(path).mtimeMs).toISOString();
  } catch {
    return null;
  }
}

/** Read-only self check. Never writes, never installs, never reloads the client. */
export async function inspectInstallation({config, env, packageRoot, packageVersion, pluginId, bundleIdentifier}) {
  const target = pluginPackageDirectory(config, env);
  const marker = ownerMarkerPath(config, env);
  const spool = spoolPath(config, env);
  const registry = readOwnerRegistry(marker);
  const detailParts = [`native plugin: ${target}`, `data root: ${localPluginDirectory(config, env)}`];

  if (!existsSync(target)) {
    if (registry) detailParts.push('Char owner record exists but the package directory is missing');
    return {status: 'notInstalled', detail: detailParts.join(' · ')};
  }
  if (!registry) {
    detailParts.push('a directory with this name exists but it is not a Char installation');
    return {status: 'notInstalled', detail: detailParts.join(' · ')};
  }

  let installedDigest = null;
  try {
    installedDigest = digestDirectory(target);
  } catch {
    installedDigest = null;
  }
  const expectedDigest = digestDirectory(nativeTemplateDirectory(packageRoot));
  const lastWrite = lastSpoolWrite(spool);
  detailParts.push(`installed version ${registry.pluginVersion ?? 'unknown'}`);
  detailParts.push(`owners: ${Object.keys(registry.owners ?? {}).sort().join(', ') || 'none'}`);
  detailParts.push(`observation spool: ${spool}${lastWrite ? ` (last event ${lastWrite})` : ' (no event yet)'}`);
  detailParts.push(`bundle: ${bundleIdentifier}`);

  if (registry.contentDigest !== expectedDigest) {
    detailParts.push('the installed files differ from this package; use 更新集成 to restore them');
    return {status: 'unavailable', detail: detailParts.join(' · ')};
  }
  if (installedDigest !== expectedDigest) {
    detailParts.push('the installed files were modified outside Char; use 更新集成 to restore them');
    return {status: 'unavailable', detail: detailParts.join(' · ')};
  }
  if (registry.pluginVersion !== packageVersion) {
    detailParts.push(`this package is version ${packageVersion}; use 更新集成 and reload the client`);
    return {status: 'reloadRequired', detail: detailParts.join(' · ')};
  }
  if (lastWrite) detailParts.push('the client has written Hook events for this installation');
  else detailParts.push('no Hook event yet; start or reload a MiniMax Code session to load the Hook');
  return {status: 'ready', detail: detailParts.join(' · ')};
}

function backupRoot(env) {
  const support = env.CHAR_SUPPORT_DIRECTORY;
  if (typeof support === 'string' && support.trim()) return join(support, 'minimax-code-native-backups');
  return join(mkdtempSync(join(tmpdir(), 'char-minimax-backup-')), 'native');
}

function backUp(target, env, label) {
  const root = backupRoot(env);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const destination = join(root, `${label}-${stamp}`);
  try {
    mkdirSync(dirname(destination), {recursive: true});
    cpSync(target, destination, {recursive: true});
    return destination;
  } catch {
    return null;
  }
}

/** Ask the client itself whether it discovered the package. Never required to succeed. */
async function clientDiscovery(config, env) {
  const binary = config.cliBinary ?? 'mcode';
  const dataDir = localPluginDirectory(config, env).replace(/\/plugins$/, '');
  return new Promise((resolve) => {
    const child = execFile(binary, ['plugin', 'list', '--json'], {
      timeout: DISCOVERY_TIMEOUT_MS,
      env: {...env},
      maxBuffer: 4 * 1024 * 1024,
    }, (error, stdout) => {
      if (error) {
        resolve(`client discovery skipped: ${error.killed ? 'timed out' : error.code ?? error.message}`);
        return;
      }
      try {
        const parsed = JSON.parse(stdout);
        const installed = [...(parsed.installed ?? []), ...(parsed.available ?? [])];
        const entry = installed.find((item) => item?.name === (config.pluginPackageName ?? 'char-observer'));
        resolve(entry
          ? `client discovery: ${entry.pluginId ?? entry.name} installed=${entry.installed} enabled=${entry.enabled}`
          : `client discovery ran (${dataDir}) but did not list the package`);
      } catch {
        resolve('client discovery returned unreadable output');
      }
    });
    child.on('error', () => resolve('client discovery skipped: mcode CLI not found on PATH'));
  });
}

/** Install or refresh the shared native plugin for this package. */
export async function installNative({config, env, packageRoot, packageVersion, pluginID, bundleIdentifier}) {
  const target = pluginPackageDirectory(config, env);
  const marker = ownerMarkerPath(config, env);
  const template = nativeTemplateDirectory(packageRoot);
  const expectedDigest = digestDirectory(template);
  const actions = [];
  let registry = readOwnerRegistry(marker);

  if (existsSync(target) && !registry) {
    return {
      status: 'unavailable',
      detail: `refused to take over ${target}: it exists without a Char owner record`,
    };
  }
  if (existsSync(target) && registry) {
    let current = null;
    try {
      current = digestDirectory(target);
    } catch {
      current = null;
    }
    if (current !== expectedDigest) {
      const saved = backUp(target, env, 'plugin');
      actions.push(saved ? `backed up the previous package to ${saved}` : 'previous package could not be backed up');
      rmSync(target, {recursive: true, force: true});
    }
  }
  mkdirSync(dirname(target), {recursive: true});
  rmSync(target, {recursive: true, force: true});
  cpSync(template, target, {recursive: true});
  const owners = {...(registry?.owners ?? {})};
  owners[pluginID] = packageVersion;
  registry = {
    schemaVersion: 1,
    pluginName: config.pluginPackageName ?? 'char-observer',
    pluginVersion: packageVersion,
    contentDigest: expectedDigest,
    installedAt: new Date().toISOString(),
    owners,
  };
  writeOwnerRegistry(marker, registry);
  actions.push(`wrote ${target}`);
  mkdirSync(pluginDataDirectory(config, env), {recursive: true});
  actions.push(`observation spool: ${spoolPath(config, env)}`);
  actions.push(await clientDiscovery(config, env));
  actions.push('start or reload a MiniMax Code session so the client loads the Hook');
  return {status: 'ready', detail: actions.join(' · '), result: {}};
}

/** Remove this package's ownership, keeping the shared plugin while another owner needs it. */
export async function uninstallNative({config, env, packageRoot, pluginID}) {
  const target = pluginPackageDirectory(config, env);
  const marker = ownerMarkerPath(config, env);
  const registry = readOwnerRegistry(marker);
  if (!registry) {
    return {
      status: 'notInstalled',
      detail: existsSync(target)
        ? `left ${target} untouched: it is not a Char installation`
        : 'no Char installation was found',
      result: {},
    };
  }
  const owners = {...(registry.owners ?? {})};
  delete owners[pluginID];
  const remaining = Object.keys(owners).sort();
  if (remaining.length > 0) {
    registry.owners = owners;
    writeOwnerRegistry(marker, registry);
    return {
      status: 'ready',
      detail: `kept ${target} because other installed packages still use it: ${remaining.join(', ')}`,
      result: {},
    };
  }
  const saved = backUp(target, env, 'plugin');
  rmSync(target, {recursive: true, force: true});
  rmSync(marker, {force: true});
  const spoolDirectory = pluginDataDirectory(config, env);
  rmSync(spoolPath(config, env), {force: true});
  // Preserve files not owned by this integration, including user diagnostics.
  try { rmdirSync(spoolDirectory); } catch (error) {
    if (!['ENOENT', 'ENOTEMPTY', 'EEXIST'].includes(error.code)) throw error;
  }
  return {
    status: 'ready',
    detail: [
      `removed ${target}`,
      `removed owned events.ndjson; retained any unrelated files in ${spoolDirectory}`,
      saved ? `kept a backup at ${saved}` : 'no backup was written',
      'user configuration, sessions and other plugins were not touched',
    ].join(' · '),
    result: {},
  };
}

/** Update is an install that reports which files changed. */
export async function updateNative(context) {
  const before = readOwnerRegistry(ownerMarkerPath(context.config, context.env));
  const outcome = await installNative(context);
  const after = readOwnerRegistry(ownerMarkerPath(context.config, context.env));
  const changed = before?.contentDigest !== after?.contentDigest;
  return {...outcome, detail: `${changed ? 'updated' : 'already current'} · ${outcome.detail}`};
}

export {ownerMarkerPath};