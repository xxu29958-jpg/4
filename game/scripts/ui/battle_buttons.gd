extends Control
## 战斗按钮（§7.3 右下圆形按钮：技能·横扫 + 军令·冲锋/稳守）。仅战斗中可见。
## 三国大时代式圆形半透明大按钮带中文小标签；横扫/冲锋有冷却扫层，
## 军令激活态（冲锋/稳守）在对应按钮上画发光圈。
## 位置避让 MIUI 边缘/手势死区（真机实测：贴边注入触摸会被系统吞掉）。

@export var player_path: NodePath

var _player: Player
var _battle: BattleManager
var _active_order := "none"  # 玩家方当前军令（发光圈用）
var _glow_t := 0.0

@onready var _sweep: TextureButton = $Sweep
@onready var _charge: TextureButton = $Charge
@onready var _hold: TextureButton = $Hold


func _ready() -> void:
	_player = get_node(player_path) as Player
	_sweep.pressed.connect(_player.use_sweep)
	_charge.pressed.connect(_player.use_rally)
	_hold.pressed.connect(_player.use_hold)


## main.gd 在开战时注入 BattleManager：冲锋冷却扫层 + 军令发光圈用。
func bind_battle(bm: BattleManager) -> void:
	unbind_battle()
	_battle = bm
	_active_order = "none"
	bm.order_changed.connect(_on_order_changed)


func unbind_battle() -> void:
	if _battle != null and _battle.order_changed.is_connected(_on_order_changed):
		_battle.order_changed.disconnect(_on_order_changed)
	_battle = null
	_active_order = "none"


func _on_order_changed(team: int, order: String) -> void:
	if team == _player.team:
		_active_order = order


func _process(delta: float) -> void:
	if not visible:
		return
	_glow_t += delta
	# 横扫冷却扫层（主将技能冷却在 player 上）。
	var sweep_cd := _player.skill_cd_left
	_apply_cooldown(_sweep, sweep_cd)
	# 冲锋冷却扫层（军令冷却在 BattleManager 上）。
	var charge_cd := 0.0
	if _battle != null and is_instance_valid(_battle):
		charge_cd = _battle.charge_cd_left(_player.team)
	_apply_cooldown(_charge, charge_cd)
	queue_redraw()


func _apply_cooldown(btn: TextureButton, cd_left: float) -> void:
	var cooling := cd_left > 0.0
	btn.disabled = cooling
	btn.modulate = Color(0.35, 0.35, 0.35, 0.6) if cooling else Color.WHITE


## 军令发光圈：激活的军令按钮外圈画脉动金环。
func _draw() -> void:
	if _active_order != "charge" and _active_order != "hold":
		return
	var btn := _charge if _active_order == "charge" else _hold
	var center := btn.position + btn.size / 2.0
	var alpha := 0.55 + 0.45 * sin(_glow_t * 5.0)
	var color := Color(0.92, 0.76, 0.38, alpha)
	draw_arc(center, btn.size.x / 2.0 + 6.0, 0.0, TAU, 48, color, 3.0)
