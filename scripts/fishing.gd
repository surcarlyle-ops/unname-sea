extends Node
class_name FishingSystem
## 钓鱼核心循环系统
##
## 这是《未名之海》最核心的模块。完整的钓鱼状态机：
##     IDLE -> CASTING -> WAITING -> BITING -> REELING -> RESULT -> IDLE
##
## 设计参考泰拉瑞亚：垃圾竿等待久且易脱钩，好竿快且稳。
##
## 用法：
##     var fishing := FishingSystem.new()
##     add_child(fishing)
##     fishing.setup("shallow", Rod.new("rod_branch"), Bait.new("bait_none"))
##     fishing.state_changed.connect(_on_fishing_state_changed)
##     fishing.cast()

signal state_changed(new_state: int)
signal cast_started()
signal bite_started(window: float)
signal escaped(reason: String)
signal caught(result: Dictionary)
signal monster_encountered(monster: Dictionary)

enum State {
	IDLE,       ## 待机
	CASTING,    ## 抛竿中
	WAITING,    ## 等待咬钩
	BITING,     ## 咬钩（限时按键窗口）
	REELING,    ## 收线中
	RESULT,     ## 结算展示
}

# 渔获类型概率（与设计文档一致）
const OUTCOME_WEIGHTS := {
	"common": 50,    ## 普通水产
	"junk": 25,      ## 垃圾
	"quest": 15,     ## 任务物品
	"monster": 5,    ## 异兽
	"strange": 3,    ## 奇异物质
	"story": 2,      ## 剧情道具
}

const CAST_DURATION := 0.6      ## 抛竿动画时长
const RESULT_DURATION := 1.2    ## 结算展示时长

# 运行时状态
var state: State = State.IDLE
var area_id: String = "shallow"
var rod: Rod = Rod.new()
var bait: Bait = Bait.new()

# 计时器
var _timer: float = 0.0
var _bite_window: float = 0.0
var _reel_time: float = 0.0

# 本次抛竿的临时数据
var _pending_outcome: String = ""
var _pending_monster: Dictionary = {}


func _process(delta: float) -> void:
	match state:
		State.CASTING:
			_timer -= delta
			if _timer <= 0.0:
				_enter_waiting()
		State.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				_enter_biting()
		State.BITING:
			_bite_window -= delta
			if _bite_window <= 0.0:
				_handle_miss()
		State.REELING:
			_timer -= delta
			if _timer <= 0.0:
				_finish_reel()
		State.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				_set_state(State.IDLE)


## 配置本次钓鱼的环境
func setup(p_area_id: String, p_rod: Rod, p_bait: Bait) -> void:
	area_id = p_area_id
	rod = p_rod if p_rod != null else Rod.new()
	bait = p_bait if p_bait != null else Bait.new()


## 玩家按下抛竿键时调用
func cast() -> bool:
	if state != State.IDLE:
		return false
	_set_state(State.CASTING)
	_timer = CAST_DURATION
	cast_started.emit()
	return true


## 玩家在咬钩窗口内按键时调用
func reel() -> bool:
	if state != State.BITING:
		return false
	# 先判定脱钩
	if rod.roll_escape(bait.get_escape_modifier()):
		_handle_miss("脱钩")
		return false
	_set_state(State.REELING)
	_timer = rod.roll_reel_time()
	_reel_time = _timer
	return true


## 玩家在结算界面按键时调用（跳过展示）
func dismiss_result() -> void:
	if state == State.RESULT:
		_set_state(State.IDLE)


# ---------- 内部状态流转 ----------

func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func _enter_waiting() -> void:
	_set_state(State.WAITING)
	_timer = rod.roll_wait_time()


func _enter_biting() -> void:
	_set_state(State.BITING)
	# 咬钩窗口：竿越好，窗口越宽松（0.35 ~ 0.6 秒）
	_bite_window = lerpf(0.35, 0.60, clampf(float(rod.level - 1) / 5.0, 0.0, 1.0))
	bite_started.emit(_bite_window)


func _handle_miss(reason: String = "错过时机") -> void:
	_set_state(State.IDLE)
	escaped.emit(reason)


