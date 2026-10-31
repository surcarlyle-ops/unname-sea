extends Node3D
## A repeatable combat slice, separate from the legacy shore and fishing prototype.

const PLAYER_SCENE: PackedScene = preload("res://scenes/mvp/first_person_player.tscn")
const ENEMY_SCRIPT: Script = preload("res://scripts/mvp/melee_enemy.gd")
const GUARDIAN_SCRIPT: Script = preload("res://scripts/enemies/ruin_guardian_combat.gd")
const HUD_SCRIPT: Script = preload("res://scripts/mvp/combat_hud.gd")
const COURSE_SCRIPT: Script = preload("res://scripts/mvp/movement_course.gd")
const TREE_SCRIPT: Script = preload("res://scripts/mvp/imported_tree.gd")
const RUINS_PATH: String = "res://assets/environments/portal_ruins/portal_ruins_sample.glb"
## 钓鱼 MVP（CodeBuddy 2026-10-28）：逻辑、战利品、表现、拾取各自独立，互不引用手部脚本。
const FISHING_SCRIPT: Script = preload("res://scripts/mvp/fishing_mvp.gd")
const LOOT_SCRIPT: Script = preload("res://scripts/mvp/fishing_loot.gd")
const FISHING_PRESENTATION_SCRIPT: Script = preload("res://scripts/mvp/fishing_presentation.gd")
const PICKUP_SCRIPT: Script = preload("res://scripts/mvp/loot_drop.gd")
const SHORE_SCENE: PackedScene = preload("res://scenes/tests/shore_test_area.tscn")

@export var initial_mode: int = 3

const FISHING_CONFIG_PATH: String = "res://data/fishing_mvp.json"
## 遗迹偏移：已按地形扫描反算，让最平坦的草地正好落在训练场原点。
## 原偏移 (20,110,-640) 下平坦区在世界 (4,36.5,-162)，故新偏移 = 旧偏移 - 该点 + (0,1,0)。
const RUINS_OFFSET: Vector3 = Vector3(16.0, 72.5, -478.0)

var player: CharacterBody3D
var hud: Control
var enemies: Node3D
var tuning: Dictionary
var course: Node3D
var mode: int = 0
var defeated_count: int = 0
var round_total: int = 0
var round_complete: bool = false
var notice: String = ""
var notice_time: float = 0.0
var _sounds: Dictionary = {}
var _audio: Array[AudioStreamPlayer] = []
var _audio_index: int = 0
var play_menu: CanvasLayer
var guardian: CharacterBody3D
var feedback_config: Dictionary
var fishing_config: Dictionary
var fishing: Node
var loot: Node
var shore_area: Node3D
var fishing_fx: Node3D
var encounter_enemy: CharacterBody3D
var pickups: Array[Node3D] = []
var fishing_notice: String = ""
var fishing_notice_time: float = 0.0
var rod_granted: bool = false
var _encounter_pending: Dictionary = {}
var _enemy_tuning: Dictionary = {}


func _ready() -> void:
	tuning = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_mvp.json")) as Dictionary
	feedback_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/fishing_feedback.json")) as Dictionary
	_setup_pickup_action()
	fishing_config = JSON.parse_string(FileAccess.get_file_as_string(FISHING_CONFIG_PATH)) as Dictionary
	if fishing_config == null:
		fishing_config = {}
	_build_world()
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = _vector(tuning.arena.spawn)
	add_child(player)
	player.retry_requested.connect(restart_round)
	player.loadout_requested.connect(_toggle_loadout)
	player.notice_requested.connect(show_notice)
	player.attack_started.connect(func() -> void: _sound("swing"))
	player.melee_hit.connect(func(_target: Node3D) -> void: _sound("hit"))
	player.movement_sound.connect(func(sound_name: String, strength: float) -> void: _sound(sound_name, strength))
	player.wave_released.connect(func() -> void: _sound("wave"))
	player.health_changed.connect(func(_value: int) -> void:
		if player.hurt_time_left > 0.0:
			_sound("hurt")
	)
	enemies = Node3D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(HUD_SCRIPT)
	hud.arena = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	_build_audio()
	loot = LOOT_SCRIPT.new()
	loot.name = "FishingLoot"
	loot.bind(player.inventory)  ## 绑定到玩家的通用库存
	add_child(loot)
	fishing = FISHING_SCRIPT.new()
	fishing.name = "FishingMVP"
	fishing.config = fishing_config
	add_child(fishing)
	_wire_fishing()
	play_menu = load("res://scripts/ui/play_pause_menu.gd").new()
	play_menu.name = "PlayMenu"
	play_menu.arena = self
	add_child(play_menu)
	start_round(initial_mode)
	# Give the player time to read the controls before enemies advance.
	player.set_controls_active(false)


func _process(delta: float) -> void:
	notice_time = maxf(0.0, notice_time - delta)
	fishing_notice_time = maxf(0.0, fishing_notice_time - delta)
	# 钓鱼状态机用真实帧时间推进，不受 physics_tick 设置影响；暂停时由 _toggle_loadout 冻结。
	if mode == 4 and fishing != null:
		# 菜单/失焦期间冻结咬钩计时；与引擎暂停无关，HUD 仍可绘制。
		fishing.set_paused(player.menu_open or not player.controls_active)
		fishing.rod_tip_position = fishing_fx.rod_tip() if is_instance_valid(fishing_fx) else Vector3.ZERO
		fishing.check_distance(player.global_position)
		_update_pickups(delta)


