#!/usr/bin/env python3
"""把 GPT 生成的 2 行×4 列角色精灵表切成游戏帧。
流程：按网格粗切 → 黑底键控（阈值+边缘收边）→ alpha 包围盒裁切 →
统一脚底基线 → 缩放到目标高度 → 输出逐帧 PNG + frames.json。
用法: slice_sheet.py <输入.png> <输出目录> <名字前缀> [目标高度px]
"""
import sys, json, pathlib
from PIL import Image, ImageFilter
import numpy as np

KEY_THRESH = 26      # 黑底键控亮度阈值
FEATHER = 1          # 边缘羽化像素
TARGET_H = 192       # 默认输出帧高

def key_black(cell: np.ndarray) -> np.ndarray:
    rgb = cell[..., :3].astype(np.int16)
    lum = rgb.max(axis=2)
    alpha = np.clip((lum - KEY_THRESH) * 12, 0, 255).astype(np.uint8)
    # 腐蚀一圈去黑边毛刺
    a = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3))
    alpha = np.array(a)
    out = cell.copy()
    out[..., 3] = alpha
    return out

def autocrop(cell: np.ndarray, pad=4):
    a = cell[..., 3]
    ys, xs = np.where(a > 8)
    if len(xs) == 0:
        return None
    x0, x1 = xs.min(), xs.max() + 1
    y0, y1 = ys.min(), ys.max() + 1
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(cell.shape[1], x1 + pad); y1 = min(cell.shape[0], y1 + pad)
    return cell[y0:y1, x0:x1]

def main():
    src, outdir, prefix = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
    th = int(sys.argv[4]) if len(sys.argv) > 4 else TARGET_H
    img = Image.open(src).convert("RGBA")
    W, H = img.size
    cw, ch = W // 4, H // 2
    outdir.mkdir(parents=True, exist_ok=True)
    arr = np.array(img)
    names = ["walk1", "walk2", "walk3", "walk4", "windup", "slash", "hurt", "idle"]
    frames = {}
    max_foot_w = 0
    crops = []
    for i, name in enumerate(names):
        r, c = divmod(i, 4)
        cell = arr[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw].copy()
        cell = key_black(cell)
        crop = autocrop(cell)
        if crop is None:
            print(f"!! {name} 空帧，跳过"); continue
        crops.append((name, crop))
        max_foot_w = max(max_foot_w, crop.shape[1])
    # 统一帧宽（取最宽，居中放置，脚底对齐底部），再整体缩放
    max_h = max(c.shape[0] for _, c in crops)
    for name, crop in crops:
        h, w = crop.shape[:2]
        canvas = np.zeros((max_h, max_foot_w, 4), dtype=np.uint8)
        x = (max_foot_w - w) // 2
        canvas[max_h - h:max_h, x:x + w] = crop
        im = Image.fromarray(canvas)
        scale = th / max_h
        im = im.resize((max(1, round(max_foot_w * scale)), th), Image.LANCZOS)
        im.save(outdir / f"{prefix}_{name}.png")
        frames[name] = {"file": f"{prefix}_{name}.png", "w": im.width, "h": im.height}
        print(f"{name}: {im.width}x{im.height}")
    (outdir / f"{prefix}_frames.json").write_text(
        json.dumps(frames, ensure_ascii=False, indent=1), encoding="utf-8")

if __name__ == "__main__":
    main()
