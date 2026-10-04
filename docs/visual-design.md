# Companion visual direction

## Current direction (2026-10-04)

Reference: `docs/reference/visual-motion.png`. The default pet is a cream rounded square with a dark outline, two vertical eyes and round feet. Breathing, squash/rebound, tilt and blink use continuous elastic poses. Desktop placement has a complete bubble ring; four screen-edge placements partially hide the body and keep the orbit on the inward side.

Agent icons are centered in fixed 52-point glossy circular bubbles with gentle elastic deformation. Six ring slots are available; overflow occupies the last slot and exposes at most three miniature bubbles. Wheel cycling and the pet's next/previous menu actions make every work end accessible. Ordinary targets remain at least 44 points; 22-point miniature targets have the full-size cycling alternative and named accessibility controls. Unviewed/running counts and reason/past/fallback marks retain their meanings.

Artwork can be replaced using the strict seven-clip RGBA format in `docs/pet-skin-format.md`. Agent icons can be overridden by PNG configuration assets. Native installed app icons are preferred; CLI clients keep their own identity instead of inheriting a terminal logo.

Cross-display movement exits and re-enters: desktop shrink, edge retraction. Positions are saved as pet centers and placement per display. Manual Space switches use a persistent window policy. Return feedback runs alongside immediate native application activation; whole-Space compositor motion remains controlled by macOS (#15). Reduce Motion freezes continuous poses and uses short fades.

Settings provides placement, selected-skin preview/import/selection/deletion, and immediate Agent/source plugin management. Source removal ends Hold, Agent unloading removes its attention, and deleted built-ins stay deleted until explicitly restored. Runtime evidence and unrun environment cases are recorded in `docs/redesign-verification-2026-10-04.md`.

## Earlier baseline (superseded visual appearance)


Char uses one original rounded teal spark, drawn with native shapes. A dark inset face and two pale eyes give the small silhouette an identifiable expression; the source application's icon occupies a separate small badge during Hold. System fonts render counts; SF Symbols render work ends and reasons. No downloaded asset, web font or generated logo is required.

Daily surfaces use graphics and numbers only. Each work end has one bubble: work-end glyph, the head item's reason, an unviewed count, and separate marks for a past stop and a degraded visit. An application-accuracy Hold also has the degradation mark. Running counts remain visually secondary. Accessible labels describe these controls without displaying conversation or command text.

The companion and bubbles have at least 44-point hit areas. A nonactivating transparent panel preserves the foreground application's keyboard focus until a visit or return action. A normal native settings window provides the graphical legend, timing, sound, login and integration controls. Ordinary companion clicks give a brief visual response; right-click exposes settings, mute and end Hold.

Display placement follows the foreground window's display, never the pointer alone. Dragging updates the remembered position for that display. Relocation lasts about 180 ms and does not disable controls; Reduce Motion uses a short fade. One panel joins Spaces and fullscreen applications.

A runtime visual check must inspect the actual panel, counts, past/degraded feedback and settings at native size. Code and symbol names alone do not establish that the graphics communicate their meaning to a user. Remaining display and comprehension checks belong in the verification note.
