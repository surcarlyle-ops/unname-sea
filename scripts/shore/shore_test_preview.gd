extends Node3D
## 岸边钓鱼测试区独立预览入口（CodeBuddyPro，2026-10-28）。
##
## 场地本体在 res://scenes/tests/shore_test_area.tscn（可被主场景单独实例化）；
## 本场景只负责：环境光、一个第一人称玩家、调试 HUD，以及一份钓鱼状态机，
## 让测试区能单独跑起来验证水面、钓点和岸边短战斗。
## 不改 combat_arena / first_person_player / first_person_hands / combat_hud。

const AREA_SCENE: PackedScene = preload("res://scenes/tests/shore_test_area.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/mvp/first_person_player.tscn")
const FISHING_SCRIPT: Script = preload("res://scripts/mvp/fishing_mvp.gd")
const PRESENTATION_SCRIPT: Script = preload("res://scripts/mvp/fishing_presentation.gd")
const ENEMY_SCRIPT: Script = preload("res://scripts/mvp/melee_enemy.gd")
const FISHING_CONFIG_PATH: String = "res://data/fishing_mvp.json"
const COMBAT_CONFIG_PATH: String = "res://data/combat_mvp.json"

var area: Node3D
var player: CharacterBody3D
var fishing: Node
var fishing_fx: Node3D
var enemies: Node3D
var fishing_config: Dictionary = {}

var _enemy_tuning: Dictionary = {}
var _encounter_enemy: CharacterBody3D
var _notice_label: Label
var _notice_time: float = 0.0
var _cast_label: Label
var _pos_label: Label
var _marker: MeshInstance3D
var _spawn_markers_visible: bool = false


func _ready() -> void:
	fishing_config = _load_json(FISHING_CONFIG_PATH)
	_build_environment()
	area = AREA_SCENE.instantiate()
	area.name = "ShoreTestArea"
	add_child(area)
	# 钓鱼逻辑（FishingMVP.resolve_cast）按 arena.pond_min/pond_max/water_level 判定落点，
	# 这里换成测试区自己的水域边界，其他参数仍用 data/fishing_mvp.json。
	fishing_config["arena"] = area.fishing_arena_config()
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = area.player_spawn_point()
	add_child(player)
	player.retry_requested.connect(_on_retry)
	player.loadout_requested.connect(_toggle_controls)
	player.notice_requested.connect(show_notice)
	player.water_tool_used.connect(_on_water_tool)
	player.loadout_changing.connect(_on_loadout_changing)
	player.grapple_requested.connect(_on_grapple_requested)
	player.reset_applied.connect(_on_player_reset)
	player.died.connect(func() -> void: show_notice("已倒下 · R 回到出生点"))
	fishing = FISHING_SCRIPT.new()
	fishing.name = "FishingMVP"
	fishing.config = fishing_config
	add_child(fishing)
	_wire_fishing()
	fishing_fx = PRESENTATION_SCRIPT.new() as Node3D
	fishing_fx.name = "FishingPresentation"
	fishing_fx.fishing = fishing
	fishing_fx.player = player
	fishing_fx.water_level = area.water_level()
	add_child(fishing_fx)
	enemies = Node3D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	_build_marker()
	_build_hud()
	_grant_rod()
	show_notice("岸边测试区：2 号位鱼竿，左键抛竿（2–12 米）· M 出生点 / N 试放异兽 / X 清空 / R 回出生点")


