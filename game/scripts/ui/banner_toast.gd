class_name BannerToast
extends CanvasLayer
## 进区域横幅（§3）：屏上 1/3 处大字+小字，淡入停 1.2s 淡出。
## 触发圈用 map_points.json 点位（半径 240px），每区域只播一次，
## 离开 400px 后重置可再播。淡入淡出走 _process 相位机，不依赖补间。

const FONT_BOLD := preload("res://assets/fonts/NotoSansCJKsc-Bold.otf")
const POINTS_PATH := "res://data/map_points.json"

const TRIGGER_RADIUS := 240.0
const RESET_RADIUS := 400.0
const FADE_IN := 0.35
const HOLD := 1.2
const FADE_OUT := 0.5

## 区域名 → [点位 key, 主标题, 副标题]。
const ZONES := {
	"yangzhai": ["player_spawn", "阳翟", "颍川郡治"],
	"guandao": ["bandit_block", "官道", "通往长社"],
	"linjian": ["zhai_gate", "林间小路", "北山"],
	"shanzhai": ["zhai_chief", "黄巾贼寨", "险"],
	"hewan": ["river_view", "河湾", ""],
	"cunzhuang": ["village_elder", "张家村", ""],
	"feiying": ["treasure_ruins", "废营", "有物闪光"],
}

var _player: Node2D
var _zones: Array[Dictionary] = []  # {pos, title, sub, inside}
var _phase := 0  # 0=闲置 1=淡入 2=停留 3=淡出
var _phase_t := 0.0

var _title: Label
var _sub: Label


func _ready() -> void:
	layer = 6
	_player = get_tree().get_first_node_in_group("player")
	var pts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POINTS_PATH))
	for key in ZONES:
		var z: Array = ZONES[key]
		var a: Array = pts[z[0]]
		_zones.append({
			"pos": Vector2(a[0], a[1]),
			"title": z[1], "sub": z[2],
			"inside": false,
		})
	_title = _make_label(40, Vector2(1280, 64), Vector2(0, 200))
	_sub = _make_label(22, Vector2(1280, 34), Vector2(0, 268))
	_sub.add_theme_color_override("font_color", Color(0.86, 0.81, 0.70))


func _make_label(font_size: int, size: Vector2, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT_BOLD)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.94, 0.82, 0.48))
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = size
	l.position = pos
	l.modulate.a = 0.0
	add_child(l)
	return l


func _process(delta: float) -> void:
	_track_zones()
	_tick_fade(delta)


## 区域触发：进圈播横幅（一次只播一条，播完才接新的），出 400px 重置。
func _track_zones() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for z in _zones:
		var d: float = _player.global_position.distance_to(z["pos"])
		if not z["inside"] and d < TRIGGER_RADIUS:
			z["inside"] = true
			_play(z["title"], z["sub"])
		elif z["inside"] and d > RESET_RADIUS:
			z["inside"] = false


func _tick_fade(delta: float) -> void:
	if _phase == 0:
		return
	_phase_t += delta
	match _phase:
		1:
			var a: float = minf(1.0, _phase_t / FADE_IN)
			_set_alpha(a)
			if _phase_t >= FADE_IN:
				_phase = 2
				_phase_t = 0.0
		2:
			if _phase_t >= HOLD:
				_phase = 3
				_phase_t = 0.0
		3:
			var a: float = maxf(0.0, 1.0 - _phase_t / FADE_OUT)
			_set_alpha(a)
			if _phase_t >= FADE_OUT:
				_phase = 0


func _set_alpha(a: float) -> void:
	_title.modulate.a = a
	_sub.modulate.a = a


func _play(title: String, sub: String) -> void:
	if _phase != 0:
		return  # 一次只播一条
	_title.text = title
	_sub.text = sub
	_phase = 1
	_phase_t = 0.0
