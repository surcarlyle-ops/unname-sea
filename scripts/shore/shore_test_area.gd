extends Node3D
## 岸边钓鱼测试区（CodeBuddyPro，2026-10-28）。
##
## 只搭场地并提供查询接口：不含玩家、敌人、钓鱼状态机与 HUD，方便主场景直接实例化。
## 布局数据在 res://data/shore_test_area.json，本脚本不写死坐标。
##
## 主场景接入方式（都在下面有对应方法）：
##   var area := preload("res://scenes/tests/shore_test_area.tscn").instantiate()
##   add_child(area)
##   area.player_spawn_point()            # 玩家出生点（世界坐标）
##   area.water_bounds()                  # Rect2：x/z 平面的水域矩形（世界坐标）
##   area.fishing_arena_config()          # 直接塞给 FishingMVP.config["arena"] 的字典
##   area.pick_encounter_spawn(player.global_position, 5.0)  # 合法异兽出现点，无解返回 Vector3.INF
##
## 水面是纯视觉网格，**不带碰撞体**：钩爪射线默认打所有层，水面有碰撞会被当成可钩锚点，
## 也会挡玩家与异兽。水域边界只通过 water_bounds() / fishing_arena_config() 暴露，
## 当前 FishingMVP.resolve_cast 用的就是矩形 + 水面高度这套几何判定。

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")
const CONFIG_PATH: String = "res://data/shore_test_area.json"
## 池塘水面着色器：山谷那份的高频涟漪版（不改山谷本体），参数在 _pond_material()。
const POND_SHADER: Shader = preload("res://shaders/pond_water.gdshader")
const GRASS_SHADER: Shader = preload("res://shaders/grass_wind.gdshader")
const HILL_SHADER: Shader = preload("res://shaders/valley_hill.gdshader")
## 装饰模型：Ultimate Stylized Nature（Quaternius，CC0 1.0），见同目录 ASSET_NOTES.md。
## 全部无碰撞，只做视觉，不参与抛竿射线、出生点与钩爪判定。
const DECOR_SCENES: Dictionary = {
	"birch": preload("res://assets/environments/stylized_nature/BirchTree_1.gltf"),
	"maple": preload("res://assets/environments/stylized_nature/MapleTree_2.gltf"),
	"dead_tree": preload("res://assets/environments/stylized_nature/DeadTree_3.gltf"),
	"bush_large": preload("res://assets/environments/stylized_nature/Bush_Large.gltf"),
	"bush_small": preload("res://assets/environments/stylized_nature/Bush_Small.gltf"),
	"grass": preload("res://assets/environments/stylized_nature/Grass_Large_Extruded.gltf"),
	"flowers_a": preload("res://assets/environments/stylized_nature/Flower_2_Clump.gltf"),
	"flowers_b": preload("res://assets/environments/stylized_nature/Flower_3_Clump.gltf"),
}

var config: Dictionary = {}
var water_surface: MeshInstance3D
var spawn_root: Node3D
var player_spawn: Marker3D

var _encounter_spawns: Array[Marker3D] = []
var _water_center: Vector2 = Vector2(0.0, -17.5)
var _water_size: Vector2 = Vector2(32.0, 21.0)
var _water_level: float = 0.06
var _combat_ground_node: MeshInstance3D
var _combat_ground_size: Vector2 = Vector2(24.0, 15.0)
var _decor_root: Node3D
var _scissor_materials: Dictionary = {}


func _ready() -> void:
	config = _load_config()
	_build_ground()
	_build_valley()
	_build_backdrop()
	_build_water()
	_build_dock()
	_build_path()
	_build_shore_walls()
	_build_lanterns()
	_build_combat_ground()
	_build_grapple_props()
	_build_rocks()
	_build_decor()
	_build_grass_field()
	_build_spawns()
	_build_signs()
	add_to_group("shore_test_area")


# === 公开查询接口 ===

## 水域矩形（世界坐标 x/z 平面）。落点在矩形内即算水面。本区只支持整体平移，不做旋转/缩放。
func water_bounds() -> Rect2:
	var center: Vector3 = to_global(Vector3(_water_center.x, 0.0, _water_center.y))
	return Rect2(Vector2(center.x - _water_size.x * 0.5, center.z - _water_size.y * 0.5), _water_size)


func water_level() -> float:
	return to_global(Vector3(_water_center.x, _water_level, _water_center.y)).y


## 水面视觉网格（无碰撞）。
func water_mesh_instance() -> MeshInstance3D:
	return water_surface


func is_in_water(point: Vector3) -> bool:
	var bounds: Rect2 = water_bounds()
	if bounds.size == Vector2.ZERO:
		return false
	return bounds.has_point(Vector2(point.x, point.z))


## 直接写进 FishingMVP.config["arena"] 的字典，字段与 data/fishing_mvp.json 的 arena 块一致。
func fishing_arena_config() -> Dictionary:
	var bounds: Rect2 = water_bounds()
	var spawn: Vector3 = player_spawn_point()
	var spots: Array = []
	for point: Vector3 in encounter_spawn_points():
		spots.append([point.x, point.y, point.z])
	return {
		"spawn": [spawn.x, spawn.y, spawn.z],
		"spawn_yaw_degrees": 0.0,
		"pond_min": [bounds.position.x, bounds.position.y],
		"pond_max": [bounds.end.x, bounds.end.y],
		"water_level": water_level(),
		"encounter_spawns": spots,
	}


func player_spawn_point() -> Vector3:
	return player_spawn.global_position if player_spawn != null else Vector3(0.0, 0.08, 6.5)


## 岸边平坦战斗空地（世界坐标 x/z 平面）。
func combat_ground_rect() -> Rect2:
	if _combat_ground_node == null:
		return Rect2()
	var center: Vector2 = Vector2(_combat_ground_node.global_position.x, _combat_ground_node.global_position.z)
	return Rect2(center - _combat_ground_size * 0.5, _combat_ground_size)


func fishing_spot() -> Vector3:
	var spot: Array = config.get("fishing_spot", [0.0, 0.55, -12.5])
	return to_global(_vector3(spot, Vector3(0.0, 0.55, -12.5)))


func encounter_min_distance() -> float:
	return float(config.get("encounter_min_distance", 5.0))


## 全部异兽出生候选点（世界坐标，顺序与 JSON 一致）。
func encounter_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker: Marker3D in _encounter_spawns:
		if is_instance_valid(marker):
			points.append(marker.global_position)
	return points


## 候选点对应的 Marker3D（主场景也可用 marker.global_position 直接取）。
func encounter_spawn_markers() -> Array[Marker3D]:
	return _encounter_spawns


## 选一个距玩家至少 minimum_distance、不在水里、胶囊体不重叠的候选点。
## 候选点都不合法时，围绕玩家在岸上再找一圈；仍无解返回 Vector3.INF。
func pick_encounter_spawn(player_position: Vector3, minimum_distance: float = 5.0) -> Vector3:
	for marker: Marker3D in _encounter_spawns:
		if not is_instance_valid(marker):
			continue
		var spot: Vector3 = marker.global_position
		if _flat_distance(spot, player_position) < minimum_distance:
			continue
		if is_in_water(spot) or spot_blocked(spot):
			continue
		return spot
	for angle: int in range(0, 360, 30):
		var offset: Vector3 = Vector3(cos(deg_to_rad(float(angle))), 0.0, sin(deg_to_rad(float(angle)))) * (minimum_distance + 1.0)
		var spot: Vector3 = player_position + offset
		spot.y = 0.1
		if is_in_water(spot) or not _on_shore(spot) or spot_blocked(spot):
			continue
		return spot
	return Vector3.INF


