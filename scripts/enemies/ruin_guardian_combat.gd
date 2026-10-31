extends "res://scripts/enemies/ruin_guardian.gd"
## Combat wrapper around the verified root-motion guardian. The preview stays reusable.

signal defeated(enemy: Node3D)
signal health_changed(value: int)
signal damage_received(amount: int, point: Vector3, armored: bool)

enum State { CHASE, WINDUP, DASH, RECOVERY, DEAD }
const FIST_SOLID_SCRIPT: Script = preload("res://scripts/enemies/guardian_stone_fist.gd")
const MOTION_SCRIPT: Script = preload("res://scripts/enemies/guardian_procedural_motion.gd")

var target: CharacterBody3D
var tuning: Dictionary = {}
var stats: Dictionary = {}
var health: int = 300
var max_health: int = 300
var dead: bool = false
var state: State = State.CHASE
var attack_count: int = 0
var _cooldown: float = 0.7
var _hit_this_attack: bool = false
var _idle_pending: bool = false
var _death_time: float = 0.0
var _flash_time: float = 0.0
var _fist_bone: int = -1
var _meshes: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D
var _warning: MeshInstance3D
var _warning_material: StandardMaterial3D
var _knockback: Vector3 = Vector3.ZERO
var _warning_anchor: Transform3D = Transform3D.IDENTITY
var solid_fist: AnimatableBody3D
var solid_parts: Array[AnimatableBody3D] = []
var motion: RefCounted
var attack_kind: String = "charge"
var _close_elapsed: float = 0.0
var _close_count: int = 0
var _slam_center: Vector3 = Vector3.ZERO
var _shockwave: MeshInstance3D
var _charge_stopped: bool = false


func _ready() -> void:
	size_multiplier = maxf(0.1, float(tuning.get("size_multiplier", 2.0)))
	super._ready()
	add_to_group("mvp_enemies")
	collision_mask = 7
	floor_snap_length = 0.3
	gravity = float(tuning.get("gravity", 22.0))
	windup_skip = float(tuning.get("windup_skip", 1.6))
	attack_speed = maxf(0.1, float(tuning.get("attack_speed", 1.3)))
	max_health = int(stats.get("hp", 300))
	health = max_health
	_fist_bone = skeleton.find_bone("stone_hammer") if skeleton != null else -1
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 0.91, 0.66, 0.65)
	_build_warning()
	attack_finished.connect(_on_attack_finished)
	_set_idle_pose()
	process_physics_priority = -10
	solid_fist = AnimatableBody3D.new()
	solid_fist.name = "SolidStoneFist"
	solid_fist.set_script(FIST_SOLID_SCRIPT)
	solid_fist.guardian = self
	add_child(solid_fist)
	solid_parts.append(solid_fist)
	# The visible rigid limbs are also melee/bullet hurt regions, not just the torso capsule.
	for bone_name: String in ["forearm_light", "foot_heavy", "foot_light", "upper_arm_heavy", "upper_arm_light", "chest", "pelvis", "thigh_heavy", "shin_heavy", "thigh_light", "shin_light"]:
		var part: AnimatableBody3D = AnimatableBody3D.new()
		part.name = "Solid_" + bone_name
		part.set_script(FIST_SOLID_SCRIPT)
		part.guardian = self
		part.bone_name = StringName(bone_name)
		add_child(part)
		solid_parts.append(part)
	motion = MOTION_SCRIPT.new()
	motion.setup(self)
	_build_shockwave()


