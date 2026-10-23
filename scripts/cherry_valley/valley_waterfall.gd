extends Node3D
## (Claude Code) Waterfall at the far end of the river: a rimmed rock face, a
## falling water sheet with scrolling streaks, white lip, foam and light mist.
## Sits outside the walkable corridor so it frames the vista without blocking it.

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var config: Dictionary
var terrain: Node3D
var materials: Dictionary
var sizes: Dictionary = {}

var sheets: Array[MeshInstance3D] = []
var flow_materials: Array[ShaderMaterial] = []
var foam: MultiMeshInstance3D
var mist: CPUParticles3D

var _flow_offset: float = 0.0
var _flow_speed: float = 1.0
var _mist_amount_high: int = 80
## Anchors derived from the river, so the fall always lands in the channel.
var _fall_x: float = 0.0
var _fall_z: float = 0.0
var _pool_center: Vector2 = Vector2.ZERO


func build(cfg: Dictionary, terrain_node: Node3D, kit_materials: Dictionary) -> void:
	config = cfg
	terrain = terrain_node
	materials = kit_materials
	if not cfg.has("waterfall") or not bool(cfg.waterfall.enabled):
		return
	var spec: Dictionary = cfg.waterfall
	var fall: Dictionary = spec.fall
	_fall_z = float(fall.z)
	# The lip sits on the river centre. The old config put it 6 m off the channel,
	# so the sheets and the pool were buried in the bank.
	_fall_x = float(terrain.river_point_at_z(_fall_z).x)
	_pool_center = Vector2(_fall_x, _fall_z + 5.0)
	_build_cliff(spec.cliff, spec)
	_build_fall(fall)
	_build_foam(spec.foam)
	_build_mist(spec.mist)
	sizes["sheets"] = sheets.size()
	sizes["fall_x"] = _fall_x


# ---------------------------------------------------------------- cliff

