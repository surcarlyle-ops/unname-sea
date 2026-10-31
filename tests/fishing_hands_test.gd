extends SceneTree
## Verify attachment and cancellation on the real glove, then capture rendered key poses.

var failures: int = 0
var checks: int = 0
var preview: Node3D


class ControllerStub extends Node:
	var state: int = 0
	func cast_progress() -> float:
		return 0.3
	func reveal_progress() -> float:
		return 0.62


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	preview = load("res://scenes/tests/fishing_hands_preview.tscn").instantiate() as Node3D
	root.add_child(preview)
	current_scene = preview
	await process_frame
	preview.set_process(false)
	var hands: Node3D = preview.hands
	check(hands._weapon_id == "fishing_rod", "Preview equips the fishing viewmodel")
	check(not hands.is_melee("fishing_rod") and not hands.is_ranged("fishing_rod"), "Rod is not a combat weapon")
	var cast_pitch: Array[float] = []
	for state: String in ["idle", "casting", "waiting", "biting", "reeling"]:
		var samples: Array = [0.0, 0.30, 0.62, 1.0] if state in ["casting", "reeling"] else [0.0]
		for at: float in samples:
			preview.sample_pose(state, at)
			await process_frame
			var palm: Vector3 = hands.right_arm.to_global(hands.GRIP_CENTER)
			check(palm.distance_to(hands._fishing_rod.global_position) < 0.00001, state + " handle stays in palm")
			var skeleton: Skeleton3D = hands.right_glove.skeleton
			var hand: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hand"))
			check((hand * hands.GRIP_CENTER).distance_to(hands._fishing_rod.global_position) < 0.002, state + " actual skinned hand stays on handle after sleeve correction")
			var shaft_axis: Vector3 = hands._fishing_rod.global_basis.y.normalized()
			check(shaft_axis.dot(-hands.right_arm.global_basis.x.normalized()) > 0.9999, state + " rod exits the thumb side")
			check(hands._fishing_rod.visible, state + " rod remains visible")
			check(not hands._tide_blade.visible and not hands._pistol.visible, state + " no stale weapon model")
			if state == "casting":
				cast_pitch.append(hands.right_arm.quaternion.get_euler().x)
			if state == "idle" or state == "waiting" or (state == "casting" and at in [0.30, 0.62]) or (state == "reeling" and at == 0.30):
				await capture(state + "_" + str(roundi(at * 100.0)))
	check(cast_pitch.size() == 4 and absf(cast_pitch[1] - cast_pitch[2]) > 0.8, "Cast has a distinct draw-back and forward flick")
	for state: String in ["casting", "reeling"]:
		var start: Dictionary = hands._fishing_rod.sample_motion(state, 0.0)
		var finish: Dictionary = hands._fishing_rod.sample_motion(state, 1.0)
		check(start.offset == finish.offset and is_equal_approx(float(start.pitch), float(finish.pitch)), state + " returns to its resting pose")
	var sword_pose: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/sword_grip_pose.json")) as Dictionary
	for bone_name: String in sword_pose.right:
		var raw: Array = sword_pose.right[bone_name]
		var target: Quaternion = Quaternion(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
		var actual: Quaternion = hands.right_glove.skeleton.get_bone_pose_rotation(hands.right_glove.skeleton.find_bone(bone_name))
		check(actual.angle_to(target) < 0.01, "Approved finger contact preserved: " + bone_name)
	preview.sample_pose("waiting", 0.0)
	for side: int in [1, 2]:
		preview.angle = side
		preview.update_camera()
		await capture("grip_" + str(side))
	preview.angle = 0
	preview.update_camera()
	hands.set_fishing_presentation("casting", 0.4)
	hands.reset_motion()
	check(hands._fishing_rod.phase == "idle" and is_zero_approx(hands._fishing_rod._flex), "Reset clears presentation progress and flex")
	hands.set_weapon("m1911")
	for i: int in range(90):
		hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, true, 2.0)
	check(not hands._fishing_rod.visible and hands._m1911_pivot.visible, "Switching to pistol hides rod")
	check(not hands.right_glove.authored_grip and not hands.right_glove._pose_override.is_empty(), "Pistol restores its dedicated finger pose")
	hands.set_weapon("")
	hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, false, 2.0)
	check(not hands._fishing_rod.visible and hands.right_glove._pose_override.is_empty(), "Empty hands clear tool and pistol pose")
	hands.set_weapon("tide_blade")
	hands._cancel_spawn_animation()
	hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, true, 2.0)
	check(hands._tide_blade.visible and not hands._fishing_rod.visible, "Sword remains available")
	check(is_equal_approx(hands._tide_blade.rotation_degrees.y, 65.0), "Sword angle preserved")
	var controller: Node = ControllerStub.new()
	root.add_child(controller)
	hands.bind_fishing_controller(controller)
	hands.set_weapon("fishing_rod")
	for state: int in range(5):
		controller.state = state
		hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, false, 2.0)
		check(hands._fishing_rod.phase == ["idle", "casting", "waiting", "biting", "reeling"][state], "Controller phase mapping " + str(state))
		if state == 1 or state == 4:
			check(is_equal_approx(hands._fishing_rod.progress, 0.3 if state == 1 else 0.62), "Controller action progress")
	check(hands.fishing_tip_anchor().global_position.distance_to(hands.fishing_tip_world()) < 0.00001, "Line anchor matches the real rod tip")
	controller.free()
	hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, true, 2.0)
	check(hands._fishing_controller == null and hands._fishing_rod.phase == "idle", "Freed controller clears the binding safely")
	print("FISHING_HANDS_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_hands/" + label + ".png")