func _physics_process(delta: float) -> void:
	_update_flash(delta)
	if dead:
		_death_time += delta
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		if _death_time >= float(tuning.get("death_linger", 1.3)):
			queue_free()
		return
	if global_position.y < -8.0:
		_die()
		return
	if not is_instance_valid(target) or not target.controls_active or target.dead:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	if attacking:
		if attack_kind != "charge":
			_process_close_attack(delta)
			return
		var previous_time: float = clip_time()
		var previous_fist: Vector3 = fist_position()
		var before_move: Vector3 = global_position
		var saved_multiplier: float = root_motion_multiplier
		if _charge_stopped:
			root_motion_multiplier = 0.0
		super._physics_process(delta)
		root_motion_multiplier = saved_multiplier
		if clip_time() >= DASH_WINDOW.x and clip_time() <= DASH_WINDOW.y and global_position.distance_to(before_move) < 0.001:
			for i: int in range(get_slide_collision_count()):
				if absf(get_slide_collision(i).get_normal().y) < 0.5:
					_charge_stopped = true
		_update_state()
		if previous_time <= DAMAGE_WINDOW.y and clip_time() >= DAMAGE_WINDOW.x:
			_try_damage(previous_fist, fist_position())
		_update_warning()
		return
	if _idle_pending:
		_set_idle_pose()
		_idle_pending = false
	_cooldown = maxf(0.0, _cooldown - delta)
	var toward: Vector3 = target.global_position - global_position
	toward.y = 0.0
	var distance: float = toward.length()
	var desired: Vector3 = Vector3.ZERO
	var reachable_height: bool = absf(target.global_position.y - global_position.y) < float(tuning.get("target_height", 2.0))
	var visible_target: bool = _line_clear(global_position + Vector3.UP, target.global_position + Vector3.UP)
	var melee_range: float = float(tuning.get("melee_range", 4.0))
	var can_charge: bool = distance >= float(tuning.get("charge_min_range", 8.0)) and distance <= float(tuning.get("charge_max_range", 22.0))
	if reachable_height and visible_target and _cooldown <= 0.0 and (distance <= melee_range or can_charge):
		rotation.y = atan2(toward.x, toward.z)
		if can_charge:
			play_attack()
		else:
			_close_count += 1
			start_close_attack("slam" if _close_count % 3 == 0 else "swing")
		_update_warning()
		return
	elif distance > melee_range * 0.8 and distance <= float(tuning.get("aggro_range", 28.0)):
		desired = _steer(toward.normalized()) * float(tuning.get("walk_speed", 3.15))
		if desired.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(desired.x, desired.z), minf(delta * 4.0, 1.0))
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 8.0)
	velocity.x = move_toward(velocity.x, desired.x + _knockback.x, delta * 12.0)
	velocity.z = move_toward(velocity.z, desired.z + _knockback.z, delta * 12.0)
	_apply_gravity(delta)
	move_and_slide()
	motion.walk(delta, Vector2(velocity.x, velocity.z).length())
	_update_warning()


func _steer(direction: Vector3) -> Vector3:
	for angle: float in [0.0, -0.8, 0.8, -1.5, 1.5]:
		var candidate: Vector3 = direction.rotated(Vector3.UP, angle)
		if not test_move(global_transform, candidate * 0.8):
			# Avoid walking off ledges while chasing a player on a different platform.
			var probe: Vector3 = global_position + candidate + Vector3.UP * 0.5
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(probe, probe - Vector3.UP * 1.4, 1)
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				return candidate
	return Vector3.ZERO


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func fist_position() -> Vector3:
	if is_instance_valid(solid_fist):
		return skeleton.global_transform * skeleton.get_bone_global_pose(_fist_bone) * (solid_fist._center / (MODEL_SCALE * size_multiplier))
	if _fist_bone >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(_fist_bone) * Vector3(0.0, float(tuning.get("fist_offset", 0.20)), 0.0)
	return global_position + global_basis.z * 1.0 + Vector3.UP


func damage_point() -> Vector3:
	# Large enemies remain hittable at leg height by a first-person melee weapon.
	return global_position + Vector3.UP * minf(BODY_HEIGHT * size_multiplier * 0.5, 1.2)


