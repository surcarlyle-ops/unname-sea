extends Node
class_name CombatSystem
## 简化回合制战斗系统
##
## 设计参考 Slay the Spire 的轻量结构：每回合三选一（攻击/防御/特技），
## 3-5 回合内结束，不打断钓鱼节奏。
##
## 用法：
##     var combat := CombatSystem.new()
##     add_child(combat)
##     combat.combat_ended.connect(_on_combat_ended)
##     combat.start(monster_dict)

signal combat_started(monster: Dictionary)
signal turn_resolved(log_line: String)
signal combat_ended(victory: bool, drops: Array)

enum Action { ATTACK, DEFEND, SKILL }

const SKILL_COOLDOWN := 2      ## 特技冷却回合数
const MAX_TURNS := 8           ## 保底回合数（防止无限僵持）

# 玩家属性（MVP 固定值，后续可接入成长系统）
var player_max_hp: int = 40
var player_hp: int = 40
var player_attack: int = 8
var player_defense: int = 2

# 怪物属性
var monster: Dictionary = {}
var monster_hp: int = 0
var monster_max_hp: int = 0
var monster_attack: int = 0
var monster_defense: int = 0

# 战斗状态
var active: bool = false
var turn: int = 0
var _skill_cd: int = 0
var _log: Array[String] = []


## 开始一场战斗
func start(monster_data: Dictionary) -> void:
	monster = monster_data
	monster_max_hp = int(monster_data.get("hp", 30))
	monster_hp = monster_max_hp
	monster_attack = int(monster_data.get("attack", 5))
	monster_defense = int(monster_data.get("defense", 1))

	player_hp = player_max_hp
	turn = 0
	_skill_cd = 0
	_log.clear()
	active = true

	combat_started.emit(monster)
	_append_log("遭遇 %s！" % String(monster.get("name", "异兽")))


## 玩家选择一个行动
func take_action(action: Action) -> void:
	if not active:
		return

	turn += 1
	match action:
		Action.ATTACK:
			var dmg := _calc_damage(player_attack, monster_defense)
			monster_hp = maxi(0, monster_hp - dmg)
			_append_log("你发动攻击，造成 %d 点伤害。" % dmg)
		Action.DEFEND:
			var heal := int(ceil(float(player_max_hp) * 0.15))
			player_hp = mini(player_max_hp, player_hp + heal)
			_append_log("你采取防御姿态，恢复 %d 点生命。" % heal)
		Action.SKILL:
			if _skill_cd > 0:
				_append_log("特技冷却中（还需 %d 回合）。" % _skill_cd)
				turn -= 1  # 无效行动，不计回合
				return
			var dmg := _calc_damage(player_attack * 2, monster_defense)
			monster_hp = maxi(0, monster_hp - dmg)
			_skill_cd = SKILL_COOLDOWN
			_append_log("你施展特技，造成 %d 点伤害！" % dmg)

	# 检查怪物是否被击败
	if monster_hp <= 0:
		_end(true)
		return

	# 怪物回合
	_monster_turn()
	if player_hp <= 0:
		_end(false)
		return

	# 保底：超过最大回合数判定为撤退
	if turn >= MAX_TURNS:
		_append_log("战斗拖得太久，你选择了撤退。")
		_end(false)
		return

	if _skill_cd > 0:
		_skill_cd -= 1


func _monster_turn() -> void:
	var dmg := _calc_damage(monster_attack, player_defense)
	player_hp = maxi(0, player_hp - dmg)
	_append_log("%s 反击，造成 %d 点伤害。" % [String(monster.get("name", "异兽")), dmg])


func _calc_damage(atk: int, def: int) -> int:
	# 基础伤害 = 攻击 - 防御/2，最低 1
	return maxi(1, atk - int(floor(float(def) * 0.5)))


func _append_log(line: String) -> void:
	_log.append(line)
	turn_resolved.emit(line)


func _end(victory: bool) -> void:
	active = false
	var drops: Array = []
	if victory:
		drops = _roll_drops()
		for d in drops:
			_append_log("获得：%s" % GameData.get_item_name(String(d.get("item", ""))))
	combat_ended.emit(victory, drops)


## 按掉落表抽取战利品
func _roll_drops() -> Array:
	var result: Array = []
	var table: Array = monster.get("drops", [])
	for entry in table:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var rate := float(d.get("rate", 0.0))
		if randf() < rate:
			result.append(d)
	return result


## 给 UI 用的战斗状态摘要
func get_status() -> Dictionary:
	return {
		"active": active,
		"turn": turn,
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"monster_name": String(monster.get("name", "")),
		"monster_hp": monster_hp,
		"monster_max_hp": monster_max_hp,
		"skill_cd": _skill_cd,
		"log": _log.duplicate(),
	}
