extends Node
class_name Inventory
## 通用物品栏（武器、工具、药水、鱼、材料）
##
## 核心：Dictionary 存储 id -> count，格位数组追踪物品顺序与位置。
## 快捷栏与装备栏特殊格位由外部管理，主储物由 slots 记录。
## 支持：移动、交换、堆叠、拆分、整理与垃圾槽恢复。
##
## 用法：
##     var inv := Inventory.new()
##     inv.setup(15, 999)  # 15 格，每格 999 上限
##     inv.add_item("item_fish_bone", 3)
##     print(inv.get_count("item_fish_bone"))  # 3
##     inv.move_slot(0, 1)  # 交换第 0 格与第 1 格

signal changed()
signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)
signal slot_changed(slot: int)

var items: Dictionary = {}  ## id -> count（唯一数量源）
var slots: Array[String] = []  ## 格位序列，"" 表示空；长度 = slot_count
var slot_count: int = 0
var stack_limit: int = 999

## 垃圾槽：存最后删除的物品，可拿回一次
var trash_item: String = ""
var trash_count: int = 0


## 初始化：格位数、堆叠上限
func setup(total_slots: int, per_stack: int) -> void:
	slot_count = maxi(total_slots, 1)
	stack_limit = maxi(per_stack, 1)
	slots.clear()
	for _i: int in range(slot_count):
		slots.append("")


## 添加物品：尽量装进背包，返回实际装入数量
func add_item(item_id: String, count: int = 1) -> int:
	if item_id.is_empty() or count <= 0:
		return 0
	var accepted: int = _do_add(item_id, count)
	if accepted > 0:
		item_added.emit(item_id, accepted)
		changed.emit()
	return accepted


## 移除物品：数量不足时返回 false
func remove_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	var current := int(items.get(item_id, 0))
	if current < count:
		return false
	var left := current - count
	if left <= 0:
		items.erase(item_id)
		_remove_slot(item_id)
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
	slots.fill("")
	changed.emit()


