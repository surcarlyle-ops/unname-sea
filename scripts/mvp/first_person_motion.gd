extends RefCounted
## Collision-aware locomotion. The owner resolves movement once, after prepare().

signal landed(speed: float)
signal mantle_boosted()

var crouching: bool = false
var sliding: bool = false
var mantling: bool = false
var vaulting: bool = false
var wallrunning: bool = false
var profile_id: String = "agile"
var slide_count: int = 0
var mantle_count: int = 0
var step_count: int = 0
var _body: CharacterBody3D
var _head: Node3D
var _camera: Camera3D
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _tuning: Dictionary
var _slide_left: float = 0.0
var _slide_buffer: float = 0.0
var _carrying_momentum: bool = false
var _jump_buffer: float = 0.0
var _coyote: float = 0.0
var _was_grounded: bool = false
var _landed_last_frame: bool = false
var _was_crouch_held: bool = false
var _landing_recovery: float = 0.0
var _mantle_boost_ready: bool = false
var _boost_fov_time: float = 0.0
var _wallrun_time: float = 0.0
var _wallrun_cooldown: float = 0.0
var _wall_jump_window: float = 0.0
## 蹬墙侧：-1 墙在左，1 墙在右。手部系统据此选择扶墙的手。
var wallrun_side: float = 0.0
var _wallrun_view_weight: float = 0.0
var _wallrun_shake_phase: float = 0.0
var _wall_normal: Vector3 = Vector3.ZERO
var _camera_offset: float = 0.0
var _eye_height: float = 1.6
var _vertical_speed: float = 0.0
var _slide_view_weight: float = 0.0
var _slide_view_phase: float = 0.0
var _slide_impact_age: float = 1.0
var _slide_view_kick: float = 0.0
var _view_was_sliding: bool = false
var _camera_base_position: Vector3
var _camera_base_rotation: Vector3
## 跑动镜头起伏：与手部 bob 共用同一个步频相位（由 player 每帧写入）。
var view_stride_phase: float = 0.0
var _bob_weight: float = 0.0
var _mantle_target: Vector3
var _mantle_direction: Vector3
var _mantle_speed: float = 0.0
var _mantle_time: float = 0.0
var _mantle_start: Vector3
var _mantle_elapsed: float = 0.0
var _mantle_duration: float = 0.0


func setup(body: CharacterBody3D, settings: Dictionary) -> void:
	_body = body
	_head = body.get_node("Head") as Node3D
	_camera = _head.get_node("Camera3D") as Camera3D
	_camera_base_position = _camera.position
	_camera_base_rotation = _camera.rotation
	_collision = body.get_node("CollisionShape3D") as CollisionShape3D
	_capsule = _collision.shape.duplicate() as CapsuleShape3D
	_collision.shape = _capsule
	_tuning = settings
	profile_id = str(settings.movement_profile)
	_eye_height = float(settings.standing_eye_height)


func reset() -> void:
	crouching = false
	sliding = false
	mantling = false
	vaulting = false
	wallrunning = false
	_wallrun_time = 0.0
	_wallrun_cooldown = 0.0
	_wall_jump_window = 0.0
	_wallrun_view_weight = 0.0
	_slide_left = 0.0
	_slide_buffer = 0.0
	_carrying_momentum = false
	_jump_buffer = 0.0
	_coyote = 0.0
	_camera_offset = 0.0
	_was_grounded = false
	_landed_last_frame = false
	_was_crouch_held = false
	_landing_recovery = 0.0
	_eye_height = float(_tuning.standing_eye_height)
	_capsule.height = float(_tuning.standing_height)
	_collision.position.y = _capsule.height * 0.5
	_head.position.y = _eye_height
	_camera.fov = float(_tuning.fov)
	_reset_slide_view()
	slide_count = 0
	mantle_count = 0
	step_count = 0


func suspend() -> void:
	mantling = false
	vaulting = false
	sliding = false
	wallrunning = false
	_wallrun_time = 0.0
	_wall_jump_window = 0.0
	_wallrun_view_weight = 0.0
	_slide_buffer = 0.0
	_carrying_momentum = false
	_jump_buffer = 0.0
	_coyote = 0.0
	_reset_slide_view()


