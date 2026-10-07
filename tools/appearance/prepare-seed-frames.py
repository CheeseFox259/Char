#!/usr/bin/env python3
"""Turn an AI-generated magenta-background character sheet into video seed frames.

The sheet is opaque RGB on a flat magenta plate. Scaling is done while the image
is still opaque so no alpha fringing is introduced; the matte is keyed and
unmixed at the final size instead, which keeps edges clean at 128 px.

Usage:
  tools/appearance/prepare-seed-frames.py <sheet.png> <out-dir> [figure-index]
                                        [fill 0.78] [baseline 0.92] [suffix]

figure-index picks one plate-separated figure (0 = leftmost). fill and baseline
place the character on the seed canvases: fill is its height as a share of the
canvas, baseline is where its feet sit. Use a lower baseline for the edge clips.

Outputs (all 8-bit RGBA PNG unless noted):
  <out-dir>/<name>-figure-keyed.png    native-resolution cut-out, straight alpha
  <out-dir>/<name>-seed-square.png     1024x1024 magenta plate, video seed frame
  <out-dir>/<name>-seed-wide.png       1920x1080 magenta plate, character centred
  <out-dir>/<name>-canvas-128.png      128x128 real pet canvas, framing proof
  <out-dir>/<out-dir-report.txt        measured figure boxes and key colour
"""

import os
import subprocess
import sys
import tempfile

KEY = (255, 0, 255)          # plate colour used by the generation prompt
OPAQUE_D = 40                # d = min(r,b) - g below this is never plate spill
PLATE_D = 150                # d at or above this is bare plate; generation sites
                             # dim the plate toward the corners, so the bright
                             # centre value cannot be used as the cut-off
BOX_FILL = 0.78              # character height as a share of the seed canvas
BOX_BASE = 0.92              # baseline (feet) as a share of canvas height


def probe_size(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height", "-of", "csv=p=0", path],
        capture_output=True, text=True, check=True).stdout.strip()
    w, h = out.split(",")[:2]
    return int(w), int(h)


def to_raw(path, w, h):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        capture_output=True, check=True).stdout


def from_raw(raw, w, h, path, pix="rgb24"):
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", pix,
         "-s", "%dx%d" % (w, h), "-i", "-", "-pix_fmt", "rgba", path],
        input=raw, check=True)


def resize_opaque(raw, w, h, tw, th):
    """Lanczos resize of opaque RGB; caller keys the matte afterwards."""
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (w, h), "-i", "-", "-vf",
         "scale=%d:%d:flags=lanczos" % (tw, th), "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        input=raw, capture_output=True, check=True).stdout
    return out


def unmix_key(rgb, w, h):
    """Return straight-alpha RGBA bytes for a magenta plate.

    For this palette every character colour satisfies g >= min(r, b), so the
    plate spill is exactly d = min(r, b) - g and the matte is d / 255. Partial
    pixels are then unmixed against the plate colour.
    """
    out = bytearray(w * h * 4)
    kr, kg, kb = KEY
    for i in range(w * h):
        r = rgb[3 * i]
        g = rgb[3 * i + 1]
        b = rgb[3 * i + 2]
        m = r if r < b else b
        d = m - g
        o = 4 * i
        if d <= OPAQUE_D:
            out[o] = r
            out[o + 1] = g
            out[o + 2] = b
            out[o + 3] = 255
        elif d >= PLATE_D:
            out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0
        else:
            a = d / 255.0
            inv = 1.0 - a
            for ci, (c, k) in enumerate(((r, kr), (g, kg), (b, kb))):
                v = int(round((c - k * inv) / a))
                out[o + ci] = 0 if v < 0 else 255 if v > 255 else v
            out[o + 3] = int(round(a * 255))
    return out


def alpha_box(rgba, w, h, threshold=12, xlo=0, xhi=None):
    xhi = w - 1 if xhi is None else xhi
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = 4 * y * w
        for x in range(xlo, xhi + 1):
            if rgba[row + 4 * x + 3] > threshold:
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    return x0, y0, x1, y1


def column_groups(rgba, w, h, threshold=12, min_gap=4):
    """Split the sheet into figures by fully transparent column runs."""
    solid = bytearray(w)
    for x in range(w):
        solid[x] = 1
        for y in range(0, h, 2):
            if rgba[4 * (y * w + x) + 3] > threshold:
                break
        else:
            solid[x] = 0
    groups, start, gap = [], None, 0
    for x in range(w):
        if solid[x]:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                groups.append((start, x - gap))
                start = None
    if start is not None:
        groups.append((start, w - 1))
    return groups


