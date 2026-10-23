extends Node3D
## (Claude Code) Planar-looking water reflection without ReflectionProbe or SSR.
## Visual meshes are flattened into one mirrored group about y = plane_y, with a
## dimmed flat material. Negative scale flips winding, so culling is disabled.
## No collision and no shadows are copied.

var config: Dictionary
var mirror_root: Node3D
var enabled: bool = true
var sizes: Dictionary = {}

var _dim_material: ShaderMaterial
var _copied: int = 0


func build(cfg: Dictionary) -> void:
	config = cfg
	# A shader instead of a plain material: the mirror has to discard everything
	# that ends up above the water plane, otherwise the flipped river bed is drawn
	# across the bank as a hard dark band.
	var mirror_shader: Shader = load("res://shaders/valley_mirror.gdshader") as Shader
	_dim_material = ShaderMaterial.new()
	_dim_material.shader = mirror_shader
	_dim_material.set_shader_parameter("tint", Color(config.reflection.tint, float(config.reflection.alpha)))
	_dim_material.set_shader_parameter("plane_y", float(config.reflection.plane_y))
	_dim_material.set_shader_parameter("fade_start", 70.0)
	_dim_material.set_shader_parameter("fade_end", 200.0)
	mirror_root = Node3D.new()
	mirror_root.name = "MirrorRoot"
	add_child(mirror_root)


## Copy every visible mesh under the given source roots. Call once after the
## valley is built; the sources should be visual groups only.
func copy_from(sources: Array[Node3D]) -> void:
	if mirror_root == null:
		return
	for child: Node in mirror_root.get_children():
		child.queue_free()
	_copied = 0
	for source: Node3D in sources:
		if is_instance_valid(source):
			_collect(source)
	var plane_y: float = float(config.reflection.plane_y)
	mirror_root.transform = Transform3D(
		Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)),
		Vector3(0.0, plane_y * 2.0, 0.0)
	)
	sizes["mirrored_meshes"] = _copied


func _collect(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			if mesh_node.mesh != null and not _is_effect(mesh_node):
				var copy: MeshInstance3D = MeshInstance3D.new()
				copy.name = mesh_node.name + "_Mirror"
				copy.mesh = mesh_node.mesh
				copy.material_override = _mirror_material(mesh_node)
				copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				copy.visibility_range_end = 200.0
				# Local transform under MirrorRoot equals the original world
				# transform, because MirrorRoot itself sits at the world origin.
				copy.transform = mesh_node.global_transform
				mirror_root.add_child(copy)
				_copied += 1
		elif child is Node3D:
			_collect(child)


func _is_effect(node: MeshInstance3D) -> bool:
	var lower_name: String = node.name.to_lower()
	if lower_name.contains("halo") or lower_name.contains("foam") or lower_name.contains("spirit"):
		return true
	if node.material_override is StandardMaterial3D:
		var material: StandardMaterial3D = node.material_override as StandardMaterial3D
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


func _mirror_material(_node: MeshInstance3D) -> Material:
	# One flat dim material for every copy: negative scale flips winding, so a
	# cull-disabled unshaded material avoids missing backfaces and doubled shading.
	return _dim_material


func set_enabled(value: bool) -> void:
	enabled = value
	if mirror_root != null:
		mirror_root.visible = value
