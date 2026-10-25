#!/usr/bin/env python3
"""从 RGC logo 原图生成全系列品牌 Logo 与品牌文字（透明背景，主流尺寸）。

用法（在仓库根目录）:
    python3 editors/code/scripts/make-logos.py

输出目录:
    website/assets/logo/         logo 标（正方形，透明底）
        logo-16.png ... logo-1024.png
        favicon.ico    16/32/48 多尺寸图标
        apple-touch-icon.png     180x180
        og-image.png   1200x630 社交分享图（品牌绿底）
        logo-white.png           白色剪影版（深色背景用）
        logo.svg                 矢量版（vtracer 描摹）
        logo-white.svg           白色剪影矢量版

    website/assets/wordmark/     品牌文字（横版，保持原比例）
        wordmark-32.png ... wordmark-1024.png（按高度）
        wordmark-white.png
        wordmark.svg
        wordmark-white.svg

原理: 原图为纯色背景（logo 为纯白、品牌文字为米白）。以背景色为基准
计算每个像素的 alpha（距离背景色越远越不透明），再做反预乘消除背景
边缘，最后裁剪留白并缩放。
"""

from pathlib import Path

import numpy as np
from PIL import Image
import vtracer

ROOT = Path(__file__).resolve().parents[3]

# --- 源文件与输出目录 ---
LOGO_SOURCE = ROOT / "RGC编程语言logo生成(1).png"   # 正方形 logo 标（2048x2048）
WORDMARK_SOURCE = ROOT / "RGC编程语言logo生成.png"  # 横版品牌文字（2848x1600）
LOGO_OUT = ROOT / "website" / "assets" / "logo"
WORDMARK_OUT = ROOT / "website" / "assets" / "wordmark"

# 品牌色（从 logo 中提取）
BRAND_GREEN = (0, 112, 64)
BRAND_DARK_GREEN = (0, 60, 36)

# 距离背景色多少算完全不透明（0-441）
FULL_OPACITY_DISTANCE = 90.0
# 低于该距离视为背景噪声，完全透明（过滤原图极淡的纹理）
NOISE_FLOOR_DISTANCE = 14.0
# 计算内容包围盒时使用的 alpha 阈值（0-255）
CONTENT_ALPHA_THRESHOLD = 64
# 内容四周留白比例（正方形 logo 与横版文字略有不同）
LOGO_PADDING_RATIO = 0.06
WORDMARK_PADDING_RATIO = 0.04

# logo 标（正方形）PNG 尺寸
LOGO_PNG_SIZES = [16, 32, 48, 64, 128, 180, 192, 256, 512, 1024]
# 品牌文字（按高度）尺寸
WORDMARK_HEIGHTS = [32, 48, 64, 96, 128, 256, 512, 1024]


