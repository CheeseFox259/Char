# Whole-branch review

Reviewed `f5960d4` against `origin/main` (`f5d7d46`). Commands: `git diff origin/main...HEAD` and `git log origin/main..HEAD --oneline`. Standards and Spec were reviewed by separate agents; review was read-only. Fixes were implemented on one branch and merged as `b5a79a7`.

## Standards

No actionable findings. No breaches of AGENTS.md, domain-document rules or settled ADR decisions were found. The implementation preserves domain language, local processing, native-session ownership, the first return anchor and the approved application fallback behavior. No heuristic smell justified a required change.

## Spec

1. **P1 — Missing stop categories.** The spec requests question, approval, turn end, failure, rate limit and context exhaustion. Codex failure/rate/context and Claude context exhaustion currently have no reliable observation path. The capability matrix labels them unavailable; no stop is guessed from text or inactivity. **Open:** the explicit first-release scope question is pending.
2. **P2 — Failed return discarded a valid source.** The spec ends Hold after accurate return, or approved WeChat activation. `completeReturn` previously ended it for unavailable or failed exact returns. **Fixed:** unavailable returns and Tabbit/VS Code fallback preserve the original anchor for retry; exact success and degraded WeChat activation finish Hold. Core acceptance checks cover retry behavior.
3. **P3 — Missing expiry fade.** The spec says the source icon fades quickly and quietly on grace expiry. Previously it disappeared immediately. **Fixed:** the graphical badge fades over 180 ms after actual Hold clears; actions remain available and no sound is emitted. Packaged smoke checks partial/completed fade and click availability.

Standards: 0 findings. Spec: 3 findings, 2 fixed and 1 open; the remaining issue is native signal coverage. Fixture checks do not establish native navigation, audio, login or desktop acceptance. See [verification](verification.md).
