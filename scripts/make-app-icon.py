#!/usr/bin/env python3
"""Generate the RubikSolver macOS application icon.

The icon is drawn from scratch at 2x and downsampled, so the checked-in
AppIcon.icns can be reproduced without any external artwork:

    python3 scripts/make-app-icon.py
    python3 scripts/make-app-icon.py --preview /tmp/RubikSolver-icon.png
"""

import argparse
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2
CANVAS = SIZE * SCALE

BACKGROUND_TOP = (31, 41, 59)
BACKGROUND_BOTTOM = (6, 8, 12)
PLASTIC = (9, 11, 16)

WHITE = (245, 246, 248)
GREEN = (34, 197, 94)
RED = (239, 68, 68)


def scaled(value):
    return int(round(value * SCALE))


def vertical_gradient(size, top, bottom):
    width, height = size
    strip = Image.new("RGB", (1, height))
    pixels = strip.load()
    for y in range(height):
        t = y / max(1, height - 1)
        pixels[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return strip.resize((width, height), Image.Resampling.NEAREST)


def draw_sticker(face, box, color, radius):
    x0, y0, x1, y1 = box
    width = x1 - x0 + 1
    height = y1 - y0 + 1
    sticker = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sticker)
    draw.rounded_rectangle([0, 0, width - 1, height - 1], radius,
                           fill=color + (255,))

    # A soft top-to-middle gloss makes the sticker read as glossy plastic.
    gloss = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gloss_draw = ImageDraw.Draw(gloss)
    half = max(1, height // 2)
    for y in range(half):
        alpha = int(52 * (1.0 - y / half))
        gloss_draw.line([(0, y), (width, y)], fill=(255, 255, 255, alpha))
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, height - 1],
                                           radius, fill=255)
    gloss.putalpha(ImageChops.multiply(gloss.getchannel("A"), mask))
    sticker.alpha_composite(gloss)

    # A dark inner edge separates neighbouring stickers without a heavy grid.
    draw = ImageDraw.Draw(sticker)
    draw.rounded_rectangle([0, 0, width - 1, height - 1], radius,
                           outline=(0, 0, 0, 55), width=max(1, SCALE))
    face.alpha_composite(sticker, (x0, y0))


def flat_face(colors):
    """Render one 3x3 face as a flat texture before projecting it."""
    face_size = scaled(720)
    face = Image.new("RGBA", (face_size, face_size), PLASTIC + (255,))
    cell = face_size / 3.0
    inset = cell * 0.065
    radius = int(cell * 0.13)
    for row in range(3):
        for col in range(3):
            color = colors[row][col]
            x0 = int(col * cell + inset)
            y0 = int(row * cell + inset)
            x1 = int((col + 1) * cell - inset) - 1
            y1 = int((row + 1) * cell - inset) - 1
            draw_sticker(face, (x0, y0, x1, y1), color, radius)
    return face


def warp_face(face, origin, u_axis, v_axis):
    """Project a flat square face onto a parallelogram in the canvas."""
    face_size = face.width
    ox, oy = origin
    ux, uy = u_axis
    vx, vy = v_axis
    determinant = ux * vy - uy * vx
    a = face_size * vy / determinant
    b = -face_size * vx / determinant
    c = face_size * (oy * vx - ox * vy) / determinant
    d = -face_size * uy / determinant
    e = face_size * ux / determinant
    f = face_size * (uy * ox - ux * oy) / determinant
    return face.transform((CANVAS, CANVAS), Image.Transform.AFFINE,
                          (a, b, c, d, e, f),
                          resample=Image.Resampling.BICUBIC)


def add_glow(canvas, mask, box, color, blur_radius):
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(blur_radius))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    canvas.alpha_composite(layer)