func prepare(delta: float, direction: Vector3, sprint: bool, jump_pressed: bool, jump_held: bool, crouch_held: bool, momentum_grace: bool) -> void:
	var grounded: bool = _body.is_on_floor()
	var attached: bool = _body.grapple.is_pulling()
	_landing_recovery = maxf(0.0, _landing_recovery - delta)
	_wallrun_cooldown = maxf(0.0, _wallrun_cooldown - delta)
	_wall_jump_window = maxf(0.0, _wall_jump_window - delta)
	_coyote = float(_tuning.coyote_seconds) if grounded else maxf(0.0, _coyote - delta)
	_jump_buffer = float(_tuning.jump_buffer_seconds) if jump_pressed else maxf(0.0, _jump_buffer - delta)
	var crouch_pressed: bool = crouch_held and not _was_crouch_held
	_was_crouch_held = crouch_held
	_slide_buffer = float(_tuning.slide_buffer_seconds) if crouch_pressed else maxf(0.0, _slide_buffer - delta)
	if not crouch_held:
		_slide_buffer = 0.0
	if attached:
		mantling = false
		vaulting = false
		sliding = false
		_slide_buffer = 0.0
	if momentum_grace:
		_carrying_momentum = true
	var horizontal: Vector3 = Vector3(_body.velocity.x, 0, _body.velocity.z)
	if not sliding and not attached and not mantling and grounded and crouch_held and (_slide_buffer > 0.0 or _landed_last_frame) and horizontal.length() >= float(_tuning.slide_min_speed):
		sliding = true
		_slide_left = float(_tuning.slide_duration)
		_slide_buffer = 0.0
		_carrying_momentum = true
		slide_count += 1
	if sliding:
		_slide_left -= delta
		var downhill: bool = grounded and Vector3.DOWN.slide(_body.get_floor_normal()).dot(horizontal.normalized()) * float(_tuning.gravity) * float(_tuning.slide_slope_acceleration) > float(_tuning.slide_friction)
		if not crouch_held or (_slide_left <= 0.0 and not downhill) or horizontal.length() < float(_tuning.slide_end_speed):
			sliding = false
	# Briefly accept an early slide press without immediately braking into a crouch.
	var awaiting_slide: bool = _slide_buffer > 0.0 and sprint and not direction.is_zero_approx() and not crouching
	_set_stance((crouch_held and not awaiting_slide) or sliding)
	# 攀爬：空中按前进贴墙即可翻上去（Apex 式）；挂钩时同样允许，成功后先松开钩索。
	var wants_climb: bool = _jump_buffer > 0.0 or (jump_held and not grounded) or (not grounded and not direction.is_zero_approx())
	var started_mantle: bool = false
	if not mantling and not crouching and wants_climb and not direction.is_zero_approx():
		if try_mantle(direction):
			started_mantle = true
			if attached:
				_body.grapple.release()
				attached = false
	# 蹬墙跳：蹬墙跑中按跳跃，或离墙后的短暂窗口内补跳，借墙的反作用力弹出去。
	if jump_pressed and (wallrunning or _wall_jump_window > 0.0):
		_do_wall_jump()
	if mantling:
		# 起始攀爬的那一次跳跃不能同时登记翻越冲刺：此前同一帧会置位，导致每次
		# 起跳攀爬都额外 +mantle_jump_boost 冲出去，窄高台上会直接飞过对面掉下去。
		_update_mantle(delta, jump_pressed and not started_mantle)
	elif wallrunning:
		_update_wallrun(delta, direction, grounded)
	elif not attached:
		var speed: float = float(_tuning.crouch_speed) if crouching else movement_speed(direction, sprint)
		if sliding:
			_update_slide(delta, direction, grounded)
		elif grounded and not momentum_grace:
			var target: Vector3 = direction * speed
			var rate: float = float(_tuning.ground_friction if direction.is_zero_approx() else _tuning.ground_acceleration)
			if not direction.is_zero_approx() and horizontal.dot(direction) < 0.0:
				rate = float(_tuning.ground_reverse_acceleration)
			if _carrying_momentum and not direction.is_zero_approx() and horizontal.length() > speed + 0.1:
				# External speed decays separately from steering; ordinary sprint is never external momentum.
				target = direction.normalized() * maxf(speed, horizontal.length() - float(_tuning.overspeed_deceleration) * delta)
			else:
				_carrying_momentum = false
			horizontal = horizontal.move_toward(target, rate * delta)
			# 落地僵直：短暂压低水平速度上限，重落时移动明显变钝。
			if _landing_recovery > 0.0:
				horizontal = horizontal.limit_length(speed * float(_tuning.landing_recovery_speed_scale))
			_body.velocity.x = horizontal.x
			_body.velocity.z = horizontal.z
		else:
			_air_steer(delta, direction, speed)
			# 蹬墙跑：空中带速度贴墙 + 朝墙前进方向即可起跑。
			if _can_start_wallrun(direction, grounded):
				_start_wallrun()
		if _jump_buffer > 0.0 and _coyote > 0.0 and _landing_recovery <= 0.0:
			_body.velocity.y = float(_tuning.jump_speed)
			_jump_buffer = 0.0
			_coyote = 0.0
			_carrying_momentum = _carrying_momentum or sliding
			sliding = false
	if not mantling:
		if wallrunning:
			# 蹬墙跑期间重力大幅降低，形成贴墙滑行而不是直接掉下去。
			_body.velocity.y -= float(_tuning.gravity) * float(_tuning.wallrun_gravity_scale) * delta
			_body.velocity.y = maxf(_body.velocity.y, -float(_tuning.terminal_velocity))
		elif not grounded or _body.velocity.y > 0.0:
			_body.velocity.y -= _effective_gravity() * delta
			# 终端速度兜底：软衰减已让重力趋近 0，这里防止数值穿透。
			_body.velocity.y = maxf(_body.velocity.y, -float(_tuning.terminal_velocity))
		elif _body.velocity.y < 0.0:
			_body.velocity.y = 0.0
		if grounded and not attached and not sliding and _body.velocity.y <= 0.0:
			_try_step_up(delta)
	_vertical_speed = _body.velocity.y


