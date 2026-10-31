extends SceneTree
## 场景切换组件结构检查（CodeBuddyPro，2026-10-28）。
##
## 跑法：
##   "D:\claude project\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\claude project\projects\unname_sea" ^
##     --log-file .mvp_qa/scene_switch/check.log --script res://tests/scene_switch_check.gd
##
## 覆盖：地图清单字段与真实路径、最小菜单可点、重复点击只受理一次、三个地图进入/返回、
## 旧场景清理（玩家/相机/背景音）、失败后仍停在可操作的菜单。

const DATA = preload("res://scripts/ui/scene_menu_data.gd")
const MENU_SCENE: String = "res://scenes/ui/map_select.tscn"

var _passes: int = 0
var _fails: int = 0
var _failed_id: String = ""
var _failed_reason: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_config()
	await _check_menu()
	await _check_guard_and_enter()
	await _check_return()
	await _check_failure()
	await _check_each_map()
	print("SCENE_SWITCH_RESULT pass=%d fail=%d" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)


# === 清单 ===

func _check_config() -> void:
	var maps: Array[Dictionary] = DATA.maps()
	_check(maps.size() == 3, "地图清单 %d 项" % maps.size())
	var complete: bool = true
	var ids: Array[String] = []
	for entry: Dictionary in maps:
		for key: String in ["id", "name", "description", "scene", "status", "kind", "kind_label"]:
			if not entry.has(key) or str(entry.get(key, "")).is_empty():
				complete = false
		if not ResourceLoader.exists(str(entry.get("scene", ""))):
			complete = false
		ids.append(str(entry.get("id", "")))
	_check(complete, "每项都含 id/名称/说明/状态/分类/真实场景路径，且场景文件存在")
	_check(ids == ["combat_mvp", "shore_test", "cherry_valley"], "清单顺序：%s" % str(ids))
	_check(str(DATA.find_map("combat_mvp").get("kind", "")) == "main", "训练场标为「主战斗 Demo」")
	_check(str(DATA.find_map("shore_test").get("scene", "")) == "res://scenes/tests/shore_test_area_preview.tscn",
		"岸边指向带玩家的预览场景（不是只有场地本体的 shore_test_area.tscn）")
	_check(str(DATA.find_map("cherry_valley").get("kind", "")) == "preview", "樱花山谷标为「独立预览」")
	_check(ResourceLoader.exists(DATA.menu_scene_path()), "地图选择场景存在：%s" % DATA.menu_scene_path())
	_check(DATA.return_key_name() == "B" and DATA.return_keycode() == KEY_B,
		"返回键 %s 与键码一致（不使用 F 功能键）" % DATA.return_key_name())
	_check(not DATA.session_notice().is_empty(), "带「每次进入都会重开、不携带进度」的提示文案")


# === 菜单 ===

func _check_menu() -> void:
	var packed: PackedScene = load(MENU_SCENE) as PackedScene
	_check(packed != null and change_scene_to_packed(packed) == OK, "能加载地图选择场景")
	await _wait_scene(MENU_SCENE)
	_check(current_scene != null and current_scene.scene_file_path == MENU_SCENE, "当前场景是地图选择")
	var buttons: Array[Node] = _buttons()
	_check(buttons.size() == 3, "菜单里 %d 个地图按钮" % buttons.size())
	_check(not _any_disabled(buttons), "初始三个按钮都可点")
	_check(root.get_node_or_null(DATA.RETURN_HOOK_NAME) == null, "菜单里没有残留的返回钩子")


# === 重复点击 + 进入 ===

func _check_guard_and_enter() -> void:
	var switcher: Node = current_scene.get("switcher")
	_check(switcher != null, "菜单里能拿到 SceneSwitcher")
	var first: bool = bool(switcher.call("enter_map", "combat_mvp"))
	var second: bool = bool(switcher.call("enter_map", "shore_test"))
	_check(first and not second and bool(switcher.call("is_switching")),
		"切换中重复点击被拒绝（第一次 true、第二次 false）")
	_check(str(switcher.call("switching_map_id")) == "combat_mvp", "切换中状态记录了目标地图")
	var arrived: bool = await _wait_scene("res://scenes/combat_mvp.tscn")
	_check(arrived, "进入训练场")
	_check(root.get_node_or_null(DATA.RETURN_HOOK_NAME) != null, "地图内挂了返回钩子")
	_check(_count_player_nodes() == 1, "只有 %d 个玩家节点（旧场景已释放）" % _count_player_nodes())
	_check(_count_cameras() == 1, "只有 %d 个相机" % _count_cameras())
	_check(root.get_node_or_null("ShoreTestPreview") == null, "没有残留的岸边场景")
	_check(_playing_audio() == 0, "没有多余背景音在播")


# === 返回 ===