## 兜底点必须真的踩在岸上（正下方 0.5 米内有层 1 地面），否则会落到场地外。
func _on_shore(point: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 2.0, point - Vector3.UP * 0.5, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return absf((hit.position as Vector3).y - 0.0) < 0.4


## 胶囊体（半径 0.5 / 高 1.1）是否与层 1、2 重叠：用于判断出生点是否卡在墙里或敌人身上。
func spot_blocked(point: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.1
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.6)
	query.collision_mask = 3
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func set_spawn_markers_visible(visible_state: bool) -> void:
	if spawn_root != null:
		spawn_root.visible = visible_state


# === 搭场地 ===

func _build_ground() -> void:
	var shore: Dictionary = config.get("shore", {})
	var size: Vector2 = _vector2(shore.get("size", [56.0, 45.0]), Vector2(56.0, 45.0))
	var center: Vector2 = _vector2(shore.get("center", [0.0, -9.5]), Vector2(0.0, -9.5))
	# 概念图是整片湿绿的谷底，只有水线附近才露沙。碰撞盒不变，只把顶面换成草绿，
	# 沙岸由 _build_valley() 里贴在水边的一条窄带补回来。
	_box("ShoreGround", Vector3(center.x, -1.5, center.y), Vector3(size.x, 3.0, size.y), Color("6f8c4d"))


## 山谷：把原来"一块平地 + 远处石峰"补成四面围合的低谷。
## 全部纯视觉、无碰撞，也不放进 Decor（Decor 只装 JSON 里的贴地模型）。
##  - ValleyFloor：整片谷底草地，盖住 56×45 碰撞盒的边缘
##  - 近岸沙带：只铺玩家这一侧的岸，水面另一侧留给草与芦苇（概念图就是这样）
##  - 山丘：三面围合 + 远处更淡的岭线，形成"谷"
##  - 森林带：谷壁脚下与中景各一圈树，把天空压下来
##  - 石拱：水对岸的视觉焦点，和概念图里那座石拱呼应
func _build_valley() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Valley"
	add_child(root)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261028

	# 谷底：碰撞盒以内绝对水平（和碰撞一致），盒外才缓慢抬头成谷壁。
	_build_valley_floor(root)

	# 近岸泥地：只铺木台前这一小条（x ±5.5，z -7..-4.6），压暗成湿土色。
	# 之前 16×3.4 的浅沙会变成一个显眼的米色土包，把水线整个挡住。
	var water_max: Vector2 = _water_max_local()
	_box("ValleySandBank", Vector3(0.0, 0.006, water_max.y + 1.3), Vector3(11.0, 0.012, 2.4), Color("8d7b5f"), false).reparent(root, true)

	# 三面山丘：far / west / east / behind，全部落在碰撞盒之外。
	var hill_color: Color = Color("6f8f52")
	var hills: Array[Dictionary] = []
	# 山丘排在 z=-56 以外：太近会把水对岸和石拱一起吞进山体。
	for spot: Vector3 in [
		Vector3(-34, 0, -58), Vector3(-16, 0, -62), Vector3(2, 0, -66), Vector3(20, 0, -60), Vector3(36, 0, -56),
		Vector3(-52, 0, -34), Vector3(-56, 0, -14), Vector3(-50, 0, 2),
		Vector3(52, 0, -34), Vector3(56, 0, -14), Vector3(50, 0, 2),
		Vector3(-34, 0, 24), Vector3(-14, 0, 28), Vector3(12, 0, 27), Vector3(34, 0, 23),
	]:
		var radius: float = rng.randf_range(12.0, 19.0)
		var height: float = rng.randf_range(7.0, 13.0)
		var stretch: float = rng.randf_range(0.8, 1.25)
		var tone: Color = hill_color.lerp(Color("7fa05c"), rng.randf_range(0.0, 0.6))
		_hill(root, spot, radius, height, tone, stretch)
		hills.append({"center": spot, "radius": radius, "height": height, "stretch": stretch})
	# 水对岸两侧各一个小丘，中间留口子让石拱露出来（和概念图的取景一样）。
	for side: float in [-1.0, 1.0]:
		_hill(root, Vector3(side * 24.0, 0.0, -44.0), 11.0, 7.0, Color("78985a"), 1.0)

	# 更远的岭线：haze 直接压进雾色，把谷口封住。
	for index: int in range(9):
		var x: float = lerpf(-150.0, 150.0, float(index) / 8.0)
		var z: float = -105.0 - float(index % 3) * 26.0
		var tone: Color = Color("7f9b78").lerp(Color("b6cbb8"), clampf(float(index) / 8.0, 0.0, 1.0))
		_hill(root, Vector3(x, 0.0, z), rng.randf_range(26.0, 42.0), rng.randf_range(22.0, 34.0), tone, 1.4, 0.42)

	# 森林：谷壁脚下一圈近树，中景一圈更大的树，形成层次。
	# 以白桦/枫为主，枯树只占少数：概念图是茂密的彩色树冠，不是枯枝林。
	var trees: Array[PackedScene] = [
		DECOR_SCENES["birch"], DECOR_SCENES["maple"], DECOR_SCENES["birch"], DECOR_SCENES["maple"], DECOR_SCENES["dead_tree"],
	]
	var bushes: Array[PackedScene] = [DECOR_SCENES["bush_large"], DECOR_SCENES["bush_small"], DECOR_SCENES["bush_large"]]
	# 山坡上的树：直接算在球面上，打断山丘那条光滑的轮廓线。
	for hill: Dictionary in hills:
		var center: Vector3 = hill["center"]
		var hill_radius: float = float(hill["radius"])
		var hill_height: float = float(hill["height"])
		var hill_stretch: float = float(hill["stretch"])
		for _tree_index: int in range(2):
			var angle: float = rng.randf_range(0.0, TAU)
			var distance: float = rng.randf_range(0.32, 0.62)
			var px: float = center.x + cos(angle) * hill_radius * hill_stretch * distance
			var pz: float = center.z + sin(angle) * hill_radius * distance
			var nx: float = (px - center.x) / (hill_radius * hill_stretch)
			var nz: float = (pz - center.z) / hill_radius
			var surface: float = maxf(0.0, 1.0 - nx * nx - nz * nz)
			var py: float = hill_height * 0.5 - 0.05 + hill_height * 0.5 * sqrt(surface)
			_tree_at_y(root, trees[rng.randi() % trees.size()], Vector3(px, py, pz), rng.randf_range(1.5, 2.4), rng)
	for index: int in range(64):
		var angle: float = TAU * float(index) / 64.0 + rng.randf_range(-0.05, 0.05)
		var radius: float = rng.randf_range(30.0, 38.0)
		var point: Vector3 = Vector3(cos(angle) * radius, 0.0, -17.5 + sin(angle) * radius * 0.82)
		if _shore_box_contains(point.x, point.z):
			continue
		if absf(point.x) < 7.0 and point.z < -24.0:
			continue  # 石拱前方的取景
		_tree(root, trees[index % trees.size()], point, rng.randf_range(1.8, 2.8), rng)
	for index: int in range(44):
		var angle: float = TAU * float(index) / 44.0 + rng.randf_range(-0.08, 0.08)
		var radius: float = rng.randf_range(48.0, 70.0)
		var point: Vector3 = Vector3(cos(angle) * radius, 0.0, -17.5 + sin(angle) * radius * 0.85)
		_tree(root, trees[(index + 2) % trees.size()], point, rng.randf_range(2.4, 3.6), rng)
	for index: int in range(36):
		var angle: float = TAU * float(index) / 36.0 + rng.randf_range(-0.12, 0.12)
		var radius: float = rng.randf_range(27.0, 33.0)
		var point: Vector3 = Vector3(cos(angle) * radius, 0.0, -17.5 + sin(angle) * radius * 0.8)
		if _shore_box_contains(point.x, point.z):
			continue
		_tree(root, bushes[index % bushes.size()], point, rng.randf_range(1.4, 2.2), rng)
	# 玩家背后：树要放在 BackCliff（z=12.2，前脸 ≈11.5）**前面**，
	# 放到墙后就全被挡掉，转身只会看到一整面光的石壁。
	for index: int in range(14):
		var point: Vector3 = Vector3(lerpf(-34.0, 34.0, float(index) / 13.0) + rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(9.6, 11.2))
		_tree(root, trees[index % trees.size()], point, rng.randf_range(1.6, 2.6), rng)
	# 水对岸的灌木与芦苇：把对岸那条空草带压住，视线越过水面时不会看到光秃的岸线。
	for index: int in range(20):
		if index % 5 == 3:
			continue  # 别排成一条等距的绿篱
		var point: Vector3 = Vector3(lerpf(-15.0, 15.0, float(index) / 19.0) + rng.randf_range(-2.4, 2.4), 0.0, rng.randf_range(-32.4, -28.8))
		if absf(point.x) < 8.5:
			continue  # 石拱的取景口
		_tree(root, bushes[index % bushes.size()], point, rng.randf_range(1.0, 2.3), rng)
	# 水边青苔石：给岸线一点硬度，概念图里水边是有石头的。
	for entry: Dictionary in _boulder_specs():
		_boulder(root, Vector3(entry["x"], 0.0, entry["z"]), entry["size"], entry["yaw"])

	_build_arch(root)
	_build_reeds_and_flowers(root)


## 谷底网格：320 米见方，碰撞盒以内 y=0（和碰撞面完全一致），盒外慢慢抬头，
## 34 米外升到约 10 米，把平地"折"成谷盆。纯视觉，不参与任何判定。
func _build_valley_floor(root: Node3D) -> void:
	var extent: float = 320.0
	var cells: int = 96
	var half: float = extent * 0.5
	var center_z: float = -20.0
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var low: Color = Color("5f7c42")
	var high: Color = Color("7fa05a")
	for iz: int in range(cells + 1):
		for ix: int in range(cells + 1):
			var x: float = lerpf(-half, half, float(ix) / float(cells))
			var z: float = lerpf(-half, half, float(iz) / float(cells)) + center_z
			var y: float = _valley_height(x, z)
			vertices.append(Vector3(x, y, z))
			var shade: float = clampf(y / 12.0, 0.0, 1.0)
			var tone: Color = low.lerp(high, shade * 0.85 + 0.1 * sin(x * 0.21) * cos(z * 0.17))
			colors.append(tone)
	for iz: int in range(cells):
		for ix: int in range(cells):
			var a: int = iz * (cells + 1) + ix
			var c: int = a + cells + 1
			indices.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface: SurfaceTool = SurfaceTool.new()
	surface.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	surface.generate_normals()
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.name = "ValleyFloor"
	floor_mesh.mesh = surface.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	floor_mesh.material_override = material
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_mesh)


