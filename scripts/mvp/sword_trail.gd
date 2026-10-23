extends Node3D
## (Claude Code) World-space sword trail ribbon.
## Samples the blade tip during the active part of a swing and draws a
## fading triangle strip between the hilt and tip. Kept engine-side so it
## works with any weapon model without editing its meshes.

const SAMPLE_COUNT: int = 12
const LIFETIME_MS: int = 110
const MIN_TIP_MOVEMENT: float = 0.010

var _weapon_root: Node3D
var _tip_local: Vector3 = Vector3(0.0, 0.55, 0.0)
var _grip_local: Vector3 = Vector3(0.0, 0.20, 0.0)
var _color: Color = Color(1.0, 0.93, 0.76)
var _samples: Array[Dictionary] = []
var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _material: StandardMaterial3D
var _last_tip: Vector3 = Vector3.ZERO
var _has_last_tip: bool = false


func _ready() -> void:
	# Ribbon lives in world space so it lags behind the moving blade.
	top_level = true
	global_transform = Transform3D.IDENTITY
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color.WHITE
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)


## Cache the blade extent for the currently equipped weapon. Uses the visible
## mesh AABBs so the same code fits the procedural practice blade and the GLB.
func set_weapon(weapon_root: Node3D, weapon_id: String) -> void:
	_weapon_root = weapon_root
	_color = Color(0.70, 1.0, 0.94) if weapon_id == "tide_blade" else Color(1.0, 0.93, 0.76)
	_samples.clear()
	_has_last_tip = false
	_tip_local = Vector3(0.0, 0.55, 0.0)
	_grip_local = Vector3(0.0, 0.20, 0.0)
	if weapon_root == null:
		return
	var max_y: float = 0.0
	var min_y: float = INF
	# Weapon meshes may not be inside the tree yet, so read their AABB in place
	# instead of relying on global_transform.
	for instance: MeshInstance3D in _visible_meshes(weapon_root):
		var aabb: AABB = instance.get_aabb()
		for corner: Vector3 in _aabb_corners(aabb):
			var local: Vector3 = instance.transform * corner
			var check: Node = instance
			while check != null and check != weapon_root:
				if check is Node3D:
					local = (check as Node3D).transform * local
				check = check.get_parent()
			if check == weapon_root:
				# weapon_root's own scale/rotation is applied by the ribbon consumer.
				max_y = maxf(max_y, local.y)
				min_y = minf(min_y, local.y)
	if max_y > 0.05:
		_tip_local = Vector3(0.0, max_y, 0.0)
		if min_y < INF and min_y < max_y:
			_grip_local = Vector3(0.0, lerpf(min_y, max_y, 0.22), 0.0)


## Record the current blade position while the swing is in its active window.
func push_sample() -> void:
	if _weapon_root == null or not is_instance_valid(_weapon_root):
		return
	var tip: Vector3 = _weapon_root.global_transform * _tip_local
	if _has_last_tip and tip.distance_to(_last_tip) < MIN_TIP_MOVEMENT:
		return
	_last_tip = tip
	_has_last_tip = true
	_samples.push_back({
		"ms": Time.get_ticks_msec(),
		"tip": tip,
		"grip": _weapon_root.global_transform * _grip_local,
	})
	while _samples.size() > SAMPLE_COUNT:
		_samples.pop_front()


func clear() -> void:
	_samples.clear()
	_has_last_tip = false
	_rebuild()


func _process(_delta: float) -> void:
	_expire()
	_rebuild()


func _expire() -> void:
	var now: int = Time.get_ticks_msec()
	while not _samples.is_empty() and now - int(_samples[0].ms) > LIFETIME_MS:
		_samples.pop_front()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var now: int = Time.get_ticks_msec()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for sample: Dictionary in _samples:
		var age: float = clampf(float(now - int(sample.ms)) / float(LIFETIME_MS), 0.0, 1.0)
		var alpha: float = pow(1.0 - age, 1.6) * 0.55
		var tip: Vector3 = sample.tip
		var grip: Vector3 = sample.grip
		_mesh.surface_set_color(Color(_color, alpha))
		_mesh.surface_add_vertex(tip)
		# Inner edge is dimmer and shorter so the ribbon reads as a blade arc.
		_mesh.surface_set_color(Color(_color, alpha * 0.25))
		_mesh.surface_add_vertex(grip.lerp(tip, 0.30))
	_mesh.surface_end()


func _visible_meshes(root: Node3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child: Node in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).is_visible_in_tree():
			found.append(child as MeshInstance3D)
		if child is Node3D:
			found.append_array(_visible_meshes(child as Node3D))
	return found


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	return [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]