def remove_background(img: Image.Image, bg_color, noise_floor: float = NOISE_FLOOR_DISTANCE) -> Image.Image:
    """以 bg_color 为背景色，把背景变透明（含反预乘去边缘）。"""
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    bg = np.asarray(bg_color, dtype=np.float32)

    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    alpha = np.clip(
        (dist - noise_floor) / (FULL_OPACITY_DISTANCE - noise_floor),
        0.0,
        1.0,
    )

    # 反预乘: color = (observed - bg * (1 - a)) / a
    a = np.clip(alpha, 1e-6, 1.0)[..., None]
    color = (rgb - bg * (1.0 - alpha[..., None])) / a
    color = np.clip(color, 0.0, 255.0)

    rgba = np.dstack([color, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(rgba, mode="RGBA")


def crop_to_content(img: Image.Image, threshold: int = CONTENT_ALPHA_THRESHOLD) -> Image.Image:
    alpha = np.asarray(img)[..., 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0:
        return img
    return img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def pad_content(img: Image.Image, ratio: float) -> Image.Image:
    """在内容四周加留白（保持原比例，不强制正方形）。"""
    pad_x = int(img.width * ratio)
    pad_y = int(img.height * ratio)
    canvas = Image.new("RGBA", (img.width + pad_x * 2, img.height + pad_y * 2), (0, 0, 0, 0))
    canvas.paste(img, (pad_x, pad_y), img)
    return canvas


def to_monochrome_white(img: Image.Image) -> Image.Image:
    """把彩色 logo 变成白色剪影（保留 alpha，颜色全部置白）。"""
    rgba = np.asarray(img.convert("RGBA")).astype(np.uint8)
    rgba[..., 0] = 255
    rgba[..., 1] = 255
    rgba[..., 2] = 255
    return Image.fromarray(rgba, mode="RGBA")


def load_master(source: Path, crop_box, bg_color, padding_ratio: float, size: int) -> Image.Image:
    """通用流程: 裁水印 → 去背景 → 裁内容 → 加留白 → 缩放到目标尺寸。"""
    img = Image.open(source)
    if crop_box:
        img = img.crop(crop_box)

    transparent = remove_background(img, bg_color)
    transparent = crop_to_content(transparent)
    transparent = pad_content(transparent, padding_ratio)

    return transparent.resize((size, size), Image.LANCZOS)


def save_png_series(img: Image.Image, sizes, out_dir: Path, prefix: str) -> None:
    for size in sizes:
        out = out_dir / f"{prefix}-{size}.png"
        img.resize((size, size), Image.LANCZOS).save(out, optimize=True)
        print(f"wrote {out.relative_to(ROOT)} ({size}x{size})")


def trace_svg_color(img: Image.Image, out_path: Path) -> None:
    """把透明 PNG 描摹成彩色矢量 SVG（vtracer 直接支持 RGBA 透明底）。"""
    tmp = out_path.with_name(out_path.stem + "_tmp.png")
    img.save(tmp, format="PNG")
    vtracer.convert_image_to_svg_py(
        str(tmp),
        str(out_path),
        colormode="color",
        hierarchical="stacked",
        mode="spline",
        filter_speckle=4,
        color_precision=6,
        layer_difference=16,
        corner_threshold=60,
        length_threshold=4.0,
        max_iterations=10,
        splice_threshold=45,
        path_precision=3,
    )
    tmp.unlink()


def trace_svg_white(img: Image.Image, out_path: Path) -> None:
    """用 alpha 掩膜（内容=黑/背景=白）做 binary 描摹，再把填充改为白色。"""
    alpha = np.asarray(img.convert("RGBA"))[..., 3]
    mask = Image.fromarray((255 - alpha).astype(np.uint8), mode="L")
    tmp = out_path.with_name(out_path.stem + "_mask.png")
    mask.save(tmp)
    vtracer.convert_image_to_svg_py(
        str(tmp),
        str(out_path),
        colormode="binary",
        mode="spline",
        filter_speckle=4,
        color_precision=6,
        layer_difference=16,
        corner_threshold=60,
        length_threshold=4.0,
        max_iterations=10,
        splice_threshold=45,
        path_precision=3,
    )
    tmp.unlink()
    svg_text = out_path.read_text(encoding="utf-8")
    svg_text = svg_text.replace('fill="#000000"', 'fill="#ffffff"')
    out_path.write_text(svg_text, encoding="utf-8")


def make_favicon(master: Image.Image, path: Path) -> None:
    """生成多尺寸 favicon.ico（16/32/48）。"""
    base = master.resize((48, 48), Image.LANCZOS)
    base.save(path, format="ICO", sizes=[(48, 48), (32, 32), (16, 16)])


def make_og_image(master: Image.Image, path: Path) -> None:
    """生成 1200x630 社交分享图：品牌绿渐变底 + 居中 logo。"""
    W, H = 1200, 630
    img = Image.new("RGBA", (W, H), BRAND_GREEN + (255,))

    # 从深绿到主绿的柔和径向渐变
    base = np.asarray(img.convert("RGB")).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    cx, cy = W / 2, H / 2
    dist = np.sqrt(((xx - cx) / (W / 2)) ** 2 + ((yy - cy) / (H / 2)) ** 2)
    t = np.clip(1.0 - dist, 0.0, 1.0) ** 2
    dark = np.asarray(BRAND_DARK_GREEN, dtype=np.float32)
    for c in range(3):
        base[..., c] = base[..., c] * (1.0 - t * 0.55) + dark[c] * (t * 0.55)
    grad = Image.fromarray(base.astype(np.uint8), mode="RGB").convert("RGBA")

    # logo 占高度的 ~40%，居中
    logo_h = int(H * 0.42)
    logo = master.resize((logo_h, logo_h), Image.LANCZOS)
    grad.alpha_composite(logo, ((W - logo_h) // 2, (H - logo_h) // 2))
    grad.convert("RGB").save(path, optimize=True)


def process_logo() -> None:
    """正方形 logo 标全系列。"""
    LOGO_OUT.mkdir(parents=True, exist_ok=True)
    master = load_master(
        source=LOGO_SOURCE,
        crop_box=(0, 0, 1800, 1880),  # 裁掉右下角水印（原图 2048x2048）
        bg_color=(255, 255, 255),
        padding_ratio=LOGO_PADDING_RATIO,
        size=1024,
    )
    print(f"logo master: {master.width}x{master.height}")

    save_png_series(master, LOGO_PNG_SIZES, LOGO_OUT, "logo")

    make_favicon(master, LOGO_OUT / "favicon.ico")
    print(f"wrote {(LOGO_OUT / 'favicon.ico').relative_to(ROOT)} (16/32/48)")

    (LOGO_OUT / "apple-touch-icon.png").write_bytes(
        (LOGO_OUT / "logo-180.png").read_bytes()
    )
    print(f"wrote {(LOGO_OUT / 'apple-touch-icon.png').relative_to(ROOT)} (180x180)")

    make_og_image(master, LOGO_OUT / "og-image.png")
    print(f"wrote {(LOGO_OUT / 'og-image.png').relative_to(ROOT)} (1200x630)")

    white = to_monochrome_white(master)
    white.resize((512, 512), Image.LANCZOS).save(LOGO_OUT / "logo-white.png", optimize=True)
    print(f"wrote {(LOGO_OUT / 'logo-white.png').relative_to(ROOT)} (512x512)")

    trace_svg_color(master, LOGO_OUT / "logo.svg")
    print(f"wrote {(LOGO_OUT / 'logo.svg').relative_to(ROOT)}")
    trace_svg_white(white, LOGO_OUT / "logo-white.svg")
    print(f"wrote {(LOGO_OUT / 'logo-white.svg').relative_to(ROOT)}")


def process_wordmark() -> None:
    """横版品牌文字系列（保持原比例，不裁成正方形）。"""
    WORDMARK_OUT.mkdir(parents=True, exist_ok=True)

    # 原图 2848x1600，水印在右下角 (x>2560, y>1510)；裁到安全区域
    img = Image.open(WORDMARK_SOURCE).crop((0, 0, 2400, 1400))
    # 背景为米白 (255,250,245)
    transparent = remove_background(img, bg_color=(255, 250, 245))
    transparent = crop_to_content(transparent)
    transparent = pad_content(transparent, WORDMARK_PADDING_RATIO)
    print(f"wordmark content: {transparent.width}x{transparent.height}")

    # 按高度生成系列（保持宽高比）
    for h in WORDMARK_HEIGHTS:
        w = max(1, round(transparent.width * h / transparent.height))
        out = WORDMARK_OUT / f"wordmark-{h}.png"
        transparent.resize((w, h), Image.LANCZOS).save(out, optimize=True)
        print(f"wrote {out.relative_to(ROOT)} ({w}x{h})")

    white = to_monochrome_white(transparent)
    wh = 512
    ww = round(transparent.width * wh / transparent.height)
    white.resize((ww, wh), Image.LANCZOS).save(WORDMARK_OUT / "wordmark-white.png", optimize=True)
    print(f"wrote {(WORDMARK_OUT / 'wordmark-white.png').relative_to(ROOT)} ({ww}x{wh})")

    # 矢量版
    base_svg = transparent.resize(
        (round(transparent.width * 1024 / transparent.height), 1024), Image.LANCZOS
    )
    trace_svg_color(base_svg, WORDMARK_OUT / "wordmark.svg")
    print(f"wrote {(WORDMARK_OUT / 'wordmark.svg').relative_to(ROOT)}")
    trace_svg_white(base_svg, WORDMARK_OUT / "wordmark-white.svg")
    print(f"wrote {(WORDMARK_OUT / 'wordmark-white.svg').relative_to(ROOT)}")


def main() -> None:
    if not LOGO_SOURCE.exists():
        raise SystemExit(f"找不到源 logo: {LOGO_SOURCE}")
    if not WORDMARK_SOURCE.exists():
        raise SystemExit(f"找不到品牌文字源图: {WORDMARK_SOURCE}")

    process_logo()
    print()
    process_wordmark()
    print("\n完成。")


if __name__ == "__main__":
    main()