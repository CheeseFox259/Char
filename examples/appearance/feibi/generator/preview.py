#!/usr/bin/env python3
"""Offline previews for the 菲比 charpet: clip sheets, looping WebP, edge study, icon sizes.

Nothing here is imported by Char; it only lets the package be reviewed before it
reaches the app. The edge study rotates each peek frame the way the host orients
a bottom-authored clip and clips it against a mock screen edge, which catches
framing errors offline even though the real placement still needs the app.

Usage: preview.py <work-dir> <package-dir>
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

PREVIEW_SCALE = 2
# CompanionGeometry.edgeRotation: degrees applied to the bottom-authored clip. The host
# only rotates while an edge clip is playing (CompanionPanel.drawPet), so the settled
# pose is drawn unrotated and both states are shown side by side.
EDGE_ROTATION = {"bottom": 0, "right": 90, "top": 180, "left": -90}
# Runtime.position: the pet centre sits EDGE_INSET points inside the chosen edge.
EDGE_INSET = 8.0
CROP = (320.0, 210.0)        # visible area shown, in points


def checkerboard(size, cell=8):
    y, x = np.mgrid[0:size, 0:size]
    board = (((x // cell) + (y // cell)) % 2) * 27 + 198
    return Image.fromarray(np.dstack([board] * 3).astype(np.uint8), "RGB")


def desk_gradient(size):
    ramp = np.linspace(206, 232, size, dtype=np.float32)
    return Image.fromarray(np.dstack([ramp[:, None].repeat(size, 1),
                                      (ramp + 7)[:, None].repeat(size, 1),
                                      (ramp + 16)[:, None].repeat(size, 1)]).astype(np.uint8), "RGB")


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


def placement_study(rows, path, pet_sizes=(48, 88), scale=2.0):
    """Each edge exactly as the host composes it.

    rows is a list of (label, frame, rotated) so the playing edge clip and the settled
    idle pose can be compared: the canvas centre is EDGE_INSET points inside the edge,
    the frame is petSize square, and all edge-placement frames carry edgeRotation.
    """
    width, height = int(CROP[0] * scale), int(CROP[1] * scale)
    header, gap = 22, 8
    columns = [(edge, ps) for edge in EDGE_ROTATION for ps in pet_sizes]
    canvas = Image.new("RGB", (len(columns) * (width + gap) + gap,
                               len(rows) * (height + header + gap) + gap), (252, 252, 254))
    draw = ImageDraw.Draw(canvas)
    backdrop = desk_gradient(max(width, height)).convert("RGBA").crop((0, 0, width, height))
    for col, (edge, ps) in enumerate(columns):
        horizontal = edge in ("top", "bottom")
        cx = width / 2 if horizontal else EDGE_INSET * scale
        cy = height - EDGE_INSET * scale if horizontal else height / 2
        side = ps * scale
        for row, (label, image, rotated) in enumerate(rows):
            shot = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            shot.alpha_composite(backdrop)
            art = image.rotate(EDGE_ROTATION[edge] if rotated else 0, expand=True, resample=Image.BICUBIC)
            art = art.resize((int(side), int(side)), Image.LANCZOS)
            shot.paste(art, (int(cx - side / 2), int(cy - side / 2)), art)
            bar = {"bottom": (0, height - 3, width, height), "top": (0, 0, width, 3),
                   "left": (0, 0, 3, height), "right": (width - 3, 0, width, height)}[edge]
            ImageDraw.Draw(shot).rectangle(bar, fill=(52, 52, 60, 255))
            y = gap + header + row * (height + header + gap)
            canvas.paste(shot.convert("RGB"), (gap + col * (width + gap), y))
            draw.text((gap + col * (width + gap) + 4, y - 13), f"{edge} · {ps}pt · {label}",
                      fill=(55, 55, 65))
    canvas.save(path)


def icon_sizes(icon, out_dir):
    strips = []
    for px in (18, 32, 64, 128):
        small = icon.resize((px, px), Image.LANCZOS)
        small.save(os.path.join(out_dir, f"icon-{px}.png"))
        zoom = small.resize((px * 6, px * 6), Image.NEAREST)
        board = Image.new("RGB", (px * 6 + 20, px * 6 + 30), (255, 255, 255))
        board.paste(Image.alpha_composite(Image.new("RGBA", zoom.size, (243, 243, 246, 255)), zoom).convert("RGB"), (10, 22))
        ImageDraw.Draw(board).text((10, 6), f"{px}px, shown 6x", fill=(20, 20, 20))
        strips.append(board)
    row = Image.new("RGB", (sum(s.width for s in strips), max(s.height for s in strips)), (255, 255, 255))
    x = 0
    for s in strips:
        row.paste(s, (x, 0))
        x += s.width
    row.save(os.path.join(out_dir, "icon-sizes.png"))
    icon.save(os.path.join(out_dir, "icon-512.png"))


def main():
    work, package = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    out = os.path.join(work, "preview")
    os.makedirs(out, exist_ok=True)
    manifest = json.load(open(os.path.join(package, "manifest.json")))

    page = ["<!doctype html><meta charset='utf-8'><title>菲比 charpet 离线预览</title>",
            "<style>body{font:14px/1.6 -apple-system,system-ui,sans-serif;margin:28px;background:#fbfbfd;color:#222}",
            "h2{font-size:16px;margin:26px 0 4px}img{background:#fff;border:1px solid #ddd}",
            ".row{display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start}figure{margin:0}",
            "figcaption{font-size:12px;color:#666;text-align:center;margin-top:4px}</style><body>",
            "<h1>菲比 · charpet 离线预览</h1>",
            "<p>canvas 128×128 · 24 fps · idle 48 帧首尾衔接循环。edgePeek / edgeHide 按宿主朝向旋转画布后贴到模拟屏幕边，"
            "用于离线检查构图；真实边缘裁切仍需在 Char 里实际放置确认。</p>"]
    for name, spec in manifest["clips"].items():
        frames = [Image.open(os.path.join(package, p)).convert("RGBA") for p in spec["frames"]]
        big = [f.resize((128 * PREVIEW_SCALE, 128 * PREVIEW_SCALE), Image.LANCZOS) for f in frames]
        sheet(frames, [f"{i:02d}" for i in range(len(frames))], os.path.join(out, f"{name}-sheet.png"))
        big[0].save(os.path.join(out, f"{name}.webp"), save_all=True, append_images=big[1:],
                    duration=int(1000 / spec["fps"]), loop=0, lossless=True, quality=100)
        if name in ("edgePeek", "edgeHide"):
            rest = Image.open(os.path.join(package, manifest["clips"]["idle"]["frames"][0])).convert("RGBA")
            placement_study([("edgePeek 末帧 · 宿主已旋转", frames[-1], True),
                             ("落位后 idle · 保持边缘朝向", rest, True)],
                            os.path.join(out, f"{name}-edges.png"))
        page.append(f"<h2>{name} — {len(frames)} 帧 @ {spec['fps']} fps</h2><div class='row'>")
        page.append(f"<figure><img src='{name}.webp' width='{128 * PREVIEW_SCALE}'><figcaption>循环播放</figcaption></figure>")
        page.append(f"<figure><img src='{name}-sheet.png'><figcaption>逐帧（编号即 manifest 顺序）</figcaption></figure>")
        if name in ("edgePeek", "edgeHide"):
            page.append(f"<figure><img src='{name}-edges.png'><figcaption>四边预演：上=边缘动作（按宿主朝向旋转），下=落位后 idle（宿主在全部边缘动作和闲置期间保持朝向）</figcaption></figure>")
        page.append("</div>")

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