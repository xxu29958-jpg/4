extends Node2D
## 接线层（§6 工程纪律）：建图（map_builder）→ 氛围（atmosphere）
## → 摆遭遇（encounters）→ UI（标题/HUD/对话框/横幅/结算卡）→ 存档恢复。
## 地图装配在 map_builder.gd，遭遇编排在 encounters.gd，战斗规则在 battle/。
## 启动顺序：_ready 建图/遭遇 → title_screen 置顶（暂停）→ started 后恢复，
## 无存档才播开场会战（§5 开场）。

const MapBuilder := preload("res://scripts/map_builder.gd")
const Encounters := preload("res://scripts/encounters.gd")
const Atmosphere := preload("res://scripts/atmosphere.gd")

const TS := 64
## 开场会战战场：阳翟城内主街（出生点东侧，黄巾前锋打进城）。
const OPENING_BATTLE_POS := Vector2(11 * TS, 24.5 * TS)
## 寨内山贼组出战人数（官道组 18；战阵 v2 规模）。
const ZHAI_BANDIT_COUNT := 24

@onready var _ground: TileMapLayer = $Ground
@onready var _decoration: TileMapLayer = $Decoration
@onready var _player: Player = $Player
@onready var _joystick: Joystick = $UI/Joystick
@onready var _tap: TapToMove = $TapToMove
@onready var _battle_buttons: Control = $UI/BattleButtons
@onready var _camera: Camera2D = $Player/Camera2D

var _battle: BattleManager
var _save := SaveSystem.new()
var _music: Music
var _encounters: Encounters
var _dialog: DialogBox
var _hud: Hud
var _result_card: ResultCard
var _fade_rect: ColorRect
var _challenged: BanditGroup  # 本次开战的山贼组；null = 开场会战
var _bandits_cleared := false
var _reward_money := 0
var _zhai_cleared := false
var _fresh_start := false  # 无存档：标题关闭后播开场会战
var _last_saved_pos := Vector2.ZERO


func _ready() -> void:
	add_child(Sfx.new())
	_music = Music.new()
	add_child(_music)
	add_child(_save)
	MapBuilder.new().build(_ground, _decoration)
	add_child(Atmosphere.new())
	# 对话框要先于遭遇摆放建好：NPC 的对话触发器在 populate 时找它。
	_dialog = DialogBox.new()
	add_child(_dialog)
	_encounters = Encounters.new()
	_encounters.name = "NPCs"  # 兼容旧 smoke 工具的查找路径
	add_child(_encounters)
	_encounters.bandits_challenged.connect(_on_bandits_challenged)
	_encounters.old_blade_picked.connect(_on_old_blade_picked)
	_encounters.populate()
	_player.global_position = _encounters.point("player_spawn")
	_player.setup(_joystick, _tap)
	_hud = Hud.new()
	add_child(_hud)
	add_child(BannerToast.new())
	_result_card = ResultCard.new()
	add_child(_result_card)
	_update_objective()
	# 兵败渐暗层（战败复活专用）。
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 24
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)
	_restore_latest_save()
	# 标题置顶（其 _ready 暂停整树）；started 后恢复，新档再播开场会战。
	var title := TitleScreen.new()
	add_child(title)
	title.started.connect(_on_title_started)


## 标题关闭：恢复游戏；全新存档播开场白（传闻客四句，交代时局+钩子+方向，§5）。
func _on_title_started() -> void:
	if _fresh_start:
		_fresh_start = false
		_dialog.show_lines("传闻客", [
			"哟，面生啊。这年月还敢出门的，不是亡命徒，就是真豪杰。",
			"光和七年，黄巾四起。长社那边打得凶，咱颍川的官道也不太平喽。",
			"听说了吗？东边官道上一伙贼人拦路劫道，张家的商队叫他们扣下了。",
			"壮士若有几分本事，何不去看看？——出了东门，顺着官道走就是。",
		])


## 目标行：不指路的软目标提示（反箭头纪律，只一句话）。
func _update_objective() -> void:
	if _bandits_cleared and _zhai_cleared:
		_hud.set_objective("颍川暂安 · 自由闯荡")
	elif _bandits_cleared:
		_hud.set_objective("官道已通 · 传闻：北山贼寨仍在")
	else:
		_hud.set_objective("传闻：东边官道出事了")


## 屏震：相机短促抖动（横扫命中 / 主将受击）。
func shake(strength := 5.0, duration := 0.16) -> void:
	var tw := create_tween()
	var steps := 4
	for i in steps:
		tw.tween_property(_camera, "offset",
				Vector2(randf_range(-strength, strength),
						randf_range(-strength, strength)),
				duration / steps)
	tw.tween_property(_camera, "offset", Vector2.ZERO, duration / steps)


## 镜头呼吸：交战越密，视野越广（±10% 内）；规模感靠整体运动。
var _breath_cd := 0.0


