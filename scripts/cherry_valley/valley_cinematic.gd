extends Node3D
## (Claude Code) Four cinematic camera anchors with eased transitions. The player
## controller is suspended while a shot is active so input does not fight the camera.

signal shot_changed(index: int, label: String)

var config: Dictionary
var anchors: Array[Dictionary] = []
var camera: Camera3D
var active: bool = false
var current_index: int = 0

var _player: Node3D
var _player_camera: Camera3D
var _transition: float = 0.0
var _from_transform: Transform3D
var _from_fov: float = 60.0
var _to_transform: Transform3D
var _to_fov: float = 60.0
var _shot_duration: float = 2.4
## (Claude Code) When the system asks for less motion, locked shots stay still.
var reduce_motion: bool = false


func build(cfg: Dictionary, player_node: Node3D) -> void:
	config = cfg
	_player = player_node
	reduce_motion = bool(cfg.scene.get("reduce_motion", false))
	_player_camera = player_node.get_node("Head/Camera3D") as Camera3D
	camera = Camera3D.new()
	camera.name = "CinematicCamera"
	camera.current = false
	camera.near = 0.05
	camera.far = float(cfg.scene.camera_far)
	add_child(camera)
	anchors.clear()
	for entry: Dictionary in cfg.cinematic:
		var position: Vector3 = _vec(entry.position)
		var target: Vector3 = _vec(entry.target)
		var transform: Transform3D = Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)
		anchors.append({
			"label": str(entry.name),
			"transform": transform,
			"fov": float(entry.fov),
		})


func enter(index: int = 0) -> void:
	if anchors.is_empty():
		return
	active = true
	current_index = clampi(index, 0, anchors.size() - 1)
	# Freeze the player controller: no movement, no mouse look.
	# The free camera is detached from the player body, so a scripted move would
	# not touch the camera; it stays current until the shot ends.
	_player.set_controls_active(false)
	_from_transform = _player_camera.global_transform
	_from_fov = _player_camera.fov
	_transition = 0.0
	_apply_anchor(current_index)
	camera.current = true
	shot_changed.emit(current_index, label())


func exit() -> void:
	if not active:
		return
	active = false
	camera.current = false
	_player_camera.current = true
	_transition = 0.0
	_player.set_controls_active(true)
	_player_camera.fov = float(config.scene.fov_restore if config.scene.has("fov_restore") else 78.0)
	shot_changed.emit(-1, "")


func cycle(step: int) -> void:
	if not active or anchors.is_empty():
		return
	current_index = posmod(current_index + step, anchors.size())
	_from_transform = camera.global_transform
	_from_fov = camera.fov
	_transition = 0.0
	_apply_anchor(current_index)
	shot_changed.emit(current_index, label())


func label() -> String:
	if anchors.is_empty():
		return ""
	return str(anchors[current_index].label)


func _apply_anchor(index: int) -> void:
	var entry: Dictionary = anchors[index]
	_to_transform = entry.transform
	_to_fov = float(entry.fov)


func _process(delta: float) -> void:
	if not active:
		return
	if _transition < 1.0:
		_transition = minf(1.0, _transition + delta / _shot_duration)
		var eased: float = _smoothstep(_transition)
		var position: Vector3 = _from_transform.origin.lerp(_to_transform.origin, eased)
		var rotation: Quaternion = _from_transform.basis.get_rotation_quaternion().slerp(
			_to_transform.basis.get_rotation_quaternion(), eased
		)
		camera.global_transform = Transform3D(Basis(rotation), position)
		camera.fov = lerpf(_from_fov, _to_fov, eased)
	elif not reduce_motion:
		# Slow drift keeps a locked shot from feeling like a still frame.
		camera.global_transform = Transform3D(
			_to_transform.basis,
			_to_transform.origin + _to_transform.basis.y * sin(Time.get_ticks_msec() * 0.00012) * 0.12
		)
	else:
		camera.global_transform = _to_transform


func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
