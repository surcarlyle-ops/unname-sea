extends Control
## APEX-style crosshair.
## Blue when the grapple can attach, yellow when it cannot, red while attached,
## gray while cooling down, with a cooldown arc around the center.

@export var hook_path: NodePath
@export var cannot_color: Color = Color(0.66, 0.62, 0.77)
@export var ready_color: Color = Color(0.91, 0.79, 0.55)
@export var attached_color: Color = Color(0.88, 0.48, 0.42)
@export var cooldown_color: Color = Color(0.35, 0.32, 0.44)
@export var gap: float = 6.0
@export var tick_length: float = 10.0
@export var thickness: float = 2.0

var _hook: GrappleHook
var _pulse: float = 0.0


func _ready() -> void:
	if hook_path != NodePath():
		_hook = get_node_or_null(hook_path) as GrappleHook
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var color: Color = cannot_color
	var attached: bool = false
	var ready: bool = true

	if _hook != null:
		attached = _hook.is_attached()
		ready = _hook.is_ready()
		if attached:
			color = attached_color
		elif not ready:
			color = cooldown_color
		elif _hook.can_attach():
			color = ready_color

	# Four ticks.
	draw_line(center + Vector2(-gap - tick_length, 0.0), center + Vector2(-gap, 0.0), color, thickness)
	draw_line(center + Vector2(gap, 0.0), center + Vector2(gap + tick_length, 0.0), color, thickness)
	draw_line(center + Vector2(0.0, -gap - tick_length), center + Vector2(0.0, -gap), color, thickness)
	draw_line(center + Vector2(0.0, gap), center + Vector2(0.0, gap + tick_length), color, thickness)
	draw_circle(center, 1.5, color)

	if _hook == null:
		return

	# Ready ring hints that the current aim is within grapple range.
	if ready and _hook.can_attach():
		draw_arc(center, 22.0, 0.0, TAU, 32, Color(color, 0.35), 1.0)

	# Attached ring breathes gently.
	if attached:
		var breath: float = 1.0 + sin(_pulse * 6.0) * 0.08
		draw_arc(center, 20.0 * breath, 0.0, TAU, 32, Color(color, 0.5), 1.5)

	# Cooldown arc fills back up as the hook recovers.
	if not ready and not attached:
		var remaining: float = _hook.cooldown_ratio()
		if remaining > 0.0:
			draw_arc(center, 18.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - remaining), 32, cooldown_color, 2.0)
