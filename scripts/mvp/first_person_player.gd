extends CharacterBody3D
## Main first-person controller. Grapple mechanics remain owned by its component.

const MOTION_SCRIPT: Script = preload("res://scripts/mvp/first_person_motion.gd")
const TIDE_WAVE_SCRIPT: Script = preload("res://scripts/mvp/tide_wave.gd")
const BOLT_SCENE: PackedScene = preload("res://scenes/mvp/tide_bolt.tscn")

signal health_changed(value: int)
signal died()
signal retry_requested()
signal loadout_requested()
signal attack_started()
signal melee_hit(target: Node3D)
signal notice_requested(message: String)
signal movement_sound(sound_name: String, strength: float)
signal wave_released()
signal hurt_direction(direction: Vector2)  ## (Claude Code) Apex-style damage direction indicator: screen-space 2D direction from player to attacker
signal fall_damage_taken(amount: int)  ## 坠落扣血，供 HUD 在血条上方显示数字
## 钓鱼钩子（CodeBuddy 2026-10-28）：换装备/武器或使用钩爪前，先清理未完成的钓鱼；
## 场景重置（重新开始、切试炼）后通知钓鱼状态机清场。
signal water_tool_used()  ## 当前快捷物品是钓鱼竿，左键交给钓鱼逻辑
signal loadout_changing()  ## 即将切换快捷物品
signal grapple_requested()  ## 即将发射钩爪
signal reset_applied()  ## reset_to_spawn 已把玩家送回出生点

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var hands: Node3D = $Head/Camera3D/Hands
@onready var grapple: Node3D = $GrappleHook

var controls_active: bool = true
var menu_open: bool = false
## (Claude Code) Optional virtual-stick axes from a touch layer. Zero on desktop,
## where only keyboard axes feed movement.
var _touch_move: Vector2 = Vector2.ZERO
var dead: bool = false
var health: int = 100
var max_health: int = 100
var selected_slot: int = 2
var quick_slots: Array[String] = ["tide_blade", "", "steam_pistol", "m1911", "potion"]
## 通用物品栏（武器、工具、药水、鱼、材料共用）
const BACKPACK_SLOT_COUNT: int = 15
const POTION_ID: String = "potion"
var inventory: Inventory  ## 唯一数量与格位来源
## 泰拉瑞亚式装备栏：护甲 3（头/身/腿）+ 饰品 5，与背包同一套点击搬运逻辑。
const ARMOR_SLOT_COUNT: int = 3
const ACCESSORY_SLOT_COUNT: int = 5
const ARMOR_ROW: int = 4
const ACCESSORY_ROW: int = 5
var armor_slots: Array[String] = []
var accessory_slots: Array[String] = []
var _equipment: Dictionary = {}
## 鸣潮刃的充能格数，命中积累，满格后按 E 释放冲击波。
var energy: int = 0
var _wave_elapsed: float = -1.0
var _wave_fired: bool = false
var spawn_position: Vector3
## 钓鱼（CodeBuddy 2026-10-28）：最近使用的战斗武器、钓到异兽后自动切到的武器。
var last_combat_weapon_id: String = ""
var _tool_input_held: bool = false
var fishing_auto_weapon_id: String = ""
var attack_elapsed: float = -1.0
## 远程武器每次攻击只触发一发，避免 active 窗口跨帧重复开火。
var _attack_fired: bool = false
var swing_index: int = 0
var hit_count: int = 0
var damage_taken: int = 0
var last_hit_time: float = -100.0
var hurt_time_left: float = 0.0
var motion: RefCounted
## 0..1，翻越冲刺特效强度，供 HUD 绘制速度线。
var boost_effect: float = 0.0
var _momentum_time: float = 0.0
var _attack_blocked_until_release: bool = false
var _potion_cooldown: float = 0.0
var _hit_targets: Dictionary = {}
var _settings: Dictionary
var _weapons: Dictionary = {}
var _weapon: Dictionary = {}
var _was_on_floor: bool = true
## 坠落伤害：离地后记录到过的最高点，落地时用落差结算。
var _fall_peak_y: float = 0.0
var _fall_grounded: bool = false
## 供 HUD 判断：这次掉血是不是坠落造成的（坠落没有攻击方向，不画方向箭头）。
var last_damage_was_fall: bool = false
var _previous_velocity_y: float = 0.0
var _shake: float = 0.0
var _hitstop_time: float = 0.0  ## (Claude Code) seconds of hit-stop remaining
var _hitstop_end: float = 0.0  ## (Claude Code) wall-clock time (seconds) when the freeze ends
var _last_hit_direction: Vector2 = Vector2.ZERO  ## (Claude Code) screen-space direction of last incoming hit
var _stride_distance: float = 0.0
var _stride_phase: float = 0.0
var _slide_sound_distance: float = 0.0
var _feedback_grounded: bool = false
var _feedback_sliding: bool = false
var _feedback_position: Vector3