func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _audio:
		voice.stop()
		voice.stream = null
	_sounds.clear()


func _input(event: InputEvent) -> void:
	if player == null or play_menu == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if play_menu.opened:
				play_menu.close()
			elif player.menu_open:
				_toggle_loadout()
			else:
				open_play_menu()
			get_viewport().set_input_as_handled()
		elif play_menu.opened and (event.physical_keycode == KEY_TAB or (event.physical_keycode >= KEY_0 and event.physical_keycode <= KEY_Z)):
			get_viewport().set_input_as_handled()


func open_play_menu() -> void:
	play_menu.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		if not play_menu.opened and player.controls_active and not player.menu_open and not player.dead:
			_collect_nearest_pickup()
		get_viewport().set_input_as_handled()


func start_round(next_mode: int) -> void:
	hud.clear_damage_numbers()
	mode = clampi(next_mode, 0, 4)
	guardian = null
	# 切试炼：清掉未结算的钓鱼、遭遇占用与岸边掉落物（背包里的物品保留）。
	_clear_fishing_trial()
	if mode != 4:
		_remove_fishing_world()
	_clear_encounter()
	_clear_pickups()
	for old_enemy: Node in enemies.get_children():
		enemies.remove_child(old_enemy)
		old_enemy.queue_free()
	defeated_count = 0
	round_complete = false
	player.spawn_position = _vector(tuning.arena.movement_spawn if mode == 2 else tuning.arena.spawn)
	if mode == 3:
		player.spawn_position = _vector(tuning.arena.guardian_player_spawn)
	elif mode == 4:
		_ensure_fishing_world()
		if not fishing_config.has("arena"):
			push_error("fishing_mvp.json 缺少 arena 块")
		player.spawn_position = _vector(fishing_config.arena.spawn)
	player.reset_to_spawn()
	course.reset()
	hud.close_loadout()
	if mode == 4:
		# 出生点面朝水池：鱼竿开局就能直接抛竿。
		player.rotation.y = deg_to_rad(float(fishing_config.arena.get("spawn_yaw_degrees", 200.0)))
		_prepare_fishing_trial()
		return
	if mode == 3:
		round_total = 1
		guardian = CharacterBody3D.new()
		guardian.name = "RuinGuardian"
		guardian.set_script(GUARDIAN_SCRIPT)
		guardian.target = player
		guardian.tuning = tuning.guardian
		guardian.stats = GameData.get_monster(str(tuning.guardian.source_id))
		guardian.position = _vector(tuning.arena.guardian_spawn)
		guardian.defeated.connect(_on_enemy_defeated)
		guardian.damage_received.connect(hud.add_damage_number)
		enemies.add_child(guardian)
		show_notice("守卫试炼：看蓄力预告，侧移、跳跃或钩爪避开石拳，趁收招反击 · J 重开")
		return
	var positions: Array = [] if mode == 2 else (tuning.arena.swarm_spawns if mode == 0 else tuning.arena.mobility_spawns)
	round_total = positions.size()
	for point: Array in positions:
		var enemy: CharacterBody3D = CharacterBody3D.new()
		enemy.set_script(ENEMY_SCRIPT)
		enemy.target = player
		enemy.tuning = tuning.enemy
		enemy.stats = GameData.get_monster(str(tuning.enemy.source_id))
		enemy.position = _vector(point)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.damage_received.connect(hud.add_damage_number)
		enemies.add_child(enemy)
	show_notice("清怪试炼：用横扫同时命中多个敌人" if mode == 0 else ("机动试炼：钩住横梁，松钩后保留速度，再返回地面近战" if mode == 1 else "移动练习：沿左侧金色标记前进，Ctrl 滑铲、空格翻越"))


func restart_round() -> void:
	start_round(mode)


func _on_enemy_defeated(_enemy: Node3D) -> void:
	defeated_count += 1
	if defeated_count >= round_total:
		round_complete = true
		show_notice("守卫已击败！R / J 再战 · F 清怪 / G 机动 / H 移动" if mode == 3 else "试炼完成！R 再来一轮 · F 清怪 / G 机动 / H 移动 / J 守卫")


func show_notice(message: String) -> void:
	notice = message
	notice_time = 5.0
	if hud != null and hud.has_method("push_message"):
		hud.push_message(message)
	if mode == 4:
		fishing_notice = message
		fishing_notice_time = 4.0