## Apex 式重力：上升偏轻、顶点滞空、下落偏沉，接近终端速度时平滑衰减。
func _effective_gravity() -> float:
	var base: float = float(_tuning.gravity)
	var vy: float = _body.velocity.y
	var scale: float = float(_tuning.gravity_rising_scale) if vy > 0.0 else float(_tuning.gravity_falling_scale)
	# 顶点滞空：垂直速度接近 0 时重力减半，形成短暂漂浮停顿。
	if absf(vy) < float(_tuning.gravity_apex_window):
		scale *= float(_tuning.gravity_apex_scale)
	# 下落接近终端速度：重力线性衰减到 0，落地前保持稳定匀速而不是无限加速。
	if vy < 0.0:
		var fall_speed: float = -vy
		var terminal: float = float(_tuning.terminal_velocity)
		var soft: float = float(_tuning.terminal_soft_zone)
		if fall_speed > terminal - soft:
			scale *= 1.0 - clampf((fall_speed - (terminal - soft)) / soft, 0.0, 1.0)
	return base * scale


func after_move(delta: float) -> void:
	var grounded: bool = _body.is_on_floor()
	_landed_last_frame = grounded and not _was_grounded
	if _landed_last_frame and _vertical_speed < -4.0:
		var impact: float = -_vertical_speed
		# 三档落地：轻落只压一点视线，重落深压后由 step_camera_recovery 回弹。
		var dip: float = float(_tuning.landing_dip_light)
		if impact >= 20.0:
			dip = float(_tuning.landing_dip_heavy)
		elif impact >= 9.0:
			dip = float(_tuning.landing_dip_medium)
		# 同档位内继续按落速加深，避免所有跳跃落地手感一致。
		dip *= clampf(impact / 14.0, 0.55, 1.8)
		_camera_offset -= dip
		# 落地僵直：重落有明显硬直，轻落几乎没有。
		if impact >= 20.0:
			_landing_recovery = float(_tuning.landing_recovery_heavy)
		elif impact >= 9.0:
			_landing_recovery = float(_tuning.landing_recovery_medium)
		landed.emit(impact)
	_was_grounded = grounded
	_update_view(delta)


