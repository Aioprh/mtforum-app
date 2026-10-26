#!/usr/bin/env python3
"""生成浅色拟态（Neumorphism）风格的 MT 论坛启动图标。

构图：柔光底 + 内嵌浮雕面板 + 单线描边 MT 字标。
所有尺寸由同一张 1024px 母版缩放，并输出自适应图标的前景 / 背景图层。
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CANVAS = 1024
WORK = CANVAS * 2  # 先按 2 倍尺寸绘制，再缩回母版，边缘更干净

# 浅蓝灰拟态配色。
BG_TOP = (250, 253, 255)
BG_BOTTOM = (226, 239, 252)
PLATE_TOP = (255, 255, 255)
PLATE_BOTTOM = (216, 230, 247)
SHADOW = (163, 189, 221)
LINE = (115, 145, 185)

OUTER_INSET = 16          # 1024 坐标系下的边距
OUTER_RADIUS = 232
PLATE_BOX = (212, 206, 812, 806)
PLATE_RADIUS = 128
LETTER_SCALE = 0.82   # 字标相对面板中心的缩放
LETTER_STROKE = 21

M_PATH = [(311, 632), (311, 380), (421, 620), (531, 380), (531, 632)]
T_BAR = [(587, 380), (713, 380)]
T_STEM = [(650, 380), (650, 632)]


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


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def render_background(rounded):
    """底：极浅的蓝白渐变，左上受光、右下略深。"""
    img = vertical_gradient(WORK, BG_TOP, BG_BOTTOM)
    k = WORK / CANVAS
    img = Image.alpha_composite(img, soft_blob(WORK, (-400, -520, 1100, 780), (255, 255, 255), 320, 40))
    img = Image.alpha_composite(img, soft_blob(WORK, (-300, 1200, 1500, 2100), SHADOW, 360, 26))
    if rounded:
        inset = OUTER_INSET * k
        img.putalpha(rounded_mask(
            WORK,
            (inset, inset, WORK - inset - 1, WORK - inset - 1),
            int(OUTER_RADIUS * k)))
    return img


def plate_geometry(scale):
    def point(x, y):
        return (512 + (x - 512) * scale, 506 + (y - 506) * scale)

    x0, y0, x1, y1 = [point(PLATE_BOX[0], PLATE_BOX[1])[0],
                      point(PLATE_BOX[0], PLATE_BOX[1])[1],
                      point(PLATE_BOX[2], PLATE_BOX[3])[0],
                      point(PLATE_BOX[2], PLATE_BOX[3])[1]]
    return (x0, y0, x1, y1), int(PLATE_RADIUS * scale), point


def render_plate(scale=1.0):
    """内嵌面板：投影 + 白色到浅蓝渐变 + 上缘高光 + 下缘内阴影。"""
    k = WORK / CANVAS
    box, radius, point = plate_geometry(scale)
    mask = rounded_mask(WORK, tuple(v * k for v in box), int(radius * k))
    out = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))

    # 落地投影：让面板从底色中浮起。
    shadow = Image.new("RGBA", (WORK, WORK), SHADOW + (0,))
    shadow.putalpha(mask.point(lambda a: int(a * 0.46)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(42 * scale * k))
    shadow = ImageChops.offset(shadow, int(4 * scale * k), int(28 * scale * k))
    contact = Image.new("RGBA", (WORK, WORK), SHADOW + (0,))
    contact.putalpha(mask.point(lambda a: int(a * 0.3)))
    contact = contact.filter(ImageFilter.GaussianBlur(16 * scale * k))
    contact = ImageChops.offset(contact, 0, int(10 * scale * k))
    out = Image.alpha_composite(out, shadow)
    out = Image.alpha_composite(out, contact)

    body = vertical_gradient(WORK, PLATE_TOP, PLATE_BOTTOM)
    body = Image.alpha_composite(body, soft_blob(WORK, (-200, -260, 1250, 900), (255, 255, 255), 260, 90))
    body = Image.alpha_composite(body, soft_blob(WORK, (500, 900, 1900, 2000), SHADOW, 260, 46))
    body.putalpha(mask)
    out = Image.alpha_composite(out, body)

    # 上缘高光条。
    top_rim = ImageChops.subtract(mask, ImageChops.offset(mask, int(18 * k), int(20 * k)))
    top_rim = top_rim.filter(ImageFilter.GaussianBlur(9 * k))
    top_rim = ImageChops.multiply(top_rim, mask)
    highlight = Image.new("RGBA", (WORK, WORK), (255, 255, 255, 0))
    highlight.putalpha(top_rim.point(lambda a: int(a * 0.72)))
    out = Image.alpha_composite(out, highlight)

    # 下缘内阴影，收出厚度。
    bottom_rim = ImageChops.subtract(mask, ImageChops.offset(mask, -int(16 * k), -int(22 * k)))
    bottom_rim = bottom_rim.filter(ImageFilter.GaussianBlur(18 * k))
    bottom_rim = ImageChops.multiply(bottom_rim, mask)
    inner = Image.new("RGBA", (WORK, WORK), SHADOW + (0,))
    inner.putalpha(bottom_rim.point(lambda a: int(a * 0.5)))
    out = Image.alpha_composite(out, inner)
    return out


def render_letters(scale=1.0):
    """单线描边的 MT 字标，圆头圆角，和参考图的线性图标一致。"""
    k = WORK / CANVAS
    _, _, point = plate_geometry(scale)
    stroke = max(1, int(LETTER_STROKE * scale * k))

    def letter_point(x, y):
        lx = 512 + (x - 512) * LETTER_SCALE
        ly = 506 + (y - 506) * LETTER_SCALE
        return point(lx, ly)

    def path(points):
        return [tuple(v * k for v in letter_point(x, y)) for x, y in points]

    layer = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for points in (M_PATH, T_BAR, T_STEM):
        draw.line(path(points), fill=LINE + (255,), width=stroke, joint="curve")
    # PIL 的线段是平头，补圆点模拟圆头。
    for x, y in (M_PATH[0], M_PATH[-1], T_BAR[0], T_BAR[-1], T_STEM[-1]):
        cx, cy = letter_point(x, y)
        cx, cy = cx * k, cy * k
        r = stroke / 2
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=LINE + (255,))
    return layer


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
    legacy = downscale(Image.alpha_composite(
        render_background(rounded=True),
        Image.alpha_composite(render_plate(), render_letters())))
    background = downscale(render_background(rounded=False))
    foreground = downscale(Image.alpha_composite(render_plate(0.93), render_letters(0.93)))

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
