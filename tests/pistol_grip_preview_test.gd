extends SceneTree

var preview: Node3D
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/pistol_grip")
	preview = load("res://scenes/tests/pistol_grip_preview.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	await process_frame
	var skeleton: Skeleton3D = preview.glove_skeleton
	for name: String in preview.pose.right:
		var q: Array = preview.pose.right[name]
		_check(skeleton.get_bone_pose_rotation(skeleton.find_bone(name)).angle_to(Quaternion(q[0],q[1],q[2],q[3])) < 0.001,"Authored pistol finger: "+name)
	await _capture("m1911_first_person")
	preview.angle = 1
	preview.update_camera()
	await _capture("m1911_palm")
	preview.angle = 2
	preview.update_camera()
	await _capture("m1911_back")
	preview.angle = 0
	preview.set_weapon("steam_pistol")
	await _capture("steam_first_person")
	preview.angle = 1
	preview.update_camera()
	await _capture("steam_palm")
	preview.set_weapon("reference")
	_check(preview.reference.visible and not preview.arm.visible,"Author reference is distinct from own glove")
	await _capture("source_pistol")
	preview.set_weapon("m1911")
	_check(preview.arm.visible and not preview.reference.visible,"Own glove restores after reference")
	preview._kick = 0.18
	preview._process(0.04)
	_check(preview.arm.position.z > preview._rest_position.z,"Gun and grasp share the recoil")
	preview._process(0.3)
	_check(preview.arm.position.is_equal_approx(preview._rest_position),"Recoil returns without losing grip")
	print("PISTOL_GRIP_PREVIEW_RESULT failures=%d fingers=15" % failures)
	preview.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/pistol_grip/"+name+".png")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