def cut(rgb, w, h, box):
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(cw * ch * 3)
    for y in range(ch):
        src = ((y0 + y) * w + x0) * 3
        out[3 * y * cw:3 * (y + 1) * cw] = rgb[src:src + cw * 3]
    return out, cw, ch


def plate(w, h):
    return bytearray(bytes(KEY) * (w * h))


def paste(dst, dw, src, sw, sh, ox, oy):
    for y in range(sh):
        d = 3 * ((oy + y) * dw + ox)
        s = 3 * y * sw
        dst[d:d + 3 * sw] = src[s:s + 3 * sw]
    return dst


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sheet, outdir = sys.argv[1], sys.argv[2]
    pick = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    box_fill = float(sys.argv[4]) if len(sys.argv) > 4 else BOX_FILL
    box_base = float(sys.argv[5]) if len(sys.argv) > 5 else BOX_BASE
    suffix = sys.argv[6] if len(sys.argv) > 6 else ""
    os.makedirs(outdir, exist_ok=True)
    name = os.path.splitext(os.path.basename(sheet))[0] + suffix

    w, h = probe_size(sheet)
    rgb = to_raw(sheet, w, h)
    rgba = unmix_key(rgb, w, h)
    groups = column_groups(rgba, w, h)
    report = ["sheet %dx%d, %d plate-separated figures" % (w, h, len(groups))]
    for i, (gx0, gx1) in enumerate(groups):
        bx0, by0, bx1, by1 = alpha_box(rgba, w, h, xlo=gx0, xhi=gx1)
        report.append("  figure %d columns %d..%d box x=%d y=%d w=%d h=%d"
                      % (i, gx0, gx1, bx0, by0, bx1 - bx0 + 1, by1 - by0 + 1))
    if not groups:
        sys.exit("no figures found: is the background flat %s?" % (KEY,))
    if pick >= len(groups):
        sys.exit("figure %d requested, only %d found" % (pick, len(groups)))

    gx0, gx1 = groups[pick]
    x0, y0, x1, y1 = alpha_box(rgba, w, h, xlo=gx0, xhi=gx1)
    report.append("  chosen figure %d box x=%d y=%d w=%d h=%d" % (pick, x0, y0, x1 - x0 + 1, y1 - y0 + 1))
    cutrgb, cw, ch = cut(rgb, w, h, (x0, y0, x1, y1))
    report.append("  source aspect %.4f" % (cw / ch))
    keyed = unmix_key(cutrgb, cw, ch)
    from_raw(keyed, cw, ch, os.path.join(outdir, name + "-figure-keyed.png"), "rgba")
    edge = sum(1 for i in range(cw * ch) if 0 < keyed[4 * i + 3] < 255)
    report.append("  keyed cut-out %dx%d, %d anti-aliased edge pixels" % (cw, ch, edge))

    for label, (cw2, ch2) in (("seed-square", (1024, 1024)), ("seed-wide", (1920, 1080)),
                              ("canvas-128", (128, 128))):
        target_h = int(round(ch2 * box_fill))
        scale = target_h / ch
        target_w = max(1, int(round(cw * scale)))
        if target_w > cw2:
            scale = cw2 / cw
            target_w = cw2
            target_h = int(round(ch * scale))
        resized = resize_opaque(cutrgb, cw, ch, target_w, target_h)
        canvas = plate(cw2, ch2)
        ox = (cw2 - target_w) // 2
        oy = int(round(ch2 * box_base)) - target_h
        if oy < 0:
            oy = 0
        paste(canvas, cw2, resized, target_w, target_h, ox, oy)
        from_raw(canvas, cw2, ch2, os.path.join(outdir, "%s-%s.png" % (name, label)))
        if label == "canvas-128":
            from_raw(unmix_key(canvas, cw2, ch2), cw2, ch2,
                     os.path.join(outdir, "%s-canvas-128-keyed.png" % name), "rgba")
        report.append("  %-12s canvas %dx%d character %dx%d at x=%d y=%d (fill %.1f%%)"
                      % (label, cw2, ch2, target_w, target_h, ox, oy, 100.0 * target_h / ch2))

    with open(os.path.join(outdir, name + "-report.txt"), "w") as fh:
        fh.write("\n".join(report) + "\n")
    print("\n".join(report))


if __name__ == "__main__":
    main()
