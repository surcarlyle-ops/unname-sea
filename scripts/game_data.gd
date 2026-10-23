extends Node
## 全局数据管理器（Autoload 单例：GameData）
##
## 负责加载 data/ 目录下的所有 JSON 配置，并提供统一的只读查询接口。
## 所有游戏系统的数据来源都从这里取，避免各处硬编码。
##
## 用法：
##     var rod := GameData.get_rod("rod_bone")
##     var pool := GameData.get_area("shallow").get("fish_pool", [])

const DATA_PATH := "res://data/"

# 原始数据（数组）
var rods: Array = []
var baits: Array = []
var fish: Array = []
var monsters: Array = []
var items: Array = []
var recipes: Array = []
var areas: Array = []

# 索引表（id -> Dictionary），加速查询
var _rod_index: Dictionary = {}
var _bait_index: Dictionary = {}
var _fish_index: Dictionary = {}
var _monster_index: Dictionary = {}
var _item_index: Dictionary = {}
var _recipe_index: Dictionary = {}
var _area_index: Dictionary = {}

# 加载状态
var loaded: bool = false
var load_errors: Array[String] = []


func _ready() -> void:
	_load_all()


## 加载全部数据表
func _load_all() -> void:
	rods = _load_json("rod_data.json", "rods")
	baits = _load_json("bait_data.json", "baits")
	fish = _load_json("fish_data.json", "fish")
	monsters = _load_json("monster_data.json", "monsters")
	items = _load_json("item_data.json", "items")
	recipes = _load_json("recipe_data.json", "recipes")
	areas = _load_json("water_area_data.json", "areas")

	_rod_index = _build_index(rods)
	_bait_index = _build_index(baits)
	_fish_index = _build_index(fish)
	_monster_index = _build_index(monsters)
	_item_index = _build_index(items)
	_recipe_index = _build_index(recipes)
	_area_index = _build_index(areas)

	loaded = true
	if load_errors.is_empty():
		print("[GameData] 全部数据加载成功：鱼竿 %d / 鱼饵 %d / 鱼 %d / 异兽 %d / 物品 %d / 配方 %d / 水域 %d" % [
			rods.size(), baits.size(), fish.size(), monsters.size(), items.size(), recipes.size(), areas.size()
		])
	else:
		push_warning("[GameData] 加载过程中有 %d 个错误" % load_errors.size())


## 读取单个 JSON 文件的指定数组字段
func _load_json(file_name: String, key: String) -> Array:
	var path := DATA_PATH + file_name
	if not FileAccess.file_exists(path):
		load_errors.append("文件不存在: " + path)
		push_error("[GameData] 文件不存在: " + path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("无法打开: " + path)
		push_error("[GameData] 无法打开: " + path)
		return []

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		load_errors.append("JSON 解析失败: " + path)
		push_error("[GameData] JSON 解析失败: " + path)
		return []

	var dict: Dictionary = parsed
	if not dict.has(key):
		load_errors.append("缺少字段 '%s': %s" % [key, path])
		push_warning("[GameData] 缺少字段 '%s': %s" % [key, path])
		return []

	var arr: Variant = dict[key]
	if not (arr is Array):
		load_errors.append("字段 '%s' 不是数组: %s" % [key, path])
		return []

	return arr


## 把数组转成 id -> Dictionary 的索引
func _build_index(arr: Array) -> Dictionary:
	var idx: Dictionary = {}
	for entry in arr:
		if entry is Dictionary and entry.has("id"):
			var d: Dictionary = entry
			idx[String(d["id"])] = d
	return idx


# ---------- 查询接口 ----------

func get_rod(id: String) -> Dictionary:
	return _rod_index.get(id, {})

func get_bait(id: String) -> Dictionary:
	return _bait_index.get(id, {})

func get_fish(id: String) -> Dictionary:
	return _fish_index.get(id, {})

func get_monster(id: String) -> Dictionary:
	return _monster_index.get(id, {})

func get_item(id: String) -> Dictionary:
	return _item_index.get(id, {})

func get_recipe(id: String) -> Dictionary:
	return _recipe_index.get(id, {})

func get_area(id: String) -> Dictionary:
	return _area_index.get(id, {})


## 按水域筛选鱼种
func get_fish_by_area(area_id: String) -> Array:
	var area := get_area(area_id)
	var pool: Array = area.get("fish_pool", [])
	var result: Array = []
	for fid in pool:
		var f := get_fish(String(fid))
		if not f.is_empty():
			result.append(f)
	return result


## 按稀有度筛选鱼种
func get_fish_by_rarity(area_id: String, rarity: String) -> Array:
	return get_fish_by_area(area_id).filter(func(f: Dictionary) -> bool:
		return String(f.get("rarity", "")) == rarity
	)


## 按水域筛选异兽
func get_monsters_by_area(area_id: String) -> Array:
	var area := get_area(area_id)
	var pool: Array = area.get("monster_pool", [])
	var result: Array = []
	for mid in pool:
		var m := get_monster(String(mid))
		if not m.is_empty():
			result.append(m)
	return result


## 获取所有已解锁水域
func get_unlocked_areas() -> Array:
	return areas.filter(func(a: Dictionary) -> bool:
		return bool(a.get("unlocked", false))
	)


## 获取物品显示名（找不到时回退到 id）
func get_item_name(id: String) -> String:
	var it := get_item(id)
	return String(it.get("name", id))
