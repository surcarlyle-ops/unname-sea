extends SceneTree
## 岸边钓鱼测试区结构检查（CodeBuddyPro，2026-10-28）。
##
## 跑法：
##   "D:\claude project\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\claude project\projects\unname_sea" ^
##     --log-file .mvp_qa/shore_test_area_check.log --script res://tests/shore_test_area_check.gd
##
## 覆盖：水域矩形与水面高度、2–12 米有效抛竿、岸沿不遮挡水面、岸边与钓台碰撞、
## 出生点到钓点的通路、8 个异兽候选点与选择器、水面可读性参数。

const AREA_SCENE: PackedScene = preload("res://scenes/tests/shore_test_area.tscn")
const PREVIEW_SCENE: String = "res://scenes/tests/shore_test_area_preview.tscn"
const FISHING_SCRIPT: Script = preload("res://scripts/mvp/fishing_mvp.gd")
const FISHING_CONFIG_PATH: String = "res://data/fishing_mvp.json"

var _passes: int = 0
var _fails: int = 0
var _area: Node3D
var _fishing: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_area = AREA_SCENE.instantiate() as Node3D
	root.add_child(_area)
	current_scene = _area
	await physics_frame
	await physics_frame
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FISHING_CONFIG_PATH))
	var config: Dictionary = (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}
	config["arena"] = _area.fishing_arena_config()
	_fishing = FISHING_SCRIPT.new()
	_fishing.name = "FishingMVP"
	_fishing.config = config
	root.add_child(_fishing)
	await physics_frame

	_check_water()
	_check_casts()
	_check_surface()
	_check_path()
	_check_spawns()
	_check_decor()

	# 场地检查完毕，换成完整预览场景，验证"钓到异兽 → 选点生成"这条链路。
	_area.queue_free()
	_fishing.queue_free()
	await process_frame
	await process_frame
	await _check_preview()

	print("SHORE_TEST_AREA_RESULT pass=%d fail=%d" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)


