#!/usr/bin/env python3
"""Independent format, transparency and budget audit of a built .charpet package.

`char-package-check skin` is the authority; this records the evidence the
acceptance pass asks for: per-file PNG bit depth and colour type, real
transparency, non-empty frames, blank frames only at migration ends, frame order
and anchor, shared-frame reuse, unique-pixel budget, the RGBA decode estimate,
the idle loop seam and silhouette-motion continuity.

Usage: inspect_package.py <package-dir> [report.json]
"""

import json
import os
import re
import struct
import sys
import wave

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
    return {"width": width, "height": height, "bit_depth": depth, "colour_type": colour,
            "interlace": head[28], "animated": b"acTL" in head}


def main():
    package = os.path.abspath(sys.argv[1])
    report_path = sys.argv[2] if len(sys.argv) > 2 else None
    problems = []

    manifest_path = os.path.join(package, "manifest.json")
    manifest_bytes = os.path.getsize(manifest_path)
    manifest = json.load(open(manifest_path))
    schema = manifest.get("schemaVersion")
    if schema not in (1, 2):
        problems.append("this audit targets schemaVersion 1/2 base-animation and WAV packages")
    manifest_limit = 128 * 1024 if schema == 2 else MAX_MANIFEST_BYTES
    package_limit = 64 * 1024 * 1024 if schema == 2 else MAX_PACKAGE_BYTES
    entry_limit = 2200 if schema == 2 else MAX_ENTRIES
    reference_limit = 2048 if schema == 2 else 480
    if manifest_bytes > manifest_limit:
        problems.append(f"manifest {manifest_bytes} B exceeds {manifest_limit} B")
    features = manifest.get("features", {})
    if set(features) - {"sounds"}:
        problems.append("use the production validator for features other than sounds")
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
            if path.startswith("/") or "\\" in path or ".." in path.split("/") or not path.endswith(".png"):
                problems.append(f"{name}: unsafe frame path {path}")
            referenced.add(path)
        per_clip[name] = {"fps": spec["fps"], "frames": len(frames), "unique": len(set(frames)),
                          "duration_s": round(len(frames) / spec["fps"], 3)}
    total_refs = sum(len(clips[name]["frames"]) for name in CLIPS)
    if total_refs > reference_limit:
        problems.append(f"{total_refs} references exceed {reference_limit}")

    on_disk, entries, package_bytes = set(), 0, 0
    for root, _, files in os.walk(package):
        for name in files:
            entries += 1
            full = os.path.join(root, name)
            if os.path.islink(full):
                problems.append(f"symlink in package: {full}")
            package_bytes += os.path.getsize(full)
            on_disk.add(os.path.relpath(full, package))
    if entries > entry_limit:
        problems.append(f"{entries} directory entries exceed {entry_limit}")
    if package_bytes > package_limit:
        problems.append(f"package {package_bytes} B exceeds {package_limit} B")

    icon_rel = manifest.get("appIcon")
    image_paths = set(referenced) | ({icon_rel} if icon_rel else set())
    sounds = features.get("sounds", {})
    sound_paths = {sound["file"] for sound in sounds.values()}
    expected = image_paths | sound_paths
    if on_disk - expected - {"manifest.json"}:
        problems.append(f"unreferenced files: {sorted(on_disk - expected - {'manifest.json'})}")
    if expected - on_disk:
        problems.append(f"missing files: {sorted(expected - on_disk)}")

    headers, alpha_report, coverage = {}, {}, {}
    for rel in sorted(image_paths):
        full = os.path.join(package, rel)
        head = png_header(full)
        if head is None:
            problems.append(f"{rel}: not a PNG")
            continue
        headers[rel] = head
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
        if os.path.getsize(full) > MAX_FRAME_BYTES:
            problems.append(f"{rel}: exceeds 4 MiB")
        alpha = np.asarray(Image.open(full).convert("RGBA"))[..., 3]
        alpha_report[rel] = {"opaque_fraction": round(float((alpha >= 250).mean()), 4),
                             "transparent_fraction": round(float((alpha == 0).mean()), 4),
                             "max_alpha": int(alpha.max())}

    sound_report = {}
    for name, sound in sounds.items():
        rel = sound["file"]
        if rel.startswith("/") or "\\" in rel or any(part in ("", ".", "..") for part in rel.split("/")):
            problems.append(f"unsafe sound path: {rel}")
            continue
        full = os.path.join(package, rel)
        try:
            with wave.open(full, "rb") as audio:
                duration = audio.getnframes() / audio.getframerate()
            if not 0 < duration <= 30 or os.path.getsize(full) > 8 * 1024 * 1024:
                problems.append(f"{rel}: sound exceeds duration/size budget")
            if not 0 <= sound.get("volume", 1) <= 1 or not 0.1 <= sound.get("cooldown", 0.3) <= 60:
                problems.append(f"{rel}: invalid volume/cooldown")
            sound_report[name] = {"path": rel, "duration_s": round(duration, 3), "bytes": os.path.getsize(full)}
        except (OSError, wave.Error) as error:
            problems.append(f"{rel}: invalid WAV: {error}")

    for name in CLIPS:
        cover = []
        for rel in clips[name]["frames"]:
            cover.append(float((np.asarray(Image.open(os.path.join(package, rel)).convert("RGBA"))[..., 3] > 0).mean()))
        # Blank frames are only acceptable in a run that touches the clip head or
        # tail: those are the intended fade ends of a migration.
        allowed, count = set(), len(cover)
        k = 0
        while k < count and cover[k] == 0.0:
            allowed.add(k)
            k += 1
        k = count - 1
        while k >= 0 and cover[k] == 0.0:
            allowed.add(k)
            k -= 1
        for index, value in enumerate(cover):
            if value == 0.0 and index not in allowed:
                problems.append(f"{name} frame {index} ({clips[name]['frames'][index]}) is blank inside the clip")
        coverage[name] = {"min": round(min(cover), 4), "max": round(max(cover), 4),
                          "blank_frames": [i for i, value in enumerate(cover) if value == 0.0]}

    rest_frame = clips["idle"]["frames"][0]
    continuity = {}
    for name in CLIPS:
        if name == "idle":
            continue
        frames = clips[name]["frames"]
        continuity[name] = {
            "starts_at_rest": frames[0] == rest_frame,
            "ends_at_rest": frames[-1] == rest_frame,
            "blank_head": alpha_report.get(frames[0], {}).get("max_alpha", 0) == 0,
            "blank_tail": alpha_report.get(frames[-1], {}).get("max_alpha", 0) == 0,
        }

    def motion(name):
        rows, cache = [], {}
        for rel in clips[name]["frames"]:
            if rel not in cache:
                alpha = np.asarray(Image.open(os.path.join(package, rel)).convert("RGBA"))[..., 3]
                ys, _ = np.where(alpha > 0)
                cache[rel] = (0.0, 0.0, 0.0) if len(ys) == 0 else (float(len(ys)) / alpha.size,
                                                                    float(ys.mean()), float(ys.max() - ys.min()))
            rows.append(cache[rel])
        return rows

    motion_report = {}
    for name in CLIPS:
        rows = motion(name)
        solid = [row for row in rows if row[2] > 0]
        steps = [abs(solid[i + 1][j] - solid[i][j]) for i in range(len(solid) - 1) for j in (1, 2)]
        accel = [abs(steps[i + 1] - steps[i]) for i in range(len(steps) - 1)]
        motion_report[name] = {"centroid_y": [round(row[1], 2) for row in rows],
                               "silhouette_height": [round(row[2], 1) for row in rows],
                               "max_step": round(max(steps), 3) if steps else 0.0,
                               "max_acceleration": round(max(accel), 3) if accel else 0.0,
                               "measured_over_frames": len(solid)}

    idle_arrays = [np.asarray(Image.open(os.path.join(package, path)).convert("RGBA")).astype(np.int16)
                   for path in clips["idle"]["frames"]]
    diffs = [float(np.abs(idle_arrays[i + 1] - idle_arrays[i]).mean()) for i in range(len(idle_arrays) - 1)]
    seam = float(np.abs(idle_arrays[0] - idle_arrays[-1]).mean())
    worst = max(diffs)

    unique = sorted(referenced)
    frame_pixels = len(unique) * canvas["width"] * canvas["height"]
    icon_head = headers.get(icon_rel, {"width": 0, "height": 0})
    total_pixels = frame_pixels + icon_head["width"] * icon_head["height"]
    if total_pixels > MAX_TOTAL_PIXELS:
        problems.append(f"{total_pixels} unique pixels exceed {MAX_TOTAL_PIXELS}")

    result = {
        "package": package, "id": manifest["id"], "name": manifest["name"],
        "canvas": canvas, "anchor": anchor,
        "app_icon": {"path": icon_rel, "size": [icon_head.get("width"), icon_head.get("height")],
                     "bytes": os.path.getsize(os.path.join(package, icon_rel))},
        "clips": per_clip, "sounds": sound_report, "frame_references": total_refs, "unique_frames": len(unique),
        "shared_frames": sorted({path for path in referenced
                                 if sum(path in clips[name]["frames"] for name in CLIPS) > 1}),
        "directory_entries": entries, "package_bytes": package_bytes,
        "unique_frame_pixels": frame_pixels, "icon_pixels": icon_head["width"] * icon_head["height"],
        "total_unique_pixels": total_pixels, "pixel_budget": MAX_TOTAL_PIXELS,
        "rgba_decode_estimate_mib": round((total_pixels * 4) / 1048576, 2),
        "idle_seam_mean_abs_diff": round(seam, 3),
        "idle_mean_consecutive_diff": round(float(np.mean(diffs)), 3),
        "idle_max_consecutive_diff": round(worst, 3),
        "idle_seam_vs_worst_step": round(seam / worst, 3),
        "rest_pose_continuity": continuity, "silhouette_motion": motion_report,
        "alpha_coverage": coverage, "problems": problems,
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
