extends Control
## The player-facing menu; routing and return handling stay in SceneSwitcher.

const DATA: Script = preload("res://scripts/ui/scene_menu_data.gd")
const SWITCHER_SCENE: PackedScene = preload("res://scenes/ui/scene_switcher.tscn")
const COPY_PATH: String = "res://data/scene_menu_presentation.json"
const ART: String = "res://assets/ui/trial_menu/"
const INK: Color = Color("12111e")
const PANEL: Color = Color("211e31")
const BORDER: Color = Color("423b55")
const TEXT: Color = Color("F0EAF4")
const DIM: Color = Color("A9A1B7")
const GOLD: Color = Color("D9BE87")

var switcher: Node
var selected_id: String = ""
var _entries: Array[Dictionary] = []
var _copy: Dictionary = {}
var _buttons: Array[Button] = []
var _cards: Array[Dictionary] = []
var _textures: Dictionary = {}
var _status: Label
var _enter: Button
var _title: Label
var _subtitle: Label
var _description: Label
var _kind: Label
var _image_caption: Label
var _photo: TextureRect
var _features: HFlowContainer
var _margin: MarginContainer
var _body: BoxContainer
var _destinations: BoxContainer
var _image_panel: PanelContainer
var _footer: BoxContainer
var _busy: bool = false
var _font: SystemFont


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stale: Node = get_tree().root.get_node_or_null(DATA.RETURN_HOOK_NAME)
	if stale != null:
		stale.queue_free()
	_copy = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH)) as Dictionary
	_entries = DATA.maps()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var menu_theme: Theme = Theme.new()
	menu_theme.default_font = _font
	menu_theme.default_font_size = 14
	theme = menu_theme
	switcher = SWITCHER_SCENE.instantiate()
	switcher.name = "SceneSwitcher"
	add_child(switcher)
	switcher.switch_started.connect(_on_switch_started)
	switcher.switch_failed.connect(_on_switch_failed)
	_build_ui()
	resized.connect(_update_layout)
	_update_layout()
	if not _entries.is_empty():
		var remembered: String = str(get_tree().get_meta("trial_menu_selected", ""))
		select_map(remembered if not DATA.find_map(remembered).is_empty() else str(_entries[0].id))
	else:
		_status.text = "还没有可进入的地图。"
		_enter.disabled = true


func _build_ui() -> void:
	var background: TextureRect = TextureRect.new()
	background.texture = _texture(ART + "backdrop.svg")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_margin.add_child(scroll)
	var page: VBoxContainer = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	_build_header(page)
	var divider: ColorRect = ColorRect.new()
	divider.color = Color(BORDER, 0.7)
	divider.custom_minimum_size.y = 1
	page.add_child(divider)
	var section: HBoxContainer = HBoxContainer.new()
	section.custom_minimum_size.y = 44
	section.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(section)
	var heading: VBoxContainer = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	section.add_child(heading)
	heading.add_child(_label("选择一处出发", 23, TEXT))
	var flow: HBoxContainer = HBoxContainer.new()
	flow.visible = false
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("separation", 10)
	section.add_child(flow)
	flow.add_child(_label("选择地图", 12, GOLD))
	flow.add_child(_icon("arrow.svg", 18))
	flow.add_child(_label("进入体验", 12, DIM))
	flow.add_child(_icon("arrow.svg", 18))
	flow.add_child(_label(DATA.return_key_name() + " 返回", 12, DIM))
	flow.name = "JourneyHint"
	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_body)
	_destinations = BoxContainer.new()
	_destinations.vertical = true
	_destinations.add_theme_constant_override("separation", 12)
	_body.add_child(_destinations)
	for i: int in range(_entries.size()):
		_build_card(_entries[i], i)
	_build_detail()
	_build_footer(page)


func _build_header(page: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.custom_minimum_size.y = 56
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)
	header.add_child(_icon("compass.svg", 49))
	var brand: VBoxContainer = VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 2)
	header.add_child(brand)
	brand.add_child(_label("未名之海", 28, TEXT))
	brand.add_child(_label("THE UNNAMED SEA", 10, GOLD))
	var badge: PanelContainer = PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _style(Color("262337"), BORDER, 7, 11))
	badge.add_child(_label("开发试玩  /  0.1", 12, DIM))
	header.add_child(badge)
	var exit_button: Button = Button.new()
	exit_button.icon = _texture(ART + "close.svg")
	exit_button.custom_minimum_size = Vector2(40, 40)
	exit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exit_button.tooltip_text = "退出试玩"
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	_button_styles(exit_button, false)
	header.add_child(exit_button)


