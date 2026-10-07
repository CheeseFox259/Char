#!/usr/bin/env python3
"""Render the 菲比 charpet: seven clips, the software icon, manifest and previews.

Every clip is a rigid/affine performance of one keyed cut-out, so identity and
line weight never drift between frames. All easing lives in the clip tables
below; the shared rest pose (idle frame 0) is referenced by several clips so it
is stored as a single PNG and decoded once.

Memory notes: the art is transformed at canvas * SS (premultiplied float) and
Lanczos-downsampled to the canvas, so a 128 px frame never upsamples anything.

Usage: build.py <work-dir> <package-dir>
"""

import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

FPS = 24
REST = {"sx": 1.0, "sy": 1.0, "rot": 0.0, "skew": 0.0, "dx": 0.0, "dy": 0.0, "alpha": 1.0, "eyes": "open"}


def clip(fps, rows, eyes=None):
    """rows: list of (sx, sy, rot, skew, dx, dy, alpha); eyes: list of eye variants."""
    return {
        "fps": fps,
        "poses": [dict(REST, sx=r[0], sy=r[1], rot=r[2], skew=r[3], dx=r[4], dy=r[5], alpha=r[6])
                  for r in rows],
        "eyes": eyes or ["open"] * len(rows),
    }


# sx, sy, rot(deg), skew, dx, dy, alpha — hand-tuned keys, not procedural curves,
# so each motion can be read and adjusted on its own.
CLIPS = {
    # Breathing loop: every term is periodic in the 48-frame period, so the seam
    # is invisible. Two harmonics keep it from reading as a plain sine.
    "idle": clip(24, [
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
        (0.998, 1.008, 0.34, 0.004, 0.19, -0.62, 1.0),
        (0.995, 1.017, 0.66, 0.008, 0.36, -1.20, 1.0),
        (0.992, 1.022, 0.92, 0.011, 0.49, -1.60, 1.0),
        (0.989, 1.023, 1.11, 0.013, 0.56, -1.78, 1.0),
        (0.987, 1.020, 1.23, 0.014, 0.57, -1.72, 1.0),
        (0.986, 1.014, 1.27, 0.014, 0.53, -1.46, 1.0),
        (0.987, 1.007, 1.23, 0.013, 0.45, -1.08, 1.0),
        (0.989, 1.001, 1.11, 0.011, 0.34, -0.70, 1.0),
        (0.992, 0.997, 0.92, 0.009, 0.22, -0.37, 1.0),
        (0.995, 0.994, 0.66, 0.006, 0.10, -0.14, 1.0),
        (0.998, 0.993, 0.34, 0.003, 0.02, -0.03, 1.0),
        (1.000, 0.994, 0.00, 0.000, 0.00, 0.05, 1.0),
        (1.001, 0.998, -0.34, -0.003, -0.02, 0.13, 1.0),
        (1.003, 1.003, -0.66, -0.006, -0.10, 0.20, 1.0),
        (1.004, 1.007, -0.92, -0.008, -0.22, 0.25, 1.0),
        (1.005, 1.010, -1.11, -0.009, -0.34, 0.27, 1.0),
        (1.005, 1.011, -1.23, -0.009, -0.45, 0.26, 1.0),
        (1.005, 1.009, -1.27, -0.008, -0.53, 0.23, 1.0),
        (1.004, 1.006, -1.23, -0.007, -0.57, 0.18, 1.0),
        (1.003, 1.003, -1.11, -0.006, -0.56, 0.12, 1.0),
        (1.002, 1.000, -0.92, -0.004, -0.49, 0.06, 1.0),
        (1.001, 0.998, -0.66, -0.003, -0.36, 0.01, 1.0),
        (1.000, 0.997, -0.34, -0.001, -0.19, -0.02, 1.0),
        (1.000, 0.996, 0.00, 0.000, 0.00, -0.03, 1.0),
        (0.999, 0.997, 0.34, 0.001, 0.19, -0.02, 1.0),
        (0.998, 0.999, 0.66, 0.003, 0.36, 0.01, 1.0),
        (0.997, 1.001, 0.92, 0.004, 0.49, 0.06, 1.0),
        (0.996, 1.003, 1.11, 0.006, 0.56, 0.12, 1.0),
        (0.995, 1.003, 1.23, 0.007, 0.57, 0.18, 1.0),
        (0.995, 1.003, 1.27, 0.007, 0.53, 0.23, 1.0),
        (0.996, 1.001, 1.23, 0.006, 0.45, 0.26, 1.0),
        (0.997, 0.999, 1.11, 0.005, 0.34, 0.27, 1.0),
        (0.998, 0.997, 0.92, 0.004, 0.22, 0.25, 1.0),
        (1.000, 0.997, 0.66, 0.002, 0.10, 0.20, 1.0),
        (1.001, 0.998, 0.34, 0.001, 0.02, 0.13, 1.0),
        (1.001, 1.000, 0.00, 0.000, 0.00, 0.05, 1.0),
        (1.001, 1.003, -0.34, -0.001, -0.02, -0.03, 1.0),
        (1.002, 1.007, -0.66, -0.003, -0.10, -0.14, 1.0),
        (1.002, 1.010, -0.92, -0.004, -0.22, -0.37, 1.0),
        (1.002, 1.011, -1.11, -0.005, -0.34, -0.70, 1.0),
        (1.001, 1.011, -1.23, -0.005, -0.45, -1.08, 1.0),
        (1.000, 1.009, -1.27, -0.005, -0.53, -1.46, 1.0),
        (0.999, 1.007, -1.23, -0.004, -0.57, -1.72, 1.0),
        (0.998, 1.004, -1.11, -0.003, -0.56, -1.78, 1.0),
        (0.997, 1.001, -0.92, -0.002, -0.49, -1.60, 1.0),
        (0.996, 0.998, -0.66, -0.001, -0.36, -1.20, 1.0),
        (0.995, 0.996, -0.34, 0.000, -0.19, -0.62, 1.0),
        (0.995, 0.995, 0.00, 0.000, 0.00, 0.00, 1.0),
    ], ["open"] * 33 + ["blink"] * 3 + ["open"] * 12),

    # Pressed: fast cubic squash under the cursor, one damped rebound, feet planted.
    "press": clip(24, [
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
        (1.040, 0.952, -0.90, 0.008, 0.00, 1.30, 1.0),
        (1.082, 0.888, -1.80, 0.018, 0.00, 2.90, 1.0),
        (1.098, 0.868, -2.20, 0.024, 0.00, 3.70, 1.0),
        (1.082, 0.888, -1.90, 0.020, 0.00, 3.10, 1.0),
        (1.050, 0.932, -1.20, 0.012, 0.00, 2.00, 1.0),
        (0.968, 1.052, 1.30, -0.010, 0.00, -3.00, 1.0),
        (1.014, 0.976, 0.55, -0.004, 0.00, 1.10, 1.0),
        (0.992, 1.018, -0.25, 0.002, 0.00, -0.55, 1.0),
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
    ], ["open", "blink", "blink", "blink", "blink", "blink", "open", "open", "open", "open"]),

    # Return home: anticipation, one hop with a happy face, landing squash, settle.
    "return": clip(24, [
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
        (0.976, 0.930, -1.40, 0.010, 0.00, 2.40, 1.0),
        (0.950, 1.100, 2.40, -0.020, 0.30, -8.80, 1.0),
        (0.944, 1.128, 3.10, -0.026, 0.90, -11.40, 1.0),
        (0.966, 1.060, 1.70, -0.012, 0.50, -6.80, 1.0),
        (1.036, 0.930, -0.80, 0.012, -1.40, 0.60, 1.0),
        (0.980, 1.046, -1.10, 0.006, 0.20, -3.80, 1.0),
        (1.012, 0.974, 0.60, -0.004, 0.90, 1.30, 1.0),
        (0.994, 1.018, -0.30, 0.002, 0.10, -0.70, 1.0),
        (1.004, 0.990, 0.15, -0.001, -0.05, 0.30, 1.0),
        (0.999, 1.006, -0.08, 0.000, 0.02, -0.15, 1.0),
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
    ], ["open", "open", "happy", "happy", "happy", "open", "open", "open", "open", "open", "open", "open"]),

    # Departure: stretch away, shrink with cubic ease-in, drift off, fade out.
    "depart": clip(24, [
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
        (0.985, 1.042, -1.60, -0.010, -0.80, -2.60, 1.0),
        (0.940, 1.010, -1.20, -0.006, 0.40, -1.60, 1.0),
        (0.868, 0.952, -0.40, 0.000, 2.00, 0.60, 0.97),
        (0.790, 0.888, 0.30, 0.006, 3.90, 1.80, 0.90),
        (0.712, 0.818, 0.80, 0.010, 5.90, 2.90, 0.79),
        (0.638, 0.752, 1.10, 0.012, 7.80, 3.80, 0.66),
        (0.568, 0.690, 1.30, 0.012, 9.50, 4.60, 0.53),
        (0.502, 0.632, 1.40, 0.010, 11.00, 5.30, 0.40),
        (0.440, 0.578, 1.45, 0.008, 12.20, 5.90, 0.28),
        (0.382, 0.528, 1.45, 0.006, 13.10, 6.40, 0.16),
        (0.326, 0.482, 1.40, 0.004, 13.70, 6.80, 0.00),
    ]),

    # Arrival: reappears small and transparent, elastic overshoot, one squash.
    "arrive": clip(24, [
        (0.326, 0.482, 1.40, 0.004, 13.70, 6.80, 0.00),
        (0.382, 0.528, 1.30, 0.006, 12.40, 5.90, 0.16),
        (0.448, 0.590, 1.15, 0.008, 10.60, 4.90, 0.38),
        (0.526, 0.664, 0.90, 0.008, 8.40, 3.90, 0.62),
        (0.618, 0.752, 0.55, 0.006, 5.90, 2.80, 0.83),
        (0.722, 0.848, 0.10, 0.002, 3.20, 1.60, 0.96),
        (0.860, 0.982, -0.50, -0.002, 0.60, 0.30, 1.00),
        (1.048, 0.958, -0.80, 0.004, -1.20, 1.60, 1.00),
        (0.978, 1.020, 0.45, -0.002, 0.50, -0.60, 1.00),
        (1.006, 0.992, -0.20, 0.001, -0.10, 0.25, 1.00),
        (0.997, 1.005, 0.10, 0.000, 0.02, -0.10, 1.00),
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.00),
    ], ["open"] * 5 + ["happy", "open", "open", "open", "open", "open", "open"]),

    # Edge peek: authored toward the canvas bottom, hidden below it, elastic rise.
    "edgePeek": clip(24, [
        (1.030, 0.975, 3.00, 0.030, 0.00, 140.0, 0.00),
        (1.026, 0.980, 2.40, 0.026, 0.00, 118.0, 0.26),
        (1.020, 0.988, 1.80, 0.022, 0.00, 92.0, 0.55),
        (1.012, 0.996, 1.20, 0.017, 0.00, 66.0, 0.80),
        (1.005, 1.008, 0.70, 0.012, 0.00, 43.0, 0.94),
        (0.998, 1.020, 0.25, 0.007, 0.00, 25.0, 1.00),
        (0.992, 1.028, -0.35, 0.002, 0.00, 13.0, 1.00),
        (0.996, 1.014, 0.20, 0.000, 0.00, 5.0, 1.00),
        (1.002, 0.996, -0.15, 0.000, 0.00, 1.5, 1.00),
        (0.999, 1.005, 0.10, 0.000, 0.00, -1.2, 1.00),
        (1.000, 0.999, -0.05, 0.000, 0.00, -0.6, 1.00),
        (1.000, 1.000, 0.03, 0.000, 0.00, 0.2, 1.00),
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.0, 1.00),
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.0, 1.00),
    ], ["open"] * 6 + ["happy", "happy"] + ["open"] * 6),

    # Edge hide: small anticipation, then slide down the same authored direction.
    "edgeHide": clip(24, [
        (1.000, 1.000, 0.00, 0.000, 0.00, 0.00, 1.0),
        (0.975, 1.036, -1.50, 0.010, 0.00, -3.40, 1.00),
        (1.010, 0.984, 1.20, -0.008, 0.00, 1.60, 1.00),
        (1.006, 0.996, 0.80, -0.004, 0.00, 6.00, 1.00),
        (0.998, 1.004, 0.40, 0.000, 0.00, 14.0, 1.00),
        (1.000, 1.000, 0.20, 0.002, 0.00, 26.0, 0.98),
        (1.004, 0.996, 0.10, 0.004, 0.00, 42.0, 0.90),
        (1.000, 1.000, 0.00, 0.004, 0.00, 62.0, 0.74),
        (1.000, 1.000, 0.00, 0.003, 0.00, 84.0, 0.55),
        (1.000, 1.000, 0.00, 0.002, 0.00, 108.0, 0.34),
        (1.000, 1.000, 0.00, 0.001, 0.00, 126.0, 0.15),
        (1.000, 1.000, 0.00, 0.000, 0.00, 140.0, 0.00),
    ]),
}

