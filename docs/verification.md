# Product verification

插件与新桌宠视觉的本轮记录见 [2026-10-04 视觉扩展验收](redesign-verification-2026-10-04.md)。这轮与此前原生集成验收分别记录；整屏 Space 动画边界单独跟踪 #15。

新增工作端与回城的本轮记录见 [2026-10-04 扩展验收](acceptance-2026-10-04.md)。七工作端实现与最终组合检查已完成；实体 Ctrl+B / Tabbit 原标签回城及延迟修复有用户反馈和原生计时。使用者已批准已确认信号的首版范围。原生客户端、桌面环境未运行项单列；不能把演示跳转视为真实应用跳转。

上一轮用户请求的基线验收记录见 [2026-10-03 当前完成部分验收](acceptance-2026-10-03.md)。本次补充了实际 CUA 输入、设置图例、正常应用的 Warp/Codex 激活，以及正常设置退出/重启保留和本地音频选择。使用者反馈“可以正常使用”，临时运行数据已清理。该基线的原生类别范围决定已在 2026-10-04 获批准；未完成的实机检查仍保留。下文为此前记录，其中锁定阻塞和部分未运行项已被本次续验更新；请以最新报告为准。

2026-10-03, macOS 26, Apple Silicon, Swift 6.3.2 Command Line Tools. This note distinguishes deterministic contracts, fixture application paths, native integrations and distribution checks. Review readiness does not mean every release acceptance path has been run.

## Verified

- `scripts/check.sh`: 4 persisted-settings checks, 16 attention/Hold checks, 7 local observation contract groups, 8 platform contract groups, and 4 VS Code extension tests pass. The issue/PR follow-up reran this command after both P2 fixes; their new regressions failed before the fixes and passed afterward. The executable checks exit nonzero on failure; no XCTest installation is required.
- The same command runs both actual Python hook installers against disposable settings with an existing hook and an unrelated preference. Repeated installation is idempotent. Executing their generated commands produces a shared normalized stream with correct Claude/Codex Desktop identity, no harness-facing output, no prompt/command sentinel text, and file mode 0600. No user harness configuration is changed.
- `swift build` compiles the integrated core, observer and platform modules. `scripts/build-app.sh` produces the final release bundle, and `codesign --verify --deep --strict --verbose=2 build/Char.app` passes.
- Local record shapes were inspected for structured keys and enums only. Codex Desktop question call/output and turn markers have representative contracts. Historical records are baselined, incomplete lines wait for completion, child/remote records are skipped, and a complete sleep/wake batch precedes attention-clock advancement.
- Platform mocks verify owning-app visits return fallback, preserve unviewed attention, refuse missing/ambiguous exact sources, validate source lifetime and degrade WeChat application return. Temporary Tabbit/VS Code source-query failures return unknown rather than confirmed closure, refuse an unverified return and allow a later retry. These mocks do not prove a real app switched.

## Runtime evidence

`build/Char.app/Contents/MacOS/Char --smoke` opens the actual native companion and exits zero after fixture visit/ignore/return checks. It checks three work ends, visible past head, fallback with unviewed retention, first-source preservation, degraded return, hit areas, quiet 180 ms source-badge fade and click availability during that fade. The final post-review package passed this check. Navigation is synthetic; this is not native Warp/Codex/WeChat activation evidence.

`build/Char.app/Contents/MacOS/Char --demo` was launched for native-size visual and physical-input acceptance. CUA could not inspect it because the Mac was locked and automatic unlock failed. The test fixture was stopped through its own terminal; no user app or harness was changed. Screenshot, mouse/right-click/drag, and settings-layout acceptance are **Blocked pending manual unlock**, not passed.

The issue/PR follow-up rebuilt the final package, reran `--smoke`, and verified the ad hoc signature successfully after both fixes. CUA initially resolved the name Char to another worktree's package; that inspection is not evidence for this checkout. Its subsequent input attempt reported a locked Mac. The fixture started for this follow-up and the package started by that name lookup were stopped; pre-existing fixture processes were left alone. Final-package mouse and layout acceptance remains blocked.

## Not run

