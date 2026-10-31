extends Control
## Combat HUD: five-slot hotbar, health, trial info, state strip, contextual grapple panel.
## Visual style: deep violet glassmorphism, warm-gold accent, center screen stays clear.

const CROSSHAIR: Script = preload("res://scripts/mvp/crosshair.gd")
const SLOT_ITEMS: Array[String] = ["", "tide_blade", "steam_pistol", "m1911", "potion", "dark_knight_sword", "sword_08", "lowpoly_axe", "lowpoly_bat", "lowpoly_knife", "lowpoly_rifle", "lowpoly_sniper", "scifi_knife", "fishing_rod"]
const SLOT_ITEM_NAMES: Array[String] = ["空", "时钟剑", "潮汐手炮", "M1911（测试）", "潮汐药水", "暗黑骑士长剑", "长剑08", "低模斧", "低模球棒", "低模短刀", "低模步枪", "低模狙击", "暗影匕首", "钓鱼竿"]
## 导入批次的快捷栏标识：两字标记 + 独立颜色，避免十件新武器在 48px 格子里
## 共用同一个剑/枪图标而分不清。ranged 决定枪械还是冷兵器的底色条。
const IMPORTED_MARKS: Dictionary = {
	"dark_knight_sword": {"mark": "黑骑", "color": Color(0.88, 0.74, 0.42), "ranged": false},
	"sword_08": {"mark": "剑08", "color": Color(0.80, 0.88, 0.86), "ranged": false},
	"lowpoly_axe": {"mark": "斧", "color": Color(0.88, 0.56, 0.34), "ranged": false},
	"lowpoly_bat": {"mark": "棒", "color": Color(0.92, 0.82, 0.58), "ranged": false},
	"lowpoly_knife": {"mark": "刀", "color": Color(0.76, 0.80, 0.88), "ranged": false},
	"lowpoly_rifle": {"mark": "步枪", "color": Color(0.54, 0.82, 0.70), "ranged": true},
	"lowpoly_sniper": {"mark": "狙击", "color": Color(0.74, 0.70, 0.96), "ranged": true},
	"scifi_knife": {"mark": "暗匕", "color": Color(0.55, 0.90, 0.95), "ranged": false},
}

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
var _damage_numbers: Array[Dictionary] = []
var _damage_sequence: int = 0
## 坠落扣血提示：血条上方短暂显示数值。
var _fall_text: String = ""
var _fall_text_time: float = 0.0
## 非阻塞提示：钓鱼渔获、背包已满、测试指令等，固定在下方淡出。
var _messages: Array[Dictionary] = []


## 任何系统都可以推送一行短暂提示；不挡鼠标、不挡操作。
func push_message(message: String) -> void:
	if message.is_empty():
		return
	_messages.append({"text": message, "age": 0.0})
	while _messages.size() > 3:
		_messages.pop_front()


func clear_messages() -> void:
	_messages.clear()


func clear_damage_numbers() -> void:
	_damage_numbers.clear()


func add_damage_number(amount: int, point: Vector3, armored: bool) -> void:
	if amount <= 0:
		return
	_damage_sequence += 1
	_damage_numbers.append({"amount":amount, "point":point, "age":0.0, "armored":armored, "side":-1.0 if _damage_sequence % 2 == 0 else 1.0})
	if _damage_numbers.size() > 40:
		_damage_numbers.pop_front()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	_crosshair = Control.new()
	_crosshair.set_script(CROSSHAIR)
	_crosshair.hook_path = arena.player.grapple.get_path()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_crosshair)
	arena.player.health_changed.connect(_on_health_changed)
	arena.player.fall_damage_taken.connect(_on_fall_damage)
	# (Claude Code) The controller reports which side the hit came from.
	arena.player.hurt_direction.connect(_on_hurt_direction)
	_display_health = float(arena.player.max_health)


func _process(delta: float) -> void:
	for i: int in range(_damage_numbers.size() - 1, -1, -1):
		_damage_numbers[i].age += delta
		if float(_damage_numbers[i].age) >= 0.8:
			_damage_numbers.remove_at(i)
	_pulse += delta
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	_fall_text_time = maxf(_fall_text_time - delta, 0.0)
	for index: int in range(_messages.size() - 1, -1, -1):
		_messages[index].age = float(_messages[index].age) + delta
		if float(_messages[index].age) >= 2.6:
			_messages.remove_at(index)
	_crosshair.visible = arena.player.controls_active and not arena.player.menu_open
	if arena.player != null:
		_display_health = lerpf(_display_health, float(arena.player.health), 1.0 - exp(-10.0 * delta))
		if arena.player.last_hit_time != _last_hit_time:
			_last_hit_time = arena.player.last_hit_time
			_hit_mark = 1.0
	_hit_mark = maxf(0.0, _hit_mark - delta * 4.0)
	# (Claude Code) Direction cue decays a little slower than the edge flash so it reads.
	_damage_fade = maxf(0.0, _damage_fade - delta * 2.0)
	# Only melee swings keep the fallback streak buffer alive.
	if arena.player.attack_elapsed >= 0.0 and not bool(arena.player._weapon.get("ranged", false)):
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

	if not player.menu_open:
		_draw_hotbar(player)
	_draw_health(player)
	_draw_guardian_health()
	_draw_energy_pips(player)
	_draw_hit_markers()
	_draw_feedback_layers(player)
	_draw_damage_numbers(scale_factor, offset)
	# Expand the same upper-left hotbar instead of opening a second central panel.
	if arena.play_menu == null or not arena.play_menu.opened:
		_draw_backpack(player)


