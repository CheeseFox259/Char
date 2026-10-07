# Char 0.3.0 — appearance capabilities

- Keeps v1 appearances compatible; introduces optional schemaVersion 2 capabilities.
- Independent desktop/four-edge resources, anchors, rotations, mirrors and idle/feedback clips.
- Native pointer-following eye overlays and directional head poses.
- Hot theme switching, bubble shell/status/font/CLI/highlight/shatter/orbit styling, local audio and cooldown.
- Declarative event bindings and an isolated, bounded JavaScriptCore helper exposing only Char actions.
- Custom click/return/focus/drag/layout preferences and pet hit regions; users can disable package behavior preferences.
- Automatic application/Finder/Launchpad icon synchronization in writable ad hoc installations, with a pristine Release backup and strict re-signing verification. System icon caches still need user acceptance; icon changes may require re-adding Char Accessibility permission. Developer ID installations are not re-signed.
- Full generic appearance developer instructions, v2 API and GUI acceptance steps.

Includes v0.2.2's host fix: custom appearances retain orientation throughout edge peek, settled idle and feedback on all edges.

## Evidence

Required project checks; deterministic v2 package checks; real staged icon signing/restoration on a disposable App; native isolated rendering for variants, themes, tracking, bindings, hit regions and layout; persistent helper state, no OS bridges and infinite-loop timeout. Actual user audio, Finder/Launchpad presentation and custom package acceptance remain user-operated.

Public macOS binaries are universal arm64/x86_64 and ad hoc signed, without a Developer ID/notarization claim.