func _finish_reel() -> void:
	var result := _roll_outcome()
	_pending_outcome = String(result.get("outcome", "common"))

	# 如果是异兽，额外触发战斗信号
	if _pending_outcome == "monster" and not _pending_monster.is_empty():
		_set_state(State.RESULT)
		_timer = RESULT_DURATION
		monster_encountered.emit(_pending_monster)
		return

	_set_state(State.RESULT)
	_timer = RESULT_DURATION
	caught.emit(result)


## 抽取本次渔获结果
func _roll_outcome() -> Dictionary:
	var outcome := _weighted_outcome()
	_pending_monster = {}

	match outcome:
		"monster":
			var monsters := GameData.get_monsters_by_area(area_id)
			if monsters.is_empty():
				outcome = "common"  # 该水域无异兽，回退为普通水产
			else:
				var m: Dictionary = monsters[randi() % monsters.size()]
				_pending_monster = m
				return { "outcome": "monster", "monster": m }

		"common":
			var f := _pick_fish()
			if not f.is_empty():
				return { "outcome": "common", "fish": f }

		"junk":
			var j := _pick_item_by_category("junk")
			if not j.is_empty():
				return { "outcome": "junk", "item": j }

		"quest":
			var q := _pick_item_by_category("material")
			if not q.is_empty():
				return { "outcome": "quest", "item": q }

		"strange":
			var s := _pick_item_by_category("signature")
			if not s.is_empty():
				return { "outcome": "strange", "item": s }

		"story":
			var st := _pick_item_by_category("story")
			if not st.is_empty():
				return { "outcome": "story", "item": st }

	# 兜底：回退到普通水产，再回退到垃圾
	var fallback := _pick_fish()
	if not fallback.is_empty():
		return { "outcome": "common", "fish": fallback }
	var junk := _pick_item_by_category("junk")
	return { "outcome": "junk", "item": junk }


## 按权重抽取渔获类型（应用鱼饵修正）
func _weighted_outcome() -> String:
	var weights := OUTCOME_WEIGHTS.duplicate()
	# 鱼饵修正：异兽概率
	var mm := bait.get_monster_multiplier()
	if mm != 1.0:
		weights["monster"] = int(round(float(weights["monster"]) * mm))
	# 鱼饵修正：稀有度提升 → 减少垃圾、增加普通/任务
	var rm := bait.get_rare_multiplier()
	if rm > 1.0:
		weights["junk"] = int(round(float(weights["junk"]) / rm))
		weights["quest"] = int(round(float(weights["quest"]) * rm))

	var total := 0
	for w in weights.values():
		total += int(w)
	if total <= 0:
		return "common"

	var roll := randi() % total
	var acc := 0
	for key in weights.keys():
		acc += int(weights[key])
		if roll < acc:
			return String(key)
	return "common"


## 按稀有度权重从当前水域抽一条鱼
func _pick_fish() -> Dictionary:
	var pool := GameData.get_fish_by_area(area_id)
	if pool.is_empty():
		return {}

	# 稀有度权重（鱼饵的 rarity_bonus 会提升稀有鱼权重）
	var rare_bonus := 1.0 + rod.rarity_bonus + (bait.get_rare_multiplier() - 1.0)
	var rarity_weight := {
		"common": 60.0,
		"uncommon": 28.0 * rare_bonus,
		"rare": 10.0 * rare_bonus,
		"legendary": 2.0 * rare_bonus,
	}

	var total := 0.0
	var weighted: Array = []
	for f in pool:
		var r := String(f.get("rarity", "common"))
		var w := float(rarity_weight.get(r, 10.0))
		total += w
		weighted.append({ "fish": f, "weight": w })

	if total <= 0.0:
		return pool[randi() % pool.size()]

	var roll := randf() * total
	var acc := 0.0
	for entry in weighted:
		acc += float(entry["weight"])
		if roll < acc:
			return entry["fish"]
	return pool[pool.size() - 1]


## 从物品表中按类别抽一件
func _pick_item_by_category(category: String) -> Dictionary:
	var pool: Array = GameData.items.filter(func(it: Dictionary) -> bool:
		return String(it.get("category", "")) == category
	)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


## 当前是否处于可交互状态
func is_busy() -> bool:
	return state != State.IDLE


## 给 UI 用的状态名
func get_state_name() -> String:
	match state:
		State.IDLE: return "待机"
		State.CASTING: return "抛竿"
		State.WAITING: return "等待中"
		State.BITING: return "咬钩！"
		State.REELING: return "收线中"
		State.RESULT: return "收获"
	return "未知"
