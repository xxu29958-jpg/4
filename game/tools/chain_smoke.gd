extends SceneTree
## 遭遇链冒烟（§5/§12.2）：
##   1. 村民靠近 → "!"气泡（告知）
##   2. 商队接近活着的山贼 → 拦停 + 警报气泡
##   3. 山贼清除后 → 酒肆门口出现传闻客，靠近冒"…"气泡
## 点位与新手工地图一致（data/map_points.json）。
## 运行：Godot --path game -s tools/chain_smoke.gd

const SHOT_DIR := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/"

var _frames := 0
var _main: Node2D
var _player: Player


func _initialize() -> void:
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_dismiss_title(_main)
	_player = _main.get_node("Player")


func _process(_delta: float) -> bool:
	_frames += 1
	# 清档会触发开场会战（城内主街）；本工具只验证遭遇链，
	# 会战一冒头就速杀清场，不让它糊住链式截图。
	var battle := _find_battle()
	if battle != null and battle.active:
		for node in get_nodes_in_group("combatants"):
			if node.team == 1 and node.alive:
				node.take_damage(50, _player.global_position, 0.0)
	match _frames:
		2:
			# 1) 村民告知：玩家到路口村民旁（villager_crossroad 1888,1440）。
			_player.global_position = Vector2(1888 - 40, 1440)
		90:
			_shot("chain_villager")
			# 2) 商队拦停：把商队搬到山贼跟前（bandit_block 2336,1568）。
			var caravan := _find_caravan()
			caravan.position = Vector2(2336 - 80, 1568)
			# 相机跟到商队：玩家也过去（但不进山贼警戒圈）。
			_player.global_position = Vector2(2336 - 250, 1568)
		150:
			var caravan := _find_caravan()
			print("CHAIN caravan_held=", caravan._held)
			_shot("chain_caravan")
			# 3) 传闻回响：模拟战斗胜利后的世界。
			_main.get_node("NPCs").spawn_rumor_drinker()
			# 玩家到酒肆门口传闻客旁（rumor_drinker 800,1568）。
			_player.global_position = Vector2(800 - 40, 1568)
		420:
			_shot("chain_rumor")
			print("CHAIN done")
			return true
	return false


func _find_battle() -> BattleManager:
	for node in _main.get_children():
		if node is BattleManager:
			return node
	return null


func _find_caravan() -> Caravan:
	for node in _main.get_node("NPCs").get_children():
		if node is Caravan:
			return node
	return null


func _shot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("CHAIN shot=", path)


## 标题画面会暂停整树；smoke 工具直接点掉它。
## 注意：自定义 SceneTree 下 Main._ready 首帧才跑，等两帧再找标题。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
