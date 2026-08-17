# 乱世行：一郡风云 — 项目总目录

> 一切都在这个文件夹里，别去别处找。

## 目录地图

| 路径 | 是什么 | 怎么用 |
|---|---|---|
| `乱世行-m0.apk` | **当前游戏安装包** | 传手机安装即玩（已 debug 签名） |
| `乱世行-设计-v1.md` | **当前施工合同**（美术/世界/战斗/剧情/UI 定案） | 改设计先改它 |
| `乱世行-架构假设.md` | 历史背景文档（第一原则仍有效，方案层已被 v1 取代） | 参考 |
| `game/` | **Godot 4.4 工程源码** | 见下 |
| `ref-三国大时代4/` | 原版逆向参考材料 | 素材红线：只研究不搬用 |
| `godot/` | Godot 4.4 引擎（免安装） | 命令行构建用 |
| `assets_ai/` | GPT 生成的角色精灵表原图（1774×887） | 切片管线的输入 |
| `测试截图/` | 历次验证截图（真机 + 无头） | 看效果演进 |

## game/ 工程结构

```
game/
├── project.godot          # 1280×720 横屏；全局默认中文字体
├── export_presets.cfg     # 安卓导出预设（一键出 ../乱世行-m0.apk）
├── data/
│   ├── map_layout.txt     # 手工地图蓝图（gen_map.py 生成，60×40）
│   ├── map_points.json    # 关键点位（出生/城门/山贼/商队/宝物…）
│   └── tilespec.json      # 图集契约（8×3×64px，碰撞/图层定义）
├── scenes/Main.tscn       # 主场景
├── scripts/
│   ├── main.gd            # 纯接线：建图/氛围/遭遇/UI/存档/战斗编排
│   ├── map_builder.gd     # 蓝图→TileMapLayer + 道具精灵装配（碰撞/Z序）
│   ├── encounters.gd      # 遭遇链：村民/山贼×2/商队/宝物/传闻客（含对话）
│   ├── atmosphere.gd      # 暮色：CanvasModulate + 晕影 + 云影漂移
│   ├── player.gd          # 主将：双输入 + CharAnim 帧动画 + 战斗（横扫/冲锋/稳守）
│   ├── char_anim.gd       # 帧动画驱动（walk×4/windup/slash/hurt/idle）
│   ├── save_system.gd     # 存档：原子写、战前战后 checkpoint、防抖
│   ├── sfx.gd / music.gd  # 音效池 / 双层音乐（环境乐 + 战鼓淡入淡出）
│   ├── battle/
│   │   ├── battle.gd      # 战阵 v2：阵型推进/军令/侧背击/援军波/士气回稳
│   │   ├── unit.gd        # 战阵单位（轻量代理，无物理体）
│   │   ├── combatant.gd   # 队伍常量 + 星爆/尘土静态特效
│   │   └── damage_number.gd
│   ├── npc/               # 木偶 NPC（村民/商队/传闻客）+ 对话触发器
│   └── ui/                # 标题/对话框/HUD（血条+士气条）/结算卡/区域横幅/战斗按钮
├── assets/
│   ├── chars/             # 主将/汉军/黄巾 帧切片（walk/windup/slash/hurt/idle）
│   ├── fonts/             # Noto Sans SC 子集（OFL，~390KB/个）
│   ├── props/             # 建筑道具精灵（房/酒肆/城墙/寨旗/大树/帐篷/篝火）
│   ├── tiles/  npc/  ui/  sfx/  music/
└── tools/
    ├── gen_map.py         # 地图蓝图生成（改布局改这里，别手改 txt）
    ├── gen_tiles_v2.py / gen_props_v2.py   # 程序美术（暮色方向）
    ├── slice_sheet.py     # GPT 精灵表 → 游戏帧（键控/裁切/基线/缩放）
    ├── gen_sfx.py / gen_music.py / gen_drums.py  # 合成音效/环境乐/战鼓
    ├── subset_font.py     # 字体子集化（扫描源码用到的字）
    └── *_smoke.gd / battle_distribution.gd / zcheck.gd  # 自动化验证
```

## 素材生产线（角色这样来）

1. WebBridge 驱动浏览器里的 ChatGPT 生成 2×4 精灵表（走 4 帧 + 起手/出手/受击/待机）；
2. `slice_sheet.py` 键控黑底、裁切、对齐脚底基线、缩放到 192px 帧高；
3. `char_anim.gd` 在游戏里播帧动画。人物是真的在走，不是木偶颠簸。

## 常用命令（在 `乱世行/` 下执行）

```bash
# 桌面跑起来玩
godot/Godot_v4.4-stable_win64.exe --path game

# 重新出 APK
godot/Godot_v4.4-stable_win64_console.exe --headless --path game --export-debug "Android" "../乱世行-m0.apk"

# 自动化验证（标题/对话/战斗/遭遇链/存档/开场/俯瞰）
godot/Godot_v4.4-stable_win64_console.exe --path game -s tools/ui_smoke.gd
godot/Godot_v4.4-stable_win64_console.exe --path game -s tools/battle_smoke.gd
godot/Godot_v4.4-stable_win64_console.exe --headless --path game -s tools/battle_distribution.gd   # 20 场时长分布

# 改地图/素材/字体后重新生成
.venv/Scripts/python game/tools/gen_map.py
.venv/Scripts/python game/tools/gen_tiles_v2.py && .venv/Scripts/python game/tools/gen_props_v2.py
.venv/Scripts/python game/tools/subset_font.py
```

## 素材版权红线

`ref-三国大时代4/` 里的一切只用于**研究和测量**；游戏内所有美术/音乐/音效
均为程序生成或 AI 原创（GPT 生成精灵表 + PIL/numpy 程序美术 + 合成音频），
与原版无素材共用。字体为 Noto Sans SC（SIL OFL 许可，可再分发）。
