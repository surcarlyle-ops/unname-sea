extends SceneTree
## 岸边测试区实机截图（CodeBuddyPro，2026-10-28）。
##
## 跑法（需要窗口，不要加 --headless）：
##   "D:\claude project\Godot_v4.7.2-stable_win64.exe" --path "D:\claude project\projects\unname_sea" ^
##     --script res://tests/capture_shore_test_area.gd
##
## 输出到 .mvp_qa/shore_test/：出生点视角、钓台末端、8 米鱼漂、12 米抛竿、
## 战斗空地全景、出生点标记。用于人工看水面可读性与岸边观感。

const PREVIEW_SCENE: String = "res://scenes/tests/shore_test_area_preview.tscn"
const OUTPUT_DIR: String = "res://.mvp_qa/shore_test"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var preview: Node3D = (load(PREVIEW_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(preview)
	current_scene = preview
	await process_frame
	await process_frame
	var player: CharacterBody3D = preview.player
	player.set_physics_process(false)
	player.set_controls_active(false)
	# 01 出生点视角：面向木台与水面。
	_place(player, Vector3(0.0, 0.08, 6.5), 0.0, -6.0)
	await _shot("01_spawn_view.png")
	# 02 钓台末端：看 2–12 米的抛竿区与水面钓点环。
	_place(player, Vector3(0.0, 0.56, -12.5), 0.0, -16.0)
	await _shot("02_dock_end.png")
	# 03 8 米鱼漂：验证正常第一人称视距下能不能看清。
	var tip: Vector3 = preview.fishing_fx.rod_tip()
	var eight: Vector3 = Vector3(0.0, 0.06, -20.5)
	preview.fishing.begin_cast(tip, eight)
	preview.fishing.state = 2
	await _shot("03_bobber_8m.png")
	# 04 11.8 米（12 米射线）鱼漂：抛竿上限处仍要看得见。
	preview.fishing.state = 0
	var far: Vector3 = Vector3(0.0, 0.06, -24.3)
	preview.fishing.begin_cast(tip, far)
	preview.fishing.state = 2
	await _shot("04_bobber_12m.png")
	preview.fishing.state = 0
	# 05 战斗空地全景：从后侧岩壁前看整片空地、石柱与钓台。
	_place(player, Vector3(0.0, 0.08, 10.6), 0.0, -9.0)
	await _shot("05_combat_ground.png")
	# 06 出生点标记：F1 打开后所有候选点与玩家出生点。
	preview.area.set_spawn_markers_visible(true)
	await _shot("06_spawn_markers.png")
	# 06b 俯视总览：8 个候选点与玩家出生点、水域、木台的关系。
	_place(player, Vector3(0.0, 18.0, 1.0), 0.0, -78.0)
	await _shot("06b_spawn_overview.png")
	preview.area.set_spawn_markers_visible(false)
	# 07 岸线侧看：水面与湿沙带、木台支柱的关系。
	_place(player, Vector3(-13.0, 0.08, -3.0), -40.0, -10.0)
	await _shot("07_waterline.png")
	print("SHORE_TEST_AREA_CAPTURE done → %s" % OUTPUT_DIR)
	preview.queue_free()
	await process_frame
	quit(0)


func _place(player: CharacterBody3D, position_value: Vector3, yaw_degrees: float, pitch_degrees: float) -> void:
	player.global_position = position_value
	player.rotation.y = deg_to_rad(yaw_degrees)
	player.head.rotation.x = deg_to_rad(pitch_degrees)


func _shot(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	print("saved %s" % file_name)
