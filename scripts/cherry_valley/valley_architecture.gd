extends Node3D
## (Claude Code) Village architecture: red bridge, tea house, houses, shrine, pagoda,
## stone lanterns, fences and steps. All meshes go through one accumulator per
## structure so the draw-call count stays low.

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var config: Dictionary
var terrain: Node3D
var materials: Dictionary
var sizes: Dictionary = {}

var _lantern_bodies: Array[NamedNode] = []
var _window_lights: Array[Node3D] = []


## NamedNode lets the lighting module reach the lantern emission materials later.
class NamedNode:
	var node: MeshInstance3D
	var material: StandardMaterial3D


func build(cfg: Dictionary, terrain_node: Node3D, kit_materials: Dictionary) -> void:
	config = cfg
	terrain = terrain_node
	materials = kit_materials
	var village: Dictionary = cfg.village
	_build_bridge(village.bridge)
	_build_tea_house(village.tea_house)
	for house: Dictionary in village.houses:
		_build_house(house)
	_build_shrine(village.shrine)
	_build_pagoda(village.pagoda)
	for point: Variant in village.lanterns:
		_build_lantern(Vector2(float(point[0]), float(point[1])))
	for fence: Array in village.fences:
		var fence_from: Array = fence[0]
		var fence_to: Array = fence[1]
		_build_fence(
			Vector2(float(fence_from[0]), float(fence_from[1])),
			Vector2(float(fence_to[0]), float(fence_to[1]))
		)
	for steps: Dictionary in village.stone_steps:
		_build_steps(steps)
	sizes["structures"] = 5 + (village.houses as Array).size() + (village.lanterns as Array).size()


func set_lantern_energy(energy: float) -> void:
	for lantern: NamedNode in _lantern_bodies:
		if is_instance_valid(lantern.node):
			lantern.material.emission_energy_multiplier = energy


# ---------------------------------------------------------------- bridge