func _breathe_camera() -> void:
	_breath_cd -= get_process_delta_time()
	if _breath_cd > 0.0:
		return
	_breath_cd = 0.5
	var n: int = _battle.engaged_count()
	var target := 0.86 if n >= 26 else (0.92 if n >= 12 else 1.0)
	if absf(_camera.zoom.x - target) > 0.02:
		create_tween().tween_property(_camera, "zoom",
				Vector2(target, target), 0.8).set_trans(Tween.TRANS_SINE)


## 会战视野：开战拉广角看全线，收兵拉回跟随视角。
func set_battle_view(on: bool) -> void:
	var target := Vector2(0.95, 0.95) if on else Vector2(1.5, 1.5)
	create_tween().tween_property(_camera, "zoom", target, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 开场会战（新档限定）：阳翟东门外，黄巾前锋压境，汉军乡勇迎战。
## 大军团对垒直接当作开场钩子——玩家一进场就在战场里。
func _opening_battle() -> void:
	if _battle != null:
		return
	await get_tree().create_timer(1.2).timeout  # 一拍定神，号角再起
	if _battle != null:
		return  # 等待期间玩家已撞进山贼警戒圈，开场会战让位
	_battle = BattleManager.new()
	add_child(_battle)
	_battle.battle_ended.connect(_on_battle_ended)
	_player.in_battle = true
	_player.battle = _battle
	# 备用开场会战（当前由开场白取代，保留可调用的编排）。
	_battle.start(_player, OPENING_BATTLE_POS,
			{"melee": 10}, {"melee": 10, "ranged": 2, "chief": true})
	_battle_buttons.show()
	_battle_buttons.bind_battle(_battle)
	_hud.bind_battle(_battle)
	_music.set_ducked(true)
	set_battle_view(true)
	_save.mark_dirty(_canonical_snapshot())
	_save.flush(SaveSystem.SLOT_PRE_BATTLE)


## 安卓切后台仅作补充落盘（§8）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_save.flush()


## 位置防抖快照：战斗中不存（§7.2/§8）；战斗中驱动镜头呼吸。
func _process(_delta: float) -> void:
	if _player.in_battle and is_instance_valid(_battle):
		_breathe_camera()
	if _player.in_battle:
		return
	if _player.global_position.distance_to(_last_saved_pos) > 8.0:
		_save.mark_dirty(_canonical_snapshot())
		_last_saved_pos = _player.global_position  # 真防抖：标记后归零距离


# ---------------------------------------------------------------- 战斗编排

## 玩家撞进任一山贼组警戒圈：世界内原位开战（§12.2 不黑屏）。
## 战前 checkpoint：进程被杀则回到战前（§7.2）。
func _on_bandits_challenged(group: BanditGroup) -> void:
	if _battle != null:
		return
	_challenged = group
	_save.mark_dirty(_canonical_snapshot())
	_save.flush(SaveSystem.SLOT_PRE_BATTLE)
	_battle = BattleManager.new()
	add_child(_battle)
	_battle.battle_ended.connect(_on_battle_ended)
	_player.in_battle = true
	_player.battle = _battle
	# 大兵团：乡勇 20 枪 + 10 弓；官道贼 28 刀 + 8 弓 + 三波援军；
	# 寨内 38 刀 + 10 弓 + 寨帅。两组各自独立结算。
	var ally := {"melee": 20, "ranged": 10}
	var enemy := {"melee": 24, "ranged": 6}
	var waves := 2
	if group == _encounters.zhai_bandits:
		enemy = {"melee": 34, "ranged": 10, "chief": true}
		waves = 0
	else:
		enemy["chief"] = true
	_battle.start(_player, group.global_position, ally, enemy, waves)
	var enemy_total := int(enemy.get("melee", 0)) + int(enemy.get("ranged", 0)) + 1
	_versus_splash("遭遇战", "阳翟乡勇 ×30", "黄巾贼众 ×%d" % enemy_total)
	_battle_buttons.show()
	_battle_buttons.bind_battle(_battle)
	_hud.bind_battle(_battle)
	_music.set_ducked(true)
	set_battle_view(true)


## 战前对阵闪卡：一张图交代敌我兵力（原版对阵界面的最小形态）。
func _versus_splash(title: String, left: String, right: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	var big := Label.new()
	big.text = title
	big.add_theme_font_size_override("font_size", 44)
	big.add_theme_color_override("font_color", Color(0.92, 0.78, 0.42))
	big.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.05))
	big.add_theme_constant_override("outline_size", 10)
	big.set_anchors_preset(Control.PRESET_CENTER)
	big.position = Vector2(-big.size.x / 2.0, -96)
	box.add_child(big)
	var small := Label.new()
	small.text = "%s   ⚔   %s" % [left, right]
	small.add_theme_font_size_override("font_size", 24)
	small.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82))
	small.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.05))
	small.add_theme_constant_override("outline_size", 6)
	small.set_anchors_preset(Control.PRESET_CENTER)
	small.position = Vector2(-small.size.x / 2.0, -36)
	box.add_child(small)
	box.modulate.a = 0.0
	var tw := layer.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.3)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(layer.queue_free)