## 谷壁高度：碰撞盒内必须严格为 0，否则玩家会看到脚下"悬空"。
func _valley_height(x: float, z: float) -> float:
	var shore: Dictionary = config.get("shore", {})
	var size: Vector2 = _vector2(shore.get("size", [56.0, 45.0]), Vector2(56.0, 45.0))
	var center: Vector2 = _vector2(shore.get("center", [0.0, -9.5]), Vector2(0.0, -9.5))
	var out_x: float = maxf(0.0, absf(x - center.x) - size.x * 0.5)
	var out_back: float = maxf(0.0, (center.y - size.y * 0.5) - z)
	var out_front: float = maxf(0.0, z - (center.y + size.y * 0.5))
	var distance: float = maxf(out_x, maxf(out_back, out_front))
	if distance <= 0.0:
		return 0.0
	var rise: float = smoothstep(0.0, 34.0, distance) * 10.0
	# 低频起伏：让坡面不是一圈等高的碗沿。
	var roll: float = sin(x * 0.08 + 1.3) * cos(z * 0.10 - 0.7) * 1.2
	return rise + roll * smoothstep(0.0, 8.0, distance)


## 石拱：两根石墩 + 五块渐收的拱石，水对岸的视觉落点。无碰撞、不参与玩法。
func _build_arch(root: Node3D) -> void:
	var stone: Color = Color("9c9a86")
	var moss: Color = Color("7f8f68")
	# 立在对岸水线后 4 米：从木台看过去，两根石脚正好踩在浅水上。
	# 瘦一点、矮一点，别在取景里变成一堵灰门。
	var base_z: float = -32.0
	for side: float in [-1.0, 1.0]:
		_box("ArchPier", Vector3(side * 3.0, 2.8, base_z), Vector3(1.3, 5.6, 1.4), stone, false).reparent(root, true)
		_box("ArchPierMoss", Vector3(side * 3.0, 0.45, base_z), Vector3(1.55, 0.9, 1.65), moss, false).reparent(root, true)
	# 拱顶：斜肩 + 顶石拼出坡度，别做成一个方门洞。
	for side: float in [-1.0, 1.0]:
		# 斜肩向中间抬：右肩是 -Z 旋转，写成 +side 会变成向下的 V 字，顶石再压上去就成了"M"。
		var slab: Node3D = _box("ArchShoulder", Vector3(side * 1.6, 6.1, base_z), Vector3(2.1, 0.75, 1.4), stone, false, Vector3(0.0, 0.0, -side * 24.0))
		slab.reparent(root, true)
	_box("ArchKeystone", Vector3(0.0, 6.62, base_z), Vector3(3.0, 0.75, 1.4), stone, false).reparent(root, true)
	_box("ArchTopMoss", Vector3(0.0, 7.05, base_z), Vector3(2.6, 0.14, 1.25), moss, false).reparent(root, true)


