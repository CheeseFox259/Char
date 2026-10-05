# Appearance icon verification

Issue: [#17](https://github.com/CheeseFox259/Char/issues/17).

## Verified

- Default project PNG and multi-resolution ICNS exported by native vector generator, inspected at1024px. Body shares the default companion renderer; right-edge clipping, tilt and inset eyes preserve its identity.
- Authored example icon inspected and exported as a sharp1024px RGBA PNG.
- `swift run char-platform-checks`: authored-icon bytes, cached identity, legacy-v1 fallback, restored selection, delete fallback and invalid icon path/missing/RGB/dimensions all passed. Existing platform groups passed.
- `swift run char-package-check skin Resources/Skins/example.charpet`: valid seven-clip package with appIcon.
- Release build and `codesign --verify --deep --strict build/Char.app` passed; CFBundleIconFile points to bundled Char.icns.
- Disposable app probe: Finder custom icon API succeeds, then strict signature verification fails with resource-fork/Finder metadata. Runtime uses NSApplication.applicationIconImage and status-bar image; installation/Finder icon stays default.

## Pending

- Full native smoke stopped at the existing Space-arrival check before reaching icon-selection assertions. Mac was found locked on subsequent GUI access; this is not counted as a successful smoke or an icon-specific failure diagnosis.
- Actual Settings import/select/restart/delete, menu-bar appearance, installed Finder icon and final normal-instance restoration await manual unlock. The prior installed v0.1.0 is still the normal running application.
- No new release assets or tag were published for this change. Existing v0.1.0 artifacts remain unchanged.

## Cost

Icons are static, cached per appearance and refreshed only when selection changes; there is no new animation timer. A1024px RGBA image is approximately4MiB decoded, in addition to existing frames/platform image overhead. This is a pixel estimate, not a CPU/GPU benchmark.