func _draw_damage_numbers(scale_factor: float, offset: Vector2) -> void:
	var camera: Camera3D = arena.player.camera
	for item: Dictionary in _damage_numbers:
		var point: Vector3 = item.point
		if camera.is_position_behind(point):
			continue
		var age: float = item.age
		var at: Vector2 = (camera.unproject_position(point) - offset) / maxf(scale_factor, 0.001)
		at += Vector2(float(item.side) * (10.0 + age * 18.0), -18.0 - age * 55.0)
		var text: String = str(item.amount)
		var color: Color = Color("c8c6bc") if item.armored else Color("ffd97b")
		color.a = 1.0 - smoothstep(0.5, 0.8, age)
		at.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x * 0.5
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, 5, Color(0.06, 0.04, 0.03, color.a))
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, color)


# === 快捷栏（左上） ===
func _draw_hotbar(player: CharacterBody3D) -> void:
	_glass(Rect2(28, 26, 320, 82))
	_text(Vector2(44, 46), "快捷物品", 13, COL_TEXT_DIM)
	for slot: int in range(5):
		var cell: Rect2 = _backpack_cell(0, slot)
		var x: float = cell.position.x
		var selected: bool = slot == player.selected_slot
		if selected:
			# 外发光
			draw_rect(cell.grow(2.5), Color(COL_GOLD, 0.18), true)
			draw_rect(cell.grow(2.5), Color(COL_GOLD, 0.75), false, 1.6)
		_slot_cell(cell, selected)
		_text(Vector2(x + 4, 66), str(slot + 1), 11, Color(COL_TEXT_DIM, 0.85) if not selected else COL_GOLD)
		var icon_center: Vector2 = Vector2(x + 24.0, 80.0)
		_draw_item_icon(player.quick_slots[slot], icon_center, 1.0 if not selected else 1.12)


# === 统一物品图标：快捷栏与背包共用，避免两套图标对不上 ===
func _draw_item_icon(item_id: String, center: Vector2, icon_scale: float) -> void:
	if item_id == "fishing_rod":
		_draw_rod_icon(center, icon_scale)
	elif item_id.begins_with("fish_"):
		# 两种鱼分开配色：苍白小鲦偏冷青，环鳞鱼偏银绿并加两道鳞环。
		var fish_color: Color = Color(0.62, 0.86, 0.88) if item_id == "fish_pale_minnow" else Color(0.88, 0.90, 0.74)
		_draw_fish_icon(center, icon_scale, fish_color)
		if item_id == "fish_ring_scale":
			for i: int in range(2):
				draw_arc(center + Vector2(3.0, 0.0) * icon_scale, (4.5 + 2.0 * float(i)) * icon_scale, -1.2, 1.2, 8, Color(0.96, 0.90, 0.72, 0.8), 1.1 * icon_scale)
	elif item_id == "item_scale":
		_draw_scale_icon(center, icon_scale)
	elif item_id == "tide_blade":
		_draw_blade_icon(center, icon_scale, Color(0.45, 1.0, 0.90))
	elif item_id == "practice_blade":
		_draw_blade_icon(center, icon_scale)
	elif item_id == "steam_pistol":
		_draw_pistol_icon(center, icon_scale)
	elif item_id == "m1911":
		draw_line(center + Vector2(-13, -6) * icon_scale, center + Vector2(13, -6) * icon_scale, COL_TEXT, 5.0)
		draw_line(center + Vector2(6, -5) * icon_scale, center + Vector2(3, 10) * icon_scale, COL_GOLD, 6.0)
	elif item_id == "potion":
		_draw_potion_icon(center, icon_scale)
	elif arena != null and arena.player != null and not arena.player.equipment_def(item_id).is_empty():
		_draw_equipment_mark(center, arena.player.equipment_def(item_id))
	elif IMPORTED_MARKS.has(item_id):
		_draw_imported_mark(center, item_id)
	elif not item_id.is_empty():
		draw_circle(center, 2.2, Color(COL_TEXT_FAINT, 0.7))


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


