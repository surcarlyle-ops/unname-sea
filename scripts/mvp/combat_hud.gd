extends Control
## Combat HUD: five-slot hotbar, health, trial info, state strip, contextual grapple panel.
## Visual style: deep violet glassmorphism, warm-gold accent, center screen stays clear.

const CROSSHAIR: Script = preload("res://scripts/mvp/crosshair.gd")
const SLOT_ITEMS: Array[String] = ["", "practice_blade", "tide_blade", "steam_pistol", "potion"]
const SLOT_ITEM_NAMES: Array[String] = ["空", "练习刃", "时钟剑", "潮汐手炮", "潮汐药水"]

# --- Palette: 地心世界 · 深紫薄雾 · 暖金点缀 ---
const COL_PANEL: Color = Color(0.07, 0.06, 0.13, 0.78)
const COL_PANEL_SOFT: Color = Color(0.10, 0.09, 0.17, 0.70)
const COL_BORDER: Color = Color(0.55, 0.48, 0.78, 0.38)
const COL_SHEEN: Color = Color(0.85, 0.78, 0.95, 0.10)
const COL_TEXT: Color = Color(0.96, 0.94, 0.99)
const COL_TEXT_DIM: Color = Color(0.68, 0.63, 0.80)
const COL_TEXT_FAINT: Color = Color(0.52, 0.48, 0.66)
const COL_GOLD: Color = Color(0.94, 0.81, 0.56)
const COL_DANGER: Color = Color(0.90, 0.44, 0.40)
const COL_TRACK: Color = Color(0.18, 0.16, 0.28, 0.85)
const COL_HEALTH: Color = Color(0.45, 0.88, 0.75)
const COL_SLOT: Color = Color(0.13, 0.11, 0.21, 0.80)
const COL_SLOT_LIT: Color = Color(0.20, 0.17, 0.32, 0.90)
const COL_HAZE: Color = Color(0.03, 0.04, 0.09, 0.55)
const COL_INK: Color = Color(0.05, 0.04, 0.09, 0.85)

var arena: Node3D
var _font: SystemFont
var _menu: PanelContainer
var _options: Array[OptionButton] = []
var _updating: bool = false
var _crosshair: Control
var _hurt_flash: float = 0.0
var _display_health: float = 0.0
var _hit_mark: float = 0.0
var _last_hit_time: float = -1.0
var _pulse: float = 0.0
# (Claude Code) Apex-style damage direction cue: arc + chevron on the side the hit came from.
var _damage_dir: Vector2 = Vector2.UP  ## screen-space direction toward the attacker
var _damage_fade: float = 0.0          ## 1 → 0 over roughly half a second
# (Claude Code) Short speed streaks layered on top of a swing, separate from mantle boost.
var _swing_streak: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	_crosshair = Control.new()
	_crosshair.set_script(CROSSHAIR)
	_crosshair.hook_path = arena.player.grapple.get_path()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_crosshair)
	_build_menu()
	arena.player.health_changed.connect(_on_health_changed)
	# (Claude Code) The controller reports which side the hit came from.
	arena.player.hurt_direction.connect(_on_hurt_direction)
	_display_health = float(arena.player.max_health)


func _process(delta: float) -> void:
	_pulse += delta
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	_crosshair.visible = arena.player.controls_active and not arena.player.menu_open
	if arena.player != null:
		_display_health = lerpf(_display_health, float(arena.player.health), 1.0 - exp(-10.0 * delta))
		if arena.player.last_hit_time != _last_hit_time:
			_last_hit_time = arena.player.last_hit_time
			_hit_mark = 1.0
	_hit_mark = maxf(0.0, _hit_mark - delta * 4.0)
	# (Claude Code) Direction cue decays a little slower than the edge flash so it reads.
	_damage_fade = maxf(0.0, _damage_fade - delta * 2.0)
	# Cheap fallback: any swing in progress keeps a faint streak buffer alive.
	if arena.player.attack_elapsed >= 0.0:
		_swing_streak = maxf(_swing_streak, 0.55)
	_swing_streak = maxf(0.0, _swing_streak - delta * 3.2)
	queue_redraw()


