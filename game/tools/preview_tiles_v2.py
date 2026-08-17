#!/usr/bin/env python3
"""preview_tiles_v2.py — 渲染 tileset v2 验收预览图。

输出（工程根 ../测试截图/）：
  tiles_v2_preview.png   24 块带标签接触表 + 小场景拼接
  tiles_v2_grass8x8.png  8×8 随机草地平铺接缝检查（撒装饰层）

用法：python tools/preview_tiles_v2.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

TS = 64
ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT.parent / "测试截图"
SPEC = json.loads((ROOT / "data" / "tilespec.json").read_text(encoding="utf-8"))
FONT = ROOT / "assets" / "fonts" / "NotoSansCJKsc-Regular.otf"

ZH = {
    "grass1": "草一", "grass2": "草二", "grass3": "草三", "dirt": "官道",
    "street": "石板街", "sand": "沙滩", "water": "水", "grass_deco": "花草地",
    "tree": "松树", "tree_dense": "密林", "wall": "城墙", "house": "民居",
    "tavern": "酒肆", "farmland": "农田", "fence": "寨栅", "zhai": "寨旗",
    "ruins": "废墟", "reed": "芦苇", "tuft1": "草簇一", "tuft2": "草簇二",
    "stone": "碎石", "flower": "野花", "sign": "木牌", "campfire": "篝火",
}


def _tiles() -> dict[str, Image.Image]:
    atlas = Image.open(ROOT / "assets" / "tiles" / "tileset.png").convert("RGBA")
    out = {}
    for name, meta in SPEC["tiles"].items():
        x, y = meta["xy"]
        out[name] = atlas.crop((x * TS, y * TS, (x + 1) * TS, (y + 1) * TS))
    return out


def _checker(size: int, cell: int = 8) -> Image.Image:
    img = Image.new("RGBA", (size, size), (58, 54, 48, 255))
    d = ImageDraw.Draw(img)
    for yy in range(0, size, cell):
        for xx in range(0, size, cell):
            if (xx // cell + yy // cell) % 2 == 0:
                d.rectangle([xx, yy, xx + cell - 1, yy + cell - 1], fill=(72, 68, 60, 255))
    return img


def contact_sheet(tiles: dict[str, Image.Image]) -> Image.Image:
    scale = 2
    cell_w, cell_h = TS * scale + 8, TS * scale + 26
    cols = SPEC["columns"]
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w + 8, rows * cell_h + 8), (38, 34, 28, 255))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(str(FONT), 13)
    for idx, name in enumerate(SPEC["tiles"]):
        cx, cy = idx % cols, idx // cols
        ox, oy = 4 + cx * cell_w, 4 + cy * cell_h
        bg = _checker(TS * scale) if SPEC["tiles"][name]["layer"] == "deco" else None
        tile = tiles[name].resize((TS * scale, TS * scale), Image.NEAREST)
        if bg:
            sheet.alpha_composite(bg, (ox, oy))
        sheet.alpha_composite(tile, (ox, oy))
        d.rectangle([ox, oy, ox + TS * scale - 1, oy + TS * scale - 1],
                    outline=(90, 82, 68, 255))
        d.text((ox + 2, oy + TS * scale + 4), f"{name} {ZH.get(name, '')}",
               font=f, fill=(226, 214, 188, 255))
    return sheet


def grass_field(tiles: dict[str, Image.Image]) -> Image.Image:
    """8×8 随机草块平铺 + 装饰层撒点，检查接缝与网格感。"""
    rng = np.random.default_rng(7)
    n = 8
    img = Image.new("RGBA", (n * TS, n * TS))
    pool = ["grass1", "grass1", "grass2", "grass2", "grass3", "grass3", "grass_deco"]
    for gy in range(n):
        for gx in range(n):
            name = pool[int(rng.integers(len(pool)))]
            img.alpha_composite(tiles[name], (gx * TS, gy * TS))
    for _ in range(26):  # 模拟 decoration 层
        name = ["tuft1", "tuft2", "flower", "stone"][int(rng.integers(4))]
        img.alpha_composite(tiles[name],
                            (int(rng.integers(0, n)) * TS, int(rng.integers(0, n)) * TS))
    return img


def mini_scene(tiles: dict[str, Image.Image]) -> Image.Image:
    """手工小场景：官道穿草野，水湾滩涂，树/屋/墙/寨旗/篝火同屏。"""
    ground_map = [
        "ggggggggggwwww",
        "ggGgtgggggswww",
        "gggggtgggsswww",
        "ddddddddddssgg",
        "ggggfggggggggg",
        "ggtgffggGgtggg",
        "gggggggggggggg",
    ]
    deco_map = [
        "..............",
        "....T.........",
        ".....t..r.....",
        "..............",
        "..W.......h...",
        "......Z....t..",
        "..x.......c...",
    ]
    legend = SPEC["legend_map"]
    rng = np.random.default_rng(11)
    w = len(ground_map[0])
    h = len(ground_map)
    img = Image.new("RGBA", (w * TS, h * TS))
    for gy, row in enumerate(ground_map):
        for gx, ch in enumerate(row):
            names = legend[ch]
            ground = names[0]
            if ground == "grass_auto":
                ground = ["grass1", "grass2", "grass3"][int(rng.integers(3))]
            img.alpha_composite(tiles[ground], (gx * TS, gy * TS))
    deco_legend = {"t": "tree", "T": "tree_dense", "r": "ruins", "W": "wall",
                   "h": "house", "H": "tavern", "Z": "zhai", "F": "fence",
                   "x": "sign", "c": "campfire", "R": "reed"}
    for gy, row in enumerate(deco_map):
        for gx, ch in enumerate(row):
            if ch == ".":
                continue
            img.alpha_composite(tiles[deco_legend[ch]], (gx * TS, gy * TS))
    return img


def main() -> None:
    SHOTS.mkdir(exist_ok=True)
    tiles = _tiles()
    sheet = contact_sheet(tiles)
    scene = mini_scene(tiles).resize((14 * TS * 2, 7 * TS * 2), Image.NEAREST)
    pad = 12
    head = 24
    f = ImageFont.truetype(str(FONT), 14)
    W = max(sheet.width, scene.width + pad * 2)
    H = sheet.height + head + scene.height + head + pad
    out = Image.new("RGBA", (W, H), (30, 27, 22, 255))
    d = ImageDraw.Draw(out)
    out.alpha_composite(sheet, ((W - sheet.width) // 2, 0))
    d.text((pad, sheet.height + 4), "小场景拼接（官道/水湾/树/屋/墙/寨旗/篝火）",
           font=f, fill=(226, 214, 188, 255))
    out.alpha_composite(scene, (pad, sheet.height + head))
    p1 = SHOTS / "tiles_v2_preview.png"
    out.convert("RGB").save(p1)
    print(f"preview: {p1} ({out.width}x{out.height})")

    grass = grass_field(tiles)
    p2 = SHOTS / "tiles_v2_grass8x8.png"
    grass.convert("RGB").save(p2)
    print(f"grass8x8: {p2} ({grass.width}x{grass.height})")


if __name__ == "__main__":
    main()