## 芦苇与野花：贴着水线的细长草、草地里的小色点。纯 MultiMesh，无碰撞。
func _build_reeds_and_flowers(root: Node3D) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	var bank: Rect2 = _water_bounds_local().grow(0.4)
	var reeds: Array[Transform3D] = []
	var reed_colors: Array[Color] = []
	for _attempt: int in range(2600):
		if reeds.size() >= 760:
			break
		var point: Vector2 = Vector2(
			rng.randf_range(bank.position.x - 2.2, bank.end.x + 2.2),
			rng.randf_range(bank.position.y - 2.2, bank.end.y + 2.2))
		# 芦苇只长在水线外侧 0.15–2.2 米，水里不长。
		if _water_bounds_local().grow(0.15).has_point(point) or not bank.has_point(point):
			continue
		if absf(point.x) < 2.3 and point.y > -14.0:
			continue  # 木台与抛竿走廊
		if _shore_box_contains(point.x, point.y) == false:
			continue
		var scale_value: float = rng.randf_range(1.5, 2.4)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.9, 1.25), scale_value))
		reeds.append(Transform3D(basis, Vector3(point.x, 0.0, point.y)))
		reed_colors.append(Color("#8aa355").lerp(Color("#c3c273"), rng.randf()))
	var reed_mesh: MultiMeshInstance3D = _multimesh_instance("Reeds", _grass_mesh(), reeds, reed_colors, 1.1, 46.0)
	root.add_child(reed_mesh)

	var flowers: Array[Transform3D] = []
	var flower_colors: Array[Color] = []
	var palette: Array[Color] = [Color("#e9dfc9"), Color("#d9a9b8"), Color("#e8c96a"), Color("#9fb2d8")]
	for _attempt: int in range(2600):
		if flowers.size() >= 520:
			break
		var x: float = rng.randf_range(-32.0, 32.0)
		var z: float = rng.randf_range(-36.0, 16.0)
		if _water_bounds_local().grow(1.2).has_point(Vector2(x, z)):
			continue
		if absf(x) < 1.4 and z < 9.0 and z > -14.0:
			continue
		if not _shore_box_contains(x, z):
			continue
		var scale_value: float = rng.randf_range(0.55, 0.95)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value)
		flowers.append(Transform3D(basis, Vector3(x, 0.0, z)))
		flower_colors.append(palette[rng.randi() % palette.size()] * Color(1.0, 1.0, 1.0, 0.95))
	var flower_mesh: MultiMeshInstance3D = _multimesh_instance("Wildflowers", _flower_mesh(), flowers, flower_colors, 0.9, 42.0)
	root.add_child(flower_mesh)


## 小野花网格：两片交叉小十字，顶点色白，靠每实例颜色染色。
func _flower_mesh() -> ArrayMesh:
	var accumulator: Variant = MESH_KIT.Accumulator.new()
	var white: Color = Color(1.0, 1.0, 1.0)
	for plane: int in range(2):
		var angle: float = PI * float(plane) * 0.5
		var half: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.055
		var up: Vector3 = Vector3(0.0, 0.17, 0.0)
		var stem: Vector3 = Vector3(0.0, 0.03, 0.0)
		accumulator.tri(stem - half, stem + half, stem + up, Color(0.55, 0.72, 0.38), Vector3.UP)
		accumulator.tri(stem + up, stem + half, stem - half, white, Vector3.UP)
	return accumulator.to_mesh()


## MultiMesh 装配：草/芦苇/野花共用。range_end 控制可视距离，省掉远处的绘制。
func _multimesh_instance(node_name: String, mesh: ArrayMesh, transforms: Array[Transform3D], colors: Array[Color], wind: float, range_end: float) -> MultiMeshInstance3D:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, colors[index])
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("wind_strength", wind * 0.09)
	material.set_shader_parameter("wind_speed", 1.6)
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.visibility_range_end = range_end
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _hill(parent: Node3D, center: Vector3, radius: float, height: float, color: Color, stretch: float, haze: float = 0.0) -> void:
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "ValleyHill"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 18
	sphere.rings = 9
	body.mesh = sphere
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = HILL_SHADER
	material.set_shader_parameter("base_color", color.darkened(0.22))
	material.set_shader_parameter("top_color", color.lightened(0.05))
	material.set_shader_parameter("haze", haze)
	material.set_shader_parameter("haze_color", Color(0.82, 0.88, 0.82))
	material.set_shader_parameter("top_height", maxf(height * 0.9, 1.0))
	body.material_override = material
	body.scale = Vector3(radius * stretch, height * 0.5, radius)
	body.position = Vector3(center.x, height * 0.5 - 0.05, center.z)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if haze > 0.2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(body)


## 水边石头的位置：手工挑在水线外侧，避开木台、抛竿走廊与战斗空地。
func _boulder_specs() -> Array[Dictionary]:
	return [
		{"x": -18.6, "z": -12.4, "size": 1.7, "yaw": 24.0},
		{"x": -19.8, "z": -21.8, "size": 1.25, "yaw": 66.0},
		{"x": 18.9, "z": -14.6, "size": 1.5, "yaw": -18.0},
		{"x": 20.2, "z": -24.2, "size": 1.1, "yaw": 140.0},
		{"x": -12.4, "z": -29.6, "size": 1.9, "yaw": 92.0},
		{"x": 13.2, "z": -30.2, "size": 1.4, "yaw": 12.0},
	]


## 一块压扁的球体石头：带青苔顶色，无碰撞。
func _boulder(root: Node3D, point: Vector3, size: float, yaw: float) -> void:
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "ShoreBoulder"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 9
	sphere.rings = 5
	body.mesh = sphere
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = HILL_SHADER
	material.set_shader_parameter("base_color", Color("6f7266"))
	material.set_shader_parameter("top_color", Color("6f8f5e"))
	material.set_shader_parameter("haze", 0.0)
	material.set_shader_parameter("haze_color", Color(0.82, 0.88, 0.82))
	material.set_shader_parameter("top_height", size * 0.8)
	material.set_shader_parameter("grain_strength", 0.12)
	body.material_override = material
	body.scale = Vector3(size * 0.85, size * 0.52, size)
	body.position = point + Vector3(0.0, size * 0.42, 0.0)
	body.rotation_degrees.y = yaw
	root.add_child(body)


## 已知地面高度时用这个：山坡上的树不再走谷底高度函数。
func _tree_at_y(parent: Node3D, scene: PackedScene, point: Vector3, scale_value: float, rng: RandomNumberGenerator) -> void:
	var node: Node3D = scene.instantiate() as Node3D
	if node == null:
		return
	node.scale = Vector3.ONE * scale_value
	node.position = point
	node.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	parent.add_child(node)
	_soften_foliage(node)


func _tree(parent: Node3D, scene: PackedScene, point: Vector3, scale_value: float, rng: RandomNumberGenerator) -> void:
	var node: Node3D = scene.instantiate() as Node3D
	if node == null:
		return
	node.scale = Vector3.ONE * scale_value
	# 站到谷壁上：碰撞盒内高度是 0，盒外的树才需要抬头。
	node.position = Vector3(point.x, _valley_height(point.x, point.z), point.z)
	node.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	parent.add_child(node)
	_ground_decor(node, scale_value)
	_soften_foliage(node)


func _shore_box_contains(x: float, z: float) -> bool:
	var shore: Dictionary = config.get("shore", {})
	var size: Vector2 = _vector2(shore.get("size", [56.0, 45.0]), Vector2(56.0, 45.0))
	var center: Vector2 = _vector2(shore.get("center", [0.0, -9.5]), Vector2(0.0, -9.5))
	return absf(x - center.x) <= size.x * 0.5 and absf(z - center.y) <= size.y * 0.5


func _water_max_local() -> Vector2:
	var water_config: Dictionary = config.get("water", {})
	return _vector2(water_config.get("max", [16.0, -7.0]), Vector2(16.0, -7.0))


