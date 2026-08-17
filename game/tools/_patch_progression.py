# -*- coding: utf-8 -*-
"""游戏性数值层：经验/等级/钱/招募/目标行。所有改动一次过。"""

def patch(path, subs):
    src = open(path, encoding='utf-8').read()
    for i, (old, new) in enumerate(subs):
        assert old in src, f'{path} #{i} not found'
        src = src.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='\n').write(src)
    print('ok', path)

# ---------- player.gd：等级/钱/招募 ----------
patch('scripts/player.gd', [
    ('''const MAX_HP := 140''',
     '''const MAX_HP := 140  # 基础血量；每级 +12（max_hp 变量为准）'''),
    ('''var team := Combatant.TEAM_PLAYER
var hp := MAX_HP''',
     '''## 成长：战功升级（+12 血 +2 攻），钱用于招募乡勇。
var level := 1
var xp := 0
var money := 30
var bonus_melee := 0  # 教头处招募的额外枪兵（入编制，上限 8）
var max_hp := MAX_HP
var attack_damage := ATTACK_DAMAGE

var team := Combatant.TEAM_PLAYER
var hp := MAX_HP'''),
    ('''## 战后复位（由 Main 在 battle_ended 时调用）。
func recover() -> void:
	hp = MAX_HP''',
     '''## 战功入账：自动升级（每级 30×level 经验）。
func add_xp(n: int) -> bool:
	xp += n
	var need := level * 30
	if xp >= need:
		xp -= need
		level += 1
		max_hp += 12
		attack_damage += 2
		hp = max_hp  # 升级回满
		return true
	return false


## 战后复位（由 Main 在 battle_ended 时调用）。
func recover() -> void:
	hp = max_hp'''),
    ('''				if alive and is_instance_valid(target) and target.alive \\
						and global_position.distance_to(target.global_position) \\
								<= ATTACK_RANGE + 14.0:
					target.take_damage(ATTACK_DAMAGE, dmg_from, 60.0, false, self)''',
     '''				if alive and is_instance_valid(target) and target.alive \\
						and global_position.distance_to(target.global_position) \\
								<= ATTACK_RANGE + 14.0:
					target.take_damage(attack_damage, dmg_from, 60.0, false, self)'''),
])

# ---------- battle.gd：击杀上报（主将计战功）----------
patch('scripts/battle/battle.gd', [
    ('''func _on_unit_died(who: BattleUnit) -> void:
	if _over:
		return''',
     '''func _on_unit_died(who: BattleUnit) -> void:
	if _over:
		return
	if who.team == TEAM_BANDIT and _player != null:
		_player.add_xp(2)  # 歼敌战功'''),
])

# ---------- save_system.gd：schema v3 ----------
patch('scripts/save_system.gd', [
    ('const SCHEMA_VERSION := 2  # v1 弃档（无迁移价值，M0 阶段）',
     'const SCHEMA_VERSION := 3  # v3 加等级/钱/招募；旧档一律弃'),
])

# ---------- main.gd：战后赏金 / 编制读招募 / 目标行 / 新档字段 ----------
patch('scripts/main.gd', [
    ('''	var ally := {"melee": 20, "ranged": 10}''',
     '''	var ally := {"melee": 20 + _player.bonus_melee, "ranged": 10}'''),
    ('''	if player_won and _challenged != null:
		if _challenged == _encounters.road_bandits:
			_bandits_cleared = true
			_encounters.spawn_rumor_drinker()  # 传闻回响：酒肆开始谈论官道的事
		else:
			_zhai_cleared = true
		_encounters.clear_bandits(_challenged)''',
     '''	if player_won and _challenged != null:
		# 战后赏金：底饷 + 按歼敌（结算卡展示用）。
		_reward_money = 40 + enemies_slain * 2
		_player.money += _reward_money
		if _challenged == _encounters.road_bandits:
			_bandits_cleared = true
			_encounters.spawn_rumor_drinker()  # 传闻回响：酒肆开始谈论官道的事
		else:
			_zhai_cleared = true
		_encounters.clear_bandits(_challenged)
		_update_objective()'''),
    ('''	_result_card.show_result(player_won, allies_left, enemies_slain)''',
     '''	_result_card.show_result(player_won, allies_left, enemies_slain,
			_reward_money if player_won else 0)'''),
    ('''		_player.equip_old_blade()
		_save.mark_dirty(_canonical_snapshot())
		_save.flush(SaveSystem.SLOT_AUTO)''',
     '''		_player.equip_old_blade()
		_player.money += 25
		_player.add_xp(10)
		_save.mark_dirty(_canonical_snapshot())
		_save.flush(SaveSystem.SLOT_AUTO)'''),
    ('''		"player_pos": [_player.global_position.x, _player.global_position.y],
		"has_old_blade": _player.has_old_blade,
		"bandits_cleared": _bandits_cleared,
		"zhai_cleared": _zhai_cleared,
	}''',
     '''		"player_pos": [_player.global_position.x, _player.global_position.y],
		"has_old_blade": _player.has_old_blade,
		"bandits_cleared": _bandits_cleared,
		"zhai_cleared": _zhai_cleared,
		"level": _player.level,
		"xp": _player.xp,
		"money": _player.money,
		"bonus_melee": _player.bonus_melee,
	}'''),
])

