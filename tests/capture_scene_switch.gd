extends SceneTree
## 场景切换实机截图（CodeBuddyPro，2026-10-28）。
##
## 跑法（需要窗口，不要加 --headless）：
##   "D:\claude project\Godot_v4.7.2-stable_win64.exe" --path "D:\claude project\projects\unname_sea" ^
##     --script res://tests/capture_scene_switch.gd
##
## 输出到 .mvp_qa/scene_switch/：菜单、训练场、F10 返回后的菜单、岸边测试区、
## 樱花山谷、最终菜单。训练场→菜单这一步用真实 F10 按键事件，验证键位而不是只调方法。

const DATA: Script = preload("res://scripts/ui/scene_menu_data.gd")
const MENU_SCENE: String = "res://scenes/ui/map_select.tscn"
const COMBAT_SCENE: String = "res://scenes/combat_mvp.tscn"
const SHORE_SCENE: String = "res://scenes/tests/shore_test_area_preview.tscn"
const VALLEY_SCENE: String = "res://scenes/cherry_valley.tscn"
const OUTPUT_DIR: String = "res://.mvp_qa/scene_switch"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	change_scene_to_packed(load(MENU_SCENE) as PackedScene)
	await _wait_scene(MENU_SCENE)
	await _frames(4)
	await _shot("01_menu.png")

	# 训练场：用组件进入，再用真实 F10 按键返回。
	_enter("combat_mvp")
	await _wait_scene(COMBAT_SCENE, 600)
	await _frames(24)
	print("combat scene=%s hook=%s hint=%s" % [
		current_scene.scene_file_path,
		str(root.get_node_or_null("SceneReturnHook") != null),
		str(_hint_visible())])
	await _shot("02_combat_mvp.png")
	_send_key(DATA.return_keycode())
	var back: bool = await _wait_scene(MENU_SCENE, 300)
	await _frames(4)
	print("return_key=%s ok=%s mouse=%s" % [
		DATA.return_key_name(), str(back), str(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)])
	await _shot("03_menu_after_f10.png")

	# 岸边测试区：组件进入、钩子返回。
	_enter("shore_test")
	await _wait_scene(SHORE_SCENE, 600)
	await _frames(24)
	await _shot("04_shore_test.png")
	_return_via_hook()
	await _wait_scene(MENU_SCENE, 300)
	await _frames(4)

	# 樱花山谷：等生成完再截图、再返回。
	_enter("cherry_valley")
	await _wait_scene(VALLEY_SCENE, 600)
	await _wait_build(3000)
	await _frames(6)
	print("valley build_complete=%s" % str(current_scene.get("build_complete")))
	await _shot("05_cherry_valley.png")
	_return_via_hook()
	await _wait_scene(MENU_SCENE, 600)
	await _frames(4)
	await _shot("06_menu_final.png")

	print("SCENE_SWITCH_CAPTURE done → %s" % OUTPUT_DIR)
	quit(0)


func _enter(map_id: String) -> void:
	var switcher: Node = current_scene.get("switcher")
	if switcher != null:
		switcher.call("enter_map", map_id)


func _return_via_hook() -> void:
	var hook: Node = root.get_node_or_null("SceneReturnHook")
	if hook != null:
		hook.call("return_to_menu")


func _hint_visible() -> bool:
	var hook: Node = root.get_node_or_null("SceneReturnHook")
	if hook == null:
		return false
	var layer: CanvasLayer = hook.get_node_or_null("ReturnHint") as CanvasLayer
	return layer != null and layer.visible


func _send_key(keycode: Key) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)


func _wait_scene(scene_path: String, max_frames: int = 300) -> bool:
	for _index: int in range(max_frames):
		await process_frame
		if current_scene != null and current_scene.scene_file_path == scene_path:
			return true
	return false


func _wait_build(max_frames: int) -> void:
	for _index: int in range(max_frames):
		if current_scene == null:
			return
		if bool(current_scene.get("build_complete")):
			return
		await process_frame


func _frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	print("saved %s" % file_name)
