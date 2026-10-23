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
var quick_slots: Array[String] = ["tide_blade", "", "steam_pistol", "", "potion"]
## 鸣潮刃的充能格数，命中积累，满格后按 E 释放冲击波。
var energy: int = 0
var spawn_position: Vector3
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
	_weapon = _weapons.get(quick_slots[selected_slot], {})
	max_health = int(_settings.health)
	health = max_health
	spawn_position = global_position
	camera.fov = float(_settings.fov)
	motion = MOTION_SCRIPT.new()
	motion.setup(self, _settings)
	motion.landed.connect(func(speed: float) -> void:
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
		if key.physical_keycode == KEY_R:
			retry_requested.emit()
		elif key.physical_keycode == KEY_TAB and not dead:
			loadout_requested.emit()
		elif key.physical_keycode == KEY_V and not menu_open:
			motion.toggle_profile()
			notice_requested.emit("移动档：%s · V 切换，R 重跑路线" % motion.profile_name())
		elif key.physical_keycode == KEY_E and not menu_open:
			release_wave()
		elif key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_5:
			var slot_index: int = key.physical_keycode - KEY_1
			# 药水槽按下即使用，不切换当前武器。
			if quick_slots[slot_index] == "potion":
				use_potion()
			else:
				selected_slot = slot_index
				_refresh_weapon()
		elif key.physical_keycode == KEY_ESCAPE and not dead:
			if menu_open:
				loadout_requested.emit()
			else:
				set_controls_active(not controls_active)
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
				grapple.try_attach()
			else:
				grapple.release()
		elif button.pressed and controls_active and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			selected_slot = posmod(selected_slot + (1 if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 5)
			_refresh_weapon()


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
	if jump_pressed and grapple.is_attached():
		grapple.apply_super_grapple()
		jump_pressed = false
	motion.prepare(delta, direction, sprinting, jump_pressed, Input.is_action_pressed("fps_jump"), Input.is_action_pressed("fps_crouch"), _momentum_time > 0.0)
	if _attack_blocked_until_release:
		_attack_blocked_until_release = Input.is_action_pressed("fps_attack")
	elif Input.is_action_pressed("fps_attack"):
		request_attack()
	move_and_slide()
	motion.after_move(delta)
	_potion_cooldown = maxf(0.0, _potion_cooldown - delta)
	_update_movement_feedback()
	_update_attack(delta)
	var wall_distance: float = _front_obstacle_distance()
	var progress: float = attack_elapsed / attack_duration() if attack_elapsed >= 0.0 else -1.0
	hands.update_pose(delta, Vector2(velocity.x, velocity.z).length(), sprinting, progress, swing_index, equipped_blade(), wall_distance, {
		"grounded": is_on_floor(), "sliding": motion.sliding, "mantling": motion.mantling,
		"wallrunning": motion.wallrunning, "wallrun_side": motion.wallrun_side,
		"stride_phase": _stride_phase, "sharpness": float(_settings.hand_pose_sharpness), "scale": float(_settings.hand_motion_scale)
	})
	var glow_maximum: int = energy_max()
	hands.set_energy_glow(float(energy) / float(glow_maximum) if glow_maximum > 0 else 0.0)
	if global_position.y < -8.0:
		reset_to_spawn(false)
		notice_requested.emit("落水已返回安全点")


func equipped_blade() -> bool:
	return not quick_slots[selected_slot].is_empty()


## 当前武器的充能上限，0 表示该武器没有充能机制。
func energy_max() -> int:
	return int(_weapon.get("energy_max", 0))


func _refresh_weapon() -> void:
	_weapon = _weapons.get(quick_slots[selected_slot], {})
	energy = 0
	attack_elapsed = -1.0
	if hands != null:
		hands.set_weapon(quick_slots[selected_slot])


func assign_quick_slot(index: int, item_id: String) -> void:
	if index < 0 or index >= 5:
		return
	if not item_id.is_empty() and not _weapons.has(item_id):
		return
	if not item_id.is_empty():
		for slot: int in range(5):
			if quick_slots[slot] == item_id:
				quick_slots[slot] = ""
	quick_slots[index] = item_id
	_refresh_weapon()


## 鸣潮刃的冲击波：满格时朝准星方向挥出一道可穿透的宽波。
func release_wave() -> bool:
	if not controls_active or dead or not equipped_blade():
		return false
	if not _weapon.has("wave_damage") or energy < energy_max():
		return false
	energy = 0
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
	return true


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
	if not controls_active or dead or motion.mantling or not equipped_blade() or attack_elapsed >= 0.0:
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
		var offset: Vector3 = destination - origin
		if offset.length() > float(_weapon.range) or forward.dot(offset.normalized()) < min_dot:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, destination, 1, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		_hit_targets[target.get_instance_id()] = true
		var push: Vector3 = (destination - global_position).normalized() * float(_weapon.knockback)
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


func receive_damage(amount: int, source: Vector3) -> bool:
	if dead or not controls_active or hurt_time_left > 0.0:
		return false
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
	_reset_movement_feedback()
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	attack_elapsed = -1.0
	energy = 0
	_momentum_time = 0.0
	hurt_time_left = 0.0
	dead = false
	menu_open = false
	if restore_health:
		health = max_health
		hit_count = 0
		damage_taken = 0
	health_changed.emit(health)
	set_controls_active(true)


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
