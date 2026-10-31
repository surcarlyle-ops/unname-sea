extends Node3D
## Skinned fingerless gloves. Finger poses stay separate from camera locomotion.

const GLOVE_SCRIPT: Script = preload("res://scripts/mvp/fps_glove.gd")
const SWORD_TRAIL_SCRIPT: Script = preload("res://scripts/mvp/sword_trail.gd")  ## (Claude Code) swing ribbon
const TIDE_BLADE_SCENE: PackedScene = preload("res://assets/weapons/tide_blade_long.glb")
const PISTOL_SCENE: PackedScene = preload("res://assets/weapons/steampunk_pistol.glb")
const M1911_SCRIPT: Script = preload("res://scripts/mvp/m1911_viewmodel.gd")
const FISHING_ROD_SCRIPT: Script = preload("res://scripts/mvp/fishing_rod_viewmodel.gd")
## Imported UE/Fab weapons: one pivot per weapon, assembled from its own config.
const IMPORTED_SCRIPT: Script = preload("res://scripts/mvp/imported_weapon_viewmodel.gd")
const WEAPON_DATA_PATH: String = "res://data/combat_mvp.json"
## 手炮与 M1911 沿用原有装配；其余枪械由 JSON viewmodel 配置生成。
const PISTOL_IDS: Array[String] = ["steam_pistol", "m1911"]

# 枪沿模型 X 轴延伸（枪口 -X），绕 Y 转 -90 度后枪口指向相机前方 -Z。
const PISTOL_SCALE: float = 0.42
const PISTOL_OFFSET: Vector3 = Vector3(0.02, -0.06, -0.02)
const PISTOL_ROTATION: Vector3 = Vector3(0.0, -84.0, 0.0)
# 掏枪动画：从下方升起，同时绕枪管轴转两圈后归位。
const PISTOL_SPAWN_DURATION: float = 0.75
const PISTOL_SPAWN_RISE: float = 0.34
const PISTOL_SPAWN_TURNS: float = 2.0

# 挥砍轨迹：从 CC0 Arms.fbx 提取的手腕轨迹与逐指姿势。
const SLASH_TRACKS_PATH: String = "res://assets/characters/fps_gloves/sword_slash_tracks.json"

# 其余动作：持剑行走、格挡、左手施法、喝药。
const ACTION_TRACKS_PATH: String = "res://assets/characters/fps_gloves/action_tracks.json"
## Sword_Walk 的手腕位移只有毫米级，摆动全在旋转上，这里放大旋转让它看得出来。
const WALK_ROT_GAIN: float = 1.1
const WALK_POS_GAIN: float = 1.0
## 左手待机位置在画面下方外，施法必须把整条手臂抬进视野，因此放大位移。
const SPELL_POS_SCALE: float = 1.7
## 格挡源片段只有 0.13 秒且幅度极小，需要放大才看得出是防御姿态。
const BLOCK_POS_GAIN: float = 4.0
const BLOCK_ROT_GAIN: float = 2.2
## 喝药的源位移约 0.2 米，放大后才够把瓶子送到嘴边。
const DRINK_POS_SCALE: float = 1.5
## 瓶子淡入淡出所占的进度比例。
const DRINK_FADE: float = 0.18
const BOTTLE_SCRIPT: Script = preload("res://scripts/mvp/potion_bottle.gd")

# The curled fingers enclose a handle across the palm's X axis, not the palm normal Y.
const TIDE_SCALE: float = 0.96
const TIDE_GRIP_Y: float = 0.18
const TIDE_BLADE_YAW: float = 65.0
const GRIP_CENTER: Vector3 = Vector3(0.0, -0.037, -0.110)
# 入场动画：抛出 → 空中翻转 → 稳稳落回手中。
const TIDE_SPAWN_DURATION: float = 1.35
const TIDE_SPAWN_HEIGHT: float = 0.22
const TIDE_SPAWN_TURNS: float = 4.0

var right_arm: Node3D
var left_arm: Node3D
var weapon_root: Node3D
var _practice_model: Node3D
var _tide_blade: Node3D
var _tide_pivot: Node3D
var _tide_glow: MeshInstance3D
var _tide_glow_material: ShaderMaterial
var _pistol: Node3D
var _pistol_pivot: Node3D
var _m1911_pivot: Node3D
var _pistol_base_pos: Vector3
var _pistol_base_quat: Quaternion
var _pistol_grip_pose: Dictionary = {}
var _pistol_spawn: float = 0.0
var _slash_tracks: Dictionary = {}
var _sword_motion: Dictionary = {}
var _slash_wrist_bent: bool = false
var _action_tracks: Dictionary = {}
var _block_kind: String = ""
var _block_weight: float = 0.0
var _spell_playing: bool = false
var _spell_time: float = 0.0
var _drink_playing: bool = false
var _drink_time: float = 0.0
var _bottle: Node3D
var _bottle_pivot: Node3D
var _weapon_id: String = ""
var _spawn_time: float = 0.0
var _spawn_base_y: float = 0.0
var attack_pose: float = 0.0
var _run_blend: float = 0.0
var _slide_blend: float = 0.0
var _climb_blend: float = 0.0
var _bob_blend: float = 0.0
var _wallrun_blend: float = 0.0
var _wallrun_side: float = 0.0
var _near_wall: float = 0.0
var _equip_blend: float = 0.0
var _empty_move_blend: float = 0.0
var _grapple_blend: float = 0.0
var _rope_wrist_bent: bool = false
var _grapple_age: float = 0.0
var _grapple_was_active: bool = false
var _grapple_follow: Vector3 = Vector3.ZERO
var _grapple_start_distance: float = 0.0
var _grapple_reel: float = 0.0
var _grapple_swing: float = 0.0
var _pistol_recoil_left: float = 0.0
var _state_offset: Vector3 = Vector3.ZERO
var _state_angles: Vector3 = Vector3.ZERO
var _landing_time: float = 0.0
var _landing_strength: float = 0.0
var _presentation: Dictionary = {}
var _leather: StandardMaterial3D
var _steel: StandardMaterial3D
var _brass: StandardMaterial3D
var right_glove: Node3D
var left_glove: Node3D
var trail: Node3D  ## (Claude Code) world-space swing ribbon, driven from update_pose
## id → pivot node for the imported batch, plus the melee/ranged split used by
## the existing slash and bolt paths.
var _imported: Dictionary = {}
var _fishing_rod: Node3D
var _fishing_controller: WeakRef
var _melee_ids: Array[String] = ["practice_blade", "tide_blade"]
var _ranged_ids: Array[String] = ["steam_pistol", "m1911"]


func _ready() -> void:
	_presentation = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_person_presentation.json")) as Dictionary
	_leather = _material(Color("533f34"))
	_steel = _material(Color("c7dbd3"))
	_brass = _material(Color("c6a16b"))
	right_arm = _arm("RightArm", 1.0)
	left_arm = _arm("LeftArm", -1.0)
	# (Claude Code) Trail mesh is created once and re-pointed whenever the weapon changes.
	trail = Node3D.new()
	trail.name = "SwordTrail"
	trail.set_script(SWORD_TRAIL_SCRIPT)
	add_child(trail)
	weapon_root = Node3D.new()
	weapon_root.name = "ReplaceableWeapon"
	weapon_root.scale = Vector3.ONE * 0.65
	right_arm.add_child(weapon_root)
	weapon_root.position = GRIP_CENTER
	# Blade exits on the thumb/index side (-X), pommel on the little-finger side.
	weapon_root.rotation.z = PI * 0.5
	# 练习刃：程序化占位剑。
	_practice_model = Node3D.new()
	_practice_model.name = "PracticeBlade"
	weapon_root.add_child(_practice_model)
	_box(_practice_model, Vector3(0.0, -0.04, 0.0), Vector3(0.065, 0.23, 0.065), _leather)
	_box(_practice_model, Vector3(0.0, 0.09, 0.0), Vector3(0.23, 0.045, 0.09), _brass)
	_box(_practice_model, Vector3(0.0, 0.33, 0.0), Vector3(0.13, 0.45, 0.045), _steel)
	var tip: PrismMesh = PrismMesh.new()
	tip.size = Vector3(0.13, 0.16, 0.045)
	_mesh(_practice_model, tip, Vector3(0.0, 0.635, 0.0), _steel)
	_build_tide_blade()
	_build_pistol()
	_build_m1911()
	_configure_pistol_grips()
	_build_imported_weapons()
	_build_bottle()
	_build_fishing_rod()
	_sword_motion = JSON.parse_string(FileAccess.get_file_as_string("res://data/sword_viewmodel_motion.json")) as Dictionary
	_load_slash_tracks()
	_load_action_tracks()
	update_pose(0.0, 0.0, false, -1.0, 0, false, 1.0)


