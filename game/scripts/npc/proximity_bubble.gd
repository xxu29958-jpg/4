class_name ProximityBubble
extends Node2D
## 头顶气泡：玩家靠近时冒出、离开收起。
## 世界内"有人有话说 / 有事发生"的统一信号，不用弹窗。

const ALERT := preload("res://assets/ui/bubble_alert.png")
const TALK := preload("res://assets/ui/bubble_talk.png")

@export var radius := 70.0
@export var texture: Texture2D = ALERT

var _bubble: Sprite2D
var _t := 0.0


func _ready() -> void:
	_bubble = Sprite2D.new()
	_bubble.texture = texture
	_bubble.position = Vector2(8, -38)
	_bubble.visible = false
	add_child(_bubble)
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _process(delta: float) -> void:
	if not _bubble.visible:
		return
	_t += delta
	_bubble.position.y = -38.0 + sin(_t * 3.0) * 2.0  # 浮动呼吸感


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	_bubble.visible = true
	_bubble.scale = Vector2.ZERO
	create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_bubble.visible = false