## 格位操作：交换两个格位（用于拖放或整理）
func swap_slots(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= slot_count or to_slot < 0 or to_slot >= slot_count:
		return false
	if from_slot == to_slot:
		return true
	var temp: String = slots[from_slot]
	slots[from_slot] = slots[to_slot]
	slots[to_slot] = temp
	slot_changed.emit(from_slot)
	slot_changed.emit(to_slot)
	changed.emit()
	return true


## 将某个格位的物品全部移到另一个格位（堆叠或交换）
func move_to_slot(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= slot_count or to_slot < 0 or to_slot >= slot_count:
		return false
	if from_slot == to_slot:
		return true

	var from_id: String = slots[from_slot]
	var to_id: String = slots[to_slot]

	if from_id.is_empty():
		return true  # 源格空

	# 如果目标也有物品且 id 不同，则交换
	if not to_id.is_empty() and to_id != from_id:
		return swap_slots(from_slot, to_slot)

	# 同 id 堆叠或源格是新格位
	var from_count: int = get_count(from_id)
	var to_count: int = get_count(to_id)

	# 尝试堆叠
	if to_id == from_id:
		var room: int = stack_limit - to_count
		if room > 0:
			var move_count: int = mini(from_count, room)
			items[from_id] = from_count - move_count
			if from_count - move_count <= 0:
				items.erase(from_id)
				slots[from_slot] = ""
			if to_count + move_count >= stack_limit:
				items[to_id] = stack_limit
			else:
				items[to_id] = to_count + move_count
			slot_changed.emit(from_slot)
			slot_changed.emit(to_slot)
			changed.emit()
			return true
	else:
		# 源格到空格
		slots[to_slot] = from_id
		slots[from_slot] = ""
		slot_changed.emit(from_slot)
		slot_changed.emit(to_slot)
		changed.emit()
		return true

	return false


## 拆分：从 from_slot 拆出 count 个到 to_slot（若 to_slot 是空格则新建）
func split_from_slot(from_slot: int, to_slot: int, count: int) -> bool:
	if from_slot < 0 or from_slot >= slot_count or to_slot < 0 or to_slot >= slot_count:
		return false
	if from_slot == to_slot or count <= 0:
		return false

	var from_id: String = slots[from_slot]
	if from_id.is_empty():
		return false

	var from_count: int = get_count(from_id)
	if from_count < count:
		return false

	# 目标格必须空或同 id
	var to_id: String = slots[to_slot]
	if not to_id.is_empty() and to_id != from_id:
		return false

	# 执行拆分
	items[from_id] = from_count - count
	if from_count - count <= 0:
		items.erase(from_id)
		slots[from_slot] = ""

	if to_id.is_empty():
		slots[to_slot] = from_id
	items[from_id] = int(items.get(from_id, 0)) + count

	slot_changed.emit(from_slot)
	slot_changed.emit(to_slot)
	changed.emit()
	return true


## 整理：清理空格和重复，保留快捷栏与装备栏顺序（由外部指定 protected_ranges）
## protected_ranges: [(start, end), ...] 指定不动的格位范围
func organize(protected_ranges: Array[Array] = []) -> void:
	# 标记保护格
	var protected: Array[bool] = []
	protected.resize(slot_count)
	protected.fill(false)
	for range_item: Array in protected_ranges:
		if range_item.size() >= 2:
			var start: int = int(range_item[0])
			var end: int = int(range_item[1])
			for i: int in range(maxi(0, start), mini(slot_count, end + 1)):
				protected[i] = true

	# 收集非保护区的物品
	var collected: Array[String] = []
	for i: int in range(slot_count):
		if not protected[i] and not slots[i].is_empty():
			collected.append(slots[i])

	# 清空非保护区
	for i: int in range(slot_count):
		if not protected[i]:
			slots[i] = ""

	# 重新放入（同类物品相邻）
	var used_idx: int = 0
	for i: int in range(slot_count):
		if protected[i]:
			if not slots[i].is_empty():
				# 找下一个非保护的空格
				used_idx = i + 1
			continue
		if used_idx < collected.size():
			if used_idx < slot_count and not protected[used_idx]:
				slots[used_idx] = collected[used_idx]
			used_idx += 1


## 删除到垃圾槽（最多保留最后一次删除的物品）
func delete_to_trash(item_id: String, count: int) -> bool:
	if not remove_item(item_id, count):
		return false
	trash_item = item_id
	trash_count = count
	return true


## 从垃圾槽恢复最后一次删除的物品
func restore_from_trash() -> bool:
	if trash_item.is_empty() or trash_count <= 0:
		return false
	add_item(trash_item, trash_count)
	trash_item = ""
	trash_count = 0
	return true


## 获取展示用列表（格位顺序，含数量）
func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for item_id: String in slots:
		if item_id.is_empty():
			continue
		var current: int = get_count(item_id)
		if current <= 0:
			continue
		list.append({
			"id": item_id,
			"count": current,
			"capped": current >= stack_limit,
		})
	return list


## 导出为存档用数据
func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "slots": slots.duplicate(true)}


## 从存档恢复
func from_dict(data: Dictionary) -> void:
	if data.has("items"):
		items = Dictionary(data.get("items", {})).duplicate(true)
	if data.has("slots"):
		slots = Array(data.get("slots", [])).duplicate(true)
	changed.emit()


## 内部：添加物品实现，返回实际接收数量
func _do_add(item_id: String, count: int) -> int:
	var current: int = int(items.get(item_id, 0))
	if current >= stack_limit:
		return 0
	var accepted: int = clampi(count, 0, stack_limit - current)
	if accepted > 0:
		items[item_id] = current + accepted
		_ensure_slot(item_id)
	return accepted


## 内部：确保物品有格位
func _ensure_slot(item_id: String) -> int:
	var existing: int = slots.find(item_id)
	if existing >= 0:
		return existing
	var empty: int = slots.find("")
	if empty >= 0:
		slots[empty] = item_id
		return empty
	return -1  # 满了


## 内部：从格位中移除物品
func _remove_slot(item_id: String) -> void:
	var idx: int = slots.find(item_id)
	if idx >= 0:
		slots[idx] = ""


## 调试用：打印当前物品
func debug_print() -> void:
	print("[Inventory] 共 %d 类物品，%d 格已用：" % [items.size(), used_slots()])
	for id in items.keys():
		print("  %s x%d" % [GameData.get_item_name(String(id)), int(items[id])])


func used_slots() -> int:
	var count: int = 0
	for item_id: String in slots:
		if not item_id.is_empty():
			count += 1
	return count