## The deck is generated from the ground at both heads instead of a fixed height:
## the old bridge sat 1.35 m above the path, so the player could never walk on.
## The span also grows until both ends land on the bank rather than in the water.
func _build_bridge(bridge: Dictionary) -> void:
	var center: Vector2 = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	var width: float = float(bridge.width)
	var river: Vector2 = terrain.river_point_at_z(center.y)
	var yaw: float = _river_crossing_yaw(river, center)
	var span: float = terrain.bridge_span(center, bridge)
	var half: float = span * 0.5
	var axis: Vector2 = terrain.crossing_axis(center)
	var west: Vector2 = center - axis * half
	var east: Vector2 = center + axis * half
	var west_y: float = terrain.height_at(west.x, west.y)
	var east_y: float = terrain.height_at(east.x, east.y)
	# `bridge.height` is the clearance asked for above the water. The arch is only
	# as tall as it needs to be, so the heads still meet the ground exactly.
	var arch: float = maxf(0.42, terrain.water_level + float(bridge.height) - maxf(west_y, east_y))
	var root: Node3D = Node3D.new()
	root.name = "RedBridge"
	root.position = Vector3(center.x, 0.0, center.y)
	root.rotation.y = yaw
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var red: Color = Color("#b8463a")
	var deep_red: Color = Color("#8f3229")
	var stone: Color = Color("#9d9a8e")
	var wood: Color = Color("#6e5241")
	var segments: int = 20
	for segment: int in range(segments):
		var t0: float = float(segment) / float(segments)
		var t1: float = float(segment + 1) / float(segments)
		var x0: float = lerpf(-half, half, t0)
		var x1: float = lerpf(-half, half, t1)
		var y0: float = _deck_height(t0, west_y, east_y, arch)
		var y1: float = _deck_height(t1, west_y, east_y, arch)
		acc.quad(
			Vector3(x0, y0, -width * 0.5), Vector3(x1, y1, -width * 0.5),
			Vector3(x1, y1, width * 0.5), Vector3(x0, y0, width * 0.5),
			red.lerp(wood, t0 * 0.25), Vector3.UP
		)
		# Side beams under the deck.
		acc.box(Vector3((x0 + x1) * 0.5, y0 - 0.22, -width * 0.5 + 0.12), Vector3((x1 - x0) + 0.06, 0.30, 0.22), deep_red)
		acc.box(Vector3((x0 + x1) * 0.5, y0 - 0.22, width * 0.5 - 0.12), Vector3((x1 - x0) + 0.06, 0.30, 0.22), deep_red)
		# Railings.
		for side: float in [-1.0, 1.0]:
			acc.box(Vector3((x0 + x1) * 0.5, y0 + 1.0, side * (width * 0.5 - 0.12)), Vector3((x1 - x0) + 0.05, 0.12, 0.14), deep_red)
			acc.box(Vector3((x0 + x1) * 0.5, y0 + 0.50, side * (width * 0.5 - 0.12)), Vector3((x1 - x0) + 0.05, 0.08, 0.10), red)
		if segment % 2 == 0:
			for side: float in [-1.0, 1.0]:
				acc.cylinder(
					Vector3(x0, y0 + 0.05, side * (width * 0.5 - 0.12)),
					Vector3(x0, y0 + 1.10, side * (width * 0.5 - 0.12)),
					0.07, 0.06, 6, deep_red
				)
	# End posts with rounded caps, planted on the bank rather than in the river.
	for end: int in range(2):
		var x: float = -half if end == 0 else half
		var end_y: float = west_y if end == 0 else east_y
		for side: float in [-1.0, 1.0]:
			acc.cylinder(Vector3(x, end_y - 0.6, side * (width * 0.5 + 0.1)), Vector3(x, end_y + 1.15, side * (width * 0.5 + 0.1)), 0.20, 0.16, 10, red)
			acc.blob(Vector3(x, end_y + 1.22, side * (width * 0.5 + 0.1)), Vector3(0.19, 0.13, 0.19), Color("#d9b06a"), 4, 8, 0.02, 9)
	var mesh_node: MeshInstance3D = MESH_KIT.instance(acc, materials.architecture, "RedBridgeMesh")
	root.add_child(mesh_node)
	# Walkable collision follows the same curve as the deck, so feet stay on it at
	# the crown and there is no lip to catch at either head.
	var collision_segments: int = 18
	for segment: int in range(collision_segments):
		var t0: float = float(segment) / float(collision_segments)
		var t1: float = float(segment + 1) / float(collision_segments)
		var cx0: float = lerpf(-half, half, t0)
		var cx1: float = lerpf(-half, half, t1)
		var cy0: float = _deck_height(t0, west_y, east_y, arch)
		var cy1: float = _deck_height(t1, west_y, east_y, arch)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "BridgeDeckSegment%d" % segment
		body.position = Vector3((cx0 + cx1) * 0.5, (cy0 + cy1) * 0.5 - 0.16, 0.0)
		body.rotation.z = atan2(cy1 - cy0, cx1 - cx0)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(absf(cx1 - cx0) + 0.12, 0.32, width)
		shape.shape = box
		body.add_child(shape)
		# Railings follow the arch too. Two straight walls over the whole span used
		# to hang 1.4 m above the deck ends and caught the player by the head.
		for side: float in [-1.0, 1.0]:
			var rail: CollisionShape3D = CollisionShape3D.new()
			var rail_box: BoxShape3D = BoxShape3D.new()
			rail_box.size = Vector3(absf(cx1 - cx0) + 0.12, 1.15, 0.24)
			rail.shape = rail_box
			rail.position = Vector3(0.0, 0.16 + 0.58, side * (width * 0.5 - 0.12))
			body.add_child(rail)
		root.add_child(body)
	var crown: float = maxf(west_y, east_y) + arch
	# Store the deck transform for navigation.
	sizes["bridge_deck_y"] = crown
	sizes["bridge_yaw"] = yaw
	sizes["bridge_span"] = span
	sizes["bridge_head_west"] = west_y
	sizes["bridge_head_east"] = east_y


