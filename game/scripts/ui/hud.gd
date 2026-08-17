class_name Hud
extends CanvasLayer
## HUD（§3）：探索态=左上主将血条（绿→红渐变）；战斗态追加顶部双方士气条
## （左青右赭黄，各带小旗，<30 闪烁）与双方存活数。
## main.gd 在战斗开始时 bind_battle()（接 morale_changed），结束 unbind_battle()。

const FONT_BOLD := preload("res://assets/fonts/NotoSansCJKsc-Bold.otf")

const BAR_W := 330.0
const BAR_H := 16.0
const TOP_Y := 14.0
const GAP := 56.0  # 两条士气条之间的空隙（放对阵字）

const COLOR_PLAYER := Color(0.30, 0.72, 0.72)   # 汉军青
const COLOR_BANDIT := Color(0.80, 0.58, 0.20)   # 黄巾赭黄

var _player: Player
var _battle: BattleManager
var _morale := {0: 100.0, 1: 100.0}
var _blink_t := 0.0

var _canvas: HudCanvas
var _hp_label: Label
var _ally_label: Label
var _enemy_label: Label


## 绘图层：所有血条/士气条在 NOTIFICATION_DRAW 里画。
class HudCanvas:
	extends Control
	var hud: Hud

	func _draw() -> void:
		if hud != null:
			hud.draw_on(self)


func _ready() -> void:
	layer = 4
	_player = get_tree().get_first_node_in_group("player")
	_canvas = HudCanvas.new()
	_canvas.hud = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_hp_label = _make_label("主将", 20, 16, 12)
	_ally_label = _make_label("", 18, 254, 34)
	_enemy_label = _make_label("", 18, 906, 34)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label.size.x = 120
	for l in [_ally_label, _enemy_label]:
		l.visible = false


func _make_label(text: String, font_size: int, x: float, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_BOLD)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.93, 0.89, 0.80))
	l.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.06, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(x, y)
	_canvas.add_child(l)
	return l


## 战斗开始：接管士气显示。
func bind_battle(bm: BattleManager) -> void:
	unbind_battle()
	_battle = bm
	_morale = {0: bm.morale[0], 1: bm.morale[1]}
	bm.morale_changed.connect(_on_morale_changed)
	for l in [_ally_label, _enemy_label]:
		l.visible = true


## 战斗结束：回到探索态。
func unbind_battle() -> void:
	if _battle != null and _battle.morale_changed.is_connected(_on_morale_changed):
		_battle.morale_changed.disconnect(_on_morale_changed)
	_battle = null
	for l in [_ally_label, _enemy_label]:
		l.visible = false


func _on_morale_changed(team: int, value: float) -> void:
	_morale[team] = value


func _process(delta: float) -> void:
	_blink_t += delta
	if _battle != null and is_instance_valid(_battle):
		_ally_label.text = "乡勇 %d" % _battle.alive_count(0)
		_enemy_label.text = "贼 %d" % _battle.alive_count(1)
	_canvas.queue_redraw()


## 由 HudCanvas._draw 回调：画血条 + （战斗中）双士气条。
func draw_on(c: Control) -> void:
	_draw_hp_bar(c)
	if _battle != null:
		_draw_morale_bar(c, true)
		_draw_morale_bar(c, false)


func _draw_hp_bar(c: Control) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pos := Vector2(16, 38)
	var size := Vector2(220, 14)
	var frac: float = clampf(_player.hp / float(Player.MAX_HP), 0.0, 1.0)
	c.draw_rect(Rect2(pos - Vector2(2, 2), size + Vector2(4, 4)),
			Color(0.10, 0.08, 0.06, 0.85))
	c.draw_rect(Rect2(pos, size), Color(0.05, 0.05, 0.04, 0.9))
	if frac > 0.0:
		# 绿 → 红 随血量渐变。
		var fill := Color(0.85, 0.25, 0.18).lerp(Color(0.35, 0.78, 0.30), frac)
		c.draw_rect(Rect2(pos, Vector2(size.x * frac, size.y)), fill)
	c.draw_rect(Rect2(pos - Vector2(2, 2), size + Vector2(4, 4)),
			Color(0.788, 0.635, 0.153, 0.9), false, 2.0)
	_hp_label.text = "主将 %d" % maxi(0, _player.hp)


## 顶部双士气条：is_left=乡勇（左，青色，左起填），否则黄巾（右，赭黄，右起填）。
func _draw_morale_bar(c: Control, is_left: bool) -> void:
	var team := 0 if is_left else 1
	var color: Color = COLOR_PLAYER if is_left else COLOR_BANDIT
	var value: float = clampf(_morale[team] / BattleManager.MORALE_START, 0.0, 1.0)
	# <30 崩溃边缘：整条闪烁告警。
	if _morale[team] < BattleManager.MORALE_ROUT:
		color.a = 0.45 + 0.55 * absf(sin(_blink_t * 6.0))
	var center_x := 1280.0 / 2.0
	var bar_x := center_x - GAP - BAR_W if is_left else center_x + GAP
	var rect := Rect2(bar_x, TOP_Y, BAR_W, BAR_H)
	c.draw_rect(rect.grow(2), Color(0.10, 0.08, 0.06, 0.85))
	c.draw_rect(rect, Color(0.05, 0.05, 0.04, 0.9))
	var fill_w := BAR_W * value
	var fill_rect := Rect2(bar_x, TOP_Y, fill_w, BAR_H) if is_left \
			else Rect2(bar_x + BAR_W - fill_w, TOP_Y, fill_w, BAR_H)
	if fill_w > 0.0:
		c.draw_rect(fill_rect, color)
	c.draw_rect(rect.grow(2), Color(0.788, 0.635, 0.153, 0.9), false, 2.0)
	if is_left:
		_draw_flag(c, Vector2(bar_x - 8, TOP_Y + BAR_H), color, false)
	else:
		_draw_flag(c, Vector2(bar_x + BAR_W + 8, TOP_Y + BAR_H), color, true)


## 小旗：一杆一三角，插在士气条外端。
func _draw_flag(c: Control, base: Vector2, color: Color, flip: bool) -> void:
	var top := base + Vector2(0, -30)
	c.draw_line(base, top, Color(0.85, 0.80, 0.68), 2.0)
	var dir := -1.0 if flip else 1.0
	var pts := PackedVector2Array([
		top, top + Vector2(dir * 18, 5), top + Vector2(0, 12)])
	c.draw_colored_polygon(pts, Color(color, minf(color.a + 0.2, 1.0)))
