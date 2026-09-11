extends Node
## GameState —— 玩家档案与单局状态的唯一权威（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. **禁止** 在别处保存「玩家等级 / 金币 / 背包 / 当前角色」副本；
##    一律读写本单例。UI 通过 EventBus 信号被动刷新。
## 2. 背包是全局持久的（大厅 ↔ 关卡共享同一个 Inventory 实例）。
## 3. 属性计算入口只有 rebuild_stats()：
##      角色基础属性(CharacterData) + 全局技能树(SkillTreeService)
##    任何影响属性的新来源都必须挂到这里，不允许各自改 StatBlock。
## 4. 单局内状态（run_seed / floor_index / is_in_run）属于「一局」，
##    回大厅会被 RunManager 清理；存档里只保留 level/xp/gold/inventory。

# ---------------------------------------------------------------------------
# 存档字段
# ---------------------------------------------------------------------------

## 当前选中角色 id
var character_id: StringName = &"ranger"
## 全局等级
var player_level: int = 1
## 当前经验
var player_xp: int = 0
## 金币
var gold: int = 0
## 背包（持久）
var inventory: Inventory = null
## 已装备武器（两个槽位，持久：换场景/回大厅不丢武器）
var equipped_weapons: Array[StringName] = [&"", &""]
## 已解锁角色 id 集合
var unlocked_characters: Dictionary = {}
## 已解锁角色中，每个角色的最高通关层数（统计用）
var best_floor: int = 0
## 总击杀数（统计）
var total_kills: int = 0
## 累计游玩秒数
var play_time: float = 0.0

# ---------------------------------------------------------------------------
# 运行时（不入档）
# ---------------------------------------------------------------------------

## 当前角色基础数据
var character_data: CharacterData = null
## 当前最终属性块（基础 + 技能树）
var stats: StatBlock = null
## 当前关卡里的玩家节点（弱引用，回大厅清空）
var player: Node = null
## 是否处于关卡中
var is_in_run: bool = false
## 当前局的随机种子
var run_seed: int = 0
## 当前层数（0 = 森林第一层）
var floor_index: int = 0
## 本局已收集的战利品（结算界面用）
var run_loot_log: Array = []


func _ready() -> void:
	inventory = Inventory.new(Inventory.DEFAULT_SLOT_COUNT)
	# 默认解锁第一个角色，避免新档没有可用角色
	_ensure_default_character()
	rebuild_stats()
	EventBus.skill_tree_changed.connect(_on_skill_tree_changed)


# ---------------------------------------------------------------------------
# 角色
# ---------------------------------------------------------------------------

func _ensure_default_character() -> void:
	if character_data != null:
		return
	var all := ConfigDB.all_characters()
	if all.is_empty():
		push_error("[GameState] 没有任何角色数据，请先运行 tools/gen_data.gd 生成 res://data")
		return
	if not unlocked_characters.has(character_id):
		unlocked_characters[character_id] = true
	character_data = ConfigDB.get_character(character_id)
	if character_data == null:
		character_data = all[0]
		character_id = character_data.id


func select_character(id: StringName) -> bool:
	var cd := ConfigDB.get_character(id)
	if cd == null:
		return false
	if not is_character_unlocked(id):
		EventBus.toast.emit("角色「%s」尚未解锁" % cd.display_name, Color("#d94a4a"))
		return false
	character_id = id
	character_data = cd
	rebuild_stats()
	EventBus.character_selected.emit(id)
	EventBus.player_hp_changed.emit(get_max_hp(), get_max_hp())
	EventBus.player_armor_changed.emit(get_max_armor(), get_max_armor())
	EventBus.player_mp_changed.emit(get_max_mp(), get_max_mp())
	return true


func is_character_unlocked(id: StringName) -> bool:
	return bool(unlocked_characters.get(id, false))


func unlock_character(id: StringName) -> bool:
	var cd := ConfigDB.get_character(id)
	if cd == null or is_character_unlocked(id):
		return false
	if cd.unlock_cost > 0 and gold < cd.unlock_cost:
		return false
	if cd.unlock_cost > 0:
		add_gold(-cd.unlock_cost)
	unlocked_characters[id] = true
	return true


# ---------------------------------------------------------------------------
# 属性
# ---------------------------------------------------------------------------

## 重算最终属性。技能树变化 / 换角色 / 读档后必须调用。
func rebuild_stats() -> void:
	if character_data == null:
		_ensure_default_character()
	if character_data == null:
		return
	var block := character_data.build_stat_block()
	if SkillTreeService and SkillTreeService.is_ready():
		SkillTreeService.apply_to(block)
	block.recalculate()
	stats = block
	# 玩家节点存在时同步上限变化
	if player and is_instance_valid(player) and player.has_method("on_stats_rebuilt"):
		player.on_stats_rebuilt()


func _on_skill_tree_changed() -> void:
	rebuild_stats()


func get_stat(k: int) -> float:
	if stats == null:
		return 0.0
	return stats.get_stat(k)


func get_max_hp() -> float:
	return maxf(1.0, get_stat(GameEnums.StatKind.MAX_HP))


func get_max_armor() -> float:
	return maxf(0.0, get_stat(GameEnums.StatKind.MAX_ARMOR))


func get_max_mp() -> float:
	return maxf(0.0, get_stat(GameEnums.StatKind.MAX_MP))


func get_move_speed() -> float:
	return maxf(10.0, get_stat(GameEnums.StatKind.MOVE_SPEED))


func get_crit_chance() -> float:
	return clampf(get_stat(GameEnums.StatKind.CRIT_CHANCE), 0.0, 1.0)


func get_crit_mult() -> float:
	return maxf(1.0, get_stat(GameEnums.StatKind.CRIT_MULT))