## Deck height along the span: a straight line between the two heads plus a sine
## arch, so the ends are exactly at ground level and the middle clears the water.
func _deck_height(t: float, west_y: float, east_y: float, arch: float) -> float:
	return lerpf(west_y, east_y, t) + sin(t * PI) * arch


## Camera-facing yaw so the bridge spans the river perpendicular to its flow.
func _river_crossing_yaw(river: Vector2, center: Vector2) -> float:
	var ahead: Vector2 = terrain.sample_river(clampf(terrain.nearest_river_t(river) + 0.02, 0.0, 1.0))
	var tangent: Vector2 = ahead - river
	if tangent.length_squared() < 0.0001:
		return 0.0
	tangent = tangent.normalized()
	var crossing: Vector2 = Vector2(-tangent.y, tangent.x)
	return atan2(-crossing.y, crossing.x)


# ---------------------------------------------------------------- buildings

func _build_tea_house(spec: Dictionary) -> void:
	var center: Vector2 = Vector2(float(spec.center[0]), float(spec.center[1]))
	var yaw: float = deg_to_rad(float(spec.yaw))
	var size: Vector2 = Vector2(float(spec.size[0]), float(spec.size[1]))
	var height: float = float(spec.height)
	var root: Node3D = Node3D.new()
	root.name = "TeaHouse"
	root.position = Vector3(center.x, terrain.height_at(center.x, center.y), center.y)
	root.rotation.y = yaw
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var plaster: Color = Color("#e6dcc2")
	var timber: Color = Color("#5d4436")
	var roof: Color = Color("#7a4636")
	var roof_light: Color = Color("#935941")
	var stone: Color = Color("#9a9689")
	var glow: Color = Color("#ffd79a")
	var half_w: float = size.x * 0.5
	var half_d: float = size.y * 0.5
	# Stone base, buried deep enough that the terrace edge never shows daylight.
	acc.box(Vector3(0, -0.15, 0), Vector3(size.x + 1.4, 1.7, size.y + 1.4), stone)
	# Walls: a plaster box with visible timber posts at the corners.
	acc.box(Vector3(0, height * 0.5 + 0.7, 0), Vector3(size.x, height, size.y), plaster)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			acc.box(Vector3(sx * half_w, height * 0.5 + 0.7, sz * half_d), Vector3(0.34, height, 0.34), timber)
	for sz: float in [-1.0, 1.0]:
		acc.box(Vector3(0, height * 0.5 + 0.7, sz * half_d), Vector3(size.x, 0.24, 0.26), timber)
	# Open front: a darker window band + glowing paper panels.
	acc.box(Vector3(0, height * 0.62 + 0.7, -half_d - 0.03), Vector3(size.x * 0.78, height * 0.42, 0.10), glow)
	for sx: float in [-0.3, 0.3]:
		acc.box(Vector3(sx * size.x, height * 0.62 + 0.7, -half_d - 0.10), Vector3(0.12, height * 0.46, 0.08), timber)
	# Veranda.
	if bool(spec.veranda):
		acc.box(Vector3(0, 0.9, -half_d - 1.3), Vector3(size.x + 1.0, 0.22, 2.6), timber.darkened(0.1))
		for sx: float in [-1.0, -0.35, 0.35, 1.0]:
			acc.cylinder(Vector3(sx * (half_w + 0.35), 0.0, -half_d - 2.45), Vector3(sx * (half_w + 0.35), 0.9, -half_d - 2.45), 0.10, 0.09, 6, timber)
	# Curved hipped roof built from four sloping quads and a ridge.
	_curved_roof(acc, Vector3(0, height + 0.7, 0), Vector2(size.x + 2.6, size.y + 2.6), roof, roof_light)
	# Awning cloth over the veranda.
	acc.box(Vector3(0, height + 0.35, -half_d - 1.6), Vector3(size.x + 0.9, 0.12, 3.0), Color("#c9a98c"), 0.0)
	root.add_child(MESH_KIT.instance(acc, materials.architecture, "TeaHouseMesh"))
	MESH_KIT.solid_box(root, "TeaHouseBody", Vector3(0, height * 0.5 + 0.7, 0), Vector3(size.x, height, size.y), 0.0)
	MESH_KIT.solid_box(root, "TeaHouseVeranda", Vector3(0, 0.55, -half_d - 1.3), Vector3(size.x + 1.0, 1.1, 2.6), 0.0)