func _build_fishing_rod() -> void:
	_fishing_rod = Node3D.new()
	_fishing_rod.name = "FishingRod"
	_fishing_rod.set_script(FISHING_ROD_SCRIPT)
	right_arm.add_child(_fishing_rod)
	_fishing_rod.position = GRIP_CENTER
	_fishing_rod.rotation.z = PI * 0.5
	_fishing_rod.visible = false


func set_fishing_presentation(state: String, progress: float = 0.0) -> void:
	_fishing_rod.set_phase(state, progress)


func fishing_tip_world() -> Vector3:
	return _fishing_rod.tip_world_position()


func fishing_tip_anchor() -> Node3D:
	return _fishing_rod.get_node("LineExit") as Node3D


func bind_fishing_controller(controller: Node) -> void:
	# Optional passive adapter for FishingMVP; gameplay retains every state transition.
	_fishing_controller = weakref(controller) if is_instance_valid(controller) else null
	_fishing_rod.reset_presentation()


func _sync_fishing_controller() -> void:
	if _fishing_controller == null:
		return
	var controller: Node = _fishing_controller.get_ref() as Node
	if not is_instance_valid(controller):
		_fishing_controller = null
		_fishing_rod.reset_presentation()
		return
	var state: int = int(controller.get("state"))
	var names: Array[String] = ["idle", "casting", "waiting", "biting", "reeling"]
	var progress: float = 0.0
	if state == 1:
		progress = float(controller.call("cast_progress"))
	elif state == 3 and controller.has_method("bite_progress"):
		progress = float(controller.call("bite_progress"))
	elif state == 4:
		progress = float(controller.call("reveal_progress"))
	set_fishing_presentation(names[clampi(state, 0, names.size() - 1)], progress)


func _align_fishing_forearm() -> void:
	# Keep the cropped sleeve on the known equipped axis while the wrist tilts the rod.
	var skeleton: Skeleton3D = right_glove.skeleton
	var forearm: int = skeleton.find_bone("Forearm")
	var hand: int = skeleton.find_bone("Hand")
	var cfg: Dictionary = _fishing_rod.config
	var base: Quaternion = Quaternion.from_euler(_presentation_vector(cfg.hand_degrees) * PI / 180.0)
	var target: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(float(cfg.forearm_tilt_degrees))) * base
	var bend: Quaternion = right_arm.quaternion.inverse() * target
	var hand_position: Vector3 = skeleton.get_bone_rest(hand).origin
	skeleton.set_bone_pose_position(forearm, -(bend * hand_position))
	skeleton.set_bone_pose_rotation(forearm, bend)
	skeleton.set_bone_pose_rotation(hand, bend.inverse())
	_slash_wrist_bent = true


func _build_bottle() -> void:
	_bottle_pivot = Node3D.new()
	_bottle_pivot.name = "PotionBottle"
	_bottle_pivot.position = GRIP_CENTER + Vector3(0.0, -0.015, 0.015)
	right_arm.add_child(_bottle_pivot)
	_bottle = Node3D.new()
	_bottle.name = "BottleMesh"
	_bottle.set_script(BOTTLE_SCRIPT)
	_bottle_pivot.add_child(_bottle)
	_bottle.visible = false


func _load_slash_tracks() -> void:
	if not FileAccess.file_exists(SLASH_TRACKS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SLASH_TRACKS_PATH))
	if parsed is Dictionary:
		_slash_tracks = parsed as Dictionary


func _load_action_tracks() -> void:
	if not FileAccess.file_exists(ACTION_TRACKS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACTION_TRACKS_PATH))
	if parsed is Dictionary:
		_action_tracks = parsed as Dictionary


## 取某个动作在给定进度下的帧（60fps 采样，取最近帧足够）。
func _action_frame(key: String, progress: float) -> Dictionary:
	if not _action_tracks.has(key):
		return {}
	var track: Dictionary = _action_tracks[key] as Dictionary
	var frames: Array = track.get("frames", []) as Array
	if frames.is_empty():
		return {}
	var duration: float = float(track.get("duration", 1.0))
	var t: float = clampf(progress, 0.0, 1.0) * duration
	var index: int = clampi(int(t * 60.0), 0, frames.size() - 1)
	return frames[index] as Dictionary


## 把四元数限制在最大角度内，避免放大后翻转。
func _clamp_quaternion_angle(value: Quaternion, max_angle: float) -> Quaternion:
	var normalized: Quaternion = value.normalized()
	if normalized.w < 0.0:
		normalized = Quaternion(-normalized.x, -normalized.y, -normalized.z, -normalized.w)
	var angle: float = normalized.get_angle()
	if angle <= max_angle:
		return normalized
	var axis: Vector3 = normalized.get_axis()
	if axis.length_squared() < 0.5:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), max_angle)


## 按角度缩放四元数，用于放大源动作里幅度很小的摆动。
func _scale_quaternion(value: Quaternion, gain: float) -> Quaternion:
	var normalized: Quaternion = value.normalized()
	if normalized.w < 0.0:
		normalized = Quaternion(-normalized.x, -normalized.y, -normalized.z, -normalized.w)
	var angle: float = normalized.get_angle()
	if absf(angle) < 0.0001:
		return Quaternion.IDENTITY
	var axis: Vector3 = normalized.get_axis()
	if axis.length_squared() < 0.5:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), angle * gain)


## 供外部调用：设置格挡姿势预览，weight 0..1 平滑过渡。
## 本轮只提供姿势通道，不接按键或伤害判定；后续加玩法时直接驱动这里即可。
func set_block_preview(kind: String, weight: float) -> void:
	_block_kind = kind
	_block_weight = clampf(weight, 0.0, 1.0)


func block_active() -> bool:
	return _block_weight > 0.001 and not _block_kind.is_empty()


## 供外部调用：开始喝药。源动作 0.46 秒，瓶子在首尾各淡入淡出 18%。
func start_drink() -> void:
	if not _action_tracks.has("Drink"):
		return
	_drink_playing = true
	_drink_time = 0.0
	if is_instance_valid(_bottle):
		_bottle.visible = true
		_bottle.call("set_fill", 1.0)
		_bottle.call("set_alpha", 0.0)


func stop_drink() -> void:
	_drink_playing = false
	_drink_time = 0.0
	right_glove.clear_pose_override()
	if is_instance_valid(_bottle):
		_bottle.visible = false


func drink_active() -> bool:
	return _drink_playing


func _drink_progress() -> float:
	var track: Dictionary = _action_tracks.get("Drink", {}) as Dictionary
	var duration: float = float(track.get("duration", 1.0))
	if duration <= 0.0:
		return 0.0
	return clampf(_drink_time / duration, 0.0, 1.0)


## 喝药：右手与瓶子一起动，剑在此期间由 show_weapon 逻辑隐藏。
## 手指姿势由 update_pose 的 override 分支统一挂载，这里只驱动手臂与瓶子。
func _apply_drink(progress: float) -> void:
	var frame: Dictionary = _action_frame("Drink", progress)
	if frame.is_empty():
		return
	var delta: Array = frame.wrist_delta as Array
	var delta_quat: Array = frame.wrist_delta_quat as Array
	right_arm.position += Vector3(float(delta[0]), float(delta[1]), float(delta[2])) * DRINK_POS_SCALE
	var quat: Quaternion = Quaternion(float(delta_quat[0]), float(delta_quat[1]), float(delta_quat[2]), float(delta_quat[3]))
	right_arm.quaternion = right_arm.quaternion * quat
	# 饮用段液面下降，呼应"喝掉了"。
	if is_instance_valid(_bottle):
		var fill: float = 1.0
		if progress > 0.30:
			fill = lerpf(1.0, 0.15, clampf((progress - 0.30) / 0.45, 0.0, 1.0))
		_bottle.call("set_fill", fill)


## 供外部调用：播放左手施法动作。本轮只提供动作通道，不绑定按键或玩法。
func start_left_spell() -> void:
	if not _action_tracks.has("Left_Spell"):
		return
	_spell_playing = true
	_spell_time = 0.0


func stop_left_spell() -> void:
	_spell_playing = false
	_spell_time = 0.0
	if is_instance_valid(left_glove):
		left_glove.clear_pose_override()


## 左手施法：只驱动左臂与左手，右手和剑保持原状。
func _apply_left_spell(progress: float) -> void:
	var frame: Dictionary = _action_frame("Left_Spell", progress)
	if frame.is_empty():
		return
	var fingers: Dictionary = frame.get("fingers", {}) as Dictionary
	if not fingers.is_empty():
		left_glove.apply_pose_override(fingers, 1.0)
		left_glove.set_pose_immediate(left_glove.grip)
	var delta: Array = frame.wrist_delta as Array
	var delta_quat: Array = frame.wrist_delta_quat as Array
	# 源坐标 Z 正向是远离躯干，目标相机空间 Z 负向才是向前，需要取反；
	# 再向中间收一点，让施法手落在视野内而不是贴着左边缘。
	left_arm.position += Vector3(float(delta[0]), float(delta[1]), -float(delta[2])) * SPELL_POS_SCALE
	left_arm.position.x += 0.12 * SPELL_POS_SCALE
	var quat: Quaternion = Quaternion(float(delta_quat[0]), float(delta_quat[1]), float(delta_quat[2]), float(delta_quat[3]))
	left_arm.quaternion = left_arm.quaternion * quat


