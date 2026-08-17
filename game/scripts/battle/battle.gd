class_name BattleManager
extends Node2D
## 战阵 v2（推翻 6v6 碰碰车）：阵型推进 + 军令 + 侧背击 + 士气 2.0。
##
## 核心直觉：远看是一条会推移的战线，不是一团布朗运动。
## - 未接敌：两列横队按阵位推进（slot 每帧随战线刷新）。
## - 接敌：正面绞肉；稳守=正面减伤+枪兵结矛墙；冲锋=提速增伤+首撞击退。
## - 侧后方 120° 外攻击 ×1.8 并额外打击士气——主将绕后横扫是真战术。
## - 士气 <30 崩溃：倒旗溃逃可追歼；主将阵亡立即败北；撤退拉离即脱战。
##
## 性能：同屏 ≤60 单位，直接按队列线性扫描（每帧每单位 ~30 次距离检查，
## 远省过空间哈希的字典开销）；围攻计数每帧预计算一次。

signal battle_ended(player_won: bool)
signal morale_changed(team: int, value: float)
signal order_changed(team: int, order: String)  # "hold" / "charge" / "none"

const TEAM_PLAYER := 0
const TEAM_BANDIT := 1

const MORALE_START := 100.0
const MORALE_ROUT := 30.0
const DEATH_HIT := 0.85
const LEADER_DEATH_HIT := 30.0
const FLANK_HIT := 0.3        # 每次侧背击的士气打击
const BREACH_DRAIN := 0.5     # 每个突入阵后的敌人每秒士气流失
const BREACH_DEPTH := 40.0    # 越过本方战线质心多少算"突入阵后"
const BREACH_DRAIN_CAP := 3.0
const DISENGAGE_RANGE := 320.0  # 周围无敌才算脱战（风筝是合法战术）
const DISENGAGE_TIME := 2.2
const CHARGE_DURATION := 4.0
const CHARGE_COOLDOWN := 10.0
const CELL := 44.0            # 空间哈希格

## 兵种表（数据驱动；枪兵攻距长正面硬，刀贼快攻怕矛墙）。
const SPEARMAN := {
	"hp": 76, "damage": 3.6, "range": 58.0, "windup": 0.16, "cooldown": 1.25,
	"speed": 96.0, "armor": 2, "mass": 1.2, "brace": true,
	"frames_dir": "res://assets/chars/soldier", "display_height": 64.0,
}
const BLADE_BANDIT := {
	"hp": 68, "damage": 3.8, "range": 44.0, "windup": 0.12, "cooldown": 0.95,
	"speed": 110.0, "armor": 0, "mass": 0.9, "brace": false,
	"frames_dir": "res://assets/chars/bandit", "display_height": 64.0,
}
const HAN_ARCHER := {
	"hp": 46, "damage": 4.0, "range": 44.0, "windup": 0.22, "cooldown": 2.1,
	"speed": 100.0, "armor": 0, "mass": 0.8, "brace": false, "ranged": true,
	"pref_range": 170.0,
	"frames_dir": "res://assets/chars/archer", "display_height": 64.0,
}
const BANDIT_ARCHER := {
	"hp": 40, "damage": 3.5, "range": 44.0, "windup": 0.22, "cooldown": 2.3,
	"speed": 104.0, "armor": 0, "mass": 0.8, "brace": false, "ranged": true,
	"pref_range": 160.0,
	"frames_dir": "res://assets/chars/bandit_archer", "display_height": 64.0,
}
const ZHAI_CHIEF := {
	"hp": 230, "damage": 8, "range": 52.0, "windup": 0.16, "cooldown": 1.1,
	"speed": 104.0, "armor": 3, "mass": 2.2, "brace": false, "is_leader": true,
	"frames_dir": "res://assets/chars/bandit", "display_height": 74.0,
}

