extends Node3D
## (CodeBuddy) CombatGirls Katana pack assembled into a usable character.
##
## The FBX references its textures through the original author's desktop paths, so
## none of them resolve on import. Materials are therefore rebuilt here by material
## name and bound to the textures that ship in assets/characters/combatgirls/textures.
##
## Clips live in separate animation-only FBX files. They are merged into one
## AnimationPlayer at load time so the source FBX stays the single source of truth.
##
## Root motion: every clip animates the `root` bone's position. The character is
## driven by code, so that track is stripped — otherwise the mesh slides forward
## inside its own capsule and snaps back on loop.

const MODEL_PATH: String = "res://assets/characters/combatgirls/School_Katana_FullBody.fbx"

const CLIP_PATHS: Dictionary = {
	"idle": "res://assets/characters/combatgirls/animations/Idle.fbx",
	"walk": "res://assets/characters/combatgirls/animations/Walk.fbx",
	"run": "res://assets/characters/combatgirls/animations/Run.fbx",
	"attack1": "res://assets/characters/combatgirls/animations/Attack1.fbx",
	"attack2": "res://assets/characters/combatgirls/animations/Attack2.fbx",
	"attack3": "res://assets/characters/combatgirls/animations/Attack3.fbx",
	"skill1": "res://assets/characters/combatgirls/animations/Sp_Skill1.fbx",
}

const LOOPING: Array[String] = ["idle", "walk", "run"]

## material name in the FBX -> texture, roughness, transparency
const TEXTURES: Dictionary = {
	"Body": {"path": "res://assets/characters/combatgirls/textures/Body/Body.png", "roughness": 0.62},
	"Face": {"path": "res://assets/characters/combatgirls/textures/Body/Face.png", "roughness": 0.55},
	"Eye": {"path": "res://assets/characters/combatgirls/textures/Body/Eye.png", "roughness": 0.30},
	"Uniform": {"path": "res://assets/characters/combatgirls/textures/Cloth/Katana_Cloth_01.png", "roughness": 0.78},
	"Sporswear": {"path": "res://assets/characters/combatgirls/textures/Sportswear/Sportswear.png", "roughness": 0.72},
	"Hair": {"path": "res://assets/characters/combatgirls/textures/Hair/Katana_Hair_01.png", "roughness": 0.58},
	"Weapon_Katana": {"path": "res://assets/characters/combatgirls/textures/Weapon/Katana_01.png", "roughness": 0.35},
	"Acc_Glass": {"path": "res://assets/characters/combatgirls/textures/Cloth/Katana_Glass.png", "roughness": 0.12, "alpha": true},
}

## Meshes that make up each outfit. Exactly one body mesh may be visible at a time:
## Body_Full / Body_School_uniform / Body_Sportswear are three skin variants.
const OUTFITS: Dictionary = {
	"uniform": [
		"Body_School_uniform", "Cloth_School_uniform_Top", "Cloth_School_uniform_Skirt",
		"Cloth_School_uniform_Shoes", "Colth_School_uniform_Armband",
	],
	"sportswear": ["Body_Sportswear", "Sportswear_Top", "Sportswear_Pants", "Sportswear_Shoes"],
}

## Always visible regardless of outfit.
const SHARED_MESHES: Array[String] = [
	"Katana_Hair", "Acc_Glass", "Weapon_Katana", "Weapon_Katana_sheath",
]

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var outfit: String = "uniform"
var face_index: int = 1
var clip_names: Array[String] = []

var _meshes: Dictionary = {}
var _faces: Array[String] = []
var _current_clip: String = ""


func _ready() -> void:
	_instantiate_model()
	_build_materials()
	_nudge_eye_surfaces()
	_merge_clips()
	_apply_outfit(outfit)
	set_face(face_index)
	play("idle")


func _instantiate_model() -> void:
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("KatanaGirl: model missing at " + MODEL_PATH)
		return
	var model: Node = packed.instantiate()
	model.name = "Model"
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_collect_meshes(model)
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)
	# Track paths in the clips are written as "Skeleton3D:bone", so the player's
	# root has to be the node that owns Skeleton3D — i.e. the model root.
	animation_player.root_node = animation_player.get_path_to(model)


func _collect_meshes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			_meshes[str(child.name)] = child
			if str(child.name).begins_with("Face_"):
				_faces.append(str(child.name))
		_collect_meshes(child)
	_faces.sort()


## Rebuild every material from the packed textures. The imported materials are all
## blank because the FBX points at the author's local disk.
func _build_materials() -> void:
	var cache: Dictionary = {}
	for mesh_name: String in _meshes:
		var mesh_node: MeshInstance3D = _meshes[mesh_name]
		if mesh_node.mesh == null:
			continue
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var source: Material = mesh_node.mesh.surface_get_material(surface)
			var key: String = source.resource_name if source != null else "Body"
			if not cache.has(key):
				cache[key] = _make_material(key)
			mesh_node.set_surface_override_material(surface, cache[key])