# === 钓鱼试炼（CodeBuddy 2026-10-28） ===
## 逻辑、背包、表现、遭遇各自独立；first_person_hands.gd 只通过 fishing 的
## 公开状态与信号接入，不改这里。
func _wire_fishing() -> void:
	player.water_tool_used.connect(_on_fishing_action)
	player.loadout_changing.connect(func() -> void: fishing.cancel_silent("switch"))
	player.grapple_requested.connect(func() -> void: fishing.cancel_silent("grapple"))
	player.reset_applied.connect(func() -> void: fishing.cancel_silent("reset"))
	player.died.connect(_on_player_died_fishing)
	fishing.notice_requested.connect(show_notice)
	fishing.reel_started.connect(func(_is_fish: bool) -> void: _sound("fish_reel", 0.8))
	fishing.cast_started.connect(_on_fishing_cast)
	fishing.bite_started.connect(_on_fishing_bite)
	fishing.bite_missed.connect(_on_fishing_missed)
	fishing.cancelled.connect(_on_fishing_cancelled)
	fishing.result_revealed.connect(_on_fishing_revealed)
	fishing.encounter_requested.connect(_on_fishing_encounter)
	fishing.auto_reeled.connect(_on_fishing_auto_reeled)
	# Hands read the fishing state passively; the rod tip anchor is rebound below
	# every time the presentation layer is rebuilt.
	player.hands.bind_fishing_controller(fishing)


func _on_player_died_fishing() -> void:
	if fishing == null:
		return
	fishing.cancel_silent("death")
	_clear_encounter()
	_clear_pickups()


func _prepare_fishing_trial() -> void:
	_ensure_fishing_world()
	_ensure_rod()
	fishing.encounter_active = false
	fishing.set_paused(false)
	show_fishing_notice("钓鱼试炼：装备鱼竿，左键抛竿 → 咬钩时再点左键收竿 · 走到木钓台，看向前方 2–12 米水面 · N 鱼 / M 异兽")


## 只在第一次进入钓鱼试炼时把鱼竿放进空置的 2 号位；该格被占用时不覆盖。
func _ensure_rod() -> void:
	if rod_granted:
		return
	rod_granted = true
	var slot: int = int(fishing_config.get("rod_quick_slot", 1))
	if player.quick_slots.has("fishing_rod"):
		return
	if slot < 0 or slot >= player.quick_slots.size():
		return
	if not player.quick_slots[slot].is_empty():
		show_notice("2 号位已有物品，鱼竿留在背包里（Tab 自行放入）")
		return
	player.assign_quick_slot(slot, "fishing_rod")
	player.selected_slot = slot
	player._refresh_weapon()
	show_notice("鱼竿已放进 2 号位")


func _on_fishing_action() -> void:
	if mode != 4 or fishing == null or player.dead or player.menu_open or not player.controls_active:
		return
	if fishing.encounter_active:
		show_fishing_notice("先处理异兽，再继续垂钓")
		return
	match int(fishing.state):
		2:  # WAITING：提前收竿，正常取消
			fishing.cancel_waiting()
		3:  # BITING：窗口内收竿 → 结算
			fishing.reel_bite()
		_:
			_cast_line()


func _cast_line() -> void:
	if not player.equipped_water_tool():
		return
	var eye: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z
	var result: Dictionary = fishing.resolve_cast(eye, forward)
	if result.has("reason"):
		show_fishing_notice(str(result.reason))
		return
	fishing.begin_cast(fishing_fx.rod_tip(), result.point as Vector3)


func _on_fishing_cast(_point: Vector3) -> void:
	_sound("fish_cast", 0.6)


func _on_fishing_bite() -> void:
	_sound("fish_bite", 1.0)
	player.add_shake(0.006)


func _on_fishing_missed() -> void:
	_sound("fish_missed", 0.8)


func _on_fishing_cancelled(_reason: String) -> void:
	_sound("fish_reel", 0.6)


func _on_fishing_auto_reeled(distance: float) -> void:
	show_notice("离鱼漂 %.1f 米，自动收竿" % distance)


func _on_fishing_revealed(outcome: String, item_id: String, _monster_id: String) -> void:
	if not is_instance_valid(fishing_fx):
		return
	if outcome == "fish":
		_sound("fish_catch", 1.0)
		fishing_fx.spawn_ripple(1.3, 0.5)
		_grant_loot(item_id, 1, fishing.bobber_position)
	else:
		# 异兽：大水纹 + 独立警示音；出生位置与自动换武器在遭遇请求里处理。
		_sound("fish_ominous", 1.0)
		fishing_fx.spawn_ripple(2.6, 1.2)


func _grant_loot(item_id: String, amount: int, _at: Vector3) -> void:
	# Catch ownership stays on the ground until the player explicitly collects it.
	var origin: Vector3 = fishing_fx.rod_tip() if is_instance_valid(fishing_fx) else player.camera.global_position
	_spawn_pickup(item_id, amount, _catch_landing_point(), origin)
	show_fishing_notice("钓到了 %s！蓝色光球落在脚边，靠近按 F 拾取" % _fishing_item_name(item_id))


