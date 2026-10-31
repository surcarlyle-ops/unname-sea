extends SceneTree
var arena: Node3D
var player: CharacterBody3D
var hands: Node3D
var failures: int = 0
func _initialize() -> void:
    run.call_deferred()
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func pose(velocity: Vector3) -> void:
    hands.update_pose(1.0/60, velocity.length(), false, -1, 0, true, 2, {"grounded":false,"grappling":true,"grapple_anchor":player.grapple.anchor,"local_velocity":velocity})
func run() -> void:
    arena = load("res://scenes/combat_mvp.tscn").instantiate()
    root.add_child(arena)
    current_scene = arena
    await process_frame
    player = arena.player
    player.set_physics_process(false)
    player.set_controls_active(true)
    player.grapple.set_physics_process(false)
    arena.guardian.set_physics_process(false)
    arena.hud.visible = false
    hands = player.hands
    hands.set_weapon("tide_blade")
    hands._cancel_spawn_animation()
    player.position = Vector3(0,0.1,16)
    player.grapple.anchor = player.camera.global_position + Vector3(2,4,-18)
    player.grapple.anchor_normal = Vector3.BACK
    player.grapple.state = player.grapple.State.ATTACHED
    player.grapple._update_rope_visual(true)
    for i: int in range(90):
        pose(Vector3.ZERO)
        await process_frame
    check(hands._grapple_reel < 0.001, "Stationary hanging does not reel on a timer")
    check(skeleton_wrist_angle() < deg_to_rad(1), "Extended pose keeps the previous hand direction")
    var far_hand: Vector3 = hands.left_arm.position
    var skeleton: Skeleton3D = hands.left_glove.skeleton
    var forearm: int = skeleton.find_bone("Forearm")
    var hand: int = skeleton.find_bone("Hand")
    var far_bend: float = skeleton.get_bone_pose_rotation(forearm).get_angle()
    await capture("reach")
    var start: Vector3 = player.position
    var travel: Vector3 = (player.grapple.anchor - player.camera.global_position) * 0.85
    for i: int in range(90):
        player.position = start + travel * float(i+1)/90.0
        pose(Vector3(0,0,-8))
        await process_frame
    for i: int in range(35):
        pose(Vector3.ZERO)
        await process_frame
    check(hands._grapple_reel > 0.95, "Approaching the anchor reels in the hand")
    check(absf(skeleton.get_bone_pose_rotation(hand).get_angle() - deg_to_rad(45)) < deg_to_rad(3), "Near wrist reaches approximately 45 degrees relative to forearm")
    check(hands.to_local(hands.grapple_grip_point()).z <= -float(hands._presentation.grapple.closest_grip_depth) + 0.001, "Near grasp stops before crowding the camera")
    check(skeleton.get_bone_pose_rotation(forearm).get_angle() > far_bend + deg_to_rad(8), "Near pose bends arm slightly")
    await capture("near")
    for i: int in range(45):
        pose(Vector3(12,0,0))
        await process_frame
    var right_swing: Quaternion = hands.left_arm.quaternion
    check(hands._grapple_swing > 0.8, "Tangential speed activates swing brace")
    await capture("swing_right")
    for i: int in range(45):
        pose(Vector3(-12,0,0))
        await process_frame
    check(right_swing.angle_to(hands.left_arm.quaternion) > 0.02, "Swing direction changes shared arm rotation")
    await capture("swing_left")
    check(skeleton.get_bone_global_pose(hand).origin.length() < 0.001, "Sleeve solve preserves wrist position")
    for name: String in hands.left_glove._rope_pose:
        var q: Array = hands.left_glove._rope_pose[name]
        check(skeleton.get_bone_pose_rotation(skeleton.find_bone(name)).angle_to(Quaternion(q[0],q[1],q[2],q[3])) < 0.01, "Closed rope grip preserved " + name)
    player.grapple.reset()
    for i: int in range(55):
        hands.update_pose(1.0/60,0,false,-1,0,true,2)
        await process_frame
    check(not hands._rope_wrist_bent and hands.left_glove._override_weight < 0.001,"Release restores normal left arm")
    print("DYNAMIC_ROPE_RESULT failures=", failures)
    quit(0 if failures == 0 else 1)
func capture(label: String) -> void:
    player.grapple.rope_visual._process(0)
    check(hands.to_local(hands.grapple_grip_point()).z <= -float(hands._presentation.grapple.closest_grip_depth) + 0.001, "Grasp depth limit survives wrist rotation and swing " + label)
    var visual: Node3D = player.grapple.rope_visual
    check(visual.rope_points[5].distance_to(hands.grapple_grip_point()) < 0.001,"Rope contact tracks hand " + label)
    check(absf((visual.rope_points[6]-visual.rope_points[4]).normalized().dot(hands.grapple_rope_tangent())) > 0.999,"Palm rope axis tracks rotation " + label)
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://.mvp_qa/rope_dynamic/"+label+".png")

func skeleton_wrist_angle() -> float:
    var skeleton: Skeleton3D = hands.left_glove.skeleton
    return skeleton.get_bone_global_pose(skeleton.find_bone("Hand")).basis.get_rotation_quaternion().get_angle()
