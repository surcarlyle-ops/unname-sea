extends Node3D
## (Claude Code) Rain layer for the "雨中" mood: falling streaks around the camera
## plus a wet-sheen darkening handled by the mood palette.

const STREAK_COUNT: int = 900

var rain: CPUParticles3D


func build(cfg: Dictionary, camera: Camera3D) -> void:
	var shape: QuadMesh = QuadMesh.new()
	shape.size = Vector2(0.03, 0.55)
	# QuadMesh already faces the camera axis; billboard material handles rotation.
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.72, 0.78, 0.85, 0.28)
	rain = CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = STREAK_COUNT
	rain.lifetime = 1.4
	rain.preprocess = 1.0
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22.0, 2.0, 22.0)
	rain.direction = Vector3(0.12, -1.0, 0.06)
	rain.spread = 4.0
	rain.gravity = Vector3(0, -14.0, 0)
	rain.initial_velocity_min = 12.0
	rain.initial_velocity_max = 17.0
	rain.scale_amount_min = 0.8
	rain.scale_amount_max = 1.5
	rain.mesh = shape
	rain.material_override = material
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.local_coords = false
	rain.emitting = false
	add_child(rain)
	set_camera(camera)


## Keep the emitter volume centred on the camera so rain always surrounds the view.
func set_camera(camera: Camera3D) -> void:
	if camera == null or rain == null:
		return
	rain.global_position = camera.global_position + Vector3(0, 9.0, 0)


func set_mood(mood: Dictionary) -> void:
	if rain == null:
		return
	rain.emitting = bool(mood.rain)
