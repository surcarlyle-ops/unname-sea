extends Node3D
## 鸣潮刃的冲击波：短距离、较宽、可穿透多个敌人并将其击退。

var direction: Vector3 = Vector3.FORWARD
var speed: float = 16.0
var max_range: float = 9.0
var damage: int = 18
var knockback: float = 7.5
var width: float = 3.2
var height: float = 1.6

var _traveled: float = 0.0
var _hit: Dictionary = {}
var _oriented: bool = false
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_build_visual()


func _physics_process(delta: float) -> void:
	# 位置由发射方在入树后设置，所以朝向延迟到第一帧再对齐。
	if not _oriented:
		_oriented = true
		if direction.length_squared() > 0.001:
			var up: Vector3 = Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
			look_at(global_position + direction.normalized(), up)
	var step: float = speed * delta
	_traveled += step
	global_position += direction * step
	_check_targets()
	# 撞墙即消失，避免穿过地形打到墙后的敌人。
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position, global_position + direction * (step + 0.45), 1
	)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		queue_free()
		return
	_fade()
	if _traveled >= max_range:
		queue_free()


func _check_targets() -> void:
	for node: Node in get_tree().get_nodes_in_group("mvp_enemies"):
		var enemy: Node3D = node as Node3D
		if enemy == null or enemy.dead or _hit.has(enemy.get_instance_id()):
			continue
		var point: Vector3 = enemy.damage_point() if enemy.has_method("damage_point") else enemy.global_position
		var offset: Vector3 = point - global_position
		offset.y = 0.0
		var along: float = offset.dot(direction)
		# 只吃冲击波所在的那一小段厚度。
		if along < -1.2 or along > 1.0:
			continue
		var lateral: Vector3 = offset - direction * along
		if lateral.length() > width * 0.5:
			continue
		if absf(point.y - global_position.y) > height:
			continue
		_hit[enemy.get_instance_id()] = true
		var push: Vector3 = direction * knockback
		push.y = 2.0
		enemy.apply_damage(damage, push)


func _fade() -> void:
	var life: float = clampf(_traveled / maxf(max_range, 0.01), 0.0, 1.0)
	var alpha: float = smoothstep(0.0, 0.07, life) * (1.0 - smoothstep(0.55, 1.0, life))
	for i: int in range(_materials.size()):
		_materials[i].set_shader_parameter("opacity", alpha * [0.95, 0.35, 0.15][i])


func _build_visual() -> void:
	var mesh: ArrayMesh = _crescent_mesh()
	for i: int in range(3):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = preload("res://shaders/tide_crescent.gdshader")
		material.set_shader_parameter("opacity", 0.0)
		material.set_shader_parameter("echo", float(i) / 2.0)
		_materials.append(material)
		var ribbon: MeshInstance3D = MeshInstance3D.new()
		ribbon.name = "Crescent" if i == 0 else "Wake%d" % i
		ribbon.mesh = mesh
		ribbon.material_override = material
		ribbon.position = Vector3(0, -0.035 * i, 0.28 * i)
		ribbon.scale = Vector3.ONE * (1.0 - i * 0.06)
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)


func _crescent_mesh() -> ArrayMesh:
	# A tapered curved ribbon with swept-back tips; the silhouette is geometry,
	# so it cannot turn back into a rectangular billboard at grazing angles.
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var segments: int = 48
	for i: int in range(segments + 1):
		var u: float = float(i) / segments
		var t: float = u * 2.0 - 1.0
		var taper: float = pow(maxf(0.0, 1.0 - t * t), 0.7)
		var center: Vector3 = Vector3(t * width * 0.5, 0.23 * (1.0 - t * t), 0.45 * t * t)
		var thickness: float = clampf(height * 0.10, 0.08, 0.20) * taper
		vertices.append(center + Vector3(0, -thickness, 0.10 * taper))
		vertices.append(center + Vector3(0, thickness, -0.10 * taper))
		uvs.append(Vector2(u, 0))
		uvs.append(Vector2(u, 1))
		if i < segments:
			var n: int = i * 2
			indices.append_array(PackedInt32Array([n, n + 1, n + 2, n + 1, n + 3, n + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
