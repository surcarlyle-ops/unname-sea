extends SceneTree
var failures: int = 0
var hands: Node3D
func _initialize() -> void:
    run.call_deferred()
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func step(delta: float = 1.0/60, attack: float = -1.0, locomotion: Dictionary = {}) -> void:
    hands.update_pose(delta,0,false,attack,0,true,2,locomotion)
func handle_point() -> Vector3:
    return hands._tide_blade.to_global(Vector3(0, hands.TIDE_GRIP_Y, 0))
func grip_point() -> Vector3:
    return hands.right_arm.to_global(hands.GRIP_CENTER)
func run() -> void:
    var arena = load("res://scenes/combat_mvp.tscn").instantiate()
    root.add_child(arena)
    current_scene = arena
    await process_frame
    var player = arena.player
    player.set_physics_process(false)
    player.set_controls_active(true)
    player.grapple.set_physics_process(false)
    arena.guardian.set_physics_process(false)
    arena.hud.visible = false
    player.position = Vector3(0,0.08,12)
    hands = player.hands
    hands.set_weapon("tide_blade")
    hands._cancel_spawn_animation()
    for i: int in range(45):
        step()
        await process_frame
    check(handle_point().distance_to(grip_point()) < 0.001, "Lengthened blade rest handle remains in palm")
    hands._play_spawn_animation()
    var flight_gap: float = 0
    var finger_opened: bool = false
    var caught: bool = false
    for frame: int in range(ceili(hands.TIDE_SPAWN_DURATION * 60.0) + 2):
        step()
        await process_frame
        var progress: float = 1.0 - hands._spawn_time / hands.TIDE_SPAWN_DURATION
        if progress > 0.30 and progress < 0.65:
            flight_gap = maxf(flight_gap,handle_point().distance_to(grip_point()))
            finger_opened = finger_opened or hands.right_glove.grip < 0.20
        if progress >= 0.80:
            caught = true
            check(handle_point().distance_to(grip_point()) < 0.001,"Handle aligns at catch and during recovery")
        if frame in [3,9,17,27,38,47,51,54,58,66]:
            await capture("frame_%02d" % frame)
    check(flight_gap > 0.10 and finger_opened,"Sword visibly releases while palm opens")
    check(caught and hands.right_glove.grip > 0.86,"Catch closes the fingers")
    var rest_pivot: Transform3D = Transform3D(Basis.IDENTITY,Vector3(0,hands._spawn_base_y,0))
    check(hands._tide_pivot.transform.is_equal_approx(rest_pivot),"Completed animation restores full pivot transform")
    # Check endpoint continuity with the same neutral arm pose on either side.
    for boundary: float in [0.16,0.80]:
        hands._cancel_spawn_animation()
        step()
        hands._apply_spawn_pose(boundary-0.00001)
        var before: Transform3D = hands._tide_pivot.global_transform
        var handle_before: Vector3 = handle_point()
        hands._cancel_spawn_animation()
        step()
        hands._apply_spawn_pose(boundary+0.00001)
        check(before.origin.distance_to(hands._tide_pivot.global_position) < 0.002,"Pivot position continuous at release/catch")
        check(handle_before.distance_to(handle_point()) < 0.002,"Handle path continuous at release/catch")
    hands._play_spawn_animation()
    step(0.4)
    hands.set_weapon("m1911")
    step()
    check(hands._spawn_time == 0 and hands._tide_pivot.transform.is_equal_approx(rest_pivot),"Switching firearms cancels airborne offsets")
    hands.set_weapon("tide_blade")
    step(0.4)
    step(1.0/60,0.25)
    check(hands._spawn_time == 0,"Attack interrupts draw immediately")
    hands._play_spawn_animation()
    step(0.4)
    step(1.0/60,-1,{"grappling":true,"grapple_anchor":Vector3(3,5,-10)})
    check(hands._spawn_time == 0,"Grapple interrupts draw immediately")
    hands.reset_motion()
    check(hands._tide_pivot.transform.is_equal_approx(rest_pivot),"Retry clears detached pivot")
    print("SWORD_DRAW_RESULT failures=",failures," max_flight_gap=",flight_gap)
    quit(0 if failures == 0 else 1)
func capture(label: String) -> void:
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://.mvp_qa/sword_draw/"+label+".png")