func _make_material(key: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = key
	var spec: Dictionary = TEXTURES.get(key, {})
	if spec.is_empty():
		# Unknown slot: keep it visibly neutral rather than pure white.
		material.albedo_color = Color(0.7, 0.7, 0.72)
		return material
	material.albedo_texture = load(str(spec.path)) as Texture2D
	material.roughness = float(spec.get("roughness", 0.7))
	material.metallic = 0.0
	material.metallic_specular = 0.4
	if bool(spec.get("alpha", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 1, 1, 0.35)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Push the iris surface ~1.5 mm along its normal. The eye mesh sits inside the face
## mesh, so with the depth test on the iris is half-occluded and reads as a red ring;
## turning the depth test off instead lets the eyes show through the back of the head.
func _nudge_eye_surfaces() -> void:
	for mesh_name: String in _meshes:
		if not mesh_name.begins_with("Face_"):
			continue
		var node: MeshInstance3D = _meshes[mesh_name]
		var source: ArrayMesh = node.mesh as ArrayMesh
		if source == null:
			continue
		var rebuilt: ArrayMesh = ArrayMesh.new()
		for surface: int in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface)
			var material: Material = source.surface_get_material(surface)
			if material != null and material.resource_name == "Eye":
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i: int in range(vertices.size()):
					vertices[i] = vertices[i] + normals[i] * 0.0015
				arrays[Mesh.ARRAY_VERTEX] = vertices
			rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, material)
		node.mesh = rebuilt


## Merge the separate animation FBX files into this character's AnimationPlayer.
func _merge_clips() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	animation_player.add_animation_library("", library)
	for clip: String in CLIP_PATHS:
		var packed: PackedScene = load(str(CLIP_PATHS[clip])) as PackedScene
		if packed == null:
			push_warning("KatanaGirl: clip missing " + str(CLIP_PATHS[clip]))
			continue
		var scene: Node = packed.instantiate()
		var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			scene.free()
			continue
		var animation: Animation = null
		for lib_name: StringName in player.get_animation_library_list():
			var source_library: AnimationLibrary = player.get_animation_library(lib_name)
			for anim_name: StringName in source_library.get_animation_list():
				animation = source_library.get_animation(anim_name)
				break
			if animation != null:
				break
		scene.free()
		if animation == null:
			continue
		var copy: Animation = animation.duplicate(true) as Animation
		_strip_root_motion(copy)
		if LOOPING.has(clip):
			copy.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip, copy)
		clip_names.append(clip)


## Two cleanups that the source clips need before they can drive this rig:
## 1. the `root` bone's position track is baked-in root motion, and the character is
##    moved by code;
## 2. the `Skeleton3D/add_*` tracks point at helper empties from the author's Unity
##    rig, which do not exist here (the same data already comes through as bone
##    tracks), so they only produce unresolved-track warnings.
func _strip_root_motion(animation: Animation) -> void:
	for track: int in range(animation.get_track_count() - 1, -1, -1):
		var path: NodePath = animation.track_get_path(track)
		var bone: String = str(path.get_concatenated_subnames())
		if bone.is_empty():
			if str(path.get_concatenated_names()).begins_with("Skeleton3D/add_"):
				animation.remove_track(track)
			continue
		if bone == "root" and animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
			animation.remove_track(track)


func play(clip: String, blend: float = 0.12) -> void:
	if animation_player == null or not animation_player.has_animation(clip):
		return
	if _current_clip == clip:
		return
	_current_clip = clip
	animation_player.play(clip, blend)


func play_once(clip: String) -> float:
	if animation_player == null or not animation_player.has_animation(clip):
		return 0.0
	_current_clip = clip
	animation_player.play(clip, 0.08)
	return animation_player.get_animation(clip).length


func current_clip() -> String:
	return _current_clip


func set_outfit(value: String) -> void:
	if not OUTFITS.has(value):
		return
	outfit = value
	_apply_outfit(value)


func _apply_outfit(value: String) -> void:
	var visible_set: Array = OUTFITS[value]
	for mesh_name: String in _meshes:
		if mesh_name.begins_with("Face_"):
			continue
		var should_show: bool = SHARED_MESHES.has(mesh_name) or visible_set.has(mesh_name)
		(_meshes[mesh_name] as MeshInstance3D).visible = should_show


func set_face(index: int) -> void:
	face_index = clampi(index, 1, maxi(_faces.size(), 1))
	for mesh_name: String in _faces:
		(_meshes[mesh_name] as MeshInstance3D).visible = mesh_name == ("Face_%02d" % face_index)


func face_count() -> int:
	return _faces.size()
