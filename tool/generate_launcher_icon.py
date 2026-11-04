#!/usr/bin/env python3
"""生成 MT 论坛的启动图标：蓝底 + 双对话气泡 + mt 字标。

构图：一块圆角蓝底上叠两个对话气泡，前面是纯白气泡（内含 mt），
后面是浅蓝气泡，表示「还在继续的对话」。
所有尺寸由同一张 1024px 母版缩放，并输出自适应图标的前景 / 背景图层。
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CANVAS = 1024
SS = 3                 # 超采样倍数，缩回母版后边缘更干净
WORK = CANVAS * SS

BLUE_TOP = (78, 128, 167)
BLUE_BOTTOM = (62, 106, 142)
BUBBLE_FRONT = (255, 255, 255)
BUBBLE_BACK = (215, 231, 246)
WORD = (51, 96, 133)

# 气泡轮廓：圆角矩形 + 底边伸出的小尾巴，整条闭合曲线一次成型，不会有拼接缝。
FRONT_PTS = [(172, 268), (612, 268), (612, 634), (480, 634),
             (456, 696), (430, 696), (410, 634), (172, 634)]
FRONT_RADII = [96, 96, 96, 14, 12, 12, 14, 96]

BACK_PTS = [(556, 408), (838, 408), (838, 716), (784, 716),
            (760, 776), (734, 776), (714, 716), (556, 716)]
BACK_RADII = [68, 68, 68, 12, 11, 11, 12, 68]

WORD_CENTER = (394, 446)
WORD_WIDTH = 210
WORD_TRACKING = -4

CORNERS = 24          # 1024 坐标系下的外边距
CORNER_RADIUS = 210

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]


def k(v):
    return v * SS


def pick_font():
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    raise RuntimeError("找不到可用的粗体字体")


def vertical_gradient(top, bottom):
    strip = Image.new("RGB", (1, CANVAS))
    px = strip.load()
    for y in range(CANVAS):
        t = y / (CANVAS - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return strip.resize((WORK, WORK), Image.BICUBIC).convert("RGBA")


def dither(image):
    """给底色加一点随机抖动，避免大面积渐变出现色带。"""
    import numpy as np
    arr = np.array(image).astype("int16")
    noise = np.random.default_rng(7).integers(-2, 3, arr.shape[:2] + (3,))
    arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
    return Image.fromarray(arr.astype("uint8"), "RGBA")


def rounded_poly(pts, radii, steps=18):
    """用二次贝塞尔把多边形拐角磨圆，生成闭合轮廓。"""
    out = []
    n = len(pts)

    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        d1 = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        d2 = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        if d1 < 1e-6 or d2 < 1e-6:
            out.append(p1)
            continue
        r = min(radii[i], d1 * 0.5, d2 * 0.5)
        a = (p1[0] + (p0[0] - p1[0]) * r / d1, p1[1] + (p0[1] - p1[1]) * r / d1)
        b = (p1[0] + (p2[0] - p1[0]) * r / d2, p1[1] + (p2[1] - p1[1]) * r / d2)
        for j in range(steps):
            t = j / steps
            u = 1 - t
            out.append((u * u * a[0] + 2 * u * t * p1[0] + t * t * b[0],
                        u * u * a[1] + 2 * u * t * p1[1] + t * t * b[1]))
    return out


def bubble_layer(pts, radii, color, shadow=None):
    """填充气泡；shadow=(模糊, 强度, 下移) 时先铺一层柔和投影。"""
    outline = [(k(x), k(y)) for x, y in rounded_poly(pts, radii)]
    layer = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))

    if shadow:
        blur, alpha, dy = shadow
        mask = Image.new("L", (WORK, WORK), 0)
        ImageDraw.Draw(mask).polygon(outline, fill=alpha)
        mask = mask.filter(ImageFilter.GaussianBlur(k(blur)))
        tint = Image.new("RGBA", (WORK, WORK), (32, 68, 98, 0))
        tint.putalpha(mask)
        layer.alpha_composite(tint, (0, int(k(dy))))

    ImageDraw.Draw(layer).polygon(outline, fill=color + (255,))
    return layer


def word_layer():
    """mt 字标，按宽度自动选字号，再用负字距收紧。"""
    layer = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    text = "mt"
    path = pick_font()

    size = 100
    font = ImageFont.truetype(path, k(size))
    while True:
        total = sum(font.getlength(ch) / SS for ch in text) \
            + WORD_TRACKING * (len(text) - 1)
        if total >= WORD_WIDTH or size <= 20:
            break
        size += 1
        font = ImageFont.truetype(path, k(size))

    advances = [font.getlength(ch) / SS + WORD_TRACKING for ch in text]
    total = sum(advances) - WORD_TRACKING
    x = WORD_CENTER[0] - total / 2
    for ch, adv in zip(text, advances):
        _, top, _, bottom = font.getbbox(ch)
        draw.text((k(x), k(WORD_CENTER[1] - (bottom + top) / 2 / SS)), ch,
                  font=font, fill=WORD + (255,))
        x += adv
    return layer


def render_content():
    layer = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    layer = Image.alpha_composite(layer, bubble_layer(BACK_PTS, BACK_RADII, BUBBLE_BACK,
                                                      shadow=(30, 34, 8)))
    layer = Image.alpha_composite(layer, bubble_layer(FRONT_PTS, FRONT_RADII, BUBBLE_FRONT))
    return Image.alpha_composite(layer, word_layer())


def scale_about_center(image, scale):
    if scale == 1.0:
        return image
    size = int(WORK * scale)
    small = image.resize((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    pad = (WORK - size) // 2
    canvas.paste(small, (pad, pad), small)
    return canvas


def render_background(rounded):
    img = vertical_gradient(BLUE_TOP, BLUE_BOTTOM)
    if rounded:
        mask = Image.new("L", (WORK, WORK), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [k(CORNERS), k(CORNERS), k(CANVAS - CORNERS), k(CANVAS - CORNERS)],
            radius=k(CORNER_RADIUS), fill=255)
        img.putalpha(mask)
    return dither(img)


def downscale(image):
    return image.resize((CANVAS, CANVAS), Image.LANCZOS)


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def sizes_for(base):
    return {
        "mdpi": base,
        "hdpi": round(base * 1.5),
        "xhdpi": base * 2,
        "xxhdpi": base * 3,
        "xxxhdpi": base * 4,
    }


def main():
    content = render_content()

    legacy = downscale(Image.alpha_composite(render_background(rounded=True), content))
    background = downscale(render_background(rounded=False))
    # 自适应图标只显示中间 72/108，且可能被裁成圆形，内容要收进安全区。
    foreground = downscale(scale_about_center(content, 0.74))

    save(legacy, ROOT / "icon_1024.png")

    res = ROOT / "android/app/src/main/res"
    for density, size in sizes_for(48).items():
        save(legacy.resize((size, size), Image.LANCZOS), res / f"mipmap-{density}/ic_launcher.png")
    for density, size in sizes_for(108).items():
        save(background.resize((size, size), Image.LANCZOS),
             res / f"mipmap-{density}/ic_launcher_background.png")
        save(foreground.resize((size, size), Image.LANCZOS),
             res / f"mipmap-{density}/ic_launcher_foreground.png")
    print("Generated launcher icons: blue plate + two bubbles + mt.")


if __name__ == "__main__":
    main()