var active := false
var center := Vector2.ZERO
var advance_dir := {TEAM_PLAYER: Vector2.RIGHT, TEAM_BANDIT: Vector2.LEFT}
var morale := {TEAM_PLAYER: MORALE_START, TEAM_BANDIT: MORALE_START}
var order := {TEAM_PLAYER: "none", TEAM_BANDIT: "none"}

var _units := {TEAM_PLAYER: [], TEAM_BANDIT: []}
var _spawned := {TEAM_PLAYER: 0, TEAM_BANDIT: 0}  # 累计出战数（结算用）
var _routed := {TEAM_PLAYER: false, TEAM_BANDIT: false}
var _charge_cd := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}
var _player: Player
var _over := false
var _dust_cd := 0.0
var _disengage := 0.0
var _wave_schedule: Array[float] = []  # 各波入场时刻（战斗秒）
var _battle_time := 0.0
var _quiet := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}  # 各队无士气损伤的秒数
var _now := 0.0  # 战斗内计时（军令统一结束时刻用）
var _order_gen := {TEAM_PLAYER: 0, TEAM_BANDIT: 0}  # 军令代际（防延迟协程复活旧令）
var _charge_end := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}
# 小队节拍：近战齐刺 / 弓手齐射。人脑对同步动作极敏感——十箭齐飞才是军队。
var _beat_melee := 0.0
var _beat_volley := 0.0
const BEAT_MELEE := 1.3
const BEAT_VOLLEY := 2.6
const BEAT_WINDOW := 0.20  # 节拍后的允许出手窗口
var _engaged_count := 0  # 当前接敌单位数（镜头呼吸用）
var _death_window := {TEAM_PLAYER: 0.0, TEAM_BANDIT: 0.0}  # 恐慌蔓延计时窗
var _death_burst := {TEAM_PLAYER: 0, TEAM_BANDIT: 0}  # 窗内死亡人数


## 节拍查询：单位只在小队节拍后的窗口内出手（齐刺/齐射）。
func beat_ready(ranged: bool) -> bool:
	return _beat_volley <= BEAT_WINDOW if ranged else _beat_melee <= BEAT_WINDOW


## 接敌单位数（主程序镜头呼吸用）。
func engaged_count() -> int:
	return _engaged_count


## 稳守枪林：结阵时前排枪尖周期性齐亮——"这是一堵矛墙"的视觉语言。
var _glint_cd := 0.0


func _tick_spear_glint(delta: float) -> void:
	if order[TEAM_PLAYER] != "hold":
		return
	_glint_cd -= delta
	if _glint_cd > 0.0:
		return
	_glint_cd = 0.7
	for u in _alive_units(TEAM_PLAYER):
		if u.fleeing or not bool(u.stats.get("brace", false)):
			continue
		if randf() < 0.55:
			Combatant.spawn_spark(self, u.global_position
					+ u.facing * 40.0 + Vector2(0, -u.stats.get("display_height", 64.0) * 0.6), 0.5)


## 冲锋冲击波：0.4s 内撞够 4 人 = 一次聚合震屏 + 低频重音。
## 大战场事件才配震屏，零碎受击不配。
var _impact_count := 0
var _impact_window := 0.0


func notify_charge_impact() -> void:
	_impact_count += 1
	_impact_window = 0.4
	if _impact_count >= 4:
		_impact_count = -99  # 本波冲锋只震这一次
		var main := _player.get_parent() if _player != null else null
		if main != null and main.has_method(&"shake"):
			main.shake(8.0, 0.22)
		Sfx.play(Sfx.ROUT)  # 低频溃吼当撞击重音


func _tick_stuck(delta: float) -> void:
	for i in range(_stuck.size() - 1, -1, -1):
		_stuck[i][1] -= delta
		if _stuck[i][1] <= 0.0:
			var node: Sprite2D = _stuck[i][0]
			if is_instance_valid(node):
				node.visible = false
				node.modulate = Color.WHITE
				node.z_index = 800
				_arrow_pool.append(node)
			_stuck.remove_at(i)