# === 装备/饰品标识（用文字标记代替图标） ===
func _draw_equipment_mark(center: Vector2, def: Dictionary) -> void:
	var color: Color = Color(str(def.get("color", "#c9b8ff")))
	var mark: String = str(def.get("mark", "?"))
	var font_size: int = 11
	var width: float = _font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(Vector2(center.x - width * 0.5, center.y + 1.0), mark, font_size, color)
	draw_rect(Rect2(center.x - 9.0, center.y + 5.0, 18.0, 2.0), Color(color, 0.75))
	draw_circle(center + Vector2(0.0, 11.0), 1.6, Color(color, 0.9))


# === 导入武器标识（两字标记 + 底色条，冷兵器/枪械分色） ===
func _draw_imported_mark(center: Vector2, item_id: String) -> void:
	var info: Dictionary = IMPORTED_MARKS[item_id]
	var color: Color = info.color
	var mark: String = str(info.mark)
	var font_size: int = 11
	var width: float = _font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(Vector2(center.x - width * 0.5, center.y + 1.0), mark, font_size, color)
	var bar_y: float = center.y + 5.0
	draw_rect(Rect2(center.x - 9.0, bar_y, 18.0, 2.0), Color(color, 0.75))
	# 枪械加一段短横线，冷兵器加一个小三角，缩略格子里也能一眼分开。
	if bool(info.ranged):
		draw_rect(Rect2(center.x + 9.0, bar_y - 1.0, 4.0, 3.0), Color(color, 0.95))
	else:
		draw_line(Vector2(center.x - 13.0, bar_y + 1.0), Vector2(center.x - 10.0, bar_y - 2.0), Color(color, 0.95), 1.6)
		draw_line(Vector2(center.x - 10.0, bar_y - 2.0), Vector2(center.x - 7.0, bar_y + 1.0), Color(color, 0.95), 1.6)


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
	# 坠落扣血：在血条上方淡出，避免和受伤方向箭头混淆。
	if _fall_text_time > 0.0:
		var fade: float = clampf(_fall_text_time / 0.6, 0.0, 1.0)
		_text(Vector2(46, 606), _fall_text, 15, Color(COL_DANGER, fade))


func _on_fall_damage(amount: int) -> void:
	_fall_text = "坠落 -%d" % amount
	_fall_text_time = 1.6


# === 试炼信息（中上） ===
func _draw_trial_info() -> void:
	var title: String = ["清怪试炼", "机动试炼", "移动练习", "守卫试炼", "钓鱼试炼"][arena.mode]
	var count: String = ""
	if arena.mode == 2:
		count = "%d / 5" % mini(arena.course.progress + 1, 5)
	elif arena.mode == 4:
		count = "渔获 %d" % (arena.loot.total_items() if arena.loot != null else 0)
	else:
		count = "%d / %d" % [arena.defeated_count, arena.round_total]
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


func _draw_guardian_health() -> void:
	if arena.mode != 3:
		return
	var boss: CharacterBody3D = arena.guardian
	if not is_instance_valid(boss):
		return
	var panel: Rect2 = Rect2(410, 76, 460, 65)
	_glass(panel)
	_text(Vector2(426, 98), "玄岩重卫", 17, COL_GOLD)
	_text(Vector2(676, 98), "%d / %d" % [boss.health, boss.max_health], 14, COL_TEXT_DIM)
	var track: Rect2 = Rect2(426, 108, 428, 8)
	draw_rect(track, COL_TRACK)
	draw_rect(Rect2(track.position, Vector2(track.size.x * float(boss.health) / maxf(float(boss.max_health), 1.0), track.size.y)), COL_DANGER)


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
		var ph: float = 96.0
		var px: float = (1280.0 - pw) * 0.5
		var py: float = (720.0 - ph) * 0.5
		_glass(Rect2(px, py, pw, ph))
		var title: String = "战败了" if player.dead else "未名之海"
		var tw: float = _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		_text(Vector2(px + (pw - tw) * 0.5, py + 52), title, 28, COL_TEXT)



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


# === 背包（泰拉瑞亚式：第一行就是快捷栏，下面是储物格） ===
const BACKPACK_COLUMNS: int = 5
const BACKPACK_ROWS: int = 4
const BACKPACK_CELL: float = 48.0
const BACKPACK_CELL_HEIGHT: float = 44.0
const BACKPACK_GAP: float = 8.0
const BACKPACK_PAD: float = 16.0
const BACKPACK_HEADER: float = 28.0
const BACKPACK_FOOTER: float = 72.0

var _held_item: String = ""
var _held_from: Vector2i = Vector2i(-1, -1)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _mouse_position: Vector2 = Vector2.ZERO


func open_loadout() -> void:
	_held_item = ""
	_held_from = Vector2i(-1, -1)
	_hover_cell = Vector2i(-1, -1)
	_loot_hover = -1
	_loot_selected = -1
	_mouse_position = get_local_mouse_position() + global_position