# 教头 NPC + 目标行 + 赏金变量：接到 _ready 后
src = open('scripts/main.gd', encoding='utf-8').read()
old = '''	_player.setup(_joystick, _tap)
	_restore_latest_save()'''
new = '''	_player.setup(_joystick, _tap)
	_encounters.spawn_drillmaster()
	_update_objective()
	_restore_latest_save()'''
assert old in src
src = src.replace(old, new)
old = '''var _bandits_cleared := false'''
new = '''var _bandits_cleared := false
var _reward_money := 0'''
assert old in src
src = src.replace(old, new)
old = '''## 屏震：相机短促抖动（横扫命中 / 主将受击）。'''
new = '''## 目标行：不指路的软目标提示（§12.6 反箭头纪律，只一句话）。
func _update_objective() -> void:
	if _bandits_cleared and _zhai_cleared:
		_hud.set_objective("颍川暂安 · 自由闯荡")
	elif _bandits_cleared:
		_hud.set_objective("官道已通 · 传闻：北山贼寨仍在")
	else:
		_hud.set_objective("传闻：东边官道出事了")


## 屏震：相机短促抖动（横扫命中 / 主将受击）。'''
assert old in src
src = src.replace(old, new)
# 读档恢复成长字段
old = '''	if data.get("zhai_cleared", false):'''
new = '''	_player.level = int(data.get("level", 1))
	_player.xp = int(data.get("xp", 0))
	_player.money = int(data.get("money", 30))
	_player.bonus_melee = int(data.get("bonus_melee", 0))
	_player.max_hp = Player.MAX_HP + 12 * (_player.level - 1)
	_player.attack_damage = Player.ATTACK_DAMAGE + 2 * (_player.level - 1)
	_player.hp = _player.max_hp
	_update_objective()
	if data.get("zhai_cleared", false):'''
assert old in src
src = src.replace(old, new)
open('scripts/main.gd', 'w', encoding='utf-8', newline='\n').write(src)
print('ok scripts/main.gd (extra)')