func _tick_impact(delta: float) -> void:
	if _impact_window > 0.0:
		_impact_window -= delta
		if _impact_window <= 0.0 and _impact_count > 0:
			_impact_count = 0


## 主将破阵：横扫落点制造 0.9s 突破口，附近友军自动突入。
func notify_player_breach(pos: Vector2) -> void:
	var responded := 0
	for u in _alive_units(TEAM_PLAYER):
		if responded >= 6:
			break
		if not u.fleeing and u.global_position.distance_to(pos) < 230.0:
			u.charge_left = maxf(u.charge_left, 0.9)
			responded += 1


## 结算只读：本方当前存活单位数（UI/战果统计用）。
func alive_count(team_id: int) -> int:
	return _alive_units(team_id).size()


## 活单位每物理帧缓存一次（评审：热路径 filter 分配 churn）。
var _alive_cache := {}
var _alive_frame := -1


## 结算只读：本方累计出战单位数（含寨帅；歼敌 = total - alive）。
func total_spawned(team_id: int) -> int:
	return _spawned[team_id]


## 军令只读：冲锋冷却剩余秒数（冷却扫层用）。
func charge_cd_left(team_id: int) -> float:
	return _charge_cd[team_id]


## 开战：双方按编制列阵对进。
## spec = {"melee": 前排近战数, "ranged": 弓手数, "chief": 有无主将}
func start(player: Player, at: Vector2, ally_spec: Dictionary,
		enemy_spec: Dictionary, waves := 0) -> void:
	_player = player
	center = at
	active = true
	for i in waves:
		_wave_schedule.append(WAVE_FIRST + i * WAVE_EVERY)
	advance_dir[TEAM_PLAYER] = (at - player.global_position).normalized()
	if advance_dir[TEAM_PLAYER].length() < 0.1:
		advance_dir[TEAM_PLAYER] = Vector2.RIGHT
	advance_dir[TEAM_BANDIT] = -advance_dir[TEAM_PLAYER]
	_spawn_army(TEAM_PLAYER, player.global_position
			+ advance_dir[TEAM_PLAYER] * 40.0, ally_spec)
	_spawn_army(TEAM_BANDIT, at - advance_dir[TEAM_BANDIT] * 170.0, enemy_spec)
	# 黄巾狂热：贼军士气池更深（大编制 + 信仰），乡勇为保家而战维持标准值。
	morale[TEAM_BANDIT] = MORALE_START + 35.0
	Sfx.play(Sfx.RALLY)


## 列阵：近战前两列（每列 ≤10 列兵），弓手排在其后 84px，主将压阵。
func _spawn_army(team_id: int, anchor: Vector2, spec: Dictionary) -> void:
	var dir: Vector2 = advance_dir[team_id]
	var perp := dir.rotated(PI / 2.0)
	var melee_stats: Dictionary = SPEARMAN if team_id == TEAM_PLAYER else BLADE_BANDIT
	var ranged_stats: Dictionary = HAN_ARCHER if team_id == TEAM_PLAYER else BANDIT_ARCHER
	var melee_n := int(spec.get("melee", 0))
	var ranged_n := int(spec.get("ranged", 0))
	_spawned[team_id] += melee_n + ranged_n + (1 if bool(spec.get("chief", false)) else 0)
	var files := mini(10, maxi(1, int(ceil(melee_n / 2.0))))
	for i in melee_n:
		var rank := i / files
		var file := i % files
		var pos := anchor + perp * (file - (files - 1) / 2.0) * 36.0 \
				- dir * rank * 42.0
		_add_unit(melee_stats, team_id, pos)
	var afiles := mini(10, maxi(1, ranged_n))
	for i in ranged_n:
		var rank := i / afiles
		var file := i % afiles
		var pos := anchor + perp * (file - (afiles - 1) / 2.0) * 38.0 \
				- dir * (84.0 + rank * 40.0)
		_add_unit(ranged_stats, team_id, pos)
	if bool(spec.get("chief", false)):
		_add_unit(ZHAI_CHIEF, team_id, anchor - dir * 150.0)


