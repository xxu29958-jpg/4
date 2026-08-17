#!/usr/bin/env python3
"""AI 精灵后处理：裁切包围盒、键控地面色块、缩放到游戏尺寸。"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def process(src: Path, dst: Path, target_h: int = 96) -> None:
    img = Image.open(src).convert("RGBA")
    arr = np.array(img)

    # 1) alpha 包围盒裁切
    alpha = arr[:, :, 3]
    ys, xs = np.where(alpha > 8)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    arr = arr[y0:y1, x0:x1]

    # 2) 键控地面色块：底部 15% 区域内的浅暖灰色（地面投影 blob）
    h, w = arr.shape[:2]
    band = int(h * 0.85)
    r = arr[:, :, 0].astype(int)
    g = arr[:, :, 1].astype(int)
    b = arr[:, :, 2].astype(int)
    beige = (r > 190) & (g > 180) & (b > 165) & (np.abs(r - b) < 45)
    mask = np.zeros((h, w), dtype=bool)
    mask[band:, :] = beige[band:, :]
    arr[mask, 3] = 0

    # 3) 二次裁切（键控后再收一次边）
    alpha = arr[:, :, 3]
    ys, xs = np.where(alpha > 8)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    arr = arr[y0:y1, x0:x1]

    # 4) 缩放到目标高度（LANCZOS 保手绘质感）
    out = Image.fromarray(arr)
    scale = target_h / out.height
    out = out.resize((max(1, int(out.width * scale)), target_h), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)
    print("wrote", dst, out.size)


if __name__ == "__main__":
    process(ROOT.parent / "ref_sgdsd" / "ai_player_front.png",
            ROOT / "assets" / "player" / "hero_front.png", 96)
