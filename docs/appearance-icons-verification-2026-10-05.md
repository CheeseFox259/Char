# Appearance icon verification

Issue: [#17](https://github.com/CheeseFox259/Char/issues/17).

## Verified

- Default project PNG and multi-resolution ICNS exported by native vector generator, inspected at1024px. Body shares the default companion renderer; right-edge clipping, tilt and inset eyes preserve its identity.
- Authored example icon inspected and exported as a sharp1024px RGBA PNG.
- `swift run char-platform-checks`: authored-icon bytes, cached identity, legacy-v1 fallback, restored selection, delete fallback and invalid icon path/missing/RGB/dimensions all passed. Existing platform groups passed.
- `swift run char-package-check skin Resources/Skins/example.charpet`: valid seven-clip package with appIcon.
- Release build and `codesign --verify --deep --strict build/Char.app` passed; CFBundleIconFile points to bundled Char.icns.
- `bash scripts/check.sh` passed all core, observation, platform and native-hook contract groups. Final local app contains both arm64 and x86_64 binaries; it was installed at `~/Applications/Char.app`, its strict signature passed, and the normal instance was launched. User preferences and appearance packages were preserved. The prior installed bundle is backed up locally at `build/Char-before-appearance-icons.app`.
- Final native bundle `--smoke --appearance-icon-check` passed: importing/selecting the authored example changed both application and menu-bar pixel content; deleting it restored both default images and the represented appearance ID. AppKit may rebuild image representations, so the comparison rasterizes both images at 256px and permits less than one 8-bit level of average channel error instead of comparing TIFF serialization.
- Disposable app probe: Finder custom icon API succeeds, then strict signature verification fails with resource-fork/Finder metadata. Runtime uses NSApplication.applicationIconImage and status-bar image; installation/Finder icon stays default.
- Actual installed Settings inspected after unlock: default right-edge icon preview is visible, and existing language, placement, size, distance and launch-at-login preferences are preserved.
- Actual isolated GUI path exercised: Settings → Import appearance → `Resources/Skins/example.charpet` selects Cream Square and displays its authored icon and pet preview; selecting Char restores the default preview. Import testing used disposable demo data. Deletion and restart persistence are covered by native smoke/platform checks, not claimed as GUI checks.
- Finder Get Info inspected for `~/Applications/Char.app`: both icon and Preview show the default right-edge peeking artwork; application is universal. The inspection windows were closed, the demo stopped, and the installed normal instance restored with Settings closed. Its pet was visibly present.

## Verification limits

- Earlier full native smoke stopped at the existing Space-arrival check before reaching icon-selection assertions. The focused icon check above now covers that path independently; this does not turn the earlier full smoke into a pass.
- Menu-bar icon binding is verified by native pixel checks; it was not separately inspected visually in the system menu bar. Earlier locked-screen GUI attempts were followed by the successful unlocked inspection above.
- No new release assets or tag were published for this change. Existing v0.1.0 artifacts remain unchanged.

## Cost

Icons are static, cached per appearance and refreshed only when selection changes; there is no new animation timer. A1024px RGBA image is approximately4MiB decoded, in addition to existing frames/platform image overhead. This is a pixel estimate, not a CPU/GPU benchmark.