func _draw() -> void:
	if _font == null or arena == null or arena.player == null:
		return
	var scale_factor: float = minf(size.x / 1280.0, size.y / 720.0)
	var offset: Vector2 = (size - Vector2(1280, 720) * scale_factor) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * scale_factor)
	var player: CharacterBody3D = arena.player

	_draw_hotbar(player)
	_draw_health(player)
	_draw_trial_info()
	_draw_energy_pips(player)
	_draw_hit_markers()
	_draw_feedback_layers(player)


# === 快捷栏（左上） ===
func _draw_hotbar(player: CharacterBody3D) -> void:
	_glass(Rect2(28, 26, 320, 82))
	_text(Vector2(44, 46), "快捷物品", 13, COL_TEXT_DIM)
	for slot: int in range(5):
		var x: float = 44.0 + slot * 56.0
		var selected: bool = slot == player.selected_slot
		var cell: Rect2 = Rect2(x, 54, 48, 44)
		if selected:
			# 外发光
			draw_rect(cell.grow(2.5), Color(COL_GOLD, 0.18), true)
			draw_rect(cell.grow(2.5), Color(COL_GOLD, 0.75), false, 1.6)
		_slot_cell(cell, selected)
		_text(Vector2(x + 4, 66), str(slot + 1), 11, Color(COL_TEXT_DIM, 0.85) if not selected else COL_GOLD)
		var icon_center: Vector2 = Vector2(x + 24.0, 80.0)
		var item_id: String = player.quick_slots[slot]
		if item_id == "tide_blade":
			_draw_blade_icon(icon_center, 1.0 if not selected else 1.12, Color(0.45, 1.0, 0.90))
		elif item_id == "practice_blade":
			_draw_blade_icon(icon_center, 1.0 if not selected else 1.12)
		elif item_id == "steam_pistol":
			_draw_pistol_icon(icon_center, 1.0 if not selected else 1.12)
		elif item_id == "potion":
			_draw_potion_icon(icon_center, 1.0 if not selected else 1.12)
		else:
			draw_circle(icon_center, 2.2, Color(COL_TEXT_FAINT, 0.7))


func _slot_cell(cell: Rect2, selected: bool) -> void:
	# 底
	draw_rect(cell, COL_SLOT_LIT if selected else COL_SLOT, true)
	# 顶部光泽
	draw_rect(Rect2(cell.position, Vector2(cell.size.x, 1.5)), COL_SHEEN, true)
	# 描边
	draw_rect(cell, COL_GOLD if selected else COL_BORDER, false, 1.4 if selected else 1.0)


# === 药水图标（玻璃瓶 + 青绿液体 + 软木塞） ===
func _draw_potion_icon(center: Vector2, icon_scale: float) -> void:
	var s: float = icon_scale
	var x: float = center.x
	var y: float = center.y
	# 瓶身
	draw_rect(Rect2(x - 5 * s, y - 4 * s, 10 * s, 12 * s), Color(0.55, 0.72, 0.68, 0.75))
	# 液体
	draw_rect(Rect2(x - 4 * s, y + 1 * s, 8 * s, 6 * s), Color(0.32, 0.95, 0.82))
	# 瓶颈
	draw_rect(Rect2(x - 2 * s, y - 9 * s, 4 * s, 6 * s), Color(0.55, 0.72, 0.68, 0.75))
	# 软木塞
	draw_rect(Rect2(x - 2.4 * s, y - 12 * s, 4.8 * s, 3.5 * s), Color(0.46, 0.34, 0.22))
	# 高光
	draw_rect(Rect2(x - 3.5 * s, y - 3 * s, 1.4 * s, 8 * s), Color(1.0, 1.0, 1.0, 0.25))