func _build_house(spec: Dictionary) -> void:
	var center: Vector2 = Vector2(float(spec.center[0]), float(spec.center[1]))
	var yaw: float = deg_to_rad(float(spec.yaw))
	var size: Vector2 = Vector2(float(spec.size[0]), float(spec.size[1]))
	var height: float = float(spec.height)
	var root: Node3D = Node3D.new()
	root.name = "House_%d_%d" % [int(center.x), int(center.y)]
	root.position = Vector3(center.x, terrain.height_at(center.x, center.y), center.y)
	root.rotation.y = yaw
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var wall: Color = Color("#ddd3bd")
	var timber: Color = Color("#564033")
	var roof_color: Color = Color("#6f7a74")
	var roof_light: Color = Color("#8c968e")
	var stone: Color = Color("#96928a")
	var glow: Color = Color("#ffcf94")
	var half_w: float = size.x * 0.5
	var half_d: float = size.y * 0.5
	acc.box(Vector3(0, -0.2, 0), Vector3(size.x + 1.0, 1.6, size.y + 1.0), stone)
	acc.box(Vector3(0, height * 0.5 + 0.6, 0), Vector3(size.x, height, size.y), wall)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			acc.box(Vector3(sx * half_w, height * 0.5 + 0.6, sz * half_d), Vector3(0.28, height, 0.28), timber)
	# 墙裙：下半截压深，和上方浅墙分层，避免整面墙一块纯色。
	var skirt_h: float = 0.55
	acc.box(Vector3(0, 0.6 + skirt_h * 0.5, 0), Vector3(size.x + 0.06, skirt_h, size.y + 0.06), timber.darkened(0.18))
	# 横向木条：等分墙面，打断大面积色块。
	for band: int in range(3):
		var band_y: float = 0.6 + height * (0.30 + 0.22 * float(band))
		acc.box(Vector3(0, band_y, 0), Vector3(size.x + 0.08, 0.10, size.y + 0.08), timber)
	acc.box(Vector3(0, height + 0.62, 0), Vector3(size.x + 0.5, 0.22, size.y + 0.5), timber)
	# One lit window on the side facing the village path.
	acc.box(Vector3(half_w + 0.02, height * 0.58 + 0.6, 0.0), Vector3(0.10, height * 0.30, size.y * 0.34), glow)
	# 窗框与窗棂：发光面外面压一圈木框和细棂，看起来才像窗而不是一块亮板。
	var win_y: float = height * 0.58 + 0.6
	var win_h: float = height * 0.30
	var win_d: float = size.y * 0.34
	acc.box(Vector3(half_w + 0.05, win_y, 0.0), Vector3(0.05, win_h + 0.16, win_d + 0.16), timber)
	for bar: int in range(3):
		var bar_z: float = lerpf(-win_d * 0.33, win_d * 0.33, float(bar) / 2.0)
		acc.box(Vector3(half_w + 0.10, win_y, bar_z), Vector3(0.04, win_h, 0.035), timber.darkened(0.3))
	acc.box(Vector3(half_w + 0.10, win_y, 0.0), Vector3(0.04, 0.035, win_d), timber.darkened(0.3))
	# 门：正面中央，深色门框 + 内凹门板 + 竖向板缝。
	var door_w: float = minf(size.x * 0.34, 1.0)
	var door_h: float = minf(height * 0.72, 1.9)
	acc.box(Vector3(0, 0.6 + door_h * 0.5, half_d + 0.03), Vector3(door_w + 0.18, door_h + 0.14, 0.10), timber.darkened(0.10))
	acc.box(Vector3(0, 0.6 + door_h * 0.5, half_d + 0.07), Vector3(door_w, door_h, 0.06), timber.darkened(0.32))
	for slot: int in range(3):
		var slot_x: float = lerpf(-door_w * 0.33, door_w * 0.33, float(slot) / 2.0)
		acc.box(Vector3(slot_x, 0.6 + door_h * 0.5, half_d + 0.11), Vector3(0.03, door_h * 0.92, 0.03), timber.darkened(0.45))
	_curved_roof(acc, Vector3(0, height + 0.6, 0), Vector2(size.x + 1.8, size.y + 1.8), roof_color, roof_light)
	root.add_child(MESH_KIT.instance(acc, materials.architecture, "HouseMesh"))
	MESH_KIT.solid_box(root, "HouseBody", Vector3(0, height * 0.5 + 0.6, 0), Vector3(size.x, height, size.y), 0.0)