# ---------- encounters.gd：乡勇教头（招募，对话选项）----------
src = open('scripts/encounters.gd', encoding='utf-8').read()
old = '''## 酒肆传闻：传闻客在酒肆门口讲时局，台词反映世界状态（三阶段换稿）。'''
new = '''## 乡勇教头：阳翟校场（城西南），40 钱募一名枪兵（上限 +8）。
## 功能附着于人——招募不是菜单，是找这个人说话（§11.2/§11.4）。
func spawn_drillmaster() -> void:
	var dm := Node2D.new()
	dm.name = "Drillmaster"
	dm.position = point("player_spawn") + Vector2(-150, 90)  # 校场角落
	var anim := CharAnim.new()
	anim.frames_dir = "res://assets/chars/soldier"
	anim.display_height = 66.0
	dm.add_child(anim)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/npc/shadow.png")
	shadow.modulate.a = 0.38
	shadow.scale = Vector2(0.55, 0.4)
	shadow.z_index = -1
	dm.add_child(shadow)
	var bubble := ProximityBubble.new()
	dm.add_child(bubble)
	add_child(dm)
	var trigger := DialogueTrigger.new()
	trigger.speaker = "乡勇教头"
	trigger.lines_provider = func() -> Array[String]: return []  # 占位，自定义流程
	dm.add_child(trigger)
	# 自定义招募流程：走近直接出带选项的对话框。
	trigger.set_process(false)
	var recruiter := RecruitTrigger.new()
	dm.add_child(recruiter)


## 招募触发器：近 50px 出选项对话框（招募/离开）。
class RecruitTrigger:
	extends Node2D
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
		if d > 90.0:
			_can_open = true
			return
		if not _can_open or d > 50.0 or _dialog.is_showing:
			return
		if _player.get("in_battle") == true:
			return
		_can_open = false
		var price := 40
		var line := "要操练乡勇吗？%d 钱一名。（已募 %d/8）" % [price, _player.bonus_melee]
		_dialog.show_lines("乡勇教头", [line], get_parent() as Node2D,
				["招募一名（%d钱）" % price, "离开"])
		var choice: int = await _dialog.choice_made
		if choice != 0:
			return
		if _player.bonus_melee >= 8:
			_dialog.show_lines("乡勇教头", ["儿郎够多了，练不过来。"], get_parent() as Node2D)
		elif _player.money < price:
			_dialog.show_lines("乡勇教头", ["囊中羞涩？先去挣几文军功钱。"], get_parent() as Node2D)
		else:
			_player.money -= price
			_player.bonus_melee += 1
			_dialog.show_lines("乡勇教头",
					["好！又一个儿郎入伍。出战时他自会列队。（乡勇 +1）"],
					get_parent() as Node2D)


## 酒肆传闻：传闻客在酒肆门口讲时局，台词反映世界状态（三阶段换稿）。'''
assert old in src
src = src.replace(old, new)
open('scripts/encounters.gd', 'w', encoding='utf-8', newline='\n').write(src)
print('ok scripts/encounters.gd')

# ---------- hud.gd：等级/钱 + 目标行 ----------
patch('scripts/ui/hud.gd', [
    ('''	_hp_label = _make_label("主将", 20, 16, 12)''',
     '''	_hp_label = _make_label("主将", 20, 16, 12)
	_stat_label = _make_label("", 16, 16, 58)
	_obj_label = _make_label("", 17, 640, 12)
	_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_label.size.x = 640
	_obj_label.position.x = 320
	_obj_label.add_theme_color_override("font_color", Color(0.86, 0.74, 0.45))'''),
    ('''var _canvas: HudCanvas
var _hp_label: Label''',
     '''var _canvas: HudCanvas
var _hp_label: Label
var _stat_label: Label
var _obj_label: Label'''),
    ('''	_canvas.queue_redraw()''',
     '''	if _player != null and is_instance_valid(_player):
		_stat_label.text = "Lv %d · 钱 %d · 乡勇+%d" % [
				_player.level, _player.money, _player.bonus_melee]
	_canvas.queue_redraw()'''),
    ('''## 战斗开始：接管士气显示。''',
     '''## 目标行（软提示，不指路）。
func set_objective(text: String) -> void:
	_obj_label.text = text


## 战斗开始：接管士气显示。'''),
])

# ---------- result_card.gd：赏金行 ----------
patch('scripts/ui/result_card.gd', [
    ('''func show_result(player_won: bool, allies_left: int, enemies_slain: int) -> void:
	if player_won:
		_title.text = "大破贼众"
		_title.add_theme_color_override("font_color", Color(0.94, 0.80, 0.42))
		_lines.text = "存活乡勇 %d\\n歼敌 %d" % [allies_left, enemies_slain]''',
     '''func show_result(player_won: bool, allies_left: int, enemies_slain: int,
		reward := 0) -> void:
	if player_won:
		_title.text = "大破贼众"
		_title.add_theme_color_override("font_color", Color(0.94, 0.80, 0.42))
		_lines.text = "存活乡勇 %d\\n歼敌 %d\\n赏钱 %d" % [allies_left, enemies_slain, reward]'''),
])
print('PROGRESSION LAYER OK')
