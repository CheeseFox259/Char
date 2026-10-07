#!/usr/bin/env python3
"""Build the 菲比 art rig: one sitting chibi cut-out plus blink and happy-eye variants.

The keyed reference is the single source of truth for identity, so every clip
reuses the same pixels; only the eye region is redrawn for expression changes.
Eye blobs are found by growing the purple iris through non-ink pixels (the dark
lid ring stops the growth and the eyebrow, a separate stroke, is never touched),
holes are refilled, and the covered area is inpainted with a Jacobi diffusion of
the surrounding skin gradient before the new lid line is stroked. Expressions are
drawn at reference resolution and only then scaled into the canvas, so the lid
line keeps its weight.

Output (all 8-bit RGBA PNG, straight alpha, canvas * SS square):
  <work>/art/open-512.png    rest art
  <work>/art/blink-512.png   eyes closed (upward lid arc)
  <work>/art/happy-512.png   eyes closed, smiling downward arc
  <work>/art/rig.json        placement, eye boxes and palette for build.py

Usage: art.py <work-dir> [canvas] [supersample]
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

CANVAS = 128
SS = 4                      # supersample factor for transform quality
TOP_MARGIN = 15             # canvas pixels between the hat top and the canvas top
BOTTOM_MARGIN = 1           # shoes rest on the canvas bottom, as in the peek study
INK_LEVEL = 120             # darkest-channel level that counts as outline ink
GROW_LIMIT = 90             # ink-connected growth budget: the lid ring is ~45 px away
RING_GROW = 3               # extra growth that swallows the anti-aliased lid edge
BLOB_AREA_LIMIT = 3.2       # guard: a grown blob may not exceed this x the iris area


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


def erode(mask):
    return ~dilate(~mask, 1)


def fill_holes(mask):
    """Fill regions of `mask` not reachable from outside its bounding box."""
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    sub = mask[y0:y1, x0:x1]
    free = ~sub
    reach = np.zeros_like(free)
    stack = []
    for y in range(sub.shape[0]):
        for x in (0, sub.shape[1] - 1):
            if free[y, x]:
                reach[y, x] = True
                stack.append((y, x))
    for x in range(sub.shape[1]):
        for y in (0, sub.shape[0] - 1):
            if free[y, x] and not reach[y, x]:
                reach[y, x] = True
                stack.append((y, x))
    while stack:
        y, x = stack.pop()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < sub.shape[0] and 0 <= nx < sub.shape[1] and free[ny, nx] and not reach[ny, nx]:
                reach[ny, nx] = True
                stack.append((ny, nx))
    out = mask.copy()
    out[y0:y1, x0:x1] |= ~reach
    return out


def grow(seed, allowed, limit):
    region = seed.copy()
    for _ in range(limit):
        grown = (dilate(region, 1) & allowed) | region
        if np.array_equal(grown, region):
            break
        region = grown
    return region


def eye_blob(rgb, alpha, box):
    """One mask covering iris, highlight, pupil and lid line of a single eye.

    The lid is reached by growing ink outward from the pixels that touch the
    iris, so the shape follows the eye's own outline. Traversal uses a dilated
    ink mask, because an anti-aliased pixel can split the thick lid apex into a
    diagonally-attached fragment that 4-connectivity would leave behind. The
    eyebrow is a separate stroke and is never traversed, and the closed lid keeps
    the growth from leaking into the cheek.
    """
    x0, y0, x1, y1 = box
    ink = rgb.min(axis=2) < INK_LEVEL
    iris = np.zeros(alpha.shape, dtype=bool)
    iris[y0:y1, x0:x1] = True
    iris &= ~ink & (alpha > 32)
    if not iris.any():
        raise SystemExit(f"no iris pixels in eye box {box}")
    lid = grow(dilate(iris, 3) & ink, dilate(ink, 1), GROW_LIMIT)
    blob = dilate(fill_holes(iris | lid), RING_GROW)
    if blob.sum() > BLOB_AREA_LIMIT * iris.sum():
        raise SystemExit(f"eye blob leaked out of {box}: {blob.sum()} px vs iris {iris.sum()} px")
    return blob


def _jacobi(field, hole, iterations):
    """Harmonic relaxation; the array edge replicates, it never fades to black."""
    for _ in range(iterations):
        padded = np.pad(field, ((1, 1), (1, 1), (0, 0)), mode="edge")
        blurred = (padded[:-2, 1:-1] + padded[2:, 1:-1] + padded[1:-1, :-2] + padded[1:-1, 2:]) / 4.0
        field = np.where(hole[..., None], blurred, field)
    return field


def inpaint(rgb, mask, coarse=6, coarse_iters=1500, fine_iters=400):
    """Solve the harmonic fill of `mask` from its skin boundary.

    Plain Jacobi needs O(size^2) sweeps to reach the middle of a 150 px eye, so
    the region is first solved on a coarse block grid (valid-pixel means) and the
    upsampled result seeds the full-resolution refinement.
    """
    ys, xs = np.where(mask)
    y0, x0 = max(int(ys.min()) - 2, 0), max(int(xs.min()) - 2, 0)
    y1, x1 = min(int(ys.max()) + 3, rgb.shape[0]), min(int(xs.max()) + 3, rgb.shape[1])
    sub = rgb[y0:y1, x0:x1].astype(np.float32).copy()
    hole = mask[y0:y1, x0:x1]

    ch, cw = sub.shape[0] // coarse, sub.shape[1] // coarse
    blocks = sub[:ch * coarse, :cw * coarse].reshape(ch, coarse, cw, coarse, 3)
    blocks = blocks.transpose(0, 2, 1, 3, 4).reshape(ch, cw, coarse * coarse, 3)
    valid = ~hole[:ch * coarse, :cw * coarse].reshape(ch, coarse, cw, coarse).transpose(0, 2, 1, 3).reshape(ch, cw, coarse * coarse)
    # Ink on the rim of the blob would seed the coarse solve with dark averages,
    # so blocks count only their skin pixels and anything mostly ink stays unknown.
    ink = sub.min(axis=2) < INK_LEVEL
    weight = (valid & ~ink[:ch * coarse, :cw * coarse].reshape(ch, coarse, cw, coarse).transpose(0, 2, 1, 3).reshape(ch, cw, coarse * coarse)).astype(np.float32)
    count = weight.sum(axis=2, keepdims=True)
    coarse_field = np.where(count > 0, (blocks * weight[..., None]).sum(axis=2) / np.maximum(count, 1), 0.0).astype(np.float32)
    unknown = count < 0.5 * coarse * coarse
    coarse_field = _jacobi(coarse_field, unknown[..., 0], coarse_iters)

    up = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(coarse_field[..., c], dtype=np.float32), mode="F")
                              .resize((sub.shape[1], sub.shape[0]), Image.BILINEAR), dtype=np.float32)
                   for c in range(3)], axis=-1)
    sub = np.where(hole[..., None], up, sub)
    sub = _jacobi(sub, hole, fine_iters)

    out = rgb.copy()
    out[y0:y1, x0:x1] = np.where(hole[..., None], sub, out[y0:y1, x0:x1])
    return out


def stroke_lid(draw, box, ink, width, bow):
    """Closed-eye lid: quadratic arc across the eye box with round caps."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    left, right = x0 + 0.05 * w, x1 - 0.05 * w
    y = y0 + 0.47 * h
    ctrl = ((left + right) / 2, y + bow * h)
    pts = []
    for i in range(65):
        t = i / 64
        pts.append(((1 - t) ** 2 * left + 2 * (1 - t) * t * ctrl[0] + t * t * right,
                    (1 - t) ** 2 * y + 2 * (1 - t) * t * ctrl[1] + t * t * y))
    draw.line(pts, fill=ink, width=width, joint="curve")
    for px, py in (pts[0], pts[-1]):
        r = width / 2
        draw.ellipse([px - r, py - r, px + r, py + r], fill=ink)