func _build_shrine(spec: Dictionary) -> void:
	var center: Vector2 = Vector2(float(spec.center[0]), float(spec.center[1]))
	var yaw: float = deg_to_rad(float(spec.yaw))
	var size: Vector2 = Vector2(float(spec.size[0]), float(spec.size[1]))
	var height: float = float(spec.height)
	var root: Node3D = Node3D.new()
	root.name = "Shrine"
	root.position = Vector3(center.x, terrain.height_at(center.x, center.y), center.y)
	root.rotation.y = yaw
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var vermilion: Color = Color("#c0523f")
	var white: Color = Color("#f0e7d4")
	var dark: Color = Color("#3f3733")
	var stone: Color = Color("#a9a598")
	var gold: Color = Color("#d8b26a")
	var half_w: float = size.x * 0.5
	var half_d: float = size.y * 0.5
	acc.box(Vector3(0, 0.0, 0), Vector3(size.x + 2.2, 2.0, size.y + 2.2), stone)
	acc.box(Vector3(0, height * 0.5 + 1.0, 0), Vector3(size.x, height, size.y), white)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			acc.cylinder(Vector3(sx * half_w, 0.0, sz * half_d), Vector3(sx * half_w, height + 1.0, sz * half_d), 0.28, 0.24, 10, vermilion)
	# Torii-style side gates framing the shrine entrance.
	for sx: float in [-1.0, 1.0]:
		acc.cylinder(Vector3(sx * (half_w + 1.4), 0.0, -half_d - 2.2), Vector3(sx * (half_w + 1.4), height + 2.2, -half_d - 2.2), 0.22, 0.20, 8, vermilion)
	acc.box(Vector3(0, height + 2.4, -half_d - 2.2), Vector3(size.x + 4.6, 0.42, 0.5), vermilion)
	acc.box(Vector3(0, height + 2.9, -half_d - 2.2), Vector3(size.x + 5.6, 0.24, 0.6), dark)
	# 墙面木构：横向长押 + 正面竖向柱，打断整块白墙。
	for band: int in range(2):
		var band_y: float = 1.0 + height * (0.42 + 0.34 * float(band))
		acc.box(Vector3(0, band_y, 0), Vector3(size.x + 0.12, 0.14, size.y + 0.12), vermilion.darkened(0.25))
	for post: int in range(3):
		var post_x: float = lerpf(-half_w * 0.66, half_w * 0.66, float(post) / 2.0)
		acc.box(Vector3(post_x, height * 0.5 + 1.0, -half_d - 0.02), Vector3(0.16, height, 0.16), vermilion.darkened(0.2))
	# Golden shrine door.
	acc.box(Vector3(0, height * 0.42 + 1.0, -half_d - 0.03), Vector3(size.x * 0.5, height * 0.66, 0.14), gold.darkened(0.25))
	# 屋顶原本用近黑色，瓦片的明暗分层在黑底上完全看不出，改用偏冷的石板灰。
	_curved_roof(acc, Vector3(0, height + 1.0, 0), Vector2(size.x + 3.2, size.y + 3.2), Color("#59616e"), Color("#7d8794"))
	root.add_child(MESH_KIT.instance(acc, materials.architecture, "ShrineMesh"))
	MESH_KIT.solid_box(root, "ShrineBody", Vector3(0, height * 0.5 + 1.0, 0), Vector3(size.x, height, size.y), 0.0)


