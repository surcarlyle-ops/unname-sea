extends SceneTree
var failures: int = 0
func _initialize() -> void:
    run.call_deferred()
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func run() -> void:
    var arena = load("res://scenes/combat_mvp.tscn").instantiate()
    root.add_child(arena)
    current_scene = arena
    await process_frame
    var player = arena.player
    player.set_controls_active(true)
    player.set_physics_process(false)
    player.grapple.set_physics_process(false)
    arena.guardian.set_physics_process(false)
    arena.hud.visible = false
    player.position = Vector3(0, 0.08, 12)
    player.rotation = Vector3.ZERO
    player.camera.rotation = Vector3.ZERO
    var hands = player.hands
    for slot: int in [2, 3]:
        player.selected_slot = slot
        player._refresh_weapon()
        for i: int in range(65):
            hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
            await process_frame
        var id: String = player.quick_slots[slot]
        check(id in ["steam_pistol", "m1911"], "Correct default firearm slot")
        for bone_name: String in hands._pistol_grip_pose.right:
            var q: Array = hands._pistol_grip_pose.right[bone_name]
            var actual: Quaternion = hands.right_glove.skeleton.get_bone_pose_rotation(hands.right_glove.skeleton.find_bone(bone_name))
            check(actual.angle_to(Quaternion(q[0],q[1],q[2],q[3])) < 0.01, id + " authored finger " + bone_name)
        var pivot: Node3D = hands._pistol_pivot if id == "steam_pistol" else hands._m1911_pivot
        var muzzle: Vector3 = -(hands.right_arm.basis * pivot.basis.x)
        check(muzzle.dot(Vector3.FORWARD) > 0.98, id + " muzzle points forward")
        check(player.request_attack(), id + " accepts attack")
        player._update_attack(float(player._weapon.windup) + 0.001)
        check(hands._pistol_recoil_left > 0, id + " starts gun recoil")
        hands.update_pose(1.0 / 60, 0, false, 0.1, 0, true, 2)
        await capture(id + "_fire")
        player._update_attack(2.0)
        for i: int in range(25):
            hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
            await process_frame
        await capture(id + "_idle")
    for id: String in hands._imported:
        hands.set_weapon(id)
        hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
        check(hands._imported[id].visible, "Imported weapon remains available " + id)
    hands.set_weapon("tide_blade")
    hands._cancel_spawn_animation()
    hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
    check(hands.right_glove._pose_override.is_empty(), "Sword clears pistol fingers")
    check(is_equal_approx(hands._tide_blade.rotation_degrees.y,65), "Sword side angle preserved")
    hands.set_weapon("")
    hands.update_pose(1.0 / 60, 0, false, -1, 0, false, 2)
    check(hands.right_glove._pose_override.is_empty(), "Empty hand clears pistol fingers")
    print("PISTOL_INTEGRATION_RESULT failures=", failures)
    quit(0 if failures == 0 else 1)
func capture(label: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://.mvp_qa/pistol_integration/" + label + ".png")