func _try_damage(from: Vector3, to: Vector3) -> void:
	if dead or _hit_this_attack or not is_instance_valid(target) or target.dead:
		return
	var radius: float = float(tuning.get("fist_radius", 0.82)) * size_multiplier
	var length: float = from.distance_to(to)
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = radius
	shape.height = length + radius * 2.0
	var orientation: Basis = Basis.IDENTITY
	if length > 0.0001:
		orientation = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(orientation, (from + to) * 0.5)
	query.collision_mask = 4
	query.exclude = [get_rid()]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
		if hit.get("collider") != target:
			continue
		# Check from the body as well as the fist so a protruding visual cannot hit through a wall.
		var aim: Vector3 = target.global_position + Vector3.UP * 0.9
		if not _line_clear(global_position + Vector3.UP, aim) or not _line_clear(to, aim):
			continue
		_hit_this_attack = true
		if target.receive_damage(int(stats.get("attack", 22)), global_position):
			attack_count += 1
		return


func _update_state() -> void:
	if dead or not attacking:
		return
	state = State.WINDUP if clip_time() < DASH_WINDOW.x else (State.DASH if clip_time() < DASH_WINDOW.y else State.RECOVERY)


func phase_label() -> String:
	if dead:
		return "已击败"
	if attacking and attack_kind != "charge":
		if state == State.WINDUP:
			return "蓄力砸地 · 跳跃避开地波" if attack_kind == "slam" else "抬拳 · 后撤或侧移"
		if state == State.DASH:
			return "砸地" if attack_kind == "slam" else "石拳横扫"
		return "收招 · 可以反击"
	match state:
		State.WINDUP: return "蓄力 · 侧向避让"
		State.DASH: return "冲刺 · 注意石拳"
		State.RECOVERY: return "收招 · 可以反击"
	return "正在接近"


func _on_attack_finished() -> void:
	state = State.CHASE
	_cooldown = float(tuning.get("attack_cooldown", 0.6923077))
	_idle_pending = true
	_update_warning()


func play_attack() -> void:
	if dead:
		return
	_hit_this_attack = false
	attack_kind = "charge"
	_charge_stopped = false
	if motion != null:
		motion.reset_pose()
	var distance: float = global_position.distance_to(target.global_position) if is_instance_valid(target) else 8.0
	var base_distance: float = absf(travel_units) * MODEL_SCALE * size_multiplier
	root_motion_multiplier = clampf(distance - float(tuning.get("charge_stop_distance", 2.3)), 2.0, float(tuning.get("charge_max_distance", 18.0))) / maxf(base_distance, 0.01)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(float(tuning.get("telegraph_width", 2.0)) * size_multiplier, world_lunge() + 1.0)
	_warning.mesh = plane
	_idle_pending = false
	state = State.WINDUP
	super.play_attack()
	_warning_anchor = global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.035, world_lunge() * 0.5 + 0.5))
	_update_warning()


func start_close_attack(kind: String) -> void:
	if dead:
		return
	attack_kind = kind
	attacking = true
	_hit_this_attack = false
	_idle_pending = false
	_close_elapsed = 0.0
	_window_open = false
	state = State.WINDUP
	motion.reset_pose()
	_slam_center = global_position + global_basis.z * 1.7
	_slam_center.y = global_position.y + 0.04
	if kind == "slam":
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = float(tuning.slam_radius)
		disc.bottom_radius = float(tuning.slam_radius)
		disc.height = 0.012
		disc.radial_segments = 64
		_warning.mesh = disc
		_warning_anchor = Transform3D(Basis.IDENTITY, _slam_center)
	else:
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(5.0, float(tuning.melee_range))
		_warning.mesh = plane
		_warning_anchor = global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 2))
	_update_warning()


func cancel_attack() -> void:
	super.cancel_attack()
	if not dead:
		state = State.CHASE
	root_motion_multiplier = 1.0
	_close_elapsed = 0.0
	_charge_stopped = false
	if motion != null:
		motion.reset_pose()
	if _shockwave != null:
		_shockwave.visible = false
	if _warning != null:
		_warning.visible = false


