class_name SaveSystem
extends Node
## M0 存档（§8）：Canonical WorldState 的 M0 子集序列化。
##
## 逻辑事务 ≠ 磁盘事务：mutation 只标 dirty；checkpoint 原子写盘
## （临时文件 → 校验 → 替换正式档）。
## Checkpoint 时机（M0 施工权范围内）：
##   - 战前 / 战后各一次（§7.2 战斗中不存）；
##   - 位置等高频变化防抖（DEBOUNCE_SEC 一次，战斗中暂停）；
##   - on_pause 仅补充。
## 槽位：auto（防抖+战后）/ pre_battle（战前快照）。

const SCHEMA_VERSION := 1
const DEBOUNCE_SEC := 4.0

const SLOT_AUTO := "user://saves/auto.save"
const SLOT_PRE_BATTLE := "user://saves/pre_battle.save"

var _dirty := false
var _pending: Dictionary = {}
var _debounce_left := 0.0


## 标记 Canonical 子集变化（只改内存标 dirty，不写盘）。
func mark_dirty(data: Dictionary) -> void:
	_pending = data
	_dirty = true


func _process(delta: float) -> void:
	if not _dirty:
		return
	_debounce_left -= delta
	if _debounce_left <= 0.0:
		flush(SLOT_AUTO)


## 立即写盘（checkpoint 用：战前/战后/on_pause）。
func flush(slot := SLOT_AUTO) -> bool:
	if not _dirty or _pending.is_empty():
		return false
	_dirty = false
	_debounce_left = DEBOUNCE_SEC
	var data := _pending.duplicate()
	data["schema_version"] = SCHEMA_VERSION
	return _atomic_write(slot, data)


## 原子写：临时文件 → 读回校验 → 替换正式档。
func _atomic_write(slot: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var tmp := slot + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败（打开临时文件）：" + tmp)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	# 校验：读回能解析才算完整落盘。
	var check := FileAccess.open(tmp, FileAccess.READ)
	if check == null or JSON.parse_string(check.get_as_text()) == null:
		push_error("存档校验失败：" + tmp)
		check = null
		return false
	check = null
	return DirAccess.rename_absolute(tmp, slot) == OK


## 读档：优先 auto，其次战前快照（战斗中进程被杀则回到战前，§7.2）。
func load_latest() -> Dictionary:
	for slot in [SLOT_AUTO, SLOT_PRE_BATTLE]:
		var data := _read_slot(slot)
		if not data.is_empty():
			return data
	return {}


func _read_slot(slot: String) -> Dictionary:
	if not FileAccess.file_exists(slot):
		return {}
	var f := FileAccess.open(slot, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.get("schema_version", 0) == SCHEMA_VERSION:
		return parsed
	return {}
