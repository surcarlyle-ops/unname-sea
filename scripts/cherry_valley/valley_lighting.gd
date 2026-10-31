extends Node3D
## (Claude Code) Three switchable moods (blue hour / morning / rain). Each mood is a
## full Environment + sky + sun + fog + glow set, applied together rather than only
## changing the background colour.

signal mood_changed(mood_key: String)

const MOOD_ORDER: Array[String] = ["blue_hour", "morning", "rain"]

var config: Dictionary
var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var current_key: String = "blue_hour"

var _environments: Dictionary = {}
var _sky_materials: Dictionary = {}
var _mood_keys: Array[String] = []
var _blend: float = 1.0
var _pending_key: String = ""
var _fog_layers: Array[MeshInstance3D] = []
## Relative opacity of each haze sheet; the mood multiplies it by `haze_alpha`.
var _fog_weights: PackedFloat32Array = PackedFloat32Array()


func build(cfg: Dictionary) -> void:
	config = cfg
	world_environment = WorldEnvironment.new()
	world_environment.name = "ValleyEnvironment"
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "ValleySun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)
	_build_fog_layers()
	_mood_keys.clear()
	for key: String in MOOD_ORDER:
		if config.moods.has(key):
			_mood_keys.append(key)
	for key: String in _mood_keys:
		_environments[key] = _make_environment(config.moods[key])
		_sky_materials[key] = _environments[key].sky.sky_material
	current_key = _mood_keys[0] if not _mood_keys.is_empty() else ""
	if current_key != "":
		apply_mood(current_key)


func get_mood_keys() -> Array[String]:
	return _mood_keys.duplicate()


func mood_label(key: String) -> String:
	if not _mood_keys.has(key):
		return key
	return str(config.moods[key].label)


func next_mood() -> String:
	if _mood_keys.is_empty():
		return ""
	var index: int = _mood_keys.find(current_key)
	var next_key: String = _mood_keys[(index + 1) % _mood_keys.size()]
	apply_mood(next_key)
	return next_key


func apply_mood(key: String) -> void:
	if not _environments.has(key):
		return
	current_key = key
	var mood: Dictionary = config.moods[key]
	var environment: Environment = _environments[key]
	world_environment.environment = environment
	sun.light_color = Color(mood.sun_color)
	sun.light_energy = float(mood.sun_energy)
	sun.rotation_degrees = Vector3(float(mood.sun_rotation[0]), float(mood.sun_rotation[1]), float(mood.sun_rotation[2]))
	# Swap the sky as well: ProceduralSkyMaterial lives on the Environment's sky.
	var sky: Sky = Sky.new()
	sky.sky_material = _sky_materials[key]
	environment.sky = sky
	var haze_alpha: float = float(mood.get("haze_alpha", 0.055))
	var mist_density: float = float(mood.get("mist_density", 1.0))
	for index: int in range(_fog_layers.size()):
		var layer_material: StandardMaterial3D = _fog_layers[index].material_override as StandardMaterial3D
		if layer_material == null:
			continue
		var weight: float = _fog_weights[index] if index < _fog_weights.size() else 1.0
		# Mist sheets thin out in clear weather and stack up in rain, so the haze
		# reads as weather rather than a fixed translucent wall.
		layer_material.albedo_color = Color(Color(mood.fog_color), haze_alpha * weight * mist_density)
	mood_changed.emit(key)


func is_raining() -> bool:
	if not config.moods.has(current_key):
		return false
	return bool(config.moods[current_key].rain)


## Palette used by petals, lanterns and ambient particles.
func accent_color() -> Color:
	if not config.moods.has(current_key):
		return Color("ffd4e0")
	return Color(config.moods[current_key].petal_color)


func _make_environment(mood: Dictionary) -> Environment:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	material.sky_top_color = Color(mood.sky_top)
	material.sky_horizon_color = Color(mood.sky_horizon)
	material.ground_horizon_color = Color(mood.sky_ground_horizon)
	material.ground_bottom_color = Color(mood.sky_bottom)
	material.sky_energy_multiplier = 1.0
	material.sun_angle_max = 18.0
	material.sun_curve = 0.12
	sky.sky_material = material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(mood.ambient_color)
	environment.ambient_light_sky_contribution = 0.55
	environment.ambient_light_energy = float(mood.ambient_energy)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = float(mood.exposure)
	environment.tonemap_white = 6.0
	# SSAO is a Forward+ / Mobile feature. In the Compatibility renderer this flag
	# is ignored, so it is switched off rather than left on to look like it works.
	environment.ssao_enabled = false
	# Glow works in Compatibility, but as an LDR screen-blend: values can never
	# exceed 1.0, so a 1.3 threshold (the old value) meant nothing ever glowed.
	environment.glow_enabled = true
	environment.glow_intensity = float(mood.glow)
	environment.glow_strength = 1.18
	environment.glow_bloom = 0.12
	# Threshold sits above the lit terrain so glow only catches lanterns, windows
	# and the sun's rim, instead of blooming the whole foreground white.
	environment.glow_hdr_threshold = 0.88
	environment.glow_hdr_scale = 1.4
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.fog_enabled = true
	# Depth fog keeps the playable valley clear and only hazes the distance,
	# so geometry never looks like it is floating in a white void.
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(mood.fog_color)
	environment.fog_light_energy = 0.55
	environment.fog_depth_begin = float(mood.get("fog_begin", 45.0))
	environment.fog_depth_end = float(mood.get("fog_end", 430.0))
	environment.fog_depth_curve = float(mood.get("fog_curve", 1.25))
	environment.fog_density = float(mood.fog_density)
	environment.fog_aerial_perspective = float(mood.fog_aerial)
	environment.fog_sky_affect = float(mood.fog_sky)
	environment.fog_sun_scatter = 0.08
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 1.06 if not bool(mood.rain) else 0.88
	return environment

## Compatibility has no volumetric fog, so the mid-ground haze is built from a
## few camera-facing sheets plus a low river-mist band. They sit down-valley from
## the village (z 46 .. -190) so every cinematic shot looks through them; the
## first pass placed them behind the panorama camera at z = 92 and none of them
## ever showed up in frame.
func _build_fog_layers() -> void:
	var tint: Color = Color("7089aa")
	# position, quad size, opacity weight
	var specs: Array[Dictionary] = [
		{"position": Vector3(0.0, 5.0, 46.0), "size": Vector2(200.0, 15.0), "weight": 0.75},
		{"position": Vector3(-12.0, 9.0, 4.0), "size": Vector2(220.0, 21.0), "weight": 0.95},
		{"position": Vector3(8.0, 14.0, -42.0), "size": Vector2(240.0, 27.0), "weight": 1.10},
		{"position": Vector3(0.0, 21.0, -86.0), "size": Vector2(262.0, 34.0), "weight": 1.20},
		{"position": Vector3(0.0, 34.0, -136.0), "size": Vector2(288.0, 42.0), "weight": 1.05},
		{"position": Vector3(0.0, 52.0, -190.0), "size": Vector2(320.0, 52.0), "weight": 0.85},
	]
	_fog_layers.clear()
	_fog_weights.clear()
	for index: int in range(specs.size()):
		var spec: Dictionary = specs[index]
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Haze must not eat the sun or cast shadows; it is a colour overlay only.
		material.disable_receive_shadows = true
		material.albedo_color = Color(tint, 0.055 * float(spec.weight))
		var quad: QuadMesh = QuadMesh.new()
		quad.size = spec.size
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "FogLayer%d" % index
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = spec.position
		add_child(node)
		_fog_layers.append(node)
		_fog_weights.append(float(spec.weight))