func _build_card(entry: Dictionary, index: int) -> void:
	var id: String = str(entry.id)
	var copy: Dictionary = _copy.get(id, {}) as Dictionary
	var button: Button = Button.new()
	button.name = "Map_" + id
	button.custom_minimum_size = Vector2(0, 126)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_to_group("map_entry_button")
	button.set_meta("map_id", id)
	button.tooltip_text = str(entry.get("name", id))
	button.pressed.connect(select_map.bind(id))
	_destinations.add_child(button)
	_buttons.append(button)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	button.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var number: Label = _label("0" + str(index + 1), 12, DIM)
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(number)
	var category: Label = _label(str(entry.get("kind_label", "独立预览")), 11, DIM)
	top.add_child(category)
	var title: Label = _label(str(copy.get("title", entry.get("name", id))), 21, TEXT)
	column.add_child(title)
	var teaser: Label = _label(str(copy.get("subtitle", "选择并进入试玩。")), 11, DIM)
	column.add_child(teaser)
	_cards.append({"button": button, "number": number, "title": title, "category": category, "teaser": teaser})
	_ignore_child_mouse(margin)


func _build_detail() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("201e30"), BORDER, 13, 0))
	_body.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	var image_panel: PanelContainer = PanelContainer.new()
	_image_panel = image_panel
	image_panel.clip_contents = true
	image_panel.custom_minimum_size.y = 218
	image_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(image_panel)
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_panel.add_child(_photo)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.07, 0.06, 0.12, 0.17)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_panel.add_child(shade)
	var image_overlay: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		image_overlay.add_theme_constant_override("margin_" + edge, 16)
	image_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_panel.add_child(image_overlay)
	var overlay: VBoxContainer = VBoxContainer.new()
	image_overlay.add_child(overlay)
	_kind = _label("", 12, Color("FFFFFF"))
	var category_badge: PanelContainer = PanelContainer.new()
	category_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	category_badge.add_theme_stylebox_override("panel", _style(Color(0.08, 0.07, 0.13, 0.87), Color(0.7, 0.65, 0.8, 0.2), 5, 8))
	category_badge.add_child(_kind)
	overlay.add_child(category_badge)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(spacer)
	_image_caption = _label("实机预览", 11, Color("F0EAF4"))
	var caption_badge: PanelContainer = PanelContainer.new()
	caption_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	caption_badge.add_theme_stylebox_override("panel", _style(Color(0.08, 0.07, 0.13, 0.8), Color.TRANSPARENT, 4, 6, 0))
	caption_badge.add_child(_image_caption)
	overlay.add_child(caption_badge)
	var detail_margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		detail_margin.add_theme_constant_override("margin_" + edge, 20)
	column.add_child(detail_margin)
	var details: VBoxContainer = VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	detail_margin.add_child(details)
	_title = _label("", 25, TEXT)
	details.add_child(_title)
	_description = _label("", 13, DIM)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 42
	_description.add_theme_constant_override("line_spacing", 4)
	details.add_child(_description)
	_features = HFlowContainer.new()
	_features.add_theme_constant_override("h_separation", 8)
	_features.add_theme_constant_override("v_separation", 6)
	details.add_child(_features)


func _build_footer(page: VBoxContainer) -> void:
	_footer = BoxContainer.new()
	_footer.add_theme_constant_override("separation", 20)
	page.add_child(_footer)
	var notes: VBoxContainer = VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 5)
	_footer.add_child(notes)
	_status = _label("选择地图，然后进入体验。", 13, TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(_status)
	var session_note: Label = _label("", 11, DIM)
	session_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(session_note)
	_enter = Button.new()
	_enter.name = "EnterMap"
	_enter.custom_minimum_size = Vector2(216, 52)
	_enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_enter.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_enter.add_theme_font_size_override("font_size", 17)
	_enter.icon = _texture(ART + "arrow.svg")
	_enter.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enter.add_theme_color_override("font_color", Color("211B20"))
	_enter.add_theme_color_override("font_hover_color", Color("211B20"))
	_enter.add_theme_color_override("font_pressed_color", Color("211B20"))
	_enter.add_theme_color_override("icon_normal_color", Color("211B20"))
	_enter.add_theme_color_override("icon_hover_color", Color("211B20"))
	_enter.add_theme_stylebox_override("normal", _style(GOLD, Color("F0D7A4"), 8, 17))
	_enter.add_theme_stylebox_override("hover", _style(Color("ECD3A4"), Color("F5E3BF"), 8, 17))
	_enter.add_theme_stylebox_override("pressed", _style(Color("BDA16A"), GOLD, 8, 17))
	_enter.add_theme_stylebox_override("disabled", _style(Color("4A4352"), BORDER, 8, 17))
	_enter.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("FFF0D4"), 8, 17, 2))
	_enter.pressed.connect(enter_selected)
	_footer.add_child(_enter)