# === 手枪图标（深蓝枪管 + 青绿枪口 + 木质握把 + 黄铜护圈） ===
func _draw_pistol_icon(center: Vector2, icon_scale: float) -> void:
	var s: float = icon_scale
	var x: float = center.x
	var y: float = center.y
	# 枪管
	draw_rect(Rect2(x - 13 * s, y - 5 * s, 21 * s, 4.5 * s), Color(0.34, 0.40, 0.47))
	draw_rect(Rect2(x - 13 * s, y - 5 * s, 21 * s, 1.5 * s), Color(0.52, 0.60, 0.67))
	# 枪口磷光
	draw_circle(Vector2(x - 13 * s, y - 2.8 * s), 2.6 * s, Color(0.42, 1.0, 0.88, 0.9))
	# 机匣
	draw_rect(Rect2(x + 1 * s, y - 7 * s, 9 * s, 7.5 * s), Color(0.28, 0.33, 0.39))
	# 木质握把
	draw_line(Vector2(x + 3 * s, y + 0.5 * s), Vector2(x + 9 * s, y + 10 * s), Color(0.48, 0.34, 0.24), 4.2 * s)
	# 扳机护圈
	draw_arc(Vector2(x + 1 * s, y + 2.5 * s), 3.4 * s, 0.0, PI, 10, COL_GOLD, 1.4 * s)
	# 黄铜箍环
	draw_rect(Rect2(x - 3 * s, y - 5.5 * s, 2.2 * s, 5.5 * s), COL_GOLD)


# === 剑形图标（分层：剑刃光泽 + 金色护手 + 棕色剑柄） ===
func _draw_blade_icon(center: Vector2, icon_scale: float, blade_color: Color = Color(0.82, 0.88, 0.86)) -> void:
	var s: float = icon_scale
	var x: float = center.x
	var y: float = center.y
	# 剑刃（两段：深色底 + 亮面）
	draw_rect(Rect2(x - 2.5 * s, y - 15 * s, 5 * s, 19 * s), blade_color)
	draw_rect(Rect2(x - 2.5 * s, y - 15 * s, 2 * s, 19 * s), blade_color.darkened(0.28))
	# 剑尖
	draw_line(Vector2(x - 2.5 * s, y - 15 * s), Vector2(x, y - 19 * s), blade_color, 2.0 * s)
	draw_line(Vector2(x + 2.5 * s, y - 15 * s), Vector2(x, y - 19 * s), blade_color, 2.0 * s)
	# 护手（暖金）
	draw_rect(Rect2(x - 8 * s, y + 4 * s, 16 * s, 2.5 * s), COL_GOLD)
	# 剑柄
	draw_rect(Rect2(x - 1.8 * s, y + 6.5 * s, 3.6 * s, 6 * s), Color(0.48, 0.34, 0.24))
	# 柄头
	draw_circle(Vector2(x, y + 13.5 * s), 2.2 * s, Color(0.62, 0.44, 0.30))


