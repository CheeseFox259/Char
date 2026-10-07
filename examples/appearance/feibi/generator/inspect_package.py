#!/usr/bin/env python3
"""Independent format, transparency and budget audit of a built .charpet package.

The production validator (char-package-check skin) is the authority; this script
records the evidence the acceptance sheet asks for: per-file PNG bit depth and
colour type, real transparency, non-empty frames, frame order and anchor, the
shared-rest-frame reuse, unique-frame pixel budget and the RGBA decode estimate.
It also measures the idle loop seam against the clip's own frame-to-frame motion.

Usage: inspect_package.py <package-dir> [report.json]
"""

import json
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

MAX_FRAME_BYTES = 4 * 1024 * 1024
MAX_MANIFEST_BYTES = 64 * 1024
MAX_PACKAGE_BYTES = 32 * 1024 * 1024
MAX_ENTRIES = 600
MAX_TOTAL_PIXELS = 16_777_216
CLIPS = ["idle", "press", "return", "depart", "arrive", "edgePeek", "edgeHide"]
ID_PATTERN = re.compile(r"^[a-z][a-z0-9.\-]{1,63}$")


def png_header(path):
    with open(path, "rb") as fh:
        head = fh.read(29)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height, depth, colour = struct.unpack(">IIBB", head[16:26])
    interlace = head[28]
    return {"width": width, "height": height, "bit_depth": depth, "colour_type": colour,
            "interlace": interlace, "animated": b"acTL" in head}


