extends SceneTree

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	print("\n=== 通用背包系统测试 ===")
	
	var inv: Inventory = Inventory.new()
	inv.setup(15, 999)
	var accepted: int = inv.add_item("fish_pale_minnow", 5)
	_check("添加5条鱼", accepted == 5 and inv.get_count("fish_pale_minnow") == 5)
	
	inv = Inventory.new()
	inv.setup(15, 999)
	inv.add_item("weapon_1", 1)
	inv.add_item("weapon_2", 1)
	_check("两种物品占两格", inv.used_slots() == 2)
	
	inv = Inventory.new()
	inv.setup(15, 999)
	inv.add_item("fish_x", 5)
	inv.delete_to_trash("fish_x", 3)
	_check("删除到垃圾槽", inv.trash_item == "fish_x")
	inv.restore_from_trash()
	_check("从垃圾槽恢复", inv.get_count("fish_x") == 5)
	
	inv = Inventory.new()
	inv.setup(15, 999)
	inv.add_item("material_a", 999)
	accepted = inv.add_item("material_a", 10)
	_check("达到上限返回0", accepted == 0)
	
	print("\n结果：%d 通过，%d 失败\n" % [passed, failed])
	await get_tree().process_frame
	get_tree().quit()

func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  ✓ %s" % label)
	else:
		failed += 1
		print("  ✗ %s" % label)
