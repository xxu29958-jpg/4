---
name: lsx-playtest
description: 乱世行项目的无头试玩/验证协议：smoke 工具怎么跑、战斗时长资格门、截图验收流程。改玩法、调数值、出包前必用。
---

# 乱世行试玩与验证协议

工程：`game/`（Godot 4.4）。引擎：`godot/Godot_v4.4-stable_win64_console.exe`（相对 乱世行/ 根）。

## 铁律

- 任何玩法/数值改动后：先 `--import` 再跑相关 smoke，截图必须用 ReadMediaFile 亲眼看，不许只看打印。
- 战斗数值改动必须过资格门：`battle_distribution.gd` 退出码非零 = 不达标（中位 30~80s、胜率≥40%、零超时）。
- 截图统一落 `乱世行/测试截图/`。

## 命令（cwd=乱世行/ 根）

```bash
G=godot/Godot_v4.4-stable_win64_console.exe
$G --headless --path game --import            # 改资源/字体后先跑这个
$G --path game -s tools/battle_smoke.gd       # 单场战斗（bot 打带跑，定点截图）
$G --headless --path game -s tools/battle_distribution.gd   # 20 场资格门（退出码判定）
$G --path game -s tools/ui_smoke.gd           # 标题/横幅/对话/战斗 HUD/结算卡
$G --path game -s tools/chain_smoke.gd        # 遭遇链：村民/商队拦停/传闻客
$G --path game -s tools/save_smoke.gd         # 存档恢复（原地+宝物+成长字段）
$G --path game -s tools/zhai_smoke.gd         # 山寨组独立结算
$G --path game -s tools/opening_smoke.gd      # 新档开场白流程
$G --path game -s tools/map_overview.gd       # 全图俯瞰截图
$G --headless --path game --export-debug "Android" "../乱世行-m0.apk"   # 出包
```

## 人工 bot 与真机差异

smoke 在无头 60fps 锁定下跑；`Engine.max_fps=60` 已在工具内设置。真机触屏手感只能用户验——
交付说明里必须写明"真机未验"项。