func _process(delta: float) -> void:
	_notice_time = maxf(0.0, _notice_time - delta)
	if _notice_label != null:
		_notice_label.visible = _notice_time > 0.0
	if fishing == null or player == null or area == null:
		return
	fishing.rod_tip_position = fishing_fx.rod_tip()
	fishing.check_distance(player.global_position)
	_update_cast_preview()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: InputEventKey = event as InputEventKey
	# 调试键不用 F1–F3：键盘没有功能键，改成 M / N / X。
	if key.physical_keycode == KEY_M:
		_spawn_markers_visible = not _spawn_markers_visible
		area.set_spawn_markers_visible(_spawn_markers_visible)
		show_notice("出生点标记：%s" % ("显示" if _spawn_markers_visible else "隐藏"))
	elif key.physical_keycode == KEY_N:
		_spawn_test_enemy()
	elif key.physical_keycode == KEY_X:
		_clear_enemies()
		show_notice("已清空测试异兽")


# === 钓鱼 ===

func _wire_fishing() -> void:
	fishing.notice_requested.connect(show_notice)
	fishing.bite_started.connect(func() -> void: player.add_shake(0.006))
	fishing.bite_missed.connect(func() -> void: show_notice("错过了咬钩，鱼漂仍在水中"))
	fishing.result_revealed.connect(_on_result_revealed)
	fishing.encounter_requested.connect(_on_fishing_encounter)
	fishing.auto_reeled.connect(func(distance: float) -> void: show_notice("离鱼漂 %.1f 米，自动收竿" % distance))


func _grant_rod() -> void:
	if player.quick_slots.has("fishing_rod"):
		player.selected_slot = player.quick_slots.find("fishing_rod")
		player._refresh_weapon()
		return
	if player.quick_slots[1].is_empty():
		player.assign_quick_slot(1, "fishing_rod")
		player.selected_slot = 1
		player._refresh_weapon()


func _on_water_tool() -> void:
	if player.dead or not player.controls_active or fishing == null:
		return
	if fishing.encounter_active:
		show_notice("先处理异兽，再继续垂钓")
		return
	match int(fishing.state):
		2:  # WAITING：提前收竿
			fishing.cancel_waiting()
		3:  # BITING：窗口内收竿
			fishing.reel_bite()
		_:
			_cast_line()


func _cast_line() -> void:
	if not player.equipped_water_tool():
		return
	var result: Dictionary = fishing.resolve_cast(player.camera.global_position, -player.camera.global_basis.z)
	if result.has("reason"):
		show_notice(str(result.reason))
		return
	fishing.begin_cast(fishing_fx.rod_tip(), result.point as Vector3)


func _on_result_revealed(outcome: String, item_id: String, _monster_id: String) -> void:
	if not is_instance_valid(fishing_fx):
		return
	if outcome == "fish":
		fishing_fx.spawn_ripple(1.3, 0.5)
		show_notice("钓到 %s" % _item_name(item_id))
	else:
		fishing_fx.spawn_ripple(2.6, 1.2)


func _on_fishing_encounter(_monster_id: String, _reward_item: String, _reward_count: int) -> void:
	if _encounter_enemy != null and is_instance_valid(_encounter_enemy):
		_refuse_encounter("已经有一只异兽在场")
		return
	var spot: Vector3 = area.pick_encounter_spawn(player.global_position, area.encounter_min_distance())
	if spot == Vector3.INF:
		_refuse_encounter("岸边没有合适的出现点")
		return
	fishing.keep_encounter()
	_encounter_enemy = _spawn_enemy(spot, "钓上来的异兽")
	fishing.encounter_active = true
	player.switch_to_combat_weapon()
	show_notice("钓到异兽！已切回战斗武器 · 出现点距玩家 %.1f 米" % _flat_distance(spot, player.global_position))


func _refuse_encounter(message: String) -> void:
	fishing.refuse_encounter(message)
	show_notice("%s，按普通渔获结算" % message)


# === 岸边短战斗 ===

func _spawn_test_enemy() -> void:
	var spot: Vector3 = area.pick_encounter_spawn(player.global_position, area.encounter_min_distance())
	if spot == Vector3.INF:
		show_notice("岸边没有距玩家 5 米以上的合法出现点")
		return
	_spawn_enemy(spot, "测试异兽")
	show_notice("测试异兽已放在距玩家 %.1f 米处" % _flat_distance(spot, player.global_position))


