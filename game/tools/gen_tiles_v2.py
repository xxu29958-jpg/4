#!/usr/bin/env python3
"""gen_tiles_v2.py — 《乱世行》「暮色中原」tileset 生成器 v2。

输出（布局严格以 data/tilespec.json 为准，8 列 × 3 行 × 64px = 512×192）：
  assets/tiles/tileset.png   全套 24 块 tile
  assets/npc/shadow.png      64×32 椭圆软阴影（角色贴地用）

美术方向（设计文档 §1）：暖金压着灰绿的黄昏地表。所有地面 tile 用可平铺的
多分形值噪声做底色渐变，再统一叠 dusk 调色（高处暖金高光 #ffe0b0、凹陷青灰）。
建筑/树为透明底，物体占 tile 中下部，投影统一朝右下。

用法：python tools/gen_tiles_v2.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SEED = 184  # 黄巾起义年，固定种子保证可复现
TS = 64

ROOT = Path(__file__).resolve().parent.parent
SPEC = json.loads((ROOT / "data" / "tilespec.json").read_text(encoding="utf-8"))
FONT_BOLD = ROOT / "assets" / "fonts" / "NotoSansCJKsc-Bold.otf"


# ------------------------------------------------------------------ 工具
def _c(hexs: str) -> tuple[int, int, int]:
    hexs = hexs.lstrip("#")
    return tuple(int(hexs[i:i + 2], 16) for i in (0, 2, 4))


def _tileable_noise(rng: np.random.Generator, cells: int, size: int = TS,
                    lattice: np.ndarray | None = None) -> np.ndarray:
    """可平铺值噪声：lattice 首尾相接，返回 size×size float32 ∈ [0,1)。"""
    lat = lattice if lattice is not None else rng.random((cells, cells), dtype=np.float32)
    t = np.arange(size, dtype=np.float32) * (cells / size)
    i0 = t.astype(np.int32)
    f = (t - i0).astype(np.float32)
    i0 %= cells
    i1 = (i0 + 1) % cells
    s = f * f * (3.0 - 2.0 * f)
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    sx = s[None, :]
    sy = s[:, None]
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


def _fbm(rng: np.random.Generator, size: int = TS,
         octaves: tuple[int, ...] = (4, 8, 16, 32), gain: float = 0.55,
         shared: dict[int, np.ndarray] | None = None) -> np.ndarray:
    """分形叠加。shared 提供低频 octave 的公共 lattice —— 多块草地变体共享
    同一低频斑块场，相邻拼接时大色块连续、无网格感。"""
    out = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    for c in octaves:
        lat = shared.get(c) if shared else None
        out += amp * _tileable_noise(rng, c, size, lat)
        norm += amp
        amp *= gain
    return out / norm


# 草地变体各自使用独立的可平铺噪声场：共享场会让每块 tile 的亮斑位置
# 完全一致，平铺后呈棋盘格（第一轮教训）。靠相近色板 + 各自平铺保证接缝柔和。
WARM = np.array(_c("ffe0b0"), np.float32)   # 暖金高光
COOL = np.array(_c("5d6a72"), np.float32)   # 青灰凹陷


def _ground_base(base: tuple[int, int, int], field: np.ndarray,
                 light: tuple[int, int, int], dark: tuple[int, int, int],
                 l_amt: float = 0.55, d_amt: float = 0.55) -> np.ndarray:
    hi = np.clip((field - 0.55) / 0.45, 0, 1)[..., None]
    lo = np.clip((0.45 - field) / 0.45, 0, 1)[..., None]
    img = np.empty((*field.shape, 3), np.float32)
    img[:] = base
    img += (np.array(light, np.float32) - img) * hi * l_amt
    img += (np.array(dark, np.float32) - img) * lo * d_amt
    return img


def _dusk(img: np.ndarray, field: np.ndarray,
          warm_amt: float = 0.10, cool_amt: float = 0.16) -> np.ndarray:
    """暮色调色：噪声高处染暖金、低处染青灰。"""
    hi = (np.clip((field - 0.60) / 0.40, 0, 1) ** 1.6)[..., None]
    lo = (np.clip((0.40 - field) / 0.40, 0, 1) ** 1.6)[..., None]
    img += (WARM - img) * hi * warm_amt
    img += (COOL - img) * lo * cool_amt
    return img


def _speckle(img: np.ndarray, rng: np.random.Generator, density: float,
             delta: float) -> np.ndarray:
    m = rng.random(img.shape[:2]) < density
    d = (rng.random(img.shape[:2]) - 0.5) * 2 * delta
    img[m] += d[m, None]
    return img


def _tint(img: np.ndarray, mask: np.ndarray, color: tuple[int, int, int],
          amt: float | np.ndarray) -> None:
    a = amt if isinstance(amt, np.ndarray) else np.full(mask.shape, amt, np.float32)
    m3 = (mask * a)[..., None]
    img += (np.array(color, np.float32) - img) * m3


def _to_pil(img: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def _with_shadow(obj: Image.Image, offset: tuple[int, int] = (4, 5),
                 blur: float = 2.5, alpha: int = 80) -> Image.Image:
    """透明底物件统一右下投影。"""
    pad = 10
    big = Image.new("RGBA", (TS + pad * 2, TS + pad * 2), (0, 0, 0, 0))
    big.alpha_composite(obj, (pad, pad))
    a = big.split()[3].point(lambda v: v * alpha // 255)
    sil = Image.new("RGBA", big.size, (16, 12, 8, 0))
    sil.putalpha(a)
    layer = Image.new("RGBA", big.size, (0, 0, 0, 0))
    layer.alpha_composite(sil, offset)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    layer.alpha_composite(big)
    return layer.crop((pad, pad, pad + TS, pad + TS))


def _add_grain(obj: Image.Image, rng: np.random.Generator, delta: float = 18.0) -> Image.Image:
    """按 alpha 遮罩给已画好的物件加噪点（草针叶、夯土颗粒等）。"""
    arr = np.array(obj).astype(np.float32)
    m = (arr[..., 3:] > 0).astype(np.float32)
    n = (rng.random(arr.shape[:2] + (1,)) - 0.5) * 2 * delta
    arr[..., :3] += n * m
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_BOLD), size)


# ------------------------------------------------------------------ 地面 tile
def paint_grass(rng: np.random.Generator, base_hex: str) -> Image.Image:
    field = _fbm(rng)                                   # 各变体独立噪声场
    field = 0.5 + (field - 0.5) * 0.8                   # 低频对比收柔，防重复斑块抢戏
    img = _ground_base(_c(base_hex), field, _c("7f8f52"), _c("47532c"), 0.48, 0.5)
    _dusk(img, field, 0.08, 0.12)
    blade = _tileable_noise(rng, 32)
    _tint(img, blade > 0.72, _c("8a9a5a"), 0.32)   # 草叶亮丝
    _tint(img, blade < 0.26, _c("3f4c28"), 0.32)   # 草叶暗隙
    _speckle(img, rng, 0.05, 11)
    return _to_pil(img)


def paint_grass1(rng): return paint_grass(rng, "5d6e38")
def paint_grass2(rng): return paint_grass(rng, "66763f")
def paint_grass3(rng): return paint_grass(rng, "71804a")


def paint_grass_deco(rng: np.random.Generator) -> Image.Image:
    """花草地：与 grass2 同底色的草地 + 小野花/草簇点缀（ground 层，不透明）。"""
    field = _fbm(rng)
    field = 0.5 + (field - 0.5) * 0.8
    img = _ground_base(_c("66763f"), field, _c("7f8f52"), _c("47532c"), 0.48, 0.5)
    _dusk(img, field, 0.08, 0.12)
    blade = _tileable_noise(rng, 32)
    _tint(img, blade > 0.72, _c("8a9a5a"), 0.32)
    _tint(img, blade < 0.26, _c("3f4c28"), 0.32)
    _speckle(img, rng, 0.05, 11)
    pil = _to_pil(img)
    d = ImageDraw.Draw(pil)
    for _ in range(5):  # 小野花
        x, y = int(rng.integers(6, 58)), int(rng.integers(6, 58))
        col = [ _c("e8d98a"), _c("e8e4da"), _c("d9a7a0") ][int(rng.integers(3))]
        d.line([(x, y + 2), (x, y)], fill=_c("47532c") + (255,))
        d.point([(x, y), (x + 1, y), (x, y - 1), (x - 1, y)], fill=col + (255,))
    for _ in range(3):  # 微草簇
        x, y = int(rng.integers(6, 58)), int(rng.integers(10, 60))
        for dx in (-2, 0, 2):
            d.line([(x, y), (x + dx, y - 4)], fill=_c("7f8f52") + (255,))
    return pil


def paint_dirt(rng: np.random.Generator) -> Image.Image:
    """官道：暖赭底 + 两道车辙暗痕（整数周期摆动，横向可平铺）+ 碎石。"""
    field = _fbm(rng)
    img = _ground_base(_c("9a7d55"), field, _c("ad8f63"), _c("7a5f3e"), 0.45, 0.55)
    x = np.arange(TS, dtype=np.float32)
    ys = np.arange(TS, dtype=np.float32)[:, None]
    for yc, ph in ((20.5, 0.0), (42.5, 2.1)):
        y_rut = yc + 1.5 * np.sin(2 * np.pi * 2 * x / TS + ph) \
                  + 0.7 * np.sin(2 * np.pi * 5 * x / TS + ph * 2)
        dist = np.abs(ys - y_rut[None, :])
        m = np.clip(1 - dist / 3.2, 0, 1) ** 1.4
        _tint(img, m > 0.01, _c("654e32"), m * 0.62)
    # 两辙之间的轻脊与路缘杂草浸染
    y_mid = 31.5 + 1.2 * np.sin(2 * np.pi * 2 * x / TS + 1.0)
    m = np.clip(1 - np.abs(ys - y_mid[None, :]) / 2.2, 0, 1) ** 2
    _tint(img, m > 0.01, _c("b0926a"), m * 0.25)
    edge = np.clip((np.abs(ys - 31.5) - 12) / 10, 0, 1)
    _tint(img, edge > 0.3, _c("6b6a44"), edge * 0.18)
    _dusk(img, field, 0.08, 0.14)
    _speckle(img, rng, 0.05, 12)
    gravel = rng.random((TS, TS)) < 0.02
    _tint(img, gravel, _c("8d8577"), 0.55)
    gravel2 = rng.random((TS, TS)) < 0.01
    _tint(img, gravel2, _c("5f4c33"), 0.5)
    return _to_pil(img)


def paint_street(rng: np.random.Generator) -> Image.Image:
    """石板街：16px 错缝石板（错缝周期整除 64，四向可平铺）。"""
    field = _fbm(rng)
    img = _ground_base(_c("8d8577"), field, _c("a29a8b"), _c("6f675c"))
    pil = _to_pil(img)
    d = ImageDraw.Draw(pil, "RGBA")
    slab = 16
    gap = _c("6a6156")
    for row in range(4):
        y0 = row * slab
        off = 8 if row % 2 else 0
        d.line([(0, y0), (TS - 1, y0)], fill=gap + (230,))
        for k in range(-1, 5):
            x0 = k * slab + off
            d.line([(x0, y0), (x0, y0 + slab - 1)], fill=gap + (230,))
        for k in range(-1, 4):  # 每块板色调抖动 + 边缘体积
            x0 = k * slab + off + 1
            tone = int(rng.integers(-7, 8))
            base = tuple(max(0, min(255, v + tone)) for v in _c("8d8577"))
            d.rectangle([x0, y0 + 1, x0 + slab - 2, y0 + slab - 1], fill=base + (18,))
            d.line([(x0, y0 + 1), (x0 + slab - 2, y0 + 1)], fill=(232, 224, 206, 24))
            d.line([(x0, y0 + 1), (x0, y0 + slab - 1)], fill=(232, 224, 206, 16))
            d.line([(x0, y0 + slab - 1), (x0 + slab - 2, y0 + slab - 1)], fill=(40, 36, 30, 28))
    arr = np.array(pil.convert("RGB")).astype(np.float32)
    _dusk(arr, field, 0.08, 0.10)
    _speckle(arr, rng, 0.04, 10)
    return _to_pil(arr)


def paint_sand(rng: np.random.Generator) -> Image.Image:
    """沙滩：细波纹（整数周期，横向可平铺）。"""
    field = _fbm(rng)
    img = _ground_base(_c("c2a878"), field, _c("cbb184"), _c("a68d5e"), 0.45, 0.55)
    x = np.arange(TS, dtype=np.float32)
    for y0 in range(2, TS, 5):
        yy = y0 + 1.2 * np.sin(2 * np.pi * 3 * x / TS + y0 * 1.7)
        yi = np.clip(yy.astype(np.int32), 0, TS - 1)
        img[yi, x.astype(np.int32)] += (np.array(_c("a8905f"), np.float32)
                                        - img[yi, x.astype(np.int32)]) * 0.36
        yi2 = np.clip(yi + 1, 0, TS - 1)
        img[yi2, x.astype(np.int32)] += (np.array(_c("d8c494"), np.float32)
                                         - img[yi2, x.astype(np.int32)]) * 0.16
    _dusk(img, field, 0.08, 0.12)
    _speckle(img, rng, 0.04, 9)
    return _to_pil(img)


def paint_water(rng: np.random.Generator) -> Image.Image:
    """深青水面：横向微光波纹 + 四角轻暗角。"""
    field = _fbm(rng)
    img = _ground_base(_c("3d5a5e"), field, _c("48686a"), _c("273e42"), 0.4, 0.5)
    ys = np.arange(TS, dtype=np.float32)[:, None]
    band = (0.5 + 0.5 * np.sin(2 * np.pi * ys / 8.0)) ** 2      # 8px 周期横波
    band = band * (0.4 + 0.6 * _tileable_noise(rng, 8))          # 波强起伏
    _tint(img, band > 0.3, _c("6f9a94"), np.clip(band - 0.3, 0, 1) * 0.22)
    d_img = _to_pil(img)
    d = ImageDraw.Draw(d_img, "RGBA")
    for _ in range(7):  # 断续微光（避开边缘，保证平铺）
        y = int(rng.integers(4, 60))
        x = int(rng.integers(4, 48))
        ln = int(rng.integers(4, 10))
        d.line([(x, y), (x + ln, y)], fill=_c("6f9a94") + (55,))
        d.point([(x + ln // 2, y)], fill=_c("a8ccc2") + (80,))
    arr = np.array(d_img.convert("RGB")).astype(np.float32)
    yy, xx = np.mgrid[0:TS, 0:TS].astype(np.float32)
    corner = np.minimum(np.minimum(np.hypot(xx, yy), np.hypot(TS - 1 - xx, yy)),
                        np.minimum(np.hypot(xx, TS - 1 - yy),
                                   np.hypot(TS - 1 - xx, TS - 1 - yy)))
    vig = np.clip(1 - corner / (TS * 0.75), 0, 1) ** 2
    _tint(arr, vig > 0.01, _c("24383c"), vig * 0.30)   # 四角圆角暗角
    _dusk(arr, field, 0.06, 0.12)
    return _to_pil(arr)


def paint_farmland(rng: np.random.Generator) -> Image.Image:
    """农田：垄沟分明（8px 周期，可平铺），沟底暗、垄背暖。"""
    field = _fbm(rng)
    img = _ground_base(_c("7a5c38"), field, _c("8f6f47"), _c("5e4526"))
    ys = np.arange(TS, dtype=np.float32)[:, None]
    x = np.arange(TS, dtype=np.float32)
    wob = 0.8 * np.sin(2 * np.pi * 3 * x / TS)
    ph = ((ys - wob[None, :]) % 8.0) / 8.0          # 垄相 0..1
    groove = np.clip(1 - np.abs(ph - 0.72) / 0.18, 0, 1) ** 1.3
    crest = np.clip(1 - np.abs(ph - 0.22) / 0.16, 0, 1) ** 1.5
    _tint(img, groove > 0.01, _c("4e3519"), groove * 0.68)
    _tint(img, crest > 0.01, _c("9c7a4e"), crest * 0.5)
    _dusk(img, field, 0.11, 0.11)
    _speckle(img, rng, 0.05, 11)
    sprout = (rng.random((TS, TS)) < 0.018) & (crest > 0.5)
    _tint(img, sprout, _c("6f7d3a"), 0.65)          # 垄上稀疏青苗
    return _to_pil(img)


# ------------------------------------------------------------------ 装饰/建筑 tile
def _shade_obj(obj: Image.Image, light_col: tuple[int, int, int],
               dark_col: tuple[int, int, int], strength: float = 0.4,
               direction: tuple[float, float] = (-0.55, -0.85)) -> Image.Image:
    """按 alpha 遮罩做方向性明暗：左上受光、右下背光，给树冠/屋顶体积感。"""
    arr = np.array(obj).astype(np.float32)
    m = arr[..., 3] > 0
    if not m.any():
        return obj
    yy, xx = np.mgrid[0:TS, 0:TS].astype(np.float32)
    ys, xs = np.nonzero(m)
    cx, cy = xs.mean(), ys.mean()
    r = max(xs.max() - xs.min(), ys.max() - ys.min()) / 2 + 1e-3
    nd = np.clip(((xx - cx) * direction[0] + (yy - cy) * direction[1]) / r, -1, 1)
    m3 = m[..., None]
    arr[..., :3] += (np.array(light_col, np.float32) - arr[..., :3]) \
        * np.clip(nd, 0, 1)[..., None] * strength * m3
    arr[..., :3] += (np.array(dark_col, np.float32) - arr[..., :3]) \
        * np.clip(-nd, 0, 1)[..., None] * strength * m3
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")


def _canopy(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float,
            col: tuple[int, int, int], phase: float = 0.0,
            squash: float = 0.82, n: int | None = None) -> None:
    """松树一层树冠：压扁主圆（半侧视）+ 边缘鳞瓣。"""
    ry = r * squash
    d.ellipse([cx - r, cy - ry, cx + r, cy + ry], fill=col + (255,))
    n = n or max(6, int(r * 0.55))
    for k in range(n):
        ang = 2 * math.pi * k / n + phase
        bx = cx + math.cos(ang) * r * 0.88
        by = cy + math.sin(ang) * ry * 0.88
        br = r * (0.30 + 0.08 * math.sin(ang * 3 + phase))
        d.ellipse([bx - br, by - br, bx + br, by + br], fill=col + (255,))


def paint_tree(rng: np.random.Generator) -> Image.Image:
    """俯视/半侧视松树：三层松塔下宽上窄，左上暖受光缘，投影右下。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    cx = 30
    d.rectangle([27, 42, 33, 54], fill=_c("4a3628") + (255,))          # 树干
    d.line([(27, 42), (27, 54)], fill=_c("33261c") + (255,))
    tiers = [(48, 25, _c("2e4a2e"), 12), (39, 19, _c("365631"), 9),
             (30, 13, _c("3e6337"), 7), (22, 7, _c("476b3a"), 5)]
    for i, (cy, r, col, n) in enumerate(tiers):
        _canopy(d, cx, cy, r, col, phase=i * 0.9, n=n, squash=0.78)
    for cy, r, _, _ in tiers[:2]:                                      # 层间暗缝（轻）
        d.arc([cx - r * 0.85, cy - r * 0.45, cx + r * 0.85, cy + r * 0.75],
              30, 150, fill=_c("1e3220") + (110,), width=1)
    obj = _shade_obj(obj, _c("86a860"), _c("1c2f1e"), 0.42)
    d = ImageDraw.Draw(obj, "RGBA")
    for cy, r, _, _ in tiers:                                          # 受光缘（左上）
        d.arc([cx - r, cy - r * 0.82, cx + r, cy + r * 0.82], 185, 280,
              fill=_c("8ab06a") + (200,), width=2)
    obj = _add_grain(obj, rng, 16)
    return _with_shadow(obj)