- Live Claude/Codex hook approval lifecycle and Codex CLI rollout acceptance. Native signal coverage and unavailable categories are listed in [observation integration](observation-integration.md); unknown reason and absence of a stop signal are different cases.
- Native owning-app activation through the final companion, live WeChat return, Tabbit moved/navigated/closed-tab return with Automation authorization, and VS Code editor/terminal return inside a disposable Extension Development Host.
- Login registration/approval and an actual logout/login cycle; saved launch-at-login preference alone is not evidence of registration.
- Multiple displays, multiple Spaces, fullscreen app visibility, Reduce Motion enabled at system level, screen placement during live focused-window changes, and a user comprehension check of the graphical legend.
- Audible system/custom audio playback and application settings behavior through an actual quit/relaunch cycle beyond the persisted store contract.
- Runtime packet capture. Source inspection and local stream checks establish the implemented local data path; they are not a packet-level audit.

## Blocked / deferred

- Native visual/input acceptance is blocked by the locked Mac. Manual unlock is requested; no alternate screenshot or UI-control route was attempted.

- Exact Warp pane navigation/reattachment and exact Warp source capture are outside the approved first-release scope ([#10](https://github.com/CheeseFox259/Char/issues/10)); no usable Warp Control endpoint was established on the installed Stable build.
- Exact Codex chat and WeChat chat return are outside the approved first-release scope ([#11](https://github.com/CheeseFox259/Char/issues/11), [#12](https://github.com/CheeseFox259/Char/issues/12)). A browser security rejection of a custom Codex URI was not bypassed.
- Codex failure/rate/context stops and Claude context exhaustion currently lack reliable observer signals. The capability matrix records them as unavailable, never as inferred unclassified events.

## Not applicable

Cloud/SSH sessions, remote synchronization, telemetry, Agent process ownership, Linux/Windows support and responding to prompts from the companion are outside the specification. Developer ID distribution signing and notarization are not part of this source PR; the build script produces an ad hoc signed local bundle.

## Reproducible remaining acceptance

Record the package commit, OS, permissions and actual outcome for each item. A fixture proves only the fixture path; use disposable native content for live integration checks.

- [ ] Unlock the Mac, run `build/Char.app/Contents/MacOS/Char --demo`, and check three bubbles at native size. Click two different work ends: each item stays unviewed with fallback, and the first source badge stays fixed. Right-click a bubble: only its head disappears. Click the pet: return clears Hold and fades the badge. Drag the pet, open its Settings menu, check the complete legend and control layout, then quit the fixture.
- [ ] Launch the normal packaged app from a stable path. Change threshold, grace, mute and local audio choice, quit and relaunch, and observe the saved values and behavior. Enable/disable login launch through Settings and check actual macOS approval state; after authorization perform a logout/login cycle. Restore the chosen final preferences.
- [ ] Observe disposable Claude Code, Codex CLI and Desktop root sessions created both before and after Char starts. Check new question/approval/turn events through supported local records or explicitly installed hooks; verify a response resumes the same item, startup history does not replay, child events are skipped, and sleep/wake batches reflect the final state. Record unsupported categories as unsupported, not passed.
- [ ] From an authorized disposable Tabbit tab, click a bubble, move/navigate the same tab, then return with the pet and compare tab identity. Repeat with manual return, actual tab closure and a temporary integration failure: closure clears Hold, failure preserves it and allows retry. With no capture authorization, verify no Hold.
- [ ] Use a disposable VS Code Extension Development Host with `--extensionDevelopmentPath=integrations/vscode`. Repeat capture/return/manual-return/closure for an unambiguous editor and terminal. Temporarily stall the bridge with the original source still open, verify Hold remains, restore the bridge and retry. Ambiguous capture must create no Hold.
- [ ] From WeChat, visit two work ends and return: activation goes to the same running app instance with fallback; no exact-chat claim is made. Warp sources create no Hold. All work-end visits preserve unviewed attention because navigation is application-level.
- [ ] On multiple displays, move the focused window and check saved per-display pet positions and clicks during relocation. Check multiple Spaces/fullscreen, system Reduce Motion, VoiceOver actions, actual system/custom audio and mute. Ask a user to identify the reason/past/fallback/source glyphs with the legend, and record the comprehension result.
