extends Area3D
class_name LootDrop
## 岸边掉落 + 靠近拾取组件（可复用，CodeBuddy 2026-10-28）。
##
## 一件掉落 = 一个 Area3D。数量全部通过注入的数量袋（FishingLoot / 任何带
## `try_add(id, n) -> 溢出数` 的节点）结算，掉落物自己只记「还没被装走的数量」，
## 所以部分装入、反复靠近、背包满之后再来都有明确结果，不会复制也不会吞掉。
##
## --- 用法（最小示例） ---
##     # 1) 直接生成一件掉落，靠近自动拾取
##     var drop := LootDrop.spawn(arena, arena.loot, "item_scale", 1, spot, arena.player)
##     drop.set_notice_target(hud)          # 可选：背包满时给一行非阻塞提示
##     # 2) 或者一次完成「入包 + 溢出落地」
##     arena.loot.grant("fish_ring_scale", 3, bobber, arena, arena.player, hud)
##
## 接口：spawn / setup / try_collect / set_amount / amount / item_id /
##       collected(item_id, amount) / pickup_blocked(item_id, remaining, reason)
##
## 旧钓鱼拾取（FishingPickup）继承本类并把 auto_collect 关掉，由 combat_arena
## 每帧调用 player_inside + set_amount，行为与改动前一致。

const ORB_VISUAL: Script = preload("res://scripts/mvp/loot_orb_visual.gd")

const LAYER: int = 8
const MASK: int = 4
const DEFAULT_PICK_RADIUS: float = 2.2

signal collected(item_id: String, amount: int)
signal pickup_blocked(item_id: String, remaining: int, reason: String)

var item_id: String = ""
var amount: int = 0
## 数量袋：需要有 try_add(item_id, amount) -> int（返回溢出数量）。
var bag: Node = null
## 玩家引用可空：为空时用碰撞体重叠判断（玩家在 layer 4）。
var player: Node3D = null
var pick_radius: float = DEFAULT_PICK_RADIUS
## true = 靠近自动拾取（新整合方式）；false = 由外部每帧驱动（旧 arena 路径）。
var auto_collect: bool = true
var manual_collect: bool = false
var paused: bool = false
var in_flight: bool = false
var _flight_from: Vector3
var _flight_to: Vector3
var _flight_time: float = 0.0
var _flight_length: float = 0.32
var _flight_arc: float = 0.22
var _focused: bool = false
signal landed

## 生成后先在地上躺一会儿再允许自动拾取，避免「刚掉就被吸走」看不清。
var pickup_delay: float = 0.5
## 背包满时的重试间隔；期间玩家不用反复点，站在原地也能等到容量。
var retry_seconds: float = 1.5
var notice_target: Node = null

var label: Label3D
var _body: Node3D
var _age: float = 0.0
var _bob_time: float = 0.0
var _retry_left: float = 0.0
var _collecting: bool = false
var _retired: bool = false


## 生成一件掉落并挂到 parent 下。parent 通常传当前场景或 arena。
static func spawn(parent: Node, bag_node: Node, drop_item: String, drop_amount: int, at: Vector3, owner_player: Node3D = null) -> Node3D:
	if parent == null or drop_amount <= 0 or drop_item.is_empty():
		return null
	var drop: Node3D = new() as Node3D
	drop.name = "LootDrop"
	parent.add_child(drop)
	drop.global_position = Vector3(at.x, 0.06, at.z)
	drop.call("setup", drop_item, drop_amount)
	drop.set("bag", bag_node)
	drop.set("player", owner_player)
	return drop


func setup(loot_item: String, loot_amount: int) -> void:
	item_id = loot_item
	amount = maxi(loot_amount, 0)
	collision_layer = LAYER
	collision_mask = MASK
	monitoring = true
	if get_child_count() == 0:
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = pick_radius
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = "PickupShape"
		collision.shape = shape
		add_child(collision)
	if not is_node_ready():
		return
	if _body == null:
		_build_visual()
	_refresh_label()


func set_notice_target(node: Node) -> void:
	notice_target = node


func notify(message: String) -> void:
	if notice_target != null and notice_target.has_method("push_message"):
		notice_target.call("push_message", message)


func is_empty() -> bool:
	return amount <= 0


func _ready() -> void:
	_build_visual()
	_refresh_label()