func _matte(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _build_water() -> void:
	var water_config: Dictionary = config.get("water", {})
	var minimum: Vector2 = _vector2(water_config.get("min", [-16.0, -28.0]), Vector2(-16.0, -28.0))
	var maximum: Vector2 = _vector2(water_config.get("max", [16.0, -7.0]), Vector2(16.0, -7.0))
	_water_level = float(water_config.get("level", 0.06))
	var span: Vector2 = maximum - minimum
	var center: Vector2 = (minimum + maximum) * 0.5
	_water_size = span
	_water_center = center
	# 池底：靠岸是浅沙，往池心沉成青灰淤泥色，配合半透明水面才有"深度"。
	_build_pond_bed(center, span)
	# 湿沙带：水面外侧一圈，颜色比干沙深一点，标出岸线。
	var band: float = float((config.get("shore", {}) as Dictionary).get("wet_band", 0.9))
	var wet: Color = Color("a08a63")
	_box("WetBandFar", Vector3(center.x, 0.008, minimum.y - band * 0.5), Vector3(span.x + band * 2.0, 0.016, band), wet, false)
	_box("WetBandNear", Vector3(center.x, 0.008, maximum.y + band * 0.5), Vector3(span.x + band * 2.0, 0.016, band), wet, false)
	_box("WetBandWest", Vector3(minimum.x - band * 0.5, 0.008, center.y), Vector3(band, 0.016, span.y), wet, false)
	_box("WetBandEast", Vector3(maximum.x + band * 0.5, 0.008, center.y), Vector3(band, 0.016, span.y), wet, false)
	# 水面：细分网格 + 山谷水面着色器。顶点色 r 烘焙"离岸多远"（0 岸边 → 1 池心），
	# 着色器据此做浅滩→深水渐变、菲涅尔与涟漪。仍然没有碰撞体。
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "WaterSurface"
	visual.mesh = _pond_mesh(span, 64, 42)
	visual.material_override = _pond_material()
	visual.position = Vector3(center.x, _water_level, center.y)
	add_child(visual)
	water_surface = visual


## 池塘水面网格：细分平面，顶点色 r = 离最近岸边的距离 / 6 米（0 岸边，1 池心）。
func _pond_mesh(span: Vector2, cells_x: int, cells_z: int) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var half_x: float = span.x * 0.5
	var half_z: float = span.y * 0.5
	for iz: int in range(cells_z + 1):
		for ix: int in range(cells_x + 1):
			var x: float = lerpf(-half_x, half_x, float(ix) / float(cells_x))
			var z: float = lerpf(-half_z, half_z, float(iz) / float(cells_z))
			vertices.append(Vector3(x, 0.0, z))
			var edge: float = minf(minf(x + half_x, half_x - x), minf(z + half_z, half_z - z))
			colors.append(Color(clampf(edge / 6.0, 0.0, 1.0), 0.0, 0.0, 1.0))
	for iz: int in range(cells_z):
		for ix: int in range(cells_x):
			var a: int = iz * (cells_x + 1) + ix
			var c: int = a + cells_x + 1
			indices.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 池底网格：顶点色从岸边的浅沙过渡到池心的青灰淤泥，透水时才看得出深浅。
func _build_pond_bed(center: Vector2, span: Vector2) -> void:
	var cells_x: int = 32
	var cells_z: int = 24
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var half_x: float = span.x * 0.5
	var half_z: float = span.y * 0.5
	# 水下沙比岸上的干沙暗一档：浅滩透出来的才是一层青绿，而不是一片白。
	var sand: Color = Color("ac9670")
	var silt: Color = Color("6d7b56")
	for iz: int in range(cells_z + 1):
		for ix: int in range(cells_x + 1):
			var x: float = lerpf(-half_x, half_x, float(ix) / float(cells_x))
			var z: float = lerpf(-half_z, half_z, float(iz) / float(cells_z))
			var edge: float = minf(minf(x + half_x, half_x - x), minf(z + half_z, half_z - z))
			# 池底不是一张平板：岸边 0.6 米开始下凹，5.5 米外落到 -0.42 米。
			# 水下的沙坡透过浅水看得见，比纯颜色渐变更像真的水。
			var dip: float = smoothstep(0.6, 5.5, edge) * 0.42
			vertices.append(Vector3(x, -dip, z))
			# 0.9 米内是湿沙，6 米外已经沉进池心。
			var sink: float = smoothstep(0.9, 6.0, edge)
			colors.append(sand.lerp(silt, sink))
	for iz: int in range(cells_z):
		for ix: int in range(cells_x):
			var a: int = iz * (cells_x + 1) + ix
			var c: int = a + cells_x + 1
			indices.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface: SurfaceTool = SurfaceTool.new()
	surface.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	surface.generate_normals()
	var bed: MeshInstance3D = MeshInstance3D.new()
	bed.name = "PondBed"
	bed.mesh = surface.commit()
	var bed_material: StandardMaterial3D = StandardMaterial3D.new()
	bed_material.vertex_color_use_as_albedo = true
	bed_material.roughness = 1.0
	bed_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	bed.material_override = bed_material
	bed.position = Vector3(center.x, 0.012, center.y)
	add_child(bed)


## 复用樱花山谷的水面着色器，换成概念图的青绿配色，静水（低流速）。
## 现在的重点是天空反射、太阳碎金与噪波法线：纯色 + 正弦波纹是"假水"的根源。
func _pond_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = POND_SHADER
	# 概念图的水是青绿到深蓝绿的渐变，水越深越沉，浅滩几乎能看见沙。
	material.set_shader_parameter("deep_color", Color(0.03, 0.26, 0.31))
	material.set_shader_parameter("shallow_color", Color(0.15, 0.50, 0.46))
	# 地平线偏奶白、天顶偏蓝，菲涅尔反射在两个色之间过渡。
	material.set_shader_parameter("sky_color", Color(0.52, 0.66, 0.70))
	material.set_shader_parameter("sky_zenith_color", Color(0.26, 0.42, 0.56))
	material.set_shader_parameter("foam_color", Color(0.94, 0.98, 0.95))
	# 浅水几乎透明（看得见沙），深水才压到不透明。
	material.set_shader_parameter("alpha_shallow", 0.5)
	material.set_shader_parameter("alpha_deep", 0.95)
	material.set_shader_parameter("wave_strength", 0.010)
	material.set_shader_parameter("normal_strength", 0.55)
	material.set_shader_parameter("flow_speed", 0.42)
	material.set_shader_parameter("ripple_scale", 2.2)
	material.set_shader_parameter("fresnel_boost", 1.05)
	material.set_shader_parameter("sun_glint", 0.45)
	material.set_shader_parameter("foam_amount", 1.0)
	# 池子只有二十来米深，淡出从 26 米才开始，对岸那片水也要有波纹。
	material.set_shader_parameter("detail_fade_start", 26.0)
	material.set_shader_parameter("detail_fade_end", 85.0)
	# 细碎波纹用运行时生成的可平铺法线纹理：程序化噪声叠到第 5 层会撑爆 GLES3 编译器。
	var ripple_noise: FastNoiseLite = FastNoiseLite.new()
	ripple_noise.seed = 20261028
	ripple_noise.frequency = 0.028
	ripple_noise.fractal_octaves = 3
	var ripple_texture: NoiseTexture2D = NoiseTexture2D.new()
	ripple_texture.width = 512
	ripple_texture.height = 512
	ripple_texture.seamless = true
	ripple_texture.as_normal_map = true
	ripple_texture.bump_strength = 2.2
	ripple_texture.noise = ripple_noise
	material.set_shader_parameter("ripple_normal", ripple_texture)
	# 主光在玩家背后，真实反射会让水面看不到高光；这里把碎金方向偏到对岸，
	# 静水面才有一条碎金带（和概念图一致，强度压得很低不抢戏）。
	material.set_shader_parameter("sun_direction", Vector3(-0.34, 0.52, -0.78).normalized())
	material.set_shader_parameter("sun_color", Color(1.0, 0.95, 0.84))
	return material


## 远岭：三排圆缓的低山，越远越淡，靠雾拉开层次（概念图里那种被森林覆盖的谷口）。
## 原来的尖锥像喀斯特石峰，和这张概念图的圆润山谷不是一回事，改成压扁的球体。
func _build_backdrop() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Backdrop"
	add_child(root)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261028
	for ring: int in range(3):
		var count: int = 9 + ring * 3
		var base_z: float = -104.0 - float(ring) * 38.0
		var color: Color = Color("7f9b78").lerp(Color("c4d4c6"), 0.30 + float(ring) * 0.28)
		for index: int in range(count):
			var x: float = lerpf(-170.0, 170.0, float(index) / float(count - 1)) + rng.randf_range(-12.0, 12.0)
			var z: float = base_z + rng.randf_range(-14.0, 14.0)
			var height: float = rng.randf_range(24.0, 38.0) * (1.0 + float(ring) * 0.22)
			var radius: float = rng.randf_range(30.0, 48.0) * (0.9 + float(ring) * 0.18)
			_hill(root, Vector3(x, 0.0, z), radius, height, color, rng.randf_range(1.0, 1.5), 0.28 + float(ring) * 0.20)


## 石板路：从出生点铺到钓台坡道，纯视觉（无碰撞），踩上去不影响移动。
func _build_path() -> void:
	var root: Node3D = Node3D.new()
	root.name = "StonePath"
	add_child(root)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 771
	var z: float = 8.6
	var index: int = 0
	while z > -3.0:
		var depth: float = rng.randf_range(0.6, 0.95)
		var slab: Node3D = _box("PathSlab%d" % index, Vector3(rng.randf_range(-0.3, 0.3), 0.015, z),
			Vector3(rng.randf_range(1.3, 1.8), 0.035, depth), Color("b0a28b"), false,
			Vector3(0.0, rng.randf_range(-12.0, 12.0), 0.0))
		slab.reparent(root, true)
		z -= depth + rng.randf_range(0.06, 0.2)
		index += 1


## 岸边矮石墙：贴着水线两段，中间给钓台留口子（概念图里水边的石砌矮墙）。
func _build_shore_walls() -> void:
	var wall_color: Color = Color("ab9d85")
	var cap_color: Color = Color("c0b39a")
	for side: float in [-1.0, 1.0]:
		for segment: int in range(2):
			var center_x: float = side * (6.4 + float(segment) * 4.6)
			_box("ShoreWall", Vector3(center_x, 0.36, -6.35), Vector3(4.3, 0.72, 0.46), wall_color)
			_box("ShoreWallCap", Vector3(center_x, 0.75, -6.35), Vector3(4.5, 0.1, 0.56), cap_color, false)


## 暖色灯笼柱：钓台入口一根、石墙上一根。点光源不带阴影，GL 兼容下代价可控。
func _build_lanterns() -> void:
	_lantern(Vector3(-2.7, 0.0, -4.3))
	_lantern(Vector3(7.6, 0.0, -6.35))


func _lantern(base: Vector3) -> void:
	var wood: Color = Color("5a4634")
	_box("LanternPost", base + Vector3(0.0, 1.25, 0.0), Vector3(0.16, 2.5, 0.16), wood)
	_box("LanternArm", base + Vector3(0.32, 2.42, 0.0), Vector3(0.8, 0.1, 0.1), wood)
	var head: Vector3 = base + Vector3(0.66, 2.16, 0.0)
	var lamp: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.26, 0.34, 0.26)
	lamp.mesh = box
	lamp.material_override = _glow_material(Color("ffc27a"), 2.6)
	lamp.position = head
	add_child(lamp)
	_box("LanternCap", head + Vector3(0.0, 0.2, 0.0), Vector3(0.34, 0.06, 0.34), Color("6b5a44"), false)
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = Color("ffb066")
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.position = head
	add_child(light)


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _build_dock() -> void:
	var dock: Dictionary = config.get("dock", {})
	var width: float = float(dock.get("width", 3.0))
	var center_x: float = float(dock.get("center_x", 0.0))
	var near_z: float = float(dock.get("near_z", -5.4))
	var far_z: float = float(dock.get("far_z", -13.4))
	var deck_y: float = float(dock.get("deck_y", 0.55))
	var thickness: float = float(dock.get("deck_thickness", 0.18))
	var length: float = absf(near_z - far_z)
	var center_z: float = (near_z + far_z) * 0.5
	_box("DockDeck", Vector3(center_x, deck_y - thickness * 0.5, center_z), Vector3(width, thickness, length), Color("8a6b4a"))
	# 甲板木纹：纯装饰，不参与碰撞。
	var plank_z: float = far_z + 0.6
	while plank_z < near_z - 0.2:
		_box("DockPlank", Vector3(center_x, deck_y + 0.004, plank_z), Vector3(width - 0.06, 0.008, 0.05), Color("6d5238"), false)
		plank_z += 1.1
	# 支柱：从水面下扎到甲板底，四根足够看清是"架起来的木台"。
	for side: float in [-1.0, 1.0]:
		for post_z: float in [near_z - 1.2, far_z + 1.0]:
			_box("DockPost", Vector3(center_x + side * (width * 0.5 - 0.16), deck_y - 0.45, post_z), Vector3(0.16, 0.9, 0.16), Color("6d5238"))
	# 入口坡道：岸边 y=0 抬到甲板 y=deck_y，坡度约 15°，不用跳也能上台。
	var run: float = float(dock.get("ramp_run", 2.0))
	var angle: float = rad_to_deg(atan2(deck_y, run))
	var slope_length: float = sqrt(run * run + deck_y * deck_y)
	var normal: Vector3 = Vector3(0.0, cos(deg_to_rad(angle)), sin(deg_to_rad(angle)))
	var mid: Vector3 = Vector3(center_x, deck_y * 0.5, near_z + run * 0.5)
	_box("DockRamp", mid - normal * (thickness * 0.5), Vector3(width, thickness, slope_length), Color("7d5f42"), true, Vector3(angle, 0.0, 0.0))
	# 坡面横条：不加这几条时，浅棕色斜面在低角度阳光下会读成一个沙丘。
	var slope_dir: Vector3 = Vector3(0.0, sin(deg_to_rad(angle)), -cos(deg_to_rad(angle)))
	for step: int in range(3):
		var along: float = (float(step) - 1.0) * (slope_length * 0.30)
		_box("DockRampPlank", mid + normal * (thickness * 0.5 + 0.004) + slope_dir * along, Vector3(width - 0.12, 0.012, 0.14), Color("5f452e"), false, Vector3(angle, 0.0, 0.0))
	# 入口两根短柱 + 金色柱帽，既是钓台标识，也提示可以从这里上去。
	for side: float in [-1.0, 1.0]:
		var post: Vector3 = Vector3(center_x + side * (width * 0.5 + 0.16), deck_y + 0.5, near_z + 0.35)
		_box("DockGatePost", post, Vector3(0.14, 1.0, 0.14), Color("6d5238"))
		_box("DockGateCap", post + Vector3(0.0, 0.56, 0.0), Vector3(0.24, 0.1, 0.24), Color("d2ac68"), false)
	# 钓点：甲板上的金色站位块 + 水面上的金色落点环（都不带碰撞，不挡抛竿射线）。
	var spot: Vector3 = _vector3(config.get("fishing_spot", [0.0, deck_y, -12.5]), Vector3(0.0, deck_y, -12.5))
	_box("FishingSpotPlate", Vector3(spot.x, deck_y + 0.006, spot.z), Vector3(2.4, 0.012, 1.4), Color("d2ac68"), false)
	var marker_distance: float = float(config.get("fishing_marker_offset", 8.0))
	_ring("FishingSpotRing", Vector3(spot.x, _water_level + 0.02, spot.z - marker_distance), 1.25, Color(0.94, 0.81, 0.56, 0.55))


