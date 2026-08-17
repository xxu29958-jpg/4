class_name TreasureSparkle
extends Sprite2D
## 废营地第一件宝物：长柄旧刀（§12.1）。
## 远处脉动闪光引人靠近；玩家踏上即拾取——横扫范围肉眼明显扩大，
## 直接教育玩家"地图角落值得我去翻"。

signal picked_up

const TEX := preload("res://assets/ui/sparkle.png")
const PICKUP_RADIUS := 40.0

var _t := 0.0
var _taken := false


func _ready() -> void:
	texture = TEX
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _process(delta: float) -> void:
	_t += delta
	var pulse := 1.0 + 0.35 * sin(_t * 4.0)
	scale = Vector2(pulse, pulse)
	modulate.a = 0.65 + 0.35 * sin(_t * 4.0)


func _on_body_entered(body: Node2D) -> void:
	if _taken or not body is Player:
		return
	_taken = true
	Sfx.play(Sfx.PICKUP)
	# 拾取爆发：放大一闪后消失。
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(3.0, 3.0), 0.2)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)
	picked_up.emit()
