class_name Sfx
extends Node
## 极简音效池：先到先得，占满即新开一路。静态入口 Sfx.play()。
## 音色全部由 tools/gen_sfx.py 程序合成，风格统一。

const SWING := preload("res://assets/sfx/swing.wav")
const HIT := preload("res://assets/sfx/hit.wav")
const SWEEP := preload("res://assets/sfx/sweep.wav")
const DOWN := preload("res://assets/sfx/down.wav")
const ROUT := preload("res://assets/sfx/rout.wav")
const RALLY := preload("res://assets/sfx/rally.wav")
const PICKUP := preload("res://assets/sfx/pickup.wav")

const POOL_SIZE := 8

static var _inst: Sfx


func _ready() -> void:
	Sfx._inst = self
	for i in POOL_SIZE:
		add_child(AudioStreamPlayer.new())


static func play(stream: AudioStream, volume_db := 0.0) -> void:
	if _inst == null:
		return
	for p in _inst.get_children():
		var player := p as AudioStreamPlayer
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.play()
			return