## Boulders that hug the rock ramp the terrain carves behind the fall. The ramp
## itself is the drop; the rocks stop it reading as a smooth slope. The old
## version scattered blobs through a hillside and added two flat benches that
## stuck out of the ground as slabs.
func _build_cliff(cliff: Dictionary, spec: Dictionary) -> void:
	var span: float = float(cliff.span_z) * 0.55
	var height: float = float(cliff.height)
	var shelf: float = float(spec.fall.get("shelf_blend", 5.5))
	var foot_y: float = float(terrain.water_level) - 1.3
	var rock_root: Node3D = Node3D.new()
	rock_root.name = "Cliff"
	add_child(rock_root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4021
	# Flanking rocks only. The sheet is the subject, so the rock work stays on the
	# sides of the notch: a heap across the channel hid the water completely.
	var clear_half: float = float(spec.fall.width) * 0.85
	var stones: int = 14
	for i: int in range(stones):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var x: float = _fall_x + side * rng.randf_range(clear_half, span)
		var y: float = rng.randf_range(foot_y + 0.6, height * 0.95)
		var t: float = clampf((height - y) / maxf(height - foot_y, 0.1), 0.0, 1.0)
		var z: float = lerpf(_fall_z - 2.0, _fall_z + shelf * 0.55, t) - rng.randf_range(0.6, 2.0)
		var radii: Vector3 = Vector3(
			rng.randf_range(1.4, 2.6),
			rng.randf_range(0.9, 1.9),
			rng.randf_range(0.8, 1.5)
		)
		var tone: Color = Color("#7f8583").darkened(rng.randf_range(0.0, 0.22))
		acc.blob(Vector3(x, y, z), radii, tone, 4, 7, 0.18, 500 + i)
	# A few splash boulders at the foot, kept clear of the falling water.
	for i: int in range(5):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var x: float = _fall_x + side * rng.randf_range(clear_half, clear_half + 3.2)
		acc.blob(
			Vector3(x, foot_y + 0.5, _fall_z + shelf * 0.62 + rng.randf_range(-1.0, 1.4)),
			Vector3(rng.randf_range(1.0, 1.7), rng.randf_range(0.6, 1.0), rng.randf_range(1.0, 1.7)),
			Color("#6f7573").darkened(rng.randf_range(0.0, 0.2)), 4, 6, 0.2, 700 + i
		)
	var mesh_node: MeshInstance3D = MESH_KIT.instance(acc, materials.rock, "CliffRock", true)
	rock_root.add_child(mesh_node)
	# A single wet ledge tucked against the flank of the fall. The old pair of boxes
	# sat in the middle of the pool and read as grey slabs floating in the water.
	var wet_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	wet_acc.box(Vector3(_fall_x - clear_half - 1.4, 2.6, _fall_z + shelf * 0.30), Vector3(2.2, 0.6, 2.4), Color("#5d6564"))
	var wet_material: StandardMaterial3D = MESH_KIT.simple_material(Color("#4a5450"), 0.35)
	var wet_node: MeshInstance3D = MESH_KIT.instance(wet_acc, wet_material, "CliffWetLedges", true)
	rock_root.add_child(wet_node)
	# Collision so the player cannot walk up the rock ramp.
	MESH_KIT.solid_box(rock_root, "CliffBlocker",
		Vector3(_fall_x, height * 0.5, _fall_z + shelf * 0.2), Vector3(span * 2.2, height, 3.0))


## The plunge pool is the river itself: the terrain carve deepens the channel at
## the foot of the fall. A separate water disc used to sit here and overlapped the
## river ribbon, which read as a second, brighter sheet of water on the bank.


# ---------------------------------------------------------------- falling water

## Three overlapping sheets at slightly different speeds: the parallax between
## them reads as depth and turbulence rather than a flat curtain.
func _build_fall(fall: Dictionary) -> void:
	var x: float = _fall_x
	var z: float = _fall_z
	# Start the sheet at the carved crest, not a metre above it: the lip is at
	# top_y - 1.0, so a sheet starting at top_y appeared to hang in the air.
	var top: float = float(fall.top_y) - 0.9
	var bottom: float = float(fall.bottom_y)
	var width: float = float(fall.width)
	# The sheet hangs from under the lip and lands downstream at the pool. It used
	# to lean the other way, into the hillside, which is why nothing was visible.
	var top_z: float = z - 1.6
	var bottom_z: float = z + 2.6
	var root: Node3D = Node3D.new()
	root.name = "FallSheets"
	add_child(root)
	var layers: Array[Dictionary] = [
		{"w": width * 1.02, "speed": 1.0, "alpha": 0.24},
		{"w": width * 0.74, "speed": 1.45, "alpha": 0.20},
		{"w": width * 0.42, "speed": 1.9, "alpha": 0.18},
	]
	for index: int in range(layers.size()):
		var layer: Dictionary = layers[index]
		var sheet_width: float = float(layer.w)
		# Water spreads and thins as it falls.
		var taper: float = 0.86
		var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
		var rows: int = 9
		var columns: int = 4
		for row: int in range(rows):
			var v0: float = float(row) / float(rows)
			var v1: float = float(row + 1) / float(rows)
			for column: int in range(columns):
				var u0: float = float(column) / float(columns) - 0.5
				var u1: float = float(column + 1) / float(columns) - 0.5
				# Bulge outward towards the middle so the sheet is not a flat card.
				var b0: float = sin((u0 + 0.5) * PI) * 0.55
				var b1: float = sin((u1 + 0.5) * PI) * 0.55
				var lower_width: float = sheet_width * lerpf(1.0, taper, v1)
				var a: Vector3 = Vector3(x + u0 * sheet_width, top, top_z + b0 * 0.4)
				var b: Vector3 = Vector3(x + u1 * sheet_width, top, top_z + b1 * 0.4)
				var c: Vector3 = Vector3(x + u1 * lower_width, lerpf(top, bottom, v1), lerpf(top_z, bottom_z, v1) + b1)
				var d: Vector3 = Vector3(x + u0 * lower_width, lerpf(top, bottom, v1), lerpf(top_z, bottom_z, v1) + b0)
				acc.quad(a, b, c, d, Color.WHITE, Vector3.UP)
		var sheet: MeshInstance3D = MESH_KIT.instance(acc, null, "FallSheet%d" % index)
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flow: ShaderMaterial = _flow_material(float(layer.alpha))
		flow.set_shader_parameter("speed_scale", float(layer.speed))
		flow.set_shader_parameter("flow_speed", _flow_speed * float(layer.speed))
		flow.set_shader_parameter("sheet_center_x", x)
		flow.set_shader_parameter("sheet_half_width", sheet_width * 0.5)
		flow.set_shader_parameter("crest_y", top)
		flow.set_shader_parameter("foot_y", bottom)
		sheet.material_override = flow
		root.add_child(sheet)
		sheets.append(sheet)
		flow_materials.append(flow)
	# Thin foam lip at the crest; a tall white box here read as a floating plank.
	var crest_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	crest_acc.box(Vector3(x, top + 0.05, top_z + 0.15), Vector3(width * 1.04, 0.22, 0.9), Color("#eef6f6"))
	var crest_material: StandardMaterial3D = MESH_KIT.simple_material(Color.WHITE, 0.5)
	var crest: MeshInstance3D = MESH_KIT.instance(crest_acc, crest_material, "FallCrest")
	crest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crest)


## Scrolling streaks: bands of brighter foam drifting down the sheet. Noise keeps
## the bands from looking like regular stripes.
func _flow_material(alpha: float) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = FLOW_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("sheet_alpha", alpha)
	material.set_shader_parameter("flow_offset", 0.0)
	material.set_shader_parameter("flow_speed", _flow_speed)
	material.set_shader_parameter("tint", Color("#dcefef"))
	return material


