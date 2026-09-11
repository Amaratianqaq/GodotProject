extends Node
## RunManager —— 单局（一次进关卡）生命周期管理（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 一局 = 「从大厅出发 → 打完森林 → 回大厅/结算」。
##    单局状态（种子、层数、击杀数、存活敌人）只存在于这里，不入档。
## 2. 地图生成必须使用 map_rng（由 run_seed 派生）以保证「同种子同地图」。
##    掉落随机使用 LootService.rng，也在开局时用 run_seed 派生，
##    方便复现「同一种子同一次掉落」。
## 3. 敌人节点不自己判断「房间是否清空」；统一调用
##    RunManager.notify_enemy_died()，由本单例驱动房间清空事件。
## 4. 结算入口只有 end_run(victory)。

signal run_state_changed()

## 地图生成随机（可复现）
var map_rng := RandomNumberGenerator.new()
## 战斗随机（暴击、散射抖动等）
var combat_rng := RandomNumberGenerator.new()

var run_active: bool = false
var run_seed: int = 0
var floor_index: int = 0

## 当前关卡节点（ForestLevel）
var level: Node = null

var enemies_spawned: int = 0
var enemies_killed: int = 0
var chests_spawned: int = 0
var gold_earned: int = 0

var _alive_enemies: Array = []
var _boss_alive: bool = false
var _start_time: int = 0

## --- 命中顿帧（hitstop）---
## 收到 EventBus.hitstop_requested 时把 Engine.time_scale 压到 HITSTOP_SCALE，
## 持续真实时间 duration 后恢复 1.0。战斗打击感的关键。
const HITSTOP_SCALE := 0.06
var _hitstop_left: float = 0.0


func _ready() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.chest_spawned.connect(_on_chest_spawned)
	EventBus.coin_picked_up.connect(_on_coin_picked_up)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.hitstop_requested.connect(_on_hitstop_requested)


# ---------------------------------------------------------------------------
# 命中顿帧
# ---------------------------------------------------------------------------

func _on_hitstop_requested(duration: float) -> void:
	if duration <= 0.0 or _hitstop_left > 0.0:
		# 已在顿帧中就不再叠加，避免连续命中把时间冻死
		return
	_hitstop_left = duration
	Engine.time_scale = HITSTOP_SCALE


func _process(delta: float) -> void:
	if _hitstop_left <= 0.0:
		return
	# delta 已被 time_scale 缩放，这里换算回真实时间
	var real_delta := delta / maxf(0.0001, Engine.time_scale)
	_hitstop_left -= real_delta
	if _hitstop_left <= 0.0:
		_hitstop_left = 0.0
		Engine.time_scale = 1.0


func reset_time_scale() -> void:
	_hitstop_left = 0.0
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# 开局
# ---------------------------------------------------------------------------

func start_run(seed_value: int = -1, floor: int = 0) -> void:
	reset_time_scale()
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	floor_index = floor
	map_rng.seed = run_seed
	combat_rng.seed = run_seed ^ 0x5EED
	if LootService:
		LootService.rng.seed = run_seed ^ 0xBEEF
	enemies_spawned = 0
	enemies_killed = 0
	chests_spawned = 0
	gold_earned = 0
	_alive_enemies.clear()
	_boss_alive = false
	run_active = true
	_start_time = Time.get_ticks_msec()
	GameState.begin_run(run_seed, floor)
	EventBus.run_started.emit(run_seed, floor)
	print("[RunManager] 开局 seed=%d floor=%d" % [run_seed, floor])
	run_state_changed.emit()


func end_run(victory: bool) -> void:
	reset_time_scale()
	if not run_active:
		return
	run_active = false
	GameState.register_run_end(floor_index)
	GameState.end_run()
	EventBus.run_ended.emit(victory)
	run_state_changed.emit()
	print("[RunManager] 结束 胜利=%s 击杀=%d 用时=%.1fs" % [
		victory, enemies_killed, run_elapsed()
	])


func next_floor() -> void:
	floor_index += 1
	run_active = true
	GameState.floor_index = floor_index
	EventBus.floor_cleared.emit(floor_index - 1)
	run_state_changed.emit()


func run_elapsed() -> float:
	if _start_time <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _start_time) / 1000.0


# ---------------------------------------------------------------------------
# 关卡注册
# ---------------------------------------------------------------------------

func register_level(l: Node) -> void:
	level = l


func unregister_level() -> void:
	level = null
	_alive_enemies.clear()
	_boss_alive = false


# ---------------------------------------------------------------------------
# 敌人跟踪
# ---------------------------------------------------------------------------

func notify_enemy_spawned(e: Node) -> void:
	if e == null or not is_instance_valid(e):
		return
	if not _alive_enemies.has(e):
		_alive_enemies.append(e)
	enemies_spawned += 1
	var data = e.get("data")
	if data is EnemyData and data.is_boss():
		_boss_alive = true
		if not e.tree_exited.is_connected(_on_enemy_tree_exited):
			e.tree_exited.connect(_on_enemy_tree_exited.bind(e))


func notify_enemy_removed(e: Node) -> void:
	_alive_enemies.erase(e)


func alive_enemy_count() -> int:
	_prune_dead()
	return _alive_enemies.size()


func alive_enemies() -> Array:
	_prune_dead()
	return _alive_enemies.duplicate()


func _prune_dead() -> void:
	var i := _alive_enemies.size() - 1
	while i >= 0:
		var e = _alive_enemies[i]
		if e == null or not is_instance_valid(e) or bool(e.get("is_dead")):
			_alive_enemies.remove_at(i)
		i -= 1


func _on_enemy_tree_exited(e: Node) -> void:
	notify_enemy_removed(e)


func _on_enemy_died(enemy: Node, tier: int, _position: Vector2) -> void:
	enemies_killed += 1
	notify_enemy_removed(enemy)
	GameState.register_kill()
	run_state_changed.emit()


func _on_chest_spawned(_chest: Node, _tier: int) -> void:
	chests_spawned += 1


func _on_coin_picked_up(amount: int, _position: Vector2) -> void:
	gold_earned += amount


func _on_boss_spawned(_boss: Node) -> void:
	_boss_alive = true
	run_state_changed.emit()


func _on_boss_defeated() -> void:
	_boss_alive = false
	run_state_changed.emit()


func is_boss_alive() -> bool:
	return _boss_alive


# ---------------------------------------------------------------------------
# 进度统计
# ---------------------------------------------------------------------------

func kill_ratio() -> float:
	if enemies_spawned <= 0:
		return 0.0
	return clampf(float(enemies_killed) / float(enemies_spawned), 0.0, 1.0)


func summary() -> Dictionary:
	return {
		"seed": run_seed,
		"floor": floor_index,
		"spawned": enemies_spawned,
		"killed": enemies_killed,
		"chests": chests_spawned,
		"gold": gold_earned,
		"time": run_elapsed(),
	}


func summary_text() -> String:
	var s := summary()
	return "种子 %d · 击杀 %d/%d · 宝箱 %d · 金币 %d · 用时 %s" % [
		s["seed"], s["killed"], s["spawned"], s["chests"], s["gold"],
		_format_time(s["time"])
	]


static func _format_time(t: float) -> String:
	var total := int(t)
	return "%02d:%02d" % [total / 60, total % 60]