func _on_fishing_encounter(monster_id: String, reward_item: String, reward_count: int) -> void:
	if encounter_enemy != null and is_instance_valid(encounter_enemy):
		_refuse_encounter_fallback("已经有一只异兽在场，先处理它")
		return
	var spot: Vector3 = _pick_encounter_spot()
	if spot == Vector3.INF:
		_refuse_encounter_fallback("岸边没有合适的出现点")
		return
	fishing.keep_encounter()
	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.name = "FishingEncounter"
	enemy.set_script(ENEMY_SCRIPT)
	enemy.target = null  # 0.8 秒后才开始追击
	enemy.tuning = _fishing_enemy_tuning()
	enemy.stats = GameData.get_monster(str(fishing_config.get("encounter_enemy_source_id", "mon_silence")))
	enemy.position = spot
	enemy.defeated.connect(_on_fishing_enemy_defeated)
	enemy.damage_received.connect(hud.add_damage_number)
	var marker: Label3D = Label3D.new()
	marker.name = "EncounterTag"
	marker.text = "钓上来的异兽"
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 26
	marker.pixel_size = 0.006
	marker.outline_size = 6
	marker.modulate = Color("e6b06b")
	marker.position.y = 1.75
	enemy.add_child(marker)
	enemies.add_child(enemy)
	encounter_enemy = enemy
	_encounter_pending = {"monster_id": monster_id, "reward_item": reward_item, "reward_count": reward_count}
	fishing.encounter_active = true
	player.switch_to_combat_weapon()
	show_notice("钓到了异兽！自动切回战斗武器，0.8 秒后开始追击")
	var delay: float = float(fishing_config.get("encounter_delay", 0.8))
	get_tree().create_timer(delay).timeout.connect(_start_encounter_chase.bind(enemy))


## 异兽接不上时不能吞掉这次收竿：按普通渔获补一条鱼，并说明原因。
func _refuse_encounter_fallback(message: String) -> void:
	fishing.refuse_encounter(message)
	if is_instance_valid(fishing_fx):
		fishing_fx.spawn_ripple(1.0, 0.4)
	_grant_loot(str(fishing_config.get("fish_pale_id", "fish_pale_minnow")), 1, fishing.bobber_position)


func _start_encounter_chase(enemy: CharacterBody3D) -> void:
	if not is_instance_valid(enemy) or enemy.dead or encounter_enemy != enemy:
		return
	enemy.target = player


func _on_fishing_enemy_defeated(defeated: Node3D) -> void:
	if encounter_enemy == null or defeated != encounter_enemy:
		return
	var spot: Vector3 = defeated.global_position
	encounter_enemy = null
	fishing.encounter_active = false
	fishing.reset_encounter()
	var reward_item: String = str(_encounter_pending.get("reward_item", ""))
	var reward_count: int = int(_encounter_pending.get("reward_count", 1))
	_encounter_pending.clear()
	if not reward_item.is_empty():
		_spawn_pickup(reward_item, reward_count, spot)
	if is_instance_valid(fishing_fx):
		fishing_fx.spawn_ripple(1.6, 0.6)
	show_notice("异兽已击败，掉落一份材料，靠近按 F 拾取 · 可以继续垂钓")


func _fishing_enemy_tuning() -> Dictionary:
	if _enemy_tuning.is_empty():
		_enemy_tuning = (tuning.get("enemy", {}) as Dictionary).duplicate(true)
	return _enemy_tuning


## 预设岸上位置：至少离玩家 5 米、不在墙里也不在玩家身上。
func _pick_encounter_spot() -> Vector3:
	var minimum: float = float(fishing_config.get("encounter_min_distance", 5.0))
	if is_instance_valid(shore_area):
		return shore_area.pick_encounter_spawn(player.global_position, minimum)
	var candidates: Array = fishing_config.get("encounter_spawns", [])
	for point: Array in candidates:
		var spot: Vector3 = _vector(point)
		if Vector2(spot.x - player.global_position.x, spot.z - player.global_position.z).length() < minimum:
			continue
		if _spot_blocked(spot):
			continue
		return spot
	# 预设点都不合适时，围绕玩家再找一圈合法点（仍保持 5 米以上）。
	for angle: int in range(0, 360, 30):
		var offset: Vector3 = Vector3(cos(deg_to_rad(float(angle))), 0.0, sin(deg_to_rad(float(angle)))) * (minimum + 1.0)
		var spot: Vector3 = player.global_position + offset
		if _inside_pond(spot) or _spot_blocked(spot):
			continue
		return Vector3(spot.x, 0.1, spot.z)
	return Vector3.INF


func _spot_blocked(spot: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.1
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.6)
	query.collision_mask = 1
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _inside_pond(point: Vector3) -> bool:
	if not fishing_config.has("arena"):
		return false
	var area: Dictionary = fishing_config.arena as Dictionary
	var minimum: Array = area.get("pond_min", [])
	var maximum: Array = area.get("pond_max", [])
	if minimum.size() < 2 or maximum.size() < 2:
		return false
	return point.x >= float(minimum[0]) and point.x <= float(maximum[0]) and point.z >= float(minimum[1]) and point.z <= float(maximum[1])


