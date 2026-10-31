extends SceneTree
## Exercise selection, recoverable load failure, and a real enter/return-key flow.

const DATA: Script = preload("res://scripts/ui/scene_menu_data.gd")

var failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	change_scene_to_file("res://scenes/ui/map_select.tscn")
	await frames(8)
	var menu: Control = current_scene as Control
	check(menu != null and menu.has_method("select_map"), "Canonical menu uses the new UI")
	if menu == null or not menu.has_method("select_map"):
		quit(1)
		return
	check(menu._buttons.size() == 3, "Three real destinations available")
	check(menu._enter.get_global_rect().end.y <= menu.size.y - 10.0, "Enter button fits the desktop viewport")
	for id: String in ["combat_mvp", "shore_test", "cherry_valley"]:
		menu.select_map(id)
		await frames(4)
		check(menu.selected_id == id and menu._photo.texture != null, "Destination selection and real preview " + id)
		check(menu._enter.text.begins_with("进入"), "Clear enter action " + id)
		await shot(id)
	click(menu._buttons[1])
	await frames(2)
	check(menu.selected_id == "shore_test", "Real mouse click selects a card through its labels")
	key(KEY_3)
	await frames(2)
	check(menu.selected_id == "cherry_valley", "Keyboard shortcut selects a destination")
	var original_canvas: Vector2i = root.content_scale_size
	var original_window: Vector2i = root.size
	root.content_scale_size = Vector2i(800, 720)
	root.size = Vector2i(800, 720)
	await frames(8)
	check(menu._enter.get_global_rect().end.y <= menu.size.y - 10.0, "Enter button remains reachable at 800px width")
	await shot("compact_800")
	root.content_scale_size = original_canvas
	root.size = original_window
	await frames(8)
	menu.switcher.enter_scene("res://scenes/ui/__missing_ui_map__.tscn", "missing")
	await frames(3)
	check(not menu._busy and not menu._enter.disabled and menu._status.text.contains("暂时无法进入"), "Loading failure leaves a usable menu")
	await shot("load_error")
	menu.select_map("combat_mvp")
	click(menu._enter)
	check(menu._busy and menu._enter.disabled, "Entering locks the UI against duplicate requests")
	for i: int in range(240):
		if current_scene != null and current_scene.scene_file_path == "res://scenes/combat_mvp.tscn":
			break
		await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/combat_mvp.tscn", "Enter button opens the actual training scene")
	await frames(3)
	await shot("in_game_return")
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = DATA.return_keycode()
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = DATA.return_keycode()
	Input.parse_input_event(release)
	for i: int in range(240):
		if current_scene != null and current_scene.scene_file_path == "res://scenes/ui/map_select.tscn":
			break
		await process_frame
	await frames(5)
	menu = current_scene as Control
	check(menu != null and menu.has_method("select_map"), "Return key returns to the new UI")
	check(menu.selected_id == "combat_mvp" and not menu._enter.disabled, "Selection survives return and controls recover")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Return releases the mouse")
	await shot("returned")
	print("TRIAL_HUB_RESULT failures=", failures)
	quit(0 if failures == 0 else 1)


func click(button: Button) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func frames(count: int) -> void:
	for i: int in range(count):
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/trial_menu/" + name + ".png")
