extends CanvasLayer
## A small playtest HUD: controls, place, dodge cooldown and mouse release.

var _place: Label
var _detail: Label
var _progress: Label
var _dodge_label: Label
var _cooldown: ProgressBar
var _released: PanelContainer
var _notice: Label
var _notice_time: float = 0.0
var _root: Control


func _ready() -> void:
	var root: Control = Control.new()
	root.name = "Screen"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme.default_font = font
	theme.default_font_size = 16
	root.theme = theme
	add_child(root)
	_root = root
	_resize_root()
	get_viewport().size_changed.connect(_resize_root)
	var top: VBoxContainer = _panel(root, Vector2(28, 26), Vector2(355, 156))
	_add_label(top, "未名之海", 26, Color("f4ebcf"))
	_add_label(top, "01 / 岸边试走", 14, Color("b4cbc8"))
	_place = _add_label(top, "苇叶浅滩", 19, Color.WHITE)
	_detail = _add_label(top, "", 14, Color("d5dfd8"))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 305
	var bottom: VBoxContainer = _panel(root, Vector2.ZERO, Vector2(630, 88))
	var bottom_panel: Control = bottom.get_parent().get_parent() as Control
	bottom_panel.name = "Controls"
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_panel.offset_left = 28
	bottom_panel.offset_right = 658
	bottom_panel.offset_top = -119
	bottom_panel.offset_bottom = -31
	_add_label(bottom, "WASD 移动    鼠标 观察    Shift 闪避", 16, Color("f4ebcf"))
	_add_label(bottom, "R 回到起点    Esc 释放鼠标    点击画面继续", 14, Color("c3d2ce"))
	var right: VBoxContainer = _panel(root, Vector2.ZERO, Vector2(270, 154))
	var right_panel: Control = right.get_parent().get_parent() as Control
	right_panel.name = "Playtest"
	right_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_panel.offset_left = -298
	right_panel.offset_right = -28
	right_panel.offset_top = 26
	right_panel.offset_bottom = 180
	_add_label(right, "本轮试玩", 16, Color("f4ebcf"))
	_progress = _add_label(right, "", 14, Color("d5dfd8"))
	_dodge_label = _add_label(right, "闪避就绪", 14, Color("d5dfd8"))
	_cooldown = ProgressBar.new()
	_cooldown.custom_minimum_size = Vector2(215, 5)
	_cooldown.show_percentage = false
	_cooldown.max_value = 1.0
	_cooldown.add_theme_stylebox_override("background", _style(Color("486162"), 3))
	_cooldown.add_theme_stylebox_override("fill", _style(Color("dbbc7c"), 3))
	right.add_child(_cooldown)
	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_color", Color("fff1c5"))
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notice)
	_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.offset_left = -310
	_notice.offset_right = 310
	_notice.offset_top = -170
	_notice.offset_bottom = -134
	_released = PanelContainer.new()
	_released.add_theme_stylebox_override("panel", _style(Color(0.09, 0.17, 0.19, 0.95), 8))
	_released.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var released_text: Label = Label.new()
	released_text.text = "鼠标已释放\n点击画面继续试走"
	released_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	released_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	released_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_released.add_child(released_text)
	root.add_child(_released)
	_released.set_anchors_preset(Control.PRESET_CENTER)
	_released.offset_left = -200
	_released.offset_right = 200
	_released.offset_top = -47
	_released.offset_bottom = 47
	# The reticle helps evaluate free observation before attacks are introduced.
	var reticle: Label = Label.new()
	reticle.text = "+"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.modulate = Color(0.96, 0.96, 0.9, 0.65)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.offset_left = -7
	reticle.offset_right = 7
	reticle.offset_top = -14
	reticle.offset_bottom = 14


func _process(delta: float) -> void:
	_notice_time = maxf(0.0, _notice_time - delta)
	_notice.visible = _notice_time > 0.0


func _resize_root() -> void:
	_root.size = get_viewport().get_visible_rect().size


func update_status(player: CharacterBody3D, place: String, detail: String, dock_seen: bool, wall_seen: bool) -> void:
	_place.text = place
	_detail.text = detail
	_progress.text = "%s 走到木台\n%s 绕过石墙\n闪避 %d 次" % ["已到达" if dock_seen else "去看看", "已到达" if wall_seen else "去看看", player.dodge_count]
	_cooldown.value = 1.0 - player.cooldown_left / player.dodge_cooldown
	_dodge_label.text = "闪避冷却中" if player.cooldown_left > 0.0 else "闪避就绪"
	_released.visible = not player.controls_active


func show_notice(message: String) -> void:
	_notice.text = message
	_notice_time = 3.5


func _panel(parent: Control, point: Vector2, panel_size: Vector2) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = point
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.18, 0.2, 0.91), 8))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	return content


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box


func _add_label(parent: Node, label_text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
