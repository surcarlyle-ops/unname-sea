extends CanvasLayer
## Compact action menu; gameplay no longer needs trial/debug hotkeys.
var arena: Node
var opened: bool = false
var _column: VBoxContainer

func _ready() -> void:
	layer = 110
	visible = false
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.02, 0.045, 0.70)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 360.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("171324")
	style.border_color = Color("766786")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 9)
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 16
	_column.theme = theme
	panel.add_child(_column)

func open() -> void:
	opened = true
	visible = true
	arena.player.menu_open = true
	arena.hud.set_process_input(false)
	arena.player.set_controls_active(false)
	if arena.fishing != null:
		arena.fishing.set_paused(true)
	_main()

func close() -> void:
	opened = false
	visible = false
	arena.player.menu_open = false
	arena.hud.set_process_input(true)
	arena.player.set_controls_active(true)
	if arena.fishing != null:
		arena.fishing.set_paused(false)

func _clear(title: String) -> void:
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	var label: Label = Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("e8cd96"))
	label.add_theme_font_size_override("font_size", 22)
	_column.add_child(label)

func _button(title: String, callback: Callable, enabled: bool = true) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.custom_minimum_size.y = 42.0
	button.disabled = not enabled
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color("30283e")
	normal.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("544157")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color("eee8f5"))
	button.pressed.connect(callback)
	_column.add_child(button)
	return button

func _main() -> void:
	_clear("菜单")
	_button("继续", close, not arena.player.dead).grab_focus()
	_button("重新开始", _retry)
	_button("选择试炼", _trials)
	_button("开发工具", _developer)
	_button("地图选择", _hub)

func _retry() -> void:
	arena.restart_round()
	close()

func _trials() -> void:
	_clear("选择试炼")
	var titles: Array[String] = ["清怪", "机动", "移动", "守卫", "钓鱼"]
	for index: int in range(titles.size()):
		_button(titles[index], _choose_trial.bind(index))
	_button("返回", _main)

func _choose_trial(index: int) -> void:
	arena.start_round(index)
	close()

func _developer() -> void:
	_clear("开发工具")
	_button("下一次钓到鱼", _force_catch.bind(false), arena.mode == 4)
	_button("下一次钓到异兽", _force_catch.bind(true), arena.mode == 4)
	_button("移动手感：" + arena.player.motion.profile_name(), _toggle_motion)
	_button("返回", _main)

func _force_catch(encounter: bool) -> void:
	if encounter:
		arena.fishing.force_encounter()
	else:
		arena.fishing.force_fish()
	close()

func _toggle_motion() -> void:
	arena.player.motion.toggle_profile()
	_developer()

func _hub() -> void:
	var hook: Node = get_tree().root.get_node_or_null("SceneReturnHook")
	if is_instance_valid(hook):
		hook.return_to_menu()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/map_select.tscn")