func close_loadout() -> void:
	_held_item = ""
	_held_from = Vector2i(-1, -1)
	_hover_cell = Vector2i(-1, -1)
	arena.player.menu_open = false


func _backpack_rect() -> Rect2:
	var grid_height: float = BACKPACK_ROWS * BACKPACK_CELL_HEIGHT + (BACKPACK_ROWS - 1) * BACKPACK_GAP
	return Rect2(28, 26, 320, BACKPACK_HEADER + grid_height + BACKPACK_FOOTER)


func _backpack_cell(row: int, column: int) -> Rect2:
	var panel: Rect2 = _backpack_rect()
	var origin: Vector2 = panel.position + Vector2(BACKPACK_PAD, BACKPACK_HEADER)
	var step: Vector2 = Vector2(BACKPACK_CELL, BACKPACK_CELL_HEIGHT) + Vector2.ONE * BACKPACK_GAP
	return Rect2(origin + Vector2(column, row) * step, Vector2(BACKPACK_CELL, BACKPACK_CELL_HEIGHT))


func _item_name(item_id: String) -> String:
	if arena != null and arena.player != null:
		var equip_name: String = arena.player.equipment_name(item_id)
		if not equip_name.is_empty():
			return equip_name
	var index: int = SLOT_ITEMS.find(item_id)
	if index >= 0 and index < SLOT_ITEM_NAMES.size():
		return SLOT_ITEM_NAMES[index]
	var fish: Dictionary = GameData.get_fish(item_id)
	if not fish.is_empty():
		return str(fish.get("name", item_id))
	var item: Dictionary = GameData.get_item(item_id)
	if not item.is_empty():
		return str(item.get("name", item_id))
	return item_id


func _draw_backpack(player: CharacterBody3D) -> void:
	if not player.menu_open:
		return
	var panel: Rect2 = _backpack_rect()
	_glass(panel)
	_text(panel.position + Vector2(BACKPACK_PAD, 20), "背包 · 快捷物品", 13, COL_TEXT_DIM)
	for row: int in range(BACKPACK_ROWS):
		for column: int in range(BACKPACK_COLUMNS):
			var cell: Rect2 = _backpack_cell(row, column)
			var index: Vector2i = Vector2i(row, column)
			var item_id: String = player.slot_item(row, column)
			var hotbar: bool = row == 0
			var selected: bool = hotbar and column == player.selected_slot
			if selected:
				draw_rect(cell.grow(2.5), Color(COL_GOLD, 0.18), true)
				draw_rect(cell.grow(2.5), Color(COL_GOLD, 0.75), false, 1.6)
			_slot_cell(cell, selected)
			if hotbar:
				_text(cell.position + Vector2(4.0, 12.0), str(column + 1), 11, COL_GOLD if selected else COL_TEXT_DIM)
			# 拿在手上的那格画成空的，避免看起来有两份。
			if not item_id.is_empty() and index != _held_from:
				_draw_item_icon(item_id, cell.position + Vector2(24.0, 26.0), 1.12 if selected else 1.0)
			if _hover_cell == index:
				draw_rect(cell, Color(COL_GOLD, 0.85), false, 1.6)
	var footer_y: float = panel.end.y - 52.0
	draw_line(Vector2(panel.position.x + BACKPACK_PAD, footer_y - 15.0), Vector2(panel.end.x - BACKPACK_PAD, footer_y - 15.0), COL_BORDER, 1.0)
	var label: String = ""
	if not _held_item.is_empty():
		label = "%s · 拿在手上" % _item_name(_held_item)
	elif _hover_cell.x >= 0:
		var hovered: String = player.slot_item(_hover_cell.x, _hover_cell.y)
		label = _item_name(hovered) if not hovered.is_empty() else "空格子"
	_text(Vector2(panel.position.x + BACKPACK_PAD, footer_y), label, 15, COL_GOLD if not _held_item.is_empty() else COL_TEXT)
	_draw_equipment(player)
	_draw_loot(player)
	if not _held_item.is_empty():
		_draw_item_icon(_held_item, _virtual_mouse(), 1.15)


# === 钓鱼竿 / 鱼 / 鳞片图标（矢量绘制，不使用 emoji） ===
func _draw_rod_icon(center: Vector2, icon_scale: float) -> void:
	var s: float = icon_scale
	var tip: Vector2 = center + Vector2(-13, -14) * s
	var grip: Vector2 = center + Vector2(9, 13) * s
	draw_line(grip, tip, Color(0.62, 0.48, 0.34), 3.0 * s)
	draw_line(grip, tip, Color(0.82, 0.68, 0.46), 1.2 * s)
	# 握把
	draw_line(center + Vector2(7, 9) * s, center + Vector2(12, 15) * s, Color(0.40, 0.30, 0.22), 5.0 * s)
	# 线轮
	draw_circle(center + Vector2(4, 4) * s, 3.6 * s, Color(0.94, 0.81, 0.56, 0.9))
	draw_circle(center + Vector2(4, 4) * s, 1.6 * s, Color(0.22, 0.19, 0.28))
	# 垂下的鱼线
	var line_start: Vector2 = center + Vector2(-13, -14) * s
	draw_line(line_start, line_start + Vector2(4, 12) * s, Color(0.86, 0.88, 0.90, 0.75), 1.0)
	draw_circle(line_start + Vector2(4, 13) * s, 1.8 * s, Color(0.86, 0.48, 0.40))


