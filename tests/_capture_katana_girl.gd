extends SceneTree
## (CodeBuddy) Throwaway: capture the katana girl preview and report the material
## bindings, so the import can be judged from pixels instead of assumptions.
##
## The preview drives its own clip state machine in _process, so the harness freezes
## it (attack_locked) before playing clips by hand — otherwise every shot collapses
## back to idle.

const OUT_DIR: String = "res://.cv_qa/combatgirls"

var scene: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	scene = (load("res://scenes/tests/katana_girl_preview.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(1.0).timeout
	var girl: Node3D = scene.girl
	print("CLIPS ", girl.clip_names)
	# Freeze the preview's own state machine.
	scene._attack_locked = true
	scene._yaw = 0.55
	scene._pitch = -0.12
	scene._distance = 3.2
	await create_timer(0.4).timeout

	girl.play("idle")
	await create_timer(0.4).timeout
	await _capture("01_idle")

	# Side view so a stride is actually readable.
	scene._yaw = 1.55
	girl.play("walk")
	await create_timer(0.45).timeout
	await _capture("02_walk_side")
	girl.play("run")
	await create_timer(0.25).timeout
	await _capture("03_run_side")

	scene._yaw = 0.55
	girl.set_outfit("sportswear")
	await create_timer(0.3).timeout
	await _capture("04_sportswear")
	girl.set_outfit("uniform")
	girl.set_face(3)
	await create_timer(0.2).timeout
	await _capture("05_face3")
	girl.set_face(1)

	for entry: Array in [["attack1", 0.62], ["attack2", 0.55], ["attack3", 0.85], ["skill1", 1.7]]:
		girl.play_once(str(entry[0]))
		await create_timer(float(entry[1])).timeout
		await _capture("06_%s" % entry[0])

	# Head close-up: the face atlas is the one thing that cannot be judged at distance.
	scene._yaw = 0.30
	scene._pitch = 0.02
	scene._distance = 0.85
	scene._focus_height = 1.52
	girl.play("idle")
	await create_timer(0.6).timeout
	await _capture("07_face_closeup")
	# Back of the head: the eye layer must not show through the skull.
	scene._yaw = 3.44
	await create_timer(0.4).timeout
	await _capture("08_face_back")
	print("CAPTURE_DONE")
	quit(0)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name + ".png")
	image.save_png(path)
	print("SAVED: ", path)