def build_icon():
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    inset = scaled(42)
    radius = scaled(190)

    # Drop shadow for the rounded-square tile.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [inset, inset + scaled(14), CANVAS - inset, CANVAS - inset + scaled(14)],
        radius, fill=(0, 0, 0, 135))
    shadow = shadow.filter(ImageFilter.GaussianBlur(scaled(26)))
    canvas.alpha_composite(shadow)

    tile_mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle(
        [inset, inset, CANVAS - inset, CANVAS - inset], radius, fill=255)

    background = vertical_gradient((CANVAS, CANVAS),
                                   BACKGROUND_TOP, BACKGROUND_BOTTOM)
    canvas.paste(background, (0, 0), tile_mask)

    # Colour glows echo the cube stickers and lift the dark background.
    add_glow(canvas, tile_mask,
             [-scaled(240), -scaled(260), scaled(720), scaled(520)],
             (34, 197, 94, 78), scaled(190))
    add_glow(canvas, tile_mask,
             [scaled(430), scaled(520), scaled(1280), scaled(1280)],
             (56, 132, 255, 82), scaled(210))

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [inset, inset, CANVAS - inset, CANVAS - inset], radius,
        outline=(255, 255, 255, 42), width=max(1, scaled(3)))
    draw.rounded_rectangle(
        [inset + scaled(4), inset + scaled(4),
         CANVAS - inset - scaled(4), CANVAS - inset - scaled(4)],
        radius - scaled(4), outline=(255, 255, 255, 16),
        width=max(1, scaled(1)))

    # Isometric cube geometry in 1024-point coordinates.
    top = (scaled(512), scaled(168))
    right = (scaled(820), scaled(346))
    center = (scaled(512), scaled(524))
    left = (scaled(204), scaled(346))
    bottom_left = (scaled(204), scaled(686))
    bottom_right = (scaled(820), scaled(686))
    bottom = (scaled(512), scaled(864))
    silhouette = [top, right, bottom_right, bottom, bottom_left, left]

    cube_shadow = Image.new("L", (CANVAS, CANVAS), 0)
    shifted = [(x, y + scaled(22)) for x, y in silhouette]
    ImageDraw.Draw(cube_shadow).polygon(shifted, fill=170)
    cube_shadow = cube_shadow.filter(ImageFilter.GaussianBlur(scaled(24)))
    shadow_layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_layer.putalpha(cube_shadow)
    canvas.alpha_composite(shadow_layer)

    white_face = flat_face([[WHITE for _ in range(3)] for _ in range(3)])
    green_face = flat_face([[GREEN for _ in range(3)] for _ in range(3)])
    red_face = flat_face([[RED for _ in range(3)] for _ in range(3)])

    cube = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Left and right faces first; the top face then closes the shared edges.
    left_u = (center[0] - left[0], center[1] - left[1])
    left_v = (bottom_left[0] - left[0], bottom_left[1] - left[1])
    cube.alpha_composite(warp_face(green_face, left, left_u, left_v))

    right_u = (right[0] - center[0], right[1] - center[1])
    right_v = (bottom[0] - center[0], bottom[1] - center[1])
    cube.alpha_composite(warp_face(red_face, center, right_u, right_v))

    top_u = (right[0] - top[0], right[1] - top[1])
    top_v = (left[0] - top[0], left[1] - top[1])
    cube.alpha_composite(warp_face(white_face, top, top_u, top_v))

    # Soft diagonal sheen across the cube.
    cube_alpha = cube.getchannel("A")
    sheen = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        [scaled(150), scaled(120), scaled(760), scaled(720)],
        fill=(255, 255, 255, 46))
    sheen = sheen.filter(ImageFilter.GaussianBlur(scaled(110)))
    sheen.putalpha(ImageChops.multiply(sheen.getchannel("A"), cube_alpha))
    cube.alpha_composite(sheen)

    draw = ImageDraw.Draw(cube)
    draw.line(silhouette + [silhouette[0]], fill=(255, 255, 255, 34),
              width=max(1, scaled(2)), joint="curve")

    canvas.alpha_composite(cube)
    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def write_icns(master, output_path):
    iconset_dir = tempfile.mkdtemp(prefix="RubikSolver.iconset.")
    iconset = os.path.join(iconset_dir, "AppIcon.iconset")
    os.makedirs(iconset)
    variants = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    try:
        for filename, size in variants:
            master.resize((size, size), Image.Resampling.LANCZOS).save(
                os.path.join(iconset, filename))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", output_path],
                       check=True)
    finally:
        shutil.rmtree(iconset_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Create RubikSolver's .icns icon")
    parser.add_argument("--output", default="RubikSolver/Resources/AppIcon.icns")
    parser.add_argument("--preview", default="",
                        help="Optional path for a 1024x1024 PNG preview")
    args = parser.parse_args()

    master = build_icon()
    if args.preview:
        master.save(args.preview)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    write_icns(master, args.output)
    print(f"Wrote {args.output} ({os.path.getsize(args.output)} bytes)")


if __name__ == "__main__":
    main()
