extends Control
class_name Joystick
## 虚拟摇杆（方案 A）：手指落下处动态出现底座，拖动出向量，松手消失。
##
## 输出经 get_output() 汇入 Player 的统一 velocity 接口。
## 桌面用鼠标等效操作，便于开发机调试（project.godot 已关闭触摸/鼠标互模拟）。

const RADIUS := 48.0

var _enabled := true
var _touch_id := -1
var _base_center := Vector2.ZERO
var _output := Vector2.ZERO

var _base: TextureRect
var _knob: TextureRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_base = _make_texture_rect(preload("res://assets/ui/joy_base.png"), 96.0)
	_knob = _make_texture_rect(preload("res://assets/ui/joy_knob.png"), 48.0)
	add_child(_base)
	add_child(_knob)
	_hide_stick()


func _make_texture_rect(tex: Texture2D, size: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(size, size)
	rect.size = Vector2(size, size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Player 切换方案时调用。停用时吞掉输入事件（STOP），启用时反之亦然。
func set_active(on: bool) -> void:
	_enabled = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if not on:
		_end_touch()


func get_output() -> Vector2:
	return _output


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_begin_touch(event.position)
		elif not event.pressed and event.index == _touch_id:
			_end_touch()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_update_drag(event.position)
	elif not _on_mobile() and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _touch_id == -1:
			_touch_id = 0  # 桌面鼠标等价于一根手指
			_begin_touch(event.position)
		elif not event.pressed and _touch_id == 0:
			_end_touch()
	elif not _on_mobile() and event is InputEventMouseMotion and _touch_id == 0:
		_update_drag(event.position)


## 移动端已由 ScreenTouch 覆盖，跳过 Viewport 模拟出的鼠标事件，防双份触发。
static func _on_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


func _begin_touch(pos: Vector2) -> void:
	_base_center = pos
	_output = Vector2.ZERO
	_base.position = pos - _base.size / 2.0
	_knob.position = pos - _knob.size / 2.0
	_base.visible = true
	_knob.visible = true


func _update_drag(pos: Vector2) -> void:
	var offset := pos - _base_center
	if offset.length() > RADIUS:
		offset = offset.normalized() * RADIUS
	_output = offset / RADIUS
	_knob.position = _base_center + offset - _knob.size / 2.0


func _end_touch() -> void:
	_touch_id = -1
	_output = Vector2.ZERO
	_hide_stick()


func _hide_stick() -> void:
	_base.visible = false
	_knob.visible = false