## 背包满时的掉落点：把落点推到最近的岸边外侧，避免沉在水面中间。
func _bank_point_near(point: Vector3) -> Vector3:
	if not fishing_config.has("arena"):
		return Vector3(point.x, 0.06, point.z + 1.0)
	var area: Dictionary = fishing_config.arena as Dictionary
	var minimum: Array = area.get("pond_min", [])
	var maximum: Array = area.get("pond_max", [])
	if minimum.size() < 2 or maximum.size() < 2:
		return Vector3(point.x, 0.06, point.z + 1.0)
	var min_x: float = float(minimum[0])
	var min_z: float = float(minimum[1])
	var max_x: float = float(maximum[0])
	var max_z: float = float(maximum[1])
	var margin: float = float(fishing_config.get("bobber_grip_margin", 1.0)) * 0.7
	var bank_z: float = min_z - margin
	if min_z - point.z <= point.z - max_z and min_z - point.z <= minf(point.x - min_x, max_x - point.x):
		return Vector3(clampf(point.x, min_x, max_x), 0.06, bank_z)
	if minf(point.x - min_x, max_x - point.x) < minf(min_z - point.z, point.z - max_z):
		var bank_x: float = min_x - margin if point.x - min_x < max_x - point.x else max_x + margin
		return Vector3(bank_x, 0.06, clampf(point.z, min_z, max_z))
	var back_z: float = max_z + margin if point.z - min_z > max_z - point.z else min_z - margin
	return Vector3(clampf(point.x, min_x, max_x), 0.06, back_z)


