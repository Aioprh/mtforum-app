#!/usr/bin/env python3
"""Generate consistent black MT Forum launcher icons for Android and project previews."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BG = (8, 8, 8, 255)
WHITE = (255, 255, 255, 255)
INK = (8, 8, 8, 255)

def make_icon(size: int) -> Image.Image:
    scale = size / 1024
    im = Image.new("RGBA", (size, size), BG)
    d = ImageDraw.Draw(im)
    # Rounded app tile, with enough padding for Android launcher masks.
    inset = int(72 * scale)
    radius = int(220 * scale)
    d.rounded_rectangle((inset, inset, size-inset, size-inset),
                        radius=radius, fill=(18, 18, 18, 255),
                        outline=(48, 48, 48, 255), width=max(1, int(3*scale)))
    # Speech bubble silhouette.
    box = (int(205*scale), int(215*scale), int(819*scale), int(690*scale))
    d.rounded_rectangle(box, radius=int(105*scale), fill=WHITE)
    d.polygon([(int(365*scale), int(650*scale)),
               (int(340*scale), int(800*scale)),
               (int(505*scale), int(680*scale))], fill=WHITE)
    # Custom geometric MT lettermark; avoids font/device differences.
    def poly(points):
        d.polygon([(int(x*scale), int(y*scale)) for x,y in points], fill=INK)
    poly([(280,330),(380,330),(450,485),(520,330),(620,330),
          (620,585),(550,585),(550,445),(490,585),(435,585),
          (375,445),(375,585),(280,585)])
    poly([(635,330),(760,330),(760,395),(730,395),(730,585),
          (665,585),(665,395),(635,395)])
    return im

(ROOT / "icon_1024.png").parent.mkdir(parents=True, exist_ok=True)
make_icon(1024).save(ROOT / "icon_1024.png", optimize=True)
res = ROOT / "android/app/src/main/res"
for density, size in {"mdpi":48, "hdpi":72, "xhdpi":96, "xxhdpi":144, "xxxhdpi":192}.items():
    dest = res / f"mipmap-{density}/ic_launcher.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    make_icon(size).save(dest, optimize=True)
print("Generated icon_1024.png and all Android legacy launcher PNG densities.")