func _build_pagoda(spec: Dictionary) -> void:
	var center: Vector2 = Vector2(float(spec.center[0]), float(spec.center[1]))
	var levels: int = int(spec.levels)
	var level_height: float = float(spec.level_height)
	var base_width: float = float(spec.base_width)
	var taper: float = float(spec.taper)
	var base_y: float = terrain.height_at(center.x, center.y)
	var root: Node3D = Node3D.new()
	root.name = "Pagoda"
	root.position = Vector3(center.x, base_y, center.y)
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var body: Color = Color("#a9503f")
	var roof: Color = Color("#4d4542")
	var roof_edge: Color = Color("#6b605a")
	var stone: Color = Color("#9c998e")
	acc.box(Vector3(0, 0.1, 0), Vector3(base_width + 5.0, 2.2, base_width + 5.0), stone)
	var y: float = 1.1
	var width: float = base_width
	for level: int in range(levels):
		var h: float = level_height
		acc.box(Vector3(0, y + h * 0.5, 0), Vector3(width, h, width), body)
		# Eave ring wider than the body, with a slight upturn box on each side.
		acc.box(Vector3(0, y + h, 0), Vector3(width + 2.6, 0.34, width + 2.6), roof)
		for side: int in range(4):
			var angle: float = float(side) * PI * 0.5
			var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * (width + 1.5)
			acc.box(Vector3(offset.x, y + h + 0.22, offset.z), Vector3(0.4, 0.5, width * 0.25), roof_edge, angle)
		y += h + 0.34
		width = maxf(width * taper, 1.6)
	# Spire.
	acc.cylinder(Vector3(0, y, 0), Vector3(0, y + 5.2, 0), 0.34, 0.06, 10, roof_edge)
	for ring: int in range(4):
		acc.blob(Vector3(0, y + 1.2 + ring * 0.9, 0), Vector3(0.42, 0.10, 0.42), Color("#c9a35e"), 3, 8, 0.02, ring)
	root.add_child(MESH_KIT.instance(acc, materials.architecture, "PagodaMesh"))
	MESH_KIT.solid_box(root, "PagodaBody", Vector3(0, y * 0.5, 0), Vector3(base_width, y, base_width), 0.0)