func _process_close_attack(delta: float) -> void:
	var previous_fist: Vector3 = fist_position()
	var previous_time: float = _close_elapsed
	_close_elapsed += delta * attack_speed
	var windup: float = float(tuning[attack_kind + "_windup"])
	var active: float = float(tuning[attack_kind + "_active"])
	var recovery: float = float(tuning[attack_kind + "_recovery"])
	state = State.WINDUP if _close_elapsed < windup else (State.DASH if _close_elapsed < windup + active else State.RECOVERY)
	_window_open = state == State.DASH
	motion.attack(attack_kind, _close_elapsed, windup, active, recovery)
	var step_velocity: Vector3 = Vector3.ZERO
	if attack_kind == "swing":
		var step: float = smoothstep(windup, windup + active, _close_elapsed) - smoothstep(windup, windup + active, previous_time)
		step_velocity = global_basis.z * step * float(tuning.swing_step_distance) / maxf(delta, 0.001)
	velocity.x = step_velocity.x
	velocity.z = step_velocity.z
	_apply_gravity(delta)
	move_and_slide()
	if attack_kind == "swing" and previous_time <= windup + active and _close_elapsed >= windup:
		_try_damage(previous_fist, fist_position())
	if attack_kind == "slam" and _close_elapsed >= windup + active * 0.7:
		_update_slam_wave(previous_time, windup + active * 0.7)
	_update_warning()
	if _close_elapsed >= windup + active + recovery:
		attacking = false
		_window_open = false
		_shockwave.visible = false
		_on_attack_finished()


func _build_shockwave() -> void:
	_shockwave = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.90
	ring.outer_radius = 1.0
	ring.rings = 40
	ring.ring_segments = 8
	_shockwave.mesh = ring
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.9, 0.61, 0.24)
	_shockwave.material_override = material
	_shockwave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shockwave.top_level = true
	_shockwave.visible = false
	add_child(_shockwave)


func _update_slam_wave(previous_time: float, start_time: float) -> void:
	var duration: float = float(tuning.slam_wave_duration)
	var now: float = clampf((_close_elapsed - start_time) / duration, 0, 1)
	var before: float = clampf((previous_time - start_time) / duration, 0, 1)
	var radius: float = float(tuning.slam_radius)
	_shockwave.visible = now < 1.0
	_shockwave.global_position = _slam_center + Vector3.UP * 0.06
	_shockwave.scale = Vector3(maxf(0.05, now * radius), 0.18, maxf(0.05, now * radius))
	if _hit_this_attack or now >= 1.0 and before >= 1.0:
		return
	var distance: float = Vector2(target.global_position.x - _slam_center.x, target.global_position.z - _slam_center.z).length()
	var height: float = target.global_position.y - global_position.y
	if distance >= before * radius - 0.40 and distance <= now * radius + 0.40 and height >= -0.4 and height < float(tuning.slam_jump_height) and _line_clear(_slam_center + Vector3.UP * 0.3, target.global_position + Vector3.UP * 0.3):
		_hit_this_attack = true
		if target.receive_damage(int(stats.get("attack", 22)), _slam_center):
			attack_count += 1


func _set_idle_pose() -> void:
	animation_player.play(CLIP_NAME, 0.0)
	animation_player.seek(0.0, true)
	animation_player.pause()
	model.position = Vector3.ZERO
	_elapsed = 0.0


func apply_damage(amount: int, push: Vector3) -> void:
	apply_part_damage(amount, push, "body")


func apply_damage_at(amount: int, push: Vector3, point: Vector3) -> void:
	var low_armor: float = float(tuning.get("foot_armor_height", 0.16)) * MODEL_SCALE * size_multiplier
	apply_part_damage(amount, push, "foot_heavy" if point.y - global_position.y < low_armor else "body")


func apply_part_damage(amount: int, push: Vector3, part: String) -> void:
	if dead or amount <= 0:
		return
	var multiplier: float = float(tuning.get("hard_part_damage_multiplier", 0.5)) if part in ["stone_hammer", "forearm_light", "foot_heavy", "foot_light"] else 1.0
	var normal_damage: int = maxi(amount - int(stats.get("defense", 1)), 1)
	var loss: int = mini(health, maxi(roundi(normal_damage * multiplier), 1))
	health -= loss
	var point: Vector3 = damage_point()
	for solid: AnimatableBody3D in solid_parts:
		if solid.bone_name == part:
			point = solid.world_center()
			break
	damage_received.emit(loss, point, multiplier < 1.0)
	_flash_time = 0.10
	health_changed.emit(health)
	# A heavy boss is not stun-locked by every sword hit; the committed dash keeps its course.
	if not attacking:
		_knockback = Vector3(push.x, 0.0, push.z) * float(tuning.get("knockback_scale", 0.12))
	if health == 0:
		_die()


