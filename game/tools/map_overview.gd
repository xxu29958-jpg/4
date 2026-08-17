extends SceneTree
## 全图俯瞰验证：拉远相机到地图中心，一屏看全 §2 手工地图布局。
## 运行：Godot_v4.4-stable_win64_console.exe --path game -s tools/map_overview.gd

const SHOT_PATH := "C:/Users/Xy172/Documents/kimi/workspace/乱世行/测试截图/map_overview.png"

var _frames := 0


func _initialize() -> void:
	# 清档：俯瞰构图确定，不受存档恢复影响。
	DirAccess.remove_absolute("user://saves/auto.save")
	DirAccess.remove_absolute("user://saves/pre_battle.save")
	var main: Node2D = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_dismiss_title(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# 等 Main._ready 跑完再抢相机（_ready 会按出生点重置玩家位置）。
		var player := root.get_node("Main/Player") as Node2D
		player.position = Vector2(1920, 1280)  # 地图中心（60×40×64）
		var camera := player.get_node("Camera2D") as Camera2D
		camera.zoom = Vector2(0.27, 0.27)
		camera.position_smoothing_enabled = false
		root.get_node("Main/UI").visible = false  # 俯瞰图不挡寨区
		root.get_node("Main")._fresh_start = false  # 俯瞰只要地图，不播开场会战
	if _frames == 60:
		# 等标题淡出完（约 32 帧）、开场会战未生成（约 104 帧）的干净窗口。
		var player := root.get_node("Main/Player") as Node2D
		var camera := player.get_node("Camera2D") as Camera2D
		print("OVERVIEW player=", player.global_position,
				" cam_screen_center=", camera.get_screen_center_position())
		root.get_viewport().get_texture().get_image().save_png(SHOT_PATH)
		print("OVERVIEW shot=", SHOT_PATH)
		return true
	return false


## 标题画面会暂停整树；smoke 工具直接点掉它并立即隐藏（不等淡出）。
## 注意：自定义 SceneTree 下 Main._ready 首帧才跑，等两帧再找标题。
func _dismiss_title(m: Node) -> void:
	await process_frame
	await process_frame
	for child in m.get_children():
		if child is TitleScreen:
			child.begin()
			child.visible = false
