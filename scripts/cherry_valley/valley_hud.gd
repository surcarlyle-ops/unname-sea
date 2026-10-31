extends Control
## (Claude Code) Restrained landscape HUD: title and hint along the screen edges,
## a small status strip for mood/quality/shot, and a loading veil. Never covers
## the centre of the screen.

const COL_TEXT: Color = Color(0.94, 0.93, 0.97)
const COL_DIM: Color = Color(0.74, 0.72, 0.80)
const COL_ACCENT: Color = Color(0.98, 0.84, 0.62)
const COL_PANEL: Color = Color(0.06, 0.07, 0.12, 0.55)

var config: Dictionary
var loading: bool = true
## Set when the scene cannot build; the veil switches from progress to a clear
## error line so a missing or broken data file never leaves a blank screen.
var error_text: String = ""
var loading_text: String = "樱花山谷"
var loading_progress: float = 0.0
var mood_label: String = ""
var quality_label: String = "高画质"
var shot_label: String = ""
var ui_hidden: bool = false
var show_help: bool = true
## (Claude Code) Touch devices get a shorter, action-only hint instead of key names.
var mobile: bool = false

var _font: SystemFont
var _hint_timer: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])


func set_loading(enabled: bool, message: String = "", progress: float = 0.0) -> void:
	loading = enabled
	if message != "":
		loading_text = message
	loading_progress = progress
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	_hint_timer += delta
	queue_redraw()


func set_error(message: String) -> void:
	error_text = message
	loading = true
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var scale_factor: float = minf(size.x / 1280.0, size.y / 720.0)
	var offset: Vector2 = (size - Vector2(1280, 720) * scale_factor) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * scale_factor)
	if error_text != "":
		_draw_error()
		return
	if loading:
		_draw_loading()
		return
	if ui_hidden:
		return
	_draw_title()
	_draw_status()


func _draw_loading() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.06, 0.10, 1.0))
	var title_size: int = 34
	var width: float = _font.get_string_size(loading_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	_text(Vector2((1280.0 - width) * 0.5, 330.0), loading_text, title_size, COL_TEXT)
	var bar: Rect2 = Rect2(440.0, 362.0, 400.0, 4.0)
	draw_rect(bar, Color(1, 1, 1, 0.10), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(loading_progress, 0.0, 1.0), bar.size.y)), Color(COL_ACCENT, 0.85), true)
	var hint: String = "正在生成山谷"
	var hint_width: float = _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2((1280.0 - hint_width) * 0.5, 396.0), hint, 13, COL_DIM)


func _draw_error() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.06, 0.10, 1.0))
	var title: String = "樱花山谷 加载失败"
	var title_width: float = _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_text(Vector2((1280.0 - title_width) * 0.5, 330.0), title, 30, Color(0.96, 0.82, 0.70))
	var body: String = error_text
	var body_width: float = _font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(Vector2((1280.0 - body_width) * 0.5, 372.0), body, 14, COL_DIM)
	var hint: String = "请检查 data/cherry_valley.json 后重新运行"
	var hint_width: float = _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2((1280.0 - hint_width) * 0.5, 398.0), hint, 13, Color(COL_DIM, 0.7))


func _draw_title() -> void:
	var title: String = str(config.scene.title)
	var subtitle: String = str(config.scene.subtitle)
	var breathe: float = 0.82 + sin(_pulse * 0.9) * 0.18
	# A soft scrim plus an outline keeps the title readable over bright sky and over
	# pale hillside without turning into a heavy panel.
	for step: int in range(3):
		var t: float = float(step) / 3.0
		draw_rect(Rect2(0.0, 0.0, 300.0 - t * 90.0, 96.0), Color(0.04, 0.05, 0.09, 0.10 + t * 0.06), true)
	_text_outlined(Vector2(34.0, 52.0), title, 26, Color(COL_TEXT, breathe))
	_text_outlined(Vector2(36.0, 74.0), subtitle, 12, Color(COL_DIM, 0.9))
	draw_line(Vector2(34, 84), Vector2(34 + 148, 84), Color(COL_ACCENT, 0.55), 1.2)


func _draw_status() -> void:
	var items: Array[String] = []
	items.append("氛围 · " + mood_label)
	items.append("画质 · " + quality_label)
	if shot_label != "":
		items.append("机位 · " + shot_label)
	var width: float = 0.0
	for item: String in items:
		width = maxf(width, _font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var panel: Rect2 = Rect2(1280.0 - 34.0 - width - 24.0, 28.0, width + 24.0, 22.0 + 20.0 * float(items.size()))
	draw_rect(panel, COL_PANEL, true)
	draw_rect(Rect2(panel.position, Vector2(2.0, panel.size.y)), Color(COL_ACCENT, 0.75), true)
	for index: int in range(items.size()):
		_text(Vector2(panel.position.x + 14.0, panel.position.y + 22.0 + 20.0 * float(index)), items[index], 13, COL_DIM)


func _draw_help() -> void:
	var lines: Array[String] = [
		"WASD 移动   ·   鼠标 视角   ·   空格 跳跃   ·   Shift 走路   ·   R 回到起点",
		"C 运镜   ·   Q / E 切换机位   ·   T 自动巡游   ·   J 环境音   ·   M 氛围   ·   Y 画质   ·   H 隐藏界面",
	]
	if mobile:
		lines = [
			"左半屏 移动   ·   右半屏拖动 视角",
		]
	var alpha: float = clampf((18.0 - _hint_timer) / 2.0, 0.0, 1.0)
	var max_width: float = 0.0
	for line: String in lines:
		max_width = maxf(max_width, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var panel: Rect2 = Rect2((1280.0 - max_width - 36.0) * 0.5, 640.0, max_width + 36.0, 58.0)
	draw_rect(panel, Color(COL_PANEL, COL_PANEL.a * alpha * 1.25), true)
	for index: int in range(lines.size()):
		_text_outlined(Vector2(panel.position.x + 18.0, panel.position.y + 24.0 + 22.0 * float(index)), lines[index], 13, Color(COL_DIM, alpha))


func _text(point: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Text with a dark outline: the title sits directly on the sky, so it needs its own
## contrast instead of relying on whatever is behind it.
func _text_outlined(point: Vector2, value: String, font_size: int, color: Color) -> void:
	var outline: Color = Color(0.03, 0.04, 0.07, 0.55 * color.a)
	draw_string_outline(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, outline)
	draw_string(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
