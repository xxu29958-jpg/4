class_name Music
extends Node
## 音乐双层：环境乐（五声音阶乡野循环）常驻；战鼓层战斗时淡入。
## 战斗中环境乐 duck 6dB，让刀剑声站前面。

const AMBIENCE := preload("res://assets/music/ambience.wav")
const DRUMS := preload("res://assets/music/war_drums.wav")
const BASE_DB := -16.0
const DUCK_DB := -22.0
const DRUMS_DB := -15.0

var _player: AudioStreamPlayer
var _drums: AudioStreamPlayer


func _ready() -> void:
	_player = _make_loop(AMBIENCE, BASE_DB)
	_drums = _make_loop(DRUMS, -80.0)  # 平时静默


func _make_loop(src: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var stream := src.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = &"Master"
	add_child(p)
	p.play()
	return p


## 战斗切换：True = 环境乐压低 + 战鼓淡入；False = 恢复乡野。
func set_ducked(ducked: bool) -> void:
	create_tween().tween_property(_player, "volume_db",
			DUCK_DB if ducked else BASE_DB, 0.4)
	create_tween().tween_property(_drums, "volume_db",
			DRUMS_DB if ducked else -80.0, 0.6)
