#!/usr/bin/env python3
"""字体子集化：扫描工程内全部 .gd/.tscn/.txt/.json 文本，
收集用到的 CJK 字符 + ASCII + 常用标点，pyftsubset 就地瘦身 OTF。
用法：subset_font.py  （在 乱世行/ 下用 .venv python 跑）
"""
import re, subprocess, pathlib, sys

GAME = pathlib.Path(__file__).resolve().parent.parent
VENV_PY = GAME.parent / ".venv/Scripts/python.exe"

def collect_chars() -> str:
    chars = set(chr(c) for c in range(0x20, 0x7F))  # ASCII
    chars.update("，。！？；：「」『』、《》—…·【】（）～％▼⚔×")
    for ext in ("*.gd", "*.tscn", "*.cfg", "*.txt", "*.json"):
        for f in GAME.rglob(ext):
            if ".godot" in f.parts:
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            chars.update(re.findall(r"[\u4e00-\u9fff\uff00-\uffef\u3000-\u303f\u25a0-\u26ff\u00d7]", text))
    return "".join(sorted(chars))

def subset(font: pathlib.Path, chars_file: pathlib.Path) -> None:
    out = font.with_suffix(".subset.otf")
    cmd = [str(VENV_PY), "-m", "fontTools.subset", str(font),
           f"--text-file={chars_file}",
           f"--output-file={out}",
           "--layout-features=*", "--no-hinting", "--desubroutinize"]
    subprocess.run(cmd, check=True)
    before = font.stat().st_size
    out.replace(font)
    print(f"{font.name}: {before//1024}KB -> {font.stat().st_size//1024}KB")

def main():
    chars = collect_chars()
    cf = GAME / "assets/fonts/_used_chars.txt"
    cf.write_text(chars, encoding="utf-8")
    print(f"collected {len(chars)} chars")
    for name in ("NotoSansCJKsc-Regular.otf", "NotoSansCJKsc-Bold.otf"):
        subset(GAME / "assets/fonts" / name, cf)
    cf.unlink()

if __name__ == "__main__":
    main()
