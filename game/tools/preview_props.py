#!/usr/bin/env python3
"""preview_props.py — 道具精灵比例对照图。

所有道具按真实相对尺寸排列，每件旁边放一个 64px 高的参照人物
（角色世界内高度），地面用 tileset 草地，检查比例与风格是否统一。

输出：../测试截图/props_preview.png
用法：python tools/preview_props.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT.parent / "测试截图"
PROPS = ROOT / "assets" / "props"
FONT = ROOT / "assets" / "fonts" / "NotoSansCJKsc-Regular.otf"

ORDER = [
    ("house", "民居"), ("tavern", "酒肆"), ("zhai_seat", "山寨主座"),
    ("tree_big", "大松树"), ("wall_h", "城墙·横"), ("wall_v", "城墙·竖"),
    ("tent", "帐篷"), ("campfire_big", "篝火堆"),
]
CELL_W, CELL_H = 300, 250
GROUND_Y = 208  # 每格地面基线


def ref_figure() -> Image.Image:
    """64px 高参照人物（青袍红抹额主将剪影）。"""
    img = Image.new("RGBA", (40, 68), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([10, 60, 30, 66], fill=(16, 12, 8, 90))              # 脚下影
    d.rectangle([16, 56, 19, 62], fill=(40, 36, 30, 255))          # 腿
    d.rectangle([21, 56, 24, 62], fill=(40, 36, 30, 255))
    d.rectangle([14, 24, 26, 58], fill=(70, 96, 150, 255))         # 袍
    d.polygon([(14, 24), (26, 24), (29, 36), (11, 36)],
              fill=(82, 110, 160, 255))                             # 肩
    d.ellipse([13, 6, 27, 22], fill=(238, 198, 156, 255))          # 头
    d.rectangle([13, 10, 27, 14], fill=(196, 60, 44, 255))         # 抹额
    return img


def grass_bg(w: int, h: int) -> Image.Image:
    """用 tileset 的 grass1 铺底，检查道具与地表风格融合度。"""
    atlas = Image.open(ROOT / "assets" / "tiles" / "tileset.png").convert("RGBA")
    g1 = atlas.crop((0, 0, 64, 64))
    g2 = atlas.crop((64, 0, 128, 64))
    bg = Image.new("RGBA", (w, h))
    for y in range(0, h, 64):
        for x in range(0, w, 64):
            bg.alpha_composite(g1 if (x // 64 + y // 64) % 2 == 0 else g2, (x, y))
    return bg


def main() -> None:
    fig = ref_figure()
    f = ImageFont.truetype(str(FONT), 14)
    f_small = ImageFont.truetype(str(FONT), 11)
    cols, rows = 4, 2
    W, H = cols * CELL_W, rows * CELL_H + 34
    out = Image.new("RGBA", (W, H), (30, 27, 22, 255))
    d = ImageDraw.Draw(out)
    d.text((10, 8), "道具比例对照 —— 参照人物高 64px（1 tile）",
           font=f, fill=(226, 214, 188, 255))
    for idx, (name, zh) in enumerate(ORDER):
        cx, cy = idx % cols, idx // cols
        ox, oy = cx * CELL_W, 34 + cy * CELL_H
        cell = grass_bg(CELL_W, CELL_H)
        prop = Image.open(PROPS / f"{name}.png").convert("RGBA")
        if name == "wall_h":      # 横墙按真实用法三连排检查
            row = Image.new("RGBA", (64 * 3, 96), (0, 0, 0, 0))
            for k in range(3):
                row.alpha_composite(prop, (k * 64, 0))
            prop = row
        elif name == "wall_v":    # 竖墙两连排
            col_img = Image.new("RGBA", (64, 96 * 2), (0, 0, 0, 0))
            for k in range(2):
                col_img.alpha_composite(prop, (0, k * 96))
            prop = col_img
        px = ox + (CELL_W - prop.width) // 2 - 20
        py = oy + GROUND_Y - prop.height
        cell.alpha_composite(prop, (px - ox, py - oy))
        cell.alpha_composite(fig, (px - ox + prop.width + 8, GROUND_Y - fig.height))
        out.alpha_composite(cell, (ox, oy))
        d.line([(ox, oy + GROUND_Y + 6), (ox + CELL_W, oy + GROUND_Y + 6)],
               fill=(30, 27, 22, 120))
        d.rectangle([ox, oy, ox + CELL_W - 1, oy + CELL_H - 1],
                    outline=(90, 82, 68, 255))
        d.text((ox + 8, oy + 6), f"{zh} {name}", font=f, fill=(245, 238, 220, 255))
        d.text((ox + 8, oy + 24), f"{prop.width}×{prop.height}px",
               font=f_small, fill=(200, 190, 168, 255))
    SHOTS.mkdir(exist_ok=True)
    p = SHOTS / "props_preview.png"
    out.convert("RGB").save(p)
    print(f"preview: {p} ({out.width}x{out.height})")


if __name__ == "__main__":
    main()
