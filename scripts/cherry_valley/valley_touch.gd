extends Control
## (Claude Code) Touch layer for phones: a floating joystick on the left half and
## a look-drag pad on the right. Mouse input is ignored, so desktop is untouched.
## The joystick feeds the player through a small override hook, and the look pad
## rotates the head directly; both are inert while cinematic shots are active.
##
## Layout is anchored to the safe area, so notches and gesture bars never clip
## the controls.

const COL_BASE: Color = Color(0.94, 0.93, 0.97, 0.35)
const COL_KNOB: Color = Color(0.98, 0.84, 0.62, 0.72)

var config: Dictionary
var player: CharacterBody3D
var enabled: bool = false
var sizes: Dictionary = {}

var move_vector: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO

var _left_touch: int = -1
var _look_touch: int = -1
var _knob_origin: Vector2 = Vector2.ZERO
var _knob_position: Vector2 = Vector2.ZERO
var _look_anchor: Vector2 = Vector2.ZERO
var _radius: float = 92.0
var _look_sensitivity: float = 2.2
var _active: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Touch input must reach this Control even under the HUD's full-rect node.
	set_process_input(true)


func build(cfg: Dictionary, player_node: CharacterBody3D) -> void:
	config = cfg
	player = player_node
	enabled = bool(cfg.touch.get("enabled", true)) and DisplayServer.is_touchscreen_available()
	_radius = float(cfg.touch.get("joystick_radius", 92.0))
	_look_sensitivity = float(cfg.touch.get("look_sensitivity", 2.2))
	sizes["touch_enabled"] = enabled


func set_active(value: bool) -> void:
	_active = value
	move_vector = Vector2.ZERO
	if player != null and player.has_method("set_touch_move"):
		player.set_touch_move(Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			if touch.position.x < size.x * 0.5 and _left_touch == -1:
				_left_touch = touch.index
				_knob_origin = touch.position
				_knob_position = touch.position
			elif _look_touch == -1:
				_look_touch = touch.index
				_look_anchor = touch.position
		else:
			if touch.index == _left_touch:
				_left_touch = -1
				move_vector = Vector2.ZERO
				_push_move()
			elif touch.index == _look_touch:
				_look_touch = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _left_touch:
			var offset: Vector2 = drag.position - _knob_origin
			if offset.length() > _radius:
				# Floating stick: the base follows so the knob never runs away.
				_knob_origin += offset - offset.normalized() * _radius
				offset = offset.normalized() * _radius
			_knob_position = _knob_origin + offset
			move_vector = offset / _radius
			_push_move()
		elif drag.index == _look_touch:
			look_delta += drag.relative
			if _active:
				_apply_look(drag.relative)


func _push_move() -> void:
	if player != null and player.has_method("set_touch_move") and _active:
		player.set_touch_move(move_vector)


func _apply_look(relative: Vector2) -> void:
	if player == null:
		return
	var head: Node3D = player.get_node_or_null("Head")
	if head == null:
		return
	var scale: float = 0.0028 * _look_sensitivity
	head.rotation.y -= relative.x * scale
	head.rotation.x = clampf(head.rotation.x - relative.y * scale, -1.45, 1.45)


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	if _left_touch != -1:
		draw_circle(_knob_origin, _radius, Color(COL_BASE, COL_BASE.a * 0.5))
		draw_arc(_knob_origin, _radius, 0.0, TAU, 40, Color(COL_BASE, COL_BASE.a * 0.7), 2.0)
		draw_circle(_knob_position, _radius * 0.42, COL_KNOB)
	else:
		# Idle hint: a faint ring where the thumb naturally rests.
		var hint: Vector2 = Vector2(_radius + 28.0, size.y - _radius - 28.0)
		draw_arc(hint, _radius, 0.0, TAU, 40, Color(COL_BASE, COL_BASE.a * 0.45), 2.0)