func _add_unit(stats: Dictionary, team_id: int, pos: Vector2) -> BattleUnit:
	var u := BattleUnit.new()
	u.setup(stats, team_id, self)
	u.died.connect(_on_unit_died)
	u.position = pos
	u.slot = pos
	u.facing = advance_dir[team_id]
	add_child(u)
	_units[team_id].append(u)
	return u


func _physics_process(delta: float) -> void:
	if not active or _over:
		return
	_now += delta
	for team_id in _charge_cd:
		_charge_cd[team_id] = maxf(0.0, _charge_cd[team_id] - delta)
	if Engine.get_physics_frames() % 3 == 0:
		_precompute_attacker_counts()
		_recount_engaged()
	# 收尾放开追击
	for team_id in [TEAM_PLAYER, TEAM_BANDIT]:
		var enemy := TEAM_BANDIT if team_id == TEAM_PLAYER else TEAM_PLAYER
		if _alive_units(enemy).size() <= 3:
			for u in _alive_units(team_id):
				u.charge_left = maxf(u.charge_left, 0.5)
	_tick_reinforcements(delta)
	_tick_arrows(delta)
	_tick_impact(delta)
	_tick_stuck(delta)
	_tick_spear_glint(delta)
	_beat_melee += delta
	_beat_volley += delta
	if _beat_melee >= BEAT_MELEE:
		_beat_melee = 0.0
	if _beat_volley >= BEAT_VOLLEY:
		_beat_volley = 0.0
	# 士气回稳：3.5s 无损伤后 +3.0/s。崩溃必须一鼓作气，拉锯得以成立。
	for team_id in morale:
		_quiet[team_id] += delta
		if _death_window[team_id] > 0.0:
			_death_window[team_id] -= delta
			if _death_window[team_id] <= 0.0:
				_death_burst[team_id] = 0
		if _quiet[team_id] > 3.5 and morale[team_id] < MORALE_START 				and not _routed[team_id]:
			morale[team_id] = minf(MORALE_START, morale[team_id] + 3.0 * delta)
			morale_changed.emit(team_id, morale[team_id])
	_refresh_slots()
	_apply_breach_drain(delta)
	_spawn_battle_dust(delta)
	for team_id in morale:
		if morale[team_id] < MORALE_ROUT and not _routed[team_id]:
			_rout(team_id)
	_check_end()


# ---------------------------------------------------------------- 阵型

## 阵位刷新：以存活战线质心为锚，沿推进方向重排两列横队。
## 接敌后（质心距敌近）阵位冻结在当前线，稳守的单位钉在线上。
func _refresh_slots() -> void:
	for team_id in [TEAM_PLAYER, TEAM_BANDIT]:
		var line := _line_anchor(team_id)
		var dir: Vector2 = advance_dir[team_id]
		var perp := dir.rotated(PI / 2.0)
		var melee: Array = []
		var ranged: Array = []
		for u in _alive_units(team_id):
			if u.fleeing:
				continue
			(ranged if bool(u.stats.get("ranged", false)) else melee).append(u)
		var files := mini(10, maxi(1, int(ceil(melee.size() / 2.0))))
		for i in melee.size():
			var rank := i / files
			var file := i % files
			melee[i].slot = line + perp * (file - (files - 1) / 2.0) * 36.0 \
					- dir * rank * 42.0
		var afiles := mini(10, maxi(1, ranged.size()))
		for i in ranged.size():
			var rank := i / afiles
			var file := i % afiles
			ranged[i].slot = line + perp * (file - (afiles - 1) / 2.0) * 38.0 \
					- dir * (84.0 + rank * 40.0)


