extends CharacterBody2D
class_name Player
## 主将：双输入方案 → 统一 velocity 接口 + 战斗（§7.3）。
## 视觉：CharAnim 帧动画（GPT 精灵表切片），世界内显示高 74px。
##
## 战斗侧遵守鸭子契约：team / alive / take_damage / died 语义。

enum MoveMode { JOYSTICK, TAP }

@export var speed := 160.0

var move_mode := MoveMode.JOYSTICK

var _joystick: Joystick
var _tap: TapToMove
var _anim: CharAnim


func _ready() -> void:
	add_to_group("combatants")
	add_to_group("player")  # 对话触发器/UI 查找用
	_anim = CharAnim.new()
	_anim.frames_dir = "res://assets/chars/hero"
	_anim.display_height = 74.0
	add_child(_anim)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/npc/shadow.png")
	shadow.modulate.a = 0.4
	shadow.scale = Vector2(0.68, 0.5)
	shadow.z_index = -1
	add_child(shadow)
	# 玩家环：主将必须 0.2s 内从军阵里被眼睛抓出来。
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * 20.0, sin(a) * 9.0))
	ring.polygon = pts
	var ring_col := Color(0.92, 0.78, 0.35, 0.55)
	ring.color = ring_col
	ring.z_index = -1
	add_child(ring)
	var ring_tw := create_tween().set_loops()
	ring_tw.tween_property(ring, "modulate:a", 0.35, 0.8)
	ring_tw.tween_property(ring, "modulate:a", 0.8, 0.8)


## 由 Main 注入两个输入源；必须在首次 set_move_mode 前调用。
func setup(joystick: Joystick, tap: TapToMove) -> void:
	_joystick = joystick
	_tap = tap
	set_move_mode(MoveMode.JOYSTICK)


func toggle_move_mode() -> void:
	set_move_mode(MoveMode.TAP if move_mode == MoveMode.JOYSTICK else MoveMode.JOYSTICK)


func set_move_mode(mode: MoveMode) -> void:
	move_mode = mode
	_joystick.set_active(mode == MoveMode.JOYSTICK)
	_tap.set_active(mode == MoveMode.TAP)


func _physics_process(delta: float) -> void:
	var dir := _desired_direction()
	if not dir.is_zero_approx():
		_facing = dir.normalized()
	velocity = dir * speed
	_anim.set_stride(velocity.length())
	move_and_slide()
	_update_animation(dir)
	_combat_tick(delta)
	# 伪 Y 排序：脚越靠下画得越前（与战阵单位同一标尺）。
	z_index = int(global_position.y * 0.25)


## 统一 velocity 接口：两种方案在此处汇合成一个期望方向向量。
func _desired_direction() -> Vector2:
	if move_mode == MoveMode.JOYSTICK:
		return _joystick.get_output()
	return _tap.direction_to_target(global_position)


func _update_animation(dir: Vector2) -> void:
	if _attack_anim_left > 0.0:
		return  # 攻击动作优先
	_anim.moving = not dir.is_zero_approx()
	if absf(dir.x) > 0.1:
		_anim.flip_h = dir.x < 0.0


# ---------------------------------------------------------------- 战斗（§7.3）

const MAX_HP := 140  # 基础血量；每级 +12（max_hp 变量为准）
const ATTACK_RANGE := 62.0
const ATTACK_COOLDOWN := 0.7
const ATTACK_DAMAGE := 12
const SWEEP_RANGE := 95.0
const SWEEP_HALF_ARC := 1.134  # 130° 扇形（弧度半角）
const SWEEP_DAMAGE := 32
const SWEEP_KNOCK := 320.0
const SWEEP_COOLDOWN := 8.0
## 长柄旧刀：横扫范围肉眼明显扩大。
const SWEEP_RANGE_OLD_BLADE := 150.0

## 成长：战功升级（+12 血 +2 攻），钱用于招募乡勇。
var level := 1
var xp := 0
var money := 30
var bonus_melee := 0  # 教头处招募的额外枪兵（入编制，上限 8）
var max_hp := MAX_HP
var attack_damage := ATTACK_DAMAGE

var team := Combatant.TEAM_PLAYER
var hp := MAX_HP
var alive := true
var fleeing := false  # 契约字段：主将永不溃逃
var in_battle := false
var has_old_blade := false
var sweep_range := SWEEP_RANGE
var skill_cd_left := 0.0
var battle: BattleManager

var _attack_cd := 0.0
var _facing := Vector2.RIGHT
var _attack_anim_left := 0.0
var _action_gen := 0        # 战斗动作代际：横扫覆盖普攻时作废旧回调（评审）
var _attack_facing := Vector2.RIGHT  # 出手瞬间朝向快照（弧光与伤害同读）


