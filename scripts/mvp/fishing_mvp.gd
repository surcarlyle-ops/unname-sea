extends Node
class_name FishingMVP
## Fishing MVP state machine (CodeBuddy 2026-10-28).
##
## Logic only: no meshes, no input polling, no inventory writes. The arena owns
## input, rewards and encounters; Codex's hand/viewmodel layer reads the public
## getters below.
##
## Bite timing follows Terraria's official wiki instead of the old 15–45 s wait:
##   Catch frequency — a hidden counter grows per tick, a bite is checked once it
##   passes 660 with chance (75 + FP) / 2, then the counter resets either way.
##   Reel in time  — window = FP + rand(91..240) ticks, decaying 1–4 per tick.
## At FP 66 that averages ~3.10 s per bite and ~1.55 s per window; nothing is a
## fixed countdown.
##
## Interface for Codex (first_person_hands.gd):
##   read:  state, cast_progress(), reveal_progress(), bobber_position,
##          rod_tip_position, bite_window_left(), encounter_active, rod_equipped
##   events: cast_started(bobber_position), bite_started(), bite_missed(),
##          cancelled(reason), result_revealed(outcome, item_id, monster_id),
##          encounter_requested(monster_id, reward_item_id, reward_count),
##          encounter_released(), encounter_refused(message),
##          auto_reeled(distance), notice_requested(message)

enum State { IDLE, CASTING, WAITING, BITING, REVEAL }

signal reel_started(is_fish: bool)
signal cast_started(bobber_position: Vector3)
signal bite_started()
signal bite_missed()
signal cancelled(reason: String)
signal result_revealed(outcome: String, item_id: String, monster_id: String)
signal encounter_requested(monster_id: String, reward_item_id: String, reward_count: int)
signal encounter_released()
signal encounter_refused(message: String)
signal auto_reeled(distance: float)
signal notice_requested(message: String)

## Dev overrides set by the arena (F7 / F8). Cleared as soon as one is consumed by
## a valid catch, or when the cast that would use it is cancelled.
enum Force { NONE, FISH, ENCOUNTER }

var config: Dictionary = {}
var state: State = State.IDLE
var bobber_position: Vector3 = Vector3.ZERO
var rod_tip_position: Vector3 = Vector3.ZERO
var encounter_active: bool = false
var rod_equipped: bool = true
## Where the rod tip sat when the cast began; the line is drawn tip → bobber.
var cast_tip_origin: Vector3 = Vector3.ZERO
var force: Force = Force.NONE
## Dev log of every resolved catch, used by the simulation test (newest last).
var history: Array[Dictionary] = []

var _state_time: float = 0.0
var _counter: int = 0
var _window_left: float = 0.0
var _window_total: float = 0.0
var _window_initial: float = 0.0
var _outcome: String = ""
var _item_id: String = ""
var _monster_id: String = ""
var _reward_item: String = ""
var _reward_count: int = 0
var _paused: bool = false
## True once the reveal delay has elapsed and the result signals have fired.
var _revealed: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Injects a deterministic generator for tests. Production keeps the random one.
func seed_rng(value: int) -> void:
	_rng.seed = value


func ticks_per_second() -> float:
	return float(config.get("bobber_ticks_per_second", 60.0))


func fishing_power() -> float:
	return float(config.get("fishing_power", 66.0))


func bite_chance() -> float:
	return clampf((float(config.get("bite_success_base", 75.0)) + fishing_power()) / float(config.get("bite_success_divisor", 2.0)) * 0.01, 0.0, 1.0)


## Expected seconds per bite, including failed-roll retries.
## Wiki simplified form: 11 / (2.5 + 23/600 × FP) seconds per check.
func expected_bite_seconds() -> float:
	var power: float = fishing_power()
	var growth: float = 2.5 + power * float(config.get("counter_growth_power_rate", 0.038333))
	var per_check: float = float(config.get("catch_counter", 660)) / growth / ticks_per_second()
	return per_check / maxf(bite_chance(), 0.001)


## Mean reel window in seconds: window = FP + rand(91..240) ticks, losing
## 1–4 ticks per tick, so the mean is window ticks over the mean decay.
func expected_window_seconds() -> float:
	var ticks: float = (float(config.get("reel_window_ticks_min", 91)) + float(config.get("reel_window_ticks_max", 240))) * 0.5
	var decay: float = (float(config.get("reel_decay_min_ticks", 1)) + float(config.get("reel_decay_max_ticks", 4))) * 0.5
	return (ticks + fishing_power()) / decay / ticks_per_second()


