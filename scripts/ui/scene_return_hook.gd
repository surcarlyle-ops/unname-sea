extends Node
## 地图内的"返回地图选择"钩子（CodeBuddyPro，2026-10-28）。
##
## 由 SceneSwitcher 在进入地图前挂到 root 下（节点名 SceneReturnHook），
## 所以换场景时不会被一起释放；回到地图选择界面后由菜单负责清掉。
##
## 只做两件事：响应返回键（默认 B，键位在 data/scene_menu.json 的 return_key，
## 不用 F1–F12 功能键）、在屏幕右下角显示一个可点击的返回按钮。正式 UI 由 Codex 负责，这里是可替换的占位。

const DATA = preload("res://scripts/ui/scene_menu_data.gd")
const NORMAL_COLOR: Color = Color("e8e0c8")
const ERROR_COLOR: Color = Color("e8a882")

var _returning: bool = false
var _menu_path: String = ""
var _return_key: int = KEY_B
var _error_left: float = 0.0
var _layer: CanvasLayer
var _label: Label
var _button: Button


func _ready() -> void:
	_menu_path = DATA.menu_scene_path()
	_return_key = DATA.return_keycode()
	_build_hint()
	set_process(true)


func _process(delta: float) -> void:
	var scene: Node = get_tree().current_scene
	var in_menu: bool = scene != null and scene.scene_file_path == _menu_path
	if _layer != null:
		_layer.visible = not in_menu and not (scene != null and scene.has_method("open_play_menu"))
	if _error_left > 0.0:
		_error_left = maxf(0.0, _error_left - delta)
		if _error_left <= 0.0:
			_set_text("返回地图选择", NORMAL_COLOR)


func _unhandled_input(event: InputEvent) -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_method("open_play_menu"):
		return
	if _returning:
		return
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	# Backspace 作为备用：键盘没有功能键时，两根手指随便哪个都能退。
	if key.physical_keycode != _return_key and key.physical_keycode != KEY_BACKSPACE:
		return
	if return_to_menu():
		get_viewport().set_input_as_handled()


## 供 UI 或验证脚本直接调用。返回 false 表示没走成（正在返回或加载失败）。
func return_to_menu() -> bool:
	if _returning:
		return false
	_returning = true
	# 回菜单前先放鼠标，菜单一定是可点的。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var packed: PackedScene = DATA.load_scene(_menu_path)
	if packed == null:
		_returning = false
		_show_error("返回失败：%s" % DATA.failure_reason(_menu_path))
		return false
	var error: int = get_tree().change_scene_to_packed(packed)
	if error != OK:
		_returning = false
		_show_error("返回失败（错误码 %d）" % error)
		return false
	return true


func is_returning() -> bool:
	return _returning


func return_key_name() -> String:
	return DATA.return_key_name()


func _show_error(message: String) -> void:
	_error_left = 4.0
	_set_text(message, ERROR_COLOR)


func _set_text(text: String, color: Color) -> void:
	if _label == null:
		return
	_label.text = text
	_label.add_theme_color_override("font_color", color)


func _build_hint() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ReturnHint"
	# 压在各地图自带 HUD 之上。
	_layer.layer = 128
	add_child(_layer)
	# 用按钮而不是纯文字：鼠标可用时（背包打开、山谷里）直接点就能退，不依赖功能键。
	_button = Button.new()
	_button.name = "ReturnButton"
	# 不抢焦点，地图里的 Enter / 方向键照旧归地图 UI。
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = ""
	_button.add_theme_stylebox_override("normal", _hint_style(Color(0.09, 0.075, 0.15, 0.90), Color(0.85, 0.75, 0.53, 0.38)))
	_button.add_theme_stylebox_override("hover", _hint_style(Color(0.16, 0.13, 0.24, 0.96), Color(0.90, 0.80, 0.58, 0.90)))
	_button.add_theme_stylebox_override("pressed", _hint_style(Color(0.20, 0.17, 0.29, 1.0), Color(0.90, 0.80, 0.58, 1.0)))
	_button.add_theme_stylebox_override("focus", _hint_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_button.pressed.connect(_on_hint_pressed)
	_layer.add_child(_button)
	# 右下角：训练场的快捷栏/试炼标题/生命条、岸边的控制面板、山谷的标题与状态都在别处，
	# 这里是三张地图都不占用的位置。
	_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_button.offset_left = -224.0
	_button.offset_right = -20.0
	_button.offset_top = -58.0
	_button.offset_bottom = -20.0
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_button.add_child(margin)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 13)
	_set_text("返回地图选择", NORMAL_COLOR)
	margin.add_child(_label)


func _hint_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _on_hint_pressed() -> void:
	if _returning:
		return
	return_to_menu()
