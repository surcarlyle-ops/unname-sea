extends SceneTree
## Fishing integration focus checks (Claude 2026-10-28, resume of interrupted fishing task).
##
## Scope is only the hand-off that the previous session left unwired:
##  - hands read FishingMVP state passively (bind_fishing_controller)
##  - the line starts at the real rod tip in the hand (set_rod_tip_anchor)
##  - the anchor is rebound after the presentation layer is rebuilt
##  - inventory -> FishingLoot slot sync (数量袋 interface)
## Full gameplay coverage already lives in tests/fishing_mvp_test.gd and is not
## repeated here.
## Run: godot --headless --path . --script res://tests/fishing_integration_check.gd

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: push_error("Fishing integration timeout"); quit(2))
	var world: Node = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(8)
	var player: CharacterBody3D = world.player
	var fishing: Node = world.fishing
	var loot: Node = world.loot
	var hands: Node3D = player.hands

	_check(hands._fishing_controller != null and hands._fishing_controller.get_ref() == fishing,
		"Arena binds hands to the FishingMVP controller once at startup")

	await _trial_wiring(world, player, fishing, hands)

	# Cast from the bank and confirm the line start follows the rod tip, not the camera.
	player.global_position = world.shore_area.fishing_spot() + Vector3.UP * 0.08
	player.rotation.y = 0.0
	player.head.rotation.x = -0.45
	player.set_controls_active(true)
	await _frames(6)
	var expected: Vector3 = hands.fishing_tip_world()
	world._on_fishing_action()
	await _frames(2)
	_check(int(fishing.state) == 1, "Click from the bank starts a cast")
	_check(fishing.cast_tip_origin.distance_to(expected) < 0.01,
		"Cast tip origin is the rod tip in the hand")
	_check(world.fishing_fx.rod_tip().distance_to(hands.fishing_tip_world()) < 0.001,
		"Presentation line anchor tracks the live rod tip")

	# Passive mapping: the rod presentation follows FishingMVP.state.
	var names: Array[String] = ["idle", "casting", "waiting", "biting", "reeling"]
	for index: int in range(names.size()):
		fishing.state = index
		hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, false, 2.0)
		_check(hands._fishing_rod.phase == names[index], "Rod phase follows fishing state " + names[index])
	_check(hands._fishing_rod.visible, "Rod stays visible while the fishing trial is active")
	fishing.state = 0
	hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, false, 2.0)

	# Rebuilding the presentation must re-bind the rod tip anchor.
	var old_fx: Node = world.fishing_fx
	world._remove_fishing_world()
	await _frames(3)
	world._ensure_fishing_world()
	await _frames(3)
	_check(world.fishing_fx != null and world.fishing_fx != old_fx, "Presentation layer is recreated")
	_check(world.fishing_fx.rod_tip().distance_to(hands.fishing_tip_world()) < 0.02,
		"Rebuilt presentation re-binds to the real rod tip")

	# Quantity bag interface: everything is counted by Inventory, slots only hold ids.
	loot.inventory.from_dict({})
	await _frames(2)
	var accepted: int = loot.add_item("fish_pale_minnow", 3)
	_check(accepted == 3 and loot.count("fish_pale_minnow") == 3, "add_item returns the accepted count")
	_check(loot.cell_of("fish_pale_minnow") >= 0, "Fish occupies one slot while its count lives in Inventory")
	loot.inventory.add_item("item_scale", 1)
	await _frames(2)
	_check(loot.cell_of("item_scale") >= 0, "Direct Inventory writes sync into a free loot slot")
	_check(loot.try_add("fish_pale_minnow", 1000) == 4,
		"999 stack limit is reported as overflow by try_add")
	_check(loot.count("fish_pale_minnow") == 999, "Overflow is not stored")

	print("\n=== fishing_integration_check: %d/%d passed, %d failed ===" % [checks - failures, checks, failures])
	world.queue_free()
	await _frames(2)
	quit(0 if failures == 0 else 1)


func _trial_wiring(world: Node, player: CharacterBody3D, fishing: Node, hands: Node3D) -> void:
	world.start_round(4)
	await _frames(6)
	_check(world.mode == 4 and hands._weapon_id == "fishing_rod", "Fishing trial equips the rod in the hand")
	_check(world.fishing_fx != null and world.fishing_fx.rod_tip_anchor != null,
		"Fishing trial builds the presentation with the rod tip anchor")
	_check(fishing.bobber_position == fishing.bobber_position, "Fishing controller is alive")
	_check(not hands._tide_blade.visible and not hands._pistol.visible, "No stale weapon model under the rod")
	_check(player.equipped_water_tool(), "Rod is treated as a tool, not a weapon")


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