def render_expression(rgba, boxes, ink, bow):
    """Return float RGB/alpha with every eye redrawn as a closed lid."""
    arr = np.asarray(rgba).astype(np.float32)
    rgb, alpha = arr[:, :, :3], arr[:, :, 3]
    for box in boxes:
        blob = eye_blob(rgb.astype(np.int16), alpha, box)
        rgb = inpaint(rgb, blob)
        ys, xs = np.where(blob)
        eye = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
        img = compose(rgb, alpha)
        stroke_lid(ImageDraw.Draw(img), eye, ink, max(3, int(0.085 * (eye[3] - eye[1]))), bow)
        rgb = np.asarray(img).astype(np.float32)[:, :, :3]
    return rgb, alpha


def compose(rgb, alpha):
    stacked = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 255)]).astype(np.uint8)
    return Image.fromarray(stacked, "RGBA")


def resize_premultiplied(img, size):
    """Alpha-correct resize: premultiply, resample, unpremultiply."""
    a = np.asarray(img).astype(np.float32) / 255.0
    alpha = a[..., 3:4]
    pm = np.dstack([a[..., :3] * alpha, alpha])
    planes = [Image.fromarray(np.ascontiguousarray(pm[..., i]), mode="F").resize(size, Image.LANCZOS) for i in range(4)]
    out = np.stack([np.asarray(p) for p in planes], axis=-1)
    out[..., 3] = np.clip(out[..., 3], 0.0, 1.0)
    safe = np.maximum(out[..., 3:4], 1e-5)
    rgb = np.where(out[..., 3:4] > 1e-5, out[..., :3] / safe, 0.0)
    return Image.fromarray(np.clip(np.dstack([rgb, out[..., 3]]) * 255.0, 0, 255).astype(np.uint8), "RGBA")