func _build_combat_ground() -> void:
	var ground: Dictionary = config.get("combat_ground", {})
	var center: Vector2 = _vector2(ground.get("center", [0.0, 2.0]), Vector2(0.0, 2.0))
	_combat_ground_size = _vector2(ground.get("size", [24.0, 15.0]), Vector2(24.0, 15.0))
	# 空地标记：一块极淡的矩形色块 + 四条金边，范围和 combat_ground_rect() 完全对齐。
	var fill: MeshInstance3D = MeshInstance3D.new()
	fill.name = "CombatGround"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = _combat_ground_size
	fill.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.94, 0.81, 0.56, 0.07)
	fill.material_override = material
	fill.position = Vector3(center.x, 0.014, center.y)
	add_child(fill)
	_combat_ground_node = fill
	var edge: Color = Color("c2a878")
	for side: float in [-1.0, 1.0]:
		_box("CombatEdge", Vector3(center.x, 0.02, center.y + side * _combat_ground_size.y * 0.5),
			Vector3(_combat_ground_size.x, 0.012, 0.12), edge, false)
		_box("CombatEdge", Vector3(center.x + side * _combat_ground_size.x * 0.5, 0.02, center.y),
			Vector3(0.12, 0.012, _combat_ground_size.y), edge, false)
	# 四角短桩，给出空地的边界感，但保持中间完全通透。
	for side: float in [-1.0, 1.0]:
		for depth: float in [-1.0, 1.0]:
			var corner: Vector3 = Vector3(
				center.x + side * _combat_ground_size.x * 0.5,
				0.22,
				center.y + depth * _combat_ground_size.y * 0.5)
			_box("CombatCorner", corner, Vector3(0.18, 0.44, 0.18), Color("c4b396"), false)
			_box("CombatCornerCap", corner + Vector3(0.0, 0.25, 0.0), Vector3(0.26, 0.06, 0.26), Color("d2ac68"), false)


