#!/usr/bin/env python3
"""生成颍川郡西北野手工地图：60×40 字符蓝图 + 关键点位 JSON。
确定性（seed 184）。输出：
  game/data/map_layout.txt   60 列 × 40 行
  game/data/map_points.json  关键世界坐标（像素，格心）
图例见输出文件头注释。
"""
import json, random, pathlib

W, H = 60, 40
TILE = 64
ROOT = pathlib.Path(__file__).resolve().parent.parent / "data"
rng = random.Random(184)

g = [["g"] * W for _ in range(H)]

def rect(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = ch

def ring(x0, y0, x1, y1, ch):
    for x in range(x0, x1 + 1):
        g[y0][x] = ch; g[y1][x] = ch
    for y in range(y0, y1 + 1):
        g[y][x0] = ch; g[y][x1] = ch

def put(x, y, ch):
    g[y][x] = ch

# ---- 边界密林（2 格厚）----
rect(0, 0, W - 1, 1, "T"); rect(0, H - 2, W - 1, H - 1, "T")
rect(0, 0, 1, H - 1, "T"); rect(W - 2, 0, W - 1, H - 1, "T")

# ---- 西北松林带（含 25% 草隙，可穿行边缘）----
rect(2, 2, 26, 18, "t")
for y in range(2, 19):
    for x in range(2, 27):
        if rng.random() < 0.28:
            g[y][x] = "g"

# ---- 山寨（北中高地，栅栏环 + 南门 + 寨旗主座 2×2 锚点 Z 在 (31,4)）----
ring(28, 3, 35, 9, "F")
rect(29, 4, 34, 8, "g")
put(31, 4, "Z")                    # zhai_seat 道具锚点（占 31-32 列 × 4-5 行）
put(31, 9, "g"); put(32, 9, "g")   # 南门开口
# 寨内点缀：帐篷（v=帐篷锚点 1 格，道具 96×96 约 1.5 格）
put(29, 7, "v"); put(34, 4, "v")

# ---- 废营地（林中空地 + 篝火 + 宝物）----
rect(6, 5, 9, 8, "g")
put(6, 5, "r"); put(7, 5, "r"); put(6, 6, "r")
put(9, 7, "c")                     # 篝火道具锚点
put(8, 6, "x")

# ---- 林间小路：官道岔口(30,24) 向北到寨南门(31,10) ----
for y in range(10, 24):
    put(30, y, "d"); put(31, y, "d")

# ---- 废营地（林中空地 + 宝物）----
rect(6, 5, 9, 8, "g")
put(6, 5, "r"); put(7, 5, "r"); put(6, 6, "r")
put(8, 6, "x")

# ---- 阳翟（西南，城墙 5,21-15,28，东门 E 在 (15,24)）----
ring(5, 21, 15, 28, "W")
rect(6, 22, 14, 27, "p")
put(15, 24, "E")
# 城内建筑（道具化：h=2×2 民居锚点在其左上格，H=3×2 酒肆锚点在其左上格，
# 占据的其余格保持 p 街面，装配器按锚点摆大图 + 加碰撞）：
# 北排面街：民居(6,22)、酒肆(9,22) 占 9-11 列、民居(13,22)
put(6, 22, "h")
put(9, 22, "H")
put(13, 22, "h")
# 南排：民居(7,26)、(11,26)
put(7, 26, "h")
put(11, 26, "h")

# ---- 官道：城门(16,24) → 东界，两段微弯 ----
for x in range(16, 41):
    put(x, 24, "d")
put(41, 24, "d"); put(41, 25, "d"); put(42, 25, "d"); put(42, 26, "d")
for x in range(43, 58):
    put(x, 26, "d")

# ---- 村庄（官道南）+ 农田（2×2 民居锚点）----
put(23, 29, "h")
put(26, 30, "h")
rect(20, 33, 24, 35, "f")

# ---- 东南河湾（椭圆水面 + 沙滩）----
cx, cy, rx, ry = 50, 32, 6, 4
for y in range(H):
    for x in range(W):
        d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
        if d <= 1.0:
            g[y][x] = "w"
        elif d <= 1.45 and g[y][x] == "g":
            g[y][x] = "s"

# ---- 散树与重装饰草（避开道路/城/村/水面 1 格）----
def near(x, y, chars, r=1):
    for yy in range(max(0, y - r), min(H, y + r + 1)):
        for xx in range(max(0, x - r), min(W, x + r + 1)):
            if g[yy][xx] in chars:
                return True
    return False

avoid = set("dWpEhHfF Zrxws".replace(" ", ""))
placed_t = placed_G = 0
for _ in range(4000):
    x, y = rng.randrange(2, W - 2), rng.randrange(2, H - 2)
    if g[y][x] != "g" or near(x, y, avoid):
        continue
    if placed_t < 46 and rng.random() < 0.55:
        g[y][x] = "t"; placed_t += 1
    elif placed_G < 90:
        g[y][x] = "G"; placed_G += 1

# ---- 校验 ----
assert len(g) == H and all(len(row) == W for row in g), "地图尺寸错误"
# 官道连通性粗检：E 右边必须是 d
assert g[24][15] == "E" and g[24][16] == "d"

LEGEND = """# 颍川郡西北野 · 手工地图蓝图（60x40，每格 64px）
# g 草 G 重装饰草 d 官道 p 石板街 s 沙滩 w 水 t 松 T 边界密林
# W 城墙 E 城门 h/H 民居/酒肆锚点 f 农田 F 寨栅 Z 寨主座锚点 r 废墟 v 帐篷 c 篝火 x 宝物点
"""
(ROOT / "map_layout.txt").write_text(
    LEGEND + "\n".join("".join(row) for row in g) + "\n", encoding="utf-8")

def px(x, y):
    return [x * TILE + TILE // 2, y * TILE + TILE // 2]

points = {
    "tile": TILE, "width": W, "height": H,
    "player_spawn": px(10, 24),
    "tavern_door": px(11, 23),
    "rumor_drinker": px(12, 24),
    "city_gate": px(15, 24),
    "villager_crossroad": px(29, 22),
    "bandit_block": px(36, 24),
    "caravan_waypoints": [px(20, 24), px(40, 24), px(41, 25), px(42, 26), px(50, 26)],
    "treasure_ruins": px(8, 6),
    "zhai_gate": px(31, 10),
    "zhai_chief": px(31, 6),
    "village_elder": px(25, 30),
    "river_view": px(47, 31),
}
(ROOT / "map_points.json").write_text(
    json.dumps(points, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"map ok: {W}x{H}, trees={placed_t}, deco={placed_G}")
print("points:", ", ".join(points.keys()))
