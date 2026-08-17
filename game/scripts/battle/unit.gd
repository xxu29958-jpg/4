class_name BattleUnit
extends Node2D
## 战阵单位（轻量代理，无物理体）：阵位 → 接敌 → 溃逃。
## 索敌/分离由 BattleManager 线性供血；目标每 3 帧重估一次（分批 stagger），
## 大兵团同屏不卡。
##
## stats 字段：hp / damage / range / windup / cooldown / speed / armor / mass /
##   display_height / frames_dir / is_leader / brace（结矛墙）/
##   ranged（弓手）/ pref_range（弓手保持距离）/ proj_speed

signal died(who: BattleUnit)

const TEAM_PLAYER := 0
const TEAM_BANDIT := 1

var team := TEAM_BANDIT
var stats := {}
var hp := 0
var alive := true
var fleeing := false
var is_leader := false

var battle  # BattleManager（去类型化，打断循环依赖）
## 阵位（世界坐标）：未接敌时的目标点，由经理每帧随战线推进刷新。
var slot := Vector2.ZERO
## 正面朝向（单位向量）：侧背击判定的基准。接敌后面向目标。
var facing := Vector2.RIGHT

var charge_left := 0.0   # 冲锋军令剩余秒数
var charge_hit_done := false  # 本次冲锋的首次撞击是否已结算
var hold_order := false  # 稳守军令生效中

var _cd := 0.0
var _knock := Vector2.ZERO
var _target: Node2D
var _anim: CharAnim
var _stagger := 0


func setup(p_stats: Dictionary, p_team: int, p_battle) -> void:
	stats = p_stats
	team = p_team
	battle = p_battle
	hp = int(stats.get("hp", 40))
	is_leader = bool(stats.get("is_leader", false))


func _ready() -> void:
	add_to_group("combatants")
	_stagger = get_instance_id() % 3  # 分批重估目标
	_anim = CharAnim.new()
	_anim.frames_dir = stats.get("frames_dir", "res://assets/chars/soldier")
	_anim.display_height = float(stats.get("display_height", 64.0))
	add_child(_anim)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/npc/shadow.png")
	shadow.modulate.a = 0.38
	var s := _anim.display_height / 64.0
	shadow.scale = Vector2(s * 0.55, s * 0.4)
	shadow.position = Vector2(0, 1)
	shadow.z_index = -1
	add_child(shadow)
	# 阵营识别件：肩后小令旗（0.2s 内能从 60 人里读出阵营）。
	var pennant := Polygon2D.new()
	pennant.polygon = PackedVector2Array([Vector2(0, 0), Vector2(11, 4), Vector2(0, 8)])
	pennant.color = Color(0.30, 0.55, 0.62) if team == TEAM_PLAYER 			else Color(0.79, 0.63, 0.15)
	pennant.position = Vector2(-7, -_anim.display_height * 0.82)
	add_child(pennant)
	if is_leader:
		var banner := Sprite2D.new()
		banner.texture = load("res://assets/npc/banner_yellow.png" \
				if team == TEAM_BANDIT else "res://assets/npc/banner_han.png")
		banner.position = Vector2(10, -_anim.display_height - 8)
		banner.name = "Banner"
		add_child(banner)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_cd = maxf(0.0, _cd - delta)
	charge_left = maxf(0.0, charge_left - delta)
	if charge_left <= 0.0:
		charge_hit_done = false

	if fleeing:
		_flee_step(delta)
		return

	# 目标每 3 帧重估一次（1/3 单位错开），其余帧沿用旧目标。
	if (Engine.get_physics_frames() + _stagger) % 3 == 0 \
			or not is_instance_valid(_target) or not _target.alive:
		# 战线接触带：非冲锋近战只在近距警戒带内索敌，后排钉在阵位
		# 上形成纵深；冲锋/弓手才有远索敌。
		var leash := 480.0
		if charge_left <= 0.0 and not bool(stats.get("ranged", false)):
			leash = 170.0 if hold_order else 200.0
		_target = battle.nearest_enemy(self, leash)

	var move := Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		var offset: Vector2 = _target.global_position - global_position
		var dist := offset.length()
		if bool(stats.get("ranged", false)) and charge_left <= 0.0:
			move = _ranged_move(offset, dist)
		else:
			move = _melee_move(offset, dist)
	elif slot.distance_to(global_position) > 6.0:
		# 回阵位：战线未接敌时保持队形推进。
		var offset: Vector2 = slot - global_position
		move = offset.normalized() * _speed()
		facing = battle.advance_dir[team]
		_anim.moving = true
	else:
		_anim.moving = false
		facing = battle.advance_dir[team]

	# 友军分离 + 击退惯性。
	# 步频喂给动画：走多快踏多快，杜绝滑冰。
	_anim.set_stride(_speed() if _anim.moving else 0.0)
	move += battle.separation(self) * _speed() * 0.9
	if move.length() > _speed():
		move = move.normalized() * _speed()
	position += (move * delta) + _knock * delta
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	if absf(facing.x) > 0.1:
		_anim.flip_h = facing.x < 0.0
	# 伪 Y 排序：与主将同一标尺。
	z_index = int(global_position.y * 0.25)


