extends Node2D
class_name TapToMove
## 点地移动（方案 B）：点哪里走哪里，直线 + 碰撞滑动。
##
## A/B 公平条款（§12.7）：D1 不做绕行导航，A/B 只在无复杂遮挡的
## 开放区域对比。到达目的地或撞上障碍被挡住时停止。

const ARRIVE_EPS := 6.0

var _enabled := false
var _has_target := false
var _target := Vector2.ZERO

var _marker: Sprite2D


func _ready() -> void:
	_marker = Sprite2D.new()
	_marker.texture = preload("res://assets/ui/tap_marker.png")
	_marker.visible = false
	add_child(_marker)


func set_active(on: bool) -> void:
	_enabled = on
	if not on:
		_clear_target()


## Player 每物理帧经统一 velocity 接口查询期望方向。
func direction_to_target(from: Vector2) -> Vector2:
	if not _enabled or not _has_target:
		return Vector2.ZERO
	var offset := _target - from
	if offset.length() <= ARRIVE_EPS:
		_clear_target()
		return Vector2.ZERO
	return offset.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif not Joystick._on_mobile() and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	if tapped:
		# get_global_mouse_position() 对触摸同样返回最新触点位置。
		_target = get_global_mouse_position()
		_has_target = true
		_marker.global_position = _target
		_marker.visible = true


func _clear_target() -> void:
	_has_target = false
	_marker.visible = false
