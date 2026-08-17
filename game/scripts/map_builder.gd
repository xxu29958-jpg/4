extends RefCounted
## 手工蓝图装配（§2）：data/map_layout.txt 字符蓝图 → Ground/Decoration
## 两个 TileMapLayer + 道具精灵层。TileSet 运行时按 tilespec.json 图集契约构建：
## 8 列 × 3 行 × 64px，collision=true 的 tile 加全格碰撞多边形。
## 草（g / grass_auto）按确定性 hash(x,y) 在 grass1/2/3 加权随机，打破重复感。
## 锚点制道具：h/H/Z/v/c/W 不再放 deco tile，改摆 assets/props/ 手绘精灵
## （bottom-center 对齐、StaticBody2D 碰撞、z_index = 底边 y * 0.25 与角色同标尺）；
## t 松树林里确定性挑 14 棵换成 tree_big 大树精灵，其余照旧用 tile。

const SPEC_PATH := "res://data/tilespec.json"
const LAYOUT_PATH := "res://data/map_layout.txt"
const SOURCE_ID := 0
const TS := 64

const TEX_HOUSE := preload("res://assets/props/house.png")
const TEX_TAVERN := preload("res://assets/props/tavern.png")
const TEX_ZHAI := preload("res://assets/props/zhai_seat.png")
const TEX_TENT := preload("res://assets/props/tent.png")
const TEX_CAMPFIRE := preload("res://assets/props/campfire_big.png")
const TEX_WALL_H := preload("res://assets/props/wall_h.png")
const TEX_WALL_V := preload("res://assets/props/wall_v.png")
const TEX_TREE_BIG := preload("res://assets/props/tree_big.png")

## 这些字符走道具精灵，不进 deco 层。
const PROP_CHARS := ["h", "H", "Z", "v", "c", "W"]
## 松林带里改放大树精灵的棵数（hash(x,y) 最小者优先，确定性）。
const BIG_TREE_COUNT := 14

var _spec: Dictionary
var _atlas: Dictionary  # tile 名 → 图集坐标 Vector2i
var _rows: Array[String] = []
var _prop_cells: Array = []  # [[ch, Vector2i], ...] 铺格时收集，铺完统一摆
var _big_trees := {}  # Vector2i → true：改放 tree_big 的 t 格


## 入口：构建 TileSet 赋给两个 layer，再按蓝图铺格、摆道具。
func build(ground: TileMapLayer, deco: TileMapLayer) -> void:
	_spec = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	var ts := _make_tileset(int(_spec["tile_size"]))
	ground.tile_set = ts
	deco.tile_set = ts
	_load_rows()
	_select_big_trees()
	var legend: Dictionary = _spec["legend_map"]
	for y in _rows.size():
		for x in _rows[y].length():
			_place(ground, deco, legend, Vector2i(x, y), _rows[y].substr(x, 1))
	_scatter_deco(deco)
	_place_landmarks(deco)
	var props_root := Node2D.new()
	props_root.name = "Props"
	ground.get_parent().add_child(props_root)
	_place_props(props_root)
	_ground_variation(ground.get_parent())
	_scatter_decals(ground.get_parent())


## 大幅面地面色斑：960×640 噪声图 4x 放大盖全图——tile 重复感的卸妆水。
## z=2：压地面 tile，低于角色/道具；只染明暗冷暖，不挡任何细节。
func _ground_variation(root: Node) -> void:
	var s := Sprite2D.new()
	s.texture = preload("res://assets/tiles/ground_variation.png")
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.scale = Vector2(4.0, 4.0)
	s.centered = false
	s.z_index = 2
	root.add_child(s)


## 地面贴花：枯草/石子/断矛/破轮/篱笆/踩踏痕，随机旋转缩放撒在草地上。
## 程序负责"哪里有什么"，手绘贴花负责"看起来不像程序"。
const DECAL_TEXES := [
	preload("res://assets/props/decals/dry_grass.png"),
	preload("res://assets/props/decals/pebbles.png"),
	preload("res://assets/props/decals/broken_spear.png"),
	preload("res://assets/props/decals/cartwheel.png"),
	preload("res://assets/props/decals/fence.png"),
	preload("res://assets/props/decals/trample.png"),
]
const DECAL_COUNT := 64

func _scatter_decals(root: Node) -> void:
	var w := _rows[0].length()
	var h := _rows.size()
	var placed := 0
	var tries := 0
	while placed < DECAL_COUNT and tries < 3000:
		tries += 1
		var x := int(_hash01(Vector2i(tries, 3), 41) * w)
		var y := int(_hash01(Vector2i(5, tries), 43) * h)
		var ch := _rows[y].substr(x, 1)
		if ch != "g" and ch != "G" and ch != "s":
			continue
		var cell := Vector2i(x, y)
		var tex: Texture2D = DECAL_TEXES[int(_hash01(cell, 47) * 100.0) % DECAL_TEXES.size()]
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.position = _bc(cell, _hash01(cell, 51), _hash01(cell, 53))
		s.rotation = (_hash01(cell, 57) - 0.5) * 0.9
		var sc := 0.8 + _hash01(cell, 59) * 0.9
		s.scale = Vector2(sc, sc)
		s.modulate.a = 0.65 + _hash01(cell, 61) * 0.3
		s.z_index = 2
		root.add_child(s)
		placed += 1


