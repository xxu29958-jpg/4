# -*- coding: utf-8 -*-
def patch(path, subs):
    src = open(path, encoding='utf-8').read()
    for i, (old, new) in enumerate(subs):
        assert old in src, f'{path} #{i} not found'
        src = src.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='\n').write(src)
    print('ok', path)

# ---------- P0：山贼组战败/脱战后重新 arm ----------
patch('scripts/npc/bandit_group.gd', [
    ('''func _emit_challenged() -> void:
	challenged.emit()''',
     '''func _emit_challenged() -> void:
	challenged.emit()


## 重新武装（P0：战败/撤退不是结局，遭遇不得一次性死掉）。
## 玩家仍在警戒圈内时不立即复位，免得战败瞬间原地重开。
func rearm() -> void:
	await get_tree().create_timer(1.0).timeout
	_triggered = false'''),
])

patch('scripts/main.gd', [
    ('''	_challenged = null
	if is_instance_valid(_battle):''',
     '''	# P0：战败/脱战——山贼留在世界，警戒圈重新武装，可再战。
	if not player_won and _challenged != null:
		_challenged.rearm()
	_challenged = null
	if is_instance_valid(_battle):'''),
])

# ---------- P1：主将攻击动作代际 + 横扫朝向快照 ----------
patch('scripts/player.gd', [
    ('''var _attack_cd := 0.0
var _facing := Vector2.RIGHT
var _attack_anim_left := 0.0''',
     '''var _attack_cd := 0.0
var _facing := Vector2.RIGHT
var _attack_anim_left := 0.0
var _action_gen := 0        # 战斗动作代际：横扫覆盖普攻时作废旧回调（评审）
var _attack_facing := Vector2.RIGHT  # 出手瞬间朝向快照（弧光与伤害同读）'''),
    ('''		if _attack_cd <= 0.0:
			var target := _nearest_bandit(ATTACK_RANGE)
			if target != null:
				_attack_cd = ATTACK_COOLDOWN
				_play_attack_anim(target.global_position - global_position)
				Sfx.play(Sfx.SWING)
				var dmg_from := global_position
				_anim.attack_peak.connect(func() -> void:
					if alive and is_instance_valid(target) and target.alive \\
							and global_position.distance_to(target.global_position) \\
									<= ATTACK_RANGE + 14.0:
						target.take_damage(ATTACK_DAMAGE, dmg_from, 60.0)
				, CONNECT_ONE_SHOT)''',
     '''		if _attack_cd <= 0.0:
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
					if alive and is_instance_valid(target) and target.alive \\
							and global_position.distance_to(target.global_position) \\
									<= ATTACK_RANGE + 14.0:
						target.take_damage(ATTACK_DAMAGE, dmg_from, 60.0, false, self)
				, CONNECT_ONE_SHOT)'''),
    ('''	skill_cd_left = SWEEP_COOLDOWN
	Sfx.play(Sfx.SWEEP)
	_play_attack_anim(_facing)
	var hit_any := false
	var from := global_position
	_anim.attack_peak.connect(func() -> void:
		for node in get_tree().get_nodes_in_group("combatants"):
			if node == self or node.team == team or not node.alive:
				continue
			var offset: Vector2 = node.global_position - from
			if offset.length() > sweep_range:
				continue
			if absf(_facing.angle_to(offset)) > SWEEP_HALF_ARC:
				continue  # angle_to 带符号：不取绝对值负半圆会漏判
			node.take_damage(SWEEP_DAMAGE, from, SWEEP_KNOCK, true)
			hit_any = true''',
     '''	skill_cd_left = SWEEP_COOLDOWN
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
			hit_any = true'''),
    ('''	var arc := Polygon2D.new()
	arc.polygon = _arc_points()
	arc.rotation = _facing.angle()''',
     '''	var arc := Polygon2D.new()
	arc.polygon = _arc_points()
	arc.rotation = _attack_facing.angle()'''),
])

