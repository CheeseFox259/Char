# Integration configuration plugins, version 2

Char integrations configure independent **observation** (`workEnd`) and **return** (`returnAdapter`) capabilities. A record may provide either or both. No Agent/source category is needed. Every foreground application except Char can be captured as an application-level return origin, including Agent apps and Warp; importing a plugin is not required for this fallback. Plugins never execute scripts, load libraries, install native hooks, or contact a provider. Native pi, Kimi and DeepSeek bridges still require their separate explicit installations.

## Package

A directory such as `my-terminal.charintegration` contains `manifest.json` and optional PNG assets. The suffix is descriptive; contents are validated. No symbolic links are allowed, total size is at most 8 MiB, and an icon must decode as PNG at most 2048 × 2048 pixels.

```json
{
  "schemaVersion": 2,
  "id": "personal.pi",
  "name": "My pi",
  "workEnd": "pi",
  "bundleIdentifier": "dev.warp.Warp-Stable",
  "icon": "assets/pi.png"
}
```

An exact-return configuration uses `"returnAdapter": "tabbit"` with `"bundleIdentifier": "com.tabbit-ai.Tabbit"`, or `"vscode"` with `"com.microsoft.VSCode"`. A combined record may also specify `workEnd`. `"application"` remains accepted for existing generic configuration packages but is not necessary for origin capture.

| Field | Contract |
| --- | --- |
| `schemaVersion` | Required integer `2`; legacy version `1` is decoded and migrated. |
| `id` | Unique 1–128 ASCII letters, numbers, `.`, `_`, or `-`; begins with a letter or number. |
| `name` | Nonblank display name, at most 100 characters. |
| `bundleIdentifier` | Dotted application bundle ID. Used for observation navigation and optional precise return matching. |
| `workEnd` | Optional supported observation protocol: `claudeCode`, `codexCLI`, `codexDesktop`, `deepseekDesktop`, `kimiCLI`, `kimiDesktop`, `pi`. |
| `returnAdapter` | Optional `tabbit`, `vscode`, or `application`. Precise adapters depend on app permissions and existing bridges. |
| `icon` | Optional relative PNG path inside the package; absolute paths and `.`/`..` components are rejected. |

At least one capability must be present. Two enabled configurations cannot observe the same work end; only one enabled precise return adapter may own a bundle ID. Multiple CLI observers may share Warp, and generic application return does not reserve a bundle ID. This format configures the seven supported protocols; it does not introduce an arbitrary new Agent protocol.

## Migration, store and lifecycle

Version 1 `kind: agent`/`workEnd` and `kind: source`/`sourceAdapter` records decode into the unified capabilities. Legacy combinations remain validated. New writes encode version 2 and omit `kind` and `sourceAdapter`. Legacy installed package manifests remain readable without rewriting the package; registry mutations upgrade the registry atomically. Existing IDs, enabled states, copied assets and removal tombstones persist. Read-only reload does not rewrite user files.

`IntegrationPluginStore(directory:)` creates `registry.json` and `packages/`, initially with seven observers plus Tabbit, VS Code and WeChat configurations. Reopening does not resurrect removed built-ins; restoration is explicit and restores conflicting capabilities disabled. Import validates the full package, conflicts and duplicate IDs before copying assets; failed imports leave published entries and registry unchanged. Installed manifests are immutable: changed manifests must be removed and reimported. Removal commits first, then cleans copied assets; it does not uninstall native bridges or remove Agent data.

Runtime reloads only fully valid catalogs and clears reminders for removed observers. Generic origins survive configuration changes while their original process is live. Exact anchors become invalid when the required precise adapter disappears; temporary adapter query failures preserve them. Failed precise capture falls back to an explicitly application-level anchor. PID-based returns remain navigation fallback and do not mark attention items viewed. The first anchor is retained across visits to other Agents.

## Behavior checks

`Tests/CharCoreChecks/PluginChecks.swift` covers version 1 registry/package migration, tombstones and disabled state, shared-Warp observers, combined capabilities, conflicts, atomic rejection, owned PNG copies and deletion, traversal and symlinks. `Tests/CharPlatformChecks` checks arbitrary and Agent origin capture, PID fallback, precise adapter removal, unavailable precise capture and Char exclusion. `AttentionChecks` verifies the first Agent origin survives another Agent visit and application navigation keeps reminders unviewed. Fixtures use temporary files and mock app controllers; no user profiles or apps are controlled.