## 运行时 TileSet：从图集契约读坐标建 TileSetAtlasSource；
## collision=true 的 tile 加全格碰撞多边形（E 门洞/水见 tilespec 定义）。
func _make_tileset(tile_size: int) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://" + String(_spec["atlas"]))
	src.texture_region_size = Vector2i(tile_size, tile_size)
	# 先挂进 TileSet：TileData 写碰撞多边形时要校验物理层存在。
	ts.add_source(src, SOURCE_ID)
	var half := tile_size / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	for tile_name in _spec["tiles"]:
		var info: Dictionary = _spec["tiles"][tile_name]
		var coords := Vector2i(int(info["xy"][0]), int(info["xy"][1]))
		src.create_tile(coords)
		_atlas[tile_name] = coords
		if info.get("collision", false):
			var td := src.get_tile_data(coords, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, square)
	return ts


## 读蓝图：跳过 # 注释行与空行。
func _load_rows() -> void:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	for line in text.split("\n", false):
		var row := line.strip_edges()
		if row.is_empty() or row.begins_with("#"):
			continue
		_rows.append(row)


## 松林带里挑 BIG_TREE_COUNT 棵改放大树：hash(x,y) 最小者，跨运行不变。
func _select_big_trees() -> void:
	var cands := []
	for y in _rows.size():
		for x in _rows[y].length():
			if _rows[y].substr(x, 1) == "t":
				var cell := Vector2i(x, y)
				cands.append([_hash01(cell, 53), cell])
	cands.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for i in mini(BIG_TREE_COUNT, cands.size()):
		_big_trees[cands[i][1]] = true


## 铺一格：legend 值 = [ground] 或 [ground, deco]。
## 道具锚点格与大树格只铺 ground，deco 由道具精灵顶替。
func _place(ground: TileMapLayer, deco: TileMapLayer, legend: Dictionary,
		cell: Vector2i, ch: String) -> void:
	if ch == "g":
		# 草：三阶灰绿加权随机，打破纯色平铺。
		ground.set_cell(cell, SOURCE_ID, _atlas[_pick_grass(cell)])
		return
	if ch in PROP_CHARS or (ch == "t" and _big_trees.has(cell)):
		_ground_only(ground, legend, cell, ch)
		_prop_cells.append([ch, cell])
		return
	if not legend.has(ch):
		return
	var entry: Array = legend[ch]
	var ground_name: String = entry[0]
	if ground_name == "grass_auto":
		ground_name = _pick_grass(cell)
	ground.set_cell(cell, SOURCE_ID, _atlas[ground_name])
	if entry.size() > 1:
		deco.set_cell(cell, SOURCE_ID, _atlas[entry[1]])


## 道具格的地面：h/H/W 按 legend 是 street，Z/v/c 是 grass_auto。
func _ground_only(ground: TileMapLayer, legend: Dictionary, cell: Vector2i, ch: String) -> void:
	var ground_name := "grass_auto"
	if legend.has(ch):
		ground_name = legend[ch][0]
	if ground_name == "grass_auto":
		ground_name = _pick_grass(cell)
	ground.set_cell(cell, SOURCE_ID, _atlas[ground_name])


## 草阶加权：grass1 主、grass2 次、grass3 点缀。
func _pick_grass(cell: Vector2i) -> String:
	var r := _hash01(cell, 0)
	if r < 0.60:
		return "grass1"
	if r < 0.87:
		return "grass2"
	return "grass3"


## 确定性 hash：同格同 salt 恒定，跨运行不变（murmur3）。
func _hash01(cell: Vector2i, salt: int) -> float:
	return float(abs(hash(Vector3i(cell.x, cell.y, salt))) % 10000) / 10000.0


# ---------------------------------------------------------------- 道具精灵

## 摆全部道具：锚点格 (x,y) → 世界坐标（64px/格），bottom-center 对齐，
## z_index 用底边 y 与玩家/战阵单位同标尺（玩家能走到房子/树后面）。
func _place_props(parent: Node2D) -> void:
	for p in _prop_cells:
		var ch: String = p[0]
		var cell: Vector2i = p[1]
		match ch:
			"h":  # 民居 2×2，锚点 = footprint 左上格
				_spawn_prop(parent, TEX_HOUSE, _bc(cell, 1.0, 2.0),
						Vector2(110, 110), _bc(cell, 1.0, 1.0))
			"H":  # 酒肆 3×2
				_spawn_prop(parent, TEX_TAVERN, _bc(cell, 1.5, 2.0),
						Vector2(170, 100), _bc(cell, 1.5, 1.0))
			"Z":  # 寨主座 2×2，同民居规则
				_spawn_prop(parent, TEX_ZHAI, _bc(cell, 1.0, 2.0),
						Vector2(110, 110), _bc(cell, 1.0, 1.0))
			"v":  # 帐篷约 1.5 格
				_spawn_prop(parent, TEX_TENT, _bc(cell, 0.5, 1.0),
						Vector2(64, 64), _bc(cell, 0.5, 0.5))
			"c":  # 篝火：无碰撞
				_spawn_prop(parent, TEX_CAMPFIRE, _bc(cell, 0.5, 1.0))
			"W":  # 城墙逐格一段：左右连 W 用横墙，否则上下连 W 用竖墙
				var tex := _wall_tex(cell)
				_spawn_prop(parent, tex, _bc(cell, 0.5, 1.0),
						Vector2(64, 64), _bc(cell, 0.5, 0.5))
			"t":  # 大树（t 格里挑出来的 14 棵）：树干小碰撞；sway 组随风轻摆
				var tree := _spawn_prop(parent, TEX_TREE_BIG, _bc(cell, 0.5, 1.0),
						Vector2(24, 20), _bc(cell, 0.5, 0.85))
				tree.add_to_group("sway")


