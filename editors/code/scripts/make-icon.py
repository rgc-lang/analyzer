#!/usr/bin/env python3
"""从 RGC logo 原图生成透明背景的扩展图标。

用法（在仓库根目录）:
    python3 editors/code/scripts/make-icon.py

输出:
    editors/code/resources/icon.png   256x256  扩展图标
    editors/code/resources/logo.png   512x512  文档/README 用 logo

原理: 原图为纯白背景。以白色为基准计算每个像素的 alpha
(距离白色越远越不透明)，再做反预乘消除白边，最后裁剪留白并缩放。
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "RGC编程语言logo生成(1).png"
OUT_DIR = ROOT / "editors" / "code" / "resources"

# 距离白色多少算完全不透明（0-441）
FULL_OPACITY_DISTANCE = 90.0
# 低于该距离视为背景噪声，完全透明（过滤原图极淡的纹理）
NOISE_FLOOR_DISTANCE = 14.0
# 计算内容包围盒时使用的 alpha 阈值（0-255）
CONTENT_ALPHA_THRESHOLD = 64
# 内容四周留白比例
PADDING_RATIO = 0.06


def remove_white_background(img: Image.Image) -> Image.Image:
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)

    # 与白色的欧氏距离；先减掉噪声下限，避免极淡背景纹理变成半透明内容
    dist = np.sqrt(((255.0 - rgb) ** 2).sum(axis=2))
    alpha = np.clip(
        (dist - NOISE_FLOOR_DISTANCE)
        / (FULL_OPACITY_DISTANCE - NOISE_FLOOR_DISTANCE),
        0.0,
        1.0,
    )

    # 反预乘: color = (observed - white * (1 - a)) / a
    a = np.clip(alpha, 1e-6, 1.0)[..., None]
    color = (rgb - 255.0 * (1.0 - alpha[..., None])) / a
    color = np.clip(color, 0.0, 255.0)

    rgba = np.dstack([color, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(rgba, mode="RGBA")


def crop_to_content(
    img: Image.Image, threshold: int = CONTENT_ALPHA_THRESHOLD
) -> Image.Image:
    alpha = np.asarray(img)[..., 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0:
        return img
    return img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def square_with_padding(img: Image.Image) -> Image.Image:
    side = max(img.width, img.height)
    pad = int(side * PADDING_RATIO)
    canvas_side = side + pad * 2
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.paste(
        img,
        ((canvas_side - img.width) // 2, (canvas_side - img.height) // 2),
        img,
    )
    return canvas


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"找不到源 logo: {SOURCE}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    img = Image.open(SOURCE)
    # 裁掉右下角水印（原图 2048x2048，水印位于 x>1600, y>1800）
    img = img.crop((0, 0, 1800, 1880))

    transparent = remove_white_background(img)
    transparent = crop_to_content(transparent)
    transparent = square_with_padding(transparent)

    logo = transparent.resize((512, 512), Image.LANCZOS)
    icon = transparent.resize((256, 256), Image.LANCZOS)

    logo_path = OUT_DIR / "logo.png"
    icon_path = OUT_DIR / "icon.png"
    logo.save(logo_path, optimize=True)
    icon.save(icon_path, optimize=True)

    print(f"wrote {logo_path.relative_to(ROOT)} ({logo.width}x{logo.height})")
    print(f"wrote {icon_path.relative_to(ROOT)} ({icon.width}x{icon.height})")


if __name__ == "__main__":
    main()