func _draw_fish_icon(center: Vector2, icon_scale: float, color: Color) -> void:
	var s: float = icon_scale
	var body: Vector2 = center + Vector2(2, 0) * s
	draw_colored_polygon(PackedVector2Array([
		body + Vector2(-11, 0) * s, body + Vector2(-3, -6) * s,
		body + Vector2(9, -4) * s, body + Vector2(11, 0) * s,
		body + Vector2(9, 4) * s, body + Vector2(-3, 6) * s,
	]), color)
	draw_colored_polygon(PackedVector2Array([
		body + Vector2(-11, 0) * s, body + Vector2(-17, -6) * s, body + Vector2(-17, 6) * s,
	]), Color(color, 0.75))
	draw_circle(body + Vector2(6, -1) * s, 1.3 * s, Color(0.10, 0.13, 0.18))


func _draw_scale_icon(center: Vector2, icon_scale: float) -> void:
	var s: float = icon_scale
	var base: Vector2 = center + Vector2(0, 2) * s
	for i: int in range(3):
		draw_arc(base + Vector2(0, -5.0 * s * float(i)), 9.0 * s - float(i) * 1.4 * s, PI * 0.08, PI * 0.92, 14, Color(0.86, 0.72, 0.48) if i == 0 else Color(0.74, 0.80, 0.76), 1.6 * s)


# === 钓鱼状态面板（左下，仅钓鱼试炼） ===
func _draw_fishing_panel(player: CharacterBody3D) -> void:
	if arena.mode != 4 or arena.fishing == null or player.menu_open:
		return
	var panel: Rect2 = Rect2(28, 518, 320, 84)
	_glass(panel)
	var title: String = "钓鱼"
	var state_name: String = ["待机", "抛竿中", "等待咬钩", "咬钩了", "收获中"][int(arena.fishing.state)]
	_text(Vector2(44, 541), title, 13, COL_TEXT_DIM)
	var right: String = state_name
	var right_w: float = _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(Vector2(332 - right_w, 541), right, 14, COL_GOLD if int(arena.fishing.state) == 3 else COL_TEXT)
	var hint: String = ""
	var bar_ratio: float = -1.0
	var bar_color: Color = COL_GOLD
	match int(arena.fishing.state):
		0:
			hint = "装备 2 号位鱼竿，左键抛竿；瞄准 2–12 米水面" if not player.equipped_water_tool() else "左键抛竿 · 瞄准前方 2–12 米水面"
		1:
			hint = "抛竿中…"
			bar_ratio = arena.fishing.cast_progress()
		2:
			hint = "等待咬钩（随机 %0.1f 秒均值）· 左键提前收竿" % arena.fishing.expected_bite_seconds()
			bar_ratio = clampf(float(arena.fishing.counter()) / float(arena.fishing.config.get("catch_counter", 660)), 0.0, 1.0)
			bar_color = COL_TEXT_FAINT
		3:
			hint = "左键收竿！剩余 %0.2f 秒" % arena.fishing.bite_window_left()
			bar_ratio = clampf(arena.fishing.bite_window_left() / 2.2, 0.0, 1.0)
			bar_color = COL_DANGER
		4:
			hint = "揭晓…"
			bar_ratio = arena.fishing.reveal_progress()
	if arena.fishing.encounter_active:
		hint = "异兽在场，先处理它再继续垂钓"
		bar_ratio = -1.0
	_text(Vector2(44, 560), hint, 11, COL_TEXT_DIM if int(arena.fishing.state) != 3 else COL_GOLD)
	if bar_ratio >= 0.0:
		draw_rect(Rect2(44, 568, 288, 4), COL_TRACK, true)
		draw_rect(Rect2(44, 568, 288 * clampf(bar_ratio, 0.0, 1.0), 4), bar_color, true)
	var test_line: String = "F7 下一次有效收获 = 鱼 · F8 = 异兽"
	if int(arena.fishing.force) == 1:
		test_line = "开发测试：下一次有效收获 = 鱼"
	elif int(arena.fishing.force) == 2:
		test_line = "开发测试：下一次有效收获 = 异兽"
	_text(Vector2(44, 590), test_line, 10, COL_TEXT_FAINT)


