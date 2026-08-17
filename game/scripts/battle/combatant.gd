class_name Combatant
extends CharacterBody2D
## 战斗单位基类：HP / 受击反馈 / 击退 / 死亡表现。士兵与双方主将共用。
##
## 鸭子类型契约（Player 也遵守）：team、alive、global_position、
## take_damage(amount, from_pos, knock)、died 信号。

signal died(who: Combatant)

const TEAM_PLAYER := 0
const TEAM_BANDIT := 1

@export var max_hp := 40
@export var team := TEAM_BANDIT
@export var move_speed := 110.0
@export var attack_damage := 5
@export var attack_range := 44.0
@export var attack_cooldown := 1.15

var hp := 0
var alive := true
var fleeing := false
var knockback := Vector2.ZERO


func _ready() -> void:
	hp = max_hp
	add_to_group("combatants")


## 受击：扣血 + 击退 + 红闪 + 星爆 + 飘字 + 音效（§12.4 表现要求）。
func take_damage(amount: int, from_pos: Vector2, knock: float, is_skill := false) -> void:
	if not alive:
		return
	hp -= amount
	var dir := global_position - from_pos
	if dir.length() > 0.01:
		knockback += dir.normalized() * knock
	_flash_hit()
	spawn_spark(get_parent(), global_position + Vector2(0, -12))
	DamageNumber.spawn(get_parent(), global_position, amount, is_skill)
	Sfx.play(Sfx.HIT)
	spawn_dust(get_parent(), global_position + Vector2(0, 8), 3)
	if hp <= 0:
		_die()


func _flash_hit() -> void:
	modulate = Color(1.6, 0.7, 0.7)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.15)


func _die() -> void:
	alive = false
	died.emit(self)
	Sfx.play(Sfx.DOWN)
	spawn_dust(get_parent(), global_position, 10)
	spawn_spark(get_parent(), global_position + Vector2(0, -12), 1.5)
	# 物理刷新期间不能改碰撞状态，延后到本帧结束。
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_physics_process(false)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(self, "rotation", PI / 2.0, 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.6).set_delay(0.25)
	tw.chain().tween_callback(queue_free)


## 命中星爆（三国大时代式黄橙爆裂）：缩放弹出 + 快速消隐。
static func spawn_spark(parent: Node, pos: Vector2, size := 1.0) -> void:
	var spark := Sprite2D.new()
	spark.texture = preload("res://assets/ui/spark.png")
	spark.position = pos
	spark.scale = Vector2.ZERO
	spark.z_index = 90
	parent.add_child(spark)
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector2(size, size), 0.08) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(spark, "modulate:a", 0.0, 0.14)
	tw.tween_callback(spark.queue_free)


## 击退惯性的公共物理步：各子类把自主移动写进 move_velocity 后调用。
func _physics_step(delta: float, self_velocity: Vector2) -> void:
	velocity = self_velocity + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 800.0 * delta)
	move_and_slide()


## 尘土：命中/倒地的视觉确认。
static func spawn_dust(parent: Node, pos: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, 120)
	p.color = Color(0.78, 0.68, 0.5, 0.9)
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
