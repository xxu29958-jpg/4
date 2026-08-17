class_name NpcVisual
extends RefCounted
## NPC 视觉装配：手绘精灵 + 木偶动画。素材为单帧透明底 PNG（AI 生成后
## 经 tools/process_sprite.py 裁切键控）。

const BANDIT := preload("res://assets/npc/bandit_hd.png")
const SOLDIER_HAN := preload("res://assets/npc/soldier_han_hd.png")
const VILLAGER := preload("res://assets/npc/villager_hd.png")
const MERCHANT := preload("res://assets/npc/merchant_hd.png")


## 世界 NPC 显示高度（世界单位 px）：与战阵单位（64）同尺度。
const DISPLAY_H := 66.0


static func make_puppet(tex: Texture2D) -> Puppet:
	var p := Puppet.new()
	p.texture = tex
	var s := DISPLAY_H / tex.get_height()
	p.scale = Vector2(s, s)
	return p
