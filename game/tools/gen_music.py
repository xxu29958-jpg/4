#!/usr/bin/env python3
"""合成《乱世行》M0 环境音乐：五声音阶乡野氛围，无缝循环。

结构（48s，44100Hz 16bit 单声道）：
  - 低音 drone：C2/G2 正弦垫底 + 慢呼吸 LFO
  - 拨弦旋律：宫商角徵羽随机漫步，类古筝泛音衰减
  - 风声底噪：低电平滤波噪声慢起伏
产出 assets/music/ambience.wav
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

SR = 44100
DUR = 48.0
OUT = Path(__file__).resolve().parent.parent / "assets" / "music"

# 五声音阶（宫 C 调）：C3 D3 E3 G3 A3 C4 D4 E4
PENTA = [130.81, 146.83, 164.81, 196.00, 220.00, 261.63, 293.66, 329.63]

rng = np.random.default_rng(184)


def pluck(freq: float, dur: float) -> np.ndarray:
    """类古筝拨弦：前三个泛音指数衰减。"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * freq * t) * np.exp(-3.2 * t)
            + 0.45 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-5.0 * t)
            + 0.2 * np.sin(2 * np.pi * freq * 3 * t) * np.exp(-7.0 * t))
    # 拨弦起音
    tone *= np.minimum(t / 0.005, 1.0)
    return tone


def main() -> None:
    n = int(SR * DUR)
    t = np.arange(n) / SR
    mix = np.zeros(n)

    # drone：C2 + G2，40s 周期慢呼吸
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * t / 40.0)
    mix += 0.10 * lfo * np.sin(2 * np.pi * 65.41 * t)
    mix += 0.06 * lfo * np.sin(2 * np.pi * 98.00 * t)

    # 风声：低通噪声 + 17s 周期起伏
    noise = rng.standard_normal(n)
    kernel = np.ones(400) / 400
    wind = np.convolve(noise, kernel, mode="same")
    wind *= 0.05 * (0.6 + 0.4 * np.sin(2 * np.pi * t / 17.0 + 1.0))
    mix += wind

    # 拨弦旋律：随机漫步，音与音之间留呼吸
    pos = 0.5
    idx = 3  # 从 G3 起
    while pos < DUR - 2.0:
        step = rng.choice([-2, -1, -1, 1, 1, 2, 0])
        idx = int(np.clip(idx + step, 0, len(PENTA) - 1))
        note = pluck(PENTA[idx], 2.2) * rng.uniform(0.10, 0.16)
        start = int(pos * SR)
        end = min(start + note.size, n)
        mix[start:end] += note[:end - start]
        pos += rng.uniform(0.7, 1.6)

    # 首尾 2s 淡入淡出，循环接缝处安静 → 无缝
    fade = int(2.0 * SR)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)

    mix /= max(1.0, np.abs(mix).max() / 0.5)
    pcm = (np.clip(mix, -1, 1) * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / "ambience.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", OUT / "ambience.wav", f"{pcm.size * 2 / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