func get_damage_mult() -> float:
	return maxf(0.01, get_stat(GameEnums.StatKind.DAMAGE_MULT))


func get_pickup_range() -> float:
	return maxf(8.0, get_stat(GameEnums.StatKind.PICKUP_RANGE))


# ---------------------------------------------------------------------------
# 金币
# ---------------------------------------------------------------------------

func add_gold(n: int) -> void:
	if n == 0:
		return
	gold = maxi(0, gold + n)
	EventBus.gold_changed.emit(gold)


func spend_gold(n: int) -> bool:
	if n <= 0:
		return true
	if gold < n:
		return false
	add_gold(-n)
	return true


# ---------------------------------------------------------------------------
# 经验与等级
# ---------------------------------------------------------------------------

static func xp_needed_for_level(level: int) -> int:
	## 指数成长：1 级 20，之后每级 ×1.32，取整到 5 的倍数
	var v := 20.0 * pow(1.32, float(maxi(0, level - 1)))
	return int(ceil(v / 5.0)) * 5


func add_xp(n: int) -> void:
	if n <= 0:
		return
	player_xp += n
	EventBus.xp_gained.emit(n)
	var leveled := false
	while player_xp >= xp_needed_for_level(player_level):
		player_xp -= xp_needed_for_level(player_level)
		player_level += 1
		leveled = true
		if SkillTreeService:
			SkillTreeService.add_points(1)
		EventBus.toast.emit("等级提升！Lv.%d（+1 技能点）" % player_level, Color("#ffd35c"))
	if leveled:
		rebuild_stats()
	EventBus.player_level_changed.emit(player_level, player_xp, xp_needed_for_level(player_level))


func get_xp_progress() -> float:
	var need := xp_needed_for_level(player_level)
	if need <= 0:
		return 0.0
	return clampf(float(player_xp) / float(need), 0.0, 1.0)


# ---------------------------------------------------------------------------
# 统计
# ---------------------------------------------------------------------------

func register_kill() -> void:
	total_kills += 1


func register_run_end(floor_reached: int) -> void:
	best_floor = maxi(best_floor, floor_reached)


# ---------------------------------------------------------------------------
# 单局生命周期
# ---------------------------------------------------------------------------

func begin_run(run_seed_value: int, floor: int = 0) -> void:
	is_in_run = true
	run_seed = run_seed_value
	floor_index = floor
	run_loot_log.clear()


func end_run() -> void:
	is_in_run = false
	player = null


func log_loot(stack: ItemStack) -> void:
	if stack == null:
		return
	run_loot_log.append(stack.clone_stack())


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"character_id": String(character_id),
		"player_level": player_level,
		"player_xp": player_xp,
		"gold": gold,
		"inventory": inventory.to_dict() if inventory else {},
		"equipped_weapons": [String(equipped_weapons[0]), String(equipped_weapons[1])],
		"unlocked_characters": unlocked_characters.duplicate(),
		"best_floor": best_floor,
		"total_kills": total_kills,
		"play_time": play_time,
	}


func from_dict(d: Dictionary) -> void:
	character_id = StringName(d.get("character_id", "ranger"))
	player_level = maxi(1, int(d.get("player_level", 1)))
	player_xp = maxi(0, int(d.get("player_xp", 0)))
	gold = maxi(0, int(d.get("gold", 0)))
	unlocked_characters = (d.get("unlocked_characters", {}) as Dictionary).duplicate()
	best_floor = int(d.get("best_floor", 0))
	total_kills = int(d.get("total_kills", 0))
	play_time = float(d.get("play_time", 0.0))
	equipped_weapons = [&"", &""]
	var eq: Array = d.get("equipped_weapons", [])
	for i in mini(eq.size(), equipped_weapons.size()):
		equipped_weapons[i] = StringName(eq[i])
	if inventory == null:
		inventory = Inventory.new()
	inventory.from_dict(d.get("inventory", {}))
	character_data = ConfigDB.get_character(character_id)
	if character_data == null:
		_ensure_default_character()
	rebuild_stats()
	EventBus.gold_changed.emit(gold)
	EventBus.player_level_changed.emit(player_level, player_xp, xp_needed_for_level(player_level))


## 新档
func reset_new_game() -> void:
	character_id = &"ranger"
	player_level = 1
	player_xp = 0
	gold = 0
	best_floor = 0
	total_kills = 0
	play_time = 0.0
	unlocked_characters.clear()
	equipped_weapons = [&"", &""]
	inventory = Inventory.new(Inventory.DEFAULT_SLOT_COUNT)
	character_data = null
	_ensure_default_character()
	rebuild_stats()
	_grant_starting_kit()


## 发放初始装备与物品。
## 【重要】只在「开新档」时调用一次，不能放在 Player._setup_from_game_state 里，
## 否则每次进出大厅都会重复发一份新手物资。
func _grant_starting_kit() -> void:
	if character_data == null:
		return
	equipped_weapons[0] = character_data.start_weapon_id
	equipped_weapons[1] = &""
	for item_id in character_data.start_items:
		var it := ConfigDB.get_item(item_id)
		if it:
			inventory.add_item(ItemStack.new(it, 1))
	add_gold(character_data.start_gold)


## 记录某槽位的武器（由 Player 调用，保证武器跨场景不丢）
func set_equipped_weapon(slot: int, id: StringName) -> void:
	if slot < 0 or slot >= equipped_weapons.size():
		return
	equipped_weapons[slot] = id


func get_equipped_weapon(slot: int) -> StringName:
	if slot < 0 or slot >= equipped_weapons.size():
		return &""
	return equipped_weapons[slot]