func _spawn_enemy(spot: Vector3, tag: String) -> CharacterBody3D:
	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.name = "ShoreTestEnemy"
	enemy.set_script(ENEMY_SCRIPT)
	enemy.target = player
	enemy.tuning = _tuning()
	enemy.stats = GameData.get_monster("mon_silence")
	enemy.position = spot
	enemy.defeated.connect(_on_enemy_defeated)
	enemies.add_child(enemy)
	if not tag.is_empty():
		var label: Label3D = Label3D.new()
		label.text = tag
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 26
		label.pixel_size = 0.006
		label.outline_size = 6
		label.modulate = Color("e6b06b")
		label.position.y = 1.75
		enemy.add_child(label)
	return enemy


func _on_enemy_defeated(defeated: Node3D) -> void:
	if defeated == _encounter_enemy:
		_encounter_enemy = null
		fishing.encounter_active = false
		fishing.reset_encounter()
		show_notice("异兽已击败 · 可以继续垂钓")
	else:
		show_notice("测试异兽已击败")


func _clear_enemies() -> void:
	if is_instance_valid(_encounter_enemy):
		fishing.encounter_active = false
		fishing.reset_encounter()
	_encounter_enemy = null
	for child: Node in enemies.get_children():
		enemies.remove_child(child)
		child.queue_free()


func _tuning() -> Dictionary:
	if _enemy_tuning.is_empty():
		var combat: Dictionary = _load_json(COMBAT_CONFIG_PATH)
		_enemy_tuning = (combat.get("enemy", {}) as Dictionary).duplicate(true)
	return _enemy_tuning


# === 调试 HUD ===

func _update_cast_preview() -> void:
	var eye: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z
	var result: Dictionary = fishing.resolve_cast(eye, forward)
	if result.has("reason"):
		_marker.visible = false
		_cast_label.text = "抛竿：%s" % str(result.reason)
		_cast_label.add_theme_color_override("font_color", Color("d5dfd8"))
	else:
		var point: Vector3 = result.point as Vector3
		var distance: float = Vector2(point.x - eye.x, point.z - eye.z).length()
		_marker.visible = true
		_marker.global_position = Vector3(point.x, area.water_level() + 0.02, point.z)
		_cast_label.text = "落点 %.1f 米 · 有效（2–12 米）" % distance
		_cast_label.add_theme_color_override("font_color", Color("a8d9a0"))
	_pos_label.text = "位置 (%.1f, %.1f) · 距钓点 %.1f 米" % [
		player.global_position.x,
		player.global_position.z,
		_flat_distance(player.global_position, area.fishing_spot())]


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = "CastPreview"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.40
	torus.rings = 40
	torus.ring_segments = 6
	_marker.mesh = torus
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.95, 0.85, 0.60, 0.75)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker.material_override = material
	_marker.visible = false
	add_child(_marker)


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var root: Control = Control.new()
	root.name = "Screen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme.default_font = font
	theme.default_font_size = 15
	root.theme = theme
	layer.add_child(root)
	var top: VBoxContainer = _panel(root, Vector2(26, 22), Vector2(408, 178))
	_label(top, "未名之海 · 岸边测试区", 23, Color("f4ebcf"))
	_label(top, "钓鱼 2–12 米 · 岸边短战斗", 14, Color("b4cbc8"))
	var bounds: Rect2 = area.water_bounds()
	_label(top, "水域 x %.0f…%.0f / z %.0f…%.0f · 水面 y %.2f" % [
		bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y, area.water_level()], 13, Color("d5dfd8"))
	_cast_label = _label(top, "", 14, Color("f4ebcf"))
	_pos_label = _label(top, "", 13, Color("d5dfd8"))
	var bottom: VBoxContainer = _panel(root, Vector2.ZERO, Vector2(660, 92))
	var bottom_panel: Control = bottom.get_parent().get_parent() as Control
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_panel.offset_left = 26
	bottom_panel.offset_right = 686
	bottom_panel.offset_top = -122
	bottom_panel.offset_bottom = -30
	_label(bottom, "WASD 移动    Shift 走    空格 跳    Ctrl 蹲/滑铲    右键 钩爪", 15, Color("f4ebcf"))
	_label(bottom, "左键 抛竿 / 收竿    R 回出生点    M 出生点    N 试放异兽    X 清空", 14, Color("c3d2ce"))
	_label(bottom, "Esc / Tab 释放鼠标    点击画面继续", 14, Color("c3d2ce"))
	_notice_label = Label.new()
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_color_override("font_color", Color("fff1c5"))
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.visible = false
	root.add_child(_notice_label)
	_notice_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_notice_label.offset_left = -330
	_notice_label.offset_right = 330
	_notice_label.offset_top = -176
	_notice_label.offset_bottom = -140
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


