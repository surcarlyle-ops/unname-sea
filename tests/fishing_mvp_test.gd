extends SceneTree
## Fishing MVP checks (CodeBuddy 2026-10-28).
##
## Covers the approved acceptance scope: normal catch, repeated clicks, missed
## bite, cancel, weapon switch / grapple cleanup, distance limit, pause, death /
## retry, full bag and encounter recovery, plus a batch simulation of the bite
## distribution and a different-frame-rate comparison.
## Run: godot --headless --path . --script res://tests/fishing_mvp_test.gd

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(150.0).timeout.connect(func() -> void: push_error("Fishing test timeout"); quit(2))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fishing_mvp.json")) as Dictionary
	await _simulate_distribution(config)
	await _simulate_frame_rates(config)
	await _world_checks(config)
	print("\n=== fishing_mvp_test: %d/%d passed, %d failed ===" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- helpers ----------
func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		await process_frame


func _new_logic(config: Dictionary, seed_value: int) -> Node:
	var logic: Node = load("res://scripts/mvp/fishing_mvp.gd").new()
	logic.config = config
	root.add_child(logic)
	logic.seed_rng(seed_value)
	return logic


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
		await _frames(2)


## Drives the logic with a fixed 60 Hz step and auto-reels. Returns stats.
## Reveal now fires after a short delay (reveal_seconds); the manual 60 Hz
## driver advances it with one big step so sampling stays cheap.
func _press_reveal(logic: Node) -> void:
	logic._process(float(logic.config.get("reveal_seconds", 0.35)) + 0.01)


func _drive(logic: Node, seconds: float, auto_reel: bool) -> Dictionary:
	var step: float = 1.0 / 60.0
	var waits: Array[float] = []
	var windows: Array[float] = []
	var results: Array[String] = []
	var missed: int = 0
	var waited: float = 0.0
	var elapsed: float = 0.0
	var miss_flag: Array[int] = [0]
	logic.bite_missed.connect(func() -> void: miss_flag[0] += 1)
	logic.result_revealed.connect(func(outcome: String, _id: String, _m: String) -> void: results.append(outcome))
	logic.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	while elapsed < seconds:
		var state_before: int = int(logic.state)
		logic._process(step)
		elapsed += step
		if state_before == 2:
			waited += step
			if int(logic.state) == 3:
				waits.append(waited)
				windows.append(float(logic.bite_window_left()))
				waited = 0.0
		if int(logic.state) == 3 and auto_reel:
			logic.reel_bite()
			_press_reveal(logic)
		if int(logic.state) == 0 and int(state_before) != 0:
			# Reveal finished: start the next cast to keep sampling.
			logic.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	missed = miss_flag[0]
	return {"waits": waits, "windows": windows, "results": results, "missed": missed}


func _outcomes_since(logic: Node, mark: int) -> Array[String]:
	var outcomes: Array[String] = []
	for index: int in range(mark, logic.history.size()):
		outcomes.append(str(logic.history[index].outcome))
	return outcomes


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


# ---------- simulation ----------
func _simulate_distribution(config: Dictionary) -> void:
	var logic: Node = _new_logic(config, 20261028)
	var stats: Dictionary = await _drive(logic, 6000.0, true)
	var waits: Array = stats.waits
	var windows: Array = stats.windows
	var mean_wait: float = _mean(waits)
	var mean_window: float = _mean(windows)
	print("Simulated bites: %d, mean wait %.2f s, mean window %.2f s" % [waits.size(), mean_wait, mean_window])
	_check(waits.size() >= 700, "Batch simulation produced a large bite sample (%d)" % waits.size())
	_check(absf(mean_wait - logic.expected_bite_seconds()) < 0.35, "Mean bite wait %.2f s matches the wiki-derived %.2f s" % [mean_wait, logic.expected_bite_seconds()])
	_check(absf(mean_wait - 3.10) < 0.4, "FP 66 mean wait is near Terraria's ~3.10 s reference (%.2f s)" % mean_wait)
	var min_wait: float = INF
	var max_wait: float = 0.0
	for value: float in waits:
		min_wait = minf(min_wait, value)
		max_wait = maxf(max_wait, value)
	_check(max_wait - min_wait > 1.0, "Bite timing is random, not a fixed 3 s countdown (%.2f–%.2f s)" % [min_wait, max_wait])
	var expected_window: float = logic.expected_window_seconds()
	print("Window: initial mean %.2f s (range 0.65–5.10), effective mean %.2f s" % [mean_window, expected_window])
	_check(mean_window > 2.0 and mean_window < 5.2, "Reel window starts inside the FP-66 range (%.2f s)" % mean_window)
	_check(expected_window > 1.2 and expected_window < 2.0, "Decay makes the effective window ~1.5 s (%.2f s)" % expected_window)
	var outcomes: Dictionary = {}
	for outcome: String in stats.results:
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
	var total: float = float(stats.results.size())
	var fish_ratio: float = float(outcomes.get("fish", 0)) / maxf(total, 1.0)
	var monster_ratio: float = float(outcomes.get("monster", 0)) / maxf(total, 1.0)
	print("Outcome split: fish %.1f%%, monster %.1f%%" % [fish_ratio * 100.0, monster_ratio * 100.0])
	_check(absf(fish_ratio - 0.8) < 0.05, "Fish share is about 80%")
	_check(absf(monster_ratio - 0.2) < 0.05, "Encounter share is about 20%")

	# Missed bite: bobber stays in water, no reward, no extra escape roll.
	var misses: Array[int] = [0]
	var rewards: Array[int] = [0]
	logic.bite_missed.connect(func() -> void: misses[0] += 1)
	logic.result_revealed.connect(func(_a: String, _b: String, _c: String) -> void: rewards[0] += 1)
	logic.cancel_silent("test")
	logic.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	var step: float = 1.0 / 60.0
	var guard: int = 0
	while int(logic.state) != 3 and guard < 20000:
		logic._process(step)
		guard += 1
	var before_state: int = int(logic.state)
	logic._process(float(logic.bite_window_left()) + 0.1)
	_check(before_state == 3 and int(logic.state) == 2, "Missing the window returns to WAITING")
	_check(bool(logic.bobber_in_water()), "Bobber stays in the water after a missed bite")
	_check(misses[0] == 1 and rewards[0] == 0, "A missed bite gives no reward and no extra penalty")
	# Cancel after miss: normal cancel, no reward.
	logic.cancel_waiting()
	_check(int(logic.state) == 0 and rewards[0] == 0, "Early reel cancels without a reward")
	# F7 is not consumed by a cancelled cast.
	logic.force = 1
	logic.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	_check(int(logic.force) == 1, "F7 flag survives a cast (not consumed on cast)")
	logic.cancel_silent("switch")
	logic.force = 0
	await _free(logic)


func _simulate_frame_rates(config: Dictionary) -> void:
	var low: Node = _new_logic(config, 77)
	var high: Node = _new_logic(config, 78)
	var low_stats: Dictionary = await _drive_at(low, 600.0, 1.0 / 30.0)
	var high_stats: Dictionary = await _drive_at(high, 600.0, 1.0 / 144.0)
	var low_mean: float = _mean(low_stats.waits)
	var high_mean: float = _mean(high_stats.waits)
	print("Frame-rate comparison: 30 Hz %.2f s (n=%d), 144 Hz %.2f s (n=%d)" % [low_mean, low_stats.waits.size(), high_mean, high_stats.waits.size()])
	_check(absf(low_mean - high_mean) < 0.3, "Mean bite wait does not depend on frame rate")
	_check(low_stats.waits.size() > 60 and high_stats.waits.size() > 60, "Both frame rates keep producing bites")
	await _free(low)
	await _free(high)


func _drive_at(logic: Node, seconds: float, step: float) -> Dictionary:
	var waits: Array[float] = []
	var waited: float = 0.0
	var elapsed: float = 0.0
	logic.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	while elapsed < seconds:
		var state_before: int = int(logic.state)
		logic._process(step)
		elapsed += step
		if state_before == 2:
			waited += step
			if int(logic.state) == 3:
				waits.append(waited)
				waited = 0.0
		if int(logic.state) == 3:
			logic.reel_bite()
			_press_reveal(logic)
		if int(logic.state) == 0 and int(state_before) != 0:
			logic.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	return {"waits": waits}


# ---------- world / integration ----------
func _world_checks(config: Dictionary) -> void:
	var world: Node = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(8)
	var player: CharacterBody3D = world.player
	var fishing: Node = world.fishing
	var loot: Node = world.loot

	# Rod hand-off: empty 2nd slot gets the rod; an occupied slot is not overwritten.
	world.start_round(4)
	await _frames(6)
	_check(world.mode == 4, "K-style fishing trial enters mode 4")
	_check(player.quick_slots[1] == "fishing_rod", "Rod lands in the empty 2nd quick slot")
	_check(player.quick_slots[0] == "tide_blade" and player.quick_slots[2] == "steam_pistol", "Other equipment is untouched")
	_check(player.selected_slot == 1 and player.equipped_water_tool(), "Rod is selected and recognised as a tool")
	_check(world.get_node_or_null("FishingWorld") != null, "Fishing trial builds pond, bank and combat clearing")
	player.quick_slots[1] = ""
	world.rod_granted = false
	player.quick_slots[1] = "potion"
	world._ensure_rod()
	_check(player.quick_slots[1] == "potion", "Occupied 2nd slot is never silently overwritten")
	_check(world.rod_granted, "Rod hand-off only runs once")
	player.quick_slots[1] = "fishing_rod"
	player.selected_slot = 1
	player._refresh_weapon()
	await _frames(4)

	# Left click on the rod is a tool action, never an attack.
	var attacks: Array[int] = [0]
	player.attack_started.connect(func() -> void: attacks[0] += 1)
	player.water_tool_used.emit()
	await _frames(2)
	_check(attacks[0] == 0, "Rod click does not start a weapon attack")

	# Valid cast from the bank toward the pond (spawn yaw already faces the water).
	player.global_position = Vector3(-8.0, 0.08, 10.0)
	player.rotation.y = PI
	player.head.rotation.x = -0.5
	await _frames(3)
	var eye: Vector3 = player.camera.global_position
	var check_result: Dictionary = fishing.resolve_cast(eye, -player.camera.global_basis.z)
	_check(check_result.has("point") and bool(world._inside_pond(check_result.point as Vector3)), "Cast aiming at the marked pond resolves a water point")
	var invalid: Dictionary = fishing.resolve_cast(eye, Vector3(0, 0, -1))
	_check(invalid.has("reason"), "Aiming at flat ground is refused with a reason")

	# Cast, then repeated clicks must not re-cast or double-award.
	fishing.force = 1  # F7: next valid catch is a fish
	var fish_mark: int = fishing.history.size()
	world._on_fishing_action()
	await _frames(2)
	_check(int(fishing.state) == 1, "Click casts once")
	for _i: int in range(5):
		world._on_fishing_action()
	_check(int(fishing.state) == 1, "Rapid clicks during the cast do nothing")
	await _frames(30)
	_check(int(fishing.state) == 2, "Cast settles into WAITING after about 0.4 s")
	var state_guard: int = 0
	while int(fishing.state) == 2 and state_guard < 4000:
		await _frames(1)
		state_guard += 1
	_check(int(fishing.state) == 3, "Bite starts from the random check")
	var fish_before: int = loot.count("fish_pale_minnow") + loot.count("fish_ring_scale")
	for _i: int in range(4):
		world._on_fishing_action()
	await _frames(30)
	var fish_after: int = loot.count("fish_pale_minnow") + loot.count("fish_ring_scale")
	_check(fish_after - fish_before == 1, "One catch awards exactly one item despite repeated clicks")
	_check(not _outcomes_since(fishing, fish_mark).is_empty() and _outcomes_since(fishing, fish_mark).back() == "fish", "F7 forces the next valid catch to be a fish")
	await _frames(240)

	# Cancel: cast then reel without a bite → no reward.
	var total_before: int = loot.total_items()
	world._on_fishing_action()
	await _frames(30)
	var cancel_state: int = int(fishing.state)
	world._on_fishing_action()
	await _frames(4)
	_check(cancel_state == 2 and int(fishing.state) == 0, "Early reel cancels the cast")
	_check(loot.total_items() == total_before, "Cancel gives no reward")

	# Weapon switch cleans the fishing state before switching.
	player.select_slot(1)
	await _frames(2)
	fishing.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	await _frames(4)
	var switch_state: int = int(fishing.state)
	player.select_slot(0)
	await _frames(2)
	_check(switch_state != 0 and int(fishing.state) == 0 and int(player.selected_slot) == 0, "Switching equipment cleans up fishing first")
	var before_grapple_rewards: int = loot.total_items()
	player.grapple_requested.emit()
	await _frames(2)
	_check(int(fishing.state) == 0 and loot.total_items() == before_grapple_rewards, "Grapple cleanup cancels fishing without rewards")

	# Distance limit: walk the player away from the bobber.
	player.set_slot_item(0, 1, "fishing_rod")
	await _frames(2)
	fishing.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	await _frames(30)
	_check(int(fishing.state) == 2, "Distance check runs while the bobber is in water")
	player.global_position = Vector3(-8.0, 0.1, 32.5)
	var auto: Array[int] = [0]
	fishing.auto_reeled.connect(func(_d: float) -> void: auto[0] += 1)
	await _frames(4)
	_check(int(fishing.state) == 0 and auto[0] == 1, "Walking past 16 m auto-reels with a notice")
	player.global_position = Vector3(-8.0, 0.08, 9.0)
	await _frames(3)

	# Pause freezes the timers.
	fishing.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	await _frames(30)
	var counter_before: int = int(fishing.counter())
	world._toggle_loadout()
	await _frames(120)
	_check(int(fishing.counter()) == counter_before and int(fishing.state) == 2, "Pause freezes the fishing timer")
	world._toggle_loadout()
	await _frames(30)
	_check(int(fishing.counter()) != counter_before or int(fishing.state) != 2, "Closing the menu resumes fishing")

	# Encounter: forced monster, spawn distance, delayed chase, auto weapon.
	if player.menu_open:
		world._toggle_loadout()
		await _frames(2)
	player.select_slot(1)
	player.global_position = Vector3(-8.0, 0.08, 10.0)
	player.rotation.y = PI
	player.head.rotation.x = -0.5
	await _frames(3)
	fishing.cancel_silent("test")
	fishing.force = 2
	world._on_fishing_action()
	_check(int(fishing.state) == 1, "Forced encounter cast starts from the bank")
	await _frames(30)
	var bite_guard: int = 0
	while int(fishing.state) == 2 and bite_guard < 4000:
		await _frames(1)
		bite_guard += 1
	var items_before: int = loot.total_items()
	_check(int(fishing.state) == 3, "Forced encounter reaches the bite window")
	world._on_fishing_action()
	# Result/encounter signals fire after the reveal delay (about 0.35 s).
	await _frames(30)
	var spawned: bool = is_instance_valid(world.encounter_enemy)
	_check(spawned, "Forced encounter spawns one creature")
	var spawn_distance: float = Vector2(world.encounter_enemy.global_position.x - player.global_position.x, world.encounter_enemy.global_position.z - player.global_position.z).length() if spawned else 0.0
	_check(spawn_distance >= 5.0, "Spawn point is at least 5 m from the player (%.2f m)" % spawn_distance)
	_check(not world._spot_blocked(world.encounter_enemy.global_position) if spawned else false, "Spawn point is not inside geometry")
	_check(world.encounter_enemy.target == null, "Creature does not chase immediately")
	_check(bool(fishing.encounter_active) and not player.equipped_water_tool(), "Encounter switches to a combat weapon automatically")
	_check(loot.total_items() == items_before, "Encounter does not award loot on spawn")
	var casts_after: int = 0
	fishing.cast_started.connect(func(_p: Vector3) -> void: casts_after += 1)
	world._on_fishing_action()
	_check(casts_after == 0 and bool(fishing.encounter_active), "No new cast while the creature is alive")
	await _frames(60)
	_check(world.encounter_enemy.target == player, "Creature starts chasing after about 0.8 s")
	player.set_controls_active(true)
	var hits_before: int = 0
	while spawned and is_instance_valid(world.encounter_enemy) and not world.encounter_enemy.dead and hits_before < 200:
		world.encounter_enemy.apply_damage(50, Vector3.ZERO)
		hits_before += 1
		await _frames(1)
	await _frames(6)
	_check(not is_instance_valid(world.encounter_enemy) or world.encounter_enemy == null, "Defeated creature releases the encounter")
	_check(not bool(fishing.encounter_active), "After defeat fishing is allowed again")
	_check(world.pickups.size() == 1, "Defeat drops one material pickup")
	var shell_before: int = loot.count("item_scale")
	if world.pickups.size() == 1:
		player.global_position = world.pickups[0].global_position + Vector3(0, 0.1, 0)
		await _frames(6)
	_check(loot.count("item_scale") - shell_before == 1, "Walking onto the pickup collects the material")
	await _frames(4)

	# Full bag: overflow becomes a bank pickup; pickup notices are non-blocking.
	loot.inventory.from_dict({"fish_pale_minnow": 999})
	loot.slots[0] = "fish_pale_minnow"
	var pickups_before: int = world.pickups.size()
	world._grant_loot("fish_pale_minnow", 1, Vector3(-8.0, 0.06, 16.0))
	_check(loot.count("fish_pale_minnow") == 999, "Stack limit 999 is respected")
	_check(world.pickups.size() == pickups_before + 1, "Overflow is left on the bank as a pickup")
	var overflow_point: Vector3 = world.pickups.back().global_position if world.pickups.size() > 0 else Vector3.ZERO
	_check(not world._inside_pond(overflow_point), "Overflow pickup sits on the bank, not mid-water")
	_check(player.controls_active, "Full-bag notice does not block operations")
	loot.inventory.from_dict({"fish_pale_minnow": 5})
	await _frames(2)

	# Death / retry: unresolved state is cleared and already-earned items stay.
	fishing.begin_cast(Vector3.ZERO, Vector3(-8.0, 0.06, 16.0))
	var kept_before: int = loot.count("fish_pale_minnow")
	fishing.force = 2
	world.start_round(4)
	await _frames(6)
	_check(int(fishing.state) == 0 and int(fishing.force) == 0, "Retry clears the cast and a pending dev command")
	_check(loot.count("fish_pale_minnow") == kept_before, "Items earned this session survive a retry")
	player.hurt_time_left = 0.0
	player.receive_damage(999, player.global_position + Vector3(1, 0, 0))
	await _frames(20)
	_check(bool(player.dead) and int(fishing.state) == 0 and not bool(fishing.encounter_active), "Death clears fishing and the encounter")
	player.health = player.max_health
	player.dead = false
	player.reset_to_spawn(true)
	await _frames(6)
	_check(int(fishing.state) == 0, "Reset after death leaves fishing idle")

	# Switching trial also clears the trial state and the pond.
	world.start_round(3)
	await _frames(4)
	_check(int(fishing.state) == 0 and world.get_node_or_null("FishingWorld") == null, "Switching trials clears fishing and its world")

	world.queue_free()
	await _frames(4)
