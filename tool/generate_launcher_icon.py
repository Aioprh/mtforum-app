#!/usr/bin/env python3
"""生成拟态（Neumorphism）风格的原生质感 MT 论坛启动图标。

所有尺寸都从同一张 1024px 母版缩小，保证不同密度下视觉一致；
同时输出自适应图标（Android 8.0+）的前景 / 背景图层。
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CANVAS = 1024

# 表面：品牌绿的柔和渐变，顶部受光、底部压暗。
SURFACE_TOP = (30, 200, 128)
SURFACE_BOTTOM = (8, 136, 80)
DEPTH = (2, 48, 30)
LIGHT = (228, 255, 241)

# 气泡：白色到冷灰绿，模拟亚光材质。
BUBBLE_TOP = (255, 255, 255)
BUBBLE_BOTTOM = (237, 246, 241)
BUBBLE_BOX = (196, 224, 828, 694)
BUBBLE_RADIUS = 108
BUBBLE_TAIL = [(352, 660), (316, 806), (526, 686)]

# MT 字标：内凹雕刻，上深下浅。
LETTER_TOP = (6, 101, 59)
LETTER_BOTTOM = (17, 160, 98)
MT_M = [(280, 330), (380, 330), (450, 485), (520, 330), (620, 330),
        (620, 585), (550, 585), (550, 445), (490, 585), (435, 585),
        (375, 445), (375, 585), (280, 585)]
MT_T = [(635, 330), (760, 330), (760, 395), (730, 395), (730, 585),
        (665, 585), (665, 395), (635, 395)]


def vertical_gradient(size, top, bottom):
    strip = Image.new("RGB", (1, size))
    px = strip.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return strip.resize((size, size), Image.BILINEAR).convert("RGBA")


def soft_blob(size, box, color, blur, alpha):
    """柔和光斑；透明区域保留同色，避免高斯模糊产生暗边。"""
    layer = Image.new("RGBA", (size, size), tuple(color) + (0,))
    ImageDraw.Draw(layer).ellipse(box, fill=tuple(color) + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def rounded_mask(size, inset, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1), radius=radius, fill=255)
    return mask


def render_surface(size, rounded):
    img = vertical_gradient(size, SURFACE_TOP, SURFACE_BOTTOM)
    # 左上角受光，制造柔和的隆起感。
    img = Image.alpha_composite(img, soft_blob(size, (-340, -440, 800, 540), (255, 255, 255), 175, 42))
    # 右下角压暗，收出体积。
    img = Image.alpha_composite(img, soft_blob(size, (-260, 620, 1300, 1470), DEPTH, 200, 62))
    # 底边一条极淡的反光，避免边缘发死。
    img = Image.alpha_composite(img, soft_blob(size, (40, 910, 984, 1160), (255, 255, 255), 95, 14))
    if rounded:
        img.putalpha(rounded_mask(size, 26, 232))
    return img


def bubble_mask(size, scale):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)

    def point(x, y):
        return (512 + (x - 512) * scale, 515 + (y - 515) * scale)

    draw.rounded_rectangle(
        (*point(BUBBLE_BOX[0], BUBBLE_BOX[1]), *point(BUBBLE_BOX[2], BUBBLE_BOX[3])),
        radius=int(BUBBLE_RADIUS * scale), fill=255)
    draw.polygon([point(x, y) for x, y in BUBBLE_TAIL], fill=255)
    return mask


def render_bubble(size, scale=1.0):
    mask = bubble_mask(size, scale)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 外投影：拟态的核心，让气泡浮在表面之上。
    shadow = Image.new("RGBA", (size, size), DEPTH + (0,))
    shadow.putalpha(mask.point(lambda a: int(a * 0.5)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(36 * scale))
    shadow = ImageChops.offset(shadow, 0, int(24 * scale))
    out = Image.alpha_composite(out, shadow)

    body = vertical_gradient(size, BUBBLE_TOP, BUBBLE_BOTTOM)
    body.putalpha(mask)
    out = Image.alpha_composite(out, body)

    # 气泡内部上缘高光（只保留边缘一条，避免整体发灰）。
    top_rim = ImageChops.subtract(mask, ImageChops.offset(mask, 0, int(26 * scale)))
    top_rim = top_rim.filter(ImageFilter.GaussianBlur(10 * scale))
    top_rim = ImageChops.multiply(top_rim, mask)
    highlight = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    highlight.putalpha(top_rim.point(lambda a: int(a * 0.6)))
    out = Image.alpha_composite(out, highlight)

    # 气泡内部下缘暗部。
    bottom_rim = ImageChops.subtract(mask, ImageChops.offset(mask, 0, -int(38 * scale)))
    bottom_rim = bottom_rim.filter(ImageFilter.GaussianBlur(16 * scale))
    bottom_rim = ImageChops.multiply(bottom_rim, mask)
    inner = Image.new("RGBA", (size, size), DEPTH + (0,))
    inner.putalpha(bottom_rim.point(lambda a: int(a * 0.42)))
    out = Image.alpha_composite(out, inner)

    # MT 字标：内凹雕刻——上缘压暗、下缘提亮，保持边缘清晰。
    letters = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(letters)

    def point(x, y):
        return (512 + (x - 512) * scale, 515 + (y - 515) * scale)

    draw.polygon([point(x, y) for x, y in MT_M], fill=255)
    draw.polygon([point(x, y) for x, y in MT_T], fill=255)

    letter_fill = vertical_gradient(size, LETTER_TOP, LETTER_BOTTOM)
    letter_fill.putalpha(letters)
    out = Image.alpha_composite(out, letter_fill)

    # 左上内阴影 + 右下内高光，模拟字体被压入亚光表面。
    upper = ImageChops.offset(letters, int(3 * scale), int(4 * scale))
    lower = ImageChops.offset(letters, -int(3 * scale), -int(4 * scale))
    top_edge = ImageChops.subtract(letters, upper).filter(ImageFilter.GaussianBlur(3 * scale))
    bottom_edge = ImageChops.subtract(letters, lower).filter(ImageFilter.GaussianBlur(3 * scale))

    shade = Image.new("RGBA", (size, size), DEPTH + (0,))
    shade.putalpha(top_edge.point(lambda a: int(a * 0.5)))
    out = Image.alpha_composite(out, shade)

    sheen = Image.new("RGBA", (size, size), LIGHT + (0,))
    sheen.putalpha(bottom_edge.point(lambda a: int(a * 0.55)))
    out = Image.alpha_composite(out, sheen)
    return out


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
    legacy = Image.alpha_composite(render_surface(CANVAS, rounded=True), render_bubble(CANVAS))
    background = render_surface(CANVAS, rounded=False)
    foreground = render_bubble(CANVAS, 0.86)

    save(legacy, ROOT / "icon_1024.png")

    res = ROOT / "android/app/src/main/res"
    for density, size in sizes_for(48).items():
        save(legacy.resize((size, size), Image.LANCZOS), res / f"mipmap-{density}/ic_launcher.png")
    for density, size in sizes_for(108).items():
        save(background.resize((size, size), Image.LANCZOS),
             res / f"mipmap-{density}/ic_launcher_background.png")
        save(foreground.resize((size, size), Image.LANCZOS),
             res / f"mipmap-{density}/ic_launcher_foreground.png")
    print("Generated neumorphic launcher icons (legacy + adaptive foreground/background).")


if __name__ == "__main__":
    main()