## 格挡是单帧姿势（源动画只有 0.13 秒）。
## 第 0 帧就是基准帧、delta 为零，必须取末帧才是格挡到位姿势。
func _block_frame(kind: String) -> Dictionary:
	var key: String = "Sword_Block" if kind == "sword" else "Fists_Block"
	return _action_frame(key, 1.0)


## 格挡的手臂部分；手指部分在 set_grip 之前通过 override 通道写入。
func _apply_block_arm(kind: String, weight: float) -> void:
	var frame: Dictionary = _block_frame(kind)
	if frame.is_empty():
		return
	# 空手格挡的源幅度约为持剑的二十倍，需要分开设增益，否则会甩出画面。
	var pos_gain: float = BLOCK_POS_GAIN if kind == "sword" else BLOCK_POS_GAIN * 0.35
	var rot_gain: float = BLOCK_ROT_GAIN if kind == "sword" else BLOCK_ROT_GAIN * 0.6
	var delta: Array = frame.wrist_delta as Array
	var delta_quat: Array = frame.wrist_delta_quat as Array
	right_arm.position += Vector3(float(delta[0]), float(delta[1]), float(delta[2])) * weight * pos_gain
	var quat: Quaternion = Quaternion(float(delta_quat[0]), float(delta_quat[1]), float(delta_quat[2]), float(delta_quat[3]))
	# 源末帧的旋转接近 180°，放大后会把手和剑整个翻过去、袖口截面朝镜头。
	# 这里把最终旋转限制在 35° 以内，只保留"抬起来挡"的姿态。
	var limited: Quaternion = _clamp_quaternion_angle(_scale_quaternion(quat, rot_gain), deg_to_rad(35.0))
	right_arm.quaternion = right_arm.quaternion * Quaternion.IDENTITY.slerp(limited, weight)


## 持剑行走：源动画的手腕位移只有毫米级，摆动几乎全在旋转上。
## 因此保留原有 bob 提供上下起伏，这里只把源旋转放大后叠加，避免两套位移互相抵消。
func _apply_walk_sway(stride_phase: float, weight: float) -> void:
	if weight <= 0.001:
		return
	# stride_phase 每步走完一圈，而源动画 0.92 秒是两步一个循环；
	# 不减半会让摆动频率翻倍，看起来像高频抽搐。
	var progress: float = fmod(stride_phase / TAU * 0.5, 1.0)
	var frame: Dictionary = _action_frame("Sword_Walk", progress)
	if frame.is_empty():
		return
	var delta: Array = frame.wrist_delta as Array
	var delta_quat: Array = frame.wrist_delta_quat as Array
	var quat: Quaternion = Quaternion(float(delta_quat[0]), float(delta_quat[1]), float(delta_quat[2]), float(delta_quat[3]))
	right_arm.position += Vector3(float(delta[0]), float(delta[1]), float(delta[2])) * WALK_POS_GAIN * weight
	right_arm.quaternion = right_arm.quaternion * Quaternion.IDENTITY.slerp(_scale_quaternion(quat, WALK_ROT_GAIN), weight)


## 按攻击进度取最近一帧（源数据 60fps，足够密）。
func _slash_frame(progress: float, index: int) -> Dictionary:
	var key: String = "Sword_Slash1" if index == 0 else "Sword_Slash2"
	if not _slash_tracks.has(key):
		return {}
	var track: Dictionary = _slash_tracks[key] as Dictionary
	var frames: Array = track.get("frames", []) as Array
	if frames.is_empty():
		return {}
	var duration: float = float(track.get("duration", 1.0))
	var t: float = clampf(progress, 0.0, 1.0) * duration
	var frame_index: int = clampi(int(t * 60.0), 0, frames.size() - 1)
	return frames[frame_index] as Dictionary


## Camera-space arcs: windup, outward cut, follow-through, then recovery.
## Aim the actual blade axis instead of guessing the rotated glove's local axes.
func _apply_slash_arm(progress: float, index: int) -> void:
	var vertical: Dictionary = _sword_motion.get("vertical_swings", {}) as Dictionary
	if vertical.has(_weapon_id):
		_apply_vertical_chop(progress, vertical[_weapon_id] as Array)
		return
	var keys: Array = _sword_motion.swings[index % 2] as Array
	_apply_blade_arc(progress, keys)


func _apply_vertical_chop(progress: float, keys: Array) -> void:
	var p: float = clampf(progress, 0.0, 1.0)
	for i: int in range(keys.size() - 1):
		var a: Dictionary = keys[i] as Dictionary
		var b: Dictionary = keys[i + 1] as Dictionary
		if p > float(b.t) and i < keys.size() - 2:
			continue
		var weight: float = smoothstep(float(a.t), float(b.t), p)
		var pitch: float = deg_to_rad(lerpf(float(a.pitch), float(b.pitch), weight))
		right_arm.position += _presentation_vector(a.offset).lerp(_presentation_vector(b.offset), weight)
		# Rotate around camera-space horizontal X, preserving the grip roll/yaw.
		# Repeating a single pitch arc avoids the old alternating sideways slashes.
		right_arm.quaternion = Quaternion(Vector3.RIGHT, pitch) * right_arm.quaternion
		_align_slash_forearm(0.60 * smoothstep(0.0, 0.20, p) * (1.0 - smoothstep(0.72, 1.0, p)))
		return


func _apply_blade_arc(progress: float, keys: Array) -> void:
	var p: float = clampf(progress, 0.0, 1.0)
	var neutral: Quaternion = right_arm.quaternion
	var neutral_blade: Vector3 = (neutral * (weapon_root.quaternion * Vector3.UP)).normalized()
	for i: int in range(keys.size() - 1):
		var a: Dictionary = keys[i] as Dictionary
		var b: Dictionary = keys[i + 1] as Dictionary
		if p > float(b.t) and i < keys.size() - 2:
			continue
		var weight: float = smoothstep(float(a.t), float(b.t), p)
		var va: Array = a.offset as Array
		var vb: Array = b.offset as Array
		var offset: Vector3 = Vector3(va[0], va[1], va[2]).lerp(Vector3(vb[0], vb[1], vb[2]), weight)
		var direction_a: Vector3 = neutral_blade if i == 0 else _slash_direction(a)
		var direction_b: Vector3 = neutral_blade if i + 1 == keys.size() - 1 else _slash_direction(b)
		var blade: Vector3 = direction_a.slerp(direction_b, weight).normalized()
		var sleeve_weight: float = weight if i == 0 else (1.0 - weight if i + 1 == keys.size() - 1 else 1.0)
		var sleeve: Vector3 = (neutral * Vector3.BACK).lerp(Vector3(0.2, -0.35, 1.0), sleeve_weight)
		right_arm.position += offset
		right_arm.quaternion = _slash_rotation(blade, sleeve)
		_align_slash_forearm(smoothstep(0.0, 0.20, p) * (1.0 - smoothstep(0.72, 1.0, p)))
		return


func _slash_direction(key: Dictionary) -> Vector3:
	var values: Array = key.blade as Array
	return Vector3(values[0], values[1], values[2]).normalized()


func _slash_rotation(blade: Vector3, sleeve_direction: Vector3) -> Quaternion:
	# The glove's +Z points from wrist to sleeve. Constrain this second axis
	# toward the shoulder; shortest-arc blade alignment alone can flip the cuff.
	var sleeve: Vector3 = (sleeve_direction - blade * sleeve_direction.dot(blade)).normalized()
	var x_axis: Vector3 = -blade
	var y_axis: Vector3 = sleeve.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, x_axis.cross(y_axis)).get_rotation_quaternion()


func _align_slash_forearm(weight: float) -> void:
	# Use the existing forearm/wrist joints independently: the shoulder stays
	# below the camera while the hand and attached sword retain their exact pose.
	var skeleton: Skeleton3D = right_glove.skeleton
	var forearm: int = skeleton.find_bone("Forearm")
	var hand: int = skeleton.find_bone("Hand")
	var toward_shoulder: Vector3 = (Vector3(0.48, -0.95, 0.05) - right_arm.position).normalized()
	var local_direction: Vector3 = right_arm.quaternion.inverse() * toward_shoulder
	var bend: Quaternion = Quaternion(Vector3.BACK, local_direction)
	bend = Quaternion.IDENTITY.slerp(bend, weight)
	var hand_position: Vector3 = skeleton.get_bone_rest(hand).origin
	skeleton.set_bone_pose_position(forearm, -(bend * hand_position))
	skeleton.set_bone_pose_rotation(forearm, bend)
	skeleton.set_bone_pose_rotation(hand, bend.inverse())
	_slash_wrist_bent = true