## 近战行为：追进攻击距离开打。
func _melee_move(offset: Vector2, dist: float) -> Vector2:
	var reach: float = stats.get("range", 46.0)
	if dist > reach:
		facing = offset.normalized()
		_anim.moving = true
		return offset.normalized() * _speed()
	_anim.moving = false
	facing = offset.normalized()
	if _cd <= 0.0 and battle.beat_ready(false):
		_attack()
	return Vector2.ZERO


## 弓手行为：保持 pref_range 环形带，到位放箭；被贴身则拔刀弱反击。
func _ranged_move(offset: Vector2, dist: float) -> Vector2:
	var pref: float = stats.get("pref_range", 170.0)
	facing = offset.normalized()
	if dist < pref * 0.45:
		# 贴脸了：弓手疲软近战（数值上就是弱刀）。
		_anim.moving = false
		if _cd <= 0.0:
			_attack()
		return Vector2.ZERO
	if dist < pref - 30.0:
		_anim.moving = true
		return -offset.normalized() * _speed() * 0.85  # 放风筝后撤
	if dist > pref + 40.0:
		_anim.moving = true
		return offset.normalized() * _speed()
	_anim.moving = false
	if _cd <= 0.0 and battle.beat_ready(true):
		_attack()
	return Vector2.ZERO


func _speed() -> float:
	return float(stats.get("speed", 100.0)) * (1.6 if charge_left > 0.0 else 1.0)


func _attack() -> void:
	_cd = float(stats.get("cooldown", 1.1))
	_anim.play_attack(float(stats.get("windup", 0.14)) + randf_range(0.0, 0.12))
	var from := global_position
	var target := _target
	var peak := func() -> void:
		if not alive or not is_instance_valid(target) or not target.alive:
			return
		var dmg := int(float(stats.get("damage", 6)) * (1.5 if charge_left > 0.0 else 1.0))
		if bool(stats.get("ranged", false)) \
				and global_position.distance_to(target.global_position) > float(stats.get("range", 46.0)):
			# 放箭：抛射物飞行中目标死了箭也照飞（打空是真实的）。
			battle.spawn_arrow(global_position, target, dmg, team, self)
			Sfx.play(Sfx.SWING)
			return
		var reach: float = stats.get("range", 46.0) + 12.0
		if global_position.distance_to(target.global_position) > reach:
			return  # 目标已脱离，挥空
		var knock := 130.0 if charge_left > 0.0 else 55.0
		Sfx.play(Sfx.SWING)
		target.take_damage(dmg, from, knock, false, self)
		# 冲锋首撞：额外击退 + 小范围尘土，"撞开人墙"的手感。
		if charge_left > 0.0 and not charge_hit_done:
			charge_hit_done = true
			Combatant.spawn_dust(get_parent(), target.global_position, 6)
			battle.notify_charge_impact()
	_anim.attack_peak.connect(peak, CONNECT_ONE_SHOT)
	# 冲锋免前摇：立刻到出手点（撞进人堆就是这一下）。
	if charge_left > 0.0:
		_anim.attack_peak.emit()