func _set_stance(want_crouch: bool) -> void:
	if not want_crouch and crouching and not _clear_at(_body.global_position, float(_tuning.standing_height)):
		want_crouch = true
	crouching = want_crouch
	_capsule.height = float(_tuning.crouching_height if crouching else _tuning.standing_height)
	_collision.position.y = _capsule.height * 0.5


func toggle_profile() -> void:
	profile_id = "light_reference" if profile_id == "agile" else "agile"
	_carrying_momentum = false


func profile_name() -> String:
	return str(_tuning.movement_profiles[profile_id].name)


func movement_speed(direction: Vector3, sprint: bool) -> float:
	var profile: Dictionary = _tuning.movement_profiles[profile_id]
	var prefix: String = "sprint_" if sprint else "walk_"
	if direction.is_zero_approx():
		return float(profile[prefix + "forward"])
	var local: Vector3 = _body.global_basis.inverse() * direction.normalized()
	var forward_speed: float = float(profile[prefix + ("forward" if local.z <= 0.0 else "back")])
	var side_speed: float = float(profile[prefix + "side"])
	# An ellipse blends directional limits without a diagonal speed bonus.
	return 1.0 / sqrt(pow(local.x / side_speed, 2.0) + pow(local.z / forward_speed, 2.0))


func _air_steer(delta: float, direction: Vector3, speed: float) -> void:
	if direction.is_zero_approx():
		return
	var horizontal: Vector3 = Vector3(_body.velocity.x, 0, _body.velocity.z)
	var cap: float = maxf(movement_speed(-_body.global_basis.z, true), horizontal.length())
	var gain: float = minf(maxf(0.0, speed - horizontal.dot(direction)), float(_tuning.air_acceleration) * delta)
	horizontal = (horizontal + direction * gain).limit_length(cap)
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z


## 泰坦陨落式蹬墙跑：空中带速度贴墙、且朝墙的走向按键时才能起跑。
func _can_start_wallrun(direction: Vector3, grounded: bool) -> bool:
	if grounded or _wallrun_cooldown > 0.0 or _body.grapple.is_attached():
		return false
	if direction.is_zero_approx():
		return false
	var horizontal: Vector3 = Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if horizontal.length() < float(_tuning.wallrun_min_speed):
		return false
	var right: Vector3 = _body.global_basis.x
	for side: float in [-1.0, 1.0]:
		var origin: Vector3 = _body.global_position + Vector3.UP * 1.0 + right * side * 0.32
		var hit: Dictionary = _ray(origin, origin + right * side * float(_tuning.wallrun_reach))
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal as Vector3
		# 只接受接近垂直的墙面，地板与斜坡不算。
		if absf(normal.y) > 0.30:
			continue
		# 法线必须朝向玩家，否则是背面的墙。
		if normal.dot(right * side) > -0.40:
			continue
		var along: Vector3 = normal.cross(Vector3.UP).normalized()
		if along.dot(horizontal) < 0.0:
			along = -along
		# 前进方向要与墙的走向一致，避免横着撞墙就起跑。
		if along.dot(direction) < 0.35:
			continue
		_wall_normal = normal
		wallrun_side = side
		return true
	return false


func _start_wallrun() -> void:
	wallrunning = true
	_wallrun_time = float(_tuning.wallrun_duration)
	sliding = false
	_carrying_momentum = false
	# 起跑瞬间抵消下落，避免贴墙第一帧就往下坠。
	_body.velocity.y = maxf(_body.velocity.y, 0.0)


func _update_wallrun(delta: float, direction: Vector3, grounded: bool) -> void:
	_wallrun_time -= delta
	var along: Vector3 = _wall_normal.cross(Vector3.UP).normalized()
	var horizontal: Vector3 = Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if along.dot(horizontal) < 0.0:
		along = -along
	var speed: float = horizontal.length()
	var target: float = minf(maxf(speed, float(_tuning.wallrun_min_speed)) + float(_tuning.wallrun_acceleration) * delta, float(_tuning.wallrun_max_speed))
	horizontal = along * target
	# 抵消向外速度，保持贴着墙走。
	var outward: float = horizontal.dot(_wall_normal)
	if outward > 0.0:
		horizontal -= _wall_normal * outward
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z
	# 松开方向、落地、超时或墙面消失即结束。
	var probe_from: Vector3 = _body.global_position + Vector3.UP * 1.0 + _body.global_basis.x * wallrun_side * 0.32
	var still_on_wall: bool = not _ray(probe_from, probe_from + _body.global_basis.x * wallrun_side * (float(_tuning.wallrun_reach) + 0.18)).is_empty()
	if grounded or _wallrun_time <= 0.0 or not still_on_wall or direction.is_zero_approx() or _body.grapple.is_attached():
		_end_wallrun()