## 预览场景端到端：异兽请求必须落在离玩家 ≥5 米的岸上，清空后状态复原。
func _check_preview() -> void:
	var preview: Node3D = (load(PREVIEW_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(preview)
	current_scene = preview
	await process_frame
	await process_frame
	var player: CharacterBody3D = preview.player
	player.set_physics_process(false)
	var area: Node3D = preview.area
	_check(area != null and preview.fishing != null, "预览场景装配了测试区与钓鱼状态机")
	preview.call("_on_fishing_encounter", "mon_phosphor_scale", "item_scale", 1)
	await physics_frame
	var enemy: CharacterBody3D = preview.get("_encounter_enemy")
	var spawned: bool = enemy != null and is_instance_valid(enemy)
	var distance: float = 0.0
	if spawned:
		distance = Vector2(enemy.global_position.x - player.global_position.x,
			enemy.global_position.z - player.global_position.z).length()
	_check(spawned and distance >= 5.0 and not area.is_in_water(enemy.global_position),
		"异兽请求生成在岸上、距玩家 %.1f 米" % distance)
	_check(bool(preview.fishing.encounter_active), "异兽在场时钓鱼被锁住")
	preview.call("_clear_enemies")
	await physics_frame
	_check(preview.get("_encounter_enemy") == null and not bool(preview.fishing.encounter_active),
		"清空异兽后钓鱼状态复原")
	preview.queue_free()
	await process_frame


# === 水域 ===

func _check_water() -> void:
	var bounds: Rect2 = _area.water_bounds()
	_check(absf(bounds.size.x - 32.0) < 0.01 and absf(bounds.size.y - 21.0) < 0.01,
		"水域矩形 %.1f x %.1f 米（x %.1f…%.1f / z %.1f…%.1f）" % [
			bounds.size.x, bounds.size.y, bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y])
	_check(absf(_area.water_level() - 0.06) < 0.01, "水面高度 %.2f 米" % _area.water_level())
	var surface: MeshInstance3D = _area.water_mesh_instance()
	_check(surface != null and surface.get_child_count() == 0, "水面是纯视觉网格（不带碰撞体，钩爪不会钩到水面）")
	_check(_area.is_in_water(Vector3(0.0, 0.06, -20.0)) and not _area.is_in_water(Vector3(0.0, 0.0, 6.5)),
		"is_in_water 命中池心、排除出生点")
	var arena: Dictionary = _area.fishing_arena_config()
	var pond_min: Array = arena.get("pond_min", [])
	var pond_max: Array = arena.get("pond_max", [])
	_check(pond_min.size() == 2 and pond_max.size() == 2 and arena.has("water_level") and arena.has("encounter_spawns"),
		"fishing_arena_config() 字段可直接喂给 FishingMVP.config.arena")
	var ground: Rect2 = _area.combat_ground_rect()
	_check(absf(ground.size.x - 24.0) < 0.01 and absf(ground.size.y - 15.0) < 0.01,
		"战斗空地 %.1f x %.1f 米" % [ground.size.x, ground.size.y])


# === 抛竿 ===

func _check_casts() -> void:
	# 岸边站在钓台左侧，避免木台本身挡视线；钓台末端是主抛竿位。
	var eyes: Array[Dictionary] = [
		{"name": "岸边", "eye": Vector3(-6.0, 1.66, -6.0)},
		{"name": "钓台末端", "eye": Vector3(0.0, 2.15, -12.5)},
	]
	for entry: Dictionary in eyes:
		var eye: Vector3 = entry.eye as Vector3
		var label: String = str(entry.name)
		var drop: float = eye.y - _area.water_level()
		for horizontal: float in [2.0, 4.0, 6.0, 8.0, 10.0, 11.0]:
			_check_cast(eye, label, horizontal)
		# 射线长度正好 12 米：横向距离 = sqrt(12² − 落差²)，验证上限刚好够用。
		var edge_horizontal: float = sqrt(maxf(144.0 - drop * drop, 1.0))
		_check_cast(eye, label + "（12 米射线）", edge_horizontal)
		# 太近应被拒绝。
		var near_point: Vector3 = Vector3(eye.x, _area.water_level(), eye.z - 1.0)
		var near: Dictionary = _fishing.resolve_cast(eye, (near_point - eye).normalized())
		_check(near.has("reason"), "%s 1 米落点被拒绝：%s" % [label, str(near.get("reason", "通过"))])


func _check_cast(eye: Vector3, label: String, horizontal: float) -> void:
	var point: Vector3 = Vector3(eye.x, _area.water_level(), eye.z - horizontal)
	var direction: Vector3 = (point - eye).normalized()
	var result: Dictionary = _fishing.resolve_cast(eye, direction)
	if result.has("reason"):
		_check(false, "%s 抛竿 %.1f 米失败：%s" % [label, horizontal, str(result.reason)])
		return
	var hit: Vector3 = result.point as Vector3
	var actual: float = Vector2(hit.x - eye.x, hit.z - eye.z).length()
	# 岸沿/木台不得比水面更早挡住射线。
	var solid: Dictionary = _area.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(eye, hit, 1))
	_check(absf(actual - horizontal) < 0.25 and solid.is_empty(),
		"%s 抛竿 %.1f 米 → 落点 %.2f 米（%s）" % [
			label, horizontal, actual, "被遮挡" if not solid.is_empty() else "视线直达水面"])


# === 水面可读性 ===

func _check_surface() -> void:
	var visual: MeshInstance3D = _area.water_mesh_instance()
	var material: Material = visual.material_override
	var deep: Color = Color.BLACK
	if material is ShaderMaterial:
		deep = (material as ShaderMaterial).get_shader_parameter("deep_color") as Color
	elif material is StandardMaterial3D:
		deep = (material as StandardMaterial3D).albedo_color
	var luminance: float = deep.r * 0.299 + deep.g * 0.587 + deep.b * 0.114
	_check(luminance < 0.45, "深水颜色亮度 %.2f（鱼漂在水面上仍能对比出来）" % luminance)
	_check(material is ShaderMaterial, "水面使用山谷水面着色器（青绿浅滩 → 深水）")
	var top: float = visual.global_position.y
	_check(absf(top - _area.water_level()) < 0.001, "水面高度 %.3f 与水位一致" % top)
	_check(_area.get_node_or_null("FishingSpotRing") != null, "水面钓点环 FishingSpotRing 存在")
	_check(_area.get_node_or_null("FishingSpotPlate") != null, "钓台金色站位块存在")


# === 岸边碰撞与通路 ===

func _check_path() -> void:
	var spawn: Vector3 = _area.player_spawn_point()
	var spot: Vector3 = _area.fishing_spot()
	_check(absf(_floor_at(spawn.x, spawn.z)) < 0.05, "出生点站在地面 y=%.2f" % _floor_at(spawn.x, spawn.z))
	_check(absf(_floor_at(spot.x, spot.z) - 0.55) < 0.06, "钓点站在甲板 y=%.2f" % _floor_at(spot.x, spot.z))
	var flat: bool = true
	for point: Vector2 in [Vector2(0.0, 2.0), Vector2(-10.0, 0.0), Vector2(10.0, 0.0), Vector2(0.0, 8.0), Vector2(0.0, -2.0)]:
		if absf(_floor_at(point.x, point.y)) > 0.05:
			flat = false
	_check(flat, "战斗空地 5 个采样点都在 y=0 平地")
	var ramp: float = _floor_at(0.0, -4.4)
	_check(ramp > 0.1 and ramp < 0.45, "钓台坡道中点 y=%.2f（可走上台）" % ramp)
	# 出生点 → 钓点：每 0.4 米检查胶囊净空与地面连续性。
	var blocked_at: String = ""
	var max_step: float = 0.0
	var previous: float = NAN
	var steps: int = int(spawn.distance_to(spot) / 0.4)
	for index: int in range(steps + 1):
		var point: Vector3 = spawn.lerp(spot, float(index) / float(maxi(steps, 1)))
		var floor_y: float = _floor_at(point.x, point.z)
		if is_nan(floor_y):
			blocked_at = "z=%.1f 无地面" % point.z
			break
		if not is_nan(previous):
			max_step = maxf(max_step, absf(floor_y - previous))
		previous = floor_y
		if _capsule_blocked(Vector3(point.x, floor_y + 0.9, point.z)):
			blocked_at = "z=%.1f 胶囊被挡" % point.z
			break
	_check(blocked_at.is_empty() and max_step < 0.35,
		"出生点到钓点 %.1f 米通路可走（最大台阶 %.2f 米）%s" % [
			spawn.distance_to(spot), max_step, "" if blocked_at.is_empty() else " · " + blocked_at])


func _check_spawns() -> void:
	var points: Array[Vector3] = _area.encounter_spawn_points()
	_check(points.size() == 8, "异兽候选点 %d 个" % points.size())
	var spawn: Vector3 = _area.player_spawn_point()
	var bad: Array[String] = []
	for index: int in range(points.size()):
		var point: Vector3 = points[index]
		var distance: float = Vector2(point.x - spawn.x, point.z - spawn.z).length()
		var floor_y: float = _floor_at(point.x, point.z)
		if distance < 5.0:
			bad.append("S%d 距出生点 %.1f 米" % [index + 1, distance])
		if _area.is_in_water(point):
			bad.append("S%d 在水里" % (index + 1))
		if _area.spot_blocked(point):
			bad.append("S%d 卡在碰撞里" % (index + 1))
		if is_nan(floor_y) or absf(floor_y - point.y) > 0.3:
			bad.append("S%d 地面高度 %.2f" % [index + 1, floor_y])
	_check(bad.is_empty(), "8 个候选点都在岸上、离出生点 ≥5 米且不卡碰撞%s" % ("" if bad.is_empty() else " · " + ", ".join(bad)))
	var markers: Array[Marker3D] = _area.encounter_spawn_markers()
	_check(markers.size() == 8 and markers[0].is_in_group("shore_encounter_spawn"),
		"候选点 Marker3D 与 shore_encounter_spawn 分组可用")
	# 选择器：不同站位都要给出 ≥5 米且合法的点。
	var stands: Array[Vector3] = [spawn, _area.fishing_spot(), Vector3(0.0, 0.1, 2.0), Vector3(10.5, 0.1, 4.5)]
	var pick_ok: bool = true
	for stand: Vector3 in stands:
		var picked: Vector3 = _area.pick_encounter_spawn(stand, 5.0)
		if picked == Vector3.INF:
			pick_ok = false
			continue
		if Vector2(picked.x - stand.x, picked.z - stand.z).length() < 5.0 or _area.is_in_water(picked):
			pick_ok = false
	_check(pick_ok, "选择器在 %d 个站位都给出 ≥5 米合法点" % stands.size())
	_check(_area.pick_encounter_spawn(spawn, 100.0) == Vector3.INF, "无合法点（要求 100 米）时返回 INF")


# === 装饰 ===

## 装饰只做视觉：不能有碰撞、不能进水面/抛竿走廊/战斗空地、不能压出生点，而且要贴地。
func _check_decor() -> void:
	var root: Node3D = _area.get_node_or_null("Decor") as Node3D
	var expected: int = (_area.get("config") as Dictionary).get("decor", []).size()
	_check(root != null and root.get_child_count() == expected and expected > 0,
		"装饰 %d 个全部加载（JSON %d 条）" % [root.get_child_count() if root != null else 0, expected])
	if root == null:
		return
	var water: Rect2 = _area.water_bounds()
	var ground: Rect2 = _area.combat_ground_rect()
	var spawn_points: Array[Vector3] = _area.encounter_spawn_points()
	spawn_points.append(_area.player_spawn_point())
	var problems: Array[String] = []
	var floating: Array[String] = []
	for child: Node in root.get_children():
		var node: Node3D = child as Node3D
		var point: Vector3 = node.global_position
		var label: String = str(node.name)
		if water.has_point(Vector2(point.x, point.z)):
			problems.append(label + " 在水里")
		# 抛竿走廊只算水面这一段（岸边到远岸），远岸后面的树不算挡。
		if absf(point.x) < 4.5 and point.z < -4.0 and point.z > water.position.y - 0.5:
			problems.append(label + " 挡抛竿走廊")
		if absf(point.x) < ground.size.x * 0.5 - 0.5 and point.z > ground.position.y and point.z < ground.end.y:
			problems.append(label + " 在战斗空地里")
		for spawn: Vector3 in spawn_points:
			if Vector2(point.x - spawn.x, point.z - spawn.z).length() < 1.5:
				problems.append(label + " 压出生点")
				break
		if not node.find_children("*", "CollisionObject3D", true, false).is_empty():
			problems.append(label + " 带碰撞")
		var bounds: AABB = _world_bounds(node)
		if absf(bounds.position.y) > 0.15:
			floating.append("%s y=%.2f" % [label, bounds.position.y])
	_check(problems.is_empty(), "装饰全部不进水面/抛竿走廊/战斗空地、不压出生点、无碰撞%s" % ("" if problems.is_empty() else " · " + ", ".join(problems)))
	_check(floating.is_empty(), "装饰全部贴地%s" % ("" if floating.is_empty() else " · " + ", ".join(floating)))


func _world_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


# === 工具 ===

func _floor_at(x: float, z: float) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(x, 6.0, z), Vector3(x, -3.0, z), 1)
	var hit: Dictionary = _area.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit.position as Vector3).y


func _capsule_blocked(point: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 3
	return not _area.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _check(ok: bool, message: String) -> void:
	if ok:
		_passes += 1
		print("PASS  " + message)
	else:
		_fails += 1
		print("FAIL  " + message)