## 受击：护甲减免 → 侧背击加成 → 扣血/击退/表现。
## 侧背击只在"正与别人交手/未察觉"时成立——正面对砍方向随敌转，不算侧背。
func take_damage(amount: int, from_pos: Vector2, knock: float, is_skill := false,
		attacker: Node2D = null) -> void:
	if not alive:
		return
	var dmg := maxi(1, amount - int(stats.get("armor", 0)))
	var to_attacker := (from_pos - global_position).normalized()
	var frontal := facing.dot(to_attacker) > 0.5
	# 攻击者由调用方直传（评审：坐标反查在密集战线会认错人）
	var attacker_unit: BattleUnit = attacker as BattleUnit
	var distracted := _target != null and attacker != null and attacker != _target
	if hold_order and frontal:
		dmg = maxi(1, int(dmg * 0.65))
	elif not frontal and (distracted or attacker == null):
		# 侧背击：真实战术伤害，并打击士气。主将（非 BattleUnit）从侧背
		# 出手时 attacker==null，同样成立——绕后横扫是真战术。
		dmg = int(dmg * 1.8) + 1
		battle.notify_flanked(team)
	# 结矛墙迎击：冲锋者撞上稳守枪兵，先吃一反。
	if hold_order and bool(stats.get("brace", false)) and frontal:
		if attacker_unit != null and attacker_unit.charge_left > 0.0:
			attacker_unit.take_damage(int(stats.get("damage", 6)) + 4, global_position, 90.0, false, self)
	hp -= dmg
	_knock += (global_position - from_pos).normalized() * knock \
			/ maxf(1.0, float(stats.get("mass", 1.0)))
	_anim.play_hurt()
	modulate = Color(1.6, 0.7, 0.7)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.15)
	Combatant.spawn_spark(get_parent(), global_position + Vector2(0, -_anim.display_height * 0.55))
	# 伤害数字只给重击/技能（满地飘 2、3 是数值测试场味）。
	if is_skill or dmg >= 10:
		DamageNumber.spawn(get_parent(), global_position - Vector2(0, _anim.display_height), dmg, is_skill)
	Sfx.play(Sfx.HIT)
	if hp <= 0:
		_die()


func _die() -> void:
	alive = false
	died.emit(self)
	Sfx.play(Sfx.DOWN)
	_anim.play_dead()
	Combatant.spawn_dust(get_parent(), global_position, 10)
	Combatant.spawn_spark(get_parent(), global_position + Vector2(0, -_anim.display_height * 0.5), 1.5)
	remove_from_group("combatants")
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(self, "rotation", (PI / 2.0) * (1.0 if _anim.flip_h else -1.0), 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.8).set_delay(2.6)
	tw.chain().tween_callback(queue_free)


## 溃逃：背离最近敌人跑，旗帜倒下，离场后消散。
func rout() -> void:
	if not alive:
		return
	fleeing = true
	var banner := get_node_or_null("Banner")
	if banner != null:
		var tw := create_tween()
		tw.set_parallel()
		tw.tween_property(banner, "rotation", 1.3, 0.4)
		tw.tween_property(banner, "modulate", Color(0.5, 0.5, 0.5), 0.4)


func _flee_step(delta: float) -> void:
	var nearest: Node2D = battle.nearest_enemy(self, 9999.0)
	var away := Vector2.ZERO
	if nearest != null:
		away = (global_position - nearest.global_position).normalized()
	else:
		away = (global_position - battle.center).normalized()
	_anim.moving = true
	_anim.flip_h = away.x < 0.0
	position += away * float(stats.get("speed", 100.0)) * 1.4 * delta
	if global_position.distance_to(battle.center) > 760.0:
		queue_free()
