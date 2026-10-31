extends Node3D
## Imported UE/Fab weapon viewmodel. One node per weapon; every model carries its
## own scale / rotation / grip offset so a single constant is never shared across
## unrelated meshes. Assembly numbers live in data/combat_mvp.json and are
## playtest placeholders, not final art direction.
##
## Pivot space contract:
##   melee  → +Y runs from grip to tip
##   ranged → -Z is the muzzle direction

var weapon_id: String = ""
var _model: Node3D


## Build the model inside this node. `config` is one weapon's `viewmodel` block.
func setup(id: String, config: Dictionary) -> void:
	weapon_id = id
	var scene_path: String = str(config.get("model", ""))
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_warning("imported weapon %s: model not found %s" % [id, scene_path])
		return
	_model = packed.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	_model.scale = Vector3.ONE * float(config.get("scale", 1.0))
	_model.rotation_degrees = _vector(config.get("rotation", [0.0, 0.0, 0.0]))
	_model.position = _vector(config.get("offset", [0.0, 0.0, 0.0]))
	add_child(_model)
	_apply_materials(_model, config.get("textures", {}) as Dictionary, config.get("material", {}) as Dictionary)
	_disable_shadows(_model)


func _vector(values: Variant) -> Vector3:
	if values is Array and (values as Array).size() >= 3:
		var array: Array = values as Array
		return Vector3(float(array[0]), float(array[1]), float(array[2]))
	return Vector3.ZERO


## Textures are wired from the audited file set, never guessed from names:
## Sword_08 "M" was verified as R=AO / G=roughness / B=metallic by pairing it
## with the diffuse (non-metal grip sits on B=0, grip roughness on G high).
func _apply_materials(node: Node, textures: Dictionary, tint: Dictionary = {}) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance: MeshInstance3D = node as MeshInstance3D
		for surface: int in range(instance.mesh.get_surface_count()):
			instance.set_surface_override_material(surface, _surface_material(instance, surface, textures, tint))
	for child: Node in node.get_children():
		_apply_materials(child, textures, tint)


func _surface_material(instance: MeshInstance3D, surface: int, textures: Dictionary, tint: Dictionary = {}) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Keep whatever albedo the FBX already resolved unless the config overrides it.
	var original: Material = instance.get_active_material(surface)
	if original is BaseMaterial3D:
		var source: BaseMaterial3D = original as BaseMaterial3D
		material.albedo_color = source.albedo_color
		material.albedo_texture = source.albedo_texture
		material.metallic = source.metallic
		material.roughness = source.roughness
		material.resource_name = source.resource_name
	# 原包不带贴图的模型（如科幻刀）用纯色占位，不冒充原作者 PBR 效果。
	if tint.has("albedo_color"):
		material.albedo_color = Color(str(tint.albedo_color))
	if tint.has("metallic"):
		material.metallic = float(tint.metallic)
	if tint.has("roughness"):
		material.roughness = float(tint.roughness)
	if textures.has("albedo"):
		material.albedo_texture = load(str(textures.albedo)) as Texture2D
	if textures.has("normal"):
		material.normal_enabled = true
		material.normal_texture = load(str(textures.normal)) as Texture2D
	if textures.has("roughness"):
		material.roughness_texture = load(str(textures.roughness)) as Texture2D
	if textures.has("metallic"):
		material.metallic_texture = load(str(textures.metallic)) as Texture2D
	if textures.has("ao"):
		material.ao_enabled = true
		material.ao_texture = load(str(textures.ao)) as Texture2D
	if textures.has("emission"):
		material.emission_enabled = true
		material.emission_texture = load(str(textures.emission)) as Texture2D
		material.emission_energy_multiplier = 0.6
	# One packed ORM map: channel meaning is fixed by the audit, not by filename.
	if textures.has("orm"):
		var orm: Texture2D = load(str(textures.orm)) as Texture2D
		material.ao_enabled = true
		material.ao_texture = orm
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = orm
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture = orm
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	return material


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)
