# Char 形象包格式

A `.charpet` is a local directory containing manifest and referenced resources. All packages use schemaVersion 2. Optional capabilities, including scripts, audio, themes and tracking, are described in the [appearance API](appearance-api.md). Settings imports and immediately selects the package; selection survives restart. Deleting the selected custom pet restores the built-in `char.default`.

## Manifest

```json
{
  "schemaVersion": 2,
  "id": "studio.my-pet",
  "name": "My pet",
  "appIcon": "icon.png",
  "canvasSize": { "width": 128, "height": 128 },
  "anchor": { "x": 0.5, "y": 0.5 },
  "clips": {
    "idle": { "fps": 24, "frames": ["frames/idle-000.png", "frames/idle-001.png"] },
    "press": { "fps": 24, "frames": ["frames/press-000.png", "frames/press-001.png"] },
    "return": { "fps": 24, "frames": ["frames/return-000.png", "frames/return-001.png"] },
    "depart": { "fps": 24, "frames": ["frames/depart-000.png", "frames/depart-001.png"] },
    "arrive": { "fps": 24, "frames": ["frames/arrive-000.png", "frames/arrive-001.png"] },
    "edgePeek": { "fps": 24, "frames": ["frames/peek-000.png", "frames/peek-001.png"] },
    "edgeHide": { "fps": 24, "frames": ["frames/hide-000.png", "frames/hide-001.png"] }
  }
}
```

The example is a schema illustration; ship actual frames for every path. Use [the complete sample package](../Resources/Skins/example.charpet) as a working starting point.

| Field | Rule |
| --- | --- |
| schemaVersion | Integer `2`. Other values are rejected. |
| id | 2–64 ASCII characters: lowercase letter first, then lowercase letters, digits, `.` or `-`; no `..`. IDs must be unique, including `char.default`. |
| name | Nonempty after trimming whitespace, maximum 80 characters. |
| appIcon | Optional safe relative PNG path; square 128, 256, 512 or 1024 pixels, single-image 8-bit RGBA. Prefer 1024. It has its own size, independent of frame canvas. When omitted, derive a right-edge icon from the final edgePeek frame. |
| canvasSize | Integer width and height, each 32–512 pixels; every frame has this size. |
| anchor | Finite normalized x/y in `[0,1]`, measured from the top left. Renderer places this point at the pet's saved center. |
| clips | The seven named clips above are required; extra named clips are optional; each has 2–120 ordered frame references and finite fps from 1–60. Maximum 2048 references across all clips. |
| frames | Relative `/` paths ending in `.png`. No absolute paths, backslashes, empty components, `.` or `..`. A path may be reused by multiple clips. |

## Frame and package limits

- Each frame is a single-image, **8-bit RGBA PNG** (PNG color type 6). Indexed, RGB-only, grayscale, 16-bit and animated PNGs are rejected. Export in sRGB; pixels outside the character should have alpha zero.
- Maximum 4 MiB per PNG, 128 KiB manifest, 64 MiB entire package, 2200 directory entries and **16,777,216 pixels across unique frames and the authored icon**. Dimensions are checked before bitmap decoding.
- All package files must be `manifest.json` or referenced PNG/audio/script resources allowed by the [appearance API](appearance-api.md); no unused files, links, sockets or native executables. Symlinks are rejected anywhere, including the package directory. All required files must be present and decodable.
- An invalid import, duplicate ID or copied package that changes during import leaves installed skins and selection intact. Import is published by a same-directory rename; selection JSON uses atomic replacement.

## Animation authoring

`idle` loops continuously. Other clips play once and hold their last frame; Char changes back to idle when the interaction finishes. Frame lookup uses seconds since the clip started. Negative/nonfinite time uses frame zero. The renderer applies the app's placement, scale and Reduce Motion policy; imported artwork must not change host reminder growth or bubble hit targets. Host bubbles grow from 44pt to 66pt over five minutes; miniature entries retain compact sizes.

The idle sequence should include breathing, squash/stretch with elastic recovery, a small tilt and a blink. Keep the first and last pose compatible so wrapping is unobtrusive. `press` gives tactile compression; `return` gives a short rebound; `depart` ends transparent/small and `arrive` starts transparent/small, ending at rest. For edge clips, author movement toward/away from the **bottom** of the canvas; the companion renderer can orient it for the selected edge. Keep the anchor stable across every frame and leave padding for overshoot and feet.

Preview edge clips and the settled idle separately. The renderer keeps the edge orientation throughout edge placement, including idle and feedback. The panel-local pet frame is not the screen clipping boundary. See the [actual edge preview coordinates](appearance-development.md#边缘预演的实际坐标) before composing artwork; installed-host behavior must be verified by the user.

Char validates file structure and pixels. It cannot mechanically judge whether breathing, elastic motion or a blink looks good; preview the full sequence before distributing it.

## Included example

`Resources/Skins/example.charpet` contains a cream rounded square, dark outline, two vertical eyes and small round feet, drawn procedurally into transparent Core Graphics canvases. It has 48 idle frames and 16 frames for each interaction at 24 fps (144 PNGs total). Idle includes breathing, tilt and a three-frame blink; transitions use quadratic easing or damped spring sampling. It imports through the same native loader as user packages.

`PetSkinStore.image(for:clip:elapsed:)` returns an `NSImage` for the chosen frame. Built-in `char.default` deliberately returns nil because the app draws that pet as a resolution-independent vector. Its empty clip table is internal metadata and is not a valid import manifest.


Developer walkthrough: [appearance-development.md](appearance-development.md). Complete copyable prompt: [development-prompts.md](development-prompts.md). Validate a real package with: swift run char-package-check skin /absolute/path/your.charpet.

## Software icons

Selecting, importing or restoring an appearance updates the running application icon, menu-bar icon and Settings preview immediately; restart restores the selected artwork. Deleting the selected appearance restores the default. Icons are static cached artwork, not an extra animation loop. An authored appIcon is used as-is; automatic icon derivation rotates the final edgePeek frame from the bottom authoring direction to the right edge and composes it in the default icon tile.

The project logo and pristine installation use the built-in right-edge icon. Char automatically synchronizes a selected appearance's icon into a writable ad hoc installation using a staged, re-signed, strictly verified bundle and a pristine Release backup. Default selection restores the original artwork. This can change Accessibility trust; Developer ID signatures are not silently replaced. Details, failure handling and user checks are in the [外观 API](appearance-api.md#安装图标与预算).

分层形象可用动作的 `trackingFrames` 与 `tracking.states` 同步身体、头部、瞳孔、表情与透明度，详细契约和示例见[外观 API](appearance-api.md#分层动画的同帧同步)。

可选 `features.edgeBoundary` 为贴边位置提供白色渐变边界与柔光，字段/范围见[外观API](appearance-api.md#贴边边界光)。省略时无边界光；使用此字段的包要求配套新版宿主。
