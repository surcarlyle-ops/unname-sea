extends SceneTree
## Capture current game scenes without HUDs for the destination menu. No source image editing.

var failed: bool = false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/trial_menu"))
	var entries: Array = [
		["combat", "res://scenes/combat_mvp.tscn"],
		["shore", "res://scenes/tests/shore_test_area_preview.tscn"],
		["valley", "res://scenes/cherry_valley.tscn"]
	]
	for entry: Array in entries:
		var packed: PackedScene = load(str(entry[1])) as PackedScene
		if packed == null:
			failed = true
			continue
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		if entry[0] == "valley":
			for i: int in range(1200):
				if bool(scene.get("build_complete")):
					break
				await process_frame
			if not bool(scene.get("build_complete")):
				failed = true
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		_hide_ui(scene)
		var camera: Camera3D = root.get_camera_3d()
		if camera == null:
			failed = true
		else:
			if entry[0] == "combat":
				camera.global_position = Vector3(14.0, 6.5, 16.0)
				camera.look_at(Vector3(0.0, 3.0, -5.0), Vector3.UP)
			elif entry[0] == "shore":
				camera.global_position = Vector3(11.0, 6.5, 8.0)
				camera.look_at(Vector3(0.0, 0.7, -14.0), Vector3.UP)
			else:
				var target: Vector3 = camera.global_position - camera.global_basis.z * 20.0
				camera.global_position += Vector3.UP
				camera.look_at(target, Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			var result: Error = root.get_texture().get_image().save_png("res://assets/ui/trial_menu/" + str(entry[0]) + ".png")
			failed = failed or result != OK
			print("MENU_ASSET ", entry[0], " saved=", result == OK)
		scene.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	print("MENU_ASSETS_RESULT ok=", not failed)
	quit(1 if failed else 0)


func _hide_ui(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	if node is Node3D and node.name == "Hands":
		(node as Node3D).visible = false
	for child: Node in node.get_children():
		_hide_ui(child)
