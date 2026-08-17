class_name Caravan
extends Node2D
## 商队（§12.2）：沿官道真实移动，两端停顿后折返。
## 遭遇链互咬：山贼活着且挡在前方时，商队被拦停——
## "山贼抢商队是世界里正在发生的事"，玩家拔刀通路后商队恢复通行。

const CART_TEX := preload("res://assets/npc/cart.png")
const BLOCK_RADIUS := 90.0

@export var speed := 55.0
@export var pause_time := 4.0

var _points: Array[Vector2] = []
var _next := 1
var _pause_left := 0.0
var _blocker: Node2D
var _held := false

var _cart: Sprite2D
var _merchant: CharAnim
var _alarm: Sprite2D


func setup(points: Array[Vector2]) -> void:
	_points = points
	position = _points[0]


## 拦路者（官道山贼）。节点被释放（山贼被清除）即自动放行。
func set_blocker(node: Node2D) -> void:
	_blocker = node


func _ready() -> void:
	_cart = Sprite2D.new()
	_cart.texture = CART_TEX
	_cart.scale = Vector2(1.5, 1.5)  # 货车加大到与角色同尺度
	add_child(_cart)
	# 行商用帧动画：商队走时他真的在走（moving 驱动 walk 循环）。
	_merchant = CharAnim.new()
	_merchant.frames_dir = "res://assets/chars/merchant"
	_merchant.display_height = 64.0
	_merchant.position = Vector2(0, 30)
	add_child(_merchant)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/npc/shadow.png")
	shadow.modulate.a = 0.38
	shadow.scale = Vector2(0.55, 0.4)
	shadow.position = Vector2(0, 31)
	shadow.z_index = -1
	add_child(shadow)
	_alarm = Sprite2D.new()
	_alarm.texture = ProximityBubble.ALERT
	_alarm.position = Vector2(10, -40)
	_alarm.visible = false
	add_child(_alarm)


func _process(delta: float) -> void:
	if _points.size() < 2:
		return
	# 被拦停：山贼活着且在跟前。
	_held = is_instance_valid(_blocker) \
			and global_position.distance_to(_blocker.global_position) < BLOCK_RADIUS
	_alarm.visible = _held
	if _held:
		_merchant.moving = false
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		_merchant.moving = false
		return
	_merchant.moving = true
	var target := _points[_next]
	var offset := target - position
	var step := speed * delta
	if offset.length() <= step:
		position = target
		_pause_left = pause_time
		_next = (_next + 1) % _points.size()
	else:
		position += offset.normalized() * step
		# 行进方向左右翻转，面向路的前方。
		var facing_left := offset.x < 0.0
		_cart.flip_h = facing_left
		_merchant.flip_h = facing_left