func _combat_tick(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	skill_cd_left = maxf(0.0, skill_cd_left - delta)
	if not in_battle or not alive:
		return
	# 普攻自动：索敌范围内自动出手；短前摇后在出手帧结算伤害。
	if _attack_cd <= 0.0:
		var target := _nearest_bandit(ATTACK_RANGE)
		if target != null:
			_attack_cd = ATTACK_COOLDOWN
			_action_gen += 1
			var gen := _action_gen
			_play_attack_anim(target.global_position - global_position)
			Sfx.play(Sfx.SWING)
			var dmg_from := global_position
			_anim.attack_peak.connect(func() -> void:
				if gen != _action_gen:
					return  # 已被横扫覆盖：旧普攻回调作废
				if alive and is_instance_valid(target) and target.alive \
						and global_position.distance_to(target.global_position) \
								<= ATTACK_RANGE + 14.0:
					target.take_damage(attack_damage, dmg_from, 60.0, false, self)
			, CONNECT_ONE_SHOT)


## 技能·横扫：正面扇形伤害 + 击退 + 屏震。
func use_sweep() -> void:
	if not in_battle or not alive or skill_cd_left > 0.0:
		return
	skill_cd_left = SWEEP_COOLDOWN
	_action_gen += 1
	var gen := _action_gen
	_attack_facing = _facing  # 出手瞬间冻结朝向：弧光与伤害同读一个快照（评审）
	Sfx.play(Sfx.SWEEP)
	_play_attack_anim(_facing)
	var hit_any := false
	var from := global_position
	_anim.attack_peak.connect(func() -> void:
		if gen != _action_gen:
			return
		for node in get_tree().get_nodes_in_group("combatants"):
			if node == self or node.team == team or not node.alive:
				continue
			var offset: Vector2 = node.global_position - from
			if offset.length() > sweep_range:
				continue
			if absf(_attack_facing.angle_to(offset)) > SWEEP_HALF_ARC:
				continue  # angle_to 带符号：不取绝对值负半圆会漏判
			node.take_damage(SWEEP_DAMAGE, from, SWEEP_KNOCK, true, self)
			hit_any = true
		if hit_any:
			if battle != null:
				battle.hit_stop(0.08)
				battle.notify_player_breach(from)  # 开缺口：友军自动灌入
			_shake(6.0)
	, CONNECT_ONE_SHOT)
	_flash_arc()


## 装备长柄旧刀：横扫范围肉眼明显扩大。
func equip_old_blade() -> void:
	has_old_blade = true
	sweep_range = SWEEP_RANGE_OLD_BLADE
	_flash_arc()  # 当场亮一次新范围，让变化被看见


## 军令·冲锋。
func use_rally() -> void:
	if in_battle and battle != null:
		battle.charge_team(team)


## 军令·稳守。
func use_hold() -> void:
	if in_battle and battle != null:
		battle.hold_team(team)


## 受击：红闪 + hurt 帧 + 星爆 + 飘字 + 小屏震。
func take_damage(amount: int, _from_pos: Vector2, _knock: float, is_skill := false,
		_attacker: Node2D = null) -> void:
	if not alive:
		return
	hp -= maxi(1, amount - 3)  # 主将底子：固定减伤 3
	Sfx.play(Sfx.HIT)
	_anim.play_hurt()
	modulate = Color(1.6, 0.7, 0.7)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.15)
	Combatant.spawn_spark(get_parent(), global_position + Vector2(0, -40))
	DamageNumber.spawn(get_parent(), global_position - Vector2(0, 74), amount, is_skill)
	Combatant.spawn_dust(get_parent(), global_position + Vector2(0, 8), 3)
	_shake(3.0)
	if hp <= 0:
		hp = 0
		alive = false
		if battle != null:
			battle.notify_player_down()


## 屏震委托给 Main（相机在它手里）。
func _shake(strength: float) -> void:
	var main := get_parent()
	if main.has_method(&"shake"):
		main.shake(strength)


## 战功入账：自动升级（每级 30×level 经验）。
func add_xp(n: int) -> bool:
	xp += n
	var need := level * 30
	if xp >= need:
		xp -= need
		level += 1
		max_hp += 12
		attack_damage += 2
		hp = max_hp  # 升级回满
		return true
	return false


## 战后复位（由 Main 在 battle_ended 时调用）。
func recover() -> void:
	hp = max_hp
	alive = true
	in_battle = false
	battle = null
	skill_cd_left = 0.0


func _nearest_bandit(max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_dist := max_dist
	for node in get_tree().get_nodes_in_group("combatants"):
		if node == self or node.team == team or not node.alive:
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


## 攻击动作：帧动画起手→出手，附带前扑位移。
func _play_attack_anim(dir: Vector2) -> void:
	_attack_anim_left = 0.26
	if absf(dir.x) > 0.1:
		_anim.flip_h = dir.x < 0.0
	_anim.play_attack(0.10, 0.16)
	var tw := create_tween()
	var nudge := dir.normalized() * 6.0
	tw.tween_property(_anim, "position", nudge, 0.06)
	tw.tween_property(_anim, "position", Vector2.ZERO, 0.12)


## 横扫弧光：扇形闪光 150ms，半径跟随当前武器（吃长柄旧刀加成）。
func _flash_arc() -> void:
	var arc := Polygon2D.new()
	arc.polygon = _arc_points()
	arc.rotation = _attack_facing.angle()
	arc.color = Color(0.85, 0.72, 0.35, 0.45)
	add_child(arc)
	var tw := arc.create_tween()
	tw.tween_property(arc, "color:a", 0.0, 0.15)
	tw.tween_callback(arc.queue_free)


func _arc_points() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		var a := -SWEEP_HALF_ARC + SWEEP_HALF_ARC * 2.0 * i / 8.0
		pts.append(Vector2(sweep_range, 0).rotated(a))
	return pts
