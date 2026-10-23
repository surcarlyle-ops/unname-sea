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
var _material: StandardMaterial3D
var _glow_material: StandardMaterial3D


func _ready() -> void:
	_build_visual()


func _physics_process(delta: float) -> void:
	# 位置由发射方在入树后设置，所以朝向延迟到第一帧再对齐。
	if not _oriented:
		_oriented = true
		if direction.length_squared() > 0.001:
			look_at(global_position + direction.normalized(), Vector3.UP)
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
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var along: float = offset.dot(direction)
		# 只吃冲击波所在的那一小段厚度。
		if along < -1.2 or along > 1.0:
			continue
		var lateral: Vector3 = offset - direction * along
		if lateral.length() > width * 0.5:
			continue
		if absf(enemy.global_position.y - global_position.y) > height:
			continue
		_hit[enemy.get_instance_id()] = true
		var push: Vector3 = direction * knockback
		push.y = 2.0
		enemy.apply_damage(damage, push)


func _fade() -> void:
	var life: float = clampf(1.0 - _traveled / maxf(max_range, 0.01), 0.0, 1.0)
	var alpha: float = clampf(life * 1.8, 0.0, 1.0)
	_material.albedo_color.a = 0.50 * alpha
	_glow_material.albedo_color.a = 0.72 * alpha


func _build_visual() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(0.32, 0.94, 0.86, 0.50)
	var shell: BoxMesh = BoxMesh.new()
	shell.size = Vector3(width, height, 0.36)
	var shell_instance: MeshInstance3D = MeshInstance3D.new()
	shell_instance.mesh = shell
	shell_instance.material_override = _material
	shell_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell_instance)

	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.albedo_color = Color(0.78, 1.0, 0.96, 0.72)
	var core: BoxMesh = BoxMesh.new()
	core.size = Vector3(width * 0.74, height * 0.52, 0.16)
	var core_instance: MeshInstance3D = MeshInstance3D.new()
	core_instance.mesh = core
	core_instance.material_override = _glow_material
	core_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core_instance)