func melee_contact(origin: Vector3, forward: Vector3, reach: float, min_dot: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var direct: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + forward * reach, 3))
	if not direct.is_empty() and _owns_collider(direct.collider):
		return _contact_record(direct)
	var candidates: Array[Vector3] = [damage_point()]
	for part: AnimatableBody3D in solid_parts:
		var nearest: Vector3 = part.world_center()
		var nearest_distance: float = INF
		for local_point: Vector3 in part.solid_shape.points:
			var point: Vector3 = part.global_transform * local_point
			var offset: Vector3 = point - origin
			var distance: float = offset.length()
			if distance < nearest_distance and distance <= reach and forward.dot(offset.normalized()) >= min_dot:
				nearest_distance = distance
				nearest = point
		if nearest_distance < INF:
			candidates.append(nearest)
	var best: Dictionary = {}
	var best_distance: float = INF
	for destination: Vector3 in candidates:
		var offset: Vector3 = destination - origin
		if offset.length() > reach or forward.dot(offset.normalized()) < min_dot:
			continue
		var ray: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, destination + offset.normalized() * 0.04, 3))
		if not ray.is_empty() and _owns_collider(ray.collider) and origin.distance_to(ray.position) < best_distance:
			best = _contact_record(ray)
			best_distance = origin.distance_to(ray.position)
	return best


func _owns_collider(collider: Object) -> bool:
	return collider == self or collider in solid_parts


func _contact_record(hit: Dictionary) -> Dictionary:
	var part: String = "body"
	if hit.collider != self:
		part = str(hit.collider.bone_name)
	elif hit.position.y - global_position.y < float(tuning.foot_armor_height) * MODEL_SCALE * size_multiplier:
		part = "foot_heavy"
	return {"position": hit.position, "part": part}


func _die() -> void:
	if dead:
		return
	dead = true
	health = 0
	state = State.DEAD
	attacking = false
	_window_open = false
	damage_window_closed.emit()
	animation_player.pause()
	collision_layer = 0
	collision_mask = 1
	remove_from_group("mvp_enemies")
	_warning.visible = false
	if _shockwave != null:
		_shockwave.visible = false
	for part: MeshInstance3D in _meshes:
		part.material_overlay = null
	var collapse: Tween = create_tween().set_parallel(true)
	collapse.tween_property(model, "rotation:x", -0.45, 0.6)
	collapse.tween_property(model, "position:y", -0.35, 0.7)
	defeated.emit(self)


func _update_flash(delta: float) -> void:
	_flash_time = maxf(0.0, _flash_time - delta)
	for part: MeshInstance3D in _meshes:
		part.material_overlay = _flash_material if _flash_time > 0.0 and not dead else null


func _build_warning() -> void:
	_warning = MeshInstance3D.new()
	_warning.name = "ChargeTelegraph"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(float(tuning.get("telegraph_width", 2.0)) * size_multiplier, world_lunge() + 1.0)
	_warning.mesh = plane
	_warning.position = Vector3(0.0, 0.035, world_lunge() * 0.5 + 0.5)
	_warning_material = StandardMaterial3D.new()
	_warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_warning.material_override = _warning_material
	_warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warning.visible = false
	add_child(_warning)


func _update_warning() -> void:
	_warning.visible = attacking and state in [State.WINDUP, State.DASH]
	if attacking:
		_warning.global_transform = _warning_anchor
	_warning_material.albedo_color = Color(1.0, 0.3, 0.19, 0.23) if state == State.DASH else Color(1.0, 0.69, 0.26, 0.19)
