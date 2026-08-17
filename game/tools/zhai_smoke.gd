extends SceneTree
## 寨内山贼组冒烟：传送玩家进寨警戒圈触发战斗，直接压伤害速杀，
## 验证与官道组各自独立结算（寨组消失、官道组仍在、存档 zhai_cleared=true）。
## 运行：Godot_v4.4-stable_win64_console.exe --path game -s tools/zhai_smoke.gd

var _frames := 0
var _main: Node2D
var _player: Player
var _battle: BattleManager


func _initialize() -> void:
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_dismiss_title(_main)
	_player = _main.get_node("Player")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# 等 Main._ready 跑完再落位：寨内山贼警戒圈（zhai_chief 2016,416）。
		_player.global_position = Vector2(2016, 520)
	if _battle == null:
		for node in _main.get_children():
			if node is BattleManager:
				_battle = node
	elif _battle.active:
		# 速杀：每帧给所有黄巾单位压 50 伤害，几秒收兵。
		for node in get_nodes_in_group("combatants"):
			if node.team == 1 and node.alive:
				node.take_damage(50, _player.global_position, 0.0)
	if _frames == 600:
		var npcs := _main.get_node_or_null("NPCs")
		var groups := 0
		if npcs != null:
			for n in npcs.get_children():
				if n is BanditGroup:
					groups += 1
		print("ZHAI zhai_cleared=", _main._zhai_cleared,
				" bandits_cleared=", _main._bandits_cleared,
				" world_bandit_groups=", groups)
		# 等战后 checkpoint 落盘再验档。
	if _frames == 900:
		var f := FileAccess.open("user://saves/auto.save", FileAccess.READ)
		var data: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
		print("ZHAI save=", data)
		print("ZHAI done")
		return true
	return false


## 标题画面会暂停整树；smoke 工具直接点掉它。
## 注意：自定义 SceneTree 下 Main._ready 首帧才跑，等两帧再找标题。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
