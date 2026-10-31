extends Node
## 场景切换组件（CodeBuddyPro，2026-10-28）。
##
## 供统一入口 UI 调用。只负责"进入某个试玩地图 / 回到地图选择"，
## 不碰各地图的玩家、背包、钓鱼或存档逻辑；每次切换都是整场景重载。
##
## 用法（Codex 的统一入口 UI）：
##   var switcher := preload("res://scenes/ui/scene_switcher.tscn").instantiate()
##   add_child(switcher)
##   switcher.switch_failed.connect(_on_switch_failed)   # (map_id, reason)
##   switcher.switch_started.connect(_on_switch_started) # (map_id, scene_path)
##   for entry in switcher.maps():                        # id/name/kind/kind_label/status/description/scene
##       ...
##   switcher.enter_map("combat_mvp")                     # false = 未知 id 或正在切换
##   switcher.back_to_menu()                              # 回到 data/scene_menu.json 的 menu_scene
##   switcher.is_switching() / switcher.switching_map_id()
##   switcher.session_notice()                            # "每次进入都会重开"的提示文案
##   switcher.return_key_name()                           # 地图内返回键（"F10"），交给 UI 显示
##
## 进入地图后，返回入口由 scripts/ui/scene_return_hook.gd 提供（挂在 root 下，F10）。

signal switch_started(map_id: String, scene_path: String)
signal switch_failed(map_id: String, reason: String)

const DATA = preload("res://scripts/ui/scene_menu_data.gd")
const RETURN_HOOK_SCRIPT: Script = preload("res://scripts/ui/scene_return_hook.gd")

var _switching: bool = false
var _switching_id: String = ""


## 地图清单（直接来自 data/scene_menu.json）。
func maps() -> Array[Dictionary]:
	return DATA.maps()


func session_notice() -> String:
	return DATA.session_notice()


func return_key_name() -> String:
	return DATA.return_key_name()


func menu_scene_path() -> String:
	return DATA.menu_scene_path()


func is_switching() -> bool:
	return _switching


func switching_map_id() -> String:
	return _switching_id


## 进入清单里的地图。返回 false 表示这次请求被拒绝（未知 id 或正在切换）。
func enter_map(map_id: String) -> bool:
	if _switching:
		return false
	var entry: Dictionary = DATA.find_map(map_id)
	if entry.is_empty():
		_fail(map_id, "地图清单里没有这张地图：%s" % map_id)
		return false
	return _begin_switch(map_id, str(entry.get("scene", "")))


## 直接按场景路径进入（清单外的临时场景/测试用）。label 只用于状态与提示。
func enter_scene(scene_path: String, label: String = "") -> bool:
	if _switching:
		return false
	return _begin_switch(label if not label.is_empty() else scene_path, scene_path)


## 回到地图选择界面。
func back_to_menu() -> bool:
	if _switching:
		return false
	return _begin_switch("menu", DATA.menu_scene_path())


func _begin_switch(map_id: String, scene_path: String) -> bool:
	_switching = true
	_switching_id = map_id
	switch_started.emit(map_id, scene_path)
	_perform_switch.call_deferred(map_id, scene_path)
	return true


## 真正加载与换场景。先自己 load，失败时菜单还活着，可以把原因显示出来。
func _perform_switch(map_id: String, scene_path: String) -> void:
	if not is_inside_tree():
		_fail(map_id, "切换组件不在场景树里")
		return
	var packed: PackedScene = DATA.load_scene(scene_path)
	if packed == null:
		_fail(map_id, DATA.failure_reason(scene_path))
		return
	# 先放鼠标：旧场景里可能有捕获，换场景瞬间不该继续锁着。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ensure_return_hook()
	var error: int = get_tree().change_scene_to_packed(packed)
	if error != OK:
		_fail(map_id, "切换场景失败（错误码 %d）：%s" % [error, scene_path])
		return
	# 成功后本节点随旧场景一起释放，不再复位状态，避免同一帧内被再次点击。


func _fail(map_id: String, reason: String) -> void:
	_switching = false
	_switching_id = ""
	switch_failed.emit(map_id, reason)


## 地图内的返回钩子挂在 root 下，切场景不会被释放；已存在就复用，避免重复。
func _ensure_return_hook() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if tree.root.get_node_or_null(DATA.RETURN_HOOK_NAME) != null:
		return
	var hook: Node = RETURN_HOOK_SCRIPT.new()
	hook.name = DATA.RETURN_HOOK_NAME
	tree.root.add_child(hook)
