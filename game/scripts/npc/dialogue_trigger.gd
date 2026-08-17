class_name DialogueTrigger
extends Node2D
## 对话触发器（§5）：玩家近 46px 自动开对话框播下一条台词（循环轮播），
## 离开 80px 后允许下次接近再播。走远自动关闭由 DialogBox 自己负责。
## 台词由 lines_provider 动态给出（可随世界状态换稿），返回空数组 = 无话可说。

const OPEN_RADIUS := 46.0
const REOPEN_RADIUS := 80.0

var speaker := ""
var lines_provider: Callable

var _idx := 0
var _player: Node2D
var _dialog: DialogBox
var _can_open := true


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_dialog = get_tree().get_first_node_in_group("dialog_box")


func _process(_delta: float) -> void:
	if _player == null or _dialog == null:
		return
	var d: float = _player.global_position.distance_to(global_position)
	if d > REOPEN_RADIUS:
		_can_open = true
		return
	if not _can_open or d > OPEN_RADIUS or _dialog.is_showing:
		return
	# 战斗中不开 RPG 对话框（战场只用短字幕/气泡，不打断节奏）。
	if _player.get("in_battle") == true:
		return
	var lines: Array[String] = lines_provider.call()
	if lines.is_empty():
		return
	_can_open = false
	_dialog.show_lines(speaker, [lines[_idx % lines.size()]], get_parent() as Node2D)
	_idx += 1
