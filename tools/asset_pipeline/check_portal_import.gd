extends SceneTree
## Check real imported terrain collision, movement, and dodge integration.

const PlayerController = preload("res://scripts/mvp/player_3d.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/portal_ruins_preview.tscn") as PackedScene
	var sample: Node3D = packed.instantiate() as Node3D
	root.add_child(sample)
	await create_timer(1.0).timeout
	var player: PlayerController = sample.get_node("Player") as PlayerController
	var initial_floor: bool = player.is_on_floor()
	var start: Vector3 = player.global_position
	player.set_controls_active(true)
	Input.action_press("move_up")
	await create_timer(0.75).timeout
	Input.action_release("move_up")
	var distance: float = Vector2(player.position.x - start.x, player.position.z - start.z).length()
	await create_timer(0.2).timeout
	var dodge_started: bool = player.try_dodge(Vector3.RIGHT)
	await create_timer(0.6).timeout
	var result: Dictionary = {
		"spawn_on_imported_ground": initial_floor,
		"movement_distance_m": distance,
		"dodge_started": dodge_started,
		"floor_after_movement_and_dodge": player.is_on_floor(),
		"final_position": [player.position.x, player.position.y, player.position.z]
	}
	var passed: bool = initial_floor and distance > 1.0 and dodge_started and player.is_on_floor()
	result["passed"] = passed
	var file: FileAccess = FileAccess.open("res://docs/art/ue_portal_import/runtime_check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("PORTAL_IMPORT_CHECK " + JSON.stringify(result))
	sample.queue_free()
	await process_frame
	quit(0 if passed else 1)