## Four-sided curved roof: each face bows upward, corners lift.
func _curved_roof(acc: MESH_KIT.Accumulator, top_center: Vector3, footprint: Vector2, color: Color, highlight: Color) -> void:
	var half_w: float = footprint.x * 0.5
	var half_d: float = footprint.y * 0.5
	var rise: float = maxf(footprint.x, footprint.y) * 0.34
	var apex_y: float = top_center.y + rise
	var apex: Vector3 = Vector3(top_center.x, apex_y, top_center.z)
	var corners: Array[Vector3] = [
		Vector3(top_center.x - half_w, top_center.y, top_center.z - half_d),
		Vector3(top_center.x + half_w, top_center.y, top_center.z - half_d),
		Vector3(top_center.x + half_w, top_center.y, top_center.z + half_d),
		Vector3(top_center.x - half_w, top_center.y, top_center.z + half_d),
	]
	for side: int in range(4):
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var mid: Vector3 = (a + b) * 0.5
		# Corner lift.
		var lift_a: Vector3 = a + Vector3(0.0, rise * 0.22, 0.0)
		var lift_b: Vector3 = b + Vector3(0.0, rise * 0.22, 0.0)
		var apex_local: Vector3 = apex
		var normal: Vector3 = ((b - a) * -1.0).cross(apex - mid).normalized()
		acc.tri(lift_a, lift_b, apex_local, color, normal)
		acc.tri(a, lift_a, apex_local, color.darkened(0.08), normal)
		acc.tri(lift_b, b, apex_local, color.darkened(0.08), normal)
		# Underside so the roof is not hollow when seen from below.
		acc.tri(b, a, apex_local, highlight.darkened(0.25), -normal)
		# 瓦片层：从檐口到屋脊铺横向条带，交替明暗并留出接缝。
		# 没有这层的话屋顶就是一整片纯色三角面，远看像塑料板。
		var tile_rows: int = 6
		var up_dir: Vector3 = (apex_local - mid).normalized()
		for row: int in range(tile_rows):
			var t0: float = float(row) / float(tile_rows)
			var t1: float = float(row + 1) / float(tile_rows)
			var e0a: Vector3 = lift_a.lerp(apex_local, t0)
			var e0b: Vector3 = lift_b.lerp(apex_local, t0)
			var e1a: Vector3 = lift_a.lerp(apex_local, t1)
			var e1b: Vector3 = lift_b.lerp(apex_local, t1)
			var lift: Vector3 = normal * (0.022 * (1.0 - t0))
			var row_color: Color = color.lightened(0.06) if row % 2 == 0 else color.darkened(0.06)
			acc.quad(e0a + lift, e0b + lift, e1b + lift, e1a + lift, row_color, normal)
			# 瓦沟：每层顶部压一条暗线，制造层叠感。
			acc.quad(e1a + lift, e1b + lift, e1b + lift - up_dir * 0.045, e1a + lift - up_dir * 0.045, color.darkened(0.22), normal)


# ---------------------------------------------------------------- small props

func _build_lantern(point: Vector2) -> void:
	var ground_y: float = terrain.height_at(point.x, point.y)
	var root: Node3D = Node3D.new()
	root.name = "StoneLantern"
	root.position = Vector3(point.x, ground_y, point.y)
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var stone: Color = Color("#9d9b90")
	acc.box(Vector3(0, 0.12, 0), Vector3(0.62, 0.24, 0.62), stone.darkened(0.08))
	acc.cylinder(Vector3(0, 0.2, 0), Vector3(0, 0.95, 0), 0.16, 0.13, 8, stone)
	acc.box(Vector3(0, 1.02, 0), Vector3(0.46, 0.16, 0.46), stone.darkened(0.05))
	acc.box(Vector3(0, 1.28, 0), Vector3(0.40, 0.36, 0.40), stone.lightened(0.05))
	acc.box(Vector3(0, 1.52, 0), Vector3(0.66, 0.16, 0.66), stone.darkened(0.1))
	acc.blob(Vector3(0, 1.63, 0), Vector3(0.10, 0.09, 0.10), stone.lightened(0.08), 3, 6, 0.02, 2)
	var mesh_node: MeshInstance3D = MESH_KIT.instance(acc, materials.architecture, "LanternStone")
	root.add_child(mesh_node)
	# Glowing paper core.
	var glow_material: StandardMaterial3D = MESH_KIT.emissive_material(Color("#ffcf8a"), 1.6)
	var glow_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	glow_acc.box(Vector3(0, 1.28, 0), Vector3(0.30, 0.28, 0.30), Color.WHITE)
	var glow_node: MeshInstance3D = MESH_KIT.instance(glow_acc, glow_material, "LanternGlow")
	glow_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow_node)
	var entry: NamedNode = NamedNode.new()
	entry.node = glow_node
	entry.material = glow_material
	_lantern_bodies.append(entry)
	# Soft halo quad so lanterns read at distance without bloom levels.
	var halo: MeshInstance3D = _make_halo(Vector3(0, 1.28, 0), 1.5, Color("#ffcf8a"))
	root.add_child(halo)
	MESH_KIT.solid_box(root, "LanternBody", Vector3(0, 0.9, 0), Vector3(0.62, 1.8, 0.62), 0.0)


