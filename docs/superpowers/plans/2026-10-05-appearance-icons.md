# Appearance Icons Implementation Plan

> Execute inline: assets, package contract, runtime binding and product checks form one small change.

**Goal:** Use the default right-edge peeking pet as project/app icon and bind runtime software icons to the selected appearance.

**Architecture:** Shared native body drawing supplies companion and icon. Optional appIcon PNG extends schema v1; old packages derive from their final edgePeek frame. Runtime NSApplication and menu-bar icons follow selection; installation bundles keep their static icon because Finder overrides fail strict signing.

**Tech Stack:** Swift/AppKit/ImageIO, iconutil, SPM.

- [x] Add PetIconArtwork.swift and generate-app-icon.swift; export PNG/multi-resolution ICNS, declare CFBundleIconFile, use PNG in README.
- [x] Add optional appIcon to PetSkinManifest. Validate safe paths, square128/256/512/1024 RGBA and package budgets. Cache icons; derive old-package icons from edgePeek. Test import, restart, deletion and invalid assets.
- [x] Bind refreshSkins/startup to NSApp.applicationIconImage and menu-bar artwork; add Settings preview. Extend native smoke to compare selected/default/restored icons.
- [x] Update format/developer docs and Resources/Skins/AGENTS.md. Run all project checks, universal release build, strict signature and focused native icon smoke. Install final app preserving user skin.
- [x] Inspect actual Settings import/select/default restoration and installed Finder icon after manual unlock; native checks cover deletion, restart persistence and menu-bar binding. Restore installed normal instance.
- [x] Push final verification source without changing immutable v0.1.0 artifacts.

Probe: NSWorkspace.setIcon succeeds on a disposable app, but strict codesign reports resource fork/Finder detritus and Icon\r. Production leaves the signed bundle intact.