## 战线锚点：本方存活单位质心沿推进方向的最前沿。
func _line_anchor(team_id: int) -> Vector2:
	var alive_units := _alive_units(team_id)
	if alive_units.is_empty():
		return center
	var sum := Vector2.ZERO
	var front := -INF
	var dir: Vector2 = advance_dir[team_id]
	for u in alive_units:
		sum += u.global_position
		front = maxf(front, dir.dot(u.global_position))
	var centroid := sum / alive_units.size()
	# 锚点 = 质心垂直分量 + 前沿推进分量（线随最前者缓慢前移）。
	return centroid + dir * maxf(0.0, front - dir.dot(centroid) - 20.0) * 0.5


# ---------------------------------------------------------------- 军令

## 冲锋：4s 提速增伤、首撞击退、阵型解散。冷却 10s。
func charge_team(team_id: int) -> void:
	if not active or _over or _charge_cd[team_id] > 0.0:
		return
	_charge_cd[team_id] = CHARGE_COOLDOWN
	order[team_id] = "charge"
	_order_gen[team_id] += 1
	var gen: int = _order_gen[team_id]
	_charge_end[team_id] = _now + CHARGE_DURATION  # 统一结束时刻：
	# 晚接到号令的单位不白赚时长（评审：尾部单位冲锋曾拖到 ~6s）
	var units := _alive_units(team_id)
	units.sort_custom(func(a, b): return a.slot.x < b.slot.x 			if team_id == TEAM_PLAYER else a.slot.x > b.slot.x)
	var i := 0
	for u in units:
		if not u.fleeing:
			_charge_delayed(u, i * 0.07, gen)
			i += 1
	Sfx.play(Sfx.RALLY)
	order_changed.emit(team_id, "charge")
	await get_tree().create_timer(CHARGE_DURATION).timeout
	if not _over and order[team_id] == "charge" and _order_gen[team_id] == gen:
		order[team_id] = "none"
		order_changed.emit(team_id, "none")


func _charge_delayed(u: BattleUnit, delay: float, gen: int) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# 代际校验：玩家中途改令（稳守/再冲锋）时，旧令的延迟协程不得复活。
	if _over or _order_gen[u.team] != gen or order[u.team] != "charge":
		return
	if not is_instance_valid(u) or not u.alive or u.fleeing:
		return
	u.charge_left = maxf(0.0, _charge_end[u.team] - _now)
	u.hold_order = false
	Combatant.spawn_dust(self, u.global_position + Vector2(0, 6), 2)


## 稳守：保持阵型、正面减伤、枪兵结矛墙迎击冲锋。
func hold_team(team_id: int) -> void:
	if not active or _over:
		return
	order[team_id] = "hold"
	_order_gen[team_id] += 1  # 作废旧冲锋的未醒协程
	for u in _alive_units(team_id):
		if not u.fleeing:
			u.hold_order = true
			u.charge_left = 0.0
	Sfx.play(Sfx.RALLY)
	order_changed.emit(team_id, "hold")


## 侧背击事件：被打侧背的一方额外掉士气。
func notify_flanked(team_id: int) -> void:
	if _over:
		return
	_quiet[team_id] = 0.0
	morale[team_id] = maxf(0.0, morale[team_id] - FLANK_HIT)
	morale_changed.emit(team_id, morale[team_id])


## 主将倒地 = 立即败北（不再是 -30 士气了事）。
func notify_player_down() -> void:
	if _over:
		return
	morale[TEAM_PLAYER] = 0.0
	morale_changed.emit(TEAM_PLAYER, 0.0)
	_finish(false)


func _on_unit_died(who: BattleUnit) -> void:
	if _over:
		return
	if who.team == TEAM_BANDIT and _player != null:
		_player.add_xp(2)  # 歼敌战功
	var hit := LEADER_DEATH_HIT if who.is_leader else DEATH_HIT
	_quiet[who.team] = 0.0
	# 恐慌蔓延：3 秒内连死 3 人以上，每次追加 +50% 打击——雪崩是这么来的。
	_death_burst[who.team] += 1
	_death_window[who.team] = 3.0
	if _death_burst[who.team] >= 3:
		hit *= 1.5
	morale[who.team] = maxf(0.0, morale[who.team] - hit)
	morale_changed.emit(who.team, morale[who.team])


