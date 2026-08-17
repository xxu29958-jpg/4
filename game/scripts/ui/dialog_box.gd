class_name DialogBox
extends CanvasLayer
## 底部对话框（§3/§5）：名字标签 + 打字机正文（30 字/秒）。
## 点击/触摸：打字中→直接显示全文；全文后→下一条；末条后→关闭。
## 非模态：打开时不暂停移动；玩家走远（>AUTO_CLOSE_RADIUS）自动关闭。

signal closed

const THEME := preload("res://assets/ui/theme_main.tres")
const FONT_BOLD := preload("res://assets/fonts/NotoSansCJKsc-Bold.otf")

const CHARS_PER_SEC := 30.0
const AUTO_CLOSE_RADIUS := 110.0

var is_showing := false

var _lines: Array[String] = []
var _idx := 0
var _anchor: Node2D
var _player: Node2D
var _typing := false

var _panel: Panel
var _name_label: Label
var _text_label: Label
var _hint_label: Label


func _ready() -> void:
	layer = 8
	add_to_group("dialog_box")
	visible = false
	_panel = Panel.new()
	_panel.theme = THEME
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(760, 132)
	_panel.size = Vector2(760, 132)
	_panel.position = Vector2(-380, -160)
	add_child(_panel)
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", FONT_BOLD)
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.92, 0.78, 0.42))
	_name_label.position = Vector2(18, 8)
	_panel.add_child(_name_label)
	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 22)
	_text_label.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82))
	_text_label.position = Vector2(18, 42)
	_text_label.size = Vector2(724, 72)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_text_label)
	_hint_label = Label.new()
	_hint_label.text = "▼"
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.788, 0.635, 0.153, 0.8))
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.position = Vector2(-32, -30)
	_panel.add_child(_hint_label)


## 播放一组台词。anchor 为说话者（走远自动关闭用），可空。
func show_lines(speaker: String, lines: Array[String], anchor: Node2D = null) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_idx = 0
	_anchor = anchor
	_player = get_tree().get_first_node_in_group("player")
	_name_label.text = speaker
	visible = true
	is_showing = true
	_show_line()


func close() -> void:
	if not is_showing:
		return
	visible = false
	is_showing = false
	_typing = false
	_anchor = null
	closed.emit()


func _show_line() -> void:
	_text_label.text = _lines[_idx]
	_text_label.visible_characters = 0
	_typing = true


func _process(delta: float) -> void:
	if not is_showing:
		return
	if _typing:
		_text_label.visible_characters += int(ceil(CHARS_PER_SEC * delta))
		if _text_label.visible_characters >= _text_label.text.length():
			_text_label.visible_characters = -1
			_typing = false
	# 走远自动关闭（以打开时的说话者为锚）。
	if _anchor != null and is_instance_valid(_anchor) and _player != null \
			and _player.global_position.distance_to(_anchor.global_position) \
					> AUTO_CLOSE_RADIUS:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not is_showing:
		return
	var tapped: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	tapped = tapped or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	get_viewport().set_input_as_handled()
	advance()


## 程序化翻页（等价于点击）：打字中→显示全文；否则下一条/关闭。
func advance() -> void:
	if not is_showing:
		return
	if _typing:
		_text_label.visible_characters = -1
		_typing = false
		return
	_idx += 1
	if _idx >= _lines.size():
		close()
	else:
		_show_line()
