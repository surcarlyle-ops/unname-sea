extends SceneTree
## 跑动镜头起伏专项（CodeBuddyPro，2026-10-28）。
##
## 跑法：
##   "D:\claude project\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\claude project\projects\unname_sea" ^
##     --script res://tests/camera_bob_check.gd
##
## 量的是 camera 的局部位移/旋转（就是玩家看到的那层晃动），数值来自
## data/combat_mvp.json 的 player.camera_bob：
##   竖直/前后/俯仰每步一次，横向/偏航/滚转每两步一次，幅度随速度缩放。
## 参考 Apex 的头动：位移之外还有俯仰与偏航，所以这里把六个分量都测一遍。

const SCENE_PATH: String = "res://scenes/combat_mvp.tscn"

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_packed(load(SCENE_PATH) as PackedScene)
	for _index: int in range(240):
		await process_frame
		if current_scene != null and current_scene.get("player") != null:
			break
	await _frames(10)
	var arena: Node3D = current_scene as Node3D
	var player: CharacterBody3D = arena.get("player")
	arena.call("start_round", 2)  # 移动试炼：没有敌人，专测镜头
	await _frames(4)
	player.set_controls_active(true)
	player.set_physics_process(true)

	var sprint: Dictionary = await _sample_run(player, false)
	var walk: Dictionary = await _sample_run(player, true)
	var rest: Dictionary = await _sample_rest(player)

	print("SPRINT vertical=%.4fm horizontal=%.4fm forward=%.4fm pitch=%.3fdeg yaw=%.3fdeg roll=%.3fdeg" % [
		sprint.vertical, sprint.horizontal, sprint.forward, sprint.pitch, sprint.yaw, sprint.roll])
	print("WALK   vertical=%.4fm horizontal=%.4fm forward=%.4fm pitch=%.3fdeg yaw=%.3fdeg roll=%.3fdeg" % [
		walk.vertical, walk.horizontal, walk.forward, walk.pitch, walk.yaw, walk.roll])
	print("REST   position=%.5fm rotation=%.5fdeg" % [rest.position, rest.rotation])

	_check(sprint.vertical > 0.019 and sprint.vertical < 0.027, "冲刺竖直起伏 %.1f cm（目标 1.9–2.7 cm）" % (sprint.vertical * 100.0))
	_check(sprint.horizontal > 0.010 and sprint.horizontal < 0.017, "冲刺横向摆动 %.1f cm（目标 1.0–1.7 cm）" % (sprint.horizontal * 100.0))
	_check(sprint.pitch > 0.28 and sprint.pitch < 0.42, "冲刺俯仰点头 %.2f°（目标 0.28–0.42°）" % sprint.pitch)
	_check(sprint.yaw > 0.12 and sprint.yaw < 0.22, "冲刺偏航摆动 %.2f°（目标 0.12–0.22°）" % sprint.yaw)
	_check(sprint.roll > 0.30 and sprint.roll < 0.46, "冲刺滚转 %.2f°（目标 0.30–0.46°）" % sprint.roll)
	_check(walk.vertical < sprint.vertical * 0.7, "走路幅度明显小于冲刺：%.1f cm < %.1f cm" % [walk.vertical * 100.0, sprint.vertical * 100.0])
	_check(rest.position < 0.0005 and rest.rotation < 0.05, "停下后完全回到普通姿态（%.5f m / %.4f°）" % [rest.position, rest.rotation])

	print("CAMERA_BOB_RESULT pass=%d fail=%d" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)


## 按住前进跑 3 秒，记录每个物理帧的极值，返回峰峰值（米/度）。
func _sample_run(player: CharacterBody3D, walking: bool) -> Dictionary:
	player.global_position = Vector3(0.0, 0.1, 12.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.reset_to_spawn()
	await _frames(6)
	if walking:
		Input.action_press("fps_walk")
	Input.action_press("move_up")
	await _frames(20)
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	var low_rot: Vector3 = Vector3(INF, INF, INF)
	var high_rot: Vector3 = Vector3(-INF, -INF, -INF)
	for _index: int in range(180):
		await physics_frame
		var offset: Vector3 = player.camera.position
		var rotation: Vector3 = player.camera.rotation
		low = Vector3(minf(low.x, offset.x), minf(low.y, offset.y), minf(low.z, offset.z))
		high = Vector3(maxf(high.x, offset.x), maxf(high.y, offset.y), maxf(high.z, offset.z))
		low_rot = Vector3(minf(low_rot.x, rotation.x), minf(low_rot.y, rotation.y), minf(low_rot.z, rotation.z))
		high_rot = Vector3(maxf(high_rot.x, rotation.x), maxf(high_rot.y, rotation.y), maxf(high_rot.z, rotation.z))
	Input.action_release("move_up")
	Input.action_release("fps_walk")
	return {
		"vertical": high.y - low.y,
		"horizontal": high.x - low.x,
		"forward": high.z - low.z,
		"pitch": rad_to_deg(high_rot.x - low_rot.x),
		"yaw": rad_to_deg(high_rot.y - low_rot.y),
		"roll": rad_to_deg(high_rot.z - low_rot.z),
	}


## 停下 2.5 秒后必须精确归零，否则"普通姿态"永远差一点点。
func _sample_rest(player: CharacterBody3D) -> Dictionary:
	await _frames(150)
	return {
		"position": player.camera.position.length(),
		"rotation": rad_to_deg(player.camera.rotation.length()),
	}


func _frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _check(ok: bool, message: String) -> void:
	if ok:
		_passes += 1
		print("PASS  " + message)
	else:
		_fails += 1
		print("FAIL  " + message)
