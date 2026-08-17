class_name RumorDrinker
extends Node2D
## 酒肆传闻客：阳翟酒肆门口的消息人士——"酒馆开始谈论玩家干的事"。
## 帧动画皮：村民帧 + 青衫染色（与村民老头区分）。

func _ready() -> void:
	var anim := CharAnim.new()
	anim.frames_dir = "res://assets/chars/villager"
	anim.display_height = 63.0
	anim.modulate = Color(0.75, 0.88, 1.05)  # 青衫
	add_child(anim)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/npc/shadow.png")
	shadow.modulate.a = 0.38
	shadow.scale = Vector2(0.55, 0.4)
	shadow.z_index = -1
	add_child(shadow)
	var bubble := ProximityBubble.new()
	bubble.texture = ProximityBubble.TALK
	add_child(bubble)
