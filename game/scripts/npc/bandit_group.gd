class_name BanditGroup
extends Node2D
## 山贼：远远堵在官道上，可绕/可靠近/可拔刀/可跑。
## 玩家进入警戒圈即开战（世界内原位开战，不黑屏不弹窗）。

signal challenged

const AGGRO_RADIUS := 190.0

## 品字形核心站位（堵路）。
const FORMATION := [Vector2(-28, -24), Vector2(28, -24), Vector2(0, 18)]

## 木偶人数：官道组 3 人，寨内组 8 人（超出核心的绕外圈站位）。
@export var member_count := 3

var _triggered := false


func _ready() -> void:
	for i in member_count:
		# 与战斗内同一套帧动画皮（待机帧 + 呼吸级轻摆由 CharAnim 驱动）。
		var bandit := CharAnim.new()
		bandit.frames_dir = "res://assets/chars/bandit"
		bandit.display_height = 64.0
		bandit.position = _slot(i)
		add_child(bandit)
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = AGGRO_RADIUS
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


## 第 i 个木偶站位：先填品字形核心，多余的绕外圈（寨内 8 人组用）。
func _slot(i: int) -> Vector2:
	if i < FORMATION.size():
		return FORMATION[i]
	var outer := member_count - FORMATION.size()
	var a := TAU * float(i - FORMATION.size()) / float(outer)
	return Vector2(cos(a), sin(a)) * 56.0


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body is Player:
		return
	_triggered = true
	# body_entered 处于物理刷新中，开战会建带碰撞的士兵节点，延后一帧。
	call_deferred("_emit_challenged")


func _emit_challenged() -> void:
	challenged.emit()


## 重新武装（P0：战败/撤退不是结局，遭遇不得一次性死掉）。
## 玩家仍在警戒圈内时不立即复位，免得战败瞬间原地重开。
func rearm() -> void:
	await get_tree().create_timer(1.0).timeout
	_triggered = false
