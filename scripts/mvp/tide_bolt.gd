extends Node3D
## 潮汐手炮的弹体：青绿磷光球 + 粒子拖尾，命中时炸开成水花与鳞片碎片。

const GLOW_COLOR: Color = Color(0.42, 1.0, 0.88)
const CORE_COLOR: Color = Color(0.86, 1.0, 0.97)
const TRAIL_COLOR: Color = Color(0.36, 0.95, 0.82, 0.55)

var velocity: Vector3 = Vector3.ZERO
var damage: int = 10
var knockback: float = 2.0
var life: float = 1.2

var _glow: MeshInstance3D
var _light: OmniLight3D
var _trail: GPUParticles3D
var _pulse: float = 0.0


func setup(origin: Vector3, direction: Vector3, speed: float, lifetime: float, dmg: int, push: float) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	life = lifetime
	damage = dmg
	knockback = push
	look_at(origin + direction, Vector3.UP)


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 16
	sphere.rings = 8
	var core_material: StandardMaterial3D = StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = CORE_COLOR
	core_material.emission_enabled = true
	core_material.emission = GLOW_COLOR
	core_material.emission_energy_multiplier = 3.2
	_glow = MeshInstance3D.new()
	_glow.mesh = sphere
	_glow.material_override = core_material
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)

	_light = OmniLight3D.new()
	_light.light_color = GLOW_COLOR
	_light.light_energy = 1.6
	_light.omni_range = 2.6
	add_child(_light)

	_trail = GPUParticles3D.new()
	_trail.amount = 26
	_trail.lifetime = 0.32
	_trail.local_coords = false
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 12.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.1
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.color = TRAIL_COLOR
	_trail.process_material = process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var trail_material: StandardMaterial3D = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	trail_material.albedo_color = TRAIL_COLOR
	quad.material = trail_material
	_trail.draw_pass_1 = quad
	_trail.emitting = true
	add_child(_trail)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_pulse += delta * 18.0
	if _glow != null:
		var scale_value: float = 1.0 + sin(_pulse) * 0.12
		_glow.scale = Vector3.ONE * scale_value
	if _light != null:
		_light.light_energy = 1.4 + sin(_pulse) * 0.35

	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 3)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to


func _impact(hit: Dictionary) -> void:
	var collider: Object = hit.get("collider")
	var point: Vector3 = hit.get("position", global_position)
	if collider != null and collider.has_method("apply_damage_at"):
		collider.apply_damage_at(damage, velocity.normalized() * knockback, point)
	elif collider != null and collider.has_method("apply_damage"):
		collider.apply_damage(damage, velocity.normalized() * knockback)
	_burst(point)
	queue_free()


func _burst(point: Vector3) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var burst: Node3D = Node3D.new()
	burst.name = "TideBurst"
	scene_root.add_child(burst)
	burst.global_position = point

	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.amount = 22
	particles.lifetime = 0.45
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.local_coords = false
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 85.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.5
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color = GLOW_COLOR
	particles.process_material = process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.85)
	quad.material = material
	particles.draw_pass_1 = quad
	burst.add_child(particles)
	particles.emitting = true

	var flash: OmniLight3D = OmniLight3D.new()
	flash.light_color = GLOW_COLOR
	flash.light_energy = 3.4
	flash.omni_range = 3.2
	burst.add_child(flash)

	var tween: Tween = create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.28)
	tween.parallel().tween_callback(burst.queue_free).set_delay(0.6)
