#!/usr/bin/env python3
"""合成战鼓循环（战斗音乐层）：大鼓 + 堂鼓 + 碎镲，8s 无缝循环。
输出 game/assets/music/war_drums.wav（44.1kHz 16bit 单声道）。
"""
import numpy as np, wave, pathlib

SR = 44100
LOOP_S = 8.0
N = int(SR * LOOP_S)
t = np.arange(N) / SR
out = np.zeros(N, dtype=np.float64)

def drum(at, freq=62.0, decay=0.28, gain=1.0, click=0.35):
    """大鼓：指数衰减正弦扫频 + 噪声打点。"""
    i0 = int(at * SR)
    n = min(N - i0, int(decay * 4 * SR))
    if n <= 0:
        return
    tt = np.arange(n) / SR
    f = freq * (1.0 + 0.6 * np.exp(-tt * 30.0))  # 起始高扫低，出"咚"的体态
    sig = np.sin(2 * np.pi * f * tt) * np.exp(-tt / decay)
    noise = np.random.default_rng(184).standard_normal(n) * np.exp(-tt / 0.012) * click
    out[i0:i0 + n] += (sig + noise) * gain

def tom(at, freq=110.0, decay=0.16, gain=0.55):
    drum(at, freq=freq, decay=decay, gain=gain, click=0.2)

def hat(at, gain=0.10):
    i0 = int(at * SR)
    n = min(N - i0, int(0.05 * SR))
    if n <= 0:
        return
    tt = np.arange(n) / SR
    noise = np.random.default_rng(int(at * 1000)).standard_normal(n)
    hp = np.diff(noise, prepend=0.0)  # 粗高通
    out[i0:i0 + n] += hp * np.exp(-tt / 0.02) * gain

# 140 BPM 战鼓型：| 咚 - 咚咚 | 咚 - 咚咚 | 堂鼓答句收尾
B = 60.0 / 140.0          # 一拍
bar = B * 4               # 一小节 4 拍 ≈ 1.714s
for b in range(int(LOOP_S / bar)):     # 8s ≈ 4.67 小节，按整循环铺
    t0 = b * bar
    drum(t0, gain=1.0)                 # 正拍大鼓
    tom(t0 + B * 1.5)                  # 附点应答
    tom(t0 + B * 2.0, gain=0.65)
    drum(t0 + B * 2.5, gain=0.8)       # 后半拍大鼓推进
    hat(t0 + B * 0.5); hat(t0 + B * 1.5); hat(t0 + B * 2.5); hat(t0 + B * 3.5)
# 循环尾句加花（最后两拍滚奏）
base = LOOP_S - B * 2
for i in range(6):
    tom(base + i * (B / 3.0), freq=98.0 + i * 6, gain=0.4)

# 低音乐句持续音（战前紧张感）：A1 持续 + 五度 E2 脉动
drone = np.sin(2 * np.pi * 55.0 * t) * 0.10 + np.sin(2 * np.pi * 82.4 * t) * 0.06
pulse = 0.5 + 0.5 * np.sin(2 * np.pi * (1.0 / bar) * t)
out += drone * (0.6 + 0.4 * pulse)

# 防削波 + 16bit 写出
out /= max(1.0, np.abs(out).max() / 0.92)
pcm = (out * 32767).astype(np.int16)
path = pathlib.Path(__file__).resolve().parent.parent / "assets/music/war_drums.wav"
path.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(path), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("war_drums.wav", path.stat().st_size, "bytes")