CLIP_ORDER = ["idle", "press", "return", "depart", "arrive", "edgePeek", "edgeHide"]


def matrix(pose, ss, pivot):
    """Forward map from canvas coordinates to canvas coordinates, at SS scale."""
    px, py = pivot[0] * ss, pivot[1] * ss
    th = math.radians(pose["rot"])
    cos, sin = math.cos(th), math.sin(th)
    to_pivot = np.array([[1, 0, px], [0, 1, py], [0, 0, 1]], float)
    from_pivot = np.array([[1, 0, -px], [0, 1, -py], [0, 0, 1]], float)
    shear = np.array([[1, pose["skew"], 0], [0, 1, 0], [0, 0, 1]], float)
    rot = np.array([[cos, -sin, 0], [sin, cos, 0], [0, 0, 1]], float)
    scale = np.array([[pose["sx"], 0, 0], [0, pose["sy"], 0], [0, 0, 1]], float)
    move = np.array([[1, 0, pose["dx"] * ss], [0, 1, pose["dy"] * ss], [0, 0, 1]], float)
    return move @ to_pivot @ shear @ rot @ scale @ from_pivot


def render(art, pose, canvas, ss, pivot):
    """Transform premultiplied float art at SS, then Lanczos down to the canvas."""
    inverse = np.linalg.inv(matrix(pose, ss, pivot))
    coeffs = [inverse[0, 0], inverse[0, 1], inverse[0, 2],
              inverse[1, 0], inverse[1, 1], inverse[1, 2]]
    big = art.shape[0]
    moved = []
    for c in range(4):
        plane = Image.fromarray(np.ascontiguousarray(art[..., c], dtype=np.float32), mode="F")
        moved.append(np.asarray(plane.transform((big, big), Image.AFFINE, coeffs, Image.BICUBIC),
                                dtype=np.float32))
    stacked = np.stack(moved, axis=-1)
    if pose["alpha"] < 1.0:
        stacked[..., 3] *= pose["alpha"]
    small = np.stack([
        np.asarray(Image.fromarray(np.ascontiguousarray(stacked[..., c], dtype=np.float32), mode="F")
                   .resize((canvas, canvas), Image.LANCZOS), dtype=np.float32) for c in range(4)], axis=-1)
    alpha = np.clip(small[..., 3], 0.0, 1.0)
    rgb = np.where(alpha[..., None] > 1e-4, np.clip(small[..., :3], 0.0, 1.0) / np.maximum(alpha[..., None], 1e-4), 0.0)
    rgb = np.clip(rgb, 0.0, alpha[..., None])
    return np.dstack([rgb, alpha])