func _reset_slash_forearm() -> void:
	if not _slash_wrist_bent:
		return
	var skeleton: Skeleton3D = right_glove.skeleton
	for name: String in ["Forearm", "Hand"]:
		var bone: int = skeleton.find_bone(name)
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		skeleton.set_bone_pose_position(bone, rest.origin)
		skeleton.set_bone_pose_rotation(bone, rest.basis.get_rotation_quaternion())
	_slash_wrist_bent = false


func _build_pistol() -> void:
	if PISTOL_SCENE == null:
		return
	_pistol_pivot = Node3D.new()
	_pistol_pivot.name = "PistolPivot"
	# 右臂持械姿态带一个为握剑设计的 Z 轴大旋转，枪会跟着被拧成竖直。
	# 用逆四元数抵消手臂的静态姿态，让枪在世界空间保持水平朝前。
	var arm_equip: Quaternion = Quaternion.from_euler(Vector3(0.10, -0.08, 1.72 - PI))
	_pistol_base_pos = Vector3(0.0, -0.034, -0.132) + PISTOL_OFFSET
	_pistol_base_quat = arm_equip.inverse() * Quaternion.from_euler(PISTOL_ROTATION * (PI / 180.0))
	_pistol_pivot.position = _pistol_base_pos
	_pistol_pivot.quaternion = _pistol_base_quat
	right_arm.add_child(_pistol_pivot)
	_pistol = PISTOL_SCENE.instantiate() as Node3D
	if _pistol == null:
		return
	_pistol.name = "SteamPistol"
	_pistol.scale = Vector3.ONE * PISTOL_SCALE
	_pistol.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	# 模型包围盒中心在原点，握把位于模型局部 +X；沿 -X 偏移让握把落回 pivot 原点。
	_pistol.position = Vector3(-0.35 * PISTOL_SCALE, 0.0, 0.0)
	_disable_shadows(_pistol)
	_pistol_pivot.add_child(_pistol)
	_pistol.visible = false


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)


func _configure_pistol_grips() -> void:
	_pistol_grip_pose = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/pistol_grip_pose.json")) as Dictionary
	var gun_basis: Basis = Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN)
	var steam: Dictionary = _pistol_grip_pose.weapons.steam_pistol
	_pistol_base_pos = _presentation_vector(steam.palm_grip)
	_pistol_base_quat = gun_basis.get_rotation_quaternion()
	_pistol_pivot.position = _pistol_base_pos
	_pistol_pivot.quaternion = _pistol_base_quat
	_pistol.scale = Vector3.ONE * float(steam.scale)
	_pistol.position = -_presentation_vector(steam.source_grip) * float(steam.scale)
	_m1911_pivot.position = _presentation_vector(_pistol_grip_pose.weapons.m1911.palm_grip)
	_m1911_pivot.basis = gun_basis


func _build_m1911() -> void:
	_m1911_pivot = Node3D.new()
	_m1911_pivot.name = "M1911"
	_m1911_pivot.set_script(M1911_SCRIPT)
	_m1911_pivot.position = GRIP_CENTER
	var arm_equip: Quaternion = Quaternion.from_euler(Vector3(0.10, -0.08, 1.72 - PI))
	_m1911_pivot.quaternion = arm_equip.inverse() * Quaternion(Vector3.UP, -PI * 0.5)
	right_arm.add_child(_m1911_pivot)
	_m1911_pivot.visible = false


## 导入武器：每件武器一个 pivot，装配参数（缩放/旋转/握把偏移）全部来自
## data/combat_mvp.json 的 viewmodel 块，不共用同一个偏移常量。
## 近战 pivot 与 weapon_root 同姿态，让挥砍弧线复用已认可的持剑动作；
## 枪械 pivot 沿用 M1911 的抵消手臂姿态，模型自身 +X 为枪口方向。
func _build_imported_weapons() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WEAPON_DATA_PATH)) as Dictionary
	if data.is_empty():
		return
	var weapons: Dictionary = data.get("weapons", {}) as Dictionary
	var arm_equip: Quaternion = Quaternion.from_euler(Vector3(0.10, -0.08, 1.72 - PI))
	for id: String in weapons:
		var entry: Variant = weapons[id]
		if not entry is Dictionary:
			continue
		var config: Dictionary = (entry as Dictionary).get("viewmodel", {}) as Dictionary
		if config.is_empty():
			continue
		var gun: bool = str(config.get("attach", "melee")) == "gun"
		var pivot: Node3D = Node3D.new()
		pivot.name = "Imported_" + id
		pivot.set_script(IMPORTED_SCRIPT)
		pivot.position = GRIP_CENTER
		if gun:
			pivot.quaternion = arm_equip.inverse() * Quaternion(Vector3.UP, PI * 0.5)
		else:
			pivot.rotation.z = PI * 0.5
		right_arm.add_child(pivot)
		pivot.call("setup", id, config)
		pivot.visible = false
		_imported[id] = pivot
		if gun:
			if not _ranged_ids.has(id):
				_ranged_ids.append(id)
		elif not _melee_ids.has(id):
			_melee_ids.append(id)


func is_melee(weapon_id: String) -> bool:
	return _melee_ids.has(weapon_id)


func is_ranged(weapon_id: String) -> bool:
	return _ranged_ids.has(weapon_id)


func _arm(node_name: String, side: float) -> Node3D:
	var rig: Node3D = Node3D.new()
	rig.name = node_name
	var glove: Node3D = Node3D.new()
	glove.set_script(GLOVE_SCRIPT)
	glove.left_hand = side < 0.0
	rig.add_child(glove)
	add_child(rig)
	if side > 0.0:
		right_glove = glove
	else:
		left_glove = glove
	return rig


func _build_tide_blade() -> void:
	if TIDE_BLADE_SCENE == null:
		return
	# 握把节点：旋转围绕抓握点，而不是模型原点（剑首底端）。
	var grip: Node3D = Node3D.new()
	grip.name = "TideGrip"
	weapon_root.add_child(grip)
	_tide_blade = TIDE_BLADE_SCENE.instantiate() as Node3D
	if _tide_blade == null:
		return
	_tide_blade.name = "TideBlade"
	_tide_blade.scale = Vector3.ONE * TIDE_SCALE
	# 入场动画要绕剑身中心翻转，所以在剑身中心插一个 pivot。
	_tide_pivot = Node3D.new()
	_tide_pivot.name = "TidePivot"
	var shape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/tide_blade_long.json")) as Dictionary
	var extension: float = float(shape.extension)
	var center_y: float = 0.5 + extension * 0.5
	_spawn_base_y = (center_y - TIDE_GRIP_Y) * TIDE_SCALE
	_tide_pivot.position = Vector3(0.0, _spawn_base_y, 0.0)
	grip.add_child(_tide_pivot)
	# 剑身中心（模型局部 Y=0.5）对齐 pivot 原点，握把中心仍落在抓握点。
	_tide_blade.position = Vector3(0.0, -center_y * TIDE_SCALE, 0.0)
	# Turn the blade slightly edge-on while preserving the handle center.
	_tide_blade.rotation_degrees = Vector3(0.0, TIDE_BLADE_YAW, 0.0)
	_tide_pivot.add_child(_tide_blade)
	# Trace flowing veins on the actual blade surface, never on a bounding box.
	_tide_glow_material = ShaderMaterial.new()
	_tide_glow_material.shader = preload("res://shaders/tide_blade_energy.gdshader")
	var source_mesh: MeshInstance3D = _find_blade_mesh(_tide_blade)
	_tide_glow = MeshInstance3D.new()
	_tide_glow.mesh = source_mesh.mesh
	_tide_glow.material_override = _tide_glow_material
	_tide_glow.transform = source_mesh.transform
	_tide_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	source_mesh.get_parent().add_child(_tide_glow)
	_tide_glow.visible = false
	_tide_blade.visible = false


func _find_blade_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_blade_mesh(child)
		if found != null:
			return found
	return null


