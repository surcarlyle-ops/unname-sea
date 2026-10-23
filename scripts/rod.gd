extends RefCounted
class_name Rod
## 鱼竿数据封装
##
## 把 GameData 中的鱼竿字典包装成一个带类型安全访问器的对象，
## 并提供"本次抛竿参数"的随机取值方法。
##
## 用法：
##     var rod := Rod.new("rod_branch")
##     print(rod.name, rod.level)
##     var wait := rod.roll_wait_time()

var id: String = ""
var name: String = "树枝竿"
var level: int = 1
var description: String = ""
var wait_min: float = 15.0
var wait_max: float = 45.0
var reel_min: float = 10.0
var reel_max: float = 20.0
var escape_rate: float = 0.30
var rarity_bonus: float = 0.0


func _init(rod_id: String = "rod_branch") -> void:
	load_from_id(rod_id)


## 从 GameData 加载指定 id 的鱼竿数据
func load_from_id(rod_id: String) -> void:
	id = rod_id
	var d := GameData.get_rod(rod_id)
	if d.is_empty():
		push_warning("[Rod] 未找到鱼竿数据: %s，使用默认值" % rod_id)
		return

	name = String(d.get("name", name))
	level = int(d.get("level", level))
	description = String(d.get("description", description))
	wait_min = float(d.get("wait_min", wait_min))
	wait_max = float(d.get("wait_max", wait_max))
	reel_min = float(d.get("reel_min", reel_min))
	reel_max = float(d.get("reel_max", reel_max))
	escape_rate = float(d.get("escape_rate", escape_rate))
	rarity_bonus = float(d.get("rarity_bonus", rarity_bonus))


## 随机一次等待时长（秒）
func roll_wait_time() -> float:
	return randf_range(wait_min, wait_max)


## 随机一次收线时长（秒）
func roll_reel_time() -> float:
	return randf_range(reel_min, reel_max)


## 判定本次是否脱钩
## bait_escape_modifier 可来自鱼饵（1.0 表示无影响，0.5 表示脱钩率减半）
func roll_escape(bait_escape_modifier: float = 1.0) -> bool:
	var rate := clampf(escape_rate * bait_escape_modifier, 0.0, 1.0)
	return randf() < rate


## 用于 UI 展示的简短描述
func get_summary() -> String:
	return "Lv%d %s｜等待 %.0f-%.0f 秒｜脱钩 %.0f%%" % [
		level, name, wait_min, wait_max, escape_rate * 100.0
	]
