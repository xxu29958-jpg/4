extends Node
## 暮色中原氛围层（§1）：暖暮色调 + 屏幕四角晕影 + 世界内漂移云影。
## 纹理全部程序生成，无外部素材。原则：提氛围，不压暗画面。

const WORLD_W := 60 * 64
const WORLD_H := 40 * 64
const MARGIN := 300.0

## 暖金暮色：只调色调，不降亮度。
const DUSK := Color(1.0, 0.93, 0.80)
const CLOUD_COUNT := 4

var _clouds: Array = []  # [Sprite2D, Vector2 速度]


func _ready() -> void:
	var mod := CanvasModulate.new()
	mod.color = DUSK
	add_child(mod)
	_add_vignette()
	_add_clouds()
	_add_smoke_and_birds()


func _process(delta: float) -> void:
	# 云影缓慢漂移，越出世界边距后从另一侧绕回，永续 loop。
	for c in _clouds:
		var s: Sprite2D = c[0]
		var v: Vector2 = c[1]
		s.position += v * delta
		if s.position.x > WORLD_W + MARGIN:
			s.position.x = -MARGIN
		elif s.position.x < -MARGIN:
			s.position.x = WORLD_W + MARGIN
		if s.position.y > WORLD_H + MARGIN:
			s.position.y = -MARGIN
		elif s.position.y < -MARGIN:
			s.position.y = WORLD_H + MARGIN
	# 大树树冠轻摆（skew 摆动读作风吹）。
	_sway_t += delta
	for t in get_tree().get_nodes_in_group("sway"):
		if is_instance_valid(t):
			t.skew = sin(_sway_t * 1.1 + t.position.x * 0.01) * 0.035
	# 水面微光带漂移。
	for wband in _water_bands:
		wband.position.x += 9.0 * delta
		wband.modulate.a = 0.10 + 0.06 * sin(_sway_t * 0.9 + wband.position.y)


var _sway_t := 0.0
var _water_bands: Array = []


## 生机层：炊烟（酒肆/村庄/山寨）+ 水面微光 + 过境飞鸟。
func _add_smoke_and_birds() -> void:
	var pts: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/map_points.json"))
	for key in ["tavern_door", "village_elder", "zhai_chief"]:
		if pts.has(key):
			_add_smoke(Vector2(pts[key][0], pts[key][1]) + Vector2(0, -70))
	if pts.has("river_view"):
		_add_water_sheen(Vector2(pts["river_view"][0], pts["river_view"][1]))
	_bird_timer = Timer.new()
	_bird_timer.wait_time = 7.0
	_bird_timer.autostart = true
	_bird_timer.timeout.connect(_spawn_bird)
	add_child(_bird_timer)


func _add_smoke(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.amount = 6
	p.lifetime = 3.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 14.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector2(3, -4)  # 缓升微偏，像有风
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.scale_amount_curve = _grow_curve()
	p.color = Color(0.82, 0.80, 0.76, 0.30)
	p.position = at
	p.z_index = 40
	add_child(p)


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(1, 1.0))
	return c


## 水面微光：两条横光带在水域缓慢扫过。
func _add_water_sheen(center: Vector2) -> void:
	var tex := _sheen_texture()
	for i in 2:
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.modulate = Color(0.85, 0.95, 0.9, 0.12)
		s.scale = Vector2(3.2, 0.35)
		s.rotation = -0.06
		s.position = center + Vector2(randf_range(-60, 60), -30 + i * 52)
		s.z_index = 5
		add_child(s)
		_water_bands.append(s)


func _sheen_texture() -> ImageTexture:
	var img := Image.create(128, 16, false, Image.FORMAT_RGBA8)
	for x in 128:
		for y in 16:
			var ax := 1.0 - absf(x - 64.0) / 64.0
			var ay := 1.0 - absf(y - 8.0) / 8.0
			img.set_pixel(x, y, Color(1, 1, 1, ax * ax * ay))
	return ImageTexture.create_from_image(img)


## 飞鸟：偶有三两点墨影掠过天际——世界不只是玩家的舞台。
var _bird_timer: Timer


func _spawn_bird() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var y := cam.get_screen_center_position().y + randf_range(-320.0, -140.0)
	var x0 := cam.get_screen_center_position().x - 700.0
	var flock := randi_range(2, 4)
	for i in flock:
		var b := Polygon2D.new()
		b.polygon = PackedVector2Array([Vector2(-7, 0), Vector2(0, -4),
				Vector2(7, 0), Vector2(0, 2)])
		b.color = Color(0.12, 0.10, 0.08, 0.75)
		b.position = Vector2(x0 - i * 26.0, y + randf_range(-14.0, 14.0))
		b.z_index = 90
		add_child(b)
		var tw := b.create_tween()
		var dur := randf_range(9.0, 12.0)
		tw.set_parallel()
		tw.tween_property(b, "position:x", b.position.x + 1500.0, dur)
		tw.tween_property(b, "position:y", b.position.y + randf_range(-50.0, 30.0), dur)
		tw.chain().tween_callback(b.queue_free)


## 四角晕影：径向渐变 TextureRect 铺满屏幕，UI 层之下（UI 已提到 layer 2）。
func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.texture = _vignette_texture()
	layer.add_child(rect)


func _vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.10, 0.06, 0.03, 0.42))
	g.add_point(0.62, Color(0, 0, 0, 0))  # 中心 62% 半径内完全通透
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 1024
	gt.height = 640
	return gt


## 云影：几块巨大半透明柔边暗斑，世界坐标系内漂移。
func _add_clouds() -> void:
	var tex := _blob_texture(192)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18404
	for i in CLOUD_COUNT:
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.modulate = Color(0.10, 0.12, 0.16, 0.16)  # 冷青灰，低透明
		s.z_index = 30  # 压地面与角色（云的影子），低于战斗星爆
		var sc := rng.randf_range(3.5, 5.5)
		s.scale = Vector2(sc * rng.randf_range(1.2, 1.6), sc)
		s.rotation = rng.randf_range(0.0, TAU)
		s.position = Vector2(rng.randf_range(0.0, WORLD_W), rng.randf_range(0.0, WORLD_H))
		add_child(s)
		var dir := 1.0 if i % 2 == 0 else -1.0
		_clouds.append([s, Vector2(rng.randf_range(6.0, 14.0),
				rng.randf_range(2.0, 5.0)) * dir])


## 柔边圆斑纹理：alpha 二次衰减，边缘零硬边。
func _blob_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