func is_busy() -> bool:
	return state != State.IDLE


func bobber_in_water() -> bool:
	return state == State.WAITING or state == State.BITING


func cast_progress() -> float:
	if state != State.CASTING:
		return -1.0
	return clampf(_state_time / maxf(float(config.get("cast_seconds", 0.4)), 0.001), 0.0, 1.0)


func reveal_progress() -> float:
	if state != State.REVEAL:
		return -1.0
	return clampf(_state_time / maxf(float(config.get("reveal_seconds", 0.35)), 0.001), 0.0, 1.0)


func bite_window_left() -> float:
	return _window_left


func bite_progress() -> float:
	return clampf(1.0 - _window_left / maxf(_window_initial, 0.001), 0.0, 1.0)


func is_paused() -> bool:
	return _paused


func counter() -> int:
	return _counter


## Frozen while the game is paused or the player controls are suspended (menu,
## window focus loss). The arena calls this every frame.
func set_paused(paused: bool) -> void:
	_paused = paused


func force_fish() -> void:
	force = Force.FISH
	notice_requested.emit("开发测试：下一次有效收获为鱼")


func force_encounter() -> void:
	force = Force.ENCOUNTER
	notice_requested.emit("开发测试：下一次有效收获为异兽")


## Starts a cast. tip is where the rod tip is now, bobber where the hook lands.
func begin_cast(tip: Vector3, bobber: Vector3) -> bool:
	if state != State.IDLE:
		return false
	cast_tip_origin = tip
	rod_tip_position = tip
	bobber_position = bobber
	_counter = 0
	_power_growth = 0.0
	_bite_decay_fraction = 0.0
	_outcome = ""
	_item_id = ""
	_monster_id = ""
	_reward_item = ""
	_reward_count = 0
	_revealed = false
	_state_time = 0.0
	state = State.CASTING
	cast_started.emit(bobber)
	return true


## Left click while waiting: a normal cancel, no reward and no extra penalty.
func cancel_waiting() -> bool:
	if state != State.WAITING and state != State.BITING:
		return false
	state = State.IDLE
	_window_left = 0.0
	cancelled.emit("early")
	notice_requested.emit("已收竿")
	return true


## Any cancel that must clean up an unfinished cast (weapon switch, grapple,
## retry, death, trial switch). Silent: the caller explains why.
func cancel_silent(reason: String) -> bool:
	if state == State.IDLE:
		return false
	state = State.IDLE
	_window_left = 0.0
	cancelled.emit(reason)
	return true


## Left click while reeling in a bite: resolves the pending outcome.
func reel_bite() -> bool:
	if state != State.BITING:
		return false
	_window_left = 0.0
	_state_time = 0.0
	_revealed = false
	state = State.REVEAL
	reel_started.emit(_outcome == "fish")
	return true


## Fired once the ~0.35 s reveal delay has passed, so presentation can play the
## lifting animation before the reward text and the encounter appear.
func _emit_reveal() -> void:
	var outcome: String = _outcome
	var item_id: String = _item_id
	var monster_id: String = _monster_id
	var reward_item: String = _reward_item
	var reward_count: int = _reward_count
	_revealed = true
	# A valid harvest consumed the F7/F8 command.
	force = Force.NONE
	history.append({"outcome": outcome, "item_id": item_id, "monster_id": monster_id})
	if history.size() > 400:
		history.pop_front()
	result_revealed.emit(outcome, item_id, monster_id)
	if outcome == "monster":
		encounter_requested.emit(monster_id, reward_item, reward_count)


## The arena calls this once the encounter can actually start (after the reveal).
func keep_encounter() -> void:
	force = Force.NONE


## The arena refuses a monster spawn (already occupied / no legal spot): fall back
## to an ordinary catch of the first fish so the click is never silently wasted.
func refuse_encounter(message: String) -> void:
	encounter_refused.emit(message)
	if state == State.REVEAL:
		_outcome = "fish"
		_item_id = str(config.get("fish_pale_id", "fish_pale_minnow"))
		_monster_id = ""
	note_message(message)


var _forced_monster_chosen: bool = false