func _check_return() -> void:
	var hook: Node = root.get_node_or_null(DATA.RETURN_HOOK_NAME)
	_check(hook != null, "能拿到返回钩子")
	_check(str(hook.call("return_key_name")) == DATA.return_key_name(), "钩子报出的返回键与清单一致")
	var hint_button: Button = hook.get("_button") as Button
	var hint_label: Label = hook.get("_label") as Label
	_check(hint_button != null and hint_button.pressed.get_connections().size() > 0,
		"地图内返回按钮存在且已接点击（不依赖键盘）")
	_check(hint_label != null and hint_label.text.contains(DATA.return_key_name()),
		"返回按钮文案带键位：%s" % (hint_label.text if hint_label != null else "无"))
	var accepted: bool = bool(hook.call("return_to_menu"))
	_check(accepted, "返回请求被受理")
	var arrived: bool = await _wait_scene(MENU_SCENE)
	_check(arrived, "回到地图选择")
	await process_frame
	await process_frame
	_check(root.get_node_or_null(DATA.RETURN_HOOK_NAME) == null, "返回后清掉返回钩子")
	_check(not _any_disabled(_buttons()), "回到菜单后按钮恢复可点")
	_check(_playing_audio() == 0, "返回后没有残留背景音")
	_check(_count_player_nodes() == 0, "返回后没有残留玩家节点")
	_check(_count_cameras() == 0, "返回后没有残留相机")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "返回后鼠标已释放")


# === 失败反馈 ===

func _check_failure() -> void:
	var switcher: Node = current_scene.get("switcher")
	switcher.switch_failed.connect(_on_switch_failed)
	var accepted: bool = bool(switcher.call("enter_scene", "res://scenes/ui/__missing_map__.tscn", "缺失场景"))
	await process_frame
	await process_frame
	_check(accepted and not _failed_reason.is_empty(), "坏路径给出失败原因：%s" % _failed_reason)
	_check(not bool(switcher.call("is_switching")), "失败后退出切换中状态")
	_check(current_scene != null and current_scene.scene_file_path == MENU_SCENE, "失败后仍停在地图选择")
	_check(not _any_disabled(_buttons()), "失败后按钮仍可点")
	_failed_id = ""
	_failed_reason = ""
	var unknown: bool = bool(switcher.call("enter_map", "no_such_map"))
	_check(not unknown and _failed_id == "no_such_map", "未知地图 id 立即拒绝并回报：%s" % _failed_reason)


func _on_switch_failed(map_id: String, reason: String) -> void:
	_failed_id = map_id
	_failed_reason = reason


# === 三个入口逐一进入/返回 ===

func _check_each_map() -> void:
	for entry: Dictionary in DATA.maps():
		var map_id: String = str(entry.get("id", ""))
		var scene_path: String = str(entry.get("scene", ""))
		var switcher: Node = current_scene.get("switcher")
		if switcher == null:
			_check(false, "菜单里没有 SceneSwitcher（%s）" % map_id)
			continue
		var accepted: bool = bool(switcher.call("enter_map", map_id))
		var arrived: bool = await _wait_scene(scene_path, 600)
		_check(accepted and arrived, "进入 %s（%s）" % [map_id, scene_path])
		if not arrived:
			continue
		if map_id == "cherry_valley":
			await _wait_build_complete(1800)
			_check(bool(current_scene.get("build_complete")), "樱花山谷生成完成后再返回")
		_check(_count_player_nodes() >= 1, "%s 里有玩家节点" % map_id)
		var hook: Node = root.get_node_or_null(DATA.RETURN_HOOK_NAME)
		var returned: bool = hook != null and bool(hook.call("return_to_menu"))
		var back: bool = await _wait_scene(MENU_SCENE, 600)
		_check(returned and back, "从 %s 返回地图选择" % map_id)
		await process_frame
		await process_frame
		_check(_playing_audio() == 0, "从 %s 返回后无残留背景音" % map_id)


# === 工具 ===

func _wait_scene(scene_path: String, max_frames: int = 300) -> bool:
	for _index: int in range(max_frames):
		await process_frame
		if current_scene != null and current_scene.scene_file_path == scene_path:
			return true
	return false


func _wait_build_complete(max_frames: int) -> void:
	for _index: int in range(max_frames):
		if current_scene == null:
			return
		if bool(current_scene.get("build_complete")):
			return
		await process_frame


func _buttons() -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in root.find_children("*", "Button", true, false):
		if node.is_in_group("map_entry_button"):
			result.append(node)
	return result


func _any_disabled(buttons: Array[Node]) -> bool:
	for node: Node in buttons:
		if (node as Button).disabled:
			return true
	return false


func _count_player_nodes() -> int:
	return root.find_children("*Player*", "CharacterBody3D", true, false).size()


func _count_cameras() -> int:
	return root.find_children("*", "Camera3D", true, false).size()


func _playing_audio() -> int:
	var count: int = 0
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		if (node as AudioStreamPlayer).playing:
			count += 1
	return count


func _check(ok: bool, message: String) -> void:
	if ok:
		_passes += 1
		print("PASS  " + message)
	else:
		_fails += 1
		print("FAIL  " + message)