func select_map(map_id: String) -> void:
	if _busy:
		return
	var entry: Dictionary = DATA.find_map(map_id)
	if entry.is_empty():
		return
	selected_id = map_id
	get_tree().set_meta("trial_menu_selected", map_id)
	var copy: Dictionary = _copy.get(map_id, {}) as Dictionary
	var accent: Color = Color(str(copy.get("accent", "#D9BE87")))
	_title.text = str(copy.get("title", entry.get("name", map_id)))
	_description.text = str(copy.get("summary", entry.get("description", "")))
	_kind.text = str(entry.get("kind_label", "独立预览"))
	_enter.text = "进入" + _title.text
	_photo.texture = _texture(str(copy.get("image", "")))
	_image_caption.text = "实机预览" if _photo.texture != null else "场景预览待补充"
	for child: Node in _features.get_children():
		_features.remove_child(child)
		child.queue_free()
	for text: String in copy.get("features", ["独立试玩"]):
		var chip: PanelContainer = PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _style(Color(accent, 0.08), Color(accent, 0.25), 5, 7))
		chip.add_child(_label(text, 11, accent))
		_features.add_child(chip)
	for card: Dictionary in _cards:
		var button: Button = card.button as Button
		var selected: bool = str(button.get_meta("map_id")) == map_id
		_button_styles(button, selected)
		(card.number as Label).add_theme_color_override("font_color", GOLD if selected else DIM)
		(card.title as Label).add_theme_color_override("font_color", GOLD if selected else TEXT)
	_status.text = "准备前往 · " + _title.text
	_status.tooltip_text = ""
	_status.add_theme_color_override("font_color", TEXT)


func enter_selected() -> void:
	if not _busy and not selected_id.is_empty():
		switcher.enter_map(selected_id)


func _on_switch_started(map_id: String, _scene_path: String) -> void:
	_busy = true
	_set_buttons_enabled(false)
	var entry: Dictionary = DATA.find_map(map_id)
	_status.text = "正在进入 " + str(entry.get("name", "地图")) + "，请稍候…"
	_status.add_theme_color_override("font_color", GOLD)
	_enter.text = "正在进入…"


func _on_switch_failed(_map_id: String, reason: String) -> void:
	_busy = false
	_set_buttons_enabled(true)
	_status.text = "暂时无法进入，请重试或选择其他地图。"
	_status.tooltip_text = reason
	_status.add_theme_color_override("font_color", Color("E7A7A0"))
	_enter.text = "重新进入" + _title.text


func _set_buttons_enabled(enabled: bool) -> void:
	for button: Button in _buttons:
		button.disabled = not enabled
	_enter.disabled = not enabled


func _input(event: InputEvent) -> void:
	if _busy or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: Key = event.physical_keycode
	var index: int = 0
	for i: int in range(_entries.size()):
		if str(_entries[i].id) == selected_id:
			index = i
	if code in [KEY_UP, KEY_DOWN] and not _entries.is_empty():
		index = posmod(index + (-1 if code == KEY_UP else 1), _entries.size())
		select_map(str(_entries[index].id))
	elif code >= KEY_1 and code <= KEY_3 and int(code - KEY_1) < _entries.size():
		select_map(str(_entries[int(code - KEY_1)].id))
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		enter_selected()
	else:
		return
	get_viewport().set_input_as_handled()


func _update_layout() -> void:
	if _body == null:
		return
	var narrow: bool = size.x < 900.0
	var side: int = 24 if narrow else 44
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", 24)
	_margin.add_theme_constant_override("margin_bottom", 24)
	_body.vertical = narrow
	_footer.vertical = size.x < 600.0
	_destinations.vertical = not narrow
	_destinations.custom_minimum_size.x = 0.0 if narrow else 316.0
	_destinations.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	_image_panel.custom_minimum_size.y = 130.0 if narrow else 218.0
	_enter.custom_minimum_size.x = 180.0 if narrow else 216.0
	for card: Dictionary in _cards:
		(card.button as Button).custom_minimum_size.y = 104.0 if narrow else 126.0
		(card.button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(card.teaser as Label).visible = not narrow
	var flow: Node = find_child("JourneyHint", true, false)
	if flow is Control:
		flow.visible = not narrow


func _button_styles(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", _style(Color("302A3C") if selected else Color("211E30"), GOLD if selected else BORDER, 10, 0))
	button.add_theme_stylebox_override("hover", _style(Color("363044"), GOLD, 10, 0))
	button.add_theme_stylebox_override("pressed", _style(Color("3A3246"), GOLD, 10, 0))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("E5D0A6"), 10, 0, 2))
	button.add_theme_stylebox_override("disabled", _style(Color("211E2C"), BORDER, 10, 0))


func _style(background: Color, border: Color, radius: int, padding: int, width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _icon(file: String, side: int) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = _texture(ART + file)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path) as Texture2D
	elif FileAccess.file_exists(path):
		# New local captures remain previewable before an editor import.
		var image: Image = Image.load_from_file(path)
		texture = ImageTexture.create_from_image(image) if image != null else null
	_textures[path] = texture
	return texture


func _ignore_child_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		if child is Control:
			_ignore_child_mouse(child as Control)