def main():
    package = os.path.abspath(sys.argv[1])
    report_path = sys.argv[2] if len(sys.argv) > 2 else None
    manifest_path = os.path.join(package, "manifest.json")
    problems = []

    manifest_bytes = os.path.getsize(manifest_path)
    if manifest_bytes > MAX_MANIFEST_BYTES:
        problems.append(f"manifest {manifest_bytes} B exceeds 64 KiB")
    manifest = json.load(open(manifest_path))

    if manifest.get("schemaVersion") != 1:
        problems.append("schemaVersion must be 1")
    if not ID_PATTERN.match(manifest.get("id", "")) or ".." in manifest.get("id", ""):
        problems.append(f"illegal id {manifest.get('id')!r}")
    if not manifest.get("name", "").strip() or len(manifest["name"]) > 80:
        problems.append("name must be 1..80 characters")
    canvas = manifest["canvasSize"]
    for axis in ("width", "height"):
        if not 32 <= canvas[axis] <= 512:
            problems.append(f"canvas {axis} out of range")
    anchor = manifest["anchor"]
    for axis in ("x", "y"):
        if not 0.0 <= anchor[axis] <= 1.0:
            problems.append(f"anchor {axis} out of range")

    clips = manifest["clips"]
    if sorted(clips) != sorted(CLIPS):
        problems.append(f"clip set mismatch: {sorted(clips)}")

    referenced, per_clip = set(), {}
    for name in CLIPS:
        spec = clips[name]
        frames = spec["frames"]
        if not 1 <= spec["fps"] <= 60:
            problems.append(f"{name}: fps {spec['fps']} out of range")
        if not 2 <= len(frames) <= 120:
            problems.append(f"{name}: {len(frames)} frames out of range")
        for path in frames:
            if path.startswith("/") or "\\" in path or ".." in path.split("/"):
                problems.append(f"{name}: unsafe frame path {path}")
            if not path.endswith(".png"):
                problems.append(f"{name}: non-png frame {path}")
            referenced.add(path)
        per_clip[name] = {"fps": spec["fps"], "frames": len(frames),
                          "unique": len(set(frames)),
                          "duration_s": round(len(frames) / spec["fps"], 3)}
    total_refs = sum(len(clips[n]["frames"]) for n in CLIPS)
    if total_refs > 480:
        problems.append(f"{total_refs} references exceed 480")

    on_disk = set()
    entries = 0
    package_bytes = 0
    for root, dirs, files in os.walk(package):
        for name in files:
            entries += 1
            full = os.path.join(root, name)
            if os.path.islink(full):
                problems.append(f"symlink in package: {full}")
            package_bytes += os.path.getsize(full)
            on_disk.add(os.path.relpath(full, package))
    if entries > MAX_ENTRIES:
        problems.append(f"{entries} directory entries exceed 600")
    if package_bytes > MAX_PACKAGE_BYTES:
        problems.append(f"package {package_bytes} B exceeds 32 MiB")

    icon_rel = manifest.get("appIcon")
    referenced_with_icon = set(referenced) | ({icon_rel} if icon_rel else set())
    unreferenced = on_disk - referenced_with_icon - {"manifest.json"}
    missing = referenced_with_icon - on_disk
    if unreferenced:
        problems.append(f"unreferenced files: {sorted(unreferenced)}")
    if missing:
        problems.append(f"missing files: {sorted(missing)}")

    header_report, alpha_report = {}, {}
    coverage = {}
    for name in CLIPS:
        frames = clips[name]["frames"]
        cov = []
        for index, rel in enumerate(frames):
            full = os.path.join(package, rel)
            data = np.asarray(Image.open(full).convert("RGBA"))
            alpha = data[..., 3]
            cov.append(float((alpha > 0).mean()))
        # A blank frame is only acceptable in a run that touches the clip head or
        # tail: those are the intended fade-in / fade-out ends of a migration.
        blank = [i for i, c in enumerate(cov) if c == 0.0]
        allowed = set()
        count = len(cov)
        k = 0
        while k < count and cov[k] == 0.0:
            allowed.add(k)
            k += 1
        k = count - 1
        while k >= 0 and cov[k] == 0.0:
            allowed.add(k)
            k -= 1
        for index in blank:
            if index not in allowed:
                problems.append(f"{name} frame {index} ({frames[index]}) is blank inside the clip")
        coverage[name] = {"min": round(min(cov), 4), "max": round(max(cov), 4),
                          "blank_frames": blank}
    for rel in sorted(referenced_with_icon):
        full = os.path.join(package, rel)
        head = png_header(full)
        if head is None:
            problems.append(f"{rel}: not a PNG")
            continue
        header_report[rel] = head
        if head["bit_depth"] != 8 or head["colour_type"] != 6:
            problems.append(f"{rel}: bit depth {head['bit_depth']} colour type {head['colour_type']}")
        if head["interlace"] != 0:
            problems.append(f"{rel}: interlaced PNG")
        if head["animated"]:
            problems.append(f"{rel}: animated PNG")
        if rel != icon_rel and (head["width"] != canvas["width"] or head["height"] != canvas["height"]):
            problems.append(f"{rel}: {head['width']}x{head['height']} != canvas")
        if rel == icon_rel and (head["width"] != head["height"] or head["width"] not in (128, 256, 512, 1024)):
            problems.append(f"icon: {head['width']}x{head['height']} not an allowed square")
        size = os.path.getsize(full)
        if size > MAX_FRAME_BYTES:
            problems.append(f"{rel}: {size} B exceeds 4 MiB")
        data = np.asarray(Image.open(full).convert("RGBA"))
        alpha = data[..., 3]
        alpha_report[rel] = {"opaque_fraction": round(float((alpha >= 250).mean()), 4),
                             "transparent_fraction": round(float((alpha == 0).mean()), 4),
                             "max_alpha": int(alpha.max())}
        if rel != icon_rel:
            ys, xs = np.where(alpha > 0)
            if len(xs) and (xs.min() == 0 or ys.min() == 0):
                alpha_report[rel]["touches_canvas_edge"] = True

    unique_frames = sorted(referenced)
    frame_pixels = len(unique_frames) * canvas["width"] * canvas["height"]
    icon_head = header_report.get(icon_rel, {"width": 0, "height": 0})
    icon_pixels = icon_head["width"] * icon_head["height"]
    total_pixels = frame_pixels + icon_pixels
    if total_pixels > MAX_TOTAL_PIXELS:
        problems.append(f"{total_pixels} unique pixels exceed {MAX_TOTAL_PIXELS}")
    decode_bytes = (len(unique_frames) * canvas["width"] * canvas["height"]
                    + icon_head["width"] * icon_head["height"]) * 4

    # idle seam: distance from the last frame to the first, against the clip's own
    # frame-to-frame motion, so a wrapped jump would stand out.
    idle = clips["idle"]["frames"]
    rest_frame = idle[0]
    continuity = {}
    for name in CLIPS:
        if name == "idle":
            continue
        frames = clips[name]["frames"]
        continuity[name] = {
            "starts_at_rest": frames[0] == rest_frame,
            "ends_at_rest": frames[-1] == rest_frame,
            "blank_head": not (alpha_report.get(frames[0], {}).get("max_alpha", 0) > 0),
            "blank_tail": not (alpha_report.get(frames[-1], {}).get("max_alpha", 0) > 0),
        }

    # Per-frame silhouette motion, measured from pixels: coverage, vertical
    # centroid and silhouette height. The second difference against the first
    # difference shows whether easing is continuous or has a visible snap.
    def motion(name):
        rows = []
        cache = {}
        for rel in clips[name]["frames"]:
            if rel not in cache:
                alpha = np.asarray(Image.open(os.path.join(package, rel)).convert("RGBA"))[..., 3]
                ys, xs = np.where(alpha > 0)
                if len(ys) == 0:
                    cache[rel] = (0.0, 0.0, 0.0)
                else:
                    cache[rel] = (float(len(ys)) / alpha.size, float(ys.mean()),
                                  float(ys.max() - ys.min()))
            rows.append(cache[rel])
        return rows

    motion_report = {}
    for name in CLIPS:
        rows = motion(name)
        # Blank fade ends have no silhouette; stepping through them would only
        # measure the sentinel, so continuity is measured over the visible run.
        solid = [r for r in rows if r[2] > 0]
        steps = [abs(solid[i + 1][j] - solid[i][j]) for i in range(len(solid) - 1) for j in (1, 2)]
        accel = [abs(steps[i + 1] - steps[i]) for i in range(len(steps) - 1)]
        motion_report[name] = {
            "centroid_y": [round(r[1], 2) for r in rows],
            "silhouette_height": [round(r[2], 1) for r in rows],
            "max_step": round(max(steps), 3) if steps else 0.0,
            "max_acceleration": round(max(accel), 3) if accel else 0.0,
            "measured_over_frames": len(solid),
        }

    idle_arrays = [np.asarray(Image.open(os.path.join(package, p)).convert("RGBA")).astype(np.int16)
                   for p in idle]
    diffs = [float(np.abs(idle_arrays[i + 1] - idle_arrays[i]).mean()) for i in range(len(idle_arrays) - 1)]
    seam = float(np.abs(idle_arrays[0] - idle_arrays[-1]).mean())
    worst_step = max(diffs)

    result = {
        "package": package,
        "id": manifest["id"],
        "name": manifest["name"],
        "canvas": canvas,
        "anchor": anchor,
        "app_icon": {"path": icon_rel, "size": [icon_head.get("width"), icon_head.get("height")],
                     "bytes": os.path.getsize(os.path.join(package, icon_rel)) if icon_rel else 0},
        "clips": per_clip,
        "frame_references": total_refs,
        "unique_frames": len(unique_frames),
        "shared_rest_frame": sorted({p for p in referenced if sum(p in clips[n]["frames"] for n in CLIPS) > 1}),
        "directory_entries": entries,
        "package_bytes": package_bytes,
        "unique_frame_pixels": frame_pixels,
        "icon_pixels": icon_pixels,
        "total_unique_pixels": total_pixels,
        "pixel_budget": MAX_TOTAL_PIXELS,
        "rgba_decode_estimate_mib": round(decode_bytes / 1048576, 2),
        "idle_seam_mean_abs_diff": round(seam, 3),
        "idle_mean_consecutive_diff": round(float(np.mean(diffs)), 3),
        "idle_max_consecutive_diff": round(worst_step, 3),
        "idle_seam_vs_worst_step": round(seam / worst_step, 3),
        "rest_pose_continuity": continuity,
        "silhouette_motion": motion_report,
        "alpha_coverage": coverage,
        "alpha_summary": {
            "min_transparent_fraction": round(min(v["transparent_fraction"] for v in alpha_report.values()), 4),
            "max_transparent_fraction": round(max(v["transparent_fraction"] for v in alpha_report.values()), 4),
        },
        "problems": problems,
        "verdict": "PASS" if not problems else "FAIL",
    }
    text = json.dumps(result, indent=2, ensure_ascii=False)
    if report_path:
        with open(report_path, "w") as fh:
            fh.write(text + "\n")
    print(text)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())