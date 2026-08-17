class_name CharAnim
extends Node2D
## 帧动画角色：GPT 精灵表切片驱动（walk1-4/windup/slash/hurt/idle）。
## 用法：frames_dir 指向 res://assets/chars/<name>/（内有 <name>_frames.json 与帧 PNG）。
## display_height = 世界内显示高度（px），内部按帧高 192 自动缩放。
##
## 信号：
##   attack_peak  —— 攻击帧出手瞬间（伤害在此刻判定）
##   attack_done  —— 攻击动作全部结束
## 状态优先级：hurt > attack > walk > idle。

signal attack_peak
signal attack_done

const FRAME_H := 192.0
var _walk_fps := 9.0  # 步频跟移速走（speed_fps），杜绝脚底滑冰

@export var frames_dir := "res://assets/chars/hero"
@export var display_height := 64.0
@export var flip_h := false:
	set(v):
		flip_h = v
		if _sprite != null:
			_sprite.flip_h = v

## 调用方喂移速：步频 = 速度 × 系数（64px 角色步幅约 7px/帧步）。
func set_stride(speed: float) -> void:
	_walk_fps = clampf(speed * 0.105, 7.5, 14.0)


var moving := false:
	set(v):
		if moving != v:
			moving = v
			if v and _state == "idle":
				_state = "walk"
				_t = 0.0
			elif not v and _state == "walk":
				_set_frame("idle")
				_state = "idle"

var _sprite: Sprite2D
var _frames := {}
var _state := "idle"  # idle / walk / attack / hurt / emote
var _t := 0.0
var _walk_idx := 0
var _emote_frames: Array = []
var _emote_fps := 2.5
var _emote_idx := 0
const WALK_ORDER := ["walk1", "walk2", "walk3", "walk4"]


func _ready() -> void:
	_sprite = Sprite2D.new()
	var s := display_height / FRAME_H
	_sprite.scale = Vector2(s, s)
	_sprite.flip_h = flip_h
	# 帧中心在几何中央：把精灵上移半高，让 node 原点落在脚底（战阵/排序基准）。
	_sprite.position = Vector2(0, -display_height / 2.0)
	add_child(_sprite)
	_load_frames()
	_set_frame("idle")


static var _cache := {}  # frames_dir → {name: Texture2D}（开战 30 人共享一次 I/O）


func _load_frames() -> void:
	if _cache.has(frames_dir):
		_frames = _cache[frames_dir]
		return
	var meta := frames_dir + "/" + frames_dir.get_file() + "_frames.json"
	var raw := FileAccess.get_file_as_string(meta)
	var data: Dictionary = {} if raw.is_empty() else JSON.parse_string(raw)
	if data.is_empty() and frames_dir != "res://assets/chars/soldier":
		# 缺素材时退回汉军帧（开发期容错，正式包不应触发）。
		frames_dir = "res://assets/chars/soldier"
		meta = frames_dir + "/soldier_frames.json"
		data = JSON.parse_string(FileAccess.get_file_as_string(meta))
	for name in data:
		_frames[name] = load(frames_dir + "/" + data[name]["file"])
	_cache[frames_dir] = _frames


func _set_frame(name: String) -> void:
	if _frames.has(name):
		_sprite.texture = _frames[name]


func _process(delta: float) -> void:
	match _state:
		"walk":
			_t += delta
			if _t >= 1.0 / _walk_fps:
				_t = 0.0
				_walk_idx = (_walk_idx + 1) % WALK_ORDER.size()
				_set_frame(WALK_ORDER[_walk_idx])
			# 步伐起伏：触地-腾空的两拍节奏，走路有"蹬地感"。
			_sprite.position.y = -display_height / 2.0 \
					- absf(sin(_t * _walk_fps * PI)) * 1.6
		"emote":
			_t += delta
			if _t >= 1.0 / _emote_fps and not _emote_frames.is_empty():
				_t = 0.0
				_emote_idx = (_emote_idx + 1) % _emote_frames.size()
				_set_frame(_emote_frames[_emote_idx])
		"attack", "hurt":
			pass  # 由 tween 驱动


## 攻击动作：起手帧（前摇）→ 出手帧（attack_peak）→ 回待机（attack_done）。
## windup 秒数由调用方按兵种节奏给。
func play_attack(windup := 0.12, recover := 0.15) -> void:
	_state = "attack"
	_set_frame("windup")
	var tw := create_tween()
	tw.tween_interval(windup)
	tw.tween_callback(func() -> void:
		_set_frame("slash")
		attack_peak.emit())
	tw.tween_interval(recover)
	tw.tween_callback(func() -> void:
		_state = "idle"
		_set_frame("idle" if not moving else WALK_ORDER[_walk_idx])
		if moving:
			_state = "walk"
		attack_done.emit())


## 受击动作：hurt 帧短闪。不打断攻击帧（攻击中的硬直由数值表现，不靠动画）。
func play_hurt() -> void:
	if _state == "attack":
		return
	_state = "hurt"
	_set_frame("hurt")
	var tw := create_tween()
	tw.tween_interval(0.18)
	tw.tween_callback(func() -> void:
		_state = "walk" if moving else "idle"
		_set_frame(WALK_ORDER[_walk_idx] if moving else "idle"))


## 死亡定格：hurt 帧倒地（旋转由外层做）。
func play_dead() -> void:
	_state = "hurt"
	_set_frame("hurt")


## 表情动作循环（村民招手、商贩张望等）：在 frames 列表间轮播。
func play_emote(frames: Array, fps := 2.5) -> void:
	_emote_frames = frames
	_emote_fps = fps
	_emote_idx = 0
	_t = 0.0
	_state = "emote"


## 结束表情，回待机/行走。
func stop_emote() -> void:
	if _state == "emote":
		_state = "walk" if moving else "idle"
		_set_frame(WALK_ORDER[_walk_idx] if moving else "idle")
