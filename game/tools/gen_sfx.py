#!/usr/bin/env python3
"""合成《乱世行》M0 战斗音效：numpy 程序合成，风格统一的低保真短音效。

产出（assets/sfx/，22050Hz 16bit 单声道 WAV）：
  swing.wav  挥砍风声（噪声起音 + 下落滤波）
  hit.wav    命中闷击（低频正弦衰减 + 噪声毛边）
  sweep.wav  横扫重击（更宽更沉的 hit）
  down.wav   倒地（下滑音）
  rout.wav   溃逃喊声（双声部下坠哀嚎，占位）
  rally.wav  冲锋军令（上行号角感）
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sfx"

rng = np.random.default_rng(184)


def save_wav(name: str, samples: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767).astype(np.int16)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", OUT / name)


def envelope(n: int, attack: float, decay_curve=np.exp) -> np.ndarray:
    t = np.linspace(0, 1, n)
    env = np.minimum(t / max(attack, 1e-4), 1.0) * decay_curve(-4.0 * t)
    return env


def lowpass(x: np.ndarray, k: int) -> np.ndarray:
    kernel = np.ones(k) / k
    return np.convolve(x, kernel, mode="same")


def swing() -> None:
    n = int(SR * 0.15)
    noise = rng.standard_normal(n)
    x = lowpass(noise, 24) * envelope(n, 0.15) * 0.9
    save_wav("swing.wav", x)


def hit() -> None:
    n = int(SR * 0.12)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * 95 * t) * np.exp(-30 * t)
    edge = lowpass(rng.standard_normal(n), 8) * np.exp(-40 * t) * 0.5
    save_wav("hit.wav", (thud + edge) * 0.95)


def sweep() -> None:
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 70 * t) * np.exp(-18 * t)
    whoosh = lowpass(rng.standard_normal(n), 32) * envelope(n, 0.1) * 0.7
    save_wav("sweep.wav", (body + whoosh) * 0.95)


def down() -> None:
    n = int(SR * 0.25)
    t = np.arange(n) / SR
    f = 300 - 180 * (t / 0.25)
    phase = np.cumsum(2 * np.pi * f / SR)
    x = np.sin(phase) * np.exp(-12 * t) * 0.8
    save_wav("down.wav", x)


def rout() -> None:
    n = int(SR * 0.55)
    t = np.arange(n) / SR
    f1 = 380 - 160 * (t / 0.55)
    f2 = 305 - 130 * (t / 0.55)
    x = (np.sin(np.cumsum(2 * np.pi * f1 / SR))
         + 0.8 * np.sin(np.cumsum(2 * np.pi * f2 / SR)))
    x = x * envelope(n, 0.05) * 0.45
    save_wav("rout.wav", x)


def rally() -> None:
    n = int(SR * 0.32)
    t = np.arange(n) / SR
    f = 200 + 200 * (t / 0.32)
    phase = np.cumsum(2 * np.pi * f / SR)
    horn = np.sin(phase) + 0.4 * np.sin(2 * phase)
    x = horn * envelope(n, 0.2) * 0.55
    save_wav("rally.wav", x)


def pickup() -> None:
    """拾取宝物：两音上行清响。"""
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    half = n // 2
    x = np.zeros(n)
    x[:half] = np.sin(2 * np.pi * 520 * t[:half]) * np.exp(-6 * t[:half])
    x[half:] = np.sin(2 * np.pi * 780 * t[half:]) * np.exp(-6 * (t[half:] - t[half]))
    save_wav("pickup.wav", x * 0.6)


if __name__ == "__main__":
    swing()
    hit()
    sweep()
    down()
    rout()
    rally()
    pickup()
    print("done")