## 切换手持武器模型。空字符串表示空手。
func set_weapon(weapon_id: String) -> void:
	_reset_slash_forearm()
	_pistol_recoil_left = 0.0
	var was_tide: bool = _weapon_id == "tide_blade"
	var was_pistol: bool = _weapon_id == "steam_pistol"
	_weapon_id = weapon_id
	right_glove.authored_grip = is_melee(weapon_id) or weapon_id == "fishing_rod"
	_fishing_rod.visible = weapon_id == "fishing_rod"
	_fishing_rod.reset_presentation()
	right_glove.grip_kind = "pistol" if is_ranged(weapon_id) else "relaxed"
	if is_instance_valid(_practice_model):
		_practice_model.visible = weapon_id == "practice_blade"
	if is_instance_valid(_tide_blade):
		_tide_blade.visible = weapon_id == "tide_blade"
	if is_instance_valid(_pistol):
		_pistol.visible = weapon_id == "steam_pistol"
	if is_instance_valid(_m1911_pivot):
		_m1911_pivot.visible = weapon_id == "m1911"
	for id: String in _imported:
		var pivot: Node3D = _imported[id] as Node3D
		if is_instance_valid(pivot):
			pivot.visible = id == weapon_id
	# (Claude Code) Re-point the swing ribbon at the new blade and drop stale samples.
	if is_instance_valid(trail):
		trail.set_weapon(_trail_root(weapon_id), weapon_id)
		trail.clear()
	# 每次从别的状态切到时钟剑都播一次入场动画。
	if weapon_id == "tide_blade" and not was_tide:
		_play_spawn_animation()
	elif weapon_id != "tide_blade":
		_cancel_spawn_animation()
	# 切到手炮时播掏枪旋转；切走时立刻归位，避免残留旋转。
	if weapon_id == "steam_pistol" and not was_pistol:
		_play_pistol_spawn()
	elif weapon_id != "steam_pistol":
		_cancel_pistol_spawn()


## 挥砍拖尾的采样根节点：导入近战武器用它自己的 pivot，内置剑仍用 weapon_root。
func _trail_root(weapon_id: String) -> Node3D:
	if _imported.has(weapon_id):
		return _imported[weapon_id] as Node3D
	return weapon_root


func _play_pistol_spawn() -> void:
	if not is_instance_valid(_pistol_pivot):
		return
	_pistol_spawn = PISTOL_SPAWN_DURATION


func _cancel_pistol_spawn() -> void:
	_pistol_spawn = 0.0
	if is_instance_valid(_pistol_pivot):
		_pistol_pivot.position = _pistol_base_pos
		_pistol_pivot.quaternion = _pistol_base_quat
	if is_instance_valid(_pistol):
		_pistol.scale = Vector3.ONE * float(_pistol_grip_pose.weapons.steam_pistol.scale)


## 掏枪：从下方升起，同时绕枪管轴自转两圈，最后落回基准位。
func _apply_pistol_spawn(progress: float) -> void:
	if not is_instance_valid(_pistol_pivot):
		return
	# Raise the hand and attached firearm together; never spin it out of the grip.
	if PISTOL_IDS.has(_weapon_id):
		right_arm.position += Vector3(0.0, -0.18, 0.08) * (1.0 - smoothstep(0.0, 1.0, progress))
		return
	var eased: float = 1.0 - pow(1.0 - progress, 2.4)
	var spin: float = eased * TAU * PISTOL_SPAWN_TURNS
	var rise: float = (1.0 - smoothstep(0.0, 0.55, progress)) * PISTOL_SPAWN_RISE
	_pistol_pivot.position = _pistol_base_pos + Vector3(0.0, rise, 0.0)
	_pistol_pivot.quaternion = _pistol_base_quat * Quaternion(Vector3(0.0, 0.0, 1.0), spin)
	# 从稍小尺寸长大，避免出现瞬间占满画面。
	if is_instance_valid(_pistol):
		_pistol.scale = Vector3.ONE * PISTOL_SCALE * lerpf(0.74, 1.0, eased)


func _cancel_spawn_animation() -> void:
	_spawn_time = 0.0
	if is_instance_valid(_tide_pivot):
		_tide_pivot.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _spawn_base_y, 0.0))


## 入场动画：抛到空中翻转数圈，再稳稳落回手中。
func _play_spawn_animation() -> void:
	if not is_instance_valid(_tide_pivot):
		return
	_spawn_time = TIDE_SPAWN_DURATION
	_tide_pivot.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _spawn_base_y, 0.0))


func _apply_spawn_pose(progress: float) -> void:
	if not is_instance_valid(_tide_pivot):
		return
	var cfg: Dictionary = _sword_motion.draw
	var release: float = float(cfg.release)
	var catch_time: float = float(cfg.catch)
	var neutral: Transform3D = right_arm.transform
	var release_pose: Transform3D = _draw_arm_pose(neutral, cfg.release_offset, cfg.release_degrees)
	var wait_pose: Transform3D = _draw_arm_pose(neutral, cfg.wait_offset, cfg.wait_degrees)
	var catch_pose: Transform3D = _draw_arm_pose(neutral, cfg.catch_offset, cfg.catch_degrees)
	var rest_pivot: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, _spawn_base_y, 0.0))
	var pivot_in_arm: Transform3D = weapon_root.transform * (_tide_pivot.get_parent() as Node3D).transform * rest_pivot
	_tide_pivot.transform = rest_pivot
	var grip: float = float(cfg.closed_grip)
	if progress < release:
		right_arm.transform = neutral.interpolate_with(release_pose, smoothstep(0.0, release, progress))
		grip = lerpf(grip, float(cfg.open_grip), smoothstep(release * 0.65, release, progress))
	elif progress < catch_time:
		var flight: float = (progress - release) / (catch_time - release)
		if flight < 0.40:
			right_arm.transform = release_pose.interpolate_with(wait_pose, smoothstep(0.0, 0.40, flight))
		else:
			right_arm.transform = wait_pose.interpolate_with(catch_pose, smoothstep(0.55, 1.0, flight))
		# Solve the airborne sword in view space independently of the moving hand.
		# At both endpoints the handle exactly matches the attached grip transform.
		var start: Transform3D = release_pose * pivot_in_arm
		var finish: Transform3D = catch_pose * pivot_in_arm
		var airborne: Transform3D = start.interpolate_with(finish, smoothstep(0.0, 1.0, flight))
		airborne.origin += Vector3(0.0, TIDE_SPAWN_HEIGHT, -float(cfg.flight_depth)) * sin(flight * PI)
		var spin: float = (1.0 - pow(1.0 - flight, 2.0)) * TAU * TIDE_SPAWN_TURNS
		airborne.basis = airborne.basis * Basis(Vector3.RIGHT, spin)
		_tide_pivot.global_transform = global_transform * airborne
		grip = float(cfg.open_grip)
	else:
		var recovery: float = smoothstep(catch_time, 1.0, progress)
		right_arm.transform = catch_pose.interpolate_with(neutral, recovery)
		right_arm.position += Vector3(0.0, -float(cfg.catch_dip), 0.012) * sin(clampf((progress - catch_time) / (1.0 - catch_time), 0.0, 1.0) * PI)
		grip = lerpf(float(cfg.open_grip), float(cfg.closed_grip), smoothstep(catch_time, float(cfg.close), progress))
	# Author the opening explicitly; smoothing back toward idle every frame kept
	# the previous hand half-closed even while the sword was in flight.
	right_glove.set_pose_immediate(grip)


func _draw_arm_pose(neutral: Transform3D, offset: Array, degrees: Array) -> Transform3D:
	var rotation: Basis = Basis.from_euler(_presentation_vector(degrees) * (PI / 180.0))
	return Transform3D(rotation * neutral.basis, neutral.origin + _presentation_vector(offset))


## 0..1 的充能强度，驱动剑身青绿裂纹的亮度；为 0 时完全隐藏，不留半透明残留。
func set_energy_glow(ratio: float) -> void:
	if _tide_glow_material == null:
		return
	var strength: float = clampf(ratio, 0.0, 1.0)
	_tide_glow_material.set_shader_parameter("charge", strength)
	if _tide_glow != null:
		_tide_glow.visible = strength > 0.02


func reset_motion() -> void:
	_fishing_rod.reset_presentation()
	_state_offset = Vector3.ZERO
	_state_angles = Vector3.ZERO
	_landing_time = 0.0
	_landing_strength = 0.0
	_reset_slash_forearm()
	_reset_rope_forearm()
	_cancel_spawn_animation()
	_cancel_pistol_spawn()
	_run_blend = 0.0
	_slide_blend = 0.0
	_climb_blend = 0.0
	_bob_blend = 0.0
	_wallrun_blend = 0.0
	_wallrun_side = 0.0
	_near_wall = 0.0
	_equip_blend = 0.0
	_empty_move_blend = 0.0
	_grapple_blend = 0.0
	_grapple_age = 0.0
	_grapple_was_active = false
	_grapple_follow = Vector3.ZERO
	_grapple_start_distance = 0.0
	_grapple_reel = 0.0
	_grapple_swing = 0.0
	_pistol_recoil_left = 0.0
	# 重试时清掉新增动作状态，否则格挡、施法、喝药会残留在下一轮。
	_block_kind = ""
	_block_weight = 0.0
	_spell_playing = false
	_spell_time = 0.0
	_drink_playing = false
	_drink_time = 0.0
	if is_instance_valid(_bottle):
		_bottle.visible = false
	if is_instance_valid(right_glove):
		right_glove.clear_pose_override()
	if is_instance_valid(left_glove):
		left_glove.clear_pose_override()
	if is_instance_valid(right_glove):
		right_glove.set_pose_immediate(0.28)
	if is_instance_valid(left_glove):
		left_glove.set_pose_immediate(0.30)