# === 渔获与材料（背包下方，数量来自 Inventory，唯一数据源） ===
## 3 列 × 5 行 = 15 格，与储物格数量一致。格子比武器格宽，因为这里要同时放
## 图标、名字和数量三种信息（48 px 的武器格塞不下四种字）。
const LOOT_COLUMNS: int = 3
const LOOT_ROWS: int = 5
const LOOT_CELL_W: float = 90.0
const LOOT_CELL_H: float = 36.0
const LOOT_CELL_GAP: float = 6.0
const LOOT_PANEL_Y: float = 330.0
const LOOT_HEADER: float = 26.0
const LOOT_FOOTER: float = 22.0
var _loot_hover: int = -1
## 渔获格不能搬动，只用来查看；点一下保持选中，名称与用途常驻在页脚。
var _loot_selected: int = -1


func _loot_panel_rect() -> Rect2:
	var grid_height: float = LOOT_ROWS * LOOT_CELL_H + (LOOT_ROWS - 1) * LOOT_CELL_GAP
	return Rect2(28, LOOT_PANEL_Y, 320, LOOT_HEADER + grid_height + LOOT_FOOTER)


func _loot_cell(index: int) -> Rect2:
	var panel: Rect2 = _loot_panel_rect()
	var origin: Vector2 = panel.position + Vector2(BACKPACK_PAD, LOOT_HEADER)
	var step: Vector2 = Vector2(LOOT_CELL_W, LOOT_CELL_H) + Vector2.ONE * LOOT_CELL_GAP
	return Rect2(origin + Vector2(index % LOOT_COLUMNS, int(index / float(LOOT_COLUMNS))) * step, Vector2(LOOT_CELL_W, LOOT_CELL_H))


func _loot_cell_at(point: Vector2) -> int:
	if not _loot_panel_rect().has_point(point):
		return -1
	for index: int in range(LOOT_COLUMNS * LOOT_ROWS):
		if _loot_cell(index).has_point(point):
			return index
	return -1


