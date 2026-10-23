extends Node3D
## A quiet side lane for testing a complete movement chain with ordinary collision.

var arena: Node3D
var progress: int = 0
var hints: Array[String] = [
	"W 向前默认奔跑，Ctrl 滑铲穿梁；按住 Shift 走路",
	"继续前进，直接走过小台阶",
	"接近矮墙，向前 + 空格翻上去",
	"接近高台，向前 + 空格攀上去",
	"瞄准高横梁，右键钩爪换位；F 可返回近战",
	"路线完成 · 可继续自由移动，R 重跑 / F 清怪"
]


func _ready() -> void:
	arena._box("CourseTunnelRoof", Vector3(-19, 1.4, 9), Vector3(3.8, 0.35, 2.8), Color("b8b99f"))
	for x: float in [-21.0, -17.0]:
		arena._box("CourseTunnelLeg", Vector3(x, 0.75, 9), Vector3(0.25, 1.5, 2.8), Color("9ca690"))
	arena._box("CourseSmallStep", Vector3(-19, 0.12, 4), Vector3(3.4, 0.24, 1.2), Color("c7bf9f"))
	arena._box("CourseLowVault", Vector3(-19, 0.425, -1), Vector3(3.4, 0.85, 0.85), Color("b6b49b"))
	arena._box("CourseHighLedge", Vector3(-19, 0.725, -7), Vector3(3.4, 1.45, 2.8), Color("c7bf9f"))
	for z: float in [15.0, 12.0, 6.5, 2.0, -3.0]:
		arena._box("CourseStripe", Vector3(-19, 0.013, z), Vector3(0.35, 0.025, 0.85), Color("d9bb78"), false)
	arena._sign("01  冲刺 / 滑铲", Vector3(-21.2, 2.3, 10.5), 22)
	arena._sign("02  小台阶", Vector3(-21.2, 1.4, 3.9), 22)
	arena._sign("03  空格翻越", Vector3(-21.2, 2.2, -1), 22)
	arena._sign("04  攀上高台", Vector3(-21.2, 3.1, -7), 22)
	arena._sign("V 切换：灵动 / 轻型参考", Vector3(-19, 2.8, 13.7), 20)


func reset() -> void:
	progress = 0


func _process(_delta: float) -> void:
	if arena.mode != 2 or not arena.player.controls_active:
		return
	var player: CharacterBody3D = arena.player
	var point: Vector3 = player.global_position
	if progress == 0 and point.z < 7.0 and player.motion.slide_count > 0:
		progress = 1
	elif progress == 1 and point.z < 2.5 and player.motion.step_count > 0:
		progress = 2
	elif progress == 2 and point.z < -1.5 and player.motion.mantle_count > 0:
		progress = 3
	elif progress == 3 and point.z < -6.0 and point.y > 1.3 and player.motion.mantle_count > 1:
		progress = 4
	elif progress == 4 and (player.grapple.is_attached() or (point.y > 3.0 and point.x > -16.0)):
		progress = 5
