# Native navigation feasibility probe (issue #3)

2026-10-03, macOS 26, Apple Silicon. This note records **partial evidence**, not the live acceptance result required by issue #3. The Swift probe reads installed app metadata and Accessibility trust, and uses its own temporary tmux server. It does not activate applications, inspect private tabs/chats, request permissions, or change a user's tmux server. The later VS Code prototype has only been mock-tested, not installed or run in VS Code.

## Reproduce the observed checks

From the repository root:

```sh
swiftc -o /tmp/char-native-probe tools/native-probe.swift
/tmp/char-native-probe --report
/tmp/char-native-probe --tmux-fixture
```

Observed output from the initial run (Warp 0.2026.09.02.08.27.01):

```text
Accessibility trusted: false
tmux executable: /opt/homebrew/bin/tmux
warpctrl executable: absent
Warp: version=0.2026.09.02.08.27.01, bundle=dev.warp.Warp-Stable, schemes=warp
Warp bundled SKILL.md: true
Codex Desktop: version=26.924.22138, bundle=com.openai.codex, schemes=codex,http,https
Tabbit: version=1.15.17.0, bundle=com.tabbit-ai.Tabbit, schemes=file,http,https,tabbit-intl-browser
Tabbit bundled scripting.sdef: true
WeChat: version=4.1.15, bundle=com.tencent.xinWeChat, schemes=wechat,weixin,xweixin
WeChat bundled scripting.sdef: false
VS Code: version=1.85.2, bundle=com.microsoft.VSCode, schemes=vscode
VS Code bundled scripting.sdef: false
Capability metadata only; no exact app navigation or return path is established by this report.
Isolated tmux pane selection: PASS (first=%0, selected=%1, active=%1)
This does not focus a Warp tab or establish reattachment after tab closure.
```

The pane IDs are allocated by the temporary tmux server and may differ on another run. The fixture starts a detached session with two `sleep 30` panes, selects the second pane by its ID, verifies the active pane ID, then kills only that isolated server. No existing Agent pane is used.

After Warp updated to Stable 0.2026.09.30.08.29.01, the same `swiftc` and `--report` commands showed `Accessibility trusted: true`, `warpctrl executable: absent`, and the new Warp version. A read-only `tmux list-sessions` showed `warp-test: 3 windows (attached)`; live tmux panes now exist, but their existence does not provide Warp pane focus. The user reported that this Stable build has no Warp Control wrapper, no **Settings > Scripting** toggle, and no local-control endpoint. None of these observations proves an exact native navigation path.

## Current scope and remaining live paths

