#!/usr/bin/env python3
"""gen_props_v2.py — 《乱世行》「暮色中原」道具精灵生成器（art pass 2）。

角色世界内高度 64~74px（1 tile = 64px），建筑按真实比例做多格大尺寸 PNG：
  assets/props/house.png        128×128  夯土墙 + 茅草顶民居（俯视 3/4）
  assets/props/tavern.png       192×144  酒肆（挑檐 + 酒幡 + 酒坛 + 灯笼）
  assets/props/zhai_seat.png    128×128  山寨主座（木台 + 高大旗杆 + 赭黄「黄」字大旗）
  assets/props/tree_big.png      96×120  大松树（地标散树）
  assets/props/wall_h.png        64×96   城墙·横（3 米高：顶面 + 雉堞 + 南立面）
  assets/props/wall_v.png        64×96   城墙·竖
  assets/props/tent.png          96×96   军营帐篷（灰白破帆布）
  assets/props/campfire_big.png  64×64   篝火堆（废营视觉锚点，橙光晕）

铁律：透明底、底部统一右下投影、暖暮色调色与 tileset 一致、seed 固定可复现。
复用 gen_tiles_v2 的色板/颗粒/字体/树冠函数；投影与方向明暗此处按任意画布泛化。

用法：python tools/gen_props_v2.py
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_tiles_v2 import _c, _add_grain, _canopy, _font  # 复用 v2 美术函数

SEED = 184
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "props"


# ------------------------------------------------------------------ 泛化工具
def shade_obj(obj: Image.Image, light_col: tuple[int, int, int],
              dark_col: tuple[int, int, int], strength: float = 0.4,
              direction: tuple[float, float] = (-0.55, -0.85)) -> Image.Image:
    """方向性明暗（任意画布）：左上受光、右下背光。"""
    arr = np.array(obj).astype(np.float32)
    m = arr[..., 3] > 0
    if not m.any():
        return obj
    yy, xx = np.mgrid[0:obj.height, 0:obj.width].astype(np.float32)
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


def ground_shadow(size: tuple[int, int], cx: float, cy: float,
                  rx: float, ry: float, alpha: int = 85,
                  blur: float = 4.0) -> Image.Image:
    """贴地椭圆软阴影（由调用者摆在物体底部偏右下）。"""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for t in np.linspace(1.0, 0.0, 9):
        a = int(alpha * (1 - t) ** 1.5)
        d.ellipse([cx - rx * t, cy - ry * t, cx + rx * t, cy + ry * t],
                  fill=(16, 12, 8, a))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def canvas(size: tuple[int, int], *layers: Image.Image) -> Image.Image:
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    for l in layers:
        img.alpha_composite(l)
    return img


def _thatch_streaks(d: ImageDraw.ImageDraw, rng: np.random.Generator,
                    x0: int, x1: int, top_fn, eave_y: float,
                    step: int = 2, alpha: int = 95) -> None:
    """茅草茎纹：从脊线/坡顶线向下檐口画明暗交替短茎。"""
    for x in range(x0, x1, step):
        ty = top_fn(x)
        col = _c("8f7345") if (x // step) % 2 == 0 else _c("c2a06a")
        d.line([(x, ty), (x + int(rng.integers(-1, 2)), eave_y)],
               fill=col + (alpha,))


def _ridge_cap(d: ImageDraw.ImageDraw, p0: tuple, p1: tuple) -> None:
    """屋脊：暗色脊条 + 顶部暖光 + 束草节。"""
    d.line([p0, p1], fill=_c("7d6440") + (255,), width=4)
    d.line([(p0[0], p0[1] - 2), (p1[0], p1[1] - 2)], fill=_c("d8b878") + (230,), width=1)
    for x in range(int(p0[0]) + 3, int(p1[0]), 7):
        d.line([(x, p0[1] - 2), (x, p0[1] + 2)], fill=_c("5e4526") + (160,))


# ------------------------------------------------------------------ 民居
def gen_house(rng: np.random.Generator) -> Image.Image:
    W = H = 128
    sh = ground_shadow((W, H), 68, 113, 54, 11, alpha=85, blur=4)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    # 南立面（屋顶覆盖其上沿，先画；立面要够高才读得出"房子"）
    d.rectangle([22, 80, 106, 114], fill=_c("cbbfa5") + (255,))
    d.rectangle([100, 80, 110, 112], fill=_c("b3a78d") + (255,))      # 东山面
    d.rectangle([22, 110, 110, 114], fill=(90, 80, 62, 90))           # 墙脚
    for x in (22, 106):                                               # 角柱
        d.rectangle([x - 1, 82, x + 1, 114], fill=_c("8a6a42") + (255,))
    d.rectangle([56, 92, 72, 114], fill=_c("4a3826") + (255,))        # 门
    d.line([(64, 92), (64, 114)], fill=_c("2e2318") + (255,))
    d.line([(56, 92), (72, 92)], fill=_c("2e2318") + (255,))
    d.rectangle([54, 114, 74, 117], fill=_c("8d8577") + (255,))       # 门槛石
    d.rectangle([32, 94, 42, 104], fill=_c("5d5138") + (255,))        # 窗
    d.line([(37, 94), (37, 104)], fill=_c("3a3122") + (255,))
    # 屋顶（约占 70% 面积）：南大坡 + 脊 + 北窄坡
    roof = [(16, 38), (34, 20), (94, 20), (112, 38), (112, 90), (16, 90)]
    d.polygon(roof, fill=_c("a8895a") + (255,))

    def top_fn(x: float) -> float:                                    # 坡顶线（脊+两抹坡）
        if x < 34:
            return 38 - (x - 16)
        if x > 94:
            return 20 + (x - 94)
        return 20.0

    d.polygon([(16, 38), (34, 20), (94, 20), (112, 38)],
              fill=(56, 40, 24, 70))                                   # 北坡压暗
    _thatch_streaks(d, rng, 18, 112, top_fn, 88)
    for yy in range(46, 88, 9):                                        # 苫草层叠横线
        d.line([(17, yy), (111, yy)], fill=_c("8f7345") + (50,))
    _ridge_cap(d, (34, 20), (94, 20))
    d.line([(16, 38), (34, 20)], fill=_c("8f7345") + (220,), width=2)  # 垂脊
    d.line([(94, 20), (112, 38)], fill=_c("6b5233") + (220,), width=2)
    d.line([(16, 88), (112, 88)], fill=_c("6b5233") + (255,), width=2)  # 檐口
    d.rectangle([22, 90, 110, 94], fill=(60, 48, 34, 100))             # 檐下阴
    d.line([(17, 39), (33, 24)], fill=_c("d8b878") + (150,), width=1)  # 西北暖缘
    obj = shade_obj(obj, _c("e8d0a0"), _c("4a3a28"), 0.22)
    obj = _add_grain(obj, rng, 12)
    return canvas((W, H), sh, obj)


# ------------------------------------------------------------------ 酒肆
def gen_tavern(rng: np.random.Generator) -> Image.Image:
    W, H = 192, 144
    sh = ground_shadow((W, H), 88, 128, 76, 12, alpha=85, blur=4)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    # 南立面
    d.rectangle([18, 88, 150, 122], fill=_c("cbbfa5") + (255,))
    d.rectangle([144, 88, 154, 120], fill=_c("b3a78d") + (255,))
    d.rectangle([18, 118, 154, 122], fill=(90, 80, 62, 90))
    for x in (18, 82, 150):                                            # 木柱
        d.rectangle([x - 2, 88, x + 2, 122], fill=_c("8a6a42") + (255,))
        d.line([(x - 2, 88), (x - 2, 122)], fill=_c("6b5233") + (255,))
    d.rectangle([58, 96, 94, 122], fill=_c("4a3826") + (255,))         # 双扇门
    d.line([(76, 96), (76, 122)], fill=_c("2e2318") + (255,))
    d.polygon([(58, 96), (76, 96), (70, 106), (58, 104)],
              fill=_c("5d4a33") + (255,))                               # 门帘半卷
    d.rectangle([30, 100, 44, 112], fill=_c("5d5138") + (255,))        # 窗
    d.line([(37, 100), (37, 112)], fill=_c("3a3122") + (255,))
    # 大屋顶（挑檐）
    roof = [(8, 38), (34, 14), (122, 14), (156, 38), (156, 92), (8, 92)]
    d.polygon(roof, fill=_c("a8895a") + (255,))

    def top_fn(x: float) -> float:
        if x < 34:
            return 38 - (x - 8) * (24 / 26)
        if x > 122:
            return 14 + (x - 122) * (24 / 34)
        return 14.0

    d.polygon([(8, 38), (34, 14), (122, 14), (156, 38)], fill=(56, 40, 24, 70))
    _thatch_streaks(d, rng, 10, 156, top_fn, 90)
    for yy in range(48, 90, 9):
        d.line([(9, yy), (155, yy)], fill=_c("8f7345") + (50,))
    _ridge_cap(d, (34, 14), (122, 14))
    d.line([(8, 38), (34, 14)], fill=_c("8f7345") + (220,), width=2)
    d.line([(122, 14), (156, 38)], fill=_c("6b5233") + (220,), width=2)
    d.line([(8, 90), (156, 90)], fill=_c("6b5233") + (255,), width=2)
    d.rectangle([18, 92, 154, 98], fill=(60, 48, 34, 120))             # 檐下阴
    for x in (26, 82, 146):                                            # 挑檐枨
        d.polygon([(x, 92), (x + 6, 92), (x, 100)], fill=_c("6b5233") + (255,))
    # 灯笼（檐角，暖光）
    d.line([(30, 92), (30, 98)], fill=_c("4a3826") + (255,))
    d.ellipse([24, 98, 36, 110], fill=_c("d98a3a") + (255,))
    d.ellipse([27, 100, 33, 108], fill=_c("f0b060") + (255,))
    d.line([(24, 104), (36, 104)], fill=_c("9a5a20") + (200,))
    # 门口木柱挑酒幡
    d.rectangle([162, 64, 166, 122], fill=_c("5e4526") + (255,))       # 幡柱
    d.line([(162, 64), (162, 122)], fill=_c("8a6c46") + (200,))
    d.line([(150, 66), (186, 66)], fill=_c("5e4526") + (255,), width=2)  # 挑竿
    cloth = [(160, 68), (184, 68), (184, 106), (179, 102), (173, 108),
             (167, 103), (160, 107)]
    d.polygon(cloth, fill=_c("9a3b2e") + (255,))
    d.polygon([(160, 68), (184, 68), (184, 76), (160, 74)],
              fill=(255, 220, 180, 40))                                 # 幡顶受光
    d.line([(184, 68), (184, 106)], fill=_c("6e2a20") + (255,))
    d.text((172, 86), "酒", font=_font(22), fill=(245, 240, 228, 255), anchor="mm")
    # 门前酒坛
    for jx, jr in ((104, 8), (118, 10), (130, 7)):
        d.ellipse([jx - jr, 122 - jr * 2, jx + jr, 122], fill=_c("7a4a2e") + (255,))
        d.ellipse([jx - jr // 2, 122 - jr * 2 - 2, jx + jr // 2, 122 - jr * 2 + 3],
                  fill=_c("4a2c1a") + (255,))
        d.arc([jx - jr, 122 - jr * 2, jx + jr, 122], 180, 300,
              fill=_c("a87a4e") + (220,))
    obj = shade_obj(obj, _c("e8d0a0"), _c("4a3a28"), 0.20)
    obj = _add_grain(obj, rng, 11)
    return canvas((W, H), sh, obj)


# ------------------------------------------------------------------ 山寨主座
def gen_zhai_seat(rng: np.random.Generator) -> Image.Image:
    W = H = 128
    sh = ground_shadow((W, H), 68, 112, 52, 11, alpha=90, blur=4)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    # 交叉长矛（杆在台后）
    for p0, p1 in [((36, 90), (60, 44)), ((68, 90), (44, 48))]:
        d.line([p0, p1], fill=_c("5e4526") + (255,), width=2)
        tip = p1
        d.polygon([(tip[0] - 3, tip[1] + 4), (tip[0] + 3, tip[1] + 4),
                   (tip[0], tip[1] - 4)], fill=_c("b8bcc0") + (255,))
    # 木台：腿 + 台面正面 + 台面顶面 + 围栏
    for x in (28, 60, 100):
        d.rectangle([x, 96, x + 5, 114], fill=_c("453320") + (255,))
    d.rectangle([20, 88, 108, 100], fill=_c("5e4526") + (255,))        # 台沿
    d.polygon([(20, 88), (108, 88), (100, 78), (28, 78)],
              fill=_c("8a6a42") + (255,))                               # 台面
    for x in range(30, 100, 8):
        d.line([(x, 87), (x + 1, 79)], fill=_c("5e4526") + (140,))
    for x in (24, 64, 104):                                            # 围栏柱
        d.rectangle([x, 70, x + 3, 79], fill=_c("6b5233") + (255,))
    d.line([(24, 71), (107, 71)], fill=_c("6b5233") + (255,), width=2)
    d.line([(20, 88), (108, 88)], fill=_c("a87a4e") + (255,))          # 台沿暖光
    # 大旗杆
    d.rectangle([46, 6, 53, 90], fill=_c("5e4526") + (255,))
    d.line([(46, 6), (46, 90)], fill=_c("8a6c46") + (220,))
    d.line([(52, 6), (52, 90)], fill=_c("3a2c18") + (220,))
    d.ellipse([45, 1, 54, 9], fill=_c("c9a227") + (255,))              # 杆顶珠
    d.arc([45, 1, 54, 9], 140, 300, fill=_c("e8c85a") + (255,))
    # 赭黄大旗
    flag = [(53, 10), (120, 15), (116, 48), (53, 43)]
    d.polygon(flag, fill=_c("c9a227") + (255,))
    d.polygon([(53, 34), (117, 39), (116, 48), (53, 43)],
              fill=(120, 88, 20, 100))                                  # 旗面下暗
    d.line([(53, 10), (120, 15)], fill=_c("e8c85a") + (255,), width=2)  # 旗顶暖光
    d.line([(120, 15), (116, 48)], fill=_c("8a6a14") + (255,))
    d.text((86, 28), "黄", font=_font(26), fill=(107, 45, 20, 255), anchor="mm")
    d.polygon([(53, 50), (76, 54), (53, 64)], fill=_c("a8871f") + (255,))  # 三角幡
    obj = _add_grain(obj, rng, 9)
    return canvas((W, H), sh, obj)


# ------------------------------------------------------------------ 大松树
def gen_tree_big(rng: np.random.Generator) -> Image.Image:
    W, H = 96, 120
    sh = ground_shadow((W, H), 52, 108, 36, 9, alpha=90, blur=4)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    cx = 44
    d.polygon([(40, 66), (49, 66), (53, 110), (37, 110)],
              fill=_c("4a3628") + (255,))                               # 树干
    d.line([(40, 68), (38, 110)], fill=_c("33261c") + (255,))
    d.line([(44, 70), (43, 108)], fill=_c("5e4526") + (200,))
    d.polygon([(37, 110), (44, 102), (44, 110)], fill=_c("3a2c20") + (255,))  # 根
    d.polygon([(53, 110), (48, 102), (48, 110)], fill=_c("33261c") + (255,))
    tiers = [(78, 38, _c("2e4a2e"), 14), (65, 33, _c("33502f"), 12),
             (52, 27, _c("3a5c34"), 11), (40, 20, _c("416637"), 9),
             (29, 12, _c("476b3a"), 7)]
    for i, (cy, r, col, n) in enumerate(tiers):
        _canopy(d, cx, cy, r, col, phase=i * 0.9, n=n, squash=0.78)
    for cy, r, _, _ in tiers[:3]:                                       # 层间暗缝（轻）
        d.arc([cx - r * 0.85, cy - r * 0.4, cx + r * 0.85, cy + r * 0.72],
              30, 150, fill=_c("1e3220") + (100,), width=1)
    obj = shade_obj(obj, _c("86a860"), _c("16241a"), 0.42)
    d = ImageDraw.Draw(obj, "RGBA")
    for cy, r, _, _ in tiers:                                           # 受光缘
        d.arc([cx - r, cy - r * 0.78, cx + r, cy + r * 0.78], 185, 280,
              fill=_c("8ab06a") + (190,), width=2)
    obj = _add_grain(obj, rng, 16)
    return canvas((W, H), sh, obj)


# ------------------------------------------------------------------ 城墙（横/竖）
def _merlon_h(d: ImageDraw.ImageDraw, x: int, y: int, w: int,
              base: tuple[int, int, int], tone: int) -> None:
    """横墙雉堞：正面方块 + 顶面小平行四边形（读出厚度），高对比。"""
    mc = tuple(max(0, min(255, v + tone)) for v in base)
    d.rectangle([x, y, x + w, y + 13], fill=mc + (255,))
    d.polygon([(x, y), (x + w, y), (x + w - 2, y - 5), (x + 2, y - 5)],
              fill=tuple(min(255, v + 40) for v in mc) + (255,))
    d.line([(x + w, y - 3), (x + w, y + 13)], fill=_c("453a2c") + (255,))
    d.line([(x, y + 13), (x + w, y + 13)], fill=_c("453a2c") + (200,))
    d.line([(x, y), (x + w, y)], fill=_c("a8947a") + (255,))


def gen_wall_h(rng: np.random.Generator) -> Image.Image:
    """城墙·横：顶面走道 + 北侧雉堞 + 高南立面（竖向阴影条纹 + 夯土层线）。"""
    W, H = 64, 96
    sh = ground_shadow((W, H), 34, 87, 30, 6, alpha=80, blur=3)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([2, 36, 62, 84], fill=_c("736450") + (255,))           # 南立面（深一号）
    arr = np.array(obj).astype(np.float32)                              # 立面竖向渐变
    m = arr[..., 3] > 0
    grad = np.zeros((H, W), np.float32)
    yy = np.arange(H, dtype=np.float32)[:, None]
    grad[:] = np.clip((yy - 36) / 48, 0, 1)
    arr[..., :3] += (np.array(_c("463b2e"), np.float32) - arr[..., :3]) \
        * (grad * 0.5 * m)[..., None]
    obj = Image.fromarray(np.clip(arr + 0, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(obj, "RGBA")
    for _ in range(6):                                                  # 竖向雨痕/阴影条纹
        x = int(rng.integers(4, 60))
        d.line([(x, 40), (x, 82)], fill=(44, 36, 28, 80))
    for y in range(44, 84, 7):                                          # 夯土层线
        d.line([(2, y), (62, y)], fill=_c("5d4f40") + (170,))
        d.line([(2, y + 1), (62, y + 1)], fill=_c("857664") + (70,))
    for x in (2, 32, 60):                                               # 垛间壁柱
        d.rectangle([x, 36, x + 3, 84], fill=(52, 43, 34, 90))
        d.line([(x, 36), (x, 84)], fill=_c("8d7d68") + (120,))
    d.polygon([(2, 36), (62, 36), (58, 24), (6, 24)],
              fill=_c("857662") + (255,))                               # 顶面走道
    d.line([(6, 24), (58, 24)], fill=_c("a8947a") + (255,))
    d.line([(2, 36), (62, 36)], fill=_c("5d4f40") + (255,))
    for k in range(4):                                                  # 雉堞（加粗）
        x = 2 + k * 16
        _merlon_h(d, x, 12, 11, _c("736450"), int(rng.integers(-6, 7)))
        d.rectangle([x, 25, x + 11, 28], fill=(26, 20, 14, 110))        # 堞下影
    d.rectangle([2, 80, 62, 84], fill=(40, 32, 24, 90))                 # 墙脚
    obj = _add_grain(obj, rng, 13)
    return canvas((W, H), sh, obj)


def gen_wall_v(rng: np.random.Generator) -> Image.Image:
    """城墙·竖：西立面 + 顶面 + 东侧雉堞，与横墙同高同配色。"""
    W, H = 64, 96
    sh = ground_shadow((W, H), 34, 90, 24, 4, alpha=55, blur=3)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.rectangle([10, 4, 26, 92], fill=_c("685a49") + (255,))           # 西立面（深一号）
    arr = np.array(obj).astype(np.float32)
    m = arr[..., 3] > 0
    grad = np.zeros((H, W), np.float32)
    yy = np.arange(H, dtype=np.float32)[:, None]
    grad[:] = np.clip((yy - 4) / 88, 0, 1)
    arr[..., :3] += (np.array(_c("3e3327"), np.float32) - arr[..., :3]) \
        * (grad * 0.38 * m)[..., None]                                  # 渐变收柔防叠段接缝
    obj = Image.fromarray(np.clip(arr + 0, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(obj, "RGBA")
    for y in range(12, 92, 7):                                          # 层线沿墙长
        d.line([(10, y), (26, y)], fill=_c("54463a") + (160,))
    for _ in range(5):
        y = int(rng.integers(8, 86))
        d.line([(12, y), (24, y)], fill=(36, 30, 23, 80))
    d.polygon([(26, 4), (42, 8), (42, 94), (26, 92)],
              fill=_c("857662") + (255,))                               # 顶面
    d.line([(26, 4), (26, 92)], fill=_c("a8947a") + (200,))
    d.line([(42, 8), (42, 94)], fill=_c("5d4f40") + (255,))
    for k in range(6):                                                  # 东侧雉堞（16px 节理，竖向叠段连续）
        y = 8 + k * 16
        tone = int(rng.integers(-6, 7))
        mc = tuple(max(0, min(255, v + tone)) for v in _c("736450"))
        d.rectangle([42, y, 55, y + 10], fill=mc + (255,))
        d.polygon([(42, y), (55, y), (53, y - 5), (44, y - 5)],
                  fill=tuple(min(255, v + 40) for v in mc) + (255,))
        d.line([(55, y - 3), (55, y + 10)], fill=_c("453a2c") + (255,))
        d.line([(42, y + 10), (55, y + 10)], fill=_c("453a2c") + (200,))
    d.rectangle([10, 90, 55, 93], fill=(40, 32, 24, 70))                # 墙脚（轻，防叠段断层）
    obj = _add_grain(obj, rng, 13)
    return canvas((W, H), sh, obj)


# ------------------------------------------------------------------ 帐篷
def gen_tent(rng: np.random.Generator) -> Image.Image:
    """军营帐篷：灰白破帆布，人字顶 3/4，牵绳地钉 + 开口。"""
    W = H = 96
    sh = ground_shadow((W, H), 50, 84, 42, 8, alpha=80, blur=4)
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(obj, "RGBA")
    d.line([(14, 36), (4, 88)], fill=_c("8a8577") + (255,))            # 牵绳
    d.line([(82, 36), (92, 88)], fill=_c("8a8577") + (255,))
    d.point([(4, 88), (5, 88)], fill=_c("4a3826") + (255,))            # 地钉
    d.point([(92, 88), (91, 88)], fill=_c("4a3826") + (255,))
    tent = [(14, 36), (40, 20), (58, 20), (84, 36), (88, 78), (10, 78)]
    d.polygon(tent, fill=_c("b8b4a8") + (255,))                        # 帆布
    d.polygon([(14, 36), (40, 20), (58, 20), (84, 36)],
              fill=(70, 66, 58, 60))                                    # 北坡
    d.line([(40, 20), (58, 20)], fill=_c("8a8577") + (255,), width=3)  # 脊
    d.line([(40, 18), (58, 18)], fill=_c("e0dccd") + (220,))
    for x in range(16, 86, 4):                                          # 帆布缝
        ty = 36 - (x - 14) * (16 / 26) if x < 40 else (
            20 if x <= 58 else 20 + (x - 58) * (16 / 26))
        d.line([(x, ty + 2), (x, 76)], fill=(120, 116, 104, 60))
    d.line([(14, 36), (10, 78)], fill=_c("8a8577") + (255,))           # 侧棱
    d.line([(84, 36), (88, 78)], fill=_c("7a7568") + (255,))
    d.line([(10, 77), (88, 77)], fill=_c("7a7568") + (255,), width=2)  # 底边压条
    d.polygon([(38, 78), (60, 78), (49, 48)],
              fill=_c("3a352c") + (255,))                               # 开口
    d.line([(49, 48), (60, 78)], fill=_c("6b675c") + (255,))
    d.line([(49, 48), (38, 78)], fill=_c("8a8577") + (255,))
    for _ in range(3):                                                  # 补丁
        x, y = int(rng.integers(16, 70)), int(rng.integers(40, 66))
        tone = int(rng.integers(-14, 15))
        pc = tuple(max(0, min(255, v + tone)) for v in _c("b8b4a8"))
        d.rectangle([x, y, x + 7, y + 5], fill=pc + (200,))
        d.rectangle([x, y, x + 7, y + 5], outline=_c("8a8577") + (160,))
    obj = shade_obj(obj, _c("e8e4d8"), _c("4a463c"), 0.25)
    obj = _add_grain(obj, rng, 10)
    return canvas((W, H), sh, obj)


# ------------------------------------------------------------------ 大篝火
def gen_campfire_big(rng: np.random.Generator) -> Image.Image:
    W = H = 64
    obj = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = 32, 42
    for r in range(30, 0, -2):
        a = int(85 * (1 - r / 30) ** 1.8)
        gd.ellipse([cx - r, cy - r * 0.75, cx + r, cy + r * 0.75],
                   fill=(232, 163, 61, a))
    obj.alpha_composite(glow.filter(ImageFilter.GaussianBlur(3)))
    d = ImageDraw.Draw(obj, "RGBA")
    for k in range(8):                                                  # 石圈
        ang = 2 * math.pi * k / 8 + 0.3
        x = cx + math.cos(ang) * 14
        y = cy + math.sin(ang) * 9
        d.ellipse([x - 3, y - 2, x + 3, y + 2], fill=_c("7d7a72") + (255,))
        d.point([(x - 1, y - 1)], fill=_c("a09c92") + (220,))
    for p0 in [(20, 46), (26, 48), (44, 46), (38, 48)]:                 # 锥形柴堆
        d.line([p0, (32, 28)], fill=_c("4a3a2c") + (255,), width=3)
        d.line([p0, ((p0[0] + 32) // 2, (p0[1] + 28) // 2)],
               fill=_c("6b5233") + (160,), width=1)
    flame = Image.new("RGBA", (W, H), (0, 0, 0, 0))                     # 火苗
    fd = ImageDraw.Draw(flame)
    fd.polygon([(32, 12), (40, 32), (38, 42), (26, 42), (24, 32)],
               fill=(217, 122, 42, 230))
    fd.polygon([(32, 19), (37, 33), (35, 41), (29, 41), (27, 33)],
               fill=(232, 163, 61, 240))
    fd.polygon([(32, 27), (35, 35), (32, 40), (29, 35)],
               fill=(245, 217, 122, 255))
    obj.alpha_composite(flame.filter(ImageFilter.GaussianBlur(0.6)))
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))                     # 轻烟
    sd = ImageDraw.Draw(smoke)
    sd.arc([26, 4, 38, 14], 200, 340, fill=(150, 146, 140, 50), width=2)
    sd.arc([30, 0, 40, 9], 220, 20, fill=(150, 146, 140, 35), width=2)
    obj.alpha_composite(smoke.filter(ImageFilter.GaussianBlur(1)))
    d = ImageDraw.Draw(obj)
    for _ in range(4):                                                  # 火星
        x, y = 32 + int(rng.integers(-8, 9)), int(rng.integers(14, 28))
        d.point([(x, y)], fill=(245, 200, 100, 200))
    return obj


# ------------------------------------------------------------------ 装配
GENERATORS = {
    "house": (gen_house, (128, 128)),
    "tavern": (gen_tavern, (192, 144)),
    "zhai_seat": (gen_zhai_seat, (128, 128)),
    "tree_big": (gen_tree_big, (96, 120)),
    "wall_h": (gen_wall_h, (64, 96)),
    "wall_v": (gen_wall_v, (64, 96)),
    "tent": (gen_tent, (96, 96)),
    "campfire_big": (gen_campfire_big, (64, 64)),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for idx, (name, (fn, size)) in enumerate(GENERATORS.items()):
        rng = np.random.default_rng(SEED * 100 + idx)
        img = fn(rng)
        assert img.size == size, f"{name} 尺寸错误: {img.size} != {size}"
        img.save(OUT / f"{name}.png")
        print(f"  {name:<14} {size[0]}x{size[1]}")
    print(f"props -> {OUT}")


if __name__ == "__main__":
    main()