func update_pose(delta: float, speed: float, sprinting: bool, attack_progress: float, swing: int, equipped: bool, wall_distance: float, locomotion: Dictionary = {}) -> void:
	_sync_fishing_controller()
	_reset_slash_forearm()
	_reset_rope_forearm()
	var blend: float = 1.0 - exp(-float(locomotion.get("sharpness", 12.0)) * delta)
	var grounded: bool = bool(locomotion.get("grounded", true))
	var grappling: bool = bool(locomotion.get("grappling", false))
	var preparing: bool = bool(locomotion.get("grapple_preparing", false))
	_grapple_age = _grapple_age + delta if grappling and _grapple_was_active else 0.0
	_grapple_was_active = grappling
	var grapple_sharpness: float = float(_presentation.grapple.raise_sharpness) if grappling or preparing else 16.0
	var grapple_target: float = 1.0 if grappling else (0.70 if preparing else 0.0)
	_grapple_blend = lerpf(_grapple_blend, grapple_target, 1.0 - exp(-delta * grapple_sharpness))
	# 剑类武器才播迁移动作；手炮走自己的开火路径。
	var sword_equipped: bool = is_melee(_weapon_id)
	var wave_progress: float = float(locomotion.get("wave_progress", -1.0))
	var wave_active: bool = _weapon_id == "tide_blade" and wave_progress >= 0.0
	var dedicated_pistol: bool = PISTOL_IDS.has(_weapon_id)
	var rod_equipped: bool = _weapon_id == "fishing_rod"
	_equip_blend = lerpf(_equip_blend, 1.0 if equipped or rod_equipped else 0.0, 1.0 - exp(-delta * 14.0))
	_run_blend = lerpf(_run_blend, 1.0 if sprinting and speed > 3.0 and grounded else 0.0, blend)
	_slide_blend = lerpf(_slide_blend, 1.0 if locomotion.get("sliding", false) else 0.0, blend)
	_climb_blend = lerpf(_climb_blend, 1.0 if locomotion.get("mantling", false) else 0.0, blend)
	_bob_blend = lerpf(_bob_blend, 1.0 if grounded and speed > 0.5 and not grappling and not locomotion.get("sliding", false) and not locomotion.get("mantling", false) else 0.0, blend)
	var wallrunning: bool = bool(locomotion.get("wallrunning", false))
	_wallrun_blend = lerpf(_wallrun_blend, 1.0 if wallrunning else 0.0, blend)
	if wallrunning:
		_wallrun_side = float(locomotion.get("wallrun_side", 0.0))
	_near_wall = lerpf(_near_wall, clampf(1.0 - wall_distance, 0.0, 1.0), minf(delta * 12.0, 1.0))
	var stride_phase: float = float(locomotion.get("stride_phase", 0.0))
	var amplitude: float = _bob_blend * float(locomotion.get("scale", 1.0))
	var bob: float = sin(stride_phase * 2.0) * minf(speed * 0.002, 0.016) * amplitude
	var sway: float = cos(stride_phase) * minf(speed * 0.0015, 0.012) * amplitude
	# 蹬墙跑时不再把手往回缩，否则扶墙动作会被贴墙收臂抵消。
	var draw_back: float = _near_wall * 0.25 * (1.0 - _wallrun_blend)
	# Elbows fall below the frame; roll the wrist so a cross-palm handle stands upright.
	right_arm.position = Vector3(0.28, -0.56, -0.30).lerp(Vector3(0.367, -0.290, -0.429), _equip_blend)
	right_arm.position += Vector3(sway, bob - _near_wall * 0.08, draw_back)
	left_arm.position = Vector3(-0.28 - sway, -0.56 - bob, -0.30 + draw_back)
	right_arm.quaternion = Quaternion.from_euler(Vector3(0.85, -0.15, -0.15)).slerp(Quaternion.from_euler(Vector3(0.10, -0.08, 1.72 - PI)), _equip_blend)
	if dedicated_pistol:
		var axes: Array = _pistol_grip_pose.hand_world_basis
		var pistol_rotation: Quaternion = Basis(_presentation_vector(axes[0]), _presentation_vector(axes[1]), _presentation_vector(axes[2])).get_rotation_quaternion()
		right_arm.quaternion = Quaternion.from_euler(Vector3(0.85, -0.15, -0.15)).slerp(pistol_rotation, _equip_blend)
		right_arm.position = Vector3(0.28, -0.56, -0.30).lerp(_presentation_vector(_pistol_grip_pose.hand_position), _equip_blend) + Vector3(sway, bob - _near_wall * 0.08, draw_back)
	left_arm.rotation = Vector3(0.85, 0.15, 0.15)
	_apply_empty_locomotion(speed, stride_phase, blend, locomotion)
	# Move close-up geometry slightly away from the eye without changing world FOV.
	var view: Dictionary = _presentation.view
	position.z = lerpf(float(view.depth_offset), 0.0, _equip_blend if sword_equipped or dedicated_pistol or rod_equipped else 0.0)
	scale = Vector3.ONE * lerpf(float(view.scale), 1.0, _equip_blend if sword_equipped or dedicated_pistol or rod_equipped else 0.0)
	# 持剑行走：源摆动叠加到已有 bob 之上；攻击、滑铲、攀爬时不参与。
	if sword_equipped and not wave_active and attack_progress < 0.0 and _bob_blend > 0.05 and not bool(locomotion.get("mantling", false)) and not bool(locomotion.get("sliding", false)):
		_apply_walk_sway(stride_phase, _bob_blend * clampf(speed / 4.0, 0.0, 1.0))
	# 左手施法：只覆盖左臂，右手与剑不动。
	if _spell_playing:
		var spell_track: Dictionary = _action_tracks.get("Left_Spell", {}) as Dictionary
		var spell_duration: float = float(spell_track.get("duration", 1.0))
		_spell_time += delta
		_apply_left_spell(clampf(_spell_time / spell_duration, 0.0, 1.0))
		if _spell_time >= spell_duration:
			stop_left_spell()
	# 喝药：右手与瓶子一起动，瓶子首尾淡入淡出。
	if _drink_playing:
		var drink_track: Dictionary = _action_tracks.get("Drink", {}) as Dictionary
		var drink_duration: float = float(drink_track.get("duration", 1.0))
		_drink_time += delta
		var drink_progress: float = clampf(_drink_time / drink_duration, 0.0, 1.0)
		_apply_drink(drink_progress)
		if is_instance_valid(_bottle):
			var fade: float = 1.0
			if drink_progress < DRINK_FADE:
				fade = drink_progress / DRINK_FADE
			elif drink_progress > 1.0 - DRINK_FADE:
				fade = (1.0 - drink_progress) / DRINK_FADE
			_bottle.call("set_alpha", fade)
		if _drink_time >= drink_duration:
			stop_drink()
	right_arm.rotation.x += _run_blend * 0.12 * _equip_blend
	right_arm.position += Vector3(0.02, -0.035, 0.025) * _run_blend * _equip_blend
	right_arm.position.y -= _slide_blend * 0.06
	left_arm.position.y -= _slide_blend * 0.04
	left_arm.position = left_arm.position.lerp(Vector3(-0.22, -0.20, -0.60), _climb_blend)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.50, _climb_blend)
	if attack_progress >= 0.0 and sword_equipped:
		# Keep the approved handle contact; source fingers open around a different hilt.
		right_glove.clear_pose_override()
	elif block_active():
		var block_pose: Dictionary = _block_frame(_block_kind)
		if not block_pose.is_empty():
			right_glove.apply_pose_override(block_pose.get("fingers", {}) as Dictionary, _block_weight)
	elif _drink_playing:
		# 喝药的手指姿势必须在这里挂上：set_grip 紧接着执行，
		# 否则放到 _apply_drink 里会在下一帧被 else 分支清空。
		var drink_pose: Dictionary = _action_frame("Drink", _drink_progress())
		if not drink_pose.is_empty():
			right_glove.apply_pose_override(drink_pose.get("fingers", {}) as Dictionary, 1.0)
	elif dedicated_pistol:
		right_glove.apply_pose_override(_pistol_grip_pose.right, _equip_blend)
	else:
		right_glove.clear_pose_override()
	right_glove.set_grip((0.88 if equipped or rod_equipped else float(_presentation.empty.grip) + _empty_move_blend * 0.16) * (1.0 - _climb_blend * 0.7), delta)
	if not _spell_playing:
		left_glove.clear_pose_override()
	left_glove.set_grip(lerpf(float(_presentation.empty.grip) + _empty_move_blend * 0.16, 0.03, _climb_blend), delta)
	attack_pose = attack_progress
	if wave_active:
		_apply_blade_arc(wave_progress, _sword_motion.wave_swing as Array)
	elif attack_progress >= 0.0 and sword_equipped:
		_apply_slash_arm(attack_progress, swing % 2)
	elif block_active():
		_apply_block_arm(_block_kind, _block_weight)
	elif is_ranged(_weapon_id):
		_apply_pistol_recoil(delta)
	elif attack_progress >= 0.0 and not rod_equipped:
		var side: float = 1.0 if swing % 2 == 0 else -1.0
		var phase: float
		if attack_progress < 0.23:
			phase = lerpf(0.0, 1.0, attack_progress / 0.23)
			right_arm.position += Vector3(side * 0.10, 0.10, 0.10) * phase
			right_arm.rotation.z -= side * phase * 0.45
			right_arm.rotation.y -= side * phase * 0.18
		elif attack_progress < 0.60:
			phase = (attack_progress - 0.23) / 0.37
			right_arm.position += Vector3(lerpf(side * 0.10, -side * 0.30, phase), lerpf(0.10, -0.03, phase), lerpf(0.10, -0.02, phase) - sin(phase * PI) * 0.12)
			right_arm.rotation.z += lerpf(-side * 0.45, side * 0.65, phase)
			right_arm.rotation.y += lerpf(-side * 0.18, side * 0.35, phase)
		else:
			phase = (attack_progress - 0.60) / 0.40
			right_arm.position += Vector3(-side * 0.30, -0.03, -0.02) * (1.0 - phase)
			right_arm.rotation.z += side * 0.65 * (1.0 - phase)
			right_arm.rotation.y += side * 0.35 * (1.0 - phase)
	# (Claude Code) Sample the blade during the active arc only; the ribbon fades on its own.
	if is_instance_valid(trail):
		var swinging: bool = sword_equipped and ((attack_progress >= 0.16 and attack_progress <= 0.64) or (wave_active and wave_progress >= 0.25 and wave_progress <= 0.62))
		if swinging:
			trail.push_sample()
	# 蹬墙跑：离墙最近的手抬起撑住墙面，掌心贴墙。
	if _wallrun_blend > 0.01:
		var toward: float = -1.0 if _wallrun_side < 0.0 else 1.0
		var support: Node3D = left_arm if toward < 0.0 else right_arm
		var support_glove: Node3D = left_glove if toward < 0.0 else right_glove
		support.position += Vector3(toward * 0.24, 0.26, -0.02) * _wallrun_blend
		support.rotation.z += -toward * 1.15 * _wallrun_blend
		support.rotation.y += toward * 0.60 * _wallrun_blend
		support.rotation.x -= 0.15 * _wallrun_blend
		support_glove.set_grip(0.02, delta)
	# 入场动画：手部抛接动作叠加在常规姿态之上。
	if not equipped or wave_active or attack_progress >= 0.0 or _climb_blend > 0.1 or _wallrun_blend > 0.1 or block_active() or _drink_playing or grappling or preparing:
		_cancel_spawn_animation()
	if _spawn_time > 0.0:
		_spawn_time = maxf(0.0, _spawn_time - delta)
		_apply_spawn_pose(1.0 - _spawn_time / TIDE_SPAWN_DURATION)
	_apply_weapon_locomotion(locomotion, delta, sword_equipped, attack_progress)
	var show_rod: bool = rod_equipped and not grappling and not preparing and not _drink_playing and not block_active() and _climb_blend < 0.1 and _wallrun_blend < 0.1
	if show_rod:
		_fishing_rod.apply_hand_pose(right_arm, delta, speed if grounded else 0.0, stride_phase)
		_align_fishing_forearm()
	_apply_grapple_hold(locomotion, delta)
	_fishing_rod.visible = show_rod
	left_arm.visible = true
	right_arm.visible = true
	# 右手扶墙时收起武器，避免剑身插进墙里。
	var show_weapon: bool = equipped and not _drink_playing and not (_wallrun_side > 0.0 and _wallrun_blend > 0.4)
	weapon_root.visible = show_weapon
	if is_instance_valid(_pistol_pivot):
		_pistol_pivot.visible = show_weapon
	if is_instance_valid(_m1911_pivot):
		_m1911_pivot.visible = show_weapon and _weapon_id == "m1911"
	for id: String in _imported:
		var imported: Node3D = _imported[id] as Node3D
		if is_instance_valid(imported):
			imported.visible = show_weapon and id == _weapon_id
	# 掏枪动画：从下方升起 + 自转，进度到 1 时自动归位。
	if _pistol_spawn > 0.0:
		_pistol_spawn = maxf(0.0, _pistol_spawn - delta)
		_apply_pistol_spawn(1.0 - _pistol_spawn / PISTOL_SPAWN_DURATION)