# ---------- P1：伤害合同传 attacker 引用，禁止坐标反查身份 ----------
patch('scripts/battle/unit.gd', [
    ('''func take_damage(amount: int, from_pos: Vector2, knock: float, is_skill := false) -> void:
	if not alive:
		return
	var dmg := maxi(1, amount - int(stats.get("armor", 0)))
	var to_attacker := (from_pos - global_position).normalized()
	var frontal := facing.dot(to_attacker) > 0.5
	var attacker: BattleUnit = battle.unit_at(from_pos)
	var distracted := _target != null and attacker != null and attacker != _target''',
     '''func take_damage(amount: int, from_pos: Vector2, knock: float, is_skill := false,
		attacker: Node2D = null) -> void:
	if not alive:
		return
	var dmg := maxi(1, amount - int(stats.get("armor", 0)))
	var to_attacker := (from_pos - global_position).normalized()
	var frontal := facing.dot(to_attacker) > 0.5
	# 攻击者由调用方直传（评审：坐标反查在密集战线会认错人）
	var attacker_unit: BattleUnit = attacker as BattleUnit
	var distracted := _target != null and attacker != null and attacker != _target'''),
    ('''	if hold_order and bool(stats.get("brace", false)) and frontal:
		if attacker != null and attacker.charge_left > 0.0:
			attacker.take_damage(int(stats.get("damage", 6)) + 4, global_position, 90.0)''',
     '''	if hold_order and bool(stats.get("brace", false)) and frontal:
		if attacker_unit != null and attacker_unit.charge_left > 0.0:
			attacker_unit.take_damage(int(stats.get("damage", 6)) + 4, global_position, 90.0, false, self)'''),
    ('''		Sfx.play(Sfx.SWING)
		target.take_damage(dmg, from, knock)''',
     '''		Sfx.play(Sfx.SWING)
		target.take_damage(dmg, from, knock, false, self)'''),
    ('''		battle.spawn_arrow(global_position, target, dmg, team)''',
     '''		battle.spawn_arrow(global_position, target, dmg, team, self)'''),
])

patch('scripts/battle/battle.gd', [
    ('''func spawn_arrow(from: Vector2, target: Node2D, dmg: int, team: int) -> void:''',
     '''func spawn_arrow(from: Vector2, target: Node2D, dmg: int, team: int,
		shooter: Node2D = null) -> void:'''),
    ('''	_arrows.append({"pos": spr.position, "vel": dir * ARROW_SPEED,
			"dmg": dmg, "team": team, "node": spr, "life": 1.8})''',
     '''	_arrows.append({"pos": spr.position, "vel": dir * ARROW_SPEED,
			"dmg": dmg, "team": team, "node": spr, "life": 1.8, "shooter": shooter})'''),
    ('''				u.take_damage(a.dmg, a.pos - a.vel.normalized() * 20.0, 18.0)''',
     '''				u.take_damage(a.dmg, a.pos - a.vel.normalized() * 20.0, 18.0, false, a.shooter)'''),
])

# ---------- 验收断言：分布不达标就非零退出（评审：测试须是资格门）----------
patch('tools/battle_distribution.gd', [
    ('''	print("REPORT all=", _results)''',
     '''	print("REPORT all=", _results)
	# 资格门：中位时长 30~80s、胜率 ≥40%、无超时才叫通过（评审）。
	var timeouts := 0
	for r in _results:
		if r.timeout:
			timeouts += 1
	var win_rate := float(wins) / maxf(1.0, float(_results.size()))
	var passed: bool = median >= 30.0 and median <= 80.0 \\
			and win_rate >= 0.4 and timeouts == 0
	print("REPORT verdict=", "PASS" if passed else "FAIL",
			" win_rate=", snappedf(win_rate, 0.01))
	quit(0 if passed else 1)'''),
])
print('P0/P1 BATCH OK')
