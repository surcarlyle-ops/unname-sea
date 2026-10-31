extends SceneTree
var failures: int = 0
var hands: Node3D
func _initialize() -> void:
    run.call_deferred()
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func pose(progress: float, index: int) -> void:
    hands.update_pose(1.0/60,0,false,progress,index,true,2)
func run() -> void:
    var arena = load("res://scenes/combat_mvp.tscn").instantiate()
    root.add_child(arena)
    current_scene = arena
    await process_frame
    var player = arena.player
    player.set_physics_process(false)
    player.set_controls_active(true)
    arena.guardian.set_physics_process(false)
    arena.hud.visible = false
    player.position = Vector3(0,0.08,12)
    hands = player.hands
    for id: String in ["dark_knight_sword","sword_08"]:
        player.quick_slots[1] = id
        player.selected_slot = 1
        player._refresh_weapon()
        for i: int in range(90):
            pose(-1,0)
            await process_frame
        var neutral: Transform3D = hands.right_arm.transform
        var blade_x: float = (-neutral.basis.x).x
        var raised_y: float = 0
        var cut_y: float = 0
        for p: float in [0.0,0.20,0.38,0.58,0.80,1.0]:
            pose(p,0)
            var first: Transform3D = hands.right_arm.transform
            check(absf((-first.basis.x).x-blade_x) < 0.002,"Cut stays in vertical plane "+id)
            pose(p,1)
            check(first.is_equal_approx(hands.right_arm.transform),"Odd/even attacks repeat same chop "+id)
            if p == 0.20: raised_y = hands.right_arm.position.y
            if p == 0.58: cut_y = hands.right_arm.position.y
            await process_frame
            await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png("res://.mvp_qa/vertical_swords/%s_%03d.png" % [id,roundi(p*100)])
        check(raised_y > cut_y + 0.15,"Hand raises then cuts down "+id)
        check(hands.right_arm.transform.is_equal_approx(neutral),"Returns exactly to idle "+id)
        check(hands._imported[id].visible,"Correct imported model remains equipped "+id)
        pose(-1,0)
        check(not hands._slash_wrist_bent,"Forearm reset on release "+id)
    hands.set_weapon("tide_blade")
    hands._cancel_spawn_animation()
    pose(0.40,0)
    var first: Transform3D = hands.right_arm.transform
    pose(0.40,1)
    check(not first.is_equal_approx(hands.right_arm.transform),"Original tide blade keeps alternating attacks")
    print("VERTICAL_SWORDS_RESULT failures=",failures)
    quit(0 if failures == 0 else 1)
