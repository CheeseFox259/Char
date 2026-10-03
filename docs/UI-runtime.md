# Companion runtime

Build the ad hoc signed local bundle with `scripts/build-app.sh`. The resulting executable is `build/Char.app/Contents/MacOS/Char`.

For an isolated visual fixture, run:

```sh
build/Char.app/Contents/MacOS/Char --demo
```

The fixture stays open with three work-end bubbles, two unviewed items per work end, a visible past Codex CLI head, Claude question and Desktop approval glyphs. Click a bubble to produce application fallback and a synthetic WeChat source badge; visit another work end to retain that original source. Right-click a bubble ignores only its head. Click the spark to perform the synthetic degraded return; without Hold it gives a short visual response. Right-click the spark for Settings, Mute, End Hold, and Quit. The spark can be dragged. The settings window contains the graphical legend and native controls.

For the automated fixture smoke check, run:

```sh
build/Char.app/Contents/MacOS/Char --smoke
```

The real native panel opens, fixture actions exercise the engine, and the app exits successfully after checking initial counts, the visible past head, fallback visit, degraded Hold, preservation of the first anchor, head-only ignore, degraded return, and minimum 44-point bubble hit areas. A failed contract exits nonzero. Output contains fixture diagnostics only. It does not establish screenshot quality or physical mouse behavior.

Both fixture modes use a new temporary settings/position directory, injected events, synthetic activation/return and silent sound accounting. They do not create real observer, platform or login services; read harness files; register login; request permissions; inspect source content; open the audio picker; or activate other apps. Showing their own Settings window activates Char itself.

Normal launch creates an `ObservationWorker` actor. It baselines `~/.claude/projects`, `${CODEX_HOME:-~/.codex}/sessions`, and `~/Library/Application Support/Char/harness-hooks.jsonl` off the UI thread. Both optional hook installers should append to this same file. Each 500 ms poll returns one complete event batch, which is ingested before focus and clock advancement. Timer work does not overlap. Agent visits capture the first source before async activation, preserve existing Hold, and release platform tokens when Hold ends. Sound effects use a selected local file or system Ping.

Normal startup reconciles an enabled launch-at-login preference through `LoginItemController`; actual registration/approval status and failures appear in Settings. Accessibility and Tabbit Automation requests require explicit Settings actions. Without an identifiable foreground window display, the panel remains on its current display. With one, the panel follows that display and restores its saved position. Placement changes animate for 180 ms, with a fade under Reduce Motion; controls remain enabled. The transparent nonactivating panel joins Spaces and fullscreen applications.

The custom buttons expose native press actions and descriptive accessibility labels; custom actions provide ignore, Settings, mute and End Hold. Daily drawing contains native symbols and counts, with separate past, fallback, unavailable and source-icon graphics. It contains no prompt or command text.

## Evidence

Verified during implementation: Swift build, release app packaging/signing, and fixture smoke on the local macOS host. The implementation worker did not use CUA or manipulate user apps.

Pending visual/manual verification: native-size screenshot and actual click/right-click/drag paths, settings layout, VoiceOver, exact live Tabbit/VS Code returns, WeChat activation, login approval, focused-display movement, Spaces/fullscreen, and Reduce Motion. Record those results in the final verification note; fixture smoke does not claim these live paths passed.