## 格内偏移 → 世界像素（fx/fy 以格为单位）。
func _bc(cell: Vector2i, fx: float, fy: float) -> Vector2:
	return Vector2((cell.x + fx) * TS, (cell.y + fy) * TS)


## 城墙段朝向：左右邻格有 W → wall_h；否则上下邻有 W → wall_v；
## 都有优先 wall_h（拐角），都没有兜底 wall_h。
func _wall_tex(cell: Vector2i) -> Texture2D:
	var horiz := _is_char(cell + Vector2i(1, 0), "W") or _is_char(cell + Vector2i(-1, 0), "W")
	var vert := _is_char(cell + Vector2i(0, 1), "W") or _is_char(cell + Vector2i(0, -1), "W")
	if horiz or not vert:
		return TEX_WALL_H
	return TEX_WALL_V


func _is_char(cell: Vector2i, ch: String) -> bool:
	var w := _rows[0].length()
	var h := _rows.size()
	return _in_bounds(cell, w, h) and _rows[cell.y].substr(cell.x, 1) == ch


## 单个道具：精灵 bottom-center 对齐 + 可选 StaticBody2D 矩形碰撞。
## 碰撞体不参与渲染层级；精灵 z_index = int(底边 y * 0.25)。
func _spawn_prop(parent: Node2D, tex: Texture2D, bottom_center: Vector2,
		col_size := Vector2.ZERO, col_center := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.position = Vector2(bottom_center.x, bottom_center.y - tex.get_height() / 2.0)
	s.z_index = int(bottom_center.y * 0.25)
	parent.add_child(s)
	if col_size != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.position = col_center
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = col_size
		shape.shape = rect
		body.add_child(shape)
		parent.add_child(body)
	return s


# ---------------------------------------------------------------- deco 撒点

## 软化边界 + 打破网格感（§1）：水边撒芦苇，草地上稀撒草簇/碎石/花。
func _scatter_deco(deco: TileMapLayer) -> void:
	var w := _rows[0].length()
	var h := _rows.size()
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if deco.get_cell_source_id(cell) != -1:
				continue  # 已有树/栅栏等
			var ch := _rows[y].substr(x, 1)
			if ch == "s" or (ch == "g" and _adjacent(x, y, "w")):
				if _hash01(cell, 7) < 0.35:
					deco.set_cell(cell, SOURCE_ID, _atlas["reed"])
			elif ch == "g" and _hash01(cell, 13) < 0.08:
				var names := ["tuft1", "tuft2", "flower", "stone"]
				var pick: String = names[int(_hash01(cell, 29) * 100.0) % names.size()]
				deco.set_cell(cell, SOURCE_ID, _atlas[pick])


## 小道具（读蓝图定位，不写死坐标）：酒肆门口挂木牌，废营地摆营火。
func _place_landmarks(deco: TileMapLayer) -> void:
	var w := _rows[0].length()
	var h := _rows.size()
	var campfire_done := false
	for y in h:
		for x in w:
			var ch := _rows[y].substr(x, 1)
			if ch == "H":
				var sign_cell := Vector2i(x - 1, y + 1)
				if _in_bounds(sign_cell, w, h) \
						and deco.get_cell_source_id(sign_cell) == -1:
					deco.set_cell(sign_cell, SOURCE_ID, _atlas["sign"])
			elif ch == "r" and not campfire_done:
				for d in [Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 1)]:
					var c := Vector2i(x + d.x, y + d.y)
					if _in_bounds(c, w, h) and _rows[c.y].substr(c.x, 1) == "g" \
							and deco.get_cell_source_id(c) == -1:
						deco.set_cell(c, SOURCE_ID, _atlas["campfire"])
						campfire_done = true
						break


func _in_bounds(cell: Vector2i, w: int, h: int) -> bool:
	return 0 <= cell.x and cell.x < w and 0 <= cell.y and cell.y < h


## 四邻是否贴着指定字符（水边判断用）。
func _adjacent(x: int, y: int, ch: String) -> bool:
	var w := _rows[0].length()
	var h := _rows.size()
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := Vector2i(x + d.x, y + d.y)
		if _in_bounds(c, w, h) and _rows[c.y].substr(c.x, 1) == ch:
			return true
	return false
