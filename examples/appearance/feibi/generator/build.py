"""Affine rig and icon composition helpers for showcase.py."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

def matrix(pose, ss, pivot):
    """Forward map from canvas coordinates to canvas coordinates, at SS scale."""
    px, py = pivot[0] * ss, pivot[1] * ss
    theta = math.radians(pose["rot"])
    cos, sin = math.cos(theta), math.sin(theta)
    to_pivot = np.array([[1, 0, px], [0, 1, py], [0, 0, 1]], float)
    from_pivot = np.array([[1, 0, -px], [0, 1, -py], [0, 0, 1]], float)
    shear = np.array([[1, pose["skew"], 0], [0, 1, 0], [0, 0, 1]], float)
    rotation = np.array([[cos, -sin, 0], [sin, cos, 0], [0, 0, 1]], float)
    scale = np.array([[pose["sx"], 0, 0], [0, pose["sy"], 0], [0, 0, 1]], float)
    move = np.array([[1, 0, pose["dx"] * ss], [0, 1, pose["dy"] * ss], [0, 0, 1]], float)
    return move @ to_pivot @ shear @ rotation @ scale @ from_pivot


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


def build_icon(rest_image, canvas, size=512):
    """Static software icon: same peek language as the host, sized for 18 px.

    The user asked for the host's peek composition (rounded gradient tile, screen
    edge line, the same character), so those proportions are kept; the character
    is then scaled up until the hat and eyes still read in an 18 px menu bar.
    """
    inset = int(round(size * 0.078))
    radius = int(round(size * 0.213))
    edge_x = int(round(size * 0.762))
    w = int(round(size * 0.86))
    tile = rounded_tile(size, inset, radius, (0.97, 0.98, 1.00), (0.88, 0.93, 0.99))

    src = rest_image.resize((canvas, canvas), Image.LANCZOS).rotate(90, expand=True, resample=Image.BICUBIC)
    src = src.resize((w, w), Image.LANCZOS)
    left, top = int(round(size * 0.055)), int(round((size - w) / 2))

    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body.paste(src, (left, top), src)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (size, size), (16, 12, 24, 56)), (-2, 5),
                 body.split()[3].filter(ImageFilter.GaussianBlur(size * 0.020)))

    clip_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(clip_mask).rectangle([0, 0, edge_x, size], fill=255)
    empty = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile.alpha_composite(Image.composite(shadow, empty, clip_mask))
    tile.alpha_composite(Image.composite(body, empty, clip_mask))

    draw = ImageDraw.Draw(tile)
    draw.rectangle([edge_x, inset, edge_x + 3, size - inset], fill=(133, 153, 184, 115))
    draw.rectangle([edge_x + 3, inset, edge_x + 7, size - inset], fill=(255, 255, 255, 204))
    return tile
