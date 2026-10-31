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
    player.set_physics_process(false)
    arena.guardian.set_physics_process(false)
    player.set_controls_active(true)
    var hud = arena.hud
    await capture("closed")
    key(player, KEY_TAB)
    check(player.menu_open, "Tab opens backpack")
    check(hud._backpack_rect().position == Vector2(28,26), "Panel anchored upper-left")
    for row: int in range(4):
        for col: int in range(5):
            var rect: Rect2 = hud._backpack_cell(row,col)
            check(hud._cell_at(rect.get_center()) == Vector2i(row,col), "Cell hit matches rendering")
            if row == 0:
                check(rect == Rect2(44 + col * 56,54,48,44), "Expanded hotbar stays fixed")
    hud._hover_cell = Vector2i(1,0)
    await capture("open")
    var stored: String = player.slot_item(1,0)
    var previous: String = player.slot_item(0,1)
    click(hud, hud._backpack_cell(1,0).get_center())
    check(hud._held_item == stored and not stored.is_empty(), "Mouse picks storage item")
    click(hud, hud._backpack_cell(0,1).get_center())
    check(player.slot_item(0,1) == stored and player.slot_item(1,0) == previous, "Mouse swaps into hotbar")
    click(hud, hud._backpack_cell(0,1).get_center())
    click(hud, Vector2(600,400))
    check(hud._held_item.is_empty() and player.slot_item(0,1) == stored, "Outside click returns item")
    key(player, KEY_ESCAPE)
    check(not player.menu_open and player.controls_active, "Esc closes and resumes")
    key(player, KEY_ESCAPE)
    check(player.menu_open, "Esc opens backpack")
    key(player, KEY_TAB)
    check(not player.menu_open, "Tab closes backpack")
    print("BACKPACK_CORNER_RESULT failures=", failures)
    quit(0 if failures == 0 else 1)
func key(player: Node, code: int) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.physical_keycode = code
    event.pressed = true
    player._unhandled_input(event)
func click(hud: Control, point: Vector2) -> void:
    var factor: float = minf(hud.size.x / 1280.0, hud.size.y / 720.0)
    var offset: Vector2 = (hud.size - Vector2(1280,720) * factor) * 0.5
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = hud.global_position + offset + point * factor
    hud._input(event)
func capture(label: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://.mvp_qa/backpack_corner/" + label + ".png")