func _process(delta: float) -> void:
	if amount <= 0:
		_retire()
		return
	if paused:
		return
	_age += delta
	if in_flight:
		_flight_time += delta
		var t: float = clampf(_flight_time / _flight_length, 0.0, 1.0)
		global_position = _flight_from.lerp(_flight_to, t) + Vector3.UP * sin(t * PI) * _flight_arc
		if t >= 1.0:
			in_flight = false
			_age = 0.0
			_refresh_label()
			landed.emit()
		return
	_bob_time += delta
	if _body != null:
		_body.position.y = 0.22 + sin(_bob_time * 2.4) * 0.06
		_body.rotation.y += delta * 1.2
	_retry_left = maxf(0.0, _retry_left - delta)
	if not auto_collect or _retired or _age < pickup_delay:
		return
	if _retry_left > 0.0:
		return
	if player_inside(_resolve_player()):
		try_collect()


## 唯一结算入口：全部数量都经过 bag.try_add，重复调用或同一帧多次进入都只会
## 结算一次；返回实际装入的数量（0 = 一个都没装进去）。
func try_collect() -> int:
	if _collecting or _retired or paused or in_flight or (manual_collect and _age < pickup_delay):
		return 0
	if amount <= 0:
		_retire()
		return 0
	if bag == null or not bag.has_method("try_add"):
		return 0
	_collecting = true
	var overflow: int = int(bag.call("try_add", item_id, amount))
	var accepted: int = amount - overflow
	if accepted > 0:
		amount = overflow
		_refresh_label()
		collected.emit(item_id, accepted)
		if amount <= 0:
			_collecting = false
			_retire()
			return accepted
		_collecting = false
		return accepted
	# 背包满 / 堆叠满：原地保留，等容量或下次靠近。
	_retry_left = retry_seconds
	pickup_blocked.emit(item_id, amount, "full")
	notify("背包已满，%s ×%d 留在地上" % [item_name(), amount])
	_collecting = false
	return 0


func set_amount(value: int) -> void:
	amount = maxi(value, 0)
	_refresh_label()
	if amount <= 0:
		_retire()


func player_inside(who: Node3D) -> bool:
	# 已经结算完/正在销毁的掉落不能再查询物理（monitoring 已关会报错），
	# 外部每帧驱动的旧路径因此也不会重复拾取。
	if who == null or _retired or is_queued_for_deletion() or not is_inside_tree():
		return false
	if monitoring:
		for body: Node3D in get_overlapping_bodies():
			if body == who:
				return true
	return global_position.distance_to(who.global_position) <= pick_radius


## 名称从 /root/GameData 取，而不是直接写 GameData：本组件会被 preload，
## 在无编辑器导入的 headless/早期解析阶段里 autoload 名字可能还没注册。
func item_name() -> String:
	if item_id.is_empty():
		return ""
	var data: Node = get_node_or_null("/root/GameData")
	if data == null:
		return item_id
	var fish: Dictionary = data.call("get_fish", item_id) as Dictionary
	if not fish.is_empty():
		return str(fish.get("name", item_id))
	return str(data.call("get_item_name", item_id))


func _resolve_player() -> Node3D:
	if is_instance_valid(player):
		return player
	for body: Node3D in get_overlapping_bodies():
		if body is CharacterBody3D and body.collision_layer & MASK:
			player = body
			return body
	return null


func _retire() -> void:
	if _retired:
		return
	_retired = true
	monitoring = false
	set_process(false)
	queue_free()


func _refresh_label() -> void:
	if label == null:
		return
	label.text = "%s ×%d" % [item_name(), amount]
	label.modulate = Color("eefaff") if _focused else Color("a9d8fa")
	label.visible = amount > 0 and not in_flight and (not manual_collect or _focused)



func _build_visual() -> void:
	if _body != null:
		return
	_body = Node3D.new()
	_body.name = "PickupVisual"
	_body.position.y = 0.22
	add_child(_body)
	var orb: Node3D = ORB_VISUAL.build()
	_body.add_child(orb)
	label = Label3D.new()
	label.name = "PickupLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 20
	label.pixel_size = 0.0035
	label.outline_size = 6
	label.modulate = Color("f5ead1")
	label.position.y = 0.62
	add_child(label)


func launch_from(from: Vector3, seconds: float = 0.32, arc: float = 0.22) -> void:
	_flight_to = global_position
	_flight_from = from - Vector3.UP * 0.22
	_flight_length = maxf(0.05, seconds)
	_flight_arc = arc
	_flight_time = 0.0
	in_flight = true
	global_position = _flight_from
	_refresh_label()


func set_focused(value: bool) -> void:
	_focused = value
	_refresh_label()
