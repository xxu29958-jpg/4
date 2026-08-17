extends SceneTree
## z 序遮挡专项验证：道具 z_index = 底边 y * 0.25，与玩家同标尺。
## 玩家站酒肆南侧 → 人挡房；站北侧（与精灵边缘重叠）→ 房挡人。
## 运行：Godot_v4.4-stable_win64_console.exe --path game -s tools/zcheck.gd

const SHOT_DIR := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/"
## 民居锚点 (6,22)：碰撞中心 (448,1408)，精灵底边 (448,1536) z=384。
const SOUTH_POS := Vector2(448, 1545)  # 南侧贴边：z 玩家 386 > 房 384 → 人挡房
const NORTH_POS := Vector2(390, 1430)  # 西北角贴边：z 玩家 357 < 房 384 → 房挡人

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
	(_player.get_node("Camera2D") as Camera2D).position_smoothing_enabled = false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_main._fresh_start = false  # 验证遮挡，不播开场会战
		for child in _main.get_children():
			if child is DialogBox:
				child.visible = false  # 对话框不挡画面
	if _frames == 5:
		_player.global_position = SOUTH_POS
	if _frames == 40:
		_shot("zcheck_south")
		_player.global_position = NORTH_POS
	if _frames == 75:
		_shot("zcheck_north")
		return true
	return false


func _shot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("ZCHECK shot=", path)


## 标题画面会暂停整树；smoke 工具直接点掉它并立即隐藏（不等淡出）。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
			child.visible = false
