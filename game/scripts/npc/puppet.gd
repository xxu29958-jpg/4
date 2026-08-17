class_name Puppet
extends Sprite2D
## 手绘单帧精灵的木偶动画：行走颠簸/倾斜、待机呼吸、挥斩动作。
## 一张 AI 手绘立绘 + 程序化动作 = 风格统一且生动的角色表现。

## 贴地软阴影（§1）：玩家/士兵/NPC 木偶脚下各一个。
const SHADOW_TEX := preload("res://assets/npc/shadow.png")

var moving := false
## 前摇等姿势锁定：true 时 _process 不写 transform（外部 tween 接管）。
var pose_locked := false

var _phase := 0.0
var _idle_t := 0.0
var _slashing := false
var _shadow: Sprite2D


func _ready() -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = SHADOW_TEX
	_shadow.modulate = Color(0.0, 0.0, 0.0, 0.38)
	_shadow.scale = Vector2(0.75, 0.5)
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shadow.show_behind_parent = true
	add_child(_shadow)
	if texture != null:
		# 枢轴移到脚底：旋转/颠簸都围绕脚踩点，不会浮空漂移。
		offset = Vector2(0, 8 - texture.get_height() / 2.0)


func _process(delta: float) -> void:
	# 阴影钉在原地：抵消木偶颠簸/倾斜，影子始终贴地。
	if _shadow != null:
		_shadow.position.y = -position.y + 5.0
		_shadow.rotation = -rotation
	if _slashing or pose_locked:
		return
	if moving:
		_phase += delta * 11.0
		position.y = -absf(sin(_phase)) * 3.5
		rotation = sin(_phase) * 0.05
		_idle_t = 0.0
	else:
		_phase = 0.0
		_idle_t += delta
		position.y = lerpf(position.y, 0.0, 12.0 * delta)
		# 待机呼吸：极缓微摆
		rotation = lerpf(rotation, sin(_idle_t * 1.6) * 0.015, 6.0 * delta)


## 挥斩：后仰 → 甩出 → 收势。
func slash() -> void:
	if _slashing:
		return
	_slashing = true
	pose_locked = false
	position.y = 0.0
	var sign := -1.0 if flip_h else 1.0
	var tw := create_tween()
	tw.tween_property(self, "rotation", -0.4 * sign, 0.05)
	tw.tween_property(self, "rotation", 0.35 * sign, 0.09)
	tw.tween_property(self, "rotation", 0.0, 0.1)
	tw.tween_callback(func() -> void: _slashing = false)
