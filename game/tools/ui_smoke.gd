extends SceneTree
## UI 冒烟（§3/§5 验证协议）：
##   1. 清档+写入最小存档（跳过开场会战，专注 UI 验证）→ 截图标题
##   2. 模拟点击开始 → 传送张家村触发区域横幅 → 截图
##   3. 传送传闻客旁 → 自动开对话框 → 截图（中文渲染检查）
##   4. 传送官道触发战斗 → 截图 HUD（双士气条 + 战斗按钮）
##   5. 速杀山贼 → 结算卡 → 截图；全程打印 PASS 检查点。
## 运行：Godot_v4.4-stable_win64_console.exe --path game -s tools/ui_smoke.gd

const SHOT_DIR := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/"

var _frames := 0
var _main: Node2D
var _player: Player
var _title: TitleScreen
var _dialog: DialogBox
var _battle: BattleManager
var _result_card: ResultCard
var _killed := false
var _ended := false
var _result_wait := 0


func _initialize() -> void:
	# 清档。
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	# 写入最小合法存档：跳过开场会战，让 UI 截图不被会战糊住。
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open("user://saves/auto.save", FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"player_pos": [672, 1568], "has_old_blade": false,
		"bandits_cleared": false, "zhai_cleared": false, "schema_version": 1,
	}))
	f.close()
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_player = _main.get_node("Player")
	# 注意：自定义 SceneTree 下 Main._ready 首帧才跑，UI 节点要等一帧再找。


func _fetch_ui() -> void:
	for child in _main.get_children():
		if child is TitleScreen:
			_title = child
		elif child is DialogBox:
			_dialog = child
		elif child is ResultCard:
			_result_card = child


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		2:
			_fetch_ui()
			print("UI_SMOKE title_visible=", _title != null and _title.visible,
					" paused=", paused)
			if _title == null or _dialog == null or _result_card == null:
				print("UI_SMOKE FAIL ui nodes missing")
				return true
		30:
			_shot("ui_title")
			print("UI_SMOKE PASS title shot")
			_title.begin()  # 模拟点击开始
		100:
			print("UI_SMOKE unpaused=", not paused)
		160:
			# 阳翟横幅播完（~2.1s）后再传张家村，截干净的第二横幅。
			_player.global_position = Vector2(1632 + 100, 1952)
		205:
			for child in _main.get_children():
				if child is BannerToast:
					print("UI_SMOKE banner_phase=", child._phase, " title_a=", child._title.modulate.a, " title=", child._title.text, " sub=", child._sub.text)
			_shot("ui_banner")
			print("UI_SMOKE PASS banner shot")
		230:
			# 传闻客旁（rumor_drinker 800,1568）：46px 内自动开对话框。
			_player.global_position = Vector2(800 - 36, 1568)
		400:
			print("UI_SMOKE dialog_showing=", _dialog.is_showing,
					" speaker=", _dialog._name_label.text,
					" text=", _dialog._text_label.text)
			_shot("ui_dialog")
			print("UI_SMOKE PASS dialog shot")
		420:
			# 官道山贼警戒圈（bandit_block 2336,1568，AGGRO 190）。
			_player.global_position = Vector2(2336 - 150, 1568)
	if _frames > 420 and _battle == null:
		_battle = _find_battle()
		if _battle != null:
			_battle.battle_ended.connect(func(_won: bool) -> void: _ended = true)
			print("UI_SMOKE battle_started")
	if _battle != null and not _killed and _battle.active:
		# 等战线接敌（开战 ~4s 后）再截 HUD。
		if _frames >= 680:
			_killed = true
			print("UI_SMOKE morale=", _battle.morale,
					" han_alive=", _battle.alive_count(0),
					" bandit_alive=", _battle.alive_count(1),
					" spawned=", _battle.total_spawned(1))
			_shot("ui_battle")
			print("UI_SMOKE PASS battle hud shot")
			# 速杀山贼 → 胜利 → 结算卡。
			for node in get_nodes_in_group("combatants"):
				if node.team == 1 and node.alive:
					node.take_damage(999, _player.global_position, 0.0)
	if _ended:
		# 等几帧让视口把结算卡渲染出来再截。
		_result_wait += 1
		if _result_wait == 10:
			print("UI_SMOKE result_visible=", _result_card.visible,
					" title=", _result_card._title.text,
					" lines=", _result_card._lines.text)
			_shot("ui_result")
			print("UI_SMOKE PASS result card shot")
			print("UI_SMOKE done")
			return true
	return false


func _find_battle() -> BattleManager:
	for node in _main.get_children():
		if node is BattleManager:
			return node
	return null


func _shot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("UI_SMOKE shot=", path)
