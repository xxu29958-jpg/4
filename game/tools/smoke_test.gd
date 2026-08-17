extends SceneTree
## 冒烟测试：实例化 Main，模拟摇杆向右 2 秒，截图验证渲染管线。
## 运行：Godot_v4.4-stable_win64_console.exe --path game -s tools/smoke_test.gd

const SHOT_PATH := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/smoke.png"

var _frames := 0
var _main: Node2D
var _player: Player
var _start_pos := Vector2.ZERO


func _initialize() -> void:
	# 清档：保证出生点/世界状态确定，不受上次运行残留影响。
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_dismiss_title(_main)
	_player = _main.get_node("Player")
	_start_pos = _player.global_position


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		# 模拟方案 A：摇杆满推向右（等价于手指拖到最大半径）。
		_main.get_node("UI/Joystick")._output = Vector2.RIGHT
	if _frames == 120:
		var moved := _player.global_position.x - _start_pos.x
		print("SMOKE moved_px=", moved)
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(SHOT_PATH)
		print("SMOKE shot=", SHOT_PATH)
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