def premultiply(img):
    a = np.asarray(img).astype(np.float32) / 255.0
    return np.dstack([a[..., :3] * a[..., 3:4], a[..., 3:4]])


def rounded_tile(size, inset, radius, top, bottom):
    """Rounded gradient tile in the host icon's own colours."""
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = np.linspace(0.0, 1.0, size, dtype=np.float32)
    shade = (np.array(top, np.float32)[None, :] * (1 - grad)[:, None]
             + np.array(bottom, np.float32)[None, :] * grad[:, None])
    ramp = np.clip(shade * 255.0, 0, 255)[:, None, :].repeat(size, axis=1)
    plane = Image.fromarray(np.dstack([ramp, np.full((size, size), 255.0)]).astype(np.uint8), "RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    tile.paste(plane, (0, 0), mask)
    return tile


def build_icon(rest_img, canvas, size=512):
    """Host peek composition: gradient tile, the character peeking past a screen edge.

    Proportions follow PetIconArtwork.rightEdgeIcon: the same tile inset and
    radius, the character canvas at ~59% of the tile rotated 90 degrees so it
    reads from the right edge, and the same grey/white edge line pair.
    """
    inset = int(round(size * 0.078))
    radius = int(round(size * 0.213))
    edge_x = int(round(size * 0.762))
    w = int(round(size * 0.86))
    scale = w / canvas
    tile = rounded_tile(size, inset, radius, (0.97, 0.98, 1.00), (0.88, 0.93, 0.99))

    src = rest_img.resize((canvas, canvas), Image.LANCZOS).rotate(90, expand=True, resample=Image.BICUBIC)
    src = src.resize((w, w), Image.LANCZOS)
    left = int(round(size * 0.055))
    top = int(round((size - w) / 2))

    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body.paste(src, (left, top), src)
    blurred = body.split()[3].filter(ImageFilter.GaussianBlur(size * 0.020))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (size, size), (16, 12, 24, 56)), (-2, 5), blurred)

    clip = Image.new("L", (size, size), 0)
    ImageDraw.Draw(clip).rectangle([0, 0, edge_x, size], fill=255)
    empty = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile.alpha_composite(Image.composite(shadow, empty, clip))
    tile.alpha_composite(Image.composite(body, empty, clip))

    draw = ImageDraw.Draw(tile)
    draw.rectangle([edge_x, inset, edge_x + 3, size - inset], fill=(133, 153, 184, 115))
    draw.rectangle([edge_x + 3, inset, edge_x + 7, size - inset], fill=(255, 255, 255, 204))
    return tile


