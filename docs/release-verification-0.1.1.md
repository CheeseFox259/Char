# v0.1.1 release verification — October 6, 2026

Delivery issue: #18. User requested a published release installed in `/Applications`, without installing a local build.

## Build provenance

Tag `v0.1.1` targets `5f789f65e6ca35364e57e395596da1c4708c7a13`. `.github/workflows/release.yml` uses a GitHub-hosted macOS runner for checks and universal packaging. It uploads a draft only after project checks, signature, archive hashes, both architectures and DMG verification pass.

## Initial remote failures

- Run `37340621886` failed with a Swift 6.1.2 type-check timeout in the nested bubble-layout expression. The fix adds explicit Slot/Double/CGFloat types and divides mini-frame arithmetic without changing its geometry.
- Run `37340992288` passed project checks and universal packaging, then failed because the lipo verification command placed the filename after variable-length architecture arguments. The workflow now checks the explicit architecture list. Signature and archive hashes had already passed in this run.
- Duplicate run `37340993332` was cancelled. The unpublished tag was advanced for these fixes before any v0.1.1 assets were published; v0.1.0 is unchanged.

## Installation preparation

- The old app was installed at `~/Applications/Char.app`; `/Applications/Char.app` was absent.
- Old bundle backup: `build/installation-backups/2026-10-06/Char-before-release.zip`.
- User-data backup: `build/installation-backups/2026-10-06/Char-user-data`. Existing user data remains at `~/Library/Application Support/Char`.
- Preserved preferences include Chinese and launch-at-login enabled.

## Verified

- GitHub Actions run `37341604302` completed successfully at `2026-10-05T16:39:37Z`: project checks, universal release build, downloadable archive verification and draft upload all passed. Source SHA matches the tag above.
- Release `v0.1.1` was publicly published at `2026-10-05T16:41:45Z` (October 6, 2026, 00:41:45 Asia/Shanghai). `gh release view` confirms `isDraft: false`, with ZIP, DMG and SHA256SUMS assets.
- Downloaded attachments from GitHub to `build/downloaded-releases/v0.1.1/`; `shasum -a 256 -c SHA256SUMS` passes for both archives. ZIP SHA256: `f6565aad5f52f6468d91f170b87e46cbfe463798e7385478e97bddcea2f36585`; DMG SHA256: `06f52c7106c95c157a439d50185b2fd85057509d188e3f226a6c503091c16225`.
- ZIP extraction, `hdiutil verify` of the DMG, strict deep codesign verification, and arm64/x86_64 inspection of both `Char` and `char-hook` passed.
- Downloaded bundle `--smoke --appearance-icon-check` passed using disposable data: appearance icon selection, status-bar icon switching and deletion restoring the default.
- Installed the downloaded bundle at `/Applications/Char.app`, version `0.1.1`, build `2`. No local build was installed. `codesign --verify --deep --strict /Applications/Char.app` and `diff -qr` against the extracted release bundle pass.
- Stopped the old process, moved its bundle to `build/installation-backups/2026-10-06/Char-before-release.app.disabled`, and launched `/Applications/Char.app`. Process inspection confirms one normal instance, running from the system Applications directory; the old `~/Applications/Char.app` path is absent.

## Installed GUI verification

After the user unlocked the Mac, CUA inspected the running `/Applications/Char.app`:

- Desktop companion was visible. Settings opened through its accessibility action and were closed after inspection.
- Language remained Chinese; placement remained right edge, size 48 pt, bubble distance 18 pt. Built-in integrations stayed enabled.
- Appearance selection was Char. The software-icon preview showed the default pet peeking from the right edge.
- Launch-at-login toggle was on and runtime status displayed enabled. No ServiceManagement registration error was shown. This verifies registration, not an actual logout/login.
- Accessibility displayed not authorized (optional), and Tabbit Automation displayed authorization required for this installed identity. No permission prompts were initiated during this check; accurate Tabbit return requires reauthorization.

All delivery checks are complete.

## Limits

Ad hoc signing only; no Developer ID or notarization. Runtime software/status-bar icons follow appearance; Finder/Launchpad uses the bundle default. Earlier full native smoke stopped at Space-arrival; this delivery uses the focused appearance-icon check rather than claiming that full smoke passed. No Intel hardware test, true logout/login or new performance benchmark.