func _presentation_vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func grapple_hold_weight() -> float:
	return _grapple_blend


func grapple_grip_point() -> Vector3:
	return _rope_hand_transform() * Vector3(0.0, -0.037, -0.110)


func grapple_rope_tangent() -> Vector3:
	return _rope_hand_transform().basis.x.normalized()


func _rope_hand_transform() -> Transform3D:
	# Use the posed wrist, not the arm root, so bending never leaves the rope behind.
	var skeleton: Skeleton3D = left_glove.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hand"))


func _apply_grapple_hold(locomotion: Dictionary, delta: float) -> void:
	if _grapple_blend < 0.001 or _climb_blend > 0.4 or _wallrun_blend > 0.4:
		_grapple_follow = Vector3.ZERO
		return
	var cfg: Dictionary = _presentation.grapple
	var anchor: Vector3 = locomotion.get("grapple_anchor", to_global(Vector3(0, 0, -8)))
	var distance: float = global_position.distance_to(anchor)
	if _grapple_was_active and _grapple_age == 0.0:
		_grapple_start_distance = distance
		_grapple_reel = 0.0
		_grapple_swing = 0.0
	# Progress follows the actual approach, not a timer: swinging at a fixed
	# radius must not play the arrival pose just because time has passed.
	var pull_target: float = clampf((_grapple_start_distance - distance) / maxf(_grapple_start_distance - float(cfg.pull_finish_distance), 1.0), 0.0, 1.0) if _grapple_was_active else 0.0
	var local_velocity: Vector3 = locomotion.get("local_velocity", Vector3.ZERO)
	var tether_direction: Vector3 = to_local(anchor).normalized()
	var tangent_speed: float = (local_velocity - tether_direction * local_velocity.dot(tether_direction)).length()
	var swing_target: float = clampf(tangent_speed / float(cfg.swing_reference_speed), 0.0, 1.0) if _grapple_was_active else 0.0
	var pull_blend: float = 1.0 - exp(-delta * float(cfg.pull_sharpness))
	_grapple_reel = lerpf(_grapple_reel, smoothstep(0.0, 1.0, pull_target), pull_blend)
	_grapple_swing = lerpf(_grapple_swing, swing_target, pull_blend)
	var reach: Vector3 = _presentation_vector(cfg.reach_offset).lerp(_presentation_vector(cfg.reel_offset), _grapple_reel)
	reach += _presentation_vector(cfg.swing_offset) * _grapple_swing
	left_arm.position = left_arm.position.lerp(_presentation_vector(cfg.hand_position) + reach, _grapple_blend)
	if _grapple_was_active:
		var kick: float = sin(clampf(_grapple_age / float(cfg.launch_kick_duration), 0, 1) * PI)
		var impact_time: float = float(locomotion.get("grapple_shot_duration", 0.05))
		var settle: float = sin(clampf((_grapple_age - impact_time) / float(cfg.impact_settle_duration), 0, 1) * PI)
		left_arm.position += Vector3(-0.15, -0.10, 1.0) * float(cfg.launch_kick_distance) * kick * _grapple_blend
		left_arm.position.z += float(cfg.impact_settle_distance) * settle * _grapple_blend
	# A restrained, smoothed response to tether bearing and lateral momentum.
	# Keep the approved grasp; never fully aim the whole forearm at the anchor.
	var bearing: Vector3 = to_local(anchor) - left_arm.position
	var gain: float = float(cfg.follow_gain)
	var desired: Vector3 = Vector3(
		clampf(atan2(bearing.y, Vector2(bearing.x, bearing.z).length()) * gain, -deg_to_rad(float(cfg.follow_pitch_degrees)), deg_to_rad(float(cfg.follow_pitch_degrees))),
		clampf(-atan2(bearing.x, -bearing.z) * gain, -deg_to_rad(float(cfg.follow_yaw_degrees)), deg_to_rad(float(cfg.follow_yaw_degrees))),
		clampf(-local_velocity.x * 0.012, -deg_to_rad(float(cfg.follow_roll_degrees)), deg_to_rad(float(cfg.follow_roll_degrees))))
	if not _grapple_was_active:
		desired = Vector3.ZERO
	_grapple_follow = _grapple_follow.lerp(desired, 1.0 - exp(-delta * float(cfg.follow_sharpness)))
	# Restore the accepted grip first, including its cuff placement. Apply a small
	# shared motion only AFTER that solve so sleeve and hand move as one unit.
	var pose: Quaternion = Quaternion(Vector3.BACK, -0.55) * Quaternion(Vector3.RIGHT, -0.20) * Quaternion.from_euler(Vector3(0.10, 0.08, PI - 1.72))
	left_arm.quaternion = left_arm.quaternion.slerp(pose, _grapple_blend)
	left_glove.apply_rope_grip(_grapple_blend)
	var bend_degrees: float = float(cfg.forearm_max_bend_degrees) - float(cfg.reach_bend_reduction_degrees) * (1.0 - _grapple_reel) + float(cfg.reel_bend_add_degrees) * _grapple_reel + float(cfg.swing_bend_add_degrees) * _grapple_swing
	_align_rope_forearm(_grapple_blend, bend_degrees)
	var follow_gain: float = lerpf(0.30, float(cfg.swing_follow_gain), _grapple_swing)
	var pull_angles: Vector3 = _presentation_vector(cfg.reel_degrees) * (PI / 180.0) * _grapple_reel
	var shared_follow: Quaternion = Quaternion.from_euler((_grapple_follow * follow_gain + pull_angles) * _grapple_blend)
	left_arm.quaternion = shared_follow * left_arm.quaternion
	left_arm.position += Vector3(-_grapple_follow.y * 0.05, _grapple_follow.x * 0.04, 0) * _grapple_blend
	# Stop the actual palm contact before it crowds the camera, including wrist tilt.
	var grip_depth: float = to_local(grapple_grip_point()).z
	var excess: float = maxf(grip_depth + float(cfg.closest_grip_depth), 0.0)
	left_arm.position.z -= excess * _grapple_blend