def main():
    work, package = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    rig = json.load(open(os.path.join(work, "art", "rig.json")))
    canvas, ss = rig["canvas"], rig["supersample"]
    art = {name: premultiply(Image.open(os.path.join(work, "art", f"{name}-{canvas * ss}.png")))
           for name in ("open", "blink", "happy")}
    pivot = (canvas * 0.5, canvas - 1)

    frames_dir = os.path.join(package, "frames")
    if os.path.exists(package):
        shutil.rmtree(package)
    os.makedirs(frames_dir)

    writes = {}
    manifest_clips = {}
    for name in CLIP_ORDER:
        spec = CLIPS[name]
        paths = []
        for i, (pose, eyes) in enumerate(zip(spec["poses"], spec["eyes"])):
            pixels = render(art[eyes], pose, canvas, ss, pivot)
            key = pixels.tobytes()
            if key not in writes:
                rel = f"frames/{name}-{i:03d}.png"
                img = Image.fromarray(np.clip(pixels * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")
                img.save(os.path.join(package, rel), optimize=True)
                writes[key] = rel
            paths.append(writes[key])
        manifest_clips[name] = {"fps": spec["fps"], "frames": paths}

    rest_img = Image.open(os.path.join(work, "art", f"open-{canvas * ss}.png")).convert("RGBA")
    build_icon(rest_img, canvas).save(os.path.join(package, "icon.png"), optimize=True)

    manifest = {
        "schemaVersion": 1,
        "id": "feibi.pet",
        "name": "菲比",
        "appIcon": "icon.png",
        "canvasSize": {"width": canvas, "height": canvas},
        "anchor": rig["anchor"],
        "clips": manifest_clips,
    }
    with open(os.path.join(package, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False, sort_keys=True)

    unique = sorted(set(writes.values()))
    print(json.dumps({
        "package": package,
        "clips": {k: len(v["frames"]) for k, v in manifest_clips.items()},
        "frame_references": sum(len(v["frames"]) for v in manifest_clips.values()),
        "unique_frames": len(unique),
        "unique_pixels": len(unique) * canvas * canvas + 512 * 512,
        "rga_estimate_mib": round((len(unique) * canvas * canvas * 4 + 512 * 512 * 4) / 1048576, 2),
    }, indent=2))


if __name__ == "__main__":
    main()