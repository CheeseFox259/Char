# Whole-branch review

Reviewed `f5960d4` against `origin/main` (`f5d7d46`). Commands: `git diff origin/main...HEAD` and `git log origin/main..HEAD --oneline`. Standards and Spec were reviewed by separate agents; review was read-only. Fixes were implemented on one branch and merged as `b5a79a7`.

## Standards

No actionable findings. No breaches of AGENTS.md, domain-document rules or settled ADR decisions were found. The implementation preserves domain language, local processing, native-session ownership, the first return anchor and the approved application fallback behavior. No heuristic smell justified a required change.

## Spec

1. **P1 — Missing stop categories.** The spec requests question, approval, turn end, failure, rate limit and context exhaustion. Codex failure/rate/context and Claude context exhaustion currently have no reliable observation path. The capability matrix labels them unavailable; no stop is guessed from text or inactivity. **Open:** the explicit first-release scope question is pending.
2. **P2 — Failed return discarded a valid source.** The spec ends Hold after accurate return, or approved WeChat activation. `completeReturn` previously ended it for unavailable or failed exact returns. **Fixed:** unavailable returns and Tabbit/VS Code fallback preserve the original anchor for retry; exact success and degraded WeChat activation finish Hold. Core acceptance checks cover retry behavior.
3. **P3 — Missing expiry fade.** The spec says the source icon fades quickly and quietly on grace expiry. Previously it disappeared immediately. **Fixed:** the graphical badge fades over 180 ms after actual Hold clears; actions remain available and no sound is emitted. Packaged smoke checks partial/completed fade and click availability.

Standards: 0 findings. Spec: 3 findings, 2 fixed and 1 open; the remaining issue is native signal coverage. Fixture checks do not establish native navigation, audio, login or desktop acceptance. See [verification](verification.md).

## Issue / PR follow-up, 2026-10-03

Reviewed PR #2's current local head `5d33027` against its base `f5d7d46`; the remote head matched the local checkout. Two independent read-only review agents checked Standards and Spec.

- **Standards:** no documented-rule breaches or justified heuristic refactors. A concrete P2 observation bug was found: an older delayed stop changed the poller's dedup state even though the router rejected its timestamp, causing the next valid stop to be discarded. **Fixed:** keep a per-session event timestamp watermark, including duplicate states. The poller/router regression failed with `a delayed old stop suppressed the new attention item` before the fix and passes after it.
- **Spec:** a P2 Hold bug was found: a transient Tabbit query failure or VS Code bridge timeout was treated as confirmed source closure. **Fixed:** source validity is true / false / unknown; only confirmed invalidity clears Hold. Unknown validity refuses return without discarding the source. The platform regression failed with `Temporary Tabbit query failure invalidated a live source` before the fix and checks query recovery for both integrations.
- **Still open:** P1 native signal coverage (Codex failure/rate/context and Claude context exhaustion). No approved scope reduction is recorded. Issues #1 and #5 remain open for that decision or a supported observation implementation.
- **Issue closure:** #6 has deterministic acceptance evidence; #7 has implementation/platform contracts with live paths assigned to #9. They may close when PR #2 merges. #4, #8 and #9 remain open for their actual login/settings/input/desktop acceptance. #10–12 remain deferred exact-navigation work.

PR #2 remains a draft. Its closing references cover #6 and #7 only; implementation, controlled checks and remaining release acceptance are stated separately.