func play_pistol_recoil() -> void:
	if is_ranged(_weapon_id):
		_pistol_recoil_left = float(_presentation.pistol.kick_duration)


func _apply_pistol_recoil(delta: float) -> void:
	if _pistol_recoil_left <= 0.0:
		return
	var cfg: Dictionary = _presentation.pistol
	_pistol_recoil_left = maxf(0, _pistol_recoil_left - delta)
	var elapsed: float = float(cfg.kick_duration) - _pistol_recoil_left
	var amount: float
	if elapsed < float(cfg.rise_duration):
		amount = smoothstep(0, float(cfg.rise_duration), elapsed)
	else:
		amount = 1.0 - smoothstep(float(cfg.rise_duration), float(cfg.kick_duration), elapsed)
	right_arm.position += Vector3(0, float(cfg.up_distance), float(cfg.back_distance)) * amount
	right_arm.quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(float(cfg.pitch_degrees)) * amount) * right_arm.quaternion


func _align_rope_forearm(weight: float, bend_degrees: float) -> void:
	# Accepted fixed grasp/cuff baseline. Do not rebuild a hand frame from the
	# anchor or scale the cropped sleeve: both broke the approved grip silhouette.
	var skeleton: Skeleton3D = left_glove.skeleton
	var forearm: int = skeleton.find_bone("Forearm")
	var hand: int = skeleton.find_bone("Hand")
	var shoulder: Vector3 = Vector3(-0.50, -1.05, 0.03)
	var local_direction: Vector3 = left_arm.quaternion.inverse() * (shoulder - left_arm.position).normalized()
	var hand_position: Vector3 = skeleton.get_bone_rest(hand).origin
	# Keep the wrist near the sleeve's authored straight axis. The old shoulder
	# target could bend the cuff almost ninety degrees while counter-rotating the hand.
	var rest_direction: Vector3 = -hand_position.normalized()
	var target_bend: Quaternion = Quaternion(rest_direction, local_direction)
	var max_angle: float = deg_to_rad(bend_degrees)
	var limited_weight: float = minf(1.0, max_angle / maxf(target_bend.get_angle(), 0.001))
	var bend: Quaternion = Quaternion.IDENTITY.slerp(target_bend, limited_weight * weight)
	skeleton.set_bone_pose_position(forearm, -(bend * hand_position))
	skeleton.set_bone_pose_rotation(forearm, bend)
	var wrist_target: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(float(_presentation.grapple.reel_wrist_degrees)) * weight)
	var wrist_pose: Quaternion = bend.inverse().slerp(wrist_target, _grapple_reel * weight)
	skeleton.set_bone_pose_rotation(hand, wrist_pose)
	_rope_wrist_bent = true


func notify_landing(speed: float) -> void:
	_landing_time = 0.0
	_landing_strength = clampf(speed / 18.0, 0.2, 1.0)


func _apply_weapon_locomotion(locomotion: Dictionary, delta: float, sword: bool, attack_progress: float) -> void:
	var cfg: Dictionary = _presentation.weapon_motion
	var offset: Vector3 = Vector3.ZERO
	var angles: Vector3 = Vector3.ZERO
	var free: bool = attack_progress < 0.0 and float(locomotion.get("wave_progress", -1.0)) < 0.0 and not block_active() and not _drink_playing and _spawn_time <= 0.0 and _climb_blend < 0.1 and _wallrun_blend < 0.1
	if sword and free:
		if bool(locomotion.get("grappling", false)) or bool(locomotion.get("grapple_preparing", false)):
			offset = _presentation_vector(cfg.grapple_offset)
			angles = _presentation_vector(cfg.grapple_degrees) * (PI / 180.0)
		elif bool(locomotion.get("sliding", false)):
			offset = _presentation_vector(cfg.slide_offset)
			angles = _presentation_vector(cfg.slide_degrees) * (PI / 180.0)
		elif bool(locomotion.get("crouching", false)):
			offset = _presentation_vector(cfg.crouch_offset)
			angles = Vector3(0, 0, deg_to_rad(float(cfg.crouch_tilt_degrees)))
		elif not bool(locomotion.get("grounded", true)):
			offset = Vector3(0.01, -0.025, 0.025)
	var blend: float = 1.0 - exp(-delta * float(cfg.sharpness))
	_state_offset = _state_offset.lerp(offset, blend)
	_state_angles = _state_angles.lerp(angles, blend)
	if free and sword:
		right_arm.position += _state_offset
		right_arm.quaternion = Quaternion.from_euler(_state_angles) * right_arm.quaternion
	_landing_time += delta
	var impact: float = sin(clampf(_landing_time / 0.22, 0.0, 1.0) * PI) * _landing_strength
	if free:
		right_arm.position.y -= impact * 0.045
		if _grapple_blend < 0.1:
			left_arm.position.y -= impact * 0.035


func _reset_rope_forearm() -> void:
	if not _rope_wrist_bent:
		return
	var skeleton: Skeleton3D = left_glove.skeleton
	for name: String in ["Forearm", "Hand"]:
		var bone: int = skeleton.find_bone(name)
		skeleton.set_bone_pose(bone, skeleton.get_bone_rest(bone))
	_rope_wrist_bent = false


func _apply_empty_locomotion(speed: float, phase: float, blend: float, locomotion: Dictionary) -> void:
	var cfg: Dictionary = _presentation.empty
	var allowed: bool = bool(locomotion.get("grounded", true)) and not bool(locomotion.get("sliding", false)) and not bool(locomotion.get("mantling", false)) and not bool(locomotion.get("wallrunning", false)) and not bool(locomotion.get("grappling", false))
	var amount: float = clampf(speed / float(cfg.reference_speed), 0.0, 1.2) if allowed else 0.0
	_empty_move_blend = lerpf(_empty_move_blend, amount, blend)
	for side: float in [-1.0, 1.0]:
		var arm: Node3D = left_arm if side < 0.0 else right_arm
		var weight: float = 1.0 if side < 0.0 else 1.0 - _equip_blend
		var moving: float = smoothstep(0.02, 0.5, _empty_move_blend)
		var point: Vector3 = _presentation_vector(cfg.idle_position).lerp(_presentation_vector(cfg.moving_position), moving)
		var angles: Vector3 = _presentation_vector(cfg.idle_rotation).lerp(_presentation_vector(cfg.moving_rotation), moving)
		point.x *= side
		angles.y *= side
		angles.z *= side
		var swing: float = sin(phase) * side * _empty_move_blend
		point += Vector3(-side * absf(swing) * 0.015, swing * float(cfg.vertical_swing), -swing * float(cfg.forward_swing))
		angles.x += swing * float(cfg.pitch_swing)
		arm.position = arm.position.lerp(point, weight)
		arm.quaternion = arm.quaternion.slerp(Quaternion.from_euler(angles), weight)


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


func _box(parent: Node3D, point: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	return _mesh(parent, box, point, material)


func _mesh(parent: Node3D, mesh: Mesh, point: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
