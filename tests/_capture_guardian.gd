extends SceneTree
## (CodeBuddy) Throwaway verification for the guardian: measures body travel and
## mesh drift per mode, and captures the lunge on open ground and against the wall.

const OUT_DIR: String = "res://.cv_qa/guardian"

var scene: Node3D
var guardian: CharacterBody3D
var log_file: FileAccess


func _initialize() -> void:
	_run.call_deferred()


func _note(message: String) -> void:
	print(message)
	if log_file != null:
		log_file.store_line(message)
		log_file.flush()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	log_file = FileAccess.open(ProjectSettings.globalize_path(OUT_DIR).path_join("verify.log"), FileAccess.WRITE)
	scene = (load("res://scenes/tests/ruin_guardian_preview.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(0.8).timeout
	guardian = scene.guardian
	_note("MODEL scale=%.2f  clip=%.3fs  baked_lunge=%.4f units -> %.2f m" % [
		guardian.MODEL_SCALE, guardian.clip_length, guardian.travel_units, guardian.world_lunge()])
	# Side view so the forward travel is readable in the stills.
	scene._yaw = 1.52
	scene._pitch = -0.16
	scene._distance = 9.0
	await create_timer(0.3).timeout

	# --- A. raw clip: the mesh moves, the collider does not -----------------------
	await _run_mode(0, "A_animation_mode", false, true)
	# --- B. root motion on open ground -------------------------------------------
	await _run_mode(1, "B_root_motion_ground", false, true)
	# --- C. root motion against the wall -----------------------------------------
	await _run_mode(1, "C_root_motion_wall", true, false)
	# --- D. feet on the ground during the crouch hold -----------------------------
	_reset()
	guardian.set_drive_mode(1)
	guardian.play_attack()
	await create_timer(1.3).timeout
	scene._yaw = 1.15
	scene._pitch = -0.03
	scene._distance = 3.4
	scene._focus_height = 0.32
	await create_timer(0.3).timeout
	await _capture("D_feet_closeup")
	_note("DONE")
	log_file.close()
	quit(0)


func _reset() -> void:
	guardian.cancel_attack()
	guardian.global_position = Vector3.ZERO
	guardian.rotation.y = 0.0
	guardian.mark_spawn()
	scene._set_wall(false)
	Engine.time_scale = 1.0


func _run_mode(mode: int, label: String, wall: bool, captures: bool) -> void:
	_reset()
	guardian.set_drive_mode(mode)
	if wall:
		scene._set_wall(true)
	await create_timer(0.25).timeout
	guardian.play_attack()
	var samples: int = 12
	var step: float = 0.42
	for i: int in range(samples):
		await create_timer(step).timeout
		_note("%s  t=%.2f  body=%.3f m  drift=%.3f m  z=%.3f  dmg=%s" % [
			label, guardian.clip_time(), guardian.body_travel(), guardian.mesh_drift(),
			guardian.global_position.z, str(guardian.damage_window_active())])
		if captures and i == 6:
			await _capture(label + "_mid")
	if captures:
		# One frame right at the damage window. Polled on clip time instead of a
		# timer, so time_scale cannot throw the moment off.
		_reset()
		guardian.set_drive_mode(mode)
		guardian.play_attack()
		var guard: int = 0
		while guardian.clip_time() < 3.30 and guard < 600:
			await process_frame
			guard += 1
		await _capture(label + "_impact")
	await create_timer(0.4).timeout


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name + ".png")
	image.save_png(path)
	_note("SAVED " + path)