def paint_tree_dense(rng: np.random.Generator) -> Image.Image:
    """边界密林：多冠交叠、更暗更满。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([29, 44, 35, 56], fill=_c("3a2c20") + (255,))
    lobes = [(21, 40, 18, _c("264026"), 9), (43, 38, 19, _c("264026"), 9),
             (32, 30, 20, _c("2b452b"), 10), (31, 20, 13, _c("335231"), 7)]
    for cx, cy, r, col, n in lobes:
        _canopy(d, cx, cy, r, col, phase=cx * 0.3, n=n)
    for cx, cy, r, _, _ in lobes[:-1]:
        d.arc([cx - r * 0.9, cy - r * 0.5, cx + r * 0.9, cy + r * 0.8],
              20, 160, fill=_c("182a1a") + (170,), width=2)
    obj = _shade_obj(obj, _c("557a44"), _c("14240f"), 0.45)
    obj = _add_grain(obj, rng, 16)
    return _with_shadow(obj, alpha=85)


def paint_wall(rng: np.random.Generator) -> Image.Image:
    """夯土城墙：横向贯通，顶部雉堞剪影（周期 16，横向可平铺）。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([0, 20, 63, 50], fill=_c("7a6a58") + (255,))            # 墙面
    d.rectangle([0, 16, 63, 21], fill=_c("8d7d68") + (255,))            # 墙顶走道
    for k in range(4):                                                  # 雉堞
        x0 = k * 16
        tone = int(rng.integers(-6, 7))
        mc = tuple(max(0, min(255, v + tone)) for v in _c("7a6a58"))
        d.rectangle([x0 + 1, 9, x0 + 10, 17], fill=mc + (255,))
        d.line([(x0 + 1, 9), (x0 + 10, 9)], fill=_c("9a8a72") + (255,))  # 堞顶受光
        d.line([(x0 + 10, 9), (x0 + 10, 17)], fill=_c("55483a") + (255,))
        d.rectangle([x0 + 1, 17, x0 + 11, 20], fill=(30, 24, 18, 90))    # 堞下自影
    for y in range(24, 50, 5):                                          # 夯土层线
        d.line([(0, y), (63, y)], fill=_c("655646") + (160,))
        d.line([(0, y + 1), (63, y + 1)], fill=_c("857664") + (90,))
    d.rectangle([0, 46, 63, 50], fill=(40, 32, 24, 70))                 # 墙脚自重阴影
    d.line([(0, 20), (63, 20)], fill=_c("a08e74") + (200,))             # 顶部暖边
    obj = _add_grain(obj, rng, 14)
    return _with_shadow(obj, offset=(3, 4), alpha=75)


