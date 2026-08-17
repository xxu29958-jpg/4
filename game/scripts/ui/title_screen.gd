class_name TitleScreen
extends CanvasLayer
## 开场标题（§3）：程序渐变暮色底（暖金→深青）+ 大字「乱世行」
## + 副题「一郡风云」+「光和七年 · 颍川」+ 底部「点击开始」。
## 标题期间整树暂停（本层 process_mode=ALWAYS，自己的补间照跑）。

signal started

const FONT_BOLD := preload("res://assets/fonts/NotoSansCJKsc-Bold.otf")

var _begun := false
var _root: Control
var _hint: Label
var _hint_t := 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# 暮色渐变底：上暖金 → 下深青。
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.83, 0.58, 0.28))
	grad.set_color(1, Color(0.10, 0.20, 0.22))
	grad.add_point(0.45, Color(0.42, 0.33, 0.28))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 16
	gt.height = 512
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(bg)
	# 底部压暗，托住「点击开始」。
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.06, 0.07, 0.35)
	shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade.custom_minimum_size = Vector2(0, 180)
	shade.size.y = 180
	shade.position.y = -180
	_root.add_child(shade)
	var title := Label.new()
	title.text = "乱世行"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.92, 0.76, 0.38))
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.05))
	title.add_theme_constant_override("outline_size", 12)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.size = Vector2(360, 140)
	title.position = Vector2(-180, -170)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	var sub := Label.new()
	sub.text = "一郡风云"
	sub.add_theme_font_override("font", FONT_BOLD)
	sub.add_theme_font_size_override("font_size", 40)
	sub.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74))
	sub.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.05))
	sub.add_theme_constant_override("outline_size", 6)
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.size = Vector2(240, 60)
	sub.position = Vector2(-120, -20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(sub)
	var date := Label.new()
	date.text = "光和七年 · 颍川"
	date.add_theme_font_size_override("font_size", 22)
	date.add_theme_color_override("font_color", Color(0.82, 0.78, 0.68))
	date.set_anchors_preset(Control.PRESET_CENTER)
	date.size = Vector2(300, 34)
	date.position = Vector2(-150, 52)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(date)
	_hint = Label.new()
	_hint.text = "点击开始"
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.size = Vector2(200, 40)
	_hint.position = Vector2(-100, -110)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)
	get_tree().paused = true


func _process(delta: float) -> void:
	if _begun:
		return
	_hint_t += delta
	_hint.modulate.a = 0.55 + 0.45 * sin(_hint_t * 2.6)


func _unhandled_input(event: InputEvent) -> void:
	var tapped: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	tapped = tapped or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		begin()


## 点击开始（smoke 工具也可直接调用以跳过标题）。
func begin() -> void:
	if _begun:
		return
	_begun = true
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		started.emit()
		queue_free())
