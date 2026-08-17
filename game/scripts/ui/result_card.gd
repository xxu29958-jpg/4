class_name ResultCard
extends CanvasLayer
## 战斗结算卡（§3）：中央弹卡，点击关闭。
## 战胜=「大破贼众」+ 战果行（存活乡勇 X / 歼敌 Y）；
## 战败=「兵败」+「你被人抬回了阳翟……」。

signal dismissed

const THEME := preload("res://assets/ui/theme_main.tres")
const FONT_BOLD := preload("res://assets/fonts/NotoSansCJKsc-Bold.otf")

var _panel: Panel
var _title: Label
var _lines: Label
var _hint: Label


func _ready() -> void:
	layer = 16
	visible = false
	_panel = Panel.new()
	_panel.theme = THEME
	_panel.custom_minimum_size = Vector2(420, 220)
	_panel.size = Vector2(420, 220)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-210, -110)
	add_child(_panel)
	_title = Label.new()
	_title.add_theme_font_override("font", FONT_BOLD)
	_title.add_theme_font_size_override("font_size", 40)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(0, 22)
	_title.size = Vector2(420, 56)
	_panel.add_child(_title)
	_lines = Label.new()
	_lines.add_theme_font_size_override("font_size", 22)
	_lines.add_theme_color_override("font_color", Color(0.93, 0.89, 0.80))
	_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lines.position = Vector2(0, 96)
	_lines.size = Vector2(420, 70)
	_panel.add_child(_lines)
	_hint = Label.new()
	_hint.text = "— 点击关闭 —"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.788, 0.635, 0.153, 0.8))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, 178)
	_hint.size = Vector2(420, 26)
	_panel.add_child(_hint)


## 战果数据由 main.gd 在 battle_ended 时统计传入。
func show_result(player_won: bool, allies_left: int, enemies_slain: int,
		reward := 0) -> void:
	if player_won:
		_title.text = "大破贼众"
		_title.add_theme_color_override("font_color", Color(0.94, 0.80, 0.42))
		_lines.text = "存活乡勇 %d\n歼敌 %d\n赏钱 %d" % [allies_left, enemies_slain, reward]
	else:
		_title.text = "兵败"
		_title.add_theme_color_override("font_color", Color(0.80, 0.42, 0.34))
		_lines.text = "你被人抬回了阳翟……"
	visible = true
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var tapped: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	tapped = tapped or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	get_viewport().set_input_as_handled()
	visible = false
	dismissed.emit()
