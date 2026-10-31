extends Control
## 最小地图选择界面（CodeBuddyPro，2026-10-28）。
##
## 只用于验证场景切换组件能进入/返回三个试玩地图，不是正式 UI：
## 正式布局、配色、按钮与界面适配由 Codex 负责，直接调用 SceneSwitcher 即可。
##
## 入口：选择地图试玩.cmd → res://scenes/ui/map_select.tscn
## 返回：进入地图后按 F10（键位在 data/scene_menu.json 的 return_key）

const DATA = preload("res://scripts/ui/scene_menu_data.gd")
const SWITCHER_SCENE: PackedScene = preload("res://scenes/ui/scene_switcher.tscn")
const BUTTON_GROUP: String = "map_entry_button"
const TEXT_COLOR: Color = Color("f4ebcf")
const DIM_COLOR: Color = Color("9fb3ae")
const ERROR_COLOR: Color = Color("e8a882")

var switcher: Node
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	# 菜单一定是可点状态：放鼠标、清掉上一张地图留下的返回钩子。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_remove_stale_hook()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	switcher = SWITCHER_SCENE.instantiate()
	switcher.name = "SceneSwitcher"
	add_child(switcher)
	switcher.switch_started.connect(_on_switch_started)
	switcher.switch_failed.connect(_on_switch_failed)
	_build_ui()
	_set_status("点击地图进入 · 进入后按 %s 返回这里" % DATA.return_key_name(), DIM_COLOR)
	# 键盘也能用：方向键换项、回车进入。
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _remove_stale_hook() -> void:
	var hook: Node = get_tree().root.get_node_or_null(DATA.RETURN_HOOK_NAME)
	if hook != null:
		hook.queue_free()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.055, 0.075, 0.09)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(900.0, 0.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.12, 0.14, 0.94)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(0.0)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 30)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_label("未名之海 · 试玩地图选择", 28, TEXT_COLOR))
	column.add_child(_label("三个入口都是当前可试玩的独立场景；主战斗 Demo 与独立预览分开标注。", 14, DIM_COLOR))
	column.add_child(_label(str(DATA.session_notice()), 13, DIM_COLOR))
	column.add_child(_spacer(6))

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	column.add_child(list)
	for entry: Dictionary in DATA.maps():
		list.add_child(_map_row(entry))

	column.add_child(_spacer(4))
	_status = _label("", 14, TEXT_COLOR)
	column.add_child(_status)
	column.add_child(_label("入口：选择地图试玩.cmd · 正式 UI 由 Codex 接入 SceneSwitcher", 12, Color(0.62, 0.70, 0.68, 0.85)))


func _map_row(entry: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.17, 0.19, 0.92)
	style.set_corner_radius_all(8)
	row.add_theme_stylebox_override("panel", style)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	row.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var map_id: String = str(entry.get("id", ""))
	var button: Button = Button.new()
	button.text = "%s ｜ %s" % [str(entry.get("kind_label", "独立预览")), str(entry.get("name", map_id))]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", Color("fff8e2"))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.58, 0.8))
	button.add_theme_stylebox_override("normal", _box(Color(0.14, 0.23, 0.25, 0.95), Color(0.0, 0.0, 0.0, 0.0)))
	button.add_theme_stylebox_override("hover", _box(Color(0.19, 0.31, 0.33, 0.98), Color("d2ac68")))
	button.add_theme_stylebox_override("pressed", _box(Color(0.24, 0.38, 0.39, 1.0), Color("d2ac68")))
	button.add_theme_stylebox_override("focus", _box(Color(0.0, 0.0, 0.0, 0.0), Color("d2ac68")))
	button.add_theme_stylebox_override("disabled", _box(Color(0.10, 0.15, 0.17, 0.8), Color(0.0, 0.0, 0.0, 0.0)))
	button.add_to_group(BUTTON_GROUP)
	button.pressed.connect(_on_map_pressed.bind(map_id))
	column.add_child(button)
	_buttons.append(button)

	var detail: Label = _label("%s ｜ %s\n%s" % [
		str(entry.get("status", "")), str(entry.get("scene", "")), str(entry.get("description", ""))], 13, DIM_COLOR)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	return row


func _on_map_pressed(map_id: String) -> void:
	if switcher == null or switcher.is_switching():
		return
	switcher.enter_map(map_id)


func _on_switch_started(map_id: String, scene_path: String) -> void:
	_set_buttons_enabled(false)
	var entry: Dictionary = DATA.find_map(map_id)
	var map_name: String = str(entry.get("name", ""))
	if map_name.is_empty():
		map_name = scene_path.get_file()
	_set_status("正在进入 %s …" % map_name, TEXT_COLOR)


func _on_switch_failed(_map_id: String, reason: String) -> void:
	_set_buttons_enabled(true)
	_set_status("进入失败：%s" % reason, ERROR_COLOR)


func _set_buttons_enabled(enabled: bool) -> void:
	for button: Button in _buttons:
		if is_instance_valid(button):
			button.disabled = not enabled


func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _spacer(height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _box(color: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10.0)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(1)
	return box
