# -*- coding: utf-8 -*-
def patch(path, subs):
    src = open(path, encoding='utf-8').read()
    for i, (old, new) in enumerate(subs):
        assert old in src, f'{path} #{i} not found'
        src = src.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='\n').write(src)
    print('ok', path)

patch('scripts/battle/battle.gd', [
    ('''var _quiet := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}  # 各队无士气损伤的秒数''',
     '''var _quiet := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}  # 各队无士气损伤的秒数
var _now := 0.0  # 战斗内计时（军令统一结束时刻用）
var _order_gen := {TEAM_PLAYER: 0, TEAM_BANDIT: 0}  # 军令代际（防延迟协程复活旧令）
var _charge_end := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}'''),
    ('''	for team_id in _charge_cd:
		_charge_cd[team_id] = maxf(0.0, _charge_cd[team_id] - delta)''',
     '''	_now += delta
	for team_id in _charge_cd:
		_charge_cd[team_id] = maxf(0.0, _charge_cd[team_id] - delta)'''),
    ('''	_charge_cd[team_id] = CHARGE_COOLDOWN
	order[team_id] = "charge"
	# 指令传播：按离主将/阵前的距离次第接到号令，冲锋像浪滚过阵线。
	var units := _alive_units(team_id)
	units.sort_custom(func(a, b): return a.slot.x < b.slot.x 			if team_id == TEAM_PLAYER else a.slot.x > b.slot.x)
	var i := 0
	for u in units:
		if not u.fleeing:
			_charge_delayed(u, i * 0.07)
			i += 1
	Sfx.play(Sfx.RALLY)
	order_changed.emit(team_id, "charge")
	await get_tree().create_timer(CHARGE_DURATION).timeout
	if not _over and order[team_id] == "charge":
		order[team_id] = "none"
		order_changed.emit(team_id, "none")''',
     '''	_charge_cd[team_id] = CHARGE_COOLDOWN
	order[team_id] = "charge"
	_order_gen[team_id] += 1
	var gen: int = _order_gen[team_id]
	_charge_end[team_id] = _now + CHARGE_DURATION  # 统一结束时刻：
	# 晚接到号令的单位不白赚时长（评审：尾部单位冲锋曾拖到 ~6s）
	var units := _alive_units(team_id)
	units.sort_custom(func(a, b): return a.slot.x < b.slot.x 			if team_id == TEAM_PLAYER else a.slot.x > b.slot.x)
	var i := 0
	for u in units:
		if not u.fleeing:
			_charge_delayed(u, i * 0.07, gen)
			i += 1
	Sfx.play(Sfx.RALLY)
	order_changed.emit(team_id, "charge")
	await get_tree().create_timer(CHARGE_DURATION).timeout
	if not _over and order[team_id] == "charge" and _order_gen[team_id] == gen:
		order[team_id] = "none"
		order_changed.emit(team_id, "none")'''),
    ('''func _charge_delayed(u: BattleUnit, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if _over or not is_instance_valid(u) or not u.alive or u.fleeing:
		return
	u.charge_left = CHARGE_DURATION
	u.hold_order = false
	Combatant.spawn_dust(self, u.global_position + Vector2(0, 6), 2)''',
     '''func _charge_delayed(u: BattleUnit, delay: float, gen: int) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# 代际校验：玩家中途改令（稳守/再冲锋）时，旧令的延迟协程不得复活。
	if _over or _order_gen[u.team] != gen or order[u.team] != "charge":
		return
	if not is_instance_valid(u) or not u.alive or u.fleeing:
		return
	u.charge_left = maxf(0.0, _charge_end[u.team] - _now)
	u.hold_order = false
	Combatant.spawn_dust(self, u.global_position + Vector2(0, 6), 2)'''),
    ('''func hold_team(team_id: int) -> void:
	if not active or _over:
		return
	order[team_id] = "hold"''',
     '''func hold_team(team_id: int) -> void:
	if not active or _over:
		return
	order[team_id] = "hold"
	_order_gen[team_id] += 1  # 作废旧冲锋的未醒协程'''),
    ('''	var best: Node2D = null
	var best_score := max_dist''',
     '''	var best: Node2D = null
	var best_score := INF  # 距离合法性只看 d<=max_dist；score 只用于排序（评审）'''),
    ('''## 结算只读：本方当前存活单位数（UI/战果统计用）。
func alive_count(team_id: int) -> int:
	return _alive_units(team_id).size()''',
     '''## 结算只读：本方当前存活单位数（UI/战果统计用）。
func alive_count(team_id: int) -> int:
	return _alive_units(team_id).size()


## 活单位每物理帧缓存一次（评审：热路径 filter 分配 churn）。
var _alive_cache := {}
var _alive_frame := -1'''),
    ('''func _alive_units(team_id: int) -> Array:
	return _units[team_id].filter(func(u) -> bool:
		return is_instance_valid(u) and u.alive)''',
     '''func _alive_units(team_id: int) -> Array:
	var f: int = Engine.get_physics_frames()
	if f != _alive_frame:
		_alive_frame = f
		for t in _units:
			_alive_cache[t] = _units[t].filter(func(u) -> bool:
				return is_instance_valid(u) and u.alive)
	return _alive_cache.get(team_id, [])'''),
])

patch('scripts/main.gd', [
    ('''	_save.mark_dirty(_canonical_snapshot())
	_save.flush(SaveSystem.SLOT_AUTO)
	_result_card.show_result(player_won, allies_left, enemies_slain)
	if not player_won:
		_result_card.dismissed.connect(_on_defeat_dismissed, CONNECT_ONE_SHOT)''',
     '''	# 战败：canonical 先落定（抬回阳翟）再弹卡——卡片只是投影。
	# 评审：玩家在结算卡期间杀进程，下次必须已在阳翟，而不是战场上。
	if not player_won:
		_player.global_position = _encounters.point("player_spawn")
		_last_saved_pos = _player.global_position
	_save.mark_dirty(_canonical_snapshot())
	_save.flush(SaveSystem.SLOT_AUTO)
	_result_card.show_result(player_won, allies_left, enemies_slain)
	if not player_won:
		_result_card.dismissed.connect(_on_defeat_dismissed, CONNECT_ONE_SHOT)'''),
    ('''		tw.tween_callback(func() -> void:
			_player.global_position = _encounters.point("player_spawn")
			_last_saved_pos = _player.global_position
			_save.mark_dirty(_canonical_snapshot())
			_save.flush(SaveSystem.SLOT_AUTO))''',
     '''		tw.tween_callback(func() -> void:
			pass)  # 位置与存档已在 battle_ended 落定，这里只负责渐暗渐亮'''),
    ('''	if _player.global_position.distance_to(_last_saved_pos) > 8.0:
		_save.mark_dirty(_canonical_snapshot())''',
     '''	if _player.global_position.distance_to(_last_saved_pos) > 8.0:
		_save.mark_dirty(_canonical_snapshot())
		_last_saved_pos = _player.global_position  # 真防抖：标记后归零距离'''),
])
print('ALL REVIEW FIXES OK')
