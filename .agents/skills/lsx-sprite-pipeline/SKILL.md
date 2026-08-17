---
name: lsx-sprite-pipeline
description: 乱世行角色素材生产线：WebBridge 驱动 ChatGPT 出 2×4 精灵表 → slice_sheet.py 切片 → CharAnim 播帧。新增/更换角色皮肤、NPC 帧动画时必用。
---

# 乱世行角色素材生产线

角色帧全部来自 GPT 生成 + 程序切片，禁止手绘搬图（版权红线）。

## 流程

1. **GPT 出表**（WebBridge，daemon `http://127.0.0.1:10086/command`，session 名按任务起）：
   提示词要点——Q 版三头身厚涂深色描边；2 行×4 列 8 格等大居中脚底对齐；
   纯黑背景无地面无文字；第一行=正面行走四帧（左迈/过渡/右迈/过渡），
   第二行=攻击起手/出手/受击/待机（NPC 可换成招手/作揖/受惊/待机）。
   参考 `乱世行/测试截图/wb_*.jpg` 的历史对话。
2. **取图**：页面 img 加载完成后用 canvas.toDataURL 读全尺寸（estuary URL 直接 curl 会 401），
   分块 base64 拉回存 `assets_ai/<name>_sheet_raw.png`。
3. **切片**：`.venv/Scripts/python game/tools/slice_sheet.py assets_ai/<name>_sheet_raw.png game/assets/chars/<name> <name>`
   输出 8 帧（walk1-4/windup/slash/hurt/idle，192px 高，已提饱和/对比/锐度）+ `<name>_frames.json`。
4. **接入**：`CharAnim.new()` → `frames_dir="res://assets/chars/<name>"`、`display_height`（士兵 64、主将 74）。
   CharAnim 有静态缓存，同目录多单位只读一次。

## 验收

- 切片后拼接触表用 ReadMediaFile 逐帧看：行走腿部交替正确、攻击起手/出手不颠倒、无黑底毛边。
- 帧顺序错了别改代码——重切或重生成。

##  civ 角色第二行语义

非战斗角色第二行 = 自定义动作（如 villager：招手/作揖/受惊/待机），文件名仍是
windup/slash/hurt/idle，用 `CharAnim.play_emote(["windup","idle"], fps)` 播循环即可。
