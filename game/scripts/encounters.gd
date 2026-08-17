extends Node2D
## 遭遇编排（§5 遭遇链）：从 main.gd 抽出的世界内遭遇摆放。
## 点位全部来自 data/map_points.json：
##   村民路口招手 → 官道山贼拦商队（活着时商队被拦停）
##   → 战胜后商队通行、酒肆传闻客出现；废营地宝物闪光（长柄旧刀）。
## 寨内第二组山贼（8 人，寨旗下），与官道组各自独立结算。
## 对话（§3/§5）：传闻客开场即在酒肆门口讲时局，台词随世界状态换稿；
## 村民/商队老板走近自动开底部对话框（DialogueTrigger 轮播）。

signal bandits_challenged(group: BanditGroup)
signal old_blade_picked

const POINTS_PATH := "res://data/map_points.json"

var road_bandits: BanditGroup
var zhai_bandits: BanditGroup
var sparkle: TreasureSparkle

var _caravan: Caravan
var _rumor_spawned := false
var _merchant_thanked := false
var _pts: Dictionary = {}


## 摆放全部世界遭遇；节点名由 Main 定为 "NPCs"（兼容旧 smoke 工具）。
func populate() -> void:
	_pts = JSON.parse_string(FileAccess.get_file_as_string(POINTS_PATH))
	# 村民在路口招手；走近告知山贼劫商队，再近告知绕林小路。
	var villager := WavingVillager.new()
	villager.position = point("villager_crossroad")
	add_child(villager)
	_add_dialogue(villager, "村民", func() -> Array[String]:
		return [
			"壮士留步！前面官道有一伙黄巾余孽拦路，张家的商队刚被扣下……求壮士出手相救！",
			"想绕开就走北边林子里的小路，当心脚下。",
		])
	# 山贼堵官道（村庄方向），进入警戒圈开战。
	road_bandits = _make_bandit_group(point("bandit_block"), 3)
	# 寨内第二组山贼：8 人守在寨旗下，独立结算。
	zhai_bandits = _make_bandit_group(point("zhai_chief"), 8)
	# 商队沿官道真实移动：路径点 + 逆序回程 = 全程在路上往返；
	# 山贼活着会被拦停（遭遇链互咬）。
	_caravan = Caravan.new()
	var wps: Array[Vector2] = []
	for p in _pts["caravan_waypoints"]:
		wps.append(Vector2(p[0], p[1]))
	var route: Array[Vector2] = wps.duplicate()
	for i in range(wps.size() - 2, 0, -1):
		route.append(wps[i])
	_caravan.setup(route)
	_caravan.set_blocker(road_bandits)
	add_child(_caravan)
	# 商队老板：被拦时呼救；山贼清除后首次靠近道谢。
	_add_dialogue(_caravan, "商队老板", _merchant_lines)
	# 废营地宝物闪光：长柄旧刀。
	sparkle = TreasureSparkle.new()
	sparkle.position = point("treasure_ruins")
	sparkle.picked_up.connect(func() -> void: old_blade_picked.emit())
	add_child(sparkle)
	# 传闻客开场即在酒肆门口讲时局（台词随世界状态换稿）。
	spawn_rumor_drinker()


## 酒肆传闻：传闻客在酒肆门口讲时局，台词反映世界状态（三阶段换稿）。
## 官道山贼清除后由 main.gd 再调一次（幂等），保证传闻回响成立。
func spawn_rumor_drinker() -> void:
	if _rumor_spawned:
		return
	_rumor_spawned = true
	var drinker := RumorDrinker.new()
	drinker.position = point("rumor_drinker")
	add_child(drinker)
	_add_dialogue(drinker, "传闻客", _rumor_lines)


## 传闻客台词：阶段0（山贼未清）两条轮播；阶段1（官道已清）；
## 阶段2（寨也破）。
func _rumor_lines() -> Array[String]:
	if road_bandits != null:
		return [
			"光和七年，黄巾四起……长社打得凶，这官道上也不太平喽。",
			"东边官道出了一伙剪径的，打着黄巾旗号，商队都不敢过咯。",
		]
	if zhai_bandits != null:
		return ["听说了吗？有位游侠挑了官道那伙贼人，跑商的都回来啦！"]
	return ["北山贼寨都让人端了……颍川这是要出大人物啊。"]


## 商队老板台词：被拦停时呼救；山贼清除后首次靠近道谢（之后无话）。
func _merchant_lines() -> Array[String]:
	if _caravan._held:
		return ["好汉救我！货都被这些贼人扣了……"]
	if road_bandits == null and not _merchant_thanked:
		_merchant_thanked = true
		return ["多谢壮士救命之恩！回阳翟我逢人便讲你的义举！"]
	return []


## 给 NPC 挂对话触发器（近 46px 自动开对话框，轮播台词）。
func _add_dialogue(npc: Node2D, speaker: String, provider: Callable) -> void:
	var trigger := DialogueTrigger.new()
	trigger.speaker = speaker
	trigger.lines_provider = provider
	npc.add_child(trigger)


## 战斗胜利结算：移除对应山贼组（官道组 / 寨内组互不影响）。
func clear_bandits(group: BanditGroup) -> void:
	if group == null:
		return
	if group == road_bandits:
		road_bandits = null
	if group == zhai_bandits:
		zhai_bandits = null
	group.queue_free()


## 读档恢复：宝物已拾取则移除闪光。
func remove_sparkle() -> void:
	if is_instance_valid(sparkle):
		sparkle.queue_free()
	sparkle = null


## map_points.json 点位（像素坐标）。
func point(key: String) -> Vector2:
	var a: Array = _pts[key]
	return Vector2(a[0], a[1])


func _make_bandit_group(at: Vector2, count: int) -> BanditGroup:
	var g := BanditGroup.new()
	g.member_count = count
	g.position = at
	g.challenged.connect(func() -> void: bandits_challenged.emit(g))
	add_child(g)
	return g
