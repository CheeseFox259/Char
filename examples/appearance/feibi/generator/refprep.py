#!/usr/bin/env python3
"""Key the white-background reference into straight-alpha RGBA and locate the eye rig.

The plate is near-white with sensor noise and the character itself contains
enclosed near-white regions (hat crown, shirt), so keying is a border flood fill
over neutral near-white pixels, never a global colour test. Only the band that
touches the flood region is recomputed from an ink-over-white mix model, which
restores the anti-aliased outline without eroding light skin.

Usage: refprep.py <work-dir>

Outputs:
  <work>/reference/keyed-cutout.png    native-resolution cut-out, straight alpha
  <work>/reference/keyed-checker.png   checkerboard composite for visual review
  <work>/reference/eye-detect.png      face crop with detected iris boxes
  <work>/reference/analysis.json       bounding box and seed boxes for art.py
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
SEEDS = 2                # iris seeds reported back to art.py


def flood_from_border(plate):
    """Return a boolean mask of plate pixels reachable from the image border."""
    h, w = plate.shape
    seen = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if plate[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if plate[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and plate[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def dilate(mask, radius):
    out = mask.copy()
    for _ in range(radius):
        grown = out.copy()
        grown[1:, :] |= out[:-1, :]
        grown[:-1, :] |= out[1:, :]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def band(mask, radius):
    return dilate(mask, radius) & ~mask


def key(rgb):
    """Straight-alpha cut-out of a near-white plate."""
    data = np.asarray(rgb).astype(np.int16)
    spread = data.max(axis=2) - data.min(axis=2)
    plate = (data.min(axis=2) >= PLATE_MIN) & (spread <= NEUTRAL_SLACK)
    outside = flood_from_border(plate)

    alpha = np.full(data.shape[:2], 255.0)
    alpha[outside] = 0.0
    ring = band(outside, BAND)
    darkest = data.min(axis=2).astype(np.float64)
    alpha = np.where(ring, np.clip((INK_MIN - darkest) / (INK_MIN - 255.0), 0.0, 1.0) * 255.0, alpha)

    return Image.fromarray(np.dstack([data.astype(np.uint8), alpha.round().astype(np.uint8)]), "RGBA"), outside


def components(mask, min_pixels=4000):
    """Connected components of a boolean mask, largest first."""
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    found = []
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            size, x0, x1, y0, y1 = 0, x, x, y, y
            queue = deque([(y, x)])
            seen[y, x] = True
            while queue:
                cy, cx = queue.popleft()
                size += 1
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if size >= min_pixels:
                found.append({"size": size, "box": [x0, y0, x1, y1]})
    found.sort(key=lambda item: -item["size"])
    return found[:SEEDS]


def find_irises(rgba):
    """Locate the two irises inside the upper-middle face area."""
    data = np.asarray(rgba.convert("RGB")).astype(np.int16)
    h, w = data.shape[:2]
    r, g, b = data[:, :, 0], data[:, :, 1], data[:, :, 2]
    purple = (b - g > 26) & (r - g > 8) & (b > 110) & (b < 235) & (r > 60)
    face = np.zeros_like(purple)
    face[int(h * 0.22):int(h * 0.62), int(w * 0.28):int(w * 0.80)] = True
    return [item["box"] for item in components(purple & face)]


def checker(size, cell=16):
    w, h = size
    y, x = np.mgrid[0:h, 0:w]
    board = (((x // cell) + (y // cell)) % 2).astype(np.uint8) * 40 + 205
    return Image.fromarray(np.dstack([board] * 3 + [np.full((h, w), 255, np.uint8)]), "RGBA")


def main():
    work = os.path.abspath(sys.argv[1])
    reference = os.path.join(work, "reference")
    source = Image.open(os.path.join(reference, "source-reference.png"))
    cutout, plate_mask = key(source)

    alpha = np.asarray(cutout)[:, :, 3]
    ys, xs = np.where(alpha > 8)
    box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
    irises = find_irises(cutout)

    cutout.save(os.path.join(reference, "keyed-cutout.png"))
    board = checker(cutout.size)
    board.alpha_composite(cutout)
    board.convert("RGB").save(os.path.join(reference, "keyed-checker.png"))

    from PIL import ImageDraw
    face = cutout.crop((box[0] - 40, box[1] - 40, box[2] + 40, int(box[1] + 0.6 * (box[3] - box[1]))))
    view = checker(face.size)
    view.alpha_composite(face)
    draw = ImageDraw.Draw(view)
    for x0, y0, x1, y1 in irises:
        draw.rectangle([x0 - box[0] + 40, y0 - box[1] + 40, x1 - box[0] + 40, y1 - box[1] + 40],
                       outline=(255, 0, 0, 255), width=6)
    view.convert("RGB").save(os.path.join(reference, "eye-detect.png"))

    report = {"source_size": list(source.size), "cutout_box": box,
              "plate_pixels": int(plate_mask.sum()), "opaque_pixels": int((alpha > 200).sum()),
              "iris_boxes": irises}
    with open(os.path.join(reference, "analysis.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()