func show_notice(message: String) -> void:
	if _notice_label == null:
		return
	_notice_label.text = message
	_notice_label.visible = true
	_notice_time = 4.0


func _panel(parent: Control, point: Vector2, panel_size: Vector2) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = point
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.18, 0.20, 0.90)
	box.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", box)
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	return content


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


# === 玩家回调与环境 ===

func _on_retry() -> void:
	_clear_enemies()
	fishing.cancel_silent("reset")
	player.reset_to_spawn()
	show_notice("已回到出生点")


func _on_player_reset() -> void:
	fishing.cancel_silent("reset")


func _on_loadout_changing() -> void:
	fishing.cancel_silent("switch")


func _on_grapple_requested() -> void:
	fishing.cancel_silent("grapple")


func _toggle_controls() -> void:
	if player.controls_active:
		player.set_controls_active(false)
		show_notice("鼠标已释放 · 点击画面继续")
	else:
		player.set_controls_active(true)


func _build_environment() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.name = "Environment"
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	# 概念图配色：偏青的天空 + 暖奶油地平线 + 草绿地面反照（原来是薰衣草紫）。
	sky_material.sky_top_color = Color(0.30, 0.58, 0.75)
	sky_material.sky_horizon_color = Color(0.97, 0.90, 0.75)
	sky_material.ground_horizon_color = Color(0.60, 0.72, 0.55)
	sky_material.ground_bottom_color = Color(0.28, 0.39, 0.28)
	sky_material.sun_angle_max = 18.0
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.55
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	# 草与浅滩都比原来的沙地更亮，曝光提到 0.95 才不会把绿色压灰。
	settings.tonemap_exposure = 0.90
	# 雾改成淡淡的草绿，远岭才会像概念图那样一层层淡进天光。
	settings.fog_enabled = true
	settings.fog_light_color = Color(0.82, 0.88, 0.82)
	settings.fog_light_energy = 0.55
	settings.fog_density = 0.0085
	settings.fog_aerial_perspective = 0.62
	# 0.5 会把整片天刷成米白，压到 0.28 才留得住概念图那种偏青的天。
	settings.fog_sky_affect = 0.28
	environment.environment = settings
	add_child(environment)
	# 高一点的暖阳：谷底与草梢都能吃到光，阴影又不至于拉得太长。
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-28.0, -50.0, 0.0)
	sun.light_color = Color(1.0, 0.90, 0.74)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# 冷色补光：让阴影偏蓝紫而不是死黑，贴近概念图的柔和对比。
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-34.0, 128.0, 0.0)
	fill.light_color = Color(0.66, 0.72, 0.92)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(fill)


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("配置读取失败：%s" % path)
	return {}


func _item_name(item_id: String) -> String:
	var fish: Dictionary = GameData.get_fish(item_id)
	if not fish.is_empty():
		return str(fish.get("name", item_id))
	return GameData.get_item_name(item_id)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
