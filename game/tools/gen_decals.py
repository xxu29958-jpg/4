# -*- coding: utf-8 -*-
"""地面去程序味：大幅面色斑 overlay + 地面贴花（decal）生成。
输出：
  assets/tiles/ground_variation.png  960×640（游戏内 4x 放大盖全图，明暗/冷暖斑块）
  assets/props/decals/*.png          枯草块/石子堆/断矛/破轮/篱笆段/踩踏痕
全部 seed 固定、可复现。
"""
import numpy as np, pathlib, math, random
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent / "assets"
rng = random.Random(184184)

def vnoise(w, h, cells, seed):
    """值噪声（双线性 smoothstep），cells=晶格数。"""
    r = np.random.default_rng(seed)
    lat = r.random((cells + 1, cells + 1))
    lat[-1, :] = lat[0, :]; lat[:, -1] = lat[:, 0]
    ys = np.linspace(0, cells, h, endpoint=False)
    xs = np.linspace(0, cells, w, endpoint=False)
    yi = ys.astype(int); xi = xs.astype(int)
    yf = ys - yi; xf = xs - xi
    def sm(t): return t * t * (3 - 2 * t)
    wy = sm(yf)[:, None]; wx = sm(xf)[None, :]
    a = lat[yi][:, xi]; b = lat[yi][:, np.minimum(xi + 1, cells)]
    c = lat[np.minimum(yi + 1, cells)][:, xi]; d = lat[np.minimum(yi + 1, cells)][:, np.minimum(xi + 1, cells)]
    return a * (1 - wx) * (1 - wy) + b * wx * (1 - wy) + c * (1 - wx) * wy + d * wx * wy

# ---- 大幅面地面色斑（杀 tile 重复感的核心）----
W, H = 960, 640
n = (vnoise(W, H, 6, 1841) * 0.6 + vnoise(W, H, 14, 1842) * 0.4)
img = np.zeros((H, W, 4), np.uint8)
warm = n > 0.56
cool = n < 0.44
img[warm] = (255, 228, 170, 16)   # 暖金高光斑
img[cool] = (26, 38, 30, 20)      # 青灰暗斑
both = ~(warm | cool)
img[both] = (0, 0, 0, 0)
im = Image.fromarray(img, 'RGBA').filter(ImageFilter.GaussianBlur(3))
(ROOT / 'tiles/ground_variation.png').parent.mkdir(parents=True, exist_ok=True)
im.save(ROOT / 'tiles/ground_variation.png')

# ---- 地面贴花 ----
OUT = ROOT / 'props/decals'
OUT.mkdir(parents=True, exist_ok=True)

def save(im, name):
    im.save(OUT / f'{name}.png')

def dry_grass():
    im = Image.new('RGBA', (48, 32), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    for _ in range(26):
        x, y = rng.uniform(4, 44), rng.uniform(20, 30)
        ln = rng.uniform(6, 15); ang = rng.uniform(-1.2, 1.2) - math.pi / 2
        col = rng.choice([(148, 128, 78, 210), (128, 116, 70, 200), (160, 140, 90, 190)])
        dr.line([(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)], fill=col, width=1)
    return im.filter(ImageFilter.GaussianBlur(0.4))

def pebbles():
    im = Image.new('RGBA', (40, 28), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    for _ in range(9):
        x, y = rng.uniform(6, 34), rng.uniform(8, 22)
        r = rng.uniform(1.6, 3.6)
        tone = rng.randint(108, 148)
        dr.ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=(tone, tone - 6, tone - 16, 220))
        dr.line([(x - r * 0.4, y - r * 0.4), (x, y - r * 0.6)], fill=(tone + 40, tone + 34, tone + 20, 200), width=1)
    return im

def broken_spear():
    im = Image.new('RGBA', (56, 40), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    dr.line([(8, 34), (30, 12)], fill=(96, 74, 44, 255), width=3)      # 断杆
    dr.line([(32, 14), (44, 4)], fill=(96, 74, 44, 255), width=2)      # 前半截斜插
    dr.polygon([(44, 4), (50, 2), (46, 9)], fill=(190, 186, 172, 255))  # 枪头
    dr.line([(28, 14), (34, 20)], fill=(140, 40, 30, 255), width=2)     # 红缨
    return im

def cartwheel():
    im = Image.new('RGBA', (48, 48), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    dr.ellipse([6, 6, 42, 42], outline=(92, 70, 44, 255), width=4)
    for a in range(0, 360, 45):
        r = math.radians(a)
        dr.line([(24, 24), (24 + math.cos(r) * 17, 24 + math.sin(r) * 17)], fill=(92, 70, 44, 255), width=3)
    dr.ellipse([20, 20, 28, 28], fill=(70, 52, 32, 255))
    return im

def fence():
    im = Image.new('RGBA', (72, 32), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    for i in range(5):
        x = 6 + i * 14
        dr.line([(x, 26), (x + rng.uniform(-2, 2), 6)], fill=(110, 86, 54, 255), width=4)
    dr.line([(2, 14), (70, 18)], fill=(96, 74, 46, 255), width=3)
    return im

def trample():
    im = Image.new('RGBA', (64, 48), (0, 0, 0, 0))
    n = vnoise(64, 48, 4, 1843)
    arr = np.zeros((48, 64, 4), np.uint8)
    mask = n > 0.52
    arr[mask] = (96, 82, 54, 46)   # 踩踏露土
    return Image.fromarray(arr, 'RGBA').filter(ImageFilter.GaussianBlur(1.2))

for fn, name in [(dry_grass, 'dry_grass'), (pebbles, 'pebbles'), (broken_spear, 'broken_spear'),
                 (cartwheel, 'cartwheel'), (fence, 'fence'), (trample, 'trample')]:
    save(fn(), name)
print('ground variation + 6 decals ok')