func _build_grapple_props() -> void:
	# 两根 7 米石柱：钩爪锚点，落在战斗空地两侧，不挡中间通路。
	for pair: Array in config.get("grapple_pillars", [[-13.0, -1.0], [13.0, -1.0]]):
		var point: Vector2 = _vector2(pair, Vector2.ZERO)
		_box("GrapplePillar", Vector3(point.x, 3.5, point.y), Vector3(1.4, 7.0, 1.4), Color("b6a891"))
		_box("GrapplePillarCap", Vector3(point.x, 7.15, point.y), Vector3(2.2, 0.3, 2.2), Color("d2ac68"))
	# 后侧岩壁：既是场地边界，也是一整面可钩的墙。
	_box("BackCliff", Vector3(0.0, 2.75, 12.2), Vector3(24.0, 5.5, 1.4), Color("a4967e"))
	_box("BackCliffStripe", Vector3(0.0, 5.0, 11.48), Vector3(22.0, 0.16, 0.04), Color("d2ac68"), false)


func _build_rocks() -> void:
	var index: int = 1
	for entry: Dictionary in config.get("rocks", []):
		var point: Vector3 = _vector3(entry.get("position", [0.0, 0.25, 0.0]), Vector3.ZERO)
		var size: Vector3 = _vector3(entry.get("size", [1.4, 0.5, 1.2]), Vector3(1.4, 0.5, 1.2))
		var yaw: float = float(entry.get("yaw", 0.0))
		_box("ShoreRock%d" % index, point, size, Color("8b8478"), true, Vector3(0.0, yaw, 0.0))
		index += 1


## 装饰（Ultimate Stylized Nature，CC0）：纯视觉，不带碰撞体。
## 坐标全部来自 data/shore_test_area.json 的 decor 数组，不进水面/抛竿走廊/战斗空地。
func _build_decor() -> void:
	var entries: Array = config.get("decor", [])
	if entries.is_empty():
		return
	_decor_root = Node3D.new()
	_decor_root.name = "Decor"
	add_child(_decor_root)
	var index: int = 1
	for entry: Dictionary in entries:
		var key: String = str(entry.get("model", ""))
		var scene: PackedScene = DECOR_SCENES.get(key) as PackedScene
		if scene == null:
			push_error("岸边装饰缺少模型：%s（第 %d 项）" % [key, index])
			continue
		var node: Node3D = scene.instantiate() as Node3D
		var scale_value: float = float(entry.get("scale", 1.0))
		node.name = "Decor_%s_%d" % [key, index]
		node.scale = Vector3.ONE * scale_value
		node.position = _vector3(entry.get("position", [0.0, 0.0, 0.0]), Vector3.ZERO)
		node.rotation_degrees.y = float(entry.get("yaw", 0.0))
		_decor_root.add_child(node)
		_ground_decor(node, scale_value)
		_soften_foliage(node)
		index += 1


## 岸边草地：复用山谷那套草叶网格（3 组交叉叶片 + 根/梢顶点色），MultiMesh 撒 9000 株。
## 无碰撞、不参与任何判定；水里、木台、石板路和出生点附近不长草。
## 草叶加了一点风：见 shaders/grass_wind.gdshader，根不动、梢摆，整片草才活。
func _build_grass_field() -> void:
	var mesh: ArrayMesh = _grass_mesh()
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var shore: Dictionary = config.get("shore", {})
	var shore_size: Vector2 = _vector2(shore.get("size", [56.0, 45.0]), Vector2(56.0, 45.0))
	var shore_center: Vector2 = _vector2(shore.get("center", [0.0, -9.5]), Vector2(0.0, -9.5))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	for _attempt: int in range(42000):
		if transforms.size() >= 18000:
			break
		# 撒得比碰撞盒略大，让草从盒子边缘一直铺到谷壁脚下。
		var x: float = shore_center.x + rng.randf_range(-shore_size.x * 0.62, shore_size.x * 0.62)
		var z: float = shore_center.y + rng.randf_range(-shore_size.y * 0.58, shore_size.y * 0.58)
		var point: Vector2 = Vector2(x, z)
		# 水面、湿沙带、木台、石板路、出生点附近留空。
		if _water_bounds_local().grow(0.5).has_point(point):
			continue
		if absf(x) < 1.9 and z < -5.0 and z > -13.8:
			continue
		if absf(x) < 1.2 and z > -4.0 and z < 9.0:
			continue
		var blocked: bool = false
		for spawn: Vector3 in encounter_spawn_points():
			if Vector2(x - spawn.x, z - spawn.z).length() < 0.7:
				blocked = true
				break
		if blocked:
			continue
		var scale_value: float = rng.randf_range(0.8, 1.2)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.85, 1.3), scale_value))
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
		var tone: float = rng.randf()
		colors.append(Color("#5c7f45").lerp(Color("#a6c273"), tone) if tone < 0.88 else Color("#c3cc80"))
	add_child(_multimesh_instance("GrassField", mesh, transforms, colors, 1.0, 58.0))


