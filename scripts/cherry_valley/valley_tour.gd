extends Node3D
## (Claude Code) Optional slow auto-tour: walks the four cinematic anchors on a
## timer so the landscape can be watched hands-free. Any manual camera command
## (C / Q / E / T) cancels it; it never fights the player for control.

signal tour_finished()

var config: Dictionary
var cinematic: Node3D
var active: bool = false
var sizes: Dictionary = {}

var _timer: float = 0.0
var _interval: float = 11.0


func build(cfg: Dictionary, cinematic_node: Node3D) -> void:
	config = cfg
	cinematic = cinematic_node
	_interval = float(cfg.tour.get("interval", 11.0))
	sizes["tour_anchors"] = cinematic.anchors.size()


func start() -> void:
	if cinematic == null or active:
		return
	active = true
	_timer = 0.0
	cinematic.enter(int(config.tour.get("start_shot", 0)))


func stop(exit_camera: bool = true) -> void:
	if not active:
		return
	active = false
	if exit_camera and cinematic != null:
		cinematic.exit()


func toggle() -> bool:
	if active:
		stop()
	else:
		start()
	return active


func _process(delta: float) -> void:
	if not active:
		return
	_timer += delta
	var interval: float = _interval
	if bool(config.scene.get("reduce_motion", false)):
		# More time between cuts reads as calmer, not as a faster slideshow.
		interval *= 1.5
	if _timer >= interval:
		_timer = 0.0
		cinematic.cycle(1)
		if cinematic.current_index == 0:
			tour_finished.emit()