func _process(delta: float) -> void:
	if _paused or delta <= 0.0:
		return
	_state_time += delta
	match state:
		State.CASTING:
			if _state_time >= float(config.get("cast_seconds", 0.4)):
				_state_time = 0.0
				state = State.WAITING
		State.WAITING:
			_advance_counter(delta)
		State.BITING:
			_advance_bite_window(delta)
		State.REVEAL:
			var reveal_seconds: float = float(config.get("reveal_seconds", 0.35))
			if not _revealed and _state_time >= reveal_seconds:
				_emit_reveal()
			if _state_time >= reveal_seconds + float(config.get("reveal_hold_seconds", 3.0)):
				state = State.IDLE


var _bite_decay_fraction: float = 0.0


## Terraria "catch frequency": per tick the counter gains 1–2, plus a 1/60
## chance of 60, plus fishing_power × 23/600 (wiki simplified form, carried as a
## fraction). At or past 660 one bite check runs with (75 + FP)/2 chance; the
## counter resets either way, so a failed check only means another wait.
func _advance_counter(delta: float) -> void:
	var tick_rate: float = ticks_per_second()
	var accumulated: float = delta * tick_rate + _fractional_tick
	var ticks: int = int(floor(accumulated))
	_fractional_tick = accumulated - float(ticks)
	var threshold: int = int(config.get("catch_counter", 660))
	var growth_rate: float = fishing_power() * float(config.get("counter_growth_power_rate", 0.038333))
	for _i: int in range(ticks):
		_counter += _rng.randi_range(int(config.get("counter_growth_base_min", 1)), int(config.get("counter_growth_base_max", 2)))
		if _rng.randf() < float(config.get("counter_growth_bonus_chance_per_tick", 1.0 / 60.0)):
			_counter += int(config.get("counter_growth_bonus", 60))
		_power_growth += growth_rate
		var whole: int = int(floor(_power_growth))
		if whole > 0:
			_counter += whole
			_power_growth -= float(whole)
		if _counter >= threshold:
			_counter = 0
			if _rng.randf() < bite_chance():
				_begin_bite()
				return


var _power_growth: float = 0.0


## Reel window loss: 1–4 ticks per tick, chosen every tick (wiki "decaying by
## 1–4 ticks per tick"), so short windows feel urgent without a fixed timer.
func _advance_bite_window(delta: float) -> void:
	var tick_rate: float = ticks_per_second()
	var accumulated: float = delta * tick_rate + _bite_decay_fraction
	var ticks: int = int(floor(accumulated))
	_bite_decay_fraction = accumulated - float(ticks)
	var decay_min: int = int(config.get("reel_decay_min_ticks", 1))
	var decay_max: int = int(config.get("reel_decay_max_ticks", 4))
	for _i: int in range(ticks):
		_window_left -= float(_rng.randi_range(decay_min, decay_max)) / tick_rate
		if _window_left <= 0.0:
			_window_left = 0.0
			_miss()
			return


var _fractional_tick: float = 0.0


func _begin_bite() -> void:
	var min_ticks: int = int(config.get("reel_window_ticks_min", 91))
	var max_ticks: int = int(config.get("reel_window_ticks_max", 240))
	var decay_min: int = int(config.get("reel_decay_min_ticks", 1))
	var decay_max: int = int(config.get("reel_decay_max_ticks", 4))
	var window_ticks: float = float(_rng.randi_range(min_ticks, max_ticks)) + fishing_power()
	var decay_mean: float = (float(decay_min) + float(decay_max)) * 0.5
	_window_total = window_ticks / decay_mean / ticks_per_second()
	_window_left = window_ticks / ticks_per_second()
	_window_initial = _window_left
	_roll_outcome()
	_state_time = 0.0
	state = State.BITING
	bite_started.emit()