func _make_halo(position: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(color, 0.16)
	material.albedo_texture = _halo_texture()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(radius, radius)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "LanternHalo"
	node.mesh = quad
	node.material_override = material
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static var _halo_cache: GradientTexture2D


## Gentle radial falloff used for lantern halos and fireflies.
func _halo_texture() -> GradientTexture2D:
	if _halo_cache != null:
		return _halo_cache
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_halo_cache = texture
	return texture


func _build_fence(from: Vector2, to: Vector2) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Fence"
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var timber: Color = Color("#6a5142")
	var length: float = from.distance_to(to)
	var direction: Vector2 = (to - from).normalized()
	var yaw: float = atan2(-direction.y, direction.x)
	var posts: int = maxi(int(length / 2.2), 2)
	for index: int in range(posts + 1):
		var t: float = float(index) / float(posts)
		var p: Vector2 = from.lerp(to, t)
		var y: float = terrain.height_at(p.x, p.y)
		acc.cylinder(Vector3(p.x, y - 0.1, p.y), Vector3(p.x, y + 0.95, p.y), 0.09, 0.08, 6, timber)
	# Rails are built span by span so they follow the ground. One straight bar over
	# the whole run floated in the air wherever the bank sloped.
	for index: int in range(posts):
		var t0: float = float(index) / float(posts)
		var t1: float = float(index + 1) / float(posts)
		var p0: Vector2 = from.lerp(to, t0)
		var p1: Vector2 = from.lerp(to, t1)
		var y0: float = terrain.height_at(p0.x, p0.y)
		var y1: float = terrain.height_at(p1.x, p1.y)
		var mid: Vector2 = (p0 + p1) * 0.5
		var mid_y: float = (y0 + y1) * 0.5
		var segment_yaw: float = atan2(-(p1.y - p0.y), p1.x - p0.x)
		var segment_length: float = p0.distance_to(p1) + 0.06
		acc.box(Vector3(mid.x, mid_y + 0.72, mid.y), Vector3(segment_length, 0.10, 0.08), timber, segment_yaw)
		acc.box(Vector3(mid.x, mid_y + 0.40, mid.y), Vector3(segment_length, 0.08, 0.07), timber.darkened(0.1), segment_yaw)
	root.add_child(MESH_KIT.instance(acc, materials.architecture, "FenceMesh"))


func _build_steps(spec: Dictionary) -> void:
	var from: Vector2 = Vector2(float(spec.from[0]), float(spec.from[1]))
	var to: Vector2 = Vector2(float(spec.to[0]), float(spec.to[1]))
	var count: int = int(spec.count)
	var root: Node3D = Node3D.new()
	root.name = "StoneSteps"
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var stone: Color = Color("#a6a192")
	var direction: Vector2 = (to - from).normalized()
	var yaw: float = atan2(-direction.y, direction.x)
	for index: int in range(count):
		var t: float = float(index) / float(maxi(count - 1, 1))
		var p: Vector2 = from.lerp(to, t)
		var y: float = terrain.height_at(p.x, p.y)
		acc.box(Vector3(p.x, y + 0.06, p.y), Vector3(1.8, 0.14, 1.0), stone.darkened(0.02 * float(index % 3)), yaw)
	root.add_child(MESH_KIT.instance(acc, materials.architecture, "StepsMesh"))
