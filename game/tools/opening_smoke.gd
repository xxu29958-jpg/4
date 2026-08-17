extends SceneTree
## 新开场冒烟：新档 → 标题 → 开场白对话（传闻客四句）→ 关闭后走向东门。
## 验证：开场白出现且可翻页、玩家可移动、区域横幅触发。
## 运行：Godot --path game -s tools/opening_smoke.gd

const SHOT_DIR := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/"

var _frames := 0
var _main: Node2D
var _player: Player
var _dialog: DialogBox


func _initialize() -> void:
	Engine.max_fps = 60
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_dismiss_title(_main)
	_player = _main.get_node("Player")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_dialog = _find_dialog()
	if _frames == 10:
		# 开场白应在标题关闭后自动出现。
		var visible := _dialog != null and _dialog.visible
		print("OPENING dialog_visible=", visible)
		_shot("opening_dialog")
	if _frames in [40, 80, 120, 140]:
		_advance_dialog()
	if _frames == 180:
		_shot("opening_world")
		print("OPENING dialog_closed=", not _dialog.visible,
				" player_can_move=", not paused)
	if _frames >= 180 and _frames < 400:
		# 模拟摇杆向右（朝东门）。
		_player.velocity = Vector2(160, 0)
		_player.move_and_slide()
	if _frames == 400:
		_shot("opening_walk")
		print("OPENING moved_x=", _player.global_position.x, " (spawn 672)")
		return true
	return false


func _find_dialog() -> DialogBox:
	for child in _main.get_children():
		if child is DialogBox:
			return child
	return null


func _advance_dialog() -> void:
	if _dialog != null and _dialog.visible:
		_dialog.advance()


func _shot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("OPENING shot=", path)


## 标题画面会暂停整树；smoke 工具直接点掉它。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