func _end_wallrun() -> void:
	if not wallrunning:
		return
	wallrunning = false
	_wallrun_time = 0.0
	_wallrun_cooldown = float(_tuning.wallrun_cooldown)
	# 结束时朝墙外轻推，避免同一面墙连续吸附。
	_body.velocity += _wall_normal * 1.8
	# 空中离墙后留一个短暂窗口，仍可补一次蹬墙跳（对应"松开 W 再按跳跃"）。
	if not _body.is_on_floor():
		_wall_jump_window = float(_tuning.walljump_window)


## Apex 式蹬墙跳：朝墙外弹射，同时保留一部分沿墙速度，形成斜向远跳。
func _do_wall_jump() -> void:
	var outward: Vector3 = _wall_normal
	outward.y = 0.0
	if outward.length_squared() < 0.0001:
		return
	outward = outward.normalized()
	var along: Vector3 = outward.cross(Vector3.UP).normalized()
	var along_speed: float = _body.velocity.dot(along)
	_body.velocity = outward * float(_tuning.walljump_horizontal) + along * along_speed * float(_tuning.walljump_along_keep)
	_body.velocity.y = float(_tuning.walljump_vertical)
	wallrunning = false
	_wallrun_time = 0.0
	_wall_jump_window = 0.0
	_wallrun_cooldown = float(_tuning.wallrun_cooldown)
	_jump_buffer = 0.0
	_coyote = 0.0
	sliding = false
	# 蹬墙跳后的水平速度要保留到落地，不能被普通地面摩擦立刻吃掉。
	_carrying_momentum = true


func _update_slide(delta: float, direction: Vector3, grounded: bool) -> void:
	if not grounded:
		return
	var horizontal: Vector3 = Vector3(_body.velocity.x, 0, _body.velocity.z)
	var speed: float = horizontal.length()
	var heading: Vector3 = horizontal.normalized()
	if not direction.is_zero_approx():
		heading = heading.slerp(direction, minf(float(_tuning.slide_steering) * delta, 1.0)).normalized()
	var slope_gravity: Vector3 = Vector3.DOWN.slide(_body.get_floor_normal()) * float(_tuning.gravity) * float(_tuning.slide_slope_acceleration)
	speed = clampf(speed + (slope_gravity.dot(heading) - float(_tuning.slide_friction)) * delta, 0.0, float(_tuning.slide_max_speed))
	horizontal = heading * speed
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z


func _try_step_up(delta: float) -> void:
	var motion: Vector3 = Vector3(_body.velocity.x, 0, _body.velocity.z) * delta
	if motion.length_squared() < 0.00001:
		return
	var obstruction: KinematicCollision3D = KinematicCollision3D.new()
	if not _body.test_move(_body.global_transform, motion, obstruction) or obstruction.get_normal().y > 0.7:
		return
	var rise: float = float(_tuning.step_height)
	if _body.test_move(_body.global_transform, Vector3.UP * rise):
		return
	var raised: Transform3D = _body.global_transform
	raised.origin.y += rise
	var probe_motion: Vector3 = motion.normalized() * maxf(motion.length(), _capsule.radius + 0.10)
	if _body.test_move(raised, probe_motion):
		return
	raised.origin += probe_motion
	var landing: KinematicCollision3D = KinematicCollision3D.new()
	if not _body.test_move(raised, Vector3.DOWN * (rise + 0.08), landing) or landing.get_normal().y < 0.7:
		return
	var height: float = rise + landing.get_travel().y
	if height < 0.025 or height > rise:
		return
	_body.global_position.y += height
	_camera_offset -= height
	step_count += 1


