extends Node
## 存档管理器（Autoload 单例：SaveManager）
##
## 把游戏状态序列化为 JSON 存到 user:// 目录。
## user:// 在 Windows 上通常映射到 %APPDATA%\Godot\app_userdata\未名之海\
##
## 用法：
##     SaveManager.save_game(0, { "inventory": inv.to_dict() })
##     var data := SaveManager.load_game(0)

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves/"


func _ready() -> void:
	_ensure_dir()


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			push_error("[SaveManager] 无法创建存档目录: %s (err=%d)" % [SAVE_DIR, err])


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "save_slot%d.json" % slot


## 保存游戏
## data 形如 { "inventory": {...}, "unlocked_areas": [...], "chapter": 1 }
func save_game(slot: int, data: Dictionary) -> bool:
	_ensure_dir()
	var payload := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"data": data,
	}
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] 无法写入存档 slot %d" % slot)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("[SaveManager] 已保存 slot %d" % slot)
	return true


## 读取存档（不存在或损坏时返回空字典）
func load_game(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] 无法读取存档 slot %d" % slot)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("[SaveManager] 存档损坏 slot %d" % slot)
		return {}

	var dict: Dictionary = parsed
	if int(dict.get("version", 0)) != SAVE_VERSION:
		push_warning("[SaveManager] 存档版本不匹配，尝试兼容读取")

	var data: Variant = dict.get("data", {})
	return data if data is Dictionary else {}


## 存档是否存在
func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## 删除存档
func delete_save(slot: int) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	return err == OK


## 读取存档元信息（时间戳等），用于存档列表展示
func get_save_info(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var d: Dictionary = parsed
		return {
			"version": int(d.get("version", 0)),
			"timestamp": String(d.get("timestamp", "")),
		}
	return {}
