# Integration configuration plugins, version 1

Char integration plugins are local configuration packages. They choose an observation or source adapter already shipped with Char; importing one does not execute scripts, load libraries, install a native hook, or contact a provider. Native pi, Kimi and DeepSeek bridges still require their separate explicit installations.

## Package

A directory named, for example, `my-terminal.charintegration` contains `manifest.json` and optional PNG assets. The suffix is descriptive; the loader validates the contents. No symbolic links are permitted anywhere in the package. The total package limit is 8 MiB. An icon must decode as PNG and be at most 2048 × 2048 pixels.

Agent example:

```json
{
  "schemaVersion": 1,
  "id": "personal.pi",
  "name": "My pi",
  "kind": "agent",
  "workEnd": "pi",
  "bundleIdentifier": "dev.warp.Warp-Stable",
  "icon": "assets/pi.png"
}
```

Source example:

```json
{
  "schemaVersion": 1,
  "id": "personal.browser",
  "name": "My browser",
  "kind": "source",
  "bundleIdentifier": "com.example.browser",
  "sourceAdapter": "application"
}
```

| Field | Contract |
| --- | --- |
| `schemaVersion` | Required integer, exactly `1`. |
| `id` | Required unique ID, 1–128 ASCII letters, numbers, `.`, `_`, or `-`; begins with a letter or number. |
| `name` | Required nonblank display name, at most 100 characters. |
| `kind` | `agent` or `source`. |
| `bundleIdentifier` | Required dotted application bundle ID; segments begin with a letter/number and contain letters, numbers or hyphens. Used for the target application or source match. |
| `workEnd` | Required for an agent; one of `claudeCode`, `codexCLI`, `codexDesktop`, `deepseekDesktop`, `kimiCLI`, `kimiDesktop`, `pi`. Must be absent for a source. |
| `sourceAdapter` | Required for a source; `tabbit`, `vscode`, or `application`. Must be absent for an agent. Exact adapters depend on the installed app, its permissions and existing bridge. `application` retains application-level accuracy. |
| `icon` | Optional relative PNG path inside the package. Absolute paths and `.`/`..` components are rejected. Omit to use the renderer's built-in work-end/app icon. |

This format configures the seven supported protocols; it does not introduce a protocol for an arbitrary new agent. Disable the existing plugin for a work end before importing its replacement. Two enabled agent configurations cannot own the same `workEnd`. Each enabled source owns a unique application bundle ID. Exact Tabbit/VS Code adapters require their respective application bundle IDs; use `application` for other apps.

## Store and lifecycle

`IntegrationPluginStore(directory:)` creates `registry.json` and `packages/`. First creation installs seven agent configurations and Tabbit, VS Code and WeChat sources. The registry persists enabled state and built-in removal tombstones. Reopening the store never resurrects removed built-ins; **Restore built-ins** is explicit. Restoration keeps existing configurations and restores an agent disabled when a user's enabled replacement already owns that work end.

`importPackage(at:)` validates the full manifest and assets, checks duplicate IDs and enabled adapter conflicts, then copies into a private catalog directory. A failed import leaves the registry and published entries unchanged. Registry writes use Foundation atomic replacement. `remove(id:)` first commits removal, then cleans up its copied asset directory. Built-in configuration removal does not uninstall any native bridge or delete the user's agent data.

`setEnabled(_:for:)`, `remove(id:)`, and `restoreBuiltIns()` reload the latest registry before mutation. `reload()` publishes only a fully valid catalog; callers invoke it when the catalog changes or on a polling tick for live configuration updates. Installed packages are immutable: changing an installed manifest in place is rejected; remove and reimport the package instead. Invalid external edits do not replace the store's last valid entries.

Agent unloading and source Hold invalidation are Runtime responsibilities: the catalog reports configuration, while the existing adapters and attention router enforce session and return semantics. Importing a package alone does not replay historical journal records.

## Behavior checks

`Tests/CharCoreChecks/PluginChecks.swift` covers persistent enable state across two stores, explicit restoration after deletion/restart, work-end conflicts, invalid version/identity/adapter fields, atomic registry preservation on rejected import, owned asset copies and deletion, decoded PNG reachability, path traversal and symbolic-link rejection. All fixtures live in temporary directories; these checks do not mutate user profiles.
