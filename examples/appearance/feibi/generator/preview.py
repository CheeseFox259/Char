#!/usr/bin/env python3
"""Offline previews for the 菲比 charpet.

Produces everything the acceptance pass asks to look at without the host:
per-clip contact sheets, looping RGBA WebP, the transparent base on checkerboard /
black / white at 36, 48 and 88 pt, an open/blink/happy eye close-up, edge studies
for peek, settled idle and hidden using the real 8 pt inset, and icon sizes.

Usage: preview.py <work-dir> [package-dir]
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PREVIEW_SCALE = 2
# CompanionGeometry.edgeRotation: degrees applied to the bottom-authored clip. The host
# keeps that orientation for every clip at an edge placement, including settled idle.
EDGE_ROTATION = {"bottom": 0, "right": 90, "top": 180, "left": -90}
# Runtime.position: the pet centre sits EDGE_INSET points inside the chosen edge.
EDGE_INSET = 8.0
CROP = (320.0, 210.0)        # visible area shown in an edge study, in points
SIZES = (36, 48, 88)         # host pet sizes, points


def checkerboard(size, cell=8):
    y, x = np.mgrid[0:size, 0:size]
    board = (((x // cell) + (y // cell)) % 2) * 27 + 198
    return Image.fromarray(np.dstack([board] * 3).astype(np.uint8), "RGB")


def flat(size, level):
    return Image.new("RGB", (size, size), (level, level, level))


def desk_gradient(width, height):
    ramp = np.linspace(206, 232, height, dtype=np.float32)
    return Image.fromarray(np.dstack([ramp[:, None].repeat(width, 1),
                                      (ramp + 7)[:, None].repeat(width, 1),
                                      (ramp + 16)[:, None].repeat(width, 1)]).astype(np.uint8), "RGB")


def sheet(frames, labels, path, columns=8):
    pad, top, tile = 6, 14, 128
    rows = (len(frames) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * (tile + pad) + pad, rows * (tile + pad + top) + pad), (255, 255, 255))
    for i, (frame, label) in enumerate(zip(frames, labels)):
        board = checkerboard(tile).convert("RGBA")
        board.alpha_composite(frame.resize((tile, tile), Image.LANCZOS))
        x = pad + (i % columns) * (tile + pad)
        y = pad + (i // columns) * (tile + pad + top)
        canvas.paste(board.convert("RGB"), (x, y))
        ImageDraw.Draw(canvas).text((x + 3, y + tile + 3), label, fill=(40, 40, 40))
    canvas.save(path)


def base_check(frame, path, zoom=3):
    """Transparent base on checkerboard, black and white at the host pet sizes."""
    pad, gap, label = 10, 10, 16
    cell = 200
    canvas = Image.new("RGB", (3 * (cell + gap) + gap, len(SIZES) * (cell + gap + label) + gap), (245, 245, 248))
    draw = ImageDraw.Draw(canvas)
    for row, points in enumerate(SIZES):
        pixels = max(1, int(round(points * 2 * zoom)))
        art = frame.resize((pixels, pixels), Image.LANCZOS)
        for col, background in enumerate((checkerboard, lambda n: flat(n, 24), lambda n: flat(n, 244))):
            board = background(cell).convert("RGBA")
            board.alpha_composite(art, ((cell - pixels) // 2, (cell - pixels) // 2))
            canvas.paste(board.convert("RGB"), (gap + col * (cell + gap), gap + row * (cell + gap + label)))
        draw.text((gap + 2, gap + row * (cell + gap + label) + cell + 2), f"{points} pt · 棋盘 / 黑 / 白",
                  fill=(60, 60, 70))
    canvas.save(path)


def eye_compare(work, path, zoom=2):
    """Open / blink / happy close-up of the same eye region."""
    rig = json.load(open(os.path.join(work, "art", "rig.json")))
    side = rig["canvas"] * rig["supersample"]
    blobs = rig["eye_blobs_canvas"]
    x0 = max(min(b[0] for b in blobs) - 30, 0)
    y0 = max(min(b[1] for b in blobs) - 70, 0)
    x1 = min(max(b[2] for b in blobs) + 30, side)
    y1 = min(max(b[3] for b in blobs) + 30, side)
    names = ["open", "blink", "happy"]
    titles = ["睁眼 open", "眨眼 blink（上弯）", "笑眼 happy（下弯）"]
    width = (x1 - x0) * zoom
    out = Image.new("RGB", (3 * (width + 10) + 10, (y1 - y0) * zoom + 34), (252, 252, 254))
    draw = ImageDraw.Draw(out)
    for i, name in enumerate(names):
        crop = Image.open(os.path.join(work, "art", f"{name}-{side}.png")).convert("RGBA").crop((x0, y0, x1, y1))
        board = checkerboard((x1 - x0) * zoom).convert("RGBA")
        board.alpha_composite(crop.resize(((x1 - x0) * zoom, (y1 - y0) * zoom), Image.LANCZOS))
        out.paste(board.convert("RGB"), (10 + i * (width + 10), 28))
        draw.text((12 + i * (width + 10), 8), titles[i], fill=(30, 30, 40))
    out.save(path)


def edge_study(rows, path, pet_sizes=SIZES, scale=2.0):
    """Each edge as the host composites it, at the real 8 pt inset.

    rows is (label, frame, rotated): peek and settled idle carry the edge
    orientation, while the hidden state has nothing left on screen.
    """
    width, height = int(CROP[0] * scale), int(CROP[1] * scale)
    header, gap = 22, 8
    columns = [(edge, size) for edge in EDGE_ROTATION for size in pet_sizes]
    canvas = Image.new("RGB", (len(columns) * (width + gap) + gap,
                               len(rows) * (height + header + gap) + gap), (252, 252, 254))
    draw = ImageDraw.Draw(canvas)
    backdrop = desk_gradient(width, height).convert("RGBA")
    bars = {"bottom": (0, height - 3, width, height), "top": (0, 0, width, 3),
            "left": (0, 0, 3, height), "right": (width - 3, 0, width, height)}
    for col, (edge, size) in enumerate(columns):
        horizontal = edge in ("top", "bottom")
        cx = width / 2 if horizontal else EDGE_INSET * scale
        cy = height - EDGE_INSET * scale if horizontal else height / 2
        side = size * scale
        for row, (label, image, rotated) in enumerate(rows):
            shot = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            shot.alpha_composite(backdrop)
            if image is not None:
                art = image.rotate(EDGE_ROTATION[edge] if rotated else 0, expand=True, resample=Image.BICUBIC)
                art = art.resize((int(side), int(side)), Image.LANCZOS)
                shot.paste(art, (int(cx - side / 2), int(cy - side / 2)), art)
            ImageDraw.Draw(shot).rectangle(bars[edge], fill=(52, 52, 60, 255))
            y = gap + header + row * (height + header + gap)
            canvas.paste(shot.convert("RGB"), (gap + col * (width + gap), y))
            draw.text((gap + col * (width + gap) + 4, y - 13),
                      f"{edge} · {size}pt · {label}", fill=(55, 55, 65))
    canvas.save(path)


def icon_sizes(icon, out_dir):
    strips = []
    for px in (18, 32, 64, 128):
        small = icon.resize((px, px), Image.LANCZOS)
        small.save(os.path.join(out_dir, f"icon-{px}.png"))
        zoom = small.resize((px * 6, px * 6), Image.NEAREST)
        board = Image.new("RGB", (px * 6 + 20, px * 6 + 30), (255, 255, 255))
        board.paste(Image.alpha_composite(Image.new("RGBA", zoom.size, (243, 243, 246, 255)), zoom).convert("RGB"),
                    (10, 22))
        ImageDraw.Draw(board).text((10, 6), f"{px}px, shown 6x", fill=(20, 20, 20))
        strips.append(board)
    row = Image.new("RGB", (sum(s.width for s in strips), max(s.height for s in strips)), (255, 255, 255))
    x = 0
    for strip in strips:
        row.paste(strip, (x, 0))
        x += strip.width
    row.save(os.path.join(out_dir, "icon-sizes.png"))
    icon.save(os.path.join(out_dir, "icon-512.png"))


def main():
    work = os.path.abspath(sys.argv[1])
    package = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(work, "packages", "feibi.charpet")
    out = os.path.join(work, "preview")
    os.makedirs(out, exist_ok=True)
    manifest = json.load(open(os.path.join(package, "manifest.json")))
    rest_path = manifest["clips"]["idle"]["frames"][0]
    rest = Image.open(os.path.join(package, rest_path)).convert("RGBA")

    page = ["<!doctype html><meta charset='utf-8'><title>菲比 charpet 离线预览</title>",
            "<style>body{font:14px/1.6 -apple-system,system-ui,sans-serif;margin:28px;background:#fbfbfd;color:#222}",
            "h2{font-size:16px;margin:26px 0 4px}img{background:#fff;border:1px solid #ddd}",
            ".row{display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start}figure{margin:0}",
            "figcaption{font-size:12px;color:#666;text-align:center;margin-top:4px}</style><body>",
            "<h1>菲比 · charpet 离线预览</h1>",
            "<p>128×128 画布 · 24 fps · idle 48 帧首尾衔接循环。边缘预演按宿主真实几何（中心距屏边 8pt，"
            "左右裁切）分别画探出、落位 idle 与隐藏三态；宿主保留边缘朝向，真实裁切仍需在 Char 里确认。</p>",
            "<h2>透明基准图 · 棋盘/黑/白 × 36/48/88pt</h2><div class='row'><figure>",
            f"<img src='base-check.png'><figcaption>同一帧在三种背景与三种桌宠尺寸下的边缘</figcaption></figure>",
            f"<img src='eyes-compare.png'><figcaption>表情遮罩：睁眼 / 眨眼 / 笑眼局部对照</figcaption></figure></div>"]
    base_check(rest, os.path.join(out, "base-check.png"))
    eye_compare(work, os.path.join(out, "eyes-compare.png"))

    for name, spec in manifest["clips"].items():
        frames = [Image.open(os.path.join(package, path)).convert("RGBA") for path in spec["frames"]]
        big = [frame.resize((128 * PREVIEW_SCALE, 128 * PREVIEW_SCALE), Image.LANCZOS) for frame in frames]
        sheet(frames, [f"{i:02d}" for i in range(len(frames))], os.path.join(out, f"{name}-sheet.png"))
        big[0].save(os.path.join(out, f"{name}.webp"), save_all=True, append_images=big[1:],
                    duration=int(1000 / spec["fps"]), loop=0, lossless=True, quality=100)
        if name == "edgePeek":
            rising = frames[len(frames) // 2]
            edge_study([("edgePeek 末帧", frames[-1], True),
                        ("落位后 idle（同向）", rest, True),
                        ("edgePeek 中途（部分露出）", rising, True)],
                       os.path.join(out, "edge-poses.png"))
            page.append("<h2>四边三态</h2><div class='row'>")
            page.append("<figure><img src='edge-poses.png'>"
                        "<figcaption>四边 × 36/48/88pt：探出末帧、落位 idle、探出中途"
                        "（完全隐藏的首尾帧为全透明，见逐帧表）</figcaption></figure></div>")
        page.append(f"<h2>{name} — {len(frames)} 帧 @ {spec['fps']} fps</h2><div class='row'>")
        page.append(f"<figure><img src='{name}.webp' width='{128 * PREVIEW_SCALE}'><figcaption>循环播放</figcaption></figure>")
        page.append(f"<figure><img src='{name}-sheet.png'><figcaption>逐帧（编号即 manifest 顺序）</figcaption></figure></div>")

    icon = Image.open(os.path.join(package, manifest["appIcon"])).convert("RGBA")
    icon_sizes(icon, out)
    page.append("<h2>软件 / 状态栏图标</h2><div class='row'>")
    page.append("<figure><img src='icon-sizes.png'><figcaption>18px 状态栏 · 64px 软件图标</figcaption></figure>")
    page.append("<figure><img src='icon-512.png' width='256'><figcaption>512 实际像素</figcaption></figure>")
    page.append("</div></body>")
    with open(os.path.join(out, "index.html"), "w") as fh:
        fh.write("\n".join(page))
    print(f"previews written to {out}")


if __name__ == "__main__":
    main()