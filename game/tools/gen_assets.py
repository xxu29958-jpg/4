#!/usr/bin/env python3
"""生成《乱世行》M0 素材 v2：低饱和像素风 + 光影细节 + 正确比例。

角色 48px（地块 64px 的 3/4，比例合理），3 帧：0=站立 1=行走 2=攻击。
人物 sprite sheet 144x48；主将 4 朝向 x 3 帧 = 576x48。
地块图集 640x64：0=草地 1=土路 2=树 3=水 4=沙滩 5=房屋 6=栅栏 7=废墟 8=花草地。
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

random.seed(184)  # 黄巾起义年，固定种子保证可复现

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

# ---------------------------------------------------------------- 色板
# v3：对照三国大时代4 实机截图调高饱和度与明度——鲜绿草地 + 金秋树冠。
PAL = {
    "grass_base": (116, 152, 66),
    "grass_dark": (96, 130, 54),
    "grass_light": (138, 172, 82),
    "dirt_base": (176, 146, 100),
    "dirt_dark": (150, 122, 80),
    "dirt_light": (194, 164, 118),
    "trunk": (104, 74, 48),
    "trunk_dark": (82, 56, 36),
    "canopy_dark": (150, 114, 44),
    "canopy_mid": (196, 158, 64),
    "canopy_light": (230, 194, 96),
    "water_base": (78, 128, 148),
    "water_dark": (60, 106, 126),
    "water_light": (110, 164, 182),
    "sand_base": (202, 178, 126),
    "sand_dark": (180, 156, 106),
    "sand_light": (218, 196, 146),
    "roof": (150, 70, 50),
    "roof_dark": (122, 54, 40),
    "roof_light": (176, 88, 64),
    "wall": (160, 122, 80),
    "wall_dark": (128, 96, 62),
    "door": (56, 42, 32),
    "pal_log": (118, 86, 54),
    "pal_dark": (92, 66, 40),
    "ruin_wood": (82, 66, 50),
    "skin": (238, 198, 156),
    "skin_dark": (210, 168, 128),
    "hair": (44, 38, 34),
    "blade": (216, 222, 228),
    "blade_dark": (168, 176, 184),
    "ui_ring": (30, 32, 36),
    "ui_rim": (236, 230, 214),
    "marker": (232, 192, 80),
    "spark": (255, 214, 80),
}

# 袍色
ROBE_PLAYER = (70, 96, 150)       # 青蓝（亮）
ROBE_BANDIT = (150, 96, 50)       # 橙褐
ROBE_VILLAGER = (120, 126, 106)   # 灰绿
ROBE_MERCHANT = (82, 110, 160)    # 青蓝
ROBE_HAN = (96, 118, 88)          # 汉军灰绿甲
HEADBAND_PLAYER = (196, 60, 44)   # 绛红
HEADBAND_BANDIT = (238, 200, 60)  # 黄巾
HEADBAND_HAN = (170, 170, 160)    # 灰束带


def _shade(c, d: int):
    return (max(0, c[0] - d), max(0, c[1] - d), max(0, c[2] - d))


def _light(c, d: int):
    return (min(255, c[0] + d), min(255, c[1] + d), min(255, c[2] + d))


def speckle(img, colors, density, rect=None):
    px = img.load()
    w, h = img.size
    x0, y0, x1, y1 = rect or (0, 0, w, h)
    for y in range(y0, y1):
        for x in range(x0, x1):
            if random.random() < density:
                px[x, y] = random.choice(colors)


def soft_patch(img, colors, count, rmin=8, rmax=18, alpha=26):
    """大面积柔和色斑：多层低透明椭圆叠加出光影体积感。"""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for _ in range(count):
        x, y = random.randint(0, img.width), random.randint(0, img.height)
        r = random.randint(rmin, rmax)
        c = random.choice(colors)
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (alpha,))
    overlay = overlay.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(overlay)


# ---------------------------------------------------------------- 地块
def tile_grass(flowers=False) -> Image.Image:
    img = Image.new("RGBA", (64, 64), PAL["grass_base"] + (255,))
    soft_patch(img, [PAL["grass_dark"], PAL["grass_light"]], 5)
    d = ImageDraw.Draw(img)
    speckle(img, [PAL["grass_dark"] + (255,), PAL["grass_light"] + (255,)], 0.12)
    for _ in range(8):  # 草叶簇
        x, y = random.randint(4, 58), random.randint(6, 60)
        d.line([(x, y), (x - 1, y - 4)], fill=PAL["grass_light"] + (255,))
        d.line([(x, y), (x + 1, y - 3)], fill=PAL["grass_dark"] + (255,))
        d.line([(x, y), (x, y - 4)], fill=PAL["grass_base"] + (255,))
    if flowers:
        for _ in range(4):
            x, y = random.randint(6, 56), random.randint(6, 56)
            c = random.choice([(226, 200, 120), (232, 228, 214), (200, 130, 110)])
            d.ellipse([x, y, x + 2, y + 2], fill=c + (255,))
    return img


def tile_dirt() -> Image.Image:
    img = Image.new("RGBA", (64, 64), PAL["dirt_base"] + (255,))
    soft_patch(img, [PAL["dirt_dark"], PAL["dirt_light"]], 4)
    d = ImageDraw.Draw(img)
    speckle(img, [PAL["dirt_dark"] + (255,), PAL["dirt_light"] + (255,)], 0.16)
    # 车辙：两条横向凹痕
    for ry in (18, 44):
        for x in range(0, 64, 4):
            wobble = random.randint(-1, 1)
            d.line([(x, ry + wobble), (x + 3, ry + wobble)],
                   fill=PAL["dirt_dark"] + (255,))
    return img


def tile_tree() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 投影
    d.ellipse([16, 50, 50, 60], fill=(0, 0, 0, 50))
    # 树干（亮左暗右）
    d.rectangle([28, 34, 36, 56], fill=PAL["trunk"] + (255,))
    d.rectangle([33, 34, 36, 56], fill=PAL["trunk_dark"] + (255,))
    # 树冠三层 + 描边
    for cx, cy, r, c in [(32, 24, 21, PAL["canopy_mid"]),
                         (20, 32, 13, PAL["canopy_dark"]),
                         (44, 32, 13, PAL["canopy_dark"])]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c + (255,))
    d.ellipse([18, 6, 40, 28], fill=PAL["canopy_light"] + (255,))  # 顶部受光
    for cx, cy, r in [(32, 24, 21), (20, 32, 13), (44, 32, 13)]:
        d.arc([cx - r, cy - r, cx + r, cy + r], 100, 260,
              fill=PAL["canopy_dark"] + (255,), width=2)
    # 高光点
    for _ in range(6):
        x, y = random.randint(18, 38), random.randint(8, 26)
        d.point([(x, y)], fill=_light(PAL["canopy_light"], 24) + (255,))
    return img


def tile_water() -> Image.Image:
    img = Image.new("RGBA", (64, 64), PAL["water_base"] + (255,))
    soft_patch(img, [PAL["water_dark"], PAL["water_light"]], 4, 10, 22, 30)
    d = ImageDraw.Draw(img)
    for y in (10, 26, 42, 56):
        for x in range(0, 64, 14):
            off = (y * 3) % 9
            d.line([(x + off, y), (x + off + 7, y)],
                   fill=PAL["water_light"] + (255,), width=2)
            d.line([(x + off + 2, y + 3), (x + off + 6, y + 3)],
                   fill=PAL["water_dark"] + (255,))
    return img


def tile_sand() -> Image.Image:
    img = Image.new("RGBA", (64, 64), PAL["sand_base"] + (255,))
    soft_patch(img, [PAL["sand_dark"], PAL["sand_light"]], 4)
    speckle(img, [PAL["sand_dark"] + (255,), PAL["sand_light"] + (255,)], 0.14)
    return img


def tile_house() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([8, 48, 60, 62], fill=(0, 0, 0, 55))  # 投影
    d.rectangle([8, 6, 58, 48], fill=PAL["roof"] + (255,))
    d.rectangle([8, 6, 58, 12], fill=PAL["roof_light"] + (255,))  # 屋脊受光
    for x in range(12, 58, 7):
        d.line([(x, 12), (x, 48)], fill=PAL["roof_dark"] + (255,))
    d.rectangle([10, 48, 56, 58], fill=PAL["wall"] + (255,))
    d.rectangle([48, 48, 56, 58], fill=PAL["wall_dark"] + (255,))  # 右墙阴影
    d.rectangle([28, 48, 38, 58], fill=PAL["door"] + (255,))
    d.rectangle([14, 50, 20, 55], fill=(240, 220, 150, 255))  # 窗（暖光）
    return img


def tile_palisade() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 52, 62, 62], fill=(0, 0, 0, 45))
    for x in range(2, 64, 10):
        d.rectangle([x, 16, x + 7, 56], fill=PAL["pal_log"] + (255,))
        d.polygon([(x, 16), (x + 3, 6), (x + 7, 16)], fill=_light(PAL["pal_log"], 14) + (255,))
        d.line([(x + 6, 18), (x + 6, 56)], fill=PAL["pal_dark"] + (255,))
    d.rectangle([0, 30, 63, 35], fill=PAL["pal_dark"] + (255,))
    d.rectangle([0, 42, 63, 46], fill=_shade(PAL["pal_dark"], 10) + (255,))
    return img


def tile_ruins() -> Image.Image:
    img = Image.new("RGBA", (64, 64), PAL["dirt_dark"] + (255,))
    soft_patch(img, [PAL["dirt_base"]], 3)
    d = ImageDraw.Draw(img)
    speckle(img, [PAL["dirt_base"] + (255,)], 0.1)
    for x1, y1, x2, y2 in [(10, 14, 30, 20), (36, 30, 54, 26), (18, 44, 34, 50)]:
        d.line([(x1, y1), (x2, y2)], fill=PAL["ruin_wood"] + (255,), width=5)
        d.line([(x1, y1 - 1), (x2, y2 - 1)], fill=_light(PAL["ruin_wood"], 18) + (255,), width=1)
    for _ in range(8):
        x, y = random.randint(6, 56), random.randint(6, 56)
        d.ellipse([x, y, x + 3, y + 3], fill=(94, 92, 88, 255))
    return img


def make_tileset() -> None:
    tiles = [tile_grass(), tile_dirt(), tile_tree(), tile_water(),
             tile_sand(), tile_house(), tile_palisade(), tile_ruins(),
             tile_grass(flowers=True)]
    img = Image.new("RGBA", (64 * len(tiles), 64), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        img.paste(t, (i * 64, 0))
    out = ASSETS / "tiles" / "tileset.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out)


# ---------------------------------------------------------------- 角色（48px，Q 版大头）
def draw_character(dr: ImageDraw.ImageDraw, robe, headband, step: int,
                   attack: bool, facing: str, armed: bool) -> None:
    """48x48 一帧：0 站立 / 1 行走 / 2 攻击（持刀横挥）。
    Q 版比例：头约占全身 40%（三国大时代式高可读性）。"""
    robe_d = _shade(robe, 18)
    robe_l = _light(robe, 14)
    bob = 1 if step else 0
    # 脚下投影
    dr.ellipse([10, 41 - bob, 38, 47 - bob], fill=(0, 0, 0, 55))
    # 腿
    leg = 2 if step else 0
    dr.rectangle([18, 34 + bob, 22, 42], fill=robe_d + (255,))
    dr.rectangle([26, 34 + bob, 30, 42], fill=robe_d + (255,))
    dr.rectangle([17 - leg, 42, 23 - leg, 45], fill=PAL["hair"] + (255,))
    dr.rectangle([25 + leg, 42, 31 + leg, 45], fill=PAL["hair"] + (255,))
    # 袍身（左受光右阴影）
    dr.rectangle([16, 21 + bob, 33, 35 + bob], fill=robe + (255,))
    dr.rectangle([16, 21 + bob, 18, 35 + bob], fill=robe_l + (255,))
    dr.rectangle([31, 21 + bob, 33, 35 + bob], fill=robe_d + (255,))
    dr.rectangle([16, 31 + bob, 33, 34 + bob], fill=_shade(robe, 34) + (255,))  # 腰带
    # 手臂
    if attack and armed:
        dr.rectangle([12, 22 + bob, 15, 32 + bob], fill=robe + (255,))
        # 右臂前伸 + 刀横挥（拖尾）
        dr.rectangle([33, 23 + bob, 43, 27 + bob], fill=robe + (255,))
        dr.rectangle([43, 24 + bob, 46, 26 + bob], fill=PAL["skin"] + (255,))
        dr.rectangle([45, 14 + bob, 48, 36 + bob], fill=PAL["blade"] + (255,))
        dr.rectangle([47, 14 + bob, 48, 36 + bob], fill=PAL["blade_dark"] + (255,))
        dr.rectangle([43, 27 + bob, 49, 29 + bob], fill=PAL["trunk_dark"] + (255,))
    else:
        dr.rectangle([12, 22 + bob, 15, 32 + bob], fill=robe + (255,))
        dr.rectangle([34, 22 + bob, 37, 32 + bob], fill=robe_d + (255,))
        if armed:  # 刀垂持
            dr.rectangle([35, 30 + bob, 38, 41 + bob], fill=PAL["blade"] + (255,))
            dr.rectangle([37, 30 + bob, 38, 41 + bob], fill=PAL["blade_dark"] + (255,))
            dr.rectangle([34, 28 + bob, 39, 31 + bob], fill=PAL["trunk_dark"] + (255,))
    # 大头
    dr.rectangle([14, 2 + bob, 34, 20 + bob], fill=PAL["skin"] + (255,))
    dr.rectangle([31, 2 + bob, 34, 20 + bob], fill=PAL["skin_dark"] + (255,))
    dr.rectangle([14, 2 + bob, 34, 7 + bob], fill=PAL["hair"] + (255,))
    dr.rectangle([14, 7 + bob, 16, 14 + bob], fill=PAL["hair"] + (255,))  # 鬓角
    if headband is not None:
        dr.rectangle([14, 8 + bob, 34, 10 + bob], fill=headband + (255,))
    if facing == "up":
        dr.rectangle([14, 2 + bob, 34, 20 + bob], fill=PAL["hair"] + (255,))
        if headband is not None:
            dr.rectangle([14, 12 + bob, 34, 14 + bob], fill=headband + (255,))
    elif facing == "down":
        dr.rectangle([19, 14 + bob, 21, 16 + bob], fill=PAL["hair"] + (255,))
        dr.rectangle([27, 14 + bob, 29, 16 + bob], fill=PAL["hair"] + (255,))
        dr.rectangle([21, 18 + bob, 27, 19 + bob], fill=PAL["skin_dark"] + (255,))
    else:
        eye_x0 = 27 if facing == "right" else 19
        dr.rectangle([eye_x0, 14 + bob, eye_x0 + 2, 16 + bob], fill=PAL["hair"] + (255,))


def make_person(path: Path, robe, headband, armed=True, wave=False) -> None:
    """144x48：0 站立 / 1 行走（或摆手）/ 2 攻击。"""
    img = Image.new("RGBA", (144, 48), (0, 0, 0, 0))
    for i, (step, attack) in enumerate([(0, False), (1, False), (0, True)]):
        frame = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
        dr = ImageDraw.Draw(frame)
        draw_character(dr, robe, headband, step, attack and armed, "down", armed)
        if wave and i == 1:  # 村民摆手帧：抬右臂
            dr.rectangle([33, 10, 36, 20], fill=robe + (255,))
            dr.point([(34, 9)], fill=PAL["skin"] + (255,))
        img.paste(frame, (i * 48, 0))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path)


def make_player() -> None:
    """576x48：4 朝向（down/up/left/right）x 3 帧。"""
    img = Image.new("RGBA", (576, 48), (0, 0, 0, 0))
    for d, facing in enumerate(["down", "up", "left", "right"]):
        for f, (step, attack) in enumerate([(0, False), (1, False), (0, True)]):
            frame = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
            dr = ImageDraw.Draw(frame)
            draw_character(dr, ROBE_PLAYER, HEADBAND_PLAYER, step, attack,
                           facing, armed=True)
            img.paste(frame, ((d * 3 + f) * 48, 0))
    out = ASSETS / "player" / "player.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out)


# ---------------------------------------------------------------- 货车
def make_cart() -> None:
    img = Image.new("RGBA", (72, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([10, 36, 62, 46], fill=(0, 0, 0, 50))
    d.ellipse([10, 30, 26, 44], fill=PAL["trunk"] + (255,))
    d.ellipse([46, 30, 62, 44], fill=PAL["trunk"] + (255,))
    d.ellipse([15, 35, 21, 41], fill=(40, 32, 26, 255))
    d.ellipse([51, 35, 57, 41], fill=(40, 32, 26, 255))
    d.rectangle([6, 24, 66, 32], fill=PAL["pal_log"] + (255,))
    d.rectangle([6, 24, 66, 26], fill=_light(PAL["pal_log"], 16) + (255,))
    d.rectangle([16, 8, 56, 26], fill=(196, 178, 140, 255))
    d.rectangle([16, 8, 56, 12], fill=(216, 198, 160, 255))
    d.line([(16, 26), (56, 26)], fill=(150, 134, 102, 255))
    out = ASSETS / "npc" / "cart.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out)


# ---------------------------------------------------------------- 旗帜/闪光/气泡/招牌/UI
def make_banners() -> None:
    for name, color in [("banner_han", (176, 56, 42)), ("banner_yellow", (222, 186, 62))]:
        img = Image.new("RGBA", (20, 34), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rectangle([3, 0, 5, 33], fill=PAL["trunk"] + (255,))
        d.polygon([(6, 2), (19, 7), (6, 13)], fill=color + (255,))
        d.polygon([(6, 2), (12, 4), (6, 6)], fill=_light(color, 30) + (255,))
        out = ASSETS / "npc" / f"{name}.png"
        img.save(out)
        print("wrote", out)


def make_sparkle() -> None:
    img = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = PAL["marker"] + (255,)
    d.polygon([(10, 0), (12, 8), (20, 10), (12, 12), (10, 20), (8, 12), (0, 10), (8, 8)], fill=c)
    d.polygon([(10, 4), (11, 9), (16, 10), (11, 11), (10, 16), (9, 11), (4, 10), (9, 9)],
              fill=(250, 235, 180, 255))
    out = ASSETS / "ui" / "sparkle.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out)


def make_bubbles() -> None:
    for name, mark in [("bubble_alert", "!"), ("bubble_talk", "...")]:
        img = Image.new("RGBA", (36, 26), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([1, 1, 34, 18], radius=6,
                            fill=(244, 238, 222, 248), outline=(58, 52, 42, 255), width=2)
        d.polygon([(13, 18), (21, 18), (14, 25)], fill=(244, 238, 222, 248))
        if mark == "!":
            d.rectangle([16, 5, 19, 12], fill=(168, 56, 42, 255))
            d.rectangle([16, 13, 19, 16], fill=(168, 56, 42, 255))
        else:
            for i in range(3):
                d.ellipse([9 + i * 7, 8, 13 + i * 7, 12], fill=(92, 86, 72, 255))
        out = ASSETS / "ui" / f"{name}.png"
        img.save(out)
        print("wrote", out)


def make_sign() -> None:
    img = Image.new("RGBA", (20, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line([(10, 0), (10, 5)], fill=PAL["trunk"] + (255,))
    d.rectangle([3, 5, 17, 17], fill=(160, 118, 74, 255), outline=PAL["pal_dark"] + (255,))
    d.rectangle([7, 9, 13, 14], fill=(244, 238, 222, 255))
    d.rectangle([8, 7, 12, 9], fill=(244, 238, 222, 255))
    out = ASSETS / "tiles" / "sign.png"
    img.save(out)
    print("wrote", out)


def make_joystick() -> None:
    ui = ASSETS / "ui"
    ui.mkdir(parents=True, exist_ok=True)
    base = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    b = ImageDraw.Draw(base)
    b.ellipse([4, 4, 92, 92], fill=PAL["ui_ring"] + (110,),
              outline=PAL["ui_rim"] + (160,), width=3)
    base.save(ui / "joy_base.png")
    knob = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    k = ImageDraw.Draw(knob)
    k.ellipse([2, 2, 46, 46], fill=PAL["ui_rim"] + (200,),
              outline=PAL["ui_ring"] + (220,), width=2)
    knob.save(ui / "joy_knob.png")
    print("wrote joystick")


def make_tap_marker() -> None:
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = PAL["marker"] + (230,)
    d.ellipse([6, 10, 26, 26], outline=c, width=2)
    d.ellipse([13, 17, 19, 23], fill=c)
    out = ASSETS / "ui" / "tap_marker.png"
    img.save(out)
    print("wrote", out)


# ---------------------------------------------------------------- 命中星爆（三国大时代式）
def make_spark() -> None:
    """32x32 黄橙星爆：命中瞬间的视觉锤。"""
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for angle_deg in range(0, 360, 45):
        a = angle_deg * 3.14159265 / 180
        import math
        x2 = 16 + 14 * math.cos(a)
        y2 = 16 + 14 * math.sin(a)
        d.line([(16, 16), (x2, y2)], fill=(255, 176, 48, 255), width=3)
    d.ellipse([10, 10, 22, 22], fill=PAL["spark"] + (255,))
    d.ellipse([13, 13, 19, 19], fill=(255, 246, 200, 255))
    out = ASSETS / "ui" / "spark.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out)


# ---------------------------------------------------------------- 圆形半透明战斗按钮
def make_round_buttons() -> None:
    """64x64 半透明圆钮 + 图标：剑=横扫，旗=冲锋，盾=稳守。三国大时代式虚拟按键。"""
    for name, icon in [("btn_sweep", "sword"), ("btn_charge", "flag"),
                       ("btn_hold", "shield")]:
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.ellipse([2, 2, 62, 62], fill=(240, 236, 220, 70),
                  outline=(240, 236, 220, 170), width=3)
        if icon == "sword":
            d.line([(20, 46), (44, 22)], fill=(240, 240, 244, 230), width=5)
            d.line([(42, 24), (46, 20)], fill=(168, 176, 184, 230), width=3)
            d.line([(18, 40), (26, 48)], fill=(120, 88, 54, 255), width=4)
            d.line([(17, 45), (25, 37)], fill=(200, 168, 90, 255), width=3)
        elif icon == "flag":
            d.rectangle([22, 14, 26, 50], fill=(104, 74, 48, 255))
            d.polygon([(26, 16), (50, 24), (26, 34)], fill=(196, 60, 44, 255))
            d.polygon([(26, 16), (38, 20), (26, 24)], fill=(226, 96, 72, 255))
        else:  # shield：铁镶边圆盾
            d.ellipse([18, 16, 46, 50], fill=(96, 108, 118, 255),
                      outline=(200, 168, 90, 255), width=3)
            d.ellipse([24, 23, 40, 43], fill=(126, 140, 150, 255))
            d.ellipse([29, 29, 35, 37], fill=(200, 168, 90, 255))
        out = ASSETS / "ui" / f"{name}.png"
        img.save(out)
        print("wrote", out)


if __name__ == "__main__":
    make_tileset()
    make_player()
    make_person(ASSETS / "npc" / "bandit.png", ROBE_BANDIT, HEADBAND_BANDIT)
    make_person(ASSETS / "npc" / "villager.png", ROBE_VILLAGER, None,
                armed=False, wave=True)
    make_person(ASSETS / "npc" / "merchant.png", ROBE_MERCHANT, None, armed=False)
    make_person(ASSETS / "npc" / "soldier_han.png", ROBE_HAN, HEADBAND_HAN)
    make_cart()
    make_sparkle()
    make_banners()
    make_bubbles()
    make_sign()
    make_spark()
    make_round_buttons()
    make_joystick()
    make_tap_marker()
    print("done")