func try_mantle(direction: Vector3) -> bool:
	if mantling or crouching:
		return false
	var forward: Vector3 = -_body.global_basis.z
	if direction.dot(forward) < 0.5:
		return false
	var origin: Vector3 = _body.global_position
	var wall: Dictionary = _ray(origin + Vector3.UP * 0.55, origin + Vector3.UP * 0.55 + forward * float(_tuning.mantle_reach))
	if wall.is_empty():
		wall = _ray(origin + Vector3.UP * 0.15, origin + Vector3.UP * 0.15 + forward * float(_tuning.mantle_reach))
	if wall.is_empty() or absf(wall.normal.y) > 0.25:
		return false
	var probe: Vector3 = wall.position + forward * (_capsule.radius + 0.16)
	probe.y = origin.y + float(_tuning.mantle_max_height) + 0.10
	var top: Dictionary = _ray(probe, Vector3(probe.x, origin.y + float(_tuning.mantle_min_height) - 0.05, probe.z))
	if top.is_empty() or top.normal.y < 0.7:
		return false
	var rise: float = top.position.y - origin.y
	if rise < float(_tuning.mantle_min_height) or rise > float(_tuning.mantle_max_height):
		return false
	var target: Vector3 = top.position + Vector3.UP * 0.045
	var lifted: Vector3 = Vector3(origin.x, target.y, origin.z)
	if not _clear_at(target, float(_tuning.standing_height)) or not _clear_at(lifted, float(_tuning.standing_height)):
		return false
	var overhead: KinematicCollision3D = KinematicCollision3D.new()
	if _body.test_move(_body.global_transform, lifted - origin, overhead) and overhead.get_normal().y < -0.1:
		return false
	_mantle_target = target
	_mantle_start = origin
	_mantle_direction = forward
	_mantle_speed = clampf(Vector2(_body.velocity.x, _body.velocity.z).length(), float(_tuning.mantle_recovery_speed), movement_speed(forward, true))
	vaulting = rise <= float(_tuning.vault_max_height)
	_mantle_duration = float(_tuning.vault_duration if vaulting else _tuning.mantle_duration) * lerpf(0.8, 1.15, rise / float(_tuning.mantle_max_height))
	_mantle_elapsed = 0.0
	_mantle_time = _mantle_duration + 0.55
	_mantle_boost_ready = false
	mantling = true
	sliding = false
	_jump_buffer = 0.0
	_coyote = 0.0
	_slide_buffer = 0.0
	mantle_count += 1
	return true


func _update_mantle(delta: float, jump_pressed: bool) -> void:
	# 翻越途中按下跳跃即登记一次冲刺，完成瞬间生效。
	if jump_pressed:
		_mantle_boost_ready = true
	_mantle_time -= delta
	if _mantle_time <= 0.0:
		mantling = false
		vaulting = false
		_mantle_boost_ready = false
		_body.velocity = Vector3.ZERO
		return
	_mantle_elapsed += delta
	var progress: float = minf(_mantle_elapsed / _mantle_duration, 1.0)
	var target: Vector3
	if vaulting:
		# Rise early while already moving forward, instead of using an elevator-shaped path.
		target = _mantle_start.lerp(_mantle_target, progress * progress)
		target.y = lerpf(_mantle_start.y, _mantle_target.y, sin(progress * PI * 0.5))
	else:
		var rise_progress: float = smoothstep(0.0, 0.68, progress)
		var forward_progress: float = smoothstep(0.60, 1.0, progress)
		target = _mantle_start.lerp(_mantle_target, forward_progress)
		target.y = lerpf(_mantle_start.y, _mantle_target.y, rise_progress)
	var offset: Vector3 = target - _body.global_position
	if progress >= 1.0 and offset.length() < 0.06:
		mantling = false
		vaulting = false
		var launch: float = _mantle_speed
		if _mantle_boost_ready:
			# Apex 式翻越冲刺：向前额外加速并向上抬起，越过障碍后直接飞出去。
			launch += float(_tuning.mantle_jump_boost)
			_body.velocity.y = float(_tuning.mantle_jump_lift)
			_boost_fov_time = float(_tuning.mantle_boost_duration)
			mantle_boosted.emit()
		else:
			_body.velocity.y = 0.0
		_mantle_boost_ready = false
		_jump_buffer = 0.0
		_coyote = 0.0
		_body.velocity.x = _mantle_direction.x * launch
		_body.velocity.z = _mantle_direction.z * launch
		return
	var travel: Vector3 = offset.limit_length(float(_tuning.traversal_max_speed) * delta)
	var collision: KinematicCollision3D = KinematicCollision3D.new()
	if _body.test_move(_body.global_transform, travel, collision):
		if collision.get_normal().y < -0.1:
			# A moving overhead obstacle aborts traversal instead of pulling the head through it.
			mantling = false
			vaulting = false
			_body.velocity = Vector3.ZERO
			return
		if absf(collision.get_normal().y) < 0.7 and travel.y > 0.0:
			travel = Vector3.UP * travel.y
	_body.velocity = travel / delta