# === 生命值（左下 · Apex 分段式） ===
func _draw_health(player: CharacterBody3D) -> void:
	_glass(Rect2(28, 614, 340, 78))
	var health_ratio: float = clampf(_display_health / float(player.max_health), 0.0, 1.0)
	var hp_color: Color = COL_TEXT
	if health_ratio <= 0.3:
		var breathe: float = 0.75 + sin(_pulse * 6.0) * 0.25
		hp_color = Color(COL_DANGER, breathe)
	# 左上标签 + 右上大数字
	_text(Vector2(46, 638), "生命", 12, COL_TEXT_DIM)
	var num_text: String = "%d" % player.health
	var num_w: float = _font.get_string_size(num_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	_text(Vector2(336 - num_w, 646), num_text, 26, hp_color)
	_text(Vector2(336 - num_w - 52, 642), "/ %d" % player.max_health, 13, COL_TEXT_DIM)
	# 分段血条：5 段，每段 20 血
	var seg_count: int = 5
	var per_seg: float = float(player.max_health) / seg_count
	var seg_w: float = 55.0
	var gap: float = 6.0
	var bar_y: float = 656.0
	var seg_h: float = 12.0
	for i: int in range(seg_count):
		var seg_x: float = 46.0 + i * (seg_w + gap)
		var seg_rect: Rect2 = Rect2(seg_x, bar_y, seg_w, seg_h)
		draw_rect(seg_rect, COL_TRACK, true)
		var seg_health: float = clampf(_display_health - i * per_seg, 0.0, per_seg)
		var fill_ratio: float = seg_health / per_seg
		if fill_ratio > 0.0:
			var fill_color: Color = COL_HEALTH.lerp(COL_DANGER, clampf((0.3 - health_ratio) / 0.3, 0.0, 1.0))
			draw_rect(Rect2(seg_x, bar_y, seg_w * fill_ratio, seg_h), fill_color, true)
			draw_rect(Rect2(seg_x, bar_y, seg_w * fill_ratio, 1.4), Color(1, 1, 1, 0.30), true)
		# 段描边
		draw_rect(seg_rect, Color(COL_BORDER, 0.6), false, 1.0)


# === 试炼信息（中上） ===
func _draw_trial_info() -> void:
	var title: String = "清怪试炼" if arena.mode == 0 else ("机动试炼" if arena.mode == 1 else "移动练习")
	var count: String = "%d / 5" % mini(arena.course.progress + 1, 5) if arena.mode == 2 else "%d / %d" % [arena.defeated_count, arena.round_total]
	var label: String = title + "  ·  " + count
	var tw: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var panel_w: float = tw + 48.0
	var px: float = (1280.0 - panel_w) * 0.5
	_glass(Rect2(px, 20, panel_w, 40))
	# 两侧装饰线
	var mid_y: float = 40.0
	draw_line(Vector2(px + 12, mid_y), Vector2(px + 24, mid_y), COL_BORDER, 1.0)
	draw_line(Vector2(px + panel_w - 24, mid_y), Vector2(px + panel_w - 12, mid_y), COL_BORDER, 1.0)
	var text_x: float = px + (panel_w - tw) * 0.5
	_text(Vector2(text_x, 46), label, 17, COL_TEXT)


# === 鸣潮刃充能格（准星下方） ===
func _draw_energy_pips(player: CharacterBody3D) -> void:
	var maximum: int = player.energy_max()
	if maximum <= 0:
		return
	var filled: int = player.energy
	var spacing: float = 17.0
	var start_x: float = 640.0 - float(maximum - 1) * spacing * 0.5
	var full: bool = filled >= maximum
	var breathe: float = 1.0 if not full else 0.72 + sin(_pulse * 6.0) * 0.28
	for i: int in range(maximum):
		var point: Vector2 = Vector2(start_x + float(i) * spacing, 394.0)
		if i < filled:
			draw_circle(point, 7.0, Color(0.42, 1.0, 0.90, 0.14 * breathe))
			draw_circle(point, 4.2, Color(0.42, 1.0, 0.90, 0.92 * breathe))
		else:
			draw_circle(point, 3.2, Color(0.42, 0.58, 0.56, 0.32))


# === 命中标记 ===
func _draw_hit_markers() -> void:
	if _hit_mark <= 0.0:
		return
	var spread: float = 9.0 + 7.0 * _hit_mark
	var thickness: float = 2.0 + _hit_mark * 1.0
	var color: Color = Color(COL_GOLD, _hit_mark)
	var center: Vector2 = Vector2(640, 360)
	for direction: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_line(center + direction * 9, center + direction * spread, color, thickness)


# === 受伤红闪 + 暂停遮罩 ===
func _draw_feedback_layers(player: CharacterBody3D) -> void:
	# 翻越冲刺：放射状风线 + 边缘气流感，让玩家确认吃到了加速。
	if player.boost_effect > 0.01:
		_draw_boost_lines(player.boost_effect, false)
	# (Claude Code) Swings get a lighter, shorter streak burst than a mantle boost.
	if _swing_streak > 0.01:
		_draw_boost_lines(_swing_streak, true)
	if _hurt_flash > 0.0:
		# (Claude Code) Keep only a faint full-screen tint; the direction cue carries the
		# "where from" information, so the edges no longer flash uniformly red.
		var a: float = _hurt_flash * 0.45
		draw_rect(Rect2(0, 0, 1280, 720), Color(COL_DANGER, a * 0.16))
		_draw_damage_direction()
	if not player.controls_active and not player.menu_open:
		draw_rect(Rect2(0, 0, 1280, 720), COL_HAZE)
		var pw: float = 460.0
		var ph: float = 200.0
		var px: float = (1280.0 - pw) * 0.5
		var py: float = (720.0 - ph) * 0.5
		_glass(Rect2(px, py, pw, ph))
		var title: String = "战败了" if player.dead else "未名之海"
		var tw: float = _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		_text(Vector2(px + (pw - tw) * 0.5, py + 52), title, 28, COL_TEXT)
		var subtitle: String = "按 R 重试当前试炼" if player.dead else "移动与战斗试玩"
		var sw: float = _font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(Vector2(px + (pw - sw) * 0.5, py + 86), subtitle, 16, COL_GOLD)
		var hint1: String = "点击画面开始 / 继续"
		var h1w: float = _font.get_string_size(hint1, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text(Vector2(px + (pw - h1w) * 0.5, py + 130), hint1, 13, COL_TEXT_DIM)


# === 翻越冲刺风线 ===
## (Claude Code) Reworked streaks: three depth layers (long faint, mid, short bright),
## tapered lines, radial speed feel and a thin edge vignette. Swing mode reuses the
## same look at lower intensity and with fewer lines.
func _draw_boost_lines(strength: float, quick: bool) -> void:
	var center: Vector2 = Vector2(640, 360)
	var count: int = 18 if quick else 40
	var reach: float = 300.0 if quick else 640.0
	var lifetime_alpha: float = 0.20 if quick else 0.85
	var jitter_scale: float = 1.0 if quick else 1.6
	for i: int in range(count):
		# Fixed pseudo-random keeps every streak in the same slot across frames.
		var seed_a: float = float((i * 37 + 11) % 17) / 17.0
		var seed_b: float = float((i * 53 + 7) % 13) / 13.0
		var angle: float = TAU * float(i) / float(count) + 0.17 + seed_a * 0.08
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var inner: float = (185.0 + seed_a * 90.0) * jitter_scale
		var length: float = (70.0 + seed_b * 150.0) * jitter_scale
		var alpha: float = strength * lifetime_alpha * (0.25 + seed_b * 0.75)
		# Two segments per streak: a thin tail and a brighter head → reads as motion.
		var head: Vector2 = center + direction * (inner + length)
		var tail: Vector2 = center + direction * inner
		var mid: Vector2 = center + direction * (inner + length * 0.55)
		draw_line(tail, mid, Color(1.0, 1.0, 1.0, alpha * 0.30), 1.0)
		draw_line(mid, head, Color(1.0, 1.0, 1.0, alpha * 0.85), 1.6 + seed_a * 1.8)
	# Thin vignette on every edge; quick swings keep it subtle.
	var edge: float = strength * (0.045 if quick else 0.13)
	var edge_w: float = 4.0 if quick else 7.0
	draw_rect(Rect2(0, 0, 1280, edge_w), Color(1, 1, 1, edge))
	draw_rect(Rect2(0, 720 - edge_w, 1280, edge_w), Color(1, 1, 1, edge))
	draw_rect(Rect2(0, 0, edge_w, 720), Color(1, 1, 1, edge))
	draw_rect(Rect2(1280 - edge_w, 0, edge_w, 720), Color(1, 1, 1, edge))


# === Apex 风格受击方向指示 ===
## (Claude Code) An arc hugging the screen edge on the attacker's side, plus a
## chevron pointing inward. Positioned on a squircle so it reads the same on
## wide and narrow resolutions.
func _draw_damage_direction() -> void:
	var intensity: float = clampf(_damage_fade, 0.0, 1.0)
	if intensity <= 0.0 or _damage_dir.length_squared() < 0.001:
		return
	var dir: Vector2 = _damage_dir.normalized()
	# _damage_dir is (right, forward) in view space; screen Y grows downward.
	var screen_dir: Vector2 = Vector2(dir.x, -dir.y).normalized()
	var center: Vector2 = Vector2(640, 360)
	# Anchor point on a rounded ring near the edge.
	var ring: Vector2 = Vector2(470.0, 300.0)
	var anchor: Vector2 = center + Vector2(screen_dir.x * ring.x, screen_dir.y * ring.y)
	var base_angle: float = atan2(screen_dir.y, screen_dir.x)
	var arc_span: float = 0.85  # ~49 degrees each way
	var arc_radius: float = 62.0
	var steps: int = 18
	var arc_alpha: float = intensity * 0.55
	# Soft outer glow then the crisp arc core.
	for layer: int in range(2):
		var radius: float = arc_radius + (10.0 if layer == 0 else 0.0)
		var width: float = 12.0 if layer == 0 else 4.0
		var alpha: float = arc_alpha * (0.35 if layer == 0 else 1.0)
		var previous: Vector2 = anchor + Vector2(cos(base_angle - arc_span), sin(base_angle - arc_span)) * radius
		for step: int in range(1, steps + 1):
			var t: float = float(step) / float(steps)
			# Taper the arc toward both ends so it dissolves into the edge.
			var angle: float = base_angle - arc_span + arc_span * 2.0 * t
			var point: Vector2 = anchor + Vector2(cos(angle), sin(angle)) * radius
			var taper: float = sin(t * PI)
			draw_line(previous, point, Color(COL_DANGER, alpha * (0.35 + taper * 0.65)), width * (0.45 + taper * 0.55))
			previous = point
	# Chevron pointing inward, from the edge toward the crosshair.
	var inward: Vector2 = (center - anchor).normalized()
	var tip: Vector2 = anchor + inward * 38.0
	var back: Vector2 = anchor + inward * 8.0
	var side: Vector2 = Vector2(-inward.y, inward.x) * 16.0
	draw_line(back + side, tip, Color(COL_DANGER, intensity * 0.9), 4.5)
	draw_line(back - side, tip, Color(COL_DANGER, intensity * 0.9), 4.5)


# === 玻璃面板绘制 ===
func _glass(rect: Rect2) -> void:
	draw_style_box(_panel_style(COL_PANEL), rect)


func _panel_style(bg: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(COL_BORDER, COL_BORDER.a * bg.a / COL_PANEL.a)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style


func _panel(rect: Rect2) -> void:
	draw_style_box(_panel_style(COL_PANEL), rect)


func _text(point: Vector2, value: String, font_size: int, color: Color = COL_TEXT) -> void:
	draw_string(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# === 装备配置菜单 ===
func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", _panel_style(COL_PANEL))
	_menu.add_theme_font_override("font", _font)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.offset_left = -230
	_menu.offset_right = 230
	_menu.offset_top = -205
	_menu.offset_bottom = 205
	add_child(_menu)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_menu.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title: Label = Label.new()
	title.text = "快捷物品配置"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COL_TEXT)
	column.add_child(title)
	var detail: Label = Label.new()
	detail.text = "当前只有练习刃可用，可放入任意一格。"
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", COL_TEXT_DIM)
	column.add_child(detail)
	for slot: int in range(5):
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = "物品位 %d    " % (slot + 1)
		label.add_theme_color_override("font_color", COL_TEXT_DIM)
		row.add_child(label)
		var option: OptionButton = OptionButton.new()
		for item_name: String in SLOT_ITEM_NAMES:
			option.add_item(item_name)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.item_selected.connect(_on_slot_selected.bind(slot))
		row.add_child(option)
		_options.append(option)
		column.add_child(row)
	var close: Button = Button.new()
	close.text = "完成并继续  /  Tab"
	close.pressed.connect(arena._toggle_loadout)
	column.add_child(close)
	_menu.hide()


func open_loadout() -> void:
	_refresh_options()
	_menu.show()


func close_loadout() -> void:
	if _menu != null:
		_menu.hide()
	arena.player.menu_open = false


func _refresh_options() -> void:
	_updating = true
	for slot: int in range(5):
		var item: String = arena.player.quick_slots[slot]
		_options[slot].select(maxi(SLOT_ITEMS.find(item), 0))
	_updating = false


func _on_slot_selected(item: int, slot: int) -> void:
	if _updating:
		return
	arena.player.assign_quick_slot(slot, SLOT_ITEMS[clampi(item, 0, SLOT_ITEMS.size() - 1)])
	_refresh_options()


func _on_health_changed(_value: int) -> void:
	if arena.player.hurt_time_left > 0.0:
		_hurt_flash = 0.24
		# (Claude Code) Fallback: if the direction signal was missed, guess "from the side"
		# instead of leaving the cue blank.
		_damage_fade = maxf(_damage_fade, 1.0)


## (Claude Code) Direction comes from first_person_player.receive_damage.
## x = right component, y = forward component of the attacker in view space,
## so (0, 1) means "in front", (-1, 0) means "on your left".
func _on_hurt_direction(direction: Vector2) -> void:
	_damage_dir = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	_damage_fade = 1.0