func _draw_loot(player: CharacterBody3D) -> void:
	if arena.loot == null:
		return
	var panel: Rect2 = _loot_panel_rect()
	_glass(panel)
	_text(panel.position + Vector2(BACKPACK_PAD, 18), "渔获与材料", 13, COL_TEXT_DIM)
	# 格位数量来自绑定的 Inventory（鱼与材料没有独立的背包节点）。
	var slot_total: int = arena.loot.inventory.slot_count if arena.loot.inventory != null else 0
	var used: String = "%d/%d 格 · 共 %d 件" % [arena.loot.used_slots(), slot_total, arena.loot.total_items()]
	if arena.loot.is_full():
		used = "格位已满 · 共 %d 件" % arena.loot.total_items()
	var used_w: float = _font.get_string_size(used, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_text(Vector2(panel.end.x - BACKPACK_PAD - used_w, panel.position.y + 18), used, 11, COL_GOLD if arena.loot.is_full() else COL_TEXT_FAINT)
	var any: bool = false
	for index: int in range(LOOT_COLUMNS * LOOT_ROWS):
		var cell: Rect2 = _loot_cell(index)
		var item_id: String = _loot_item_id(index)
		var selected: bool = _loot_selected == index
		_slot_cell(cell, selected)
		if item_id.is_empty():
			continue
		any = true
		var current: int = arena.loot.count(item_id)
		var capped: bool = current >= arena.loot.stack_limit
		_draw_item_icon(item_id, cell.position + Vector2(16.0, 18.0), 0.68)
		# 图标右侧竖排：名字在上、数量在下，鱼与材料的名字都能完整显示。
		_text(Vector2(cell.position.x + 30.0, cell.position.y + 15.0), _item_name(item_id), 10, COL_GOLD if capped else COL_TEXT)
		_text(Vector2(cell.position.x + 30.0, cell.position.y + 30.0), "×%d" % current, 10, COL_GOLD if capped else COL_TEXT_DIM)
		if _loot_hover == index or selected:
			draw_rect(cell, Color(COL_GOLD, 0.85), false, 1.6)
	var footer_id: String = ""
	var focus: int = _loot_selected if _loot_selected >= 0 else _loot_hover
	if focus >= 0:
		footer_id = _loot_item_id(focus)
	var hint: String = ""
	if not footer_id.is_empty():
		hint = "%s · %s" % [_item_name(footer_id), _loot_material_hint(footer_id)]
		if arena.loot.count(footer_id) >= arena.loot.stack_limit:
			hint = "堆叠已满 · " + hint
	# 注意用绝对坐标：panel.position.y + 高度，不能把 end.y 当成相对偏移再叠一次。
	_text(Vector2(panel.position.x + BACKPACK_PAD, panel.end.y - 8.0), hint, 11, COL_TEXT if not footer_id.is_empty() else COL_TEXT_FAINT)


## 某一格里的物品 id。格位与顺序都来自绑定的 Inventory，界面不另存一份。
func _loot_item_id(index: int) -> String:
	if arena.loot == null or arena.loot.inventory == null:
		return ""
	var slots: Array = arena.loot.inventory.slots
	if index < 0 or index >= slots.size():
		return ""
	return str(slots[index])


## 渔获的物品说明统一从数据文件读，不在界面里写死数值。
## 普通鱼只说明后续可加工用途，本轮不在这里发放加工材料。
func _loot_material_hint(item_id: String) -> String:
	var fish: Dictionary = GameData.get_fish(item_id)
	if not fish.is_empty():
		var drops: Array = fish.get("drops", [])
		var names: Array[String] = []
		for drop_id: String in drops:
			names.append(GameData.get_item_name(String(drop_id)))
		return "可加工为 " + "、".join(names) if not names.is_empty() else "渔获"
	var item: Dictionary = GameData.get_item(item_id)
	if not item.is_empty():
		return str(item.get("description", item_id))
	return item_id


# === 非阻塞提示（下方居中，2.6 秒淡出） ===
func _draw_messages() -> void:
	if _messages.is_empty():
		return
	var base_y: float = 660.0 - float(_messages.size() - 1) * 24.0
	for index: int in range(_messages.size()):
		var entry: Dictionary = _messages[index]
		var age: float = entry.age
		var text: String = str(entry.text)
		var alpha: float = clampf((2.6 - age) / 0.6, 0.0, 1.0)
		var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var point: Vector2 = Vector2(640.0 - width * 0.5, base_y + float(index) * 24.0)
		draw_rect(Rect2(point.x - 12.0, point.y - 15.0, width + 24.0, 22.0), Color(COL_PANEL, 0.62 * alpha))
		_text(point, text, 15, Color(COL_TEXT, alpha))


# === 装备栏（泰拉瑞亚式：护甲 3 格 + 饰品 5 格，竖列排在背包右侧） ===
const EQUIP_CELL: float = 36.0
const EQUIP_GAP: float = 6.0
## 装备栏贴屏幕右边缘（1280 画布内，留 28 px 边距，与左侧背包的边距一致）。
const EQUIP_PANEL_X: float = 1178.0
const EQUIP_PANEL_Y: float = 26.0
const EQUIP_PANEL_W: float = 74.0
const EQUIP_HEADER: float = 40.0
const EQUIP_DIVIDER: float = 14.0
const EQUIP_LABEL_H: float = 22.0
const EQUIP_FOOTER: float = 16.0


func _equipment_panel_rect() -> Rect2:
	var armor_h: float = 3.0 * EQUIP_CELL + 2.0 * EQUIP_GAP
	var accessory_h: float = 5.0 * EQUIP_CELL + 4.0 * EQUIP_GAP
	var height: float = EQUIP_HEADER + armor_h + EQUIP_DIVIDER + EQUIP_LABEL_H + accessory_h + EQUIP_FOOTER
	return Rect2(EQUIP_PANEL_X, EQUIP_PANEL_Y, EQUIP_PANEL_W, height)


func _equipment_cell(row: int, column: int) -> Rect2:
	var panel: Rect2 = _equipment_panel_rect()
	var armor_h: float = 3.0 * EQUIP_CELL + 2.0 * EQUIP_GAP
	var top: float = panel.position.y + EQUIP_HEADER
	if row == 5:
		top += armor_h + EQUIP_DIVIDER + EQUIP_LABEL_H
	return Rect2(Vector2(panel.position.x + 19.0, top + float(column) * (EQUIP_CELL + EQUIP_GAP)), Vector2(EQUIP_CELL, EQUIP_CELL))


func _draw_equipment(player: CharacterBody3D) -> void:
	var panel: Rect2 = _equipment_panel_rect()
	_glass(panel)
	_text(panel.position + Vector2(19.0, 20.0), "装备", 12, COL_TEXT_DIM)
	var hints: Array[String] = ["头", "身", "腿"]
	for i: int in range(3):
		_draw_equipment_slot(player, 4, i, hints[i])
	var armor_h: float = 3.0 * EQUIP_CELL + 2.0 * EQUIP_GAP
	var divider_y: float = panel.position.y + EQUIP_HEADER + armor_h + 7.0
	draw_line(Vector2(panel.position.x + 12.0, divider_y), Vector2(panel.end.x - 12.0, divider_y), COL_BORDER, 1.0)
	_text(Vector2(panel.position.x + 19.0, divider_y + 16.0), "饰品", 12, COL_TEXT_DIM)
	for i: int in range(5):
		_draw_equipment_slot(player, 5, i, "")


func _draw_equipment_slot(player: CharacterBody3D, row: int, index: int, hint: String) -> void:
	var cell: Rect2 = _equipment_cell(row, index)
	var key: Vector2i = Vector2i(row, index)
	var item_id: String = player.slot_item(row, index)
	_slot_cell(cell, false)
	if item_id.is_empty():
		if not hint.is_empty():
			var width: float = _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_text(Vector2(cell.position.x + (cell.size.x - width) * 0.5, cell.position.y + 24.0), hint, 12, Color(COL_TEXT_FAINT, 0.6))
	elif key != _held_from:
		_draw_item_icon(item_id, cell.get_center(), 0.8)
	if _hover_cell == key:
		draw_rect(cell, Color(COL_GOLD, 0.85), false, 1.6)


# === 背包鼠标交互 ===
## 用事件自带的坐标换算，而不是 get_local_mouse_position()：
## 鼠标被捕获/窗口未聚焦时，后者会和实际点击位置对不上。
func _virtual_mouse() -> Vector2:
	return _to_canvas(_mouse_position)


func _to_canvas(screen_point: Vector2) -> Vector2:
	var scale_factor: float = minf(size.x / 1280.0, size.y / 720.0)
	var offset: Vector2 = (size - Vector2(1280.0, 720.0) * scale_factor) * 0.5
	return (screen_point - global_position - offset) / maxf(scale_factor, 0.001)


func _cell_at(point: Vector2) -> Vector2i:
	if _equipment_panel_rect().has_point(point):
		for i: int in range(3):
			if _equipment_cell(4, i).has_point(point):
				return Vector2i(4, i)
		for i: int in range(5):
			if _equipment_cell(5, i).has_point(point):
				return Vector2i(5, i)
		return Vector2i(-1, -1)
	if not _backpack_rect().has_point(point):
		return Vector2i(-1, -1)
	for row: int in range(BACKPACK_ROWS):
		for column: int in range(BACKPACK_COLUMNS):
			if _backpack_cell(row, column).has_point(point):
				return Vector2i(row, column)
	return Vector2i(-1, -1)


func _input(event: InputEvent) -> void:
	if arena == null or arena.player == null or not arena.player.menu_open:
		return
	if event is InputEventMouseMotion:
		_mouse_position = (event as InputEventMouseMotion).position
		_hover_cell = _cell_at(_to_canvas(_mouse_position))
		_loot_hover = _loot_cell_at(_to_canvas(_mouse_position))
		return
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if not button.pressed:
		return
	_mouse_position = button.position
	_hover_cell = _cell_at(_to_canvas(_mouse_position))
	_loot_hover = _loot_cell_at(_to_canvas(_mouse_position))
	if button.button_index == MOUSE_BUTTON_LEFT:
		# 渔获格只读：点它只切换页脚详情，不能把鱼当成武器拿起来，
		# 也不应该因为点在这里而把手上搬着的武器扔掉。
		if _loot_hover >= 0:
			var loot_id: String = _loot_item_id(_loot_hover)
			_loot_selected = _loot_hover if not loot_id.is_empty() else -1
			get_viewport().set_input_as_handled()
			return
		_click_cell(_hover_cell)
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		if _loot_hover >= 0:
			_loot_selected = -1
			get_viewport().set_input_as_handled()
			return
		_drop_held()
		get_viewport().set_input_as_handled()


## 点一次拿起、再点一次放下；目标格原有物品与来源格交换，关闭背包时不会丢东西。
func _click_cell(cell: Vector2i) -> void:
	var player: CharacterBody3D = arena.player
	if cell.x < 0:
		_drop_held()
		return
	if _held_item.is_empty():
		var item_id: String = player.slot_item(cell.x, cell.y)
		if item_id.is_empty():
			return
		_held_item = item_id
		_held_from = cell
		return
	if cell == _held_from:
		_drop_held()
		return
	var target: String = player.slot_item(cell.x, cell.y)
	player.set_slot_item(cell.x, cell.y, _held_item)
	player.set_slot_item(_held_from.x, _held_from.y, target)
	_held_item = ""
	_held_from = Vector2i(-1, -1)


func _drop_held() -> void:
	_held_item = ""
	_held_from = Vector2i(-1, -1)


func _on_health_changed(_value: int) -> void:
	if arena.player.hurt_time_left > 0.0:
		_hurt_flash = 0.24
		# 坠落伤害只闪红，不画方向箭头：它没有攻击来源。
		if not arena.player.last_damage_was_fall:
			# (Claude Code) Fallback: if the direction signal was missed, guess "from the side"
			# instead of leaving the cue blank.
			_damage_fade = maxf(_damage_fade, 1.0)


## (Claude Code) Direction comes from first_person_player.receive_damage.
## x = right component, y = forward component of the attacker in view space,
## so (0, 1) means "in front", (-1, 0) means "on your left".
func _on_hurt_direction(direction: Vector2) -> void:
	_damage_dir = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	_damage_fade = 1.0
