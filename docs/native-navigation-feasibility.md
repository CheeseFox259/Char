# Native navigation feasibility probe (issue #3)

2026-10-03, macOS 26, Apple Silicon. This note records **partial evidence**, not the live acceptance result required by issue #3. The probe reads installed app metadata and Accessibility trust, and uses its own temporary tmux server. It does not activate applications, inspect private tabs/chats, request permissions, or change a user's tmux server.

## Reproduce the observed checks

From the repository root:

```sh
swiftc -o /tmp/char-native-probe tools/native-probe.swift
/tmp/char-native-probe --report
/tmp/char-native-probe --tmux-fixture
```

Observed output on this machine:

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

## Required live paths

| Path | Observed exact outcome | Observed fallback outcome | Next live test and necessary integration |
| --- | --- | --- | --- |
| Warp + tmux Agent pane | **Unverified.** Isolated tmux `select-pane` works; no live Agent pane was targeted. | Unverified. | Install/enable Warp Control in Warp Stable **Settings > Scripting**, then use its installed CLI help and `pane list` / `pane focus` against a disposable Warp + tmux Agent pane. Record the Warp pane ID, tmux pane ID, pre/post focused pane IDs, and whether selection reaches the correct native session. Close its Warp tab only after arranging a disposable fixture; test a new tab attaching to the surviving tmux pane. The bundled `/Applications/Warp.app/Contents/Resources/bundled/skills/warpctrl/SKILL.md` describes a CLI but `warpctrl` is not on PATH here. |
| Codex Desktop chat | **Unverified.** The installed app registers `codex://`. | Unverified. | Create/use a disposable local chat, navigate away, open `codex://threads/<chat-id>`, and verify the app's selected chat ID, not merely foreground app activation. Repeat after moving the chat between windows if that behavior is required. A registered URL scheme alone does not prove this route. |
| Tabbit tab return | **Unverified.** A bundled scripting dictionary exposes window IDs, `active tab`, and `active tab index`. | Unverified. | With a disposable tab, capture its identity through Apple Events, move it to another window, navigate it, then select the same tab and verify its identity. macOS Automation consent for controlling Tabbit may be requested on first use. |
| WeChat chat return | **Unverified.** No scripting dictionary or chat-specific URI was established. | Unverified. | With a disposable chat and Accessibility permission, capture a stable chat identity, switch chats, reselect the original, and verify the selected chat. If no stable identity/focus action exists, revise the first-release exact-return requirement. |
| VS Code editor/terminal tab return | **Live path unverified.** A local extension prototype captures a live text editor `Tab` or `Terminal` object, rejects a closed object, requests focus, then compares the active object. Four mocked tests pass. | Unverified. | Run the prototype in an isolated Extension Development Host with disposable editor and terminal tabs; follow the steps below. Existing editor-area terminal tabs, external activation, and cross-window return remain open. |
| Warp pane return anchor | **Unverified.** | Unverified. | Using Warp Control as above, capture the originating Warp pane ID, visit another pane, focus the original pane, and verify its ID. Separately test the product's allowed fallback to Warp's recent position when that pane no longer exists. |

`AXIsProcessTrusted()` returned `false` for this probe process. A real Accessibility implementation needs user authorization in macOS Privacy & Security > Accessibility; another executable's authorization is not automatically inherited. Apple Events/Automation authorization is separate for Tabbit. Warp Control needs its one-time command installation and enabled Scripting setting in this Stable build. These permissions and integrations must be tested with the eventual char executable, not inferred from this probe.

**Gate status:** open. No exact native focus, exact return, or fallback outcome has been observed on live app content. `docs/spec.md` requires proof before full implementation; paths that fail after live testing need an explicit first-release constraint change before dependent implementation begins.

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
