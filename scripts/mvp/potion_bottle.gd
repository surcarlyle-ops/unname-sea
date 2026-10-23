extends Node3D
## 程序化药水瓶：圆柱瓶身 + 收口 + 软木塞 + 青绿液体。
## 挂在右手挂点上，跟随手部动作，不依赖任何外部模型资源。

const GLASS_COLOR: Color = Color(0.62, 0.78, 0.72, 0.55)
const LIQUID_COLOR: Color = Color(0.32, 0.95, 0.82)
const CORK_COLOR: Color = Color(0.46, 0.34, 0.22)

var _liquid: MeshInstance3D
var _liquid_material: StandardMaterial3D
var _glass_material_instance: StandardMaterial3D


func _ready() -> void:
	_build()


func _build() -> void:
	_glass_material_instance = _glass_material()
	# 瓶身
	_mesh(_cylinder(0.034, 0.034, 0.085), Vector3(0.0, 0.0, 0.0), _glass_material_instance)
	# 收口
	_mesh(_cylinder(0.017, 0.031, 0.028), Vector3(0.0, 0.056, 0.0), _glass_material_instance)
	# 瓶颈
	_mesh(_cylinder(0.016, 0.016, 0.024), Vector3(0.0, 0.080, 0.0), _glass_material_instance)
	# 软木塞
	_mesh(_cylinder(0.015, 0.017, 0.016), Vector3(0.0, 0.099, 0.0), _cork_material())
	# 液体
	_liquid_material = StandardMaterial3D.new()
	_liquid_material.albedo_color = LIQUID_COLOR
	_liquid_material.emission_enabled = true
	_liquid_material.emission = LIQUID_COLOR
	_liquid_material.emission_energy_multiplier = 1.1
	_liquid = _mesh(_cylinder(0.028, 0.028, 0.052), Vector3(0.0, -0.012, 0.0), _liquid_material)


## 0..1 液面高度，喝药时递减。
func set_fill(ratio: float) -> void:
	if _liquid == null:
		return
	var value: float = clampf(ratio, 0.0, 1.0)
	_liquid.visible = value > 0.02
	_liquid.scale = Vector3(1.0, maxf(value, 0.02), 1.0)
	_liquid.position.y = -0.012 - (1.0 - value) * 0.022


## 0..1 整体淡入淡出，用于取出与收起过渡。
func set_alpha(alpha: float) -> void:
	var value: float = clampf(alpha, 0.0, 1.0)
	visible = value > 0.01
	if _glass_material_instance != null:
		var glass: Color = GLASS_COLOR
		glass.a *= value
		_glass_material_instance.albedo_color = glass
	if _liquid_material != null:
		var liquid: Color = LIQUID_COLOR
		liquid.a = value
		_liquid_material.albedo_color = liquid


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 2
	return mesh


func _glass_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = GLASS_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	material.metallic = 0.1
	return material


func _cork_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = CORK_COLOR
	material.roughness = 0.9
	return material


func _mesh(mesh: Mesh, offset: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