def _thatch_roof(d: ImageDraw.ImageDraw, rng: np.random.Generator,
                 pts: list[tuple[int, int]], base: str) -> None:
    """茅草顶：梯形 + 草茎纹理 + 脊线与檐口阴影。pts = [左檐,左脊,右脊,右檐]"""
    d.polygon(pts, fill=_c(base) + (255,))
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = pts
    for x in range(x0 + 1, x3, 2):                                      # 草茎
        t = (x - x0) / max(1, x3 - x0)
        top_y = y1 + (y2 - y1) * t if x >= x1 else y0 + (y1 - y0) * (x - x0) / max(1, x1 - x0)
        if x > x2:
            top_y = y2 + (y3 - y2) * (x - x2) / max(1, x3 - x2)
        bot_y = y0 + (y3 - y0) * t
        col = _c("8f7345") if (x // 2) % 2 == 0 else _c("c2a06a")
        d.line([(x, top_y + 1), (x + int(rng.integers(-1, 2)), bot_y - 1)],
               fill=col + (110,))
    d.line([pts[1], pts[2]], fill=_c("7d6440") + (255,), width=3)       # 脊线
    d.line([(pts[1][0], pts[1][1] - 1), (pts[2][0], pts[2][1] - 1)],
           fill=_c("d8b878") + (220,), width=1)                          # 脊顶暖光
    d.line([pts[0], pts[3]], fill=_c("6b5233") + (255,), width=2)       # 檐口


def paint_house(rng: np.random.Generator) -> Image.Image:
    """民居：茅草顶 + 土墙 + 门洞，底部投影。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([12, 34, 52, 55], fill=_c("cbbfa5") + (255,))           # 土墙
    d.rectangle([46, 34, 52, 55], fill=(90, 80, 62, 70))                # 右侧背光
    d.rectangle([12, 52, 52, 55], fill=(90, 80, 62, 60))                # 墙脚
    _thatch_roof(d, rng, [(6, 38), (15, 16), (49, 16), (58, 38)], "a8895a")
    d.rectangle([12, 38, 52, 41], fill=(60, 48, 34, 110))               # 檐下阴影
    d.rectangle([28, 43, 37, 55], fill=_c("4a3826") + (255,))           # 门
    d.line([(28, 43), (37, 43)], fill=_c("2e2318") + (255,))
    d.rectangle([16, 44, 21, 49], fill=_c("5d5138") + (255,))           # 小窗
    obj = _add_grain(obj, rng, 10)
    return _with_shadow(obj)


def paint_tavern(rng: np.random.Generator) -> Image.Image:
    """酒肆：更大屋檐 + 门口挑出酒幡（暗红 #9a3b2e 白「酒」字）。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([10, 36, 54, 56], fill=_c("cbbfa5") + (255,))
    d.rectangle([47, 36, 54, 56], fill=(90, 80, 62, 70))
    d.rectangle([10, 53, 54, 56], fill=(90, 80, 62, 60))
    _thatch_roof(d, rng, [(2, 40), (12, 12), (52, 12), (62, 40)], "a8895a")
    d.rectangle([10, 40, 54, 43], fill=(60, 48, 34, 110))
    d.rectangle([25, 45, 35, 56], fill=_c("4a3826") + (255,))           # 门
    d.line([(41, 33), (55, 33)], fill=_c("5e4526") + (255,), width=2)   # 挑竿
    cloth = [(43, 34), (54, 34), (54, 49), (51, 47), (48, 50), (45, 47), (43, 49)]
    d.polygon(cloth, fill=_c("9a3b2e") + (255,))                        # 酒幡
    d.line([(54, 34), (54, 49)], fill=_c("6e2a20") + (255,))
    d.line([(43, 34), (54, 34)], fill=_c("c05a48") + (255,))
    f = _font(11)
    d.text((48.5, 41), "酒", font=f, fill=(245, 240, 228, 255), anchor="mm")
    obj = _add_grain(obj, rng, 10)
    return _with_shadow(obj)


def paint_fence(rng: np.random.Generator) -> Image.Image:
    """寨栅：一排尖木桩（桩位周期整除 64，横向可平铺）。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([0, 33, 63, 36], fill=_c("54401f") + (255,))            # 横档
    d.rectangle([0, 42, 63, 45], fill=_c("54401f") + (200,))
    for k in range(8):
        x = k * 8 + 1
        h = 24 + int(rng.integers(-2, 3))
        tone = int(rng.integers(-10, 11))
        col = tuple(max(0, min(255, v + tone)) for v in _c("6b5233"))
        top = 50 - h
        d.rectangle([x, top + 5, x + 5, 50], fill=col + (255,))
        d.polygon([(x, top + 6), (x + 2, top), (x + 5, top + 6)], fill=col + (255,))
        d.line([(x + 4, top + 4), (x + 4, 50)], fill=_c("453320") + (220,))
        d.line([(x + 1, top + 4), (x + 1, 50)], fill=_c("8a6c46") + (160,))
    obj = _add_grain(obj, rng, 12)
    return _with_shadow(obj, offset=(3, 4), alpha=70)


def paint_zhai(rng: np.random.Generator) -> Image.Image:
    """寨旗座：木台 + 赭黄大旗（风格化「黄」字），地图级地标，远看醒目。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.polygon([(8, 46), (56, 46), (60, 55), (4, 55)], fill=_c("7a5c38") + (255,))  # 木台
    for x in range(10, 58, 6):
        d.line([(x, 46), (x - 2, 55)], fill=_c("5e4526") + (160,))
    d.line([(4, 55), (60, 55)], fill=_c("453320") + (255,))
    d.line([(8, 46), (56, 46)], fill=_c("9a7a4e") + (255,))
    d.rectangle([24, 4, 28, 47], fill=_c("5e4526") + (255,))            # 旗杆
    d.line([(24, 4), (24, 47)], fill=_c("8a6c46") + (200,))
    d.ellipse([23, 1, 29, 6], fill=_c("c9a227") + (255,))               # 杆顶珠
    flag = [(28, 6), (60, 8), (58, 28), (28, 26)]                       # 大旗
    d.polygon(flag, fill=_c("c9a227") + (255,))
    d.polygon([(28, 20), (59, 22), (58, 28), (28, 26)], fill=(120, 88, 20, 90))
    d.line([(28, 6), (60, 8)], fill=_c("e8c85a") + (255,))              # 旗顶暖光
    d.line([(60, 8), (58, 28)], fill=_c("8a6a14") + (255,))
    d.polygon([(28, 30), (42, 33), (28, 38)], fill=_c("a8871f") + (255,))  # 小三角幡
    f = _font(16)
    d.text((43, 16), "黄", font=f, fill=(107, 45, 20, 255), anchor="mm")
    obj = _add_grain(obj, rng, 9)
    return _with_shadow(obj, offset=(4, 4), alpha=80)


def paint_ruins(rng: np.random.Generator) -> Image.Image:
    """废墟：焦木 + 灰石散乱堆砌，底有灰烬斑，一根断桩立残。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.ellipse([6, 28, 58, 57], fill=(40, 32, 26, 120))                  # 灰烬
    d.polygon([(28, 26), (35, 24), (37, 48), (27, 48)],
              fill=_c("4a3a2c") + (255,))                                # 断桩
    d.line([(28, 26), (35, 24)], fill=_c("241a12") + (255,))
    d.line([(28, 27), (27, 48)], fill=_c("6b5233") + (180,))
    for _ in range(4):                                                  # 焦木
        w, h = int(rng.integers(20, 30)), int(rng.integers(5, 9))
        beam = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        bd = ImageDraw.Draw(beam)
        bd.rectangle([0, 0, w - 1, h - 1], fill=_c("4a3a2c") + (255,))
        bd.line([(0, 0), (w - 1, 0)], fill=_c("6b5233") + (200,))
        bd.line([(0, h - 1), (w - 1, h - 1)], fill=_c("241a12") + (255,))
        bd.point([(int(rng.integers(2, w - 2)), int(rng.integers(1, h - 1)))],
                 fill=(30, 22, 16, 255))
        beam = beam.rotate(float(rng.integers(-70, 71)), expand=True,
                           resample=Image.BICUBIC)
        obj.alpha_composite(beam, (int(rng.integers(6, 32)), int(rng.integers(26, 44))))
    d = ImageDraw.Draw(obj, "RGBA")
    for _ in range(5):                                                  # 灰石
        x, y = int(rng.integers(10, 52)), int(rng.integers(36, 53))
        rx, ry = int(rng.integers(3, 7)), int(rng.integers(2, 5))
        d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=_c("7d7a72") + (255,))
        d.arc([x - rx, y - ry, x + rx, y + ry], 180, 300, fill=_c("9c988e") + (220,))
        d.arc([x - rx, y - ry, x + rx, y + ry], 20, 130, fill=_c("54524c") + (220,))
    d.point([(30, 46), (40, 42), (24, 44)], fill=(200, 120, 50, 170))   # 余烬
    obj = _add_grain(obj, rng, 12)
    return _with_shadow(obj, offset=(3, 3), alpha=60)


# ------------------------------------------------------------------ 小件装饰
def paint_reed(rng: np.random.Generator) -> Image.Image:
    """芦苇丛：水边软化边界用，青绿带黄、茎粗穗大。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    for k in range(9):
        bx = 16 + k * 4 + int(rng.integers(-2, 3))
        top_y = int(rng.integers(12, 26))
        bend = int(rng.integers(-5, 7))
        col = [_c("767f44"), _c("828a4c"), _c("64703a")][int(rng.integers(3))]
        px, py = float(bx), 58.0
        width = 2 if k % 3 == 0 else 1
        for t in np.linspace(0, 1, 7):                                  # 弧形茎
            nx = bx + bend * t * t
            ny = 58 + (top_y - 58) * t
            d.line([(px, py), (nx, ny)], fill=col + (255,), width=width)
            px, py = nx, ny
        d.ellipse([px - 2, py - 6, px + 2, py + 1], fill=_c("6e5a36") + (255,))  # 穗
        d.line([(px - 1, py - 5), (px - 1, py)], fill=_c("8a744a") + (200,))
    return _with_shadow(obj, offset=(2, 2), blur=1.5, alpha=50)


def _tuft(rng: np.random.Generator, cols: list[str], n: int,
          spread: int, hmax: int) -> Image.Image:
    """草簇：多基部、长叶扇形展开，要在草地上看得见的体量。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.ellipse([24, 50, 40, 55], fill=(30, 36, 20, 90))                  # 根部压暗
    for bx in (27, 32, 37):
        for _ in range(n // 3):
            tip_x = bx + int(rng.integers(-spread, spread + 1))
            tip_y = 52 - int(rng.integers(hmax // 2, hmax))
            col = _c(cols[int(rng.integers(len(cols)))])
            mid = ((bx + tip_x) / 2 + (tip_x - bx) * 0.2, (52 + tip_y) / 2)
            d.line([(bx, 52), mid, (tip_x, tip_y)], fill=col + (255,))
            d.point([(tip_x, tip_y)], fill=_c("9aaa62") + (220,))
    return _with_shadow(obj, offset=(2, 2), blur=1.2, alpha=45)


def paint_tuft1(rng): return _tuft(rng, ["66763f", "7f8f52", "556230", "8a9a5a"], 15, 11, 16)
def paint_tuft2(rng): return _tuft(rng, ["71804a", "8a7d4a", "9a8a52", "5d6e38"], 12, 14, 12)


def paint_stone(rng: np.random.Generator) -> Image.Image:
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    for _ in range(4):
        x = 32 + int(rng.integers(-12, 13))
        y = 46 + int(rng.integers(-6, 7))
        rx, ry = int(rng.integers(2, 6)), int(rng.integers(2, 4))
        tone = int(rng.integers(-12, 13))
        col = tuple(max(0, min(255, v + tone)) for v in _c("7d7a72"))
        d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=col + (255,))
        d.arc([x - rx, y - ry, x + rx, y + ry], 180, 300, fill=_c("a09c92") + (220,))
    return _with_shadow(obj, offset=(2, 2), blur=1.2, alpha=55)


def paint_flower(rng: np.random.Generator) -> Image.Image:
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    for _ in range(7):
        x = 32 + int(rng.integers(-16, 17))
        y = 50 + int(rng.integers(-7, 8))
        h = int(rng.integers(6, 12))
        d.line([(x, y), (x + int(rng.integers(-1, 2)), y - h)],
               fill=_c("4f5c30") + (255,))
        col = [_c("e8d98a"), _c("e8e4da"), _c("d9a7a0")][int(rng.integers(3))]
        fx, fy = x, y - h
        for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1),
                       (-1, -1), (1, 1)):
            d.point([(fx + dx, fy + dy)], fill=col + (255,))
        d.point([(fx, fy)], fill=_c("c9a227") + (255,))
    return _with_shadow(obj, offset=(1, 1), blur=1.0, alpha=40)


def paint_sign(rng: np.random.Generator) -> Image.Image:
    """木牌：立柱 + 刻痕板面。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([29, 26, 34, 52], fill=_c("6b5233") + (255,))
    d.line([(29, 26), (29, 52)], fill=_c("8a6c46") + (200,))
    board = Image.new("RGBA", (30, 14), (0, 0, 0, 0))
    bd = ImageDraw.Draw(board)
    bd.rectangle([0, 0, 29, 13], fill=_c("8a6a42") + (255,))
    bd.rectangle([0, 0, 29, 13], outline=_c("54401f") + (255,))
    bd.line([(4, 4), (25, 4)], fill=_c("4a3826") + (220,))
    bd.line([(6, 8), (23, 8)], fill=_c("4a3826") + (200,))
    bd.line([(8, 11), (21, 11)], fill=_c("4a3826") + (160,))
    board = board.rotate(-4, expand=True, resample=Image.BICUBIC)
    obj.alpha_composite(board, (16, 14))
    obj = _add_grain(obj, rng, 10)
    return _with_shadow(obj, offset=(3, 3), blur=2, alpha=65)


def paint_campfire(rng: np.random.Generator) -> Image.Image:
    """篝火：石圈 + 柴堆 + 火苗，带 #e8a33d 火光橙晕（自身发光，不投影）。"""
    obj = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    glow = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = 32, 42
    for r in range(30, 0, -2):
        a = int(80 * (1 - r / 30) ** 1.8)
        gd.ellipse([cx - r, cy - r * 0.8, cx + r, cy + r * 0.8],
                   fill=(232, 163, 61, a))
    obj.alpha_composite(glow.filter(ImageFilter.GaussianBlur(3)))
    d = ImageDraw.Draw(obj, "RGBA")
    for k in range(7):                                                  # 石圈
        ang = 2 * math.pi * k / 7
        x = cx + math.cos(ang) * 12
        y = cy + math.sin(ang) * 8
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=_c("7d7a72") + (255,))
        d.point([(x - 1, y - 1)], fill=_c("a09c92") + (220,))
    for pts in [[(24, 44), (40, 38)], [(26, 37), (40, 45)]]:            # 交叉柴
        d.line(pts, fill=_c("4a3a2c") + (255,), width=3)
        d.line([pts[0], (pts[0][0] + 3, pts[0][1])], fill=_c("6b5233") + (255,), width=1)
    flame = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))                   # 火苗
    fd = ImageDraw.Draw(flame)
    fd.polygon([(32, 19), (39, 35), (37, 42), (27, 42), (25, 35)],
               fill=(217, 122, 42, 230))
    fd.polygon([(32, 25), (37, 36), (35, 41), (29, 41), (27, 36)],
               fill=(232, 163, 61, 240))
    fd.polygon([(32, 31), (35, 38), (32, 41), (29, 38)], fill=(245, 217, 122, 255))
    obj.alpha_composite(flame.filter(ImageFilter.GaussianBlur(0.6)))
    for _ in range(3):                                                  # 火星
        x, y = 32 + int(rng.integers(-6, 7)), int(rng.integers(18, 30))
        d = ImageDraw.Draw(obj)
        d.point([(x, y)], fill=(245, 200, 100, 200))
    return obj


