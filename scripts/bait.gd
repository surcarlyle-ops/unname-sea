extends RefCounted
class_name Bait
## 鱼饵数据封装
##
## 包装 GameData 中的鱼饵字典，提供对"渔获概率修正"的统一读取。
##
## 用法：
##     var bait := Bait.new("bait_glow")
##     print(bait.name, bait.effect)
##     var mult := bait.get_rare_multiplier()

var id: String = ""
var name: String = "无鱼饵"
var description: String = ""
var effect: String = "none"
var modifiers: Dictionary = {}
var consumable: bool = false


func _init(bait_id: String = "bait_none") -> void:
	load_from_id(bait_id)


func load_from_id(bait_id: String) -> void:
	id = bait_id
	var d := GameData.get_bait(bait_id)
	if d.is_empty():
		push_warning("[Bait] 未找到鱼饵数据: %s，使用默认值" % bait_id)
		return

	name = String(d.get("name", name))
	description = String(d.get("description", description))
	effect = String(d.get("effect", effect))
	modifiers = d.get("modifiers", {})
	consumable = bool(d.get("consumable", consumable))


## 稀有鱼概率倍率
func get_rare_multiplier() -> float:
	return float(modifiers.get("rare_multiplier", 1.0))


## 异兽出现概率倍率
func get_monster_multiplier() -> float:
	return float(modifiers.get("monster_multiplier", 1.0))


## 脱钩率修正系数（<1 表示降低脱钩率）
func get_escape_modifier() -> float:
	return float(modifiers.get("escape_modifier", 1.0))


## 可解锁的深度层（0 表示无影响）
func get_unlock_depth() -> int:
	return int(modifiers.get("unlock_depth", 0))


## 是否仅限"静默"事件
func is_silence_only() -> bool:
	return bool(modifiers.get("silence_event_only", false))


## 是否无任何效果
func is_plain() -> bool:
	return effect == "none"
