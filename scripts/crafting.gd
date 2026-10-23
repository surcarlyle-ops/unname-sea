extends Node
class_name CraftingSystem
## 炼化系统（合成）
##
## 世界观包装：在残骸的神秘石板上进行"炼化仪式"。
## 配方三层结构：固定（60%）/ 半固定（30%）/ 隐藏（10%）。
##
## 用法：
##     var crafting := CraftingSystem.new()
##     add_child(crafting)
##     var result := crafting.refine("rec_rod_bone", inventory)

signal refine_started(recipe: Dictionary)
signal refine_finished(success: bool, result: Dictionary)
signal refine_failed(reason: String)

var refining: bool = false


## 执行一次炼化
## inventory 需为 Inventory 实例；成功时自动扣材料并加产物
func refine(recipe_id: String, inventory: Inventory) -> Dictionary:
	if refining:
		refine_failed.emit("正在炼化中")
		return {}

	var recipe := GameData.get_recipe(recipe_id)
	if recipe.is_empty():
		refine_failed.emit("配方不存在: " + recipe_id)
		return {}

	refining = true
	refine_started.emit(recipe)

	var result: Dictionary = {}
	var success := false

	match String(recipe.get("type", "fixed")):
		"fixed":
			success = _refine_fixed(recipe, inventory, result)
		"semi":
			success = _refine_semi(recipe, inventory, result)
		"hidden":
			success = _refine_hidden(recipe, inventory, result)
		_:
			refine_failed.emit("未知配方类型")

	refining = false
	refine_finished.emit(success, result)
	return result


## 固定配方：材料齐全即可产出
func _refine_fixed(recipe: Dictionary, inventory: Inventory, result: Dictionary) -> bool:
	var materials: Dictionary = recipe.get("materials", {})
	if not inventory.has_materials(materials):
		refine_failed.emit("材料不足")
		return false
	if not inventory.consume_materials(materials):
		refine_failed.emit("扣除材料失败")
		return false

	var r: Dictionary = recipe.get("result", {})
	result["success"] = true
	result["type"] = String(r.get("type", "item"))
	result["id"] = String(r.get("id", ""))
	result["count"] = int(r.get("count", 1))
	_apply_result(result, inventory)
	return true


## 半固定配方：投入任意材料，从池中随机产出
func _refine_semi(recipe: Dictionary, inventory: Inventory, result: Dictionary) -> bool:
	var any_list: Array = recipe.get("materials_any", [])
	# 需要至少 2 种指定类别材料
	var available: Array = []
	for mid in any_list:
		if inventory.has_item(String(mid), 1):
			available.append(String(mid))
	if available.size() < 2:
		refine_failed.emit("至少需要 2 种不同材料")
		return false

	# 每种各扣 1
	for mid in available:
		inventory.remove_item(mid, 1)

	var pool: Array = recipe.get("pool", [])
	if pool.is_empty():
		refine_failed.emit("配方池为空")
		return false

	var total := 0
	for e in pool:
		total += int(e.get("weight", 1))
	var roll := randi() % maxi(1, total)
	var acc := 0
	var picked_id := String(pool[0].get("id", ""))
	for e in pool:
		acc += int(e.get("weight", 1))
		if roll < acc:
			picked_id = String(e.get("id", ""))
			break

	result["success"] = true
	result["type"] = "item"
	result["id"] = picked_id
	result["count"] = 1
	_apply_result(result, inventory)
	return true


## 隐藏配方：与固定配方逻辑相同，但配方表无提示
func _refine_hidden(recipe: Dictionary, inventory: Inventory, result: Dictionary) -> bool:
	return _refine_fixed(recipe, inventory, result)


## 把产物写入物品栏
func _apply_result(result: Dictionary, inventory: Inventory) -> void:
	var id := String(result.get("id", ""))
	var count := int(result.get("count", 1))
	if id.is_empty():
		return
	inventory.add_item(id, count)


## 检查某个配方当前是否可以炼化（用于 UI 置灰）
func can_refine(recipe_id: String, inventory: Inventory) -> bool:
	var recipe := GameData.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	match String(recipe.get("type", "fixed")):
		"fixed", "hidden":
			return inventory.has_materials(recipe.get("materials", {}))
		"semi":
			var any_list: Array = recipe.get("materials_any", [])
			var cnt := 0
			for mid in any_list:
				if inventory.has_item(String(mid), 1):
					cnt += 1
			return cnt >= 2
	return false


## 列出当前所有可炼化的配方
func get_available_recipes(inventory: Inventory) -> Array:
	return GameData.recipes.filter(func(r: Dictionary) -> bool:
		return can_refine(String(r.get("id", "")), inventory)
	)
