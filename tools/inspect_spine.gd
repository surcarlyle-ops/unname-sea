extends SceneTree
## Temporary diagnostic: dump rest vs idle-frame-0 euler for the torso chain.

var _frame: int = 0
var _inst: Node = null
const TARGETS := ["hips", "spine", "spine1", "spine2", "chest", "neck", "head"]


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var scene: PackedScene = load("res://scenes/mvp/player_3d.tscn")
		_inst = scene.instantiate()
		get_root().add_child(_inst)
	elif _frame >= 3:
		var skel: Skeleton3D = _inst.find_child("Skeleton3D", true, false) as Skeleton3D
		var ap: AnimationPlayer = _inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if skel == null or ap == null:
			print("MISSING skeleton or player")
			return true
		print("=== REST (euler degrees) ===")
		for i in range(skel.get_bone_count()):
			var bone_name: String = skel.get_bone_name(i)
			var lower: String = bone_name.to_lower()
			for tgt: String in TARGETS:
				if lower.ends_with(tgt):
					var e: Vector3 = skel.get_bone_rest(i).basis.get_euler() * (180.0 / PI)
					print("%-28s rest=(%6.1f, %6.1f, %6.1f)" % [bone_name, e.x, e.y, e.z])
					break
		var anim: Animation = ap.get_animation(&"idle")
		if anim != null:
			print("=== IDLE frame 0 (euler degrees) ===")
			for t in range(anim.get_track_count()):
				if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				var path: String = str(anim.track_get_path(t))
				var lower: String = path.to_lower()
				for tgt: String in TARGETS:
					if lower.ends_with(tgt):
						var q: Quaternion = anim.track_get_key_value(t, 0)
						var e: Vector3 = q.get_euler() * (180.0 / PI)
						print("%-28s anim=(%6.1f, %6.1f, %6.1f)" % [path.get_slice(":", 1), e.x, e.y, e.z])
						break
		print("=== DONE ===")
		quit()
		return true
	return false
