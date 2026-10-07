"""Alpha-correct layer resampling and eye paint helpers for showcase.py."""
import numpy as np
from PIL import Image,ImageDraw
INK_LEVEL=120

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
    the region is solved on a coarse block grid (valid-pixel means) and the
    upsampled result seeds the full-resolution refinement. Ink on the rim would
    seed the coarse solve with dark averages, so blocks count only skin pixels.
    """
    ys, xs = np.where(mask)
    y0, x0 = max(int(ys.min()) - 2, 0), max(int(xs.min()) - 2, 0)
    y1, x1 = min(int(ys.max()) + 3, rgb.shape[0]), min(int(xs.max()) + 3, rgb.shape[1])
    sub = rgb[y0:y1, x0:x1].astype(np.float32).copy()
    hole = mask[y0:y1, x0:x1]

    ch, cw = sub.shape[0] // coarse, sub.shape[1] // coarse
    blocks = sub[:ch * coarse, :cw * coarse].reshape(ch, coarse, cw, coarse, 3)
    blocks = blocks.transpose(0, 2, 1, 3, 4).reshape(ch, cw, coarse * coarse, 3)
    valid = ~hole[:ch * coarse, :cw * coarse].reshape(ch, coarse, cw, coarse)
    valid = valid.transpose(0, 2, 1, 3).reshape(ch, cw, coarse * coarse)
    ink = sub.min(axis=2) < INK_LEVEL
    ink = ink[:ch * coarse, :cw * coarse].reshape(ch, coarse, cw, coarse).transpose(0, 2, 1, 3)
    ink = ink.reshape(ch, cw, coarse * coarse)
    weight = (valid & ~ink).astype(np.float32)
    count = weight.sum(axis=2, keepdims=True)
    coarse_field = np.where(count > 0, (blocks * weight[..., None]).sum(axis=2) / np.maximum(count, 1),
                             0.0).astype(np.float32)
    coarse_field = _jacobi(coarse_field, (count < 0.5 * coarse * coarse)[..., 0], coarse_iters)

    up = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(coarse_field[..., c], dtype=np.float32),
                                               mode="F").resize((sub.shape[1], sub.shape[0]), Image.BILINEAR),
                            dtype=np.float32) for c in range(3)], axis=-1)
    sub = _jacobi(np.where(hole[..., None], up, sub), hole, fine_iters)

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
    points = []
    for i in range(65):
        t = i / 64
        points.append(((1 - t) ** 2 * left + 2 * (1 - t) * t * ctrl[0] + t * t * right,
                       (1 - t) ** 2 * y + 2 * (1 - t) * t * ctrl[1] + t * t * y))
    draw.line(points, fill=ink, width=width, joint="curve")
    for px, py in (points[0], points[-1]):
        r = width / 2
        draw.ellipse([px - r, py - r, px + r, py + r], fill=ink)


def resize_premultiplied(image, size):
    """Alpha-correct resize: premultiply, resample, unpremultiply."""
    data = np.asarray(image).astype(np.float32) / 255.0
    alpha = data[..., 3:4]
    planes = [Image.fromarray(np.ascontiguousarray(np.dstack([data[..., :3] * alpha, alpha])[..., i],
                                                 dtype=np.float32), mode="F").resize(size, Image.LANCZOS)
              for i in range(4)]
    out = np.stack([np.asarray(p, dtype=np.float32) for p in planes], axis=-1)
    out[..., 3] = np.clip(out[..., 3], 0.0, 1.0)
    safe = np.maximum(out[..., 3:4], 1e-5)
    rgb = np.where(out[..., 3:4] > 1e-5, out[..., :3] / safe, 0.0)
    return Image.fromarray(np.clip(np.dstack([rgb, out[..., 3]]) * 255.0, 0, 255).astype(np.uint8), "RGBA")
