extends SceneTree
## 实机截图（本轮的视觉证据）：背包里的鱼与材料、堆叠已满、岸边掉落。
## 运行：godot --path . --script res://tests/_capture_loot_bag.gd
## 产物：.mvp_qa/loot_bag/open.png / full.png / shore_drop.png

const OUT_DIR: String = "res://.mvp_qa/loot_bag/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var world: Node = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(8)
	var player: CharacterBody3D = world.player
	var loot: Node = world.loot
	var hud: Control = world.hud

	world.start_round(4)
	await _frames(10)
	# 1) 正常收获：两种鱼 + 壳片（材料沿用 item_scale），打开背包。
	loot.inventory.from_dict({"fish_pale_minnow": 3, "fish_ring_scale": 12, "item_scale": 250})
	player.menu_open = true
	hud.open_loadout()
	hud._loot_selected = 1
	await _capture("open")

	# 2) 堆叠满：999 上限 + 溢出落地的提示。
	loot.inventory.from_dict({"fish_pale_minnow": 999, "fish_ring_scale": 12, "item_scale": 250})
	hud._loot_hover = 0
	hud._loot_selected = 0
	await _capture("full")

	# 3) 岸边掉落：背包满时多出来的鱼留在岸上，靠近可拾取。
	player.menu_open = false
	hud.close_loadout()
	var bobber: Vector3 = Vector3(-8.0, 0.06, 11.2)
	var got: Dictionary = loot.grant("fish_pale_minnow", 3, bobber, world, player, hud)
	player.global_position = Vector3(-8.0, 0.1, 8.6)
	player.rotation.y = PI
	player.head.rotation.x = -0.35
	await _frames(12)
	print("shore drop spawned: ", got.overflow)
	await _capture("shore_drop")
	world.queue_free()
	await _frames(4)
	quit(0)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(OUT_DIR + label + ".png")
	print("saved ", OUT_DIR + label + ".png")
