class_name RumorDrinker
extends Node2D
## 酒肆传闻客：山贼被清除后出现在阳翟酒肆门口，
## 玩家靠近冒"…"气泡——"酒馆开始谈论自己刚才干的事"。

func _ready() -> void:
	add_child(NpcVisual.make_puppet(NpcVisual.MERCHANT))
	var bubble := ProximityBubble.new()
	bubble.texture = ProximityBubble.TALK
	add_child(bubble)