func set_mood(mood: Dictionary) -> void:
	var rain: bool = bool(mood.rain)
	_flow_speed = 1.55 if rain else 1.0
	for material: ShaderMaterial in flow_materials:
		var scale: float = float(material.get_shader_parameter("speed_scale"))
		material.set_shader_parameter("flow_speed", _flow_speed * scale)
	if mist != null:
		mist.amount = int(float(_mist_amount_high) * (1.5 if rain else 1.0))


func apply_quality(settings: Dictionary) -> void:
	var light: bool = not bool(settings.get("reflection", true))
	for sheet: MeshInstance3D in sheets:
		sheet.visible = true
	if mist != null:
		mist.visibility_range_end = 70.0 if light else 160.0


func _process(delta: float) -> void:
	_flow_offset = fmod(_flow_offset + delta, 1000.0)
	for material: ShaderMaterial in flow_materials:
		# Each sheet scrolls at its own rate; a shared phase keeps them in sync.
		material.set_shader_parameter("flow_offset", _flow_offset * _flow_speed * float(material.get_shader_parameter("speed_scale")))


# ---------------------------------------------------------------- foam & mist

func _build_foam(foam_spec: Dictionary) -> void:
	var x: float = _fall_x
	var z: float = _fall_z + 3.0
	var radius: float = float(foam_spec.radius)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	acc.blob(Vector3(x, 0.04, z), Vector3(radius, 0.22, radius * 0.85), Color.WHITE, 4, 10, 0.18, 77)
	acc.blob(Vector3(x - radius * 0.55, 0.03, z + 1.0), Vector3(radius * 0.55, 0.18, radius * 0.5), Color(0.94, 0.97, 0.97), 3, 9, 0.2, 78)
	var material: StandardMaterial3D = MESH_KIT.simple_material(Color.WHITE, 0.7)
	var node: MeshInstance3D = MESH_KIT.instance(acc, material, "FallFoam", true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_mist(spec: Dictionary) -> void:
	_mist_amount_high = int(spec.amount)
	mist = CPUParticles3D.new()
	mist.name = "FallMist"
	mist.amount = _mist_amount_high
	mist.lifetime = 3.4
	mist.preprocess = 2.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = float(spec.radius)
	mist.position = Vector3(_fall_x, 1.4, _fall_z + 3.0)
	mist.direction = Vector3(0, 1, -0.4)
	mist.spread = 22.0
	mist.gravity = Vector3(0, 1.1, -0.25)
	mist.initial_velocity_min = 0.8
	mist.initial_velocity_max = 1.8
	mist.scale_amount_min = 0.6
	mist.scale_amount_max = 1.4
	mist.color = Color(0.87, 0.94, 0.96, 0.5)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.9, 0.96, 0.98, 0.16)
	var texture: GradientTexture2D = GradientTexture2D.new()
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.width = 64
	texture.height = 64
	material.albedo_texture = texture
	quad.material = material
	mist.mesh = quad
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.emitting = true
	add_child(mist)


const FLOW_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, shadows_disabled;
// (Claude Code) Vertical water sheet: scrolling foam bands + soft edge falloff.

uniform vec4 tint : source_color = vec4(0.86, 0.94, 0.94, 1.0);
uniform float sheet_alpha = 0.32;
uniform float flow_offset = 0.0;
uniform float flow_speed = 1.0;
uniform float speed_scale = 1.0;
// The sheet is generated procedurally and carries no UVs, so the soft side falloff
// is measured against these instead of UV.x (which was always 0 and made the whole
// sheet fully transparent).
uniform float sheet_center_x = 0.0;
uniform float sheet_half_width = 2.4;
uniform float crest_y = 15.0;
uniform float foot_y = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Bands run down the sheet; two scales break up regularity.
	float a = sin(local_pos.y * 1.7 - flow_offset * 1.0)
		+ sin(local_pos.y * 4.1 - flow_offset * 1.6 + local_pos.x * 1.9) * 0.55
		+ sin(local_pos.y * 9.3 - flow_offset * 2.6 + local_pos.x * 5.3) * 0.25;
	float foam = smoothstep(0.55, 1.35, a);
	// Brighter towards the crest and the foot of the fall.
	float crest = smoothstep(crest_y - 3.0, crest_y, local_pos.y);
	float foot = smoothstep(foot_y + 2.4, foot_y + 0.2, local_pos.y);
	float across = clamp(abs(local_pos.x - sheet_center_x) / max(sheet_half_width, 0.01), 0.0, 1.0);
	float edge = smoothstep(1.0, 0.62, across);
	vec3 color = mix(tint.rgb * 0.72, vec3(0.98, 1.0, 1.0), clamp(foam + crest * 0.6 + foot * 0.4, 0.0, 1.0));
	ALBEDO = color;
	// Keep the sheet translucent: at near-full opacity it reads as a white plank
	// instead of falling water.
	ALPHA = clamp(sheet_alpha + foam * 0.30 + crest * 0.16 + foot * 0.20, 0.0, 0.78) * edge;
}
"""
