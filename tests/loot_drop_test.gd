extends SceneTree
## 背包数量 + 掉落/拾取组件检查（CodeBuddy 2026-10-28）。
##
## 覆盖本轮验收范围：堆叠 999、格位容量、满包落地、部分装入、重复拾取、
## 已销毁物体、跨死亡/R 重试保留、鱼与材料不进武器/快捷栏。
## 前半段是纯组件（不依赖主场景），后半段接到 combat_mvp 验证界面与既有武器搬运。
##
## 最小使用示例（与下面实际跑过的路径一致）：
##     var bag := load("res://scripts/mvp/fishing_loot.gd").new()
##     bag.setup(15, 999)
##     var got := bag.grant("item_scale", 3, spot, world, player, hud)   # 入包 + 溢出落地
##     print(bag.count("item_scale"), bag.can_accept("item_scale", 1), got.overflow)
##     var drop := LootDrop.spawn(world, bag, "fish_ring_scale", 1, spot, player)
##     drop.set_notice_target(hud)        # 背包满时 push_message，不阻塞操作
##
## 运行：godot --headless --path . --script res://tests/loot_drop_test.gd

const BAG_SCRIPT: String = "res://scripts/mvp/fishing_loot.gd"
## 新脚本在无编辑器导入的 headless 环境里还没有全局类名，按路径预载最稳。
const DROP_SCRIPT: Script = preload("res://scripts/mvp/loot_drop.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: push_error("Loot test timeout"); quit(2))
	await _bag_checks()
	await _drop_checks()
	await _scene_checks()
	print("\n=== loot_drop_test: %d/%d passed, %d failed ===" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


## Inventory.from_dict 读的是存档格式（{items, slots}）；测试里按 id→数量重置更直观。
func _refill(bag: Node, counts: Dictionary) -> void:
	bag.inventory.clear()
	for item_id: String in counts.keys():
		bag.inventory.add_item(item_id, int(counts[item_id]))


func _new_bag() -> Node:
	var bag: Node = load(BAG_SCRIPT).new()
	root.add_child(bag)
	bag.setup(15, 999)
	return bag


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
		await _frames(2)


# ---------- 数量袋 ----------
func _bag_checks() -> void:
	var bag: Node = _new_bag()
	_check(bag.count("fish_pale_minnow") == 0, "Empty bag reports zero")
	_check(bag.add_item("fish_pale_minnow", 5) == 5, "add_item returns the accepted amount")
	_check(bag.count("fish_pale_minnow") == 5, "Count comes from the shared Inventory")
	_check(bag.used_slots() == 1 and bag.inventory.slots.find("fish_pale_minnow") == 0, "Same item keeps one stack cell")
	var entries: Array = bag.entries()
	_check(entries.size() == 1 and str(entries[0].name) == "苍白小鲦", "Bag entry carries the data-file name")

	var accepted: int = bag.add_item("fish_pale_minnow", 1000)
	_check(accepted == 994 and bag.count("fish_pale_minnow") == 999, "Stack stops at 999")
	_check(bag.room_for("fish_pale_minnow") == 0 and not bag.can_accept("fish_pale_minnow"), "A full stack reports no room")
	_check(int(bag.try_add("fish_pale_minnow", 3)) == 3, "try_add returns the overflow when the stack is full")

	# 外部直接写 Inventory（存档/制作返还）也要显示出来，数量只有一份。
	bag.inventory.add_item("fish_ring_scale", 2)
	_check(bag.count("fish_ring_scale") == 2 and bag.inventory.slots.find("fish_ring_scale") >= 0, "External Inventory writes appear in the bag")
	_check(str(bag.item_name("fish_ring_scale")) == "环鳞鱼", "Ring-scale fish name is read from fish_data.json")
	bag.inventory.remove_item("fish_ring_scale", 2)
	await _frames(1)
	_check(bag.inventory.slots.find("fish_ring_scale") < 0, "Emptied stack releases its cell")

	bag.add_item("item_scale", 3)
	_check(bag.count("item_scale") == 3 and str(bag.item_name("item_scale")) == "鳞片", "Shell material reuses the existing item id")
	_check(bag.total_items() == 1002, "Total counts every stored item (%d)" % bag.total_items())

	# 15 格塞满后，新种类没有位置。
	var filler: Array[String] = [
		"item_branch", "item_rope", "item_sharp_stone", "item_fiber", "item_fine_wood",
		"item_fish_bone", "item_glass_shard", "item_glow_core", "item_sunken_metal",
		"item_deep_essence", "item_sand_grit", "item_lens_shard", "item_tide_gel",
	]
	for item_id: String in filler:
		bag.add_item(item_id, 1)
	_check(bag.is_full() and bag.used_slots() == bag.inventory.slot_count, "15 distinct types fill the bag")
	var before: int = bag.count("fish_ring_scale")
	_check(bag.add_item("fish_ring_scale", 1) == 0 and bag.count("fish_ring_scale") == before, "A new type is refused when every cell is used")
	_check(int(bag.try_add("fish_ring_scale", 2)) == 2, "Refused type is returned as overflow, not silently dropped")
	_check(bag.can_accept("item_scale", 1) and bag.room_for("item_scale") == 996, "Existing stacks still accept while the bag is full")
	await _free(bag)


# ---------- 掉落组件 ----------
func _drop_checks() -> void:
	var root3d: Node3D = Node3D.new()
	root3d.name = "DropWorld"
	root.add_child(root3d)
	var player: CharacterBody3D = CharacterBody3D.new()
	player.collision_layer = 4
	root3d.add_child(player)
	player.global_position = Vector3(0, 0, 20)  # 先站远处
	var bag: Node = _new_bag()

	# 先塞到 997，再一次性给 5 个 → 装入 2、溢出 3 落地。
	bag.add_item("item_scale", 997)
	var result: Dictionary = bag.grant("item_scale", 5, Vector3.ZERO, root3d, player)
	var drop: Node3D = result.drop
	_check(int(result.accepted) == 2 and int(result.overflow) == 3, "Grant fills the stack and reports the overflow")
	_check(drop != null and int(drop.get("amount")) == 3, "Overflow becomes a ground drop with the remaining amount")
	_check(bag.count("item_scale") == 999, "Bag count stays at the 999 cap")

	# 背包满时靠近：不吞物品，给一次「背包已满」。
	drop.set("pickup_delay", 0.0)
	drop.set("retry_seconds", 0.0)
	var blocked: Array[int] = [0]
	drop.pickup_blocked.connect(func(_id: String, _left: int, _reason: String) -> void: blocked[0] += 1)
	var notices: Array[String] = []
	var notice_node: Node = Node.new()
	notice_node.set_script(load("res://tests/_notice_stub.gd"))
	notice_node.set("messages", notices)
	root.add_child(notice_node)
	drop.call("set_notice_target", notice_node)
	player.global_position = Vector3.ZERO
	await _frames(6)
	_check(int(drop.get("amount")) == 3 and bag.count("item_scale") == 999, "A full bag leaves the drop untouched")
	_check(blocked[0] >= 1, "Full-bag pickup emits a blocked signal")
	_check(not notices.is_empty() and str(notices.back()).contains("背包已满"), "Full-bag pickup pushes one non-blocking notice")

	# 腾出容量后站在原地再等一次（重试间隔已设 0）→ 分两次装完。
	bag.inventory.remove_item("item_scale", 2)
	await _frames(6)
	_check(int(drop.get("amount")) == 1 and bag.count("item_scale") == 999, "Capacity returns and the drop is partially collected")
	bag.inventory.remove_item("item_scale", 1)
	await _frames(8)
	_check(bag.count("item_scale") == 999, "The rest is collected on a later pass")
	_check(not is_instance_valid(drop) or drop.is_queued_for_deletion(), "An emptied drop destroys itself")

	# 重复拾取：同一帧连点两次只能结算一次。
	var again: Node3D = DROP_SCRIPT.spawn(root3d, bag, "fish_ring_scale", 1, Vector3(2, 0, 0), player) as Node3D
	again.set("pickup_delay", 0.0)
	again.set("auto_collect", false)
	var first: int = again.call("try_collect")
	var second: int = again.call("try_collect")
	_check(first == 1 and second == 0, "Repeated pickup calls cannot duplicate the item")
	_check(bag.count("fish_ring_scale") == 1, "Only one item reached the bag")

	# 堆叠已满：整个掉落留在地面，数量不变。
	_refill(bag, {"fish_ring_scale": 999})
	var stuck: Node3D = DROP_SCRIPT.spawn(root3d, bag, "fish_ring_scale", 2, Vector3(4, 0, 0), player) as Node3D
	stuck.set("auto_collect", false)
	_check(int(stuck.call("try_collect")) == 0 and int(stuck.get("amount")) == 2, "A full stack keeps the whole amount on the ground")

	# 已销毁的掉落不会再结算，也不会留下复制品。
	var ghost: Node3D = DROP_SCRIPT.spawn(root3d, bag, "fish_ring_scale", 1, Vector3(6, 0, 0), player) as Node3D
	ghost.set("auto_collect", false)
	ghost.queue_free()
	await _frames(2)
	_check(not is_instance_valid(ghost) and bag.count("fish_ring_scale") == 999, "A destroyed drop leaves no copy behind")

	await _free(notice_node)
	await _free(root3d)
	await _free(bag)


# ---------- 主场景 / 界面 ----------
func _scene_checks() -> void:
	var world: Node = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(8)
	var player: CharacterBody3D = world.player
	var loot: Node = world.loot
	var hud: Control = world.hud

	# 渔获格不是武器格：点在这里不会把鱼当成武器拿起，也不会误触攻击。
	_check(hud._cell_at(hud._loot_cell(0).get_center()) == Vector2i(-1, -1), "Loot cells are not weapon cells")
	_check(hud._loot_cell_at(hud._loot_cell(2).get_center()) == 2, "Loot grid hit-test matches the drawn cells")
	_check(not player.quick_slots.has("fish_pale_minnow") and not player.quick_slots.has("item_scale"), "Fish and materials never enter the quick bar")

	world.start_round(4)
	await _frames(6)
	var before_total: int = loot.total_items()
	var pickups_before: int = world.pickups.size()
	# 当前主流程：鱼先落在地上（蓝色光球），玩家靠近按 T 才入包。
	world._grant_loot("fish_pale_minnow", 1, Vector3(-8.0, 0.06, 16.0))
	await _frames(2)
	_check(world.pickups.size() == pickups_before + 1, "Fishing reward first lands on the shore")
	var catch: Node3D = world.pickups.back() if world.pickups.size() > 0 else null
	_check(loot.count("fish_pale_minnow") == 0, "The fish is not auto-stored before the player picks it up")
	if catch != null:
		catch.set("in_flight", false)
		catch.set("pickup_delay", 0.0)
		player.global_position = catch.global_position + Vector3(0, 0.1, 0)
		await _frames(2)
		_check(int(catch.call("try_collect")) == 1, "Walking to the catch stores exactly one fish")
	_check(loot.count("fish_pale_minnow") == 1 and loot.total_items() == before_total + 1, "Bag and HUD total follow the collected fish")
	_check(hud._messages.size() >= 1, "Pickup message shows up without blocking input")
	_check(not player.menu_open, "Awarding loot never opens the menu")
	_check(loot.count("item_fish_bone") == 0, "A plain fish does not auto-grant crafting materials")

	# 堆叠满 → 溢出留在地面，腾出容量后按次拾取。
	_refill(loot, {"fish_pale_minnow": 999})
	world._spawn_pickup("fish_pale_minnow", 2, Vector3(-6.0, 0.06, 14.0))
	var shore: Node3D = world.pickups.back()
	shore.set("in_flight", false)
	shore.set("pickup_delay", 0.0)
	player.global_position = shore.global_position + Vector3(0, 0.1, 0)
	await _frames(2)
	_check(int(shore.call("try_collect")) == 0 and int(shore.get("amount")) == 2, "Full stack keeps the whole amount on the ground")
	_refill(loot, {"fish_pale_minnow": 998})
	_check(int(shore.call("try_collect")) == 1, "One free slot collects exactly one")
	_check(loot.count("fish_pale_minnow") == 999 and int(shore.get("amount")) == 1, "Partial pick-up stores what fits and leaves the rest")
	_refill(loot, {"fish_pale_minnow": 997})
	_check(int(shore.call("try_collect")) == 1, "Coming back later collects the remainder once")
	await _frames(2)
	_check(loot.count("fish_pale_minnow") == 998 and not is_instance_valid(shore), "An emptied pickup destroys itself")

	# 跨死亡 / R 重试保留；重试不复制。
	_refill(loot, {"fish_pale_minnow": 12, "item_scale": 4})
	var kept_fish: int = loot.count("fish_pale_minnow")
	var kept_scale: int = loot.count("item_scale")
	world.start_round(4)
	await _frames(4)
	_check(loot.count("fish_pale_minnow") == kept_fish and loot.count("item_scale") == kept_scale, "R retry keeps earned items")
	player.hurt_time_left = 0.0
	player.receive_damage(999, player.global_position + Vector3(1, 0, 0))
	await _frames(10)
	player.health = player.max_health
	player.dead = false
	player.reset_to_spawn(true)
	await _frames(4)
	_check(loot.count("fish_pale_minnow") == kept_fish and loot.count("item_scale") == kept_scale, "Death keeps earned items")
	world.start_round(4)
	await _frames(4)
	world.start_round(4)
	await _frames(4)
	_check(loot.count("fish_pale_minnow") == kept_fish, "Repeated retries never duplicate counts")

	# 既有武器搬运不受影响。
	var storage_weapon: String = player.slot_item(1, 0)
	var hotbar_before: String = player.slot_item(0, 1)
	player.menu_open = true
	hud.open_loadout()
	if not storage_weapon.is_empty():
		hud._click_cell(Vector2i(1, 0))
		_check(hud._held_item == storage_weapon, "Weapon pick-up still works next to the loot grid")
		hud._click_cell(Vector2i(0, 1))
		_check(player.slot_item(0, 1) == storage_weapon and player.slot_item(1, 0) == hotbar_before, "Weapon still swaps into the hotbar")
	else:
		_check(false, "Storage row has a weapon to move")
	hud.close_loadout()
	player.menu_open = false
	# 恢复原状，避免影响后续手工试玩。
	player.set_slot_item(1, 0, storage_weapon)
	player.set_slot_item(0, 1, hotbar_before)
	await _frames(2)

	world.queue_free()
	await _frames(4)