## 草叶网格：三组交叉叶片，根暗梢亮，和山谷同一套做法（0.30 m 高）。
func _grass_mesh() -> ArrayMesh:
	var accumulator: Variant = MESH_KIT.Accumulator.new()
	var root_color: Color = Color("#4b6636")
	var tip_color: Color = Color("#93b264")
	for plane: int in range(3):
		var angle: float = PI * float(plane) / 3.0
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.11
		var side: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.038
		for blade: int in range(2):
			var offset: Vector3 = Vector3(cos(angle + PI * 0.5), 0.0, sin(angle + PI * 0.5)) * (float(blade) - 0.5) * 0.13
			var tip: Vector3 = offset + direction + Vector3(0.0, 0.20, 0.0)
			accumulator.tri(offset - side, offset + side, tip, root_color, Vector3.UP)
			accumulator.tri(tip, offset + side, offset - side, tip_color, Vector3.UP)
	return accumulator.to_mesh()


func _water_bounds_local() -> Rect2:
	var water_config: Dictionary = config.get("water", {})
	var minimum: Vector2 = _vector2(water_config.get("min", [-16.0, -28.0]), Vector2(-16.0, -28.0))
	var maximum: Vector2 = _vector2(water_config.get("max", [16.0, -7.0]), Vector2(16.0, -7.0))
	return Rect2(minimum, maximum - minimum)


## 按包围盒把模型底面贴到 y=0、水平居中：换模型或改缩放都不用再手调 y。
func _ground_decor(node: Node3D, scale_value: float) -> void:
	var bounds: AABB = _decor_bounds(node)
	if bounds.size == Vector3.ZERO:
		return
	node.position += Vector3(-bounds.get_center().x * scale_value, -bounds.position.y * scale_value, -bounds.get_center().z * scale_value)


func _decor_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	var to_local: Transform3D = node.global_transform.affine_inverse()
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box: AABB = (to_local * mesh_node.global_transform) * mesh_node.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## glTF 给叶片的是 BLEND，多层叠一起会排序闪烁；换成 alpha scissor 更稳、也更省。
## 材质按原资源缓存一份，多个实例共用同一个副本。
func _soften_foliage(node: Node3D) -> void:
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var material: Material = mesh_node.get_active_material(surface)
			if not (material is StandardMaterial3D):
				continue
			var standard: StandardMaterial3D = material as StandardMaterial3D
			if standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var softened: StandardMaterial3D = _scissor_materials.get(material) as StandardMaterial3D
			if softened == null:
				softened = standard.duplicate() as StandardMaterial3D
				softened.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				softened.alpha_scissor_threshold = 0.4
				softened.cull_mode = BaseMaterial3D.CULL_DISABLED
				_scissor_materials[material] = softened
			mesh_node.set_surface_override_material(surface, softened)


func _build_spawns() -> void:
	spawn_root = Node3D.new()
	spawn_root.name = "Spawns"
	add_child(spawn_root)
	player_spawn = Marker3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.position = _vector3(config.get("player_spawn", [0.0, 0.08, 6.5]), Vector3(0.0, 0.08, 6.5))
	spawn_root.add_child(player_spawn)
	_add_spawn_visual(player_spawn, Color(0.56, 0.82, 0.77, 0.80), "玩家出生点")
	var index: int = 1
	for point: Array in config.get("encounter_spawns", []):
		var marker: Marker3D = Marker3D.new()
		marker.name = "EncounterSpawn%d" % index
		marker.position = _vector3(point, Vector3.ZERO)
		marker.add_to_group("shore_encounter_spawn")
		spawn_root.add_child(marker)
		_add_spawn_visual(marker, Color(0.90, 0.69, 0.42, 0.80), "S%d" % index)
		_encounter_spawns.append(marker)
		index += 1
	# 默认隐藏：预览里按 F1 显示，避免正常游玩时满地圆环。
	spawn_root.visible = false


func _build_signs() -> void:
	var spot: Vector3 = _vector3(config.get("fishing_spot", [0.0, 0.55, -12.5]), Vector3(0.0, 0.55, -12.5))
	# 2.05 米时正好压在视线中间的鱼竿上方，抬到 3.4 米、字号收小，别挡水面。
	_sign("钓点 · 抛竿 2–12 米", Vector3(spot.x, spot.y + 3.4, spot.z - 0.2), 24)
	# 入口再放一块：从出生点走过来时先看到它，明确"这里上去钓鱼"。
	# 往左偏一点，避免和甲板末端那块在出生点视线里叠成一团。
	_sign("钓点 · 上木台", Vector3(spot.x - 2.4, 1.9, -4.2), 30)
	var ground: Dictionary = config.get("combat_ground", {})
	var center: Vector2 = _vector2(ground.get("center", [0.0, 2.0]), Vector2(0.0, 2.0))
	var ground_sign: Label3D = _sign("战斗空地", Vector3(center.x + 8.4, 0.6, center.y + 5.4), 26)
	ground_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign("岸边测试区  /  SHORE TEST", Vector3(0.0, 4.6, 11.3), 40)


func _add_spawn_visual(marker: Node3D, color: Color, text: String) -> void:
	var ring: MeshInstance3D = _ring("Ring", Vector3(0.0, -0.06, 0.0), 0.8, color)
	ring.reparent(marker, false)
	var label: Label3D = Label3D.new()
	label.text = text
	label.position = Vector3(0.0, 1.3, 0.0)
	label.font_size = 26
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("f0e6c8")
	label.outline_modulate = Color("3f4a45")
	label.outline_size = 8
	marker.add_child(label)


# === 小工具 ===

func _box(node_name: String, point: Vector3, dimensions: Vector3, color: Color, solid: bool = true, rotation: Vector3 = Vector3.ZERO) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = node_name
	body.position = point
	body.rotation_degrees = rotation
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(color)
	body.add_child(visual)
	if solid:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = dimensions
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	add_child(body)
	return body


func _ring(node_name: String, point: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = node_name
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius * 0.86
	torus.outer_radius = radius
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	ring.position = point
	add_child(ring)
	return ring


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.24)
	material.roughness = 0.95
	material.metallic = 0.0
	return material


func _sign(text: String, point: Vector3, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = ""
	label.position = point
	label.font_size = font_size
	label.pixel_size = 0.009
	label.modulate = Color("eff0da")
	label.outline_modulate = Color("435a55")
	label.outline_size = 10
	add_child(label)
	return label


func _load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("岸边测试区配置读取失败：%s" % CONFIG_PATH)
	return {}


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _vector2(values: Variant, fallback: Vector2) -> Vector2:
	if values is Array and (values as Array).size() >= 2:
		var array: Array = values as Array
		return Vector2(float(array[0]), float(array[1]))
	return fallback


func _vector3(values: Variant, fallback: Vector3) -> Vector3:
	if values is Array and (values as Array).size() >= 3:
		var array: Array = values as Array
		return Vector3(float(array[0]), float(array[1]), float(array[2]))
	return fallback
