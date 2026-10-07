// Shared configuration and path resolution for the MiniMax Code Char adapters.
import {homedir} from 'node:os';
import {join} from 'node:path';

/** Read the host-provided plugin configuration (a flat string dictionary). */
export function pluginConfig(env = process.env) {
  const raw = env.CHAR_PLUGIN_CONFIG;
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    const result = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value === 'string') result[key] = value;
    }
    return result;
  } catch {
    return {};
  }
}

/**
 * Resolve the MiniMax Code data root.
 * The client derives it from the user's home directory (`<home>/.minimax`) unless
 * MINIMAX_DATA_DIR is set. Nothing here is hard-coded to a developer account.
 */
export function dataDirectory(env = process.env, home = env.HOME || homedir()) {
  const override = env.MINIMAX_DATA_DIR;
  if (typeof override === 'string' && override.trim()) return override.trim();
  if (typeof home === 'string' && home.trim()) return join(home.trim(), '.minimax');
  return join(homedir(), '.minimax');
}

/** Native local-Plugin marketplace directory scanned by every MiniMax Code surface. */
export function localPluginDirectory(config, env = process.env, home = env.HOME || homedir()) {
  return join(dataDirectory(env, home), config.pluginDirectoryName ?? 'plugins');
}

/** Package directory installed inside the local marketplace. */
export function pluginPackageDirectory(config, env = process.env, home = env.HOME || homedir()) {
  return join(localPluginDirectory(config, env, home), config.pluginPackageName ?? 'char-observer');
}

/** Host-owned plugin data directory the Hook writes into (`PLUGIN_DATA`). */
export function pluginDataDirectory(config, env = process.env, home = env.HOME || homedir()) {
  return join(dataDirectory(env, home), 'v2', 'plugin-data', 'hooks', config.pluginPackageName ?? 'char-observer');
}

/** Append-only observation spool written by the client Hook. */
export function spoolPath(config, env = process.env, home = env.HOME || homedir()) {
  return join(pluginDataDirectory(config, env, home), 'events.ndjson');
}

/** Char-owned owner registry for the shared native plugin. */
export function ownerRegistryPath(config, env = process.env, home = env.HOME || homedir()) {
  return join(localPluginDirectory(config, env, home), 'char-observer.owners.json');
}

/**
 * Which client surface this package speaks for.
 * `cli` follows the terminal-hosted mcode process, `desktop` follows the Electron app.
 */
export function surfaceFor(config, workEnd, fallback) {
  const declared = config.surface;
  if (declared === 'cli' || declared === 'desktop') return declared;
  if (typeof workEnd === 'string') {
    if (workEnd.endsWith('.desktop')) return 'desktop';
    if (workEnd.endsWith('.cli')) return 'cli';
  }
  return fallback;
}