func _setup_pickup_action() -> void:
	# One canonical interaction action, with the old pickup name retained as an alias.
	for action: String in ["interact", "fps_pickup"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = OS.find_keycode_from_string(str(feedback_config.get("pickup_key", "F")))
		InputMap.action_add_event(action, key)


func _ground_drop_point(at: Vector3) -> Vector3:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at - Vector3.UP * 10.0, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.65:
		return Vector3.INF
	var spot: Vector3 = hit.position as Vector3
	if _inside_pond(spot) and spot.y < float(fishing_config.arena.water_level) + 0.1:
		return Vector3.INF
	return spot + Vector3.UP * 0.025


func _catch_landing_point() -> Vector3:
	var forward: Vector3 = -player.global_basis.z
	var right: Vector3 = player.global_basis.x
	for offset: Vector3 in [forward * 0.9 + right * 0.45, forward * 0.6, right * 0.6, -right * 0.6, Vector3.ZERO]:
		var spot: Vector3 = _ground_drop_point(player.global_position + offset)
		if spot != Vector3.INF:
			return spot
	return _ground_drop_point(player.spawn_position)


func _spawn_pickup(item_id: String, amount: int, at: Vector3, flight_origin: Vector3 = Vector3.INF) -> void:
	if amount <= 0:
		return
	var landing: Vector3 = _ground_drop_point(at) if at != Vector3.INF else _catch_landing_point()
	if landing == Vector3.INF:
		landing = _catch_landing_point()
	if landing == Vector3.INF:
		# Keep an unclaimed reward visible at the safe spawn even if a map has no ground query.
		landing = player.spawn_position
	var pickup: Area3D = PICKUP_SCRIPT.new() as Area3D
	pickup.manual_collect = true
	pickup.auto_collect = false
	pickup.bag = loot
	pickup.player = player
	pickup.pick_radius = float(feedback_config.pickup_radius)
	pickup.pickup_delay = float(feedback_config.pickup_delay)
	pickup.setup(item_id, amount)
	add_child(pickup)
	pickup.global_position = landing
	pickup.set_notice_target(hud)
	pickup.collected.connect(func(id: String, count: int) -> void:
		_sound("fish_pickup", 1.0)
		show_fishing_notice("拾取 %s ×%d" % [_fishing_item_name(id), count])
	)
	pickup.landed.connect(func() -> void: _sound("fish_drop", 0.6))
	if flight_origin != Vector3.INF:
		pickup.launch_from(flight_origin - Vector3.UP * 0.10, float(feedback_config.drop_flight_seconds), float(feedback_config.drop_arc))
	pickups.append(pickup)


func _nearest_pickup() -> Node3D:
	var nearest: Node3D = null
	var distance: float = float(feedback_config.pickup_radius)
	for pickup: Node3D in pickups:
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion() or pickup.amount <= 0 or pickup.in_flight:
			continue
		var d: float = player.global_position.distance_to(pickup.global_position)
		if d > distance:
			continue
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.camera.global_position, pickup.global_position + Vector3.UP * 0.24, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		distance = d
		nearest = pickup
	return nearest


func _collect_nearest_pickup() -> void:
	var pickup: Node3D = _nearest_pickup()
	if is_instance_valid(pickup):
		pickup.try_collect()


func _update_pickups(_delta: float) -> void:
	var nearest: Node3D = _nearest_pickup()
	for index: int in range(pickups.size() - 1, -1, -1):
		var pickup: Node3D = pickups[index]
		if not is_instance_valid(pickup):
			pickups.remove_at(index)
			continue
		pickup.paused = player.menu_open or not player.controls_active
		pickup.set_focused(pickup == nearest and not player.menu_open)


func _fishing_item_name(item_id: String) -> String:
	var fish: Dictionary = GameData.get_fish(item_id)
	if not fish.is_empty():
		return str(fish.get("name", item_id))
	return GameData.get_item_name(item_id)


func _clear_pickups() -> void:
	for pickup: Node3D in pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	pickups.clear()


func _clear_encounter() -> void:
	if encounter_enemy != null and is_instance_valid(encounter_enemy) and not encounter_enemy.dead:
		encounter_enemy.queue_free()
	encounter_enemy = null
	_encounter_pending.clear()
	if fishing != null:
		fishing.encounter_active = false
		fishing.reset_encounter()


func _clear_fishing_trial() -> void:
	if fishing != null:
		fishing.cancel_silent("trial")
		fishing.encounter_active = false
		fishing.force = 0
		fishing.set_paused(false)


func _ensure_fishing_world() -> void:
	if is_instance_valid(fishing_fx):
		return
	var existing: Node = get_node_or_null("FishingWorld")
	if existing == null or existing.is_queued_for_deletion():
		_build_fishing_world()
	fishing_fx = FISHING_PRESENTATION_SCRIPT.new() as Node3D
	fishing_fx.name = "FishingPresentation"
	fishing_fx.fishing = fishing
	fishing_fx.player = player
	fishing_fx.water_level = float(fishing_config.arena.get("water_level", 0.06)) if fishing_config.has("arena") else 0.06
	add_child(fishing_fx)
	# Let the line start at the real rod tip in the player's hand instead of the
	# camera offset fallback.
	set_rod_tip_anchor(player.hands.fishing_tip_anchor())
	fishing_fx.bite_tug.connect(func() -> void: _sound("fish_tug", 0.55))


## Codex 接手点：手部/鱼竿模型就位后，把真实竿尖节点交给表现层，
## 鱼线就会从掌心竿尖出发（不改钓鱼逻辑）。
func set_rod_tip_anchor(anchor: Node3D) -> void:
	if is_instance_valid(fishing_fx):
		fishing_fx.set_rod_tip_anchor(anchor)


func _build_fishing_world() -> void:
	# Reuse the delivered shore prefab away from the training obstacles.
	shore_area = SHORE_SCENE.instantiate() as Node3D
	shore_area.name = "FishingWorld"
	shore_area.position = _vector(fishing_config.get("shore_origin", [300.0, 0.0, 0.0]))
	add_child(shore_area)
	fishing_config["arena"] = shore_area.fishing_arena_config()
	fishing.config = fishing_config


func _remove_fishing_world() -> void:
	if is_instance_valid(fishing_fx):
		fishing_fx.queue_free()
	fishing_fx = null
	var world: Node = get_node_or_null("FishingWorld")
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	shore_area = null


func show_fishing_notice(message: String) -> void:
	show_notice(message)


func _toggle_loadout() -> void:
	if player.menu_open:
		hud.close_loadout()
		player.set_controls_active(true)
		if fishing != null:
			fishing.set_paused(false)
	else:
		player.menu_open = true
		player.set_controls_active(false)
		# 暂停期间冻结钓鱼计时与咬钩窗口；不依赖引擎暂停，战斗 HUD 仍可绘制。
		if fishing != null:
			fishing.set_paused(true)
		hud.open_loadout()


func _build_world() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	# 用程序化天空代替纯色背景：环境光从天空取，遗迹贴图才有立体感。
	settings.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.44, 0.58, 0.66)
	sky_material.sky_horizon_color = Color(0.80, 0.86, 0.84)
	sky_material.ground_horizon_color = Color(0.66, 0.72, 0.66)
	sky_material.ground_bottom_color = Color(0.30, 0.36, 0.32)
	sky_material.sun_angle_max = 24.0
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.40
	# ACES 的高光滚降比 FILMIC 更硬，压曝光后细节保得住。
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.tonemap_exposure = 0.90
	# 屏幕空间环境光遮蔽：让石头缝隙、墙根有接触阴影，立体感更强。
	settings.ssao_enabled = true
	settings.ssao_radius = 1.4
	settings.ssao_intensity = 1.8
	settings.ssao_power = 1.6
	# 远景雾：把几百米外的遗迹压淡，近处训练场保持清晰，形成空间层次。
	settings.fog_enabled = true
	settings.fog_light_color = Color(0.58, 0.66, 0.66)
	settings.fog_light_energy = 0.5
	settings.fog_density = 0.0055
	settings.fog_aerial_perspective = 0.45
	settings.fog_sky_affect = 0.35
	environment.environment = settings
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 0.90
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# 遗迹地形先铺底，训练场元素再叠在上面。
	if initial_mode != 4:
		_build_ruins()
	var floor_size: Vector3 = _vector(tuning.arena.size)
	# 地面加厚到 3 米，把遗迹草地的起伏埋在下面。
	_box("ArenaFloor", Vector3(0, -1.5, 0), Vector3(floor_size.x, 3.0, floor_size.z), Color("9c8f78"))
	for side: float in [-1.0, 1.0]:
		# 加高的外墙：既是场地边界，也是蹬墙跑的墙面（7.2 米，够跑完整段）。
		_box("SideWall", Vector3(side * 23.6, 3.6, 0), Vector3(0.8, 7.2, 44), Color("bfae90"))
		_box("EndWall", Vector3(0, 3.6, side * 21.5), Vector3(47, 7.2, 0.8), Color("bfae90"))
		# 场内独立矮墙，提供不靠边界的蹬墙跑练习段。
		_box("WallrunWall", Vector3(side * 17.5, 3.6, side * 6.0), Vector3(0.6, 7.2, 10), Color("cdbb9c"))
		for z: float in [-9.0, 4.0]:
			_box("HookPillar", Vector3(side * 7.5, 3.0, z), Vector3(1.1, 6, 1.1), Color("b6a891"))
			_box("HookCap", Vector3(side * 7.5, 6.15, z), Vector3(1.8, 0.3, 1.8), Color("d7c595"))
		_box("RaisedPlatform", Vector3(side * 12, 1.0, -5), Vector3(4, 2, 6), Color("b0a28c"))
		# A walkable ramp provides an ordinary route even without a grapple.
		var ramp: Node3D = _box("PlatformRamp", Vector3(side * 12, 1.01, 1.55), Vector3(4, 0.2, 8.0), Color("c4b396"))
		ramp.rotation_degrees.x = 16.0
		_box("LowCover", Vector3(side * 4.0, 0.55, -13.5), Vector3(3.2, 1.1, 1.3), Color("8a8072"))
	_box("FrontHookBeam", Vector3(0, 6.0, -9), Vector3(16.1, 0.5, 1.1), Color("b6a891"))
	_box("RearHookBeam", Vector3(0, 6.0, 4), Vector3(16.1, 0.5, 1.1), Color("b6a891"))
	# Bright strips identify good grapple surfaces without changing collision rules.
	_box("FrontHookStripe", Vector3(0, 5.96, -8.43), Vector3(15, 0.16, 0.035), Color("d2ac68"), false)
	_box("RearHookStripe", Vector3(0, 5.96, 4.57), Vector3(15, 0.16, 0.035), Color("d2ac68"), false)
	_box("SafePoint", Vector3(0, 0.015, 8), Vector3(3.2, 0.025, 2.6), Color("c9bda4"), false)
	_sign("练习场  /  TRAINING", Vector3(0, 3.7, -20.9), 55)
	_sign("右键钩爪 · 起钩后立刻空格助推", Vector3(0, 5.0, -8.35), 32)
	_sign("高台", Vector3(-12, 3, -5), 32)
	_sign("高台", Vector3(12, 3, -5), 32)
	_build_parkour()
	if initial_mode != 4:
		_build_exterior_trees()
	course = Node3D.new()
	course.set_script(COURSE_SCRIPT)
	course.arena = self
	add_child(course)


