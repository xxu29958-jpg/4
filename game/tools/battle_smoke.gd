extends SceneTree
## 战斗冒烟：把玩家传送到山贼警戒圈边触发战斗，AI 自动打，
## 定点截图 + 打印士气/兵力/结局，验证 §12.3 战斗闭环。
## 点位与新手工地图一致（bandit_block 2336,1568）。
## 运行：Godot_v4.4-stable_win64_console.exe --path game -s tools/battle_smoke.gd

const SHOT_DIR := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/"

var _frames := 0
var _player: Player
var _battle: BattleManager
var _retreat_left := 0


func _initialize() -> void:
	Engine.max_fps = 60  # 锁定后帧数=真实 60Hz 游戏时间
	# 清档：避免上次运行的存档恢复覆盖传送位置/世界状态。
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	var main: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_dismiss_title(main)
	_player = main.get_node("Player")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# 等 Main._ready 跑完再落位（_ready 会按出生点重置玩家位置）。
		# 落在官道山贼警戒圈内（bandit_block 2336,1568，AGGRO_RADIUS 190）。
		_player.global_position = Vector2(2336 - 150, 1568)
	if _battle == null:
		_battle = _find_battle()
		if _battle != null:
			_battle.battle_ended.connect(func(won: bool) -> void:
				print("BATTLE ended at t=", _frames, " player_won=", won))
	# 模拟真人玩家：贴本方阵线打带跑——横扫好了突进、出手就撤回；
	# 平时吊在阵线侧翼，不脸接七把刀；开战即冲锋军令。
	if _battle != null and _battle.active and _player.in_battle:
		var nearest := _nearest_bandit()
		var anchor := _own_line_anchor()
		if nearest != null:
			var to: Vector2 = nearest.global_position - _player.global_position
			if _retreat_left > 0:
				_retreat_left -= 1
				var back: Vector2 = anchor - _player.global_position
				if back.length() > 30.0:
					_player.global_position += back.normalized() * 4.0
			elif _player.skill_cd_left <= 0.0 and to.length() < 150.0:
				_player.global_position += to.normalized() * 4.0
			elif to.length() < 70.0:
				_player.global_position -= to.normalized() * 4.0
			elif (anchor - _player.global_position).length() > 130.0:
				_player.global_position += (anchor - _player.global_position).normalized() * 3.0
		if _frames % 90 == 0:
			_player.use_rally()
		if _player.skill_cd_left <= 0.0:
			_player.use_sweep()
			if _player.skill_cd_left > 0.0:
				_retreat_left = maxi(_retreat_left, 50)
	if _frames in [120, 600, 1200, 1800, 2400, 3000]:
		var path := SHOT_DIR + "battle_t%d.png" % _frames
		root.get_viewport().get_texture().get_image().save_png(path)
		_print_state("t=%d" % _frames)
	if _frames == 3600:
		_print_state("final")
		var npcs := _player.get_parent().get_node_or_null("NPCs")
		var bandit_left := 0
		if npcs != null:
			for n in npcs.get_children():
				if n is BanditGroup:
					bandit_left += 1
		print("BATTLE world_bandit_groups=", bandit_left)
		return true
	return false


func _own_line_anchor() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for node in get_nodes_in_group("combatants"):
		if node.team == 0 and node.alive and not node is Player:
			sum += node.global_position
			n += 1
	if n == 0:
		return _player.global_position + Vector2(-200, 0)
	return sum / n


func _nearest_bandit() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_nodes_in_group("combatants"):
		if node == _player or node.team == 0 or not node.alive:
			continue
		var dist := _player.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


func _find_battle() -> BattleManager:
	for node in _player.get_parent().get_children():
		if node is BattleManager:
			return node
	return null


func _print_state(tag: String) -> void:
	var alive := {0: 0, 1: 0}
	for node in get_nodes_in_group("combatants"):
		if node.alive and not node is Player:
			alive[node.team] += 1
	if _battle != null:
		print("BATTLE ", tag, " active=", _battle.active,
				" morale=", _battle.morale,
				" han=", alive[0], " bandit=", alive[1],
				" player_hp=", _player.hp)
	else:
		print("BATTLE ", tag, " (no battle node)")


## 标题画面会暂停整树；smoke 工具直接点掉它。
## 注意：自定义 SceneTree 下 Main._ready 首帧才跑，等两帧再找标题。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