func _ready() -> void:
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_mvp.json")) as Dictionary
	_settings = tuning.player
	_weapons = {}
	if tuning.has("weapon"):
		var base: Dictionary = tuning.weapon
		_weapons[str(base.id)] = base
	if tuning.has("weapons"):
		for key: String in tuning.weapons:
			_weapons[key] = tuning.weapons[key]
	_init_inventory()
	_init_equipment(tuning)
	_weapon = _weapons.get(quick_slots[selected_slot], {})
	max_health = int(_settings.health)
	health = max_health
	spawn_position = global_position
	_fall_peak_y = global_position.y
	# Enemy limbs block the player but must not become velocity-carrying platforms.
	platform_floor_layers = 1
	camera.fov = float(_settings.fov)
	motion = MOTION_SCRIPT.new()
	motion.setup(self, _settings)
	motion.landed.connect(func(speed: float) -> void:
		hands.notify_landing(speed)
		movement_sound.emit("land", clampf(speed / 8.0, 0.4, 1.0))
		# 视线下沉由 motion 统一处理，这里只补镜头震动，避免两套位移叠加。
		var shake: float = 0.0
		if speed >= 20.0:
			shake = 0.045
		elif speed >= 9.0:
			shake = 0.018
		add_shake(shake)
	)
	motion.mantle_boosted.connect(func() -> void: boost_effect = 1.0)
	_feedback_position = global_position
	_setup_input()
	# Run the existing velocity-driving component before this controller resolves movement.
	grapple.process_physics_priority = -20
	grapple.connect("released", _on_grapple_released)
	grapple.connect("attach_failed", _on_grapple_failed)
	grapple.connect("attached", func(_point: Vector3) -> void: add_shake(0.022))
	_refresh_weapon()
	set_controls_active(true)


func _process(delta: float) -> void:
	boost_effect = maxf(0.0, boost_effect - delta * 2.2)
	# (Claude Code) hit-stop: freeze gameplay briefly on a clean hit.
	# Engine.time_scale also slows _process delta, so the remaining time is measured
	# against wall-clock milliseconds — otherwise a 40 ms stop would last ~2 seconds.
	if _hitstop_time > 0.0:
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		if now >= _hitstop_end:
			_hitstop_time = 0.0
			Engine.time_scale = 1.0
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, delta * 0.35)
		camera.h_offset = randf_range(-_shake, _shake)
		camera.v_offset = randf_range(-_shake, _shake)
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## (Claude Code) Touch layer hook: x = strafe, y = forward (same axes as
## Input.get_vector). Ignored while controls are suspended.
func set_touch_move(axes: Vector2) -> void:
	_touch_move = axes.limit_length(1.0)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## (Claude Code) Trigger hit-stop — a brief freeze that sells the weight of an impact.
## Longer stops feel heavier; we cap them so combat never feels sluggish.
## Timed against wall-clock, because time_scale slows delta down with it.
func add_hitstop(duration: float, scale: float = 0.02) -> void:
	if duration <= 0.0:
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	# Only override if the new hit lands further out than the running freeze.
	if now + duration > _hitstop_end:
		_hitstop_time = duration
		_hitstop_end = now + duration
		Engine.time_scale = scale


## Must run before a pause, retry or respawn so gameplay never resumes frozen.
func clear_hitstop() -> void:
	_hitstop_time = 0.0
	Engine.time_scale = 1.0