## 载入 UE 遗迹地形，只给 Landscape 加三角碰撞，建筑保持纯装饰。
func _build_exterior_trees() -> void:
	var group: Node3D = Node3D.new()
	group.name = "ExteriorTrees"
	add_child(group)
	var points: Array[Vector3] = [Vector3(-14, 0, -30), Vector3(0, 0, -34), Vector3(14, 0, -31)]
	for i: int in range(3):
		var tree: Node3D = Node3D.new()
		tree.name = "Tree%d" % (i + 1)
		tree.set_script(TREE_SCRIPT)
		tree.position = points[i]
		tree.scale = Vector3.ONE * [0.56, 0.64, 0.60][i]
		tree.rotation.y = float(i) * 1.2
		group.add_child(tree)


func _build_ruins() -> void:
	var ruins_scene: PackedScene = load(RUINS_PATH) as PackedScene
	if ruins_scene == null:
		push_warning("遗迹模型缺失，训练场单独运行")
		return
	var ruins: Node3D = ruins_scene.instantiate() as Node3D
	if ruins == null:
		return
	ruins.name = "ImportedRuins"
	ruins.position = RUINS_OFFSET
	add_child(ruins)
	_add_ruins_collisions(ruins)


func _add_ruins_collisions(node: Node) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null and String(instance.get_path()).contains("Landscape"):
			instance.create_trimesh_collision()
	for child: Node in node.get_children():
		_add_ruins_collisions(child)