## 收兵：世界产生结果——赢了官道就通了（§12.0 闭环的一环）。
## 开场会战不牵扯世界遭遇；两组山贼各自独立结算。
## 战果统计后弹结算卡；战败走「抬回阳翟」闭环（§3/§5，世界不回滚）。
## 战后立即 checkpoint（§8）。
func _on_battle_ended(player_won: bool) -> void:
	_battle_buttons.hide()
	_battle_buttons.unbind_battle()
	_hud.unbind_battle()
	_music.set_ducked(false)
	set_battle_view(false)
	_player.recover()
	# 战果统计要在释放 BattleManager 之前取（存活乡勇 / 歼敌）。
	var allies_left := 0
	var enemies_slain := 0
	if is_instance_valid(_battle):
		allies_left = _battle.alive_count(BattleManager.TEAM_PLAYER)
		enemies_slain = _battle.total_spawned(BattleManager.TEAM_BANDIT) \
				- _battle.alive_count(BattleManager.TEAM_BANDIT)
	if player_won and _challenged != null:
		if _challenged == _encounters.road_bandits:
			_bandits_cleared = true
			_encounters.spawn_rumor_drinker()  # 传闻回响：酒肆开始谈论官道的事
		else:
			_zhai_cleared = true
		_encounters.clear_bandits(_challenged)
	# P0：战败/脱战——山贼留在世界，警戒圈重新武装，可再战。
	if not player_won and _challenged != null:
		_challenged.rearm()
	_challenged = null
	if is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	# 战败：canonical 先落定（抬回阳翟）再弹卡——卡片只是投影。
	# 评审：玩家在结算卡期间杀进程，下次必须已在阳翟，而不是战场上。
	if not player_won:
		_player.global_position = _encounters.point("player_spawn")
		_last_saved_pos = _player.global_position
	_save.mark_dirty(_canonical_snapshot())
	_save.flush(SaveSystem.SLOT_AUTO)
	_result_card.show_result(player_won, allies_left, enemies_slain)
	if not player_won:
		_result_card.dismissed.connect(_on_defeat_dismissed, CONNECT_ONE_SHOT)


## 战败闭环（§3/§5）：关闭结算卡 → 渐暗 → 满血抬回阳翟出生点 → 渐亮。
## 世界不回滚：山贼不回血不消失（clear_bandits 只在胜利分支走）。
func _on_defeat_dismissed() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		pass)  # 位置与存档已在 battle_ended 落定，这里只负责渐暗渐亮
	tw.tween_property(_fade_rect, "modulate:a", 0.0, 0.5)


## 拾取长柄旧刀：行为变化当场可感（横扫范围扩大），并入档。
func _on_old_blade_picked() -> void:
	_player.equip_old_blade()
	_player.money += 25
	_player.add_xp(10)
	_save.mark_dirty(_canonical_snapshot())
	_save.flush(SaveSystem.SLOT_AUTO)


# ---------------------------------------------------------------- 存档（§8 M0 子集）

## Canonical WorldState 的 M0 最小子集：玩家位置 + 三个世界事实。
func _canonical_snapshot() -> Dictionary:
	return {
		"player_pos": [_player.global_position.x, _player.global_position.y],
		"has_old_blade": _player.has_old_blade,
		"bandits_cleared": _bandits_cleared,
		"zhai_cleared": _zhai_cleared,
		"level": _player.level,
		"xp": _player.xp,
		"money": _player.money,
		"bonus_melee": _player.bonus_melee,
	}


## 启动恢复：回原地（不是城门口）、回装备、回世界事实。
## 全新存档 → 记 _fresh_start，等标题关闭后再触发开场大会战。
func _restore_latest_save() -> void:
	var data := _save.load_latest()
	if data.is_empty():
		_last_saved_pos = _player.global_position
		_fresh_start = true
		return
	var pos: Array = data.get("player_pos", [])
	if pos.size() == 2:
		_player.global_position = Vector2(pos[0], pos[1])
		_last_saved_pos = _player.global_position
	_player.level = int(data.get("level", 1))
	_player.xp = int(data.get("xp", 0))
	_player.money = int(data.get("money", 30))
	_player.bonus_melee = int(data.get("bonus_melee", 0))
	_player.max_hp = Player.MAX_HP + 12 * (_player.level - 1)
	_player.attack_damage = Player.ATTACK_DAMAGE + 2 * (_player.level - 1)
	_player.hp = _player.max_hp
	_update_objective()
	if data.get("has_old_blade", false):
		_player.equip_old_blade()
		_encounters.remove_sparkle()
	if data.get("bandits_cleared", false):
		_bandits_cleared = true
		_encounters.clear_bandits(_encounters.road_bandits)
		_encounters.spawn_rumor_drinker()  # 读档恢复时传闻客也在
	if data.get("zhai_cleared", false):
		_zhai_cleared = true
		_encounters.clear_bandits(_encounters.zhai_bandits)