func _setup_input() -> void:
	for binding: Array in [["fps_jump", KEY_SPACE], ["fps_walk", KEY_SHIFT], ["fps_crouch", KEY_CTRL]]:
		if not InputMap.has_action(binding[0]):
			InputMap.add_action(binding[0])
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = binding[1]
			InputMap.action_add_event(binding[0], event)
	if not InputMap.has_action("fps_attack"):
		InputMap.add_action("fps_attack")
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fps_attack", click)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		if key.physical_keycode == KEY_TAB and not dead:
			loadout_requested.emit()
		elif key.physical_keycode == KEY_E and not menu_open:
			release_wave()
		elif key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_5:
			var slot_index: int = key.physical_keycode - KEY_1
			# 药水槽按下即使用，不切换当前武器。
			if quick_slots[slot_index] == "potion":
				use_potion()
			else:
				select_slot(slot_index)
	elif event is InputEventMouseMotion and controls_active:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		rotate_camera(motion.relative)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and not controls_active and not dead and not menu_open:
			set_controls_active(true)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed and controls_active:
				motion.mantling = false
				motion.sliding = false
				grapple_requested.emit()
				grapple.try_attach()
			else:
				grapple.release()
		elif button.pressed and controls_active and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			select_slot(posmod(selected_slot + (1 if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():
		set_controls_active(false)


func _exit_tree() -> void:
	# (Claude Code) Never leave the engine frozen if the scene is torn down mid hit-stop.
	Engine.time_scale = 1.0


func rotate_camera(relative: Vector2) -> void:
	rotation.y -= relative.x * float(_settings.mouse_sensitivity)
	head.rotation.x = clampf(head.rotation.x - relative.y * float(_settings.mouse_sensitivity), -1.45, 1.45)


func set_controls_active(active: bool) -> void:
	controls_active = active and not dead
	if controls_active:
		_attack_blocked_until_release = Input.is_action_pressed("fps_attack")
		_tool_input_held = Input.is_action_pressed("fps_attack")
	if not controls_active:
		grapple.release()
		velocity = Vector3.ZERO
		attack_elapsed = -1.0
		_momentum_time = 0.0
		motion.suspend()
		clear_hitstop()
		_shake = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		_reset_movement_feedback()
	grapple.set_physics_process(controls_active)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if controls_active else Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not controls_active:
		return
	hurt_time_left = maxf(0.0, hurt_time_left - delta)
	_momentum_time = maxf(0.0, _momentum_time - delta)
	var axes: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _touch_move.length() > axes.length():
		axes = _touch_move
	var direction: Vector3 = global_basis * Vector3(axes.x, 0.0, axes.y)
	var sprinting: bool = not Input.is_action_pressed("fps_walk")
	var jump_pressed: bool = Input.is_action_just_pressed("fps_jump")
	if jump_pressed and grapple.is_pulling():
		grapple.apply_super_grapple()
		jump_pressed = false
	motion.prepare(delta, direction, sprinting, jump_pressed, Input.is_action_pressed("fps_jump"), Input.is_action_pressed("fps_crouch"), _momentum_time > 0.0)
	if _attack_blocked_until_release:
		_attack_blocked_until_release = Input.is_action_pressed("fps_attack")
	elif Input.is_action_pressed("fps_attack"):
		# 钓鱼竿：只在按下的那一次发请求；长按或连点不会重复抛竿/收竿。
		if equipped_water_tool():
			if not _tool_input_held:
				_tool_input_held = true
				water_tool_used.emit()
		else:
			request_attack()
	else:
		_tool_input_held = false
	move_and_slide()
	motion.after_move(delta)
	_update_fall_tracking()
	_potion_cooldown = maxf(0.0, _potion_cooldown - delta)
	_update_movement_feedback()
	# 镜头起伏与手部 bob 共用同一相位，节奏才对得上。
	motion.view_stride_phase = _stride_phase
	_update_attack(delta)
	_update_wave(delta)
	var wall_distance: float = _front_obstacle_distance()
	var progress: float = attack_elapsed / attack_duration() if attack_elapsed >= 0.0 else -1.0
	hands.update_pose(delta, Vector2(velocity.x, velocity.z).length(), sprinting, progress, swing_index, equipped_blade(), wall_distance, {
		"grounded": is_on_floor(), "sliding": motion.sliding, "mantling": motion.mantling,
		"crouching": motion.crouching,
		"wallrunning": motion.wallrunning, "wallrun_side": motion.wallrun_side,
		"grappling": grapple.is_attached(),
		"grapple_preparing": grapple.is_preparing(),
		"wave_progress": _wave_elapsed / _wave_duration() if _wave_elapsed >= 0.0 else -1.0,
		"grapple_anchor": grapple.anchor,
		"grapple_shot_duration": grapple.rope_visual.shot_duration,
		"local_velocity": camera.global_basis.inverse() * velocity,
		"stride_phase": _stride_phase, "sharpness": float(_settings.hand_pose_sharpness), "scale": float(_settings.hand_motion_scale)
	})
	var glow_maximum: int = energy_max()
	var glow_ratio: float = float(energy) / float(glow_maximum) if glow_maximum > 0 else 0.0
	hands.set_energy_glow(1.0 if _wave_elapsed >= 0.0 and not _wave_fired else glow_ratio)
	if global_position.y < -8.0:
		reset_to_spawn(false)
		notice_requested.emit("落水已返回安全点")


func equipped_blade() -> bool:
	return not quick_slots[selected_slot].is_empty()


## 钓鱼竿是工具不是武器：左键交给钓鱼逻辑，不触发近战/开火。
func equipped_water_tool() -> bool:
	var item: Dictionary = _weapons.get(quick_slots[selected_slot], {}) as Dictionary
	return str(item.get("tool", "")) == "fishing"


## 最近使用的战斗武器（不含空手与鱼竿），供异兽出现后自动切回。
func last_combat_weapon() -> String:
	if last_combat_weapon_id.is_empty() or not _weapons.has(last_combat_weapon_id):
		return ""
	return last_combat_weapon_id


func _remember_combat_weapon() -> void:
	var item_id: String = quick_slots[selected_slot]
	var item: Dictionary = _weapons.get(item_id, {}) as Dictionary
	if item_id.is_empty() or not item.get("tool", "").is_empty():
		return
	last_combat_weapon_id = item_id


## 当前武器的充能上限，0 表示该武器没有充能机制。
func energy_max() -> int:
	return int(_weapon.get("energy_max", 0))


## 切换手持快捷物品；先让钓鱼逻辑清理未完成的抛竿，再切换。
func select_slot(index: int) -> void:
	if index < 0 or index >= quick_slots.size() or index == selected_slot:
		return
	loadout_changing.emit()
	selected_slot = index
	_refresh_weapon()


func _refresh_weapon() -> void:
	_remember_combat_weapon()
	_wave_elapsed = -1.0
	_weapon = _weapons.get(quick_slots[selected_slot], {})
	energy = 0
	attack_elapsed = -1.0
	if hands != null:
		hands.set_weapon(quick_slots[selected_slot])


## 背包物品清单：现有全部武器 + 药水。顺序沿用 JSON，格子位置才稳定。
## 带 "hidden": true 的条目不进背包（数据仍保留，测试与旧入口照旧可用）。
func item_catalog() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _weapons:
		var entry: Variant = _weapons[key]
		if entry is Dictionary and bool((entry as Dictionary).get("hidden", false)):
			continue
		ids.append(key)
	if not ids.has(POTION_ID):
		ids.append(POTION_ID)
	return ids


## 初始化背包：没装在快捷栏里的物品按顺序摆进储物格，剩下的留空。
func _init_inventory() -> void:
	inventory = Inventory.new()
	inventory.setup(BACKPACK_SLOT_COUNT, 999)
	# 快捷栏中的非空物品需要在库存中有对应的记录（即使数量为 0 也行）。
	# 这样 UI 读取时能正常展示快捷栏内容。
	for item_id: String in quick_slots:
		if not item_id.is_empty():
			var count: int = inventory.get_count(item_id)
			if count <= 0:
				inventory.items[item_id] = 0


## 行 0 = 快捷栏（1-5 键），行 1..3 = 背包存储，行 4 = 护甲，行 5 = 饰品。
## 返回该位置的物品 ID，"" 表示空。
func slot_item(row: int, column: int) -> String:
	if row == 0:
		return quick_slots[column] if column >= 0 and column < quick_slots.size() else ""
	if row == ARMOR_ROW:
		return armor_slots[column] if column >= 0 and column < armor_slots.size() else ""
	if row == ACCESSORY_ROW:
		return accessory_slots[column] if column >= 0 and column < accessory_slots.size() else ""
	# 背包存储部分（行 1..3，列 0..4）
	var index: int = (row - 1) * 5 + column
	if index >= 0 and index < inventory.slot_count:
		return inventory.slots[index]
	return ""


## 设置某个位置的物品 ID（用于拖放、交换等 UI 操作）。
func set_slot_item(row: int, column: int, item_id: String) -> void:
	if row == 0:
		# 快捷栏
		if column < 0 or column >= quick_slots.size():
			return
		# 只要手上的物品变了就通知钓鱼逻辑清理未完成的抛竿。
		if column == selected_slot and quick_slots[column] != item_id:
			loadout_changing.emit()
		quick_slots[column] = item_id
		if column == selected_slot:
			_refresh_weapon()
		return
	if row == ARMOR_ROW or row == ACCESSORY_ROW:
		# 装备栏
		var target: Array[String] = armor_slots if row == ARMOR_ROW else accessory_slots
		if column < 0 or column >= target.size():
			return
		# 只有类型对得上的物品能放进装备栏
		if not item_id.is_empty() and not _fits_slot(item_id, row):
			return
		target[column] = item_id
		return
	# 背包存储部分
	var index: int = (row - 1) * 5 + column
	if index >= 0 and index < inventory.slot_count:
		inventory.slots[index] = item_id


# === 装备栏 ===
func _init_equipment(tuning: Dictionary) -> void:
	_equipment.clear()
	armor_slots.clear()
	accessory_slots.clear()
	var block: Dictionary = tuning.get("equipment", {}) as Dictionary
	var items: Dictionary = block.get("items", {}) as Dictionary
	for key: String in items:
		_equipment[key] = items[key]
	var defaults: Dictionary = block.get("dev_defaults", {}) as Dictionary
	var armor_default: Array = defaults.get("armor", []) as Array
	var accessory_default: Array = defaults.get("accessories", []) as Array
	for i: int in range(ARMOR_SLOT_COUNT):
		armor_slots.append(str(armor_default[i]) if i < armor_default.size() else "")
	for i: int in range(ACCESSORY_SLOT_COUNT):
		accessory_slots.append(str(accessory_default[i]) if i < accessory_default.size() else "")


func equipment_def(item_id: String) -> Dictionary:
	return _equipment.get(item_id, {}) as Dictionary


func equipment_name(item_id: String) -> String:
	var def: Dictionary = equipment_def(item_id)
	return str(def.get("name", "")) if not def.is_empty() else ""


func _fits_slot(item_id: String, row: int) -> bool:
	var def: Dictionary = equipment_def(item_id)
	if def.is_empty():
		return false
	return str(def.get("slot", "")) == ("armor" if row == ARMOR_ROW else "accessory")


## 已装备的饰品里是否有免疫坠落伤害的效果。
func has_fall_immunity() -> bool:
	for item_id: String in accessory_slots:
		if item_id.is_empty():
			continue
		var effects: Dictionary = equipment_def(item_id).get("effects", {}) as Dictionary
		if bool(effects.get("fall_immune", false)):
			return true
	return false


## 钓到异兽后自动切回最近使用的战斗武器；没有记录则用初始剑（或 1 号位上的原战斗武器）。
func switch_to_combat_weapon() -> String:
	var choice: String = last_combat_weapon()
	if choice.is_empty():
		for slot: int in range(quick_slots.size()):
			var item: Dictionary = _weapons.get(quick_slots[slot], {}) as Dictionary
			if not quick_slots[slot].is_empty() and item.get("tool", "").is_empty():
				choice = quick_slots[slot]
				break
	if choice.is_empty():
		return ""
	var slot: int = quick_slots.find(choice)
	if slot >= 0:
		loadout_changing.emit()
		selected_slot = slot
		fishing_auto_weapon_id = choice
		_refresh_weapon()
	return choice


func assign_quick_slot(index: int, item_id: String) -> void:
	if index < 0 or index >= quick_slots.size():
		return
	if not item_id.is_empty() and not _weapons.has(item_id):
		return
	loadout_changing.emit()
	if not item_id.is_empty():
		# 一件物品只占一个格子：其它快捷栏位和背包里的同名物品都清掉。
		for slot: int in range(quick_slots.size()):
			if quick_slots[slot] == item_id:
				quick_slots[slot] = ""
		for slot: int in range(inventory.slots.size()):
			if inventory.slots[slot] == item_id:
				inventory.slots[slot] = ""
	quick_slots[index] = item_id
	_refresh_weapon()


## 鸣潮刃的冲击波：满格时朝准星方向挥出一道可穿透的宽波。
func release_wave() -> bool:
	if not controls_active or dead or not equipped_blade():
		return false
	if _wave_elapsed >= 0.0 or attack_elapsed >= 0.0 or hands.drink_active() or motion.mantling or hands.block_active():
		return false
	if not _weapon.has("wave_damage") or energy < energy_max():
		return false
	energy = 0
	_wave_elapsed = 0.0
	_wave_fired = false
	hands._cancel_spawn_animation()
	return true


func _wave_duration() -> float:
	return float(_weapon.get("wave_windup", 0.20)) + float(_weapon.get("wave_active", 0.18)) + float(_weapon.get("wave_recovery", 0.30))


func _update_wave(delta: float) -> void:
	if _wave_elapsed < 0.0:
		return
	if dead or not controls_active or hands.drink_active() or motion.mantling or not _weapon.has("wave_damage"):
		_wave_elapsed = -1.0
		return
	_wave_elapsed += delta
	if not _wave_fired and _wave_elapsed >= float(_weapon.get("wave_windup", 0.20)):
		_wave_fired = true
		_spawn_wave()
	if _wave_elapsed >= _wave_duration():
		_wave_elapsed = -1.0


func _spawn_wave() -> void:
	var forward: Vector3 = -camera.global_basis.z
	var wave: Node3D = Node3D.new()
	wave.set_script(TIDE_WAVE_SCRIPT)
	wave.direction = forward
	wave.speed = float(_weapon.wave_speed)
	wave.max_range = float(_weapon.wave_range)
	wave.damage = int(_weapon.wave_damage)
	wave.knockback = float(_weapon.wave_knockback)
	wave.width = float(_weapon.wave_width)
	wave.height = float(_weapon.wave_height)
	wave_released.emit()
	get_tree().current_scene.add_child(wave)
	wave.global_position = camera.global_position + forward * 1.1
	add_shake(0.012)


func attack_duration() -> float:
	return float(_weapon.windup) + float(_weapon.active) + float(_weapon.recovery)


## 喝药：播放动作并立即回复生命；喝药期间不能攻击。
func use_potion() -> bool:
	if dead or not controls_active or _potion_cooldown > 0.0:
		return false
	if hands.drink_active():
		return false
	if health >= max_health:
		notice_requested.emit("生命已满")
		return false
	# 喝药立即打断进行中的攻击，避免武器已隐藏但判定继续。
	attack_elapsed = -1.0
	hands.start_drink()
	_potion_cooldown = float(_settings.get("potion_cooldown", 3.0))
	health = mini(max_health, health + int(_settings.get("potion_heal", 35)))
	health_changed.emit(health)
	return true


func request_attack() -> bool:
	if not controls_active or dead or motion.mantling or not equipped_blade() or attack_elapsed >= 0.0 or _wave_elapsed >= 0.0:
		return false
	if hands.drink_active():
		return false
	swing_index += 1
	attack_elapsed = 0.0
	_attack_fired = false
	_hit_targets.clear()
	attack_started.emit()
	return true


func _update_attack(delta: float) -> void:
	if attack_elapsed < 0.0:
		return
	if not controls_active or not equipped_blade() or hands.drink_active():
		attack_elapsed = -1.0
		return
	attack_elapsed += delta
	if bool(_weapon.get("ranged", false)):
		if not _attack_fired and attack_elapsed >= float(_weapon.windup):
			_attack_fired = true
			_fire_bolt()
	elif attack_elapsed >= float(_weapon.windup) and attack_elapsed <= float(_weapon.windup) + float(_weapon.active):
		_resolve_melee()
	if attack_elapsed >= attack_duration():
		attack_elapsed = -1.0


## 潮汐手炮：沿准星发射一枚磷光弹，命中由弹体自己判定。
func _fire_bolt() -> void:
	var forward: Vector3 = -camera.global_basis.z
	var origin: Vector3 = camera.global_position + forward * 0.55
	var bolt: Node3D = BOLT_SCENE.instantiate() as Node3D
	if bolt == null:
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(bolt)
	bolt.setup(origin, forward, float(_weapon.bolt_speed), float(_weapon.bolt_life), int(_weapon.damage), float(_weapon.knockback))
	hands.play_pistol_recoil()
	add_shake(0.010)


func _resolve_melee() -> void:
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var min_dot: float = cos(deg_to_rad(float(_weapon.arc_degrees) * 0.5))
	var landed: bool = false
	for node: Node in get_tree().get_nodes_in_group("mvp_enemies"):
		var target: Node3D = node as Node3D
		if target == null or target.dead or _hit_targets.has(target.get_instance_id()):
			continue
		var destination: Vector3 = target.global_position + Vector3.UP * 0.65
		var contact: Dictionary = {}
		if target.has_method("melee_contact"):
			contact = target.melee_contact(origin, forward, float(_weapon.range), min_dot)
			if contact.is_empty():
				continue
			destination = contact.position
		elif target.has_method("damage_point"):
			destination = target.damage_point()
		var offset: Vector3 = destination - origin
		if offset.length() > float(_weapon.range) or forward.dot(offset.normalized()) < min_dot:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, destination, 1, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		_hit_targets[target.get_instance_id()] = true
		var push: Vector3 = (destination - global_position).normalized() * float(_weapon.knockback)
		if not contact.is_empty():
			target.apply_part_damage(int(_weapon.damage), push, str(contact.part))
		else:
			target.apply_damage(int(_weapon.damage), push)
		hit_count += 1
		last_hit_time = Time.get_ticks_msec() / 1000.0
		landed = true
		melee_hit.emit(target)
	# (Claude Code) Impact feedback: shake + hit-stop, scaled by how many enemies we hit.
	# A clean single hit gets a sharp micro-freeze; multi-hit gets bigger shake and longer stop.
	if landed:
		var impact_strength: float = clampf(float(hit_count) * 0.8, 0.6, 2.5)
		add_shake(0.018 * impact_strength)
		add_hitstop(0.035 * impact_strength, 0.02)
	# 一次挥击只充一格，避免群怪瞬间满能量。
	if landed and energy_max() > 0:
		energy = mini(energy + 1, energy_max())


## 记录离地后的最高点；落地那一帧用"最高点 - 落点"算落差。
## 攀爬和蹬墙跑不算坠落，会持续把基准压到当前高度。
func _update_fall_tracking() -> void:
	var grounded: bool = is_on_floor()
	if grounded:
		if not _fall_grounded:
			_apply_fall_damage(_fall_peak_y - global_position.y)
		_fall_peak_y = global_position.y
	elif not motion.mantling and not motion.wallrunning:
		_fall_peak_y = maxf(_fall_peak_y, global_position.y)
	_fall_grounded = grounded


## 坠落伤害：落差在 safe_height（钩爪柱台面 6.3 m）以内不扣血，
## 超过后每多一米加 damage_per_meter，封顶 max_damage。
func _apply_fall_damage(drop: float) -> void:
	var cfg: Dictionary = _settings.get("fall_damage", {}) as Dictionary
	if cfg.is_empty() or dead or not controls_active:
		return
	# 疾风之靴之类的饰品：免疫坠落伤害。
	if has_fall_immunity():
		return
	var safe: float = float(cfg.get("safe_height", 6.3))
	if drop <= safe:
		return
	var amount: int = int(round((drop - safe) * float(cfg.get("damage_per_meter", 6.0))))
	amount = maxi(amount, int(cfg.get("min_damage", 1)))
	amount = mini(amount, int(cfg.get("max_damage", 60)))
	health = maxi(0, health - amount)
	damage_taken += amount
	last_damage_was_fall = true
	# 借用无敌帧触发 HUD 受击红闪，但不给击退方向——坠落没有攻击来源。
	hurt_time_left = float(_settings.get("hurt_invulnerability", 0.65))
	add_shake(0.012 + 0.001 * float(amount))
	health_changed.emit(health)
	fall_damage_taken.emit(amount)
	if health <= 0:
		dead = true
		set_controls_active(false)
		grapple.reset()
		died.emit()


func receive_damage(amount: int, source: Vector3) -> bool:
	if dead or not controls_active or hurt_time_left > 0.0:
		return false
	last_damage_was_fall = false
	health = maxi(0, health - amount)
	damage_taken += amount
	hurt_time_left = float(_settings.hurt_invulnerability)
	_momentum_time = 0.15
	var away: Vector3 = global_position - source
	away.y = 0.0
	velocity += away.normalized() * 2.0
	# (Claude Code) Compute screen-space damage direction for the Apex-style indicator.
	# Convert the attacker's direction into camera-space so the HUD can draw an arrow on the right side.
	var to_source: Vector3 = source - global_position
	to_source.y = 0.0
	if to_source.length_squared() > 0.001:
		var forward: Vector3 = -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right: Vector3 = camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var dir_norm: Vector3 = to_source.normalized()
		# Project onto camera forward/right → 2D screen direction relative to crosshair.
		_last_hit_direction = Vector2(right.dot(dir_norm), forward.dot(dir_norm)).normalized()
	else:
		_last_hit_direction = Vector2(0, 1)
	hurt_direction.emit(_last_hit_direction)
	health_changed.emit(health)
	if health <= 0:
		dead = true
		set_controls_active(false)
		grapple.reset()
		died.emit()
	return true


func reset_to_spawn(restore_health: bool = true) -> void:
	grapple.reset()
	motion.reset()
	clear_hitstop()
	boost_effect = 0.0
	_shake = 0.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	global_position = spawn_position
	_fall_peak_y = global_position.y
	_fall_grounded = false
	_reset_movement_feedback()
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	attack_elapsed = -1.0
	energy = 0
	_momentum_time = 0.0
	_wave_elapsed = -1.0
	_wave_fired = false
	hurt_time_left = 0.0
	dead = false
	menu_open = false
	if restore_health:
		health = max_health
		hit_count = 0
		damage_taken = 0
	health_changed.emit(health)
	set_controls_active(true)
	reset_applied.emit()


func _front_obstacle_distance() -> float:
	var start: Vector3 = camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, start - camera.global_basis.z * 1.2, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return 1.2 if hit.is_empty() else start.distance_to(hit.position)


func _reset_movement_feedback() -> void:
	_stride_distance = 0.0
	_stride_phase = 0.0
	_slide_sound_distance = 0.0
	_feedback_grounded = false
	_feedback_sliding = false
	_feedback_position = global_position
	hands.reset_motion()


func _update_movement_feedback() -> void:
	var distance: float = Vector2(global_position.x - _feedback_position.x, global_position.z - _feedback_position.z).length()
	_feedback_position = global_position
	var grounded: bool = is_on_floor()
	if not grounded and _feedback_grounded and velocity.y > 2.0 and not motion.mantling:
		movement_sound.emit("jump", 0.5)
	if grounded and not motion.mantling and distance < 1.0:
		if motion.sliding:
			_slide_sound_distance += distance
			if not _feedback_sliding or _slide_sound_distance >= 1.7:
				movement_sound.emit("slide", 0.7)
				_slide_sound_distance = 0.0
		elif distance > 0.001:
			var stride: float = float(_settings.crouch_step_distance if motion.crouching else _settings.step_distance)
			_stride_phase = fmod(_stride_phase + distance / stride * PI, TAU * 2.0)
			_stride_distance += distance
			if _stride_distance >= stride:
				_stride_distance = fmod(_stride_distance, stride)
				movement_sound.emit("step", 0.45 if motion.crouching else 0.85)
	_feedback_grounded = grounded
	_feedback_sliding = motion.sliding


func _on_grapple_released() -> void:
	_momentum_time = float(_settings.release_momentum_seconds)


func _on_grapple_failed() -> void:
	notice_requested.emit("没有钩中：瞄准石柱或横梁，距离需在 %d 米内" % int(grapple.max_range))


# === 通用背包接口（UI 与其他系统读取用） ===

## 获取某个物品的数量
func item_count(item_id: String) -> int:
	if inventory == null:
		return 0
	return inventory.get_count(item_id)


## 获取背包列表：格位顺序，含数量
func inventory_entries() -> Array[Dictionary]:
	if inventory == null:
		return []
	return inventory.entries()


## 背包操作：交换两个格位
func inventory_swap_slots(from_row: int, from_col: int, to_row: int, to_col: int) -> bool:
	var from_idx: int = _rowcol_to_index(from_row, from_col)
	var to_idx: int = _rowcol_to_index(to_row, to_col)
	if from_idx < 0 or to_idx < 0:
		return false
	return inventory.swap_slots(from_idx, to_idx)


## 背包操作：删除到垃圾槽
func inventory_delete_to_trash(item_id: String, count: int = 1) -> bool:
	if inventory == null:
		return false
	return inventory.delete_to_trash(item_id, count)


## 背包操作：从垃圾槽恢复
func inventory_restore_from_trash() -> bool:
	if inventory == null:
		return false
	return inventory.restore_from_trash()


## 内部：行列坐标转格位索引（背包存储部分，行 1..3）
func _rowcol_to_index(row: int, col: int) -> int:
	if row == 0 or row == ARMOR_ROW or row == ACCESSORY_ROW or row < 1 or row > 3 or col < 0 or col >= 5:
		return -1
	return (row - 1) * 5 + col