| Path | Observed exact outcome | Observed fallback outcome | Next live test and necessary integration |
| --- | --- | --- | --- |
| Warp + tmux Agent pane | **Not available on the tested Stable build.** Isolated tmux `select-pane` works, and a live tmux session exists, but no Warp pane control route was established. | **First-release requirement:** activate Warp's recent location, show graphical degradation, and leave the attention item unviewed. The product fallback itself still needs live verification. | Exact Warp pane focus and automatic reattachment after a Warp tab closes are deferred. Reconsider only when a working Warp control path or another exact method is available and verified against a disposable native session. The bundled Warp Control skill describes a different capability from what this Stable installation exposes. |
| Codex Desktop chat | **Deferred to [#11](https://github.com/CheeseFox259/Char/issues/11).** A registered scheme is not proof of chat selection. | First release activates Codex, displays degradation and keeps the item unviewed. Product runtime verification remains required. | The custom-scheme browser attempt was security-blocked; no alternate route was retried. Any future precise capability needs an independently supported integration and selected-chat identity evidence. |
| Tabbit tab return | **Unverified.** A bundled scripting dictionary exposes window IDs, `active tab`, and `active tab index`. | Unverified. | With a disposable tab, capture its identity through Apple Events, move it to another window, navigate it, then select the same tab and verify its identity. macOS Automation consent for controlling Tabbit may be requested on first use. |
| WeChat return | **Exact chat return deferred to [#12](https://github.com/CheeseFox259/Char/issues/12).** A permitted Accessibility view exposed no stable chat identity. | First release retains a degraded, still-running application-instance anchor. Returning activates its recent location and ends Hold. | Verify activation, process-lifetime validity, degraded graphics and manual application return. No chat selection is promised. |
| VS Code editor/terminal tab return | **Live path unverified.** A local extension prototype captures a live text editor `Tab` or `Terminal` object, rejects a closed object, requests focus, then compares the active object. Four mocked tests pass. | Unverified. | Run the prototype in an isolated Extension Development Host with disposable editor and terminal tabs; follow the steps below. Existing editor-area terminal tabs, external activation, and cross-window return remain open. |
| Warp pane return anchor | **Not established on the tested Stable build.** | App activation alone cannot form an accurate Hold anchor. | First release does not create Hold when a Warp source is known only at app level. Exact Warp pane capture/return is deferred. If a future exact anchor later becomes unavailable, Warp recent-location fallback may end Hold with graphical degradation. |

`AXIsProcessTrusted()` returned `false` on the first probe and `true` on the later run. Trust alone did not expose WeChat chat identity or Warp pane control. A real Accessibility implementation still needs authorization for the eventual char executable in macOS Privacy & Security > Accessibility; another executable's authorization is not automatically inherited. Apple Events/Automation authorization is separate for Tabbit. The previously assumed Warp Control installation/Scripting path is absent on the tested Stable build.

**First-release scope decision:** the user approved application-level graphical degradation for Codex Desktop and WeChat after the Warp scope revision. All work-end visits now activate only the owning application recent location and preserve the attention item. WeChat return uses a clearly degraded application-instance anchor; exact chat identity is deferred. Tabbit and VS Code capture remain optional and must verify a live exact source before establishing an exact Hold. The original exact-navigation gate is resolved by this explicit scope revision, not by claiming the unrun exact tests passed. Runtime activation, supported return integrations, and desktop behavior are verified during implementation and recorded in the product verification note.

## VS Code extension prototype

`tools/vscode-anchor-probe` is an unpackaged, in-memory extension. It adds three commands: **Char Probe: Capture Editor Tab**, **Char Probe: Capture Terminal Tab**, and **Char Probe: Return to Captured Tab**. It does not install into the user's VS Code profile, read file/terminal contents, or expose a local service. Run its focused mock checks with:

```sh
cd tools/vscode-anchor-probe
npm test
```

Observed: 4 tests passed. They cover selecting the same editor `Tab` object, refusing to reopen a closed editor tab, declining to claim exact focus when another tab stays active, and selecting/refusing a live/closed `Terminal` object. These mocks prove the prototype's guards and result reporting, not VS Code's live focus behavior.

The [official VS Code Extension API](https://code.visualstudio.com/api/references/vscode-api) defines `window.tabGroups`, `TabGroup.activeTab`, `TabInputText.uri`, `window.showTextDocument`, `window.activeTerminal`, `window.terminals`, and `Terminal.show`. The installed VS Code 1.85.2 API declaration is at `/Applications/Visual Studio Code.app/Contents/Resources/app/out/vscode-dts/vscode.d.ts` (notably `TabInputTerminal` at line 17777 and `Tab` at line 17789). `Tab` has no public stable identifier or focus method; `TabGroups` exposes `close` but no tab selection method. `TabInputTerminal` supplies no terminal identity. The prototype keeps object references for this extension-host lifetime, checks that the object still exists, and verifies identity after `showTextDocument` or `Terminal.show`. It reports “unverified” if VS Code reveals another object.

### Isolated live test still required

Launch a separate Extension Development Host with fresh profile and extensions directories. These commands create only disposable fixture files and a separate VS Code profile; they have **not** been run in this investigation:

```sh
probe_root=$(mktemp -d /tmp/char-vscode-probe.XXXXXX)
mkdir -p "$probe_root/workspace" "$probe_root/profile" "$probe_root/extensions"
printf 'first\n' > "$probe_root/workspace/first.txt"
printf 'second\n' > "$probe_root/workspace/second.txt"
'/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' \
  --new-window \
  --user-data-dir "$probe_root/profile" \
  --extensions-dir "$probe_root/extensions" \
  --extensionDevelopmentPath="$(pwd)/tools/vscode-anchor-probe" \
  "$probe_root/workspace"
```

From the repository root, open `first.txt` in that window, run **Capture Editor Tab** from the Command Palette, switch to `second.txt`, and run **Return to Captured Tab**. Record whether `first.txt`'s *existing* tab is selected and the command says `Exact editor tab selected`. Then close `first.txt` and repeat Return; it must say the original is closed without reopening it. Create two disposable integrated terminals, capture one with **Capture Terminal Tab**, switch to the other, return, and verify both the visible selected terminal and `Exact terminal selected`. Close the captured terminal and verify that Return refuses it. Repeat with a moved editor tab and an editor-area terminal tab to expose API limits. Finally test activation from another app/window through a future external bridge; this prototype has no such bridge.

This is evidence for one potential VS Code integration, not a working char return path. In particular, extension state vanishes on host restart; the editor identity can become unverifiable if VS Code replaces its `Tab` object; `Terminal.show()` is documented to reveal a terminal but does not by itself prove the correct OS window was activated. No ability to focus an editor-area `TabInputTerminal` by identity is established here.
