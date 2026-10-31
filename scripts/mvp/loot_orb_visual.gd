extends Node3D
## Small readable loot placeholder. Additive halo works without Bloom on Compatibility.

static func build(radius: float = 0.115, tint: Color = Color("69bcff")) -> Node3D:
	var visual: Node3D = Node3D.new()
	visual.name = "LootOrb"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	var core: MeshInstance3D = MeshInstance3D.new()
	core.name = "Core"
	core.mesh = sphere
	core.material_override = material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(core)
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(tint, 0.6))
	gradient.set_color(1, Color(tint, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	var halo_material: StandardMaterial3D = StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.albedo_texture = texture
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * radius * 5.0
	var halo: MeshInstance3D = MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = quad
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(halo)
	return visual