# ------------------------------------------------------------------ 装配
PAINTERS = {
    "grass1": paint_grass1, "grass2": paint_grass2, "grass3": paint_grass3,
    "dirt": paint_dirt, "street": paint_street, "sand": paint_sand,
    "water": paint_water, "grass_deco": paint_grass_deco,
    "tree": paint_tree, "tree_dense": paint_tree_dense, "wall": paint_wall,
    "house": paint_house, "tavern": paint_tavern, "farmland": paint_farmland,
    "fence": paint_fence, "zhai": paint_zhai, "ruins": paint_ruins,
    "reed": paint_reed, "tuft1": paint_tuft1, "tuft2": paint_tuft2,
    "stone": paint_stone, "flower": paint_flower, "sign": paint_sign,
    "campfire": paint_campfire,
}


def gen_tileset() -> Path:
    cols = SPEC["columns"]
    rows = math.ceil(len(SPEC["tiles"]) / cols)
    atlas = Image.new("RGBA", (cols * TS, rows * TS), (0, 0, 0, 0))
    for idx, (name, meta) in enumerate(SPEC["tiles"].items()):
        rng = np.random.default_rng(SEED * 1000 + idx)
        tile = PAINTERS[name](rng)
        x, y = meta["xy"]
        atlas.alpha_composite(tile, (x * TS, y * TS))
        print(f"  {name:<10} -> ({x},{y})")
    out = ROOT / "assets" / "tiles" / "tileset.png"
    atlas.save(out)
    print(f"tileset: {out} ({atlas.width}x{atlas.height})")
    return out


def gen_shadow() -> Path:
    """64×32 椭圆软阴影，半透明黑，角色贴地用。"""
    w, h = 64, 32
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dd = ((xx - (w - 1) / 2) / (w * 0.44)) ** 2 + ((yy - (h - 1) / 2) / (h * 0.40)) ** 2
    alpha = (np.clip(1 - dd, 0, 1) ** 1.5 * 105).astype(np.uint8)
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0] = 14
    arr[..., 1] = 11
    arr[..., 2] = 8
    arr[..., 3] = alpha
    out = ROOT / "assets" / "npc" / "shadow.png"
    Image.fromarray(arr, "RGBA").save(out)
    print(f"shadow:  {out} ({w}x{h})")
    return out


if __name__ == "__main__":
    gen_tileset()
    gen_shadow()
