extends SceneTree
## 存档 + 拾取冒烟：
##   第一次运行（无存档）：移动玩家到 (1000,1088)，等防抖落盘后退出。
##   第二次运行（有存档）：验证原地恢复，再把玩家传到宝物点验证拾取。
## 运行：Godot_v4.4-stable_win64_console.exe --path luanshixing-m0 -s tools/save_smoke.gd

var _frames := 0
var _player: Player
var _main: Node2D
var _had_save := false


func _initialize() -> void:
	# 先看盘上有没有档（在实例化场景之前）。
	var probe := SaveSystem.new()
	var data := probe.load_latest()
	_had_save = not data.is_empty()
	probe.free()
	print("SAVE had_save=", _had_save)

	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	_dismiss_title(_main)
	_player = _main.get_node("Player")


func _process(_delta: float) -> bool:
	_frames += 1
	if _had_save:
		# 第二轮：恢复应在 _ready 完成。
		if _frames == 5:
			print("SAVE restored_pos=", _player.global_position)
			# 传到宝物点验证拾取链（treasure_ruins 544,416）。
			_player.global_position = Vector2(544, 416)
		if _frames == 60:
			print("SAVE has_old_blade=", _player.has_old_blade,
					" sweep_range=", _player.sweep_range)
			return true
	else:
		# 第一轮：挪位置（官道上），等防抖（4s ≈ 240 帧）触发 auto 档。
		if _frames == 5:
			_player.global_position = Vector2(1200, 1568)
		if _frames == 320:
			print("SAVE auto_exists=",
					FileAccess.file_exists("user://saves/auto.save"))
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