## Outcome weights: pale minnow 40 / ring scale 40 / monster 20, then the dev
## overrides (consumed only when a bite actually rolls an outcome).
func _roll_outcome() -> void:
	var roll: float = _rng.randf() * float(
		int(config.get("outcome_fish_pale", 40)) + int(config.get("outcome_fish_ring", 40)) + int(config.get("outcome_encounter", 20)))
	var pale_weight: float = float(config.get("outcome_fish_pale", 40))
	var ring_weight: float = float(config.get("outcome_fish_ring", 40))
	_outcome = "fish"
	_monster_id = ""
	_reward_item = ""
	_reward_count = 0
	if roll < pale_weight:
		_item_id = str(config.get("fish_pale_id", "fish_pale_minnow"))
	elif roll < pale_weight + ring_weight:
		_item_id = str(config.get("fish_ring_id", "fish_ring_scale"))
	else:
		_outcome = "monster"
		_item_id = ""
		_monster_id = str(config.get("encounter_monster_id", "mon_phosphor_scale"))
		_reward_item = str(config.get("encounter_reward_item", "item_scale"))
		_reward_count = int(config.get("encounter_reward_count", 1))
	# The dev command stays armed until a valid harvest is actually resolved, so
	# cancelling after a bite never burns F7/F8 for nothing.
	if force == Force.FISH:
		_outcome = "fish"
		_item_id = str(config.get("fish_pale_id", "fish_pale_minnow"))
		_monster_id = ""
		_reward_item = ""
		_reward_count = 0
	elif force == Force.ENCOUNTER:
		_outcome = "monster"
		_item_id = ""
		_monster_id = str(config.get("encounter_monster_id", "mon_phosphor_scale"))
		_reward_item = str(config.get("encounter_reward_item", "item_scale"))
		_reward_count = int(config.get("encounter_reward_count", 1))


## Missed bite: the bobber stays in the water and the counter starts over, so the
## player keeps waiting instead of losing the cast. No extra escape roll.
func _miss() -> void:
	_counter = 0
	_power_growth = 0.0
	_bite_decay_fraction = 0.0
	_window_left = 0.0
	_state_time = 0.0
	state = State.WAITING
	bite_missed.emit()
	notice_requested.emit("错过了咬钩，鱼漂仍在水中")


## Distance guard: the arena calls this every frame while the bobber is in water.
func check_distance(player_position: Vector3) -> void:
	if not bobber_in_water():
		return
	var distance: float = Vector2(player_position.x - bobber_position.x, player_position.z - bobber_position.z).length()
	var limit: float = float(config.get("auto_reel_distance", 16.0))
	if distance <= limit:
		return
	state = State.IDLE
	_window_left = 0.0
	auto_reeled.emit(distance)
	notice_requested.emit("离鱼漂太远，自动收竿")


## Clears an unresolved state after death, retry or a trial switch. Returns true
## when something was actually pending, so a retry never double-rewards.
func reset_encounter() -> bool:
	var was_active: bool = encounter_active
	encounter_active = false
	return was_active


func note_message(message: String) -> void:
	notice_requested.emit(message)


## Resolves a cast from a camera ray. The hook must land on the configured pond
## surface, 2–12 m away horizontally and with no solid geometry in the way.
## Pure geometry + one occlusion ray: no extra collision layer, so the pond never
## becomes a grapple anchor or blocks players and enemies.
func resolve_cast(eye: Vector3, forward: Vector3) -> Dictionary:
	var min_range: float = float(config.get("cast_min_range", 2.0))
	var max_range: float = float(config.get("cast_max_range", 12.0))
	if not config.has("arena"):
		return {"reason": "钓鱼场地未配置"}
	var area: Dictionary = config.arena as Dictionary
	var minimum: Array = area.get("pond_min", [])
	var maximum: Array = area.get("pond_max", [])
	if minimum.size() < 2 or maximum.size() < 2:
		return {"reason": "钓鱼场地未配置"}
	var water_level: float = float(area.get("water_level", 0.06))
	if forward.y > -0.02:
		return {"reason": "请向下瞄准水池"}
	var travel: float = (water_level - eye.y) / forward.y
	if travel <= 0.0:
		return {"reason": "请向下瞄准水池"}
	var point: Vector3 = eye + forward * travel
	var horizontal: float = Vector2(point.x - eye.x, point.z - eye.z).length()
	if horizontal < min_range:
		return {"reason": "落点太近，需要 %d 米以上" % int(min_range)}
	if horizontal > max_range:
		return {"reason": "落点太远，最多 %d 米" % int(max_range)}
	var min_x: float = float(minimum[0])
	var min_z: float = float(minimum[1])
	var max_x: float = float(maximum[0])
	var max_z: float = float(maximum[1])
	if point.x < min_x or point.x > max_x or point.z < min_z or point.z > max_z:
		return {"reason": "落点不在水池里，瞄准标记的水面"}
	var world: World3D = get_viewport().world_3d
	var blocked: Dictionary = world.direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(eye, point, 1))
	if not blocked.is_empty():
		return {"reason": "前方有遮挡"}
	return {"point": Vector3(point.x, water_level, point.z)}