## 战线被穿透：敌冲到本方队尾（投影最小者）之后 BREACH_DEPTH，每个持续掉士气。
## 基准用队尾不用质心——阵线互嵌时质心判据会双方同时狂掉，那不对。
func _apply_breach_drain(delta: float) -> void:
	for team_id in [TEAM_PLAYER, TEAM_BANDIT]:
		var anchor_dir: Vector2 = advance_dir[team_id]
		var alive_units := _alive_units(team_id)
		if alive_units.is_empty():
			continue
		var rear := INF
		for u in alive_units:
			rear = minf(rear, anchor_dir.dot(u.global_position))
		var breachers := 0
		var enemy_team := TEAM_BANDIT if team_id == TEAM_PLAYER else TEAM_PLAYER
		for e in _alive_units(enemy_team):
			if anchor_dir.dot(e.global_position) < rear - BREACH_DEPTH:
				breachers += 1
		# 玩家本人突入敌阵后也算（绕后横扫有真实战略价值）。
		if enemy_team == TEAM_PLAYER and _player != null and _player.alive \
				and anchor_dir.dot(_player.global_position) < rear - BREACH_DEPTH:
			breachers += 1
		if breachers > 0:
			_quiet[team_id] = 0.0
			morale[team_id] = maxf(0.0, morale[team_id]
					- minf(breachers * BREACH_DRAIN, BREACH_DRAIN_CAP) * delta)
			morale_changed.emit(team_id, morale[team_id])


# ---------------------------------------------------------------- 邻居查询（线性扫描 + 每帧预计算）

var _attacker_count := {}  # instance_id → 70px 内敌人数（每帧一次）


func _precompute_attacker_counts() -> void:
	_attacker_count.clear()
	var all := _all_combatants()
	for a in all:
		var n := 0
		for b in all:
			if b != a and b.team != a.team and a.global_position \
					.distance_squared_to(b.global_position) < 4900.0:
				n += 1
		_attacker_count[a.get_instance_id()] = n


func _recount_engaged() -> void:
	var n := 0
	for team_id in _units:
		for u in _units[team_id]:
			if is_instance_valid(u) and u.alive and not u.fleeing 					and u._target != null and is_instance_valid(u._target):
				n += 1
	_engaged_count = n


func _all_combatants() -> Array:
	var all: Array = []
	for team_id in _units:
		for u in _units[team_id]:
			if is_instance_valid(u) and u.alive:
				all.append(u)
	if _player != null and _player.alive:
		all.append(_player)
	return all


## 最近敌：线性扫敌队 + 围攻惩罚（计数来自每帧预计算，不嵌套扫描）。
func nearest_enemy(unit: Node2D, max_dist: float) -> Node2D:
	var enemy_team := TEAM_BANDIT if unit.team == TEAM_PLAYER else TEAM_PLAYER
	var origin: Vector2 = unit.global_position
	var best: Node2D = null
	var best_score := INF  # 距离合法性只看 d<=max_dist；score 只用于排序（评审）
	for other in _units[enemy_team]:
		if not is_instance_valid(other) or not other.alive:
			continue
		var d := origin.distance_to(other.global_position)
		if d > max_dist:
			continue
		var score: float = d + float(_attacker_count.get(other.get_instance_id(), 0)) * 60.0
		if score < best_score:
			best_score = score
			best = other
	# 玩家也是敌队的可选目标，但带倾向惩罚：兵团优先打兵团，
	# 主将要被"够得着"才会被缠上（防全军穿阵追主将）。
	if enemy_team == TEAM_PLAYER and _player != null and _player.alive:
		var d := origin.distance_to(_player.global_position) + 130.0
		if d < best_score:
			best_score = d
			best = _player
	return best