func _build_parkour() -> void:
	# Elevated routes and floating islands for grapple practice.
	# Kept clear of the enemy spawns (z -1..-8) and the player spawn (0, 0.08, 8).
	# Rear course: a stair of platforms climbing toward the back wall.
	_box("ParkourStepA", Vector3(0, 2.5, -15), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepB", Vector3(6, 5.0, -17), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepC", Vector3(-6, 8.0, -19), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepD", Vector3(0, 12.0, -20), Vector3(4, 1, 4), Color("d7c595"))
	# Front course: a gentler climb near the spawn side.
	# Keep the central approach to the guardian unobstructed.
	_box("ParkourStepF", Vector3(8, 6.0, 16), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepG", Vector3(-8, 10.0, 18), Vector3(4, 1, 4), Color("d7c595"))
	# Floating islands in the middle: only reachable with the hook.
	_box("FloatingIslandLow", Vector3(0, 9.0, 0), Vector3(6, 0.8, 6), Color("b6a891"))
	_box("FloatingIslandHigh", Vector3(0, 15.0, -10), Vector3(5, 0.8, 5), Color("d7c595"))
	# Tall anchor pillars at the four corners, 18 m high.
	for side: float in [-1.0, 1.0]:
		for depth: float in [-14.0, 14.0]:
			_box("TallAnchor", Vector3(side * 16.0, 9.0, depth), Vector3(1.5, 18, 1.5), Color("b6a891"))
			_box("TallAnchorCap", Vector3(side * 16.0, 18.2, depth), Vector3(2.4, 0.4, 2.4), Color("d2ac68"))
	# High beams give long, readable swing lines.
	_box("HighBeamFront", Vector3(0, 12.0, 14), Vector3(20, 0.4, 0.8), Color("b6a891"))
	_box("HighBeamRear", Vector3(0, 16.0, -14), Vector3(20, 0.4, 0.8), Color("b6a891"))
	# Bright strips mark the beams as grapple surfaces, matching the existing style.
	_box("HighBeamFrontStripe", Vector3(0, 11.78, 14), Vector3(19, 0.06, 0.5), Color("d2ac68"), false)
	_box("HighBeamRearStripe", Vector3(0, 15.78, -14), Vector3(19, 0.06, 0.5), Color("d2ac68"), false)


func _box(node_name: String, point: Vector3, dimensions: Vector3, color: Color, solid: bool = true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = node_name
	body.position = point
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(color)
	body.add_child(visual)
	if solid:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = dimensions
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	add_child(body)
	return body


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# 占位灰盒的反照率偏高，在室外强光下会发白；整体压暗以贴近遗迹石材质感。
	material.albedo_color = color.darkened(0.24)
	material.roughness = 0.95
	material.metallic = 0.0
	return material


func _sign(text: String, point: Vector3, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = ""
	label.position = point
	label.font_size = font_size
	label.pixel_size = 0.009
	label.modulate = Color("eff0da")
	label.outline_modulate = Color("435a55")
	label.outline_size = 10
	add_child(label)
	return label


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _build_audio() -> void:
	for index: int in range(4):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.volume_db = -18.0
		add_child(voice)
		_audio.append(voice)
	_sounds.swing = _tone(200.0, 0.10, 0.6)
	_sounds.hit = _tone(540.0, 0.075, 0.25)
	_sounds.hurt = _tone(110.0, 0.14, 0.7)
	_sounds.step = _movement_noise(0.10, 100.0, 0.30)
	_sounds.land = _movement_noise(0.18, 65.0, 0.45)
	_sounds.jump = _movement_noise(0.10, 140.0, 0.55)
	_sounds.slide = _movement_noise(0.25, 80.0, 0.85)
	_sounds.wave = _tone(320.0, 0.32, 0.75)
	# 钓鱼：抛竿、咬钩、收获、错过、异兽警示各用独立音色。
	_sounds.fish_cast = _tone(240.0, 0.12, 0.5)
	_sounds.fish_reel = _movement_noise(0.16, 150.0, 0.5)
	_sounds.fish_tug = _movement_noise(0.07, 430.0, 0.7)
	_sounds.fish_drop = _tone(420.0, 0.08, 0.5)
	_sounds.fish_pickup = _tone(1050.0, 0.16, -0.35)
	_sounds.fish_bite = _tone(760.0, 0.12, 0.0)
	_sounds.fish_catch = _tone(520.0, 0.22, 0.25)
	_sounds.fish_missed = _tone(190.0, 0.16, 0.35)
	_sounds.fish_ominous = _tone(96.0, 0.55, 0.85)


func _tone(frequency: float, duration: float, slide: float) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count: int = int(duration * 22050.0)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(count * 2)
	var phase: float = 0.0
	for index: int in range(count):
		var progress: float = float(index) / float(count)
		phase += TAU * frequency * (1.0 - progress * slide) / 22050.0
		var envelope: float = minf(progress * 40.0, 1.0) * pow(1.0 - progress, 2.0)
		samples.encode_s16(index * 2, int(sin(phase) * envelope * 18000.0))
	stream.data = samples
	return stream


func _movement_noise(duration: float, frequency: float, roughness: float) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count: int = int(duration * stream.mix_rate)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(count * 2)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 4821
	var filtered: float = 0.0
	for index: int in range(count):
		var progress: float = float(index) / float(count)
		filtered = lerpf(filtered, random.randf_range(-1.0, 1.0), 0.28)
		var thump: float = sin(TAU * frequency * float(index) / float(stream.mix_rate))
		var envelope: float = minf(progress * 60.0, 1.0) * pow(1.0 - progress, 2.0)
		samples.encode_s16(index * 2, int(lerpf(thump * 0.5, filtered, roughness) * envelope * 23000.0))
	stream.data = samples
	return stream


func _sound(sound_name: String, strength: float = 1.0) -> void:
	if _audio.is_empty() or not _sounds.has(sound_name):
		return
	var voice: AudioStreamPlayer = _audio[_audio_index % _audio.size()]
	_audio_index += 1
	var movement: bool = sound_name in ["step", "land", "jump", "slide"]
	voice.volume_db = float(tuning.player.movement_audio_db) + linear_to_db(maxf(strength, 0.01)) if movement else -18.0
	voice.stream = _sounds[sound_name]
	voice.play()
