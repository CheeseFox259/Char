# Char pet skin format, version 1

A `.charpet` is a local directory containing `manifest.json` and PNG frames. Char never executes package code. Import completes validation before installing a private copy; importing does not select the package automatically. Selection applies immediately and survives restart. Deleting the selected custom pet selects built-in `char.default`; the built-in vector pet cannot be deleted.

## Manifest

```json
{
  "schemaVersion": 1,
  "id": "studio.my-pet",
  "name": "My pet",
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
| schemaVersion | Exactly `1`; unsupported versions are rejected. |
| id | 2–64 ASCII characters: lowercase letter first, then lowercase letters, digits, `.` or `-`; no `..`. IDs must be unique, including `char.default`. |
| name | Nonempty after trimming whitespace, maximum 80 characters. |
| canvasSize | Integer width and height, each 32–512 pixels; every frame has this size. |
| anchor | Finite normalized x/y in `[0,1]`, measured from the top left. Renderer places this point at the pet's saved center. |
| clips | Exactly the seven named clips above; each has 2–120 ordered frame references and finite fps from 1–60. Maximum 480 references across all clips. |
| frames | Relative `/` paths ending in `.png`. No absolute paths, backslashes, empty components, `.` or `..`. A path may be reused by multiple clips. |

## Frame and package limits

- Each frame is a single-image, **8-bit RGBA PNG** (PNG color type 6). Indexed, RGB-only, grayscale, 16-bit and animated PNGs are rejected. Export in sRGB; pixels outside the character should have alpha zero.
- Maximum 4 MiB per PNG, 64 KiB manifest, 32 MiB entire package, 600 directory entries and **16,777,216 pixels across unique frames**. Dimensions are checked before bitmap decoding.
- All package files must be `manifest.json` or referenced PNG assets; no unused images, links, sockets or executables. Symlinks are rejected anywhere, including the package directory. All required files must be present and decodable.
- An invalid import, duplicate ID or copied package that changes during import leaves installed skins and selection intact. Import is published by a same-directory rename; selection JSON uses atomic replacement.

## Animation authoring

`idle` loops continuously. Other clips play once and hold their last frame; Char changes back to idle when the interaction finishes. Frame lookup uses seconds since the clip started. Negative/nonfinite time uses frame zero. The renderer applies the app's placement, scale and Reduce Motion policy; imported artwork must not change bubble size or hit targets.

The idle sequence should include breathing, squash/stretch with elastic recovery, a small tilt and a blink. Keep the first and last pose compatible so wrapping is unobtrusive. `press` gives tactile compression; `return` gives a short rebound; `depart` ends transparent/small and `arrive` starts transparent/small, ending at rest. For edge clips, author movement toward/away from the **bottom** of the canvas; the companion renderer can orient it for the selected edge. Keep the anchor stable across every frame and leave padding for overshoot and feet.

Char validates file structure and pixels. It cannot mechanically judge whether breathing, elastic motion or a blink looks good; preview the full sequence before distributing it.

## Included example

`Resources/Skins/example.charpet` contains a cream rounded square, dark outline, two vertical eyes and small round feet, drawn procedurally into transparent Core Graphics canvases. It has 48 idle frames and 16 frames for each interaction at 24 fps (144 PNGs total). Idle includes breathing, tilt and a three-frame blink; transitions use quadratic easing or damped spring sampling. It imports through the same native loader as user packages.

`PetSkinStore.image(for:clip:elapsed:)` returns an `NSImage` for the chosen frame. Built-in `char.default` deliberately returns nil because the app draws that pet as a resolution-independent vector. Its empty clip table is internal metadata and is not a valid import manifest.
