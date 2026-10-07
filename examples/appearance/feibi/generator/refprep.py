#!/usr/bin/env python3
"""Key the white-background reference into straight-alpha RGBA and locate the eye rig.

The plate is near-white with sensor noise, and the character itself contains
enclosed near-white regions (hat crown, shirt). Keying therefore runs as a
border flood fill on neutral near-white pixels, never a global colour test, so
enclosed whites stay opaque. Only the one-pixel band touching the flood region
is recomputed from an ink-over-white mix model, which restores the anti-aliased
outline without eroding light skin.

Usage: refprep.py <work-dir>

Outputs:
  <work>/reference/keyed-cutout.png    native-resolution cut-out, straight alpha
  <work>/reference/keyed-checker.png   checkerboard composite for visual review
  <work>/reference/eye-detect.png      face crop with detected eye boxes
  <work>/reference/analysis.json       bounding box, palette, eye boxes
"""

import json
import os
import sys

import numpy as np
from PIL import Image
from collections import deque

NEUTRAL_SLACK = 8        # max-min channel spread still counted as the plate
PLATE_MIN = 248          # darkest plate pixel accepted by the flood fill
BAND = 2                 # half-width of the anti-alias repair band
INK_MIN = 22             # darkest channel of the outline used by the mix model
LAYERS = 3               # components used for the flood (1 image, 2 eyes)


def load_rgb(path):
    return Image.open(path).convert("RGB")


def flood_from_border(plate):
    """Return a boolean mask of plate pixels reachable from the image border."""
    h, w = plate.shape
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if plate[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if plate[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and plate[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def band(mask, radius):
    out = mask.copy()
    for _ in range(radius):
        grown = out.copy()
        grown[1:, :] |= out[:-1, :]
        grown[:-1, :] |= out[1:, :]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def key(rgb):
    """Straight-alpha cut-out of a near-white plate."""
    a = np.asarray(rgb).astype(np.int16)
    spread = a.max(axis=2) - a.min(axis=2)
    plate = (a.min(axis=2) >= PLATE_MIN) & (spread <= NEUTRAL_SLACK)
    outside = flood_from_border(plate)

    alpha = np.full(a.shape[:2], 255, dtype=np.float64)
    alpha[outside] = 0.0

    # Repair the anti-aliased outline: inside the band the pixel is a mix of ink
    # and plate, so alpha follows the darkest channel linearly.
    ring = band(outside, BAND) & ~outside
    darkest = a.min(axis=2).astype(np.float64)
    mix = np.clip((INK_MIN - darkest) / (INK_MIN - 255.0), 0.0, 1.0)
    alpha = np.where(ring, mix * 255.0, alpha)

    rgba = np.dstack([a.astype(np.uint8), alpha.round().astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA"), outside


def components(mask, min_pixels=200):
    """Connected components of a boolean mask, largest first."""
    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    out = []
    current = 0
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or labels[y, x]:
                continue
            current += 1
            size = 0
            x0 = x1 = x
            y0 = y1 = y
            q = deque([(y, x)])
            labels[y, x] = current
            while q:
                cy, cx = q.popleft()
                size += 1
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        q.append((ny, nx))
            if size >= min_pixels:
                out.append({"size": size, "box": [x0, y0, x1, y1]})
    out.sort(key=lambda c: -c["size"])
    return out[:LAYERS], labels


def find_eyes(rgba):
    """Locate the two irises inside the upper-middle face area."""
    a = np.asarray(rgba.convert("RGB")).astype(np.int16)
    h, w = a.shape[:2]
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    # Purple: blue clearly above green, red above green, mid-light so the white
    # shirt and cream hair cannot match.
    purple = (b - g > 26) & (r - g > 8) & (b > 110) & (b < 235) & (r > 60)
    face = np.zeros_like(purple)
    face[int(h * 0.22):int(h * 0.62), int(w * 0.28):int(w * 0.80)] = True
    found, labels = components(purple & face, min_pixels=4000)
    eyes = [c["box"] for c in found[:2]]
    return eyes, labels, purple


def checker(size, cell=16):
    w, h = size
    y, x = np.mgrid[0:h, 0:w]
    board = (((x // cell) + (y // cell)) % 2).astype(np.uint8) * 40 + 205
    return Image.fromarray(np.dstack([board] * 3 + [np.full((h, w), 255, np.uint8)]), "RGBA")


def main():
    work = os.path.abspath(sys.argv[1])
    ref = os.path.join(work, "reference")
    src = Image.open(os.path.join(ref, "source-reference.png"))
    cutout, plate_mask = key(src)

    alpha = np.asarray(cutout)[:, :, 3]
    ys, xs = np.where(alpha > 8)
    box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]

    cutout.save(os.path.join(ref, "keyed-cutout.png"))
    base = checker(cutout.size)
    base.alpha_composite(cutout)
    base.convert("RGB").save(os.path.join(ref, "keyed-checker.png"))

    eyes, labels, purple = find_eyes(cutout)
    preview = cutout.crop((box[0] - 40, box[1] - 40, box[2] + 40, int(box[1] + 0.6 * (box[3] - box[1]))))
    vis = checker(preview.size)
    vis.alpha_composite(preview)
    from PIL import ImageDraw
    draw = ImageDraw.Draw(vis)
    for ex0, ey0, ex1, ey1 in eyes:
        draw.rectangle([ex0 - box[0] + 40, ey0 - box[1] + 40, ex1 - box[0] + 40, ey1 - box[1] + 40],
                       outline=(255, 0, 0, 255), width=6)
    vis.convert("RGB").save(os.path.join(ref, "eye-detect.png"))

    rgb = np.asarray(cutout.convert("RGB"))
    opaque = alpha > 200
    palette = {
        "hair": [int(v) for v in rgb[int(box[1] + 0.20 * (box[3] - box[1])), int(box[0] + 0.30 * (box[2] - box[0]))]],
        "face": [int(v) for v in rgb[int(box[1] + 0.45 * (box[3] - box[1])), int(box[0] + 0.52 * (box[2] - box[0]))]],
    }
    report = {
        "source_size": list(src.size),
        "cutout_box": box,
        "plate_pixels": int(plate_mask.sum()),
        "opaque_pixels": int(opaque.sum()),
        "eye_boxes": eyes,
        "palette_samples": palette,
    }
    with open(os.path.join(ref, "analysis.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()