def place(source, box, canvas, ss):
    """Scale a keyed cut-out into the supersampled canvas with premultiplied alpha."""
    x0, y0, x1, y1 = box
    height = (canvas - TOP_MARGIN - BOTTOM_MARGIN) * ss
    scale = height / (y1 - y0)
    size = (max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale)))
    art = resize_premultiplied(source, size)
    out = Image.new("RGBA", (canvas * ss, canvas * ss), (0, 0, 0, 0))
    out.paste(art, (round((canvas * ss - art.width) / 2), round(TOP_MARGIN * ss)), art)
    return out


def main():
    work = os.path.abspath(sys.argv[1])
    canvas = int(sys.argv[2]) if len(sys.argv) > 2 else CANVAS
    ss = int(sys.argv[3]) if len(sys.argv) > 3 else SS
    ref = os.path.join(work, "reference")
    art_dir = os.path.join(work, "art")
    os.makedirs(art_dir, exist_ok=True)

    analysis = json.load(open(os.path.join(ref, "analysis.json")))
    cutout = Image.open(os.path.join(ref, "keyed-cutout.png")).convert("RGBA")
    arr = np.asarray(cutout).astype(np.int16)
    dark = arr[:, :, :3].min(axis=2)
    ink = tuple(int(v) for v in np.median(arr[:, :, :3][(dark < 60) & (arr[:, :, 3] > 200)], axis=0))
    boxes = analysis["eye_boxes"]

    variants = {"open": cutout}
    for name, bow in (("blink", -0.30), ("happy", 0.26)):
        rgb, alpha = render_expression(cutout, boxes, ink, bow)
        variants[name] = compose(rgb, alpha)

    for name, img in variants.items():
        placed = place(img, analysis["cutout_box"], canvas, ss)
        placed.save(os.path.join(art_dir, f"{name}-{canvas * ss}.png"))

    alpha = np.asarray(place(cutout, analysis["cutout_box"], canvas, ss))[:, :, 3]
    ys, xs = np.where(alpha > 4)
    rig = {
        "canvas": canvas,
        "supersample": ss,
        "anchor": {"x": 0.5, "y": 0.5},
        "top_margin": TOP_MARGIN,
        "bottom_margin": BOTTOM_MARGIN,
        "art_box_canvas": [round(float(xs.min()) / ss, 2), round(float(ys.min()) / ss, 2),
                            round(float(xs.max()) / ss, 2), round(float(ys.max()) / ss, 2)],
        "ink": list(ink),
        "eye_boxes_source": boxes,
        "source_box": analysis["cutout_box"],
    }
    with open(os.path.join(art_dir, "rig.json"), "w") as fh:
        json.dump(rig, fh, indent=2)
    print(json.dumps(rig, indent=2))


if __name__ == "__main__":
    main()