# macOS platform integration

The production platform layer is in `Sources/CharPlatform`. It uses app activation for every Claude Code TUI, Codex CLI, and Codex Desktop visit. Warp and Codex visits return `NavigationOutcome.fallback` only after the intended app is observed as frontmost; they never use Warp pane controls or Codex custom URLs. The attention item therefore remains unviewed. If the owning app is missing or activation cannot be verified, the outcome is `unavailable`.

## UI-facing API

`@MainActor MacOSPlatform` exposes:

- `foreground() -> ForegroundSnapshot?`: bundle ID and process ID from the frontmost app; numeric window ID and display ID are optional. With Accessibility authorization it obtains only the focused window's bounds and matches those bounds to a visible numeric window ID. It reads no window title or content. Window/display are nil without a provable focused window.
- `captureSource() -> ReturnAnchor?`: captures before activating an Agent. Returns nil for Warp, unknown apps, missing permissions, or ambiguous/absent optional integrations.
- `activate(workEnd:target:) async -> NavigationOutcome`: activates the owning app and returns `.fallback` or `.unavailable`; the target's untrusted bundle ID does not control which app opens.
- `isAnchorValid(_:)`, `focusContext(for:)`, and `release(_:)`: validate the original running instance and support manual return / closed-source handling. `FocusContext.exactSession` remains nil because the platform cannot prove a native Agent session; `isAgent` identifies a frontmost Warp or Codex app only.
- `returnToSource(_:) async -> NavigationOutcome`: focuses a still-valid exact Tabbit/VS Code target when verified, or activates the same WeChat process as a visibly degraded application return.
- `tabbitAutomationStatus()` and `requestTabbitAutomationPermission() async`: passive check versus explicit prompt-capable settings action. Ordinary bubble clicks never request Automation consent.

`LoginItemController.status` reads actual `SMAppService.mainApp.status`: enabled, disabled, requires approval, or unavailable. `setEnabled(_:)` calls `register()` / `unregister()` only for a packaged `.app`, then returns the actual state. The UI should show `requiresApproval` and direct the user to macOS Login Items settings; a saved preference alone is not proof of registration. [Apple documents that `requiresApproval` needs user action](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval) and that [registering the main app enables launch on later logins subject to approval](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29).

## Return integrations

| Source | Capture and return | Failure rule |
| --- | --- | --- |
| Tabbit | With existing Automation authorization, AppleScript reads the opaque ID of the active tab. On return it searches all current windows for that ID, selects the existing tab, raises its window, then verifies the front tab ID. URL and title are never read. | No capture without authorization or a unique running Tabbit instance. A closed/missing tab is never reopened. |
| VS Code | Optional `integrations/vscode` extension keeps a live editor `Tab` or `Terminal` object behind an in-memory token and serves local JSON over a private Unix socket. It captures only one unambiguous candidate in a focused VS Code window, checks the object remains open, requests reveal, and verifies that exact object is active. | No extension, no focused/unique candidate, multiple VS Code app instances, closed tab, or changed object identity means no exact anchor or an unverified fallback. Editor-area terminal tabs are not claimed supported. |
| WeChat | Stores the frontmost WeChat process ID without inspecting chats. Returns by activating that same still-running process. | `AnchorAccuracy.application` and return `.fallback`; no exact chat claim. A closed/restarted process invalidates it. |
| Warp / unknown | No source anchor. | App activation alone cannot support Hold. |

The VS Code extension uses a user-owned `/tmp/char-vscode-<uid>` directory with mode 0700 and sockets with mode 0600. It sends only operation names, random in-memory tokens, and boolean results. It reads editor resource URI locally to compare the active tab but does not transmit the URI, contents, terminal text, or labels. The [VS Code API](https://code.visualstudio.com/api/references/vscode-api) has no public stable tab ID or direct tab-focus method; both `activeTextEditor` and `activeTerminal` can describe the most recently focused object, so ambiguous capture is rejected. The bridge is optional and is not installed by the build.

Tabbit's Automation check uses `AEDeterminePermissionToAutomateTarget(..., askUserIfNeeded: false)` during ordinary capture. Its explicit permission request uses `true` off the UI thread. The bundled Tabbit scripting dictionary declares unique tab IDs and a writable active tab index; their live behavior still requires a disposable-tab check. `Resources/Info.plist` supplies `NSAppleEventsUsageDescription` for packaged Char.

## Checks and remaining live evidence

Run from the repository root:

```sh
swift run char-platform-checks
npm --prefix integrations/vscode test
swift build
```

The Swift checks inject mock app, Tabbit, VS Code, and login services. They cover owning-app fallback, activation failure, source refusal, exact identity/closed source, WeChat degradation, manual matching, and approval state. Node tests exercise the extension controller against disposable mock tabs and terminals. They do not activate or inspect the user's apps.

**Not run:** live app activation, Tabbit Automation authorization and moved-tab return, VS Code extension inside an isolated Development Host, WeChat process return, actual `SMAppService` registration/approval, multi-display window metadata, or manual return after a source closes. Before release, use disposable content and record exact versus fallback outcomes. The extension can be tried in the isolated Development Host described in `docs/native-navigation-feasibility.md`, changing `--extensionDevelopmentPath` to `integrations/vscode`; no active profile installation is needed for that check.
