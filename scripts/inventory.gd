extends Node
class_name Inventory
## 玩家物品栏
##
## 用 Dictionary 存储 id -> 数量。所有增减都通过统一接口，
## 并发出信号供 UI 刷新。
##
## 用法：
##     var inv := Inventory.new()
##     inv.add_item("item_fish_bone", 3)
##     print(inv.get_count("item_fish_bone"))  # 3

signal changed()
signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)

var items: Dictionary = {}  ## id -> count


## 添加物品
func add_item(item_id: String, count: int = 1) -> void:
	if item_id.is_empty() or count <= 0:
		return
	items[item_id] = int(items.get(item_id, 0)) + count
	item_added.emit(item_id, count)
	changed.emit()


## 移除物品（数量不足时返回 false，不做任何修改）
func remove_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	var current := int(items.get(item_id, 0))
	if current < count:
		return false
	var left := current - count
	if left <= 0:
		items.erase(item_id)
	else:
		items[item_id] = left
	item_removed.emit(item_id, count)
	changed.emit()
	return true


## 查询数量
func get_count(item_id: String) -> int:
	return int(items.get(item_id, 0))


## 是否拥有至少 count 个
func has_item(item_id: String, count: int = 1) -> bool:
	return get_count(item_id) >= count


## 批量检查材料是否齐全
## materials 形如 { "item_fish_bone": 3 }
func has_materials(materials: Dictionary) -> bool:
	for key in materials.keys():
		if not has_item(String(key), int(materials[key])):
			return false
	return true


## 批量扣除材料（先检查后扣，保证原子性）
func consume_materials(materials: Dictionary) -> bool:
	if not has_materials(materials):
		return false
	for key in materials.keys():
		remove_item(String(key), int(materials[key]))
	return true


## 清空
func clear() -> void:
	items.clear()
	changed.emit()


## 导出为存档用数据
func to_dict() -> Dictionary:
	return items.duplicate(true)


## 从存档恢复
func from_dict(data: Dictionary) -> void:
	items = data.duplicate(true)
	changed.emit()


## 调试用：打印当前物品
func debug_print() -> void:
	print("[Inventory] 共 %d 类物品：" % items.size())
	for id in items.keys():
		print("  %s x%d" % [GameData.get_item_name(String(id)), int(items[id])])
