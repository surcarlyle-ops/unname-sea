extends SceneTree
## (Claude Code) Headless structural checks for the cherry valley scene.
## Mirrors the existing tests/*.gd SceneTree pattern: build the real scene, inspect
## the nodes, drive the mood/quality/shot switches, then quit with a pass/fail code.

var checks: int = 0
var failures: int = 0
var world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		push_error("Cherry valley test timeout")
		quit(2)
	)
	var scene: PackedScene = load("res://scenes/cherry_valley.tscn") as PackedScene
	world = scene.instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var waited: int = 0
	while not bool(world.build_complete) and waited < 1200:
		await process_frame
		waited += 1
	_check(bool(world.build_complete), "Valley builds to completion")

	# Terrain
	var terrain: Node3D = world.terrain
	_check(terrain != null, "Terrain node exists")
	_check(int(terrain.sizes.get("terrain_triangles", 0)) > 20000, "Terrain mesh has a full valley surface")
	var collision: Node = terrain.get_node_or_null("TerrainCollision")
	_check(collision is StaticBody3D, "Terrain collision body exists")
	if collision is StaticBody3D:
		var shape_node: Node = (collision as StaticBody3D).get_child(0)
		_check(shape_node is CollisionShape3D and (shape_node as CollisionShape3D).shape is HeightMapShape3D,
			"Terrain collision uses HeightMapShape3D")

	# Water
	var water: Node3D = world.water
	_check(water != null and water.surface != null, "River surface exists")
	_check(water.surface.material_override is ShaderMaterial, "River uses the custom ripple shader")
	_check(water.get_node_or_null("RiverBankBlocker") != null, "River banks block walking on the bed")
	_check(int(water.sizes.get("water_triangles", 0)) > 1000, "River ribbon has geometry")

	# Architecture
	var architecture: Node3D = world.architecture
	_check(int(architecture.sizes.get("structures", 0)) >= 10, "Village structures are built")
	_check(architecture.get_node_or_null("RedBridge") != null, "Red bridge exists")
	var bridge: Node = architecture.get_node_or_null("RedBridge")
	if bridge != null:
		var deck_segments: int = 0
		for child: Node in bridge.get_children():
			if str(child.name).begins_with("BridgeDeckSegment"):
				deck_segments += 1
		_check(deck_segments >= 8, "Bridge deck collision follows the arch")
	_check(architecture.get_node_or_null("Shrine") != null, "Shrine exists")
	_check(architecture.get_node_or_null("Pagoda") != null, "Pagoda exists")

	# Flora
	var flora: Node3D = world.flora
	_check(int(flora.sizes.get("cherry_trees", 0)) >= 60, "Cherry orchard has at least 60 trees")
	_check(int(flora.sizes.get("blossom_instances", 0)) >= 1000, "Blossoms are instanced in bulk")
	_check(int(flora.sizes.get("grass_instances", 0)) >= 3000, "Ground cover is instanced in bulk")
	_check(flora.get_node_or_null("FallingPetals") != null, "Falling petals exist")
	_check(flora.get_node_or_null("Fireflies") != null, "Fireflies exist")

	# Moods
	var lighting: Node3D = world.lighting
	_check(world.mood_keys.size() == 3, "Three moods are configured")
	var blue_density: float = lighting.world_environment.environment.fog_density
	world._apply_mood("morning")
	await process_frame
	var morning_density: float = lighting.world_environment.environment.fog_density
	world._apply_mood("rain")
	await process_frame
	var rain_energy: float = lighting.sun.light_energy
	var rain_emitting: bool = world.rain.rain.emitting
	_check(absf(blue_density - morning_density) > 0.0001, "Mood switch changes fog density")
	_check(rain_energy < 0.5, "Rain mood dims the sun")
	_check(rain_emitting, "Rain mood starts rain particles")
	world._apply_mood("blue_hour")
	await process_frame
	_check(absf(lighting.world_environment.environment.fog_density - blue_density) < 0.0001,
		"Blue hour mood restores the default environment")

	# Cinematic anchors
	var cinematic: Node3D = world.cinematic
	_check(cinematic.anchors.size() == 4, "Four cinematic anchors exist")
	cinematic.enter(0)
	await process_frame
	await process_frame
	_check(cinematic.active and cinematic.camera.current, "Cinematic camera becomes active")
	var first_index: int = cinematic.current_index
	cinematic.cycle(1)
	await process_frame
	_check(cinematic.current_index != first_index, "Q/E cycle changes the anchor")
	cinematic.exit()
	await process_frame
	_check(not cinematic.active and world.player.controls_active, "Exiting cinematic restores player control")

	# Navigation
	var navigation: Node3D = world.navigation
	_check(bool(navigation.baked), "Navigation mesh baked")
	_check(int(navigation.sizes.get("nav_polygons", 0)) > 4, "Navigation mesh has walkable polygons")
	_check(world.walker != null, "Guide walker exists")
	await physics_frame
	await physics_frame

	# Quality
	world._apply_quality("light")
	_check(world.reflection.mirror_root.visible == false, "Light quality disables mirrored reflection")
	_check(float(world.flora._grass.visibility_range_end) < 100.0, "Light quality shortens grass draw distance")
	world._apply_quality("high")
	_check(world.reflection.mirror_root.visible, "High quality restores mirrored reflection")

	# Reflection content
	_check(int(world.reflection.sizes.get("mirrored_meshes", 0)) > 10, "Landscape meshes are mirrored")

	# Player & camera
	var camera: Camera3D = world.player.get_node("Head/Camera3D") as Camera3D
	_check(absf(camera.far - 1200.0) < 0.1, "Camera far plane reaches the distant mountains")
	_check(world.player.global_position.y > 0.5, "Player spawns above the valley floor")
	_check(world.hud != null and not world.hud.loading, "Loading veil is dismissed")

	# Scenery framed at the head of the valley
	var waterfall: Node3D = world.waterfall
	_check(waterfall != null, "Waterfall node exists")
	if waterfall != null:
		_check(int(waterfall.sizes.get("sheets", 0)) >= 3, "Waterfall has layered sheets")
		_check(waterfall.get_node_or_null("Cliff/CliffBlocker") != null, "Waterfall cliff blocks the player")
		_check(waterfall.get_node_or_null("FallSheets/FallCrest") != null, "Waterfall has a bright crest")
		_check(waterfall.get_node_or_null("FallMist") is CPUParticles3D, "Waterfall mist is emitted")
		world._apply_mood("rain")
		_check(absf(float(waterfall._flow_speed) - 1.55) < 0.01, "Rain quickens the waterfall flow")
		world._apply_mood("blue_hour")

	# Birds and koi
	_check(world.birds != null and world.birds.birds is MultiMeshInstance3D, "Birds are one instanced flock")
	if world.birds != null:
		_check(int(world.birds.sizes.get("birds", 0)) >= 20, "Flock has enough birds to read at distance")
		var before: Vector3 = (world.birds.transforms[0] as Transform3D).origin
		world.birds._phase += 2.0
		world.birds._update_flock(0.0)
		var after: Vector3 = (world.birds.transforms[0] as Transform3D).origin
		_check(before.distance_to(after) > 0.5, "Birds move along their orbit")
	_check(world.water._koi.size() >= 5, "Koi swim in the river")

	# Ambient audio is procedural, so no assets are needed
	if world.ambient != null:
		_check(int(world.ambient.sizes.get("ambient_layers", 0)) == 2, "Ambient bed has river and wind")
		_check(not world.ambient.enabled, "Ambient audio is off by default")
		_check(world.ambient.toggle(), "J enables ambient audio")
		var stream: AudioStreamWAV = world.ambient.players[0].stream as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Ambient streams loop")
		_check(world.ambient.toggle() == false, "J disables ambient audio again")

	# Auto-tour drives the four anchors and stops on demand
	if world.tour != null:
		_check(int(world.tour.sizes.get("tour_anchors", 0)) == 4, "Tour covers all four anchors")
		world.tour.start()
		_check(world.tour.active and world.cinematic.active, "T starts the auto-tour")
		world.tour._timer = 999.0
		world.tour._process(0.1)
		_check(world.cinematic.current_index == 1, "Tour advances to the next anchor")
		_check(world.touch.move_vector == Vector2.ZERO, "Tour releases the touch stick")
		world.tour.stop()
		_check(not world.tour.active and not world.cinematic.active, "Tour exits cleanly")

	# Touch layer and player hook
	_check(world.touch != null, "Touch layer exists")
	_check(world.player.has_method("set_touch_move"), "Player accepts virtual-stick input")
	world.player.set_touch_move(Vector2(3.0, 0.0))
	_check(absf(world.player._touch_move.length() - 1.0) < 0.001, "Touch stick is clamped to unit length")
	world.player.set_touch_move(Vector2.ZERO)

	# Failure path: a bad data file surfaces a readable error, never a white screen.
	_check(world.hud.has_method("set_error"), "HUD can show a load failure")
	world.hud.set_error("测试用错误")
	_check(world.hud.error_text == "测试用错误", "Load failure text is stored")
	world.hud.error_text = ""

	# Reduced motion preference is honoured
	_check(bool(world.config.scene.get("reduce_motion", false)) == false, "Reduced-motion flag defaults off")

	print("CHERRY_VALLEY_RESULT checks=%d failures=%d" % [checks, failures])
	world.queue_free()
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
