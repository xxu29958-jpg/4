class_name WavingVillager
extends Node2D
## 村民：路口招手（帧动画，GPT 精灵表切片）。
## 玩家靠近：招手呼唤 + 冒"!"气泡；对话由 dialogue_trigger 承接（encounters 装配）。

const WAVE_RANGE := 110.0

var _anim: CharAnim
var _player: Node2D
var _waving := false


func _ready() -> void:
	_anim = CharAnim.new()
	_anim.frames_dir = "res://assets/chars/villager"
	_anim.display_height = 62.0
	add_child(_anim)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/npc/shadow.png")
	shadow.modulate.a = 0.38
	shadow.scale = Vector2(0.55, 0.4)
	shadow.z_index = -1
	add_child(shadow)
	add_child(ProximityBubble.new())
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	if _player == null:
		return
	var near: bool = global_position.distance_to(_player.global_position) < WAVE_RANGE
	if near and not _waving:
		_waving = true
		# 招手帧与待机帧交替 = 挥手（villager 表第二行第一格是招手）。
		_anim.play_emote(["windup", "idle"], 2.5)
	elif not near and _waving:
		_waving = false
		_anim.stop_emote()