## 友军分离力：30px 内同袍斥力（线性扫本队）。
func separation(unit: BattleUnit) -> Vector2:
	var push := Vector2.ZERO
	for other in _units[unit.team]:
		if other == unit or not is_instance_valid(other) or not other.alive:
			continue
		var diff: Vector2 = unit.global_position - other.global_position
		var d: float = diff.length()
		if 0.01 < d and d < 38.0:
			push += diff.normalized() * (1.0 - d / 38.0)
	return push


## 由世界坐标反查单位（结矛墙反撞用）。
func unit_at(pos: Vector2) -> BattleUnit:
	for team_id in _units:
		for u in _units[team_id]:
			if is_instance_valid(u) and u.alive \
					and u.global_position.distance_squared_to(pos) < CELL * CELL:
				return u
	return null


# ---------------------------------------------------------------- 箭矢（对象池）

const ARROW_SPEED := 340.0
const ARROW_HIT := 14.0
var _arrows: Array = []
var _arrow_pool: Array = []
var _stuck: Array = []  # 插地箭杆 [node, 剩余秒]
var _arrow_tex: ImageTexture


func _make_arrow_tex() -> ImageTexture:
	if _arrow_tex != null:
		return _arrow_tex
	var img := Image.create(14, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(14):
		for y in range(3):
			img.set_pixel(x, y, Color(0.32, 0.24, 0.14, 1))
	for x in range(11, 14):
		img.set_pixel(x, 1, Color(0.85, 0.82, 0.72, 1))
	_arrow_tex = ImageTexture.create_from_image(img)
	return _arrow_tex


## 弓手放箭：直线抛射，命中最近敌（14px），目标先死箭也照飞。
func spawn_arrow(from: Vector2, target: Node2D, dmg: int, team: int,
		shooter: Node2D = null) -> void:
	var spr: Sprite2D
	if _arrow_pool.is_empty():
		spr = Sprite2D.new()
		spr.texture = _make_arrow_tex()
		spr.z_index = 800
		add_child(spr)
	else:
		spr = _arrow_pool.pop_back()
		spr.visible = true
		spr.modulate = Color.WHITE
		spr.z_index = 800
	var aim: Vector2 = target.global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	var dir := (aim - from).normalized()
	spr.rotation = dir.angle()
	spr.position = from + Vector2(0, -26)
	_arrows.append({"pos": spr.position, "vel": dir * ARROW_SPEED,
			"dmg": dmg, "team": team, "node": spr, "life": 1.8, "shooter": shooter})


func _tick_arrows(delta: float) -> void:
	for i in range(_arrows.size() - 1, -1, -1):
		var a: Dictionary = _arrows[i]
		a.pos += a.vel * delta
		a.life -= delta
		a.node.position = a.pos
		var hit := false
		var enemy_team := TEAM_BANDIT if a.team == TEAM_PLAYER else TEAM_PLAYER
		for u in _units[enemy_team]:
			if is_instance_valid(u) and u.alive \
					and u.global_position.distance_squared_to(a.pos) < ARROW_HIT * ARROW_HIT:
				u.take_damage(a.dmg, a.pos - a.vel.normalized() * 20.0, 18.0, false, a.shooter)
				hit = true
				break
		if not hit and enemy_team == TEAM_PLAYER and _player.alive \
				and _player.global_position.distance_squared_to(a.pos) < ARROW_HIT * ARROW_HIT:
			_player.take_damage(a.dmg, a.pos - a.vel.normalized() * 20.0, 18.0)
			hit = true
		if hit or a.life <= 0.0:
			if not hit:
				# 落空的箭插进土里，留 5s 战场痕迹。
				a.node.rotation = a.vel.angle() * 0.6
				a.node.z_index = 2
				a.node.modulate = Color(1, 1, 1, 0.5)
				_stuck.append([a.node, 5.0])
			else:
				a.node.visible = false
				_arrow_pool.append(a.node)
			_arrows.remove_at(i)


# ---------------------------------------------------------------- 收尾

func _rout(team_id: int) -> void:
	_routed[team_id] = true
	Sfx.play(Sfx.ROUT)
	for u in _alive_units(team_id):
		u.rout()
	await get_tree().create_timer(1.8).timeout
	if not _over:
		_finish(team_id == TEAM_BANDIT)


func _check_end() -> void:
	var bandit_left := _alive_units(TEAM_BANDIT).size()
	var han_left := _alive_units(TEAM_PLAYER).size()
	# 残部溃散：编制被打掉 85% 的军队事实上不存在了，残兵直接溃逃。
	for team_id in [TEAM_PLAYER, TEAM_BANDIT]:
		if not _routed[team_id] and _spawned[team_id] >= 8 				and _alive_units(team_id).size() <= maxi(2, int(_spawned[team_id] * 0.15)):
			_rout(team_id)
	if bandit_left == 0:
		_finish(true)
	elif (han_left == 0 and not _player.alive) or not _player.alive:
		_finish(false)
	elif _player_disengaged(get_physics_process_delta_time()):
		_finish(false)  # 撤退永远可用：脱离接触即脱战，世界不回滚


func _finish(player_won: bool) -> void:
	_over = true
	active = false
	for team_id in _units:
		for u in _units[team_id]:
			if is_instance_valid(u) and u.alive and not u.fleeing:
				u.rout()
	battle_ended.emit(player_won)


## 援军：首波 12s、之后每 14s 一波，每波 4 刀贼从贼侧后方入场。
## 战场不是一波流的绞肉，是"还有援军！"的起伏。
const WAVE_SIZE := 6
const WAVE_FIRST := 15.0
const WAVE_EVERY := 16.0

func _tick_reinforcements(delta: float) -> void:
	if _wave_schedule.is_empty():
		return
	_battle_time += delta
	if _battle_time < _wave_schedule[0]:
		return
	_wave_schedule.pop_front()
	var dir: Vector2 = advance_dir[TEAM_BANDIT]
	var at := center - dir * 220.0  # 贼阵后方
	_spawn_army(TEAM_BANDIT, at, {"melee": WAVE_SIZE})
	Sfx.play(Sfx.RALLY)


## 脱战判定：玩家身边 DISENGAGE_RANGE 内无敌持续 DISENGAGE_TIME 秒。
func _player_disengaged(delta: float) -> bool:
	if _player == null or not _player.alive:
		return false
	var nearest := 99999.0
	for u in _units[TEAM_BANDIT]:
		if is_instance_valid(u) and u.alive:
			nearest = minf(nearest, u.global_position.distance_to(_player.global_position))
	if nearest > DISENGAGE_RANGE:
		_disengage += delta
	else:
		_disengage = 0.0
	return _disengage >= DISENGAGE_TIME


func _alive_units(team_id: int) -> Array:
	var f: int = Engine.get_physics_frames()
	if f != _alive_frame:
		_alive_frame = f
		for t in _units:
			_alive_cache[t] = _units[t].filter(func(u) -> bool:
				return is_instance_valid(u) and u.alive)
	return _alive_cache.get(team_id, [])


## 接战线尘土：战场的呼吸。随机挑正在互砍的对子在中间点扬土。
func _spawn_battle_dust(delta: float) -> void:
	_dust_cd -= delta
	if _dust_cd > 0.0:
		return
	_dust_cd = 0.12
	var melee: Array = []
	for team_id in [TEAM_PLAYER, TEAM_BANDIT]:
		for u in _alive_units(team_id):
			if not u.fleeing and u._target != null:
				melee.append(u)
	if melee.is_empty():
		return
	var u: BattleUnit = melee[randi() % melee.size()]
	Combatant.spawn_dust(self, (u.global_position
			+ u._target.global_position) / 2.0 + Vector2(0, 6), 2)


## hit-stop：命中顿帧 60~90ms。
func hit_stop(seconds := 0.08) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
