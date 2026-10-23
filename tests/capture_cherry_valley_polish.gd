extends SceneTree
## (CodeBuddy) Fixed-camera before/after capture + walk validation for the cherry
## valley polish pass. Every camera here is hard-coded so the "before" run and the
## "after" run can be compared pixel by pixel.
##
##   godot --path <project> --script res://tests/capture_cherry_valley_polish.gd -- <tag>
##
## <tag> is appended to the file names (before / after). Output: .cv_qa/codebuddy_polish/

const OUT_DIR: String = "res://.cv_qa/codebuddy_polish"

var world: Node3D
var tag: String = "run"
var report: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = str(args[0])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	world = (load("res://scenes/cherry_valley.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process_unhandled_input(false)
	var waited: int = 0
	while not bool(world.build_complete) and waited < 3000:
		await process_frame
		waited += 1
	if not bool(world.build_complete):
		push_error("Cherry valley did not build for capture")
		quit(2)
		return
	world.player.set_process_unhandled_input(false)
	world.player.set_physics_process(false)
	await create_timer(0.8).timeout

	# ---- fixed comparison cameras -------------------------------------------------
	await _shot("01_spawn", Vector3(22.0, 0.0, 70.0), Vector3(6.0, 3.4, 18.0), 78.0, 1.66)
	await _shot("02_bridge", Vector3(-3.0, 2.4, 18.0), Vector3(-15.0, 1.4, 5.0), 70.0, 0.0)
	await _shot("03_riverside", Vector3(3.0, 0.0, 26.0), Vector3(-15.0, 1.6, 6.0), 68.0, 1.15)
	await _shot("04_waterfall", Vector3(-16.0, 2.4, -58.0), Vector3(-22.0, 10.0, -88.0), 66.0, 0.0)

	# ---- mood sweep from one fixed vantage ---------------------------------------
	var mood_camera: Camera3D = _make_camera("MoodCheck", Vector3(6.0, 12.0, 46.0), Vector3(-12.0, 1.0, 2.0), 62.0)
	for mood: String in ["blue_hour", "morning", "rain"]:
		world._apply_mood(mood)
		mood_camera.current = true
		await create_timer(1.1).timeout
		await _capture("05_mood_%s" % mood)
		report["mood_%s_luma" % mood] = await _frame_luma()
	mood_camera.queue_free()
	world._apply_mood("blue_hour")
	await create_timer(0.4).timeout

	# ---- the actual first-person spawn view --------------------------------------
	world.player.set_physics_process(true)
	world.player.reset_to_spawn(true)
	await create_timer(0.5).timeout
	await _capture("06_spawn_first_person")

	# ---- frame rate at the bridge view ------------------------------------------
	var fps_camera: Camera3D = _make_camera("FpsCheck", Vector3(-3.0, 2.4, 18.0), Vector3(-15.0, 1.4, 5.0), 70.0)
	fps_camera.current = true
	await create_timer(1.5).timeout
	var fps_total: float = 0.0
	for i: int in range(4):
		await create_timer(0.6).timeout
		fps_total += float(Engine.get_frames_per_second())
	report["fps"] = snappedf(fps_total / 4.0, 0.1)
	report["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	report["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	report["terrain_triangles"] = int(world.terrain.sizes.get("terrain_triangles", 0))
	fps_camera.queue_free()

	# ---- walk from spawn to the far side of the bridge ---------------------------
	await _walk_check()
	report["build_frames"] = waited
	report["tag"] = tag
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join("report_%s.json" % tag)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("POLISH_REPORT ", JSON.stringify(report))
	quit(0)


func _make_camera(node_name: String, position: Vector3, target: Vector3, fov: float) -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.name = node_name
	camera.fov = fov
	camera.far = 1200.0
	world.add_child(camera)
	camera.global_transform = Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)
	return camera


## Camera whose height is resolved from the terrain so the framing stays identical
## even if the ground profile is reshaped.
func _shot(file_name: String, position: Vector3, target: Vector3, fov: float, ground_anchored: float) -> void:
	var resolved: Vector3 = position
	if ground_anchored > 0.0:
		resolved.y = float(world.terrain.height_at(position.x, position.z)) + ground_anchored
	var camera: Camera3D = _make_camera("Shot_" + file_name, resolved, target, fov)
	camera.current = true
	await create_timer(0.55).timeout
	await _capture(file_name)
	camera.queue_free()


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join("%s_%s.png" % [file_name, tag])
	image.save_png(path)
	print("SAVED: ", path)


## Average luminance + the share of near-white pixels, so "washed out" is measured
## rather than eyeballed.
func _frame_luma() -> Dictionary:
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	image.resize(96, 54, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	var blown: int = 0
	var dark: int = 0
	var count: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			total += luma
			if luma > 0.93:
				blown += 1
			if luma < 0.045:
				dark += 1
			count += 1
	return {
		"luma": snappedf(total / float(maxi(count, 1)), 0.001),
		"blown_ratio": snappedf(float(blown) / float(maxi(count, 1)), 0.001),
		"dark_ratio": snappedf(float(dark) / float(maxi(count, 1)), 0.001),
	}


# ---------------------------------------------------------------- walk validation

## Drive the real controller along the configured path, then over the bridge, and
## record stalls, falls through the floor and the step heights at both bridge heads.
func _walk_check() -> void:
	var terrain: Node3D = world.terrain
	var points: Array[Vector2] = []
	for path_spec: Dictionary in world.config.terrain.paths:
		if str(path_spec.name) != "SpawnToBridge":
			continue
		for point: Array in path_spec.points:
			points.append(Vector2(float(point[0]), float(point[1])))
	# Continue across the bridge to the shrine side so the deck is walked end to end.
	var bridge: Dictionary = world.config.village.bridge
	var center: Vector2 = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	points.append(Vector2(center.x + 9.0, center.y + 0.6))
	points.append(Vector2(center.x, center.y))
	points.append(Vector2(center.x - 9.0, center.y - 0.6))
	points.append(Vector2(center.x - 14.0, center.y - 3.0))

	var player: CharacterBody3D = world.player
	player.reset_to_spawn(true)
	player.set_physics_process(true)
	player.set_controls_active(true)
	await physics_frame
	await physics_frame

	var start: Vector3 = player.global_position
	var stalls: Array[String] = []
	var worst_penetration: float = 0.0
	var lowest: float = 0.0
	var index: int = 0
	var best: float = 1e9
	var best_age: float = 0.0
	var elapsed: float = 0.0
	var deck_min: float = 1e9
	var deck_max: float = -1e9
	var samples: Array[Dictionary] = []
	while index < points.size() and elapsed < 120.0:
		var target: Vector2 = points[index]
		var position: Vector3 = player.global_position
		var flat: Vector2 = Vector2(position.x, position.z)
		var to_target: Vector2 = target - flat
		var distance: float = to_target.length()
		if distance < 1.8:
			index += 1
			best = 1e9
			best_age = 0.0
			continue
		var direction: Vector2 = to_target.normalized()
		var basis: Basis = player.global_basis
		player.set_touch_move(Vector2(direction.dot(Vector2(basis.x.x, basis.x.z)), direction.dot(Vector2(basis.z.x, basis.z.z))))
		await physics_frame
		elapsed += 1.0 / 60.0
		var ground: float = float(terrain.height_at(player.global_position.x, player.global_position.z))
		var delta: float = player.global_position.y - ground
		worst_penetration = minf(worst_penetration, delta)
		lowest = minf(lowest, delta)
		# The bridge deck is above the terrain; record the deck height range there.
		if absf(player.global_position.x - center.x) < 8.0 and absf(player.global_position.z - center.y) < 6.0:
			deck_min = minf(deck_min, player.global_position.y)
			deck_max = maxf(deck_max, player.global_position.y)
		if samples.size() < 4000:
			samples.append({"t": snappedf(elapsed, 0.01), "x": snappedf(player.global_position.x, 0.01), "y": snappedf(player.global_position.y, 0.01), "z": snappedf(player.global_position.z, 0.01), "wp": index})
		if distance < best - 0.05:
			best = distance
			best_age = 0.0
		else:
			best_age += 1.0 / 60.0
			if best_age > 2.5:
				stalls.append("waypoint %d stuck at (%.1f, %.1f) distance %.1f" % [index, player.global_position.x, player.global_position.z, distance])
				index += 1
				best = 1e9
				best_age = 0.0
	player.set_touch_move(Vector2.ZERO)
	var end: Vector3 = player.global_position
	report["walk"] = {
		"waypoints_done": index,
		"waypoints_total": points.size(),
		"seconds": snappedf(elapsed, 0.1),
		"start": [snappedf(start.x, 0.1), snappedf(start.y, 0.1), snappedf(start.z, 0.1)],
		"end": [snappedf(end.x, 0.1), snappedf(end.y, 0.1), snappedf(end.z, 0.1)],
		"stalls": stalls,
		"worst_ground_delta": snappedf(worst_penetration, 0.01),
		"deck_y_min": snappedf(deck_min, 0.01) if deck_min < 1e8 else null,
		"deck_y_max": snappedf(deck_max, 0.01) if deck_max > -1e8 else null,
	}
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join("walk_%s.json" % tag)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"tag": tag, "samples": samples}, "  "))
		file.close()
