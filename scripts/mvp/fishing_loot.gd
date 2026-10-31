extends Node
class_name FishingLoot
## 钓鱼 & 掉落物品的入包接口（兼容通用 Inventory）
##
## 在战斗场景中，玩家的库存由 first_person_player.inventory 统一管理。
## 本组件封装鱼/材料的拾取逻辑，包括堆叠、容量管理与掉落生成。
##
## 与钓鱼流程无关的独立操作（存档、制作返还等）可直接调 inventory。
##
## 用法：
##     loot.bind(player.inventory)
##     var got: Dictionary = loot.grant("fish_pale_minnow", 1, bobber, arena, player, hud)
##     if got.overflow > 0: hud.push_message("背包已满")

const DROP_SCRIPT: Script = preload("res://scripts/mvp/loot_drop.gd")

signal changed()
signal stored(item_id: String, accepted: int)

var inventory: Inventory = null
var stack_limit: int = 999


## 绑定到玩家的通用库存（第一人称战斗场景用）
func bind(inv: Inventory) -> void:
	inventory = inv


## [兼容旧接口] setup() 自动创建内部 Inventory（用于独立预览或测试）
func setup(total_slots: int, per_stack: int) -> void:
	stack_limit = maxi(per_stack, 1)
	if inventory == null:
		inventory = Inventory.new()
		inventory.setup(maxi(total_slots, 1), per_stack)


## 查询数量
func count(item_id: String) -> int:
	return inventory.get_count(item_id) if inventory != null else 0


## 背包内总件数
func total_items() -> int:
	if inventory == null:
		return 0
	var total: int = 0
	for key: String in inventory.items.keys():
		total += int(inventory.items[key])
	return total


## 已占用的格位数
func used_slots() -> int:
	if inventory == null:
		return 0
	var used: int = 0
	for item_id: String in inventory.slots:
		if not item_id.is_empty():
			used += 1
	return used


## 背包是否已满
func is_full() -> bool:
	if inventory == null:
		return true
	return used_slots() >= inventory.slot_count


## 还能再装多少个这个物品
func room_for(item_id: String) -> int:
	if inventory == null or item_id.is_empty():
		return 0
	var current: int = count(item_id)
	if current >= stack_limit:
		return 0
	var cell: int = inventory.slots.find(item_id)
	if cell >= 0:
		return stack_limit - current
	if inventory.slots.find("") >= 0:
		return stack_limit
	return 0


## 容量判断：至少还能装 amount 个
func can_accept(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return room_for(item_id) >= amount


## 尽量装入，返回实际装入数量。
## 容量上限由这里把关：Inventory 只按 999 截断，格子满了它仍会记数量，
## 新种类会变成"看不见的库存"。先按 room_for 截断，溢出留给调用方落地。
func add_item(item_id: String, amount: int) -> int:
	if inventory == null or item_id.is_empty() or amount <= 0:
		return 0
	var allowed: int = mini(amount, room_for(item_id))
	if allowed <= 0:
		return 0
	var accepted: int = inventory.add_item(item_id, allowed)
	if accepted > 0:
		stored.emit(item_id, accepted)
		changed.emit()
	return accepted


## [兼容旧接口] 装入尽可能多的量，返回没装进去的数量
func try_add(item_id: String, amount: int) -> int:
	if inventory == null or item_id.is_empty() or amount <= 0:
		return amount
	var accepted: int = add_item(item_id, amount)
	return amount - accepted


## 入包 + 溢出落地。返回 {accepted, overflow, drop}
func grant(item_id: String, amount: int, at: Vector3, parent: Node, player: Node3D = null, notice: Node = null) -> Dictionary:
	var overflow: int = try_add(item_id, amount)
	var result: Dictionary = {"accepted": amount - overflow, "overflow": overflow, "drop": null}
	if overflow > 0 and parent != null:
		var drop: Node3D = DROP_SCRIPT.spawn(parent, self, item_id, overflow, at, player) as Node3D
		if drop != null and notice != null and drop.has_method("set_notice_target"):
			drop.call("set_notice_target", notice)
			drop.call("notify", "背包已满，%s 余 %d 个留在岸边" % [item_name(item_id), overflow])
		result.drop = drop
	return result


## 获取物品名称
func item_name(item_id: String) -> String:
	var fish: Dictionary = GameData.get_fish(item_id)
	if not fish.is_empty():
		return str(fish.get("name", item_id))
	return GameData.get_item_name(item_id)


## 获取展示用列表（含数量）
func entries() -> Array[Dictionary]:
	if inventory == null:
		return []
	var list: Array[Dictionary] = []
	for item_id: String in inventory.slots:
		if item_id.is_empty():
			continue
		var current: int = count(item_id)
		if current <= 0:
			continue
		list.append({
			"id": item_id,
			"name": item_name(item_id),
			"count": current,
			"capped": current >= stack_limit,
		})
	return list