func _update_view(delta: float) -> void:
	var scale: float = clampf(float(_tuning.slide_camera_motion_scale), 0.0, 1.0)
	var grounded_slide: bool = sliding and _body.is_on_floor()
	var blend: float = 1.0 - exp(-float(_tuning.slide_view_sharpness) * delta)
	_slide_view_weight = lerpf(_slide_view_weight, 1.0 if grounded_slide else 0.0, blend)
	if grounded_slide and not _view_was_sliding:
		_slide_view_kick = -float(_tuning.slide_camera_drop) * scale
		_slide_impact_age = 0.0
	_view_was_sliding = grounded_slide
	_slide_view_kick = lerpf(_slide_view_kick, 0.0, blend)
	var target_height: float = float(_tuning.crouching_eye_height if crouching else _tuning.standing_eye_height)
	if sliding:
		target_height = lerpf(target_height, float(_tuning.slide_eye_height), scale)
	_eye_height = lerpf(_eye_height, target_height, minf(float(_tuning.stance_sharpness) * delta, 1.0))
	_head.position.y = _eye_height + _camera_offset + _slide_view_kick
	_camera_offset = move_toward(_camera_offset, 0.0, float(_tuning.step_camera_recovery) * delta)
	var speed: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	# One short entry impulse; sustained sliding has no periodic vibration.
	_slide_impact_age += delta
	_slide_view_phase = minf(_slide_impact_age / 0.18, 1.0) * TAU
	var weight: float = _slide_view_weight * scale
	var envelope: float = pow(maxf(0.0, 1.0 - _slide_impact_age / 0.18), 2.0)
	var shake: float = float(_tuning.slide_camera_shake) * scale * envelope * clampf(speed / 8.2, 0.0, 1.0)
	# 蹬墙跑的倾斜权重。
	var wallrun_blend: float = 1.0 - exp(-float(_tuning.wallrun_camera_sharpness) * delta)
	_wallrun_view_weight = lerpf(_wallrun_view_weight, 1.0 if wallrunning else 0.0, wallrun_blend)
	# 蹬墙跑高频抖动：模拟鞋底蹭墙的震动，两个不同频率叠加避免机械感。
	_wallrun_shake_phase = fmod(_wallrun_shake_phase + delta * 26.0, TAU * 1000.0)
	var wallrun_shake: float = float(_tuning.wallrun_camera_shake) * _wallrun_view_weight
	var wallrun_offset: Vector3 = Vector3.ZERO
	if wallrun_shake > 0.0001:
		wallrun_offset = Vector3(sin(_wallrun_shake_phase * 1.7) * wallrun_shake, sin(_wallrun_shake_phase * 2.3) * wallrun_shake * 0.8, 0.0)
	# 跑动镜头起伏：跟手部 bob 同一个步频相位（一个相位 = 两步），
	# 竖直每步一次起伏、横向每两步一次摆动，滑铲/攀爬/蹬墙/空中淡出。
	var bob: Dictionary = _tuning.get("camera_bob", {}) as Dictionary
	var bob_vertical: float = 0.0
	var bob_horizontal: float = 0.0
	var bob_forward: float = 0.0
	var bob_pitch: float = 0.0
	var bob_yaw: float = 0.0
	var bob_roll: float = 0.0
	if not bob.is_empty():
		var bob_allowed: bool = _body.is_on_floor() and not sliding and not mantling and not wallrunning
		# 参考速度取当前移动档的冲刺速度，换档时幅度自动跟着变。
		var reference: float = maxf(movement_speed(-_body.global_basis.z, true), 0.1)
		var bob_target: float = clampf(speed / reference, 0.0, 1.2) if bob_allowed else 0.0
		_bob_weight = lerpf(_bob_weight, bob_target, 1.0 - exp(-float(bob.get("sharpness", 8.0)) * delta))
		# 停下后残余权重归零：否则镜头永远差几十分之一毫米，回不到"普通姿态"。
		if bob_target <= 0.0 and _bob_weight < 0.01:
			_bob_weight = 0.0
		# 一个相位 = 两步：step_wave 每步一次（落地/抬头），sway_wave 每两步一次（左右）。
		var step_wave: float = sin(view_stride_phase * 2.0)
		var sway_wave: float = cos(view_stride_phase)
		bob_vertical = step_wave * float(bob.get("vertical", 0.0)) * _bob_weight
		bob_forward = -step_wave * float(bob.get("forward", 0.0)) * _bob_weight
		bob_horizontal = sway_wave * float(bob.get("horizontal", 0.0)) * _bob_weight
		# 俯仰/偏航是"像 Apex 那样走路在晃"的主因：远景上纯位移几乎看不出来。
		bob_pitch = step_wave * deg_to_rad(float(bob.get("pitch_degrees", 0.0))) * _bob_weight
		bob_yaw = sway_wave * deg_to_rad(float(bob.get("yaw_degrees", 0.0))) * _bob_weight
		bob_roll = sway_wave * deg_to_rad(float(bob.get("roll_degrees", 0.0))) * _bob_weight
	_camera.position = _camera_base_position + Vector3(sin(_slide_view_phase) * shake * 0.5 + bob_horizontal, sin(_slide_view_phase * 2.0) * shake + bob_vertical, float(_tuning.slide_camera_back) * weight + bob_forward) + wallrun_offset
	# 蹬墙跑：镜头朝墙的外侧倾斜（身体贴墙、重心偏向墙外）。
	var wallrun_roll: float = deg_to_rad(float(_tuning.wallrun_camera_roll_degrees)) * _wallrun_view_weight * wallrun_side
	# Roll changes posture without steering the forward aiming direction or mouse pitch.
	var slide_pitch: float = sin(_slide_view_phase * 1.43) * shake * 0.65
	_camera.rotation = _camera_base_rotation + Vector3(slide_pitch + bob_pitch, bob_yaw, deg_to_rad(float(_tuning.slide_camera_roll_degrees)) * (-weight + envelope * scale * sin(_slide_view_phase) * 0.30) + wallrun_roll + bob_roll)
	var walk: float = movement_speed(-_body.global_basis.z, false)
	var sprint: float = movement_speed(-_body.global_basis.z, true)
	var amount: float = clampf((speed - walk) / maxf(sprint - walk, 0.1), 0.0, 1.0)
	var target_fov: float = float(_tuning.fov) + amount * float(_tuning.sprint_fov_add) + float(_tuning.slide_camera_fov_add) * weight
	# 翻越冲刺：短暂拉宽视野，强化"冲出去"的速度感。
	_boost_fov_time = maxf(0.0, _boost_fov_time - delta)
	if _boost_fov_time > 0.0:
		var boost_ratio: float = _boost_fov_time / maxf(float(_tuning.mantle_boost_duration), 0.01)
		target_fov += float(_tuning.mantle_boost_fov_add) * boost_ratio
	_camera.fov = lerpf(_camera.fov, target_fov, minf(float(_tuning.camera_sharpness) * delta, 1.0))


func _reset_slide_view() -> void:
	_slide_impact_age = 1.0
	_slide_view_weight = 0.0
	_wallrun_view_weight = 0.0
	_wallrun_shake_phase = 0.0
	_slide_view_phase = 0.0
	_slide_view_kick = 0.0
	_view_was_sliding = false
	_bob_weight = 0.0
	_camera.position = _camera_base_position
	_camera.rotation = _camera_base_rotation
	_camera.fov = float(_tuning.fov)
	_head.position.y = _eye_height + _camera_offset


func _clear_at(feet: Vector3, height: float) -> bool:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = _capsule.radius
	shape.height = height
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height * 0.5 + 0.015))
	query.collision_mask = _body.collision_mask
	query.exclude = [_body.get_rid()]
	query.margin = 0.005
	return _body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [_body.get_rid()])
	return _body.get_world_3d().direct_space_state.intersect_ray(query)
