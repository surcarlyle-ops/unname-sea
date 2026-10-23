extends SceneTree
## (CodeBuddy) Throwaway inspection: animation clips and their track paths.

const ANIMS: Array[String] = [
	"res://assets/characters/combatgirls/animations/Idle.fbx",
	"res://assets/characters/combatgirls/animations/Walk.fbx",
	"res://assets/characters/combatgirls/animations/Run.fbx",
	"res://assets/characters/combatgirls/animations/Attack1.fbx",
	"res://assets/characters/combatgirls/animations/Attack2.fbx",
	"res://assets/characters/combatgirls/animations/Attack3.fbx",
	"res://assets/characters/combatgirls/animations/Sp_Skill1.fbx",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: PackedScene = load("res://assets/characters/combatgirls/School_Katana_FullBody.fbx") as PackedScene
	var model_scene: Node = model.instantiate()
	root.add_child(model_scene)
	var model_skeleton: Skeleton3D = model_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	print("MODEL root=%s  skeleton=%s bones=%d" % [model_scene.name, model_skeleton != null, model_skeleton.get_bone_count() if model_skeleton != null else -1])
	print("MODEL bone0=%s bone1=%s bone2=%s" % [
		model_skeleton.get_bone_name(0), model_skeleton.get_bone_name(1), model_skeleton.get_bone_name(2)])
	for path: String in ANIMS:
		var packed: PackedScene = load(path) as PackedScene
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			print("%s NO_PLAYER" % path.get_file())
			scene.queue_free()
			continue
		var skeleton: Skeleton3D = scene.find_child("Skeleton3D", true, false) as Skeleton3D
		print("%s  root=%s  skeleton_bones=%d" % [path.get_file(), scene.name, skeleton.get_bone_count() if skeleton != null else -1])
		for lib_name: StringName in player.get_animation_library_list():
			var library: AnimationLibrary = player.get_animation_library(lib_name)
			for anim_name: StringName in library.get_animation_list():
				var animation: Animation = library.get_animation(anim_name)
				print("   clip='%s' len=%.3fs tracks=%d" % [anim_name, animation.length, animation.get_track_count()])
				for t: int in range(mini(3, animation.get_track_count())):
					print("      track[%d] %s (%d)" % [t, animation.track_get_path(t), animation.track_get_type(t)])
				# Any track that animates a node rather than a bone would be root motion.
				for t: int in range(animation.get_track_count()):
					var track: NodePath = animation.track_get_path(t)
					if not str(track).contains(":"):
						print("      NODE-LEVEL TRACK: ", track)
		scene.queue_free()
	quit(0)
