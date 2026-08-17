extends SceneTree
## 战斗时长分布统计（§7.4：验收看 20 场分布，不看单场）。
##
## 随机化 bot 模拟真人差异：接近距离、撤退血量阈值、军令间隔、
## 横扫时机全部带抖动。每场全新 Main 实例、清档重来。
## headless 运行：Godot --headless --path luanshixing-m0 -s tools/battle_distribution.gd

const BATTLES := 20
const MAX_FRAMES := 5400  # 90 秒游戏时间封顶
const PLAYER_HP := 60

var _rng := RandomNumberGenerator.new()
var _battle_idx := -1
var _frames := 0
var _main: Node2D
var _player: Player
var _battle: BattleManager
var _battle_start_frame := 0
var _results: Array[Dictionary] = []

# 每场随机参数
var _engage_dist := 85.0
var _retreat_hp := 15.0
var _rally_interval := 120
var _retreat_left := 0


func _initialize() -> void:
	Engine.max_fps = 60  # 锁定后帧数=真实 60Hz 游戏时间
	_rng.seed = 184184
	_next_battle()


func _next_battle() -> void:
	if _main != null:
		_main.queue_free()
	_wipe_saves()
	_battle_idx += 1
	if _battle_idx >= BATTLES:
		_report()
		# 通过返回值无法退出，置帧数到收尾分支。
		_frames = -1
		return
	_engage_dist = _rng.randf_range(70.0, 100.0)
	_retreat_hp = _rng.randf_range(0.0, 30.0)
	_rally_interval = _rng.randi_range(60, 200)
	_retreat_left = 0
	_battle = null
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_dismiss_title(_main)
	_player = _main.get_node("Player")
	_frames = 0
	print("RUN battle=", _battle_idx + 1, " engage=", snappedf(_engage_dist, 0.1),
			" retreat_hp=", snappedf(_retreat_hp, 0.1))


func _wipe_saves() -> void:
	for f in ["auto.save", "pre_battle.save"]:
		if FileAccess.file_exists("user://saves/" + f):
			DirAccess.remove_absolute("user://saves/" + f)


func _process(_delta: float) -> bool:
	if _frames < 0:
		return true  # 全部打完，退出。
	_frames += 1
	if _frames == 2:
		# 等 Main._ready 跑完再落位（_ready 会按出生点重置玩家位置）。
		# 直接落位官道山贼警戒圈边（bandit_block 2336,1568，省跑路时间）。
		_player.global_position = Vector2(2336 - 160, 1568)
	if _battle == null:
		_battle = _find_battle()
		if _battle != null:
			_battle_start_frame = _frames
			_battle.battle_ended.connect(_on_battle_ended)
	else:
		_bot_play()
	if _frames >= MAX_FRAMES:
		_record(false, true)
		_next_battle()
	return false


## 拟人 bot：打带跑——平时吊在本方阵线侧翼，横扫冷却好就突进横扫、
## 立刻撤回阵后；低血长跑；军令按各自节奏。
func _bot_play() -> void:
	if not _battle.active:
		return
	var nearest := _nearest_bandit()
	var anchor := _own_line_anchor()
	if nearest != null:
		var to: Vector2 = nearest.global_position - _player.global_position
		if _retreat_left > 0:
			# 撤回本方阵线后。
			_retreat_left -= 1
			var back: Vector2 = (anchor - _player.global_position)
			if back.length() > 30.0:
				_player.global_position += back.normalized() * 4.0
		elif _player.hp <= _retreat_hp:
			_retreat_left = 300
		elif _player.skill_cd_left <= 0.0 and to.length() < 150.0:
			# 突进：冲到横扫射程内。
			_player.global_position += to.normalized() * 4.0
		elif to.length() < 70.0:
			# 没技能时绝不站桩挨刀。
			_player.global_position -= to.normalized() * 4.0
		elif to.length() > 200.0:
			# 够不着就往战场走（站桩会被判脱战）。
			_player.global_position += to.normalized() * 3.0
		elif (anchor - _player.global_position).length() > 130.0:
			# 闲暇时贴着本方阵线，不掉单。
			_player.global_position += (anchor - _player.global_position).normalized() * 3.0
	if _frames % _rally_interval == 0:
		_player.use_rally()
	if _player.skill_cd_left <= 0.0:
		_player.use_sweep()
		if _player.skill_cd_left > 0.0:
			_retreat_left = maxi(_retreat_left, 50)  # 横扫出手立即撤回阵后


## 本方阵线质心（bot 的"安全区"参照）。
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


func _on_battle_ended(player_won: bool) -> void:
	_record(player_won, false)
	_battle = null
	# 等收尾动画播完再开下一场。
	call_deferred("_deferred_next")


func _deferred_next() -> void:
	_next_battle()


func _record(player_won: bool, timeout: bool) -> void:
	var duration := snappedf((_frames - _battle_start_frame) / 60.0, 0.1)
	_results.append({
		"won": player_won,
		"timeout": timeout,
		"duration_s": duration,
		"player_hp": _player.hp,
	})
	print("RUN result won=", player_won, " dur=", duration, "s hp=", _player.hp,
			" timeout=", timeout)


func _report() -> void:
	var wins := 0
	var durations: Array[float] = []
	for r in _results:
		if r.won:
			wins += 1
		if not r.timeout:
			durations.append(r.duration_s)
	durations.sort()
	var median := durations[durations.size() / 2] if not durations.is_empty() else -1.0
	print("REPORT battles=", _results.size(), " wins=", wins,
			" median_s=", median, " min=", durations.front() if not durations.is_empty() else -1,
			" max=", durations.back() if not durations.is_empty() else -1)
	print("REPORT all=", _results)
	# 资格门：中位时长 30~80s、胜率 ≥40%、无超时才叫通过（评审）。
	var timeouts := 0
	for r in _results:
		if r.timeout:
			timeouts += 1
	var win_rate := float(wins) / maxf(1.0, float(_results.size()))
	var passed: bool = median >= 30.0 and median <= 80.0 \
			and win_rate >= 0.4 and timeouts == 0
	print("REPORT verdict=", "PASS" if passed else "FAIL",
			" win_rate=", snappedf(win_rate, 0.01))
	quit(0 if passed else 1)


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
	for node in _main.get_children():
		if node is BattleManager:
			return node
	return null


## 标题画面会暂停整树；smoke 工具直接点掉它。
## 注意：自定义 SceneTree 下 Main._ready 首帧才跑，等两帧再找标题。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
