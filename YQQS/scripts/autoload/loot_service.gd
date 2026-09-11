extends Node
## LootService —— 掉落与宝箱系统（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 「掉什么」全部写在 res://data/loot_tables/*.tres；本文件只负责
##    抽取算法 + 场景实例化。调掉率 = 改 .tres，不改代码。
## 2. 品质抽取唯一入口是 roll_rarity()：幸运(luck) 只在这里生效，
##    其他任何地方都不许再算品质概率。
## 3. 宝箱等级 → 掉落表映射见 CHEST_TABLE_BY_TIER；小怪/精英/BOSS
##    掉落不同等级宝箱的规则见 EnemyData.get_chest_tier()。
## 4. 掉落物场景统一由本文件实例化并挂到 parent 下，
##    调用方（敌人/关卡）不关心掉落物长什么样。

const CHEST_SCENE := "res://scenes/items/Chest.tscn"
const COIN_SCENE := "res://scenes/items/CoinPickup.tscn"
const ITEM_PICKUP_SCENE := "res://scenes/items/ItemPickup.tscn"

## 宝箱等级 → 掉落表 id
const CHEST_TABLE_BY_TIER := {
	GameEnums.ChestTier.NORMAL: &"chest_normal",
	GameEnums.ChestTier.FINE: &"chest_fine",
	GameEnums.ChestTier.RARE: &"chest_rare",
}

## 宝箱等级 → 场景缩放
const CHEST_SCALE_BY_TIER := {
	GameEnums.ChestTier.NORMAL: 1.0,
	GameEnums.ChestTier.FINE: 1.15,
	GameEnums.ChestTier.RARE: 1.35,
}

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


# ---------------------------------------------------------------------------
# 品质抽取
# ---------------------------------------------------------------------------

## 掷品质。luck 越高越容易出高品；floor_rarity/ceiling 用于宝箱等级门限。
func roll_rarity(
	luck: float = 0.0,
	floor_rarity: int = -1,
	ceiling_rarity: int = -1,
	weights_override: Dictionary = {}
) -> int:
	var items: Array = []
	var weights: Array = []
	for r in GameEnums.Rarity.values():
		if floor_rarity >= 0 and r < floor_rarity:
			continue
		if ceiling_rarity >= 0 and r > ceiling_rarity:
			continue
		var w: float = float(weights_override.get(r, GameEnums.RARITY_BASE_WEIGHT[r]))
		items.append(r)
		weights.append(maxf(0.001, w * _luck_factor(r, luck)))
	if items.is_empty():
		return GameEnums.Rarity.COMMON
	return int(RngUtils.pick_weighted(rng, items, weights))


## 幸运对某品质的权重系数
func _luck_factor(rarity: int, luck: float) -> float:
	var l := maxf(0.0, luck)
	match rarity:
		GameEnums.Rarity.COMMON:
			return maxf(0.15, 1.0 - l * 0.18)
		GameEnums.Rarity.UNCOMMON:
			return 1.0 + l * 0.12
		GameEnums.Rarity.RARE:
			return 1.0 + l * 0.30
		GameEnums.Rarity.LEGENDARY:
			return 1.0 + l * 0.45
	return 1.0


## 综合幸运值（技能树 luck + 临时加成）
func current_luck() -> float:
	var l := 0.0
	if GameState and GameState.stats:
		l += GameState.get_stat(GameEnums.StatKind.LUCK)
	return maxf(0.0, l)


# ---------------------------------------------------------------------------
# 掉落表抽取
# ---------------------------------------------------------------------------

## 掷一个掉落表，返回 ItemStack 数组（可能为空）
func roll_table(table: LootTable, luck: float = -1.0, tags: PackedStringArray = PackedStringArray()) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	if table == null:
		return out
	var eff_luck := current_luck() if luck < 0.0 else luck
	var infl := table.luck_influence
	var luck_for_rarity := eff_luck * infl

	# ① 必定掉落
	for i in table.guaranteed.size():
		var e: LootEntry = table.guaranteed[i]
		var p := 1.0
		if i < table.guaranteed_chances.size():
			p = table.guaranteed_chances[i]
		if RngUtils.chance(rng, p):
			var s := _make_stack(e)
			if s:
				out.append(s)

	# ② 随机抽取
	for i in table.roll_count:
		var pool := table.get_entries_for(0, tags)
		if pool.is_empty():
			break
		var items: Array = []
		var weights: Array = []
		if table.empty_weight > 0.0:
			items.append(null)
			weights.append(table.empty_weight)
		for e in pool:
			items.append(e)
			weights.append(maxf(0.0, e.weight))
		var picked = RngUtils.pick_weighted(rng, items, weights)
		if picked == null:
			continue
		var stack := _make_stack(picked)
		if stack:
			out.append(stack)

	# ③ 品质门限修正：不够高品的全部重掷（稀有箱子保证蓝以上）
	if table.rarity_floor >= 0 or table.rarity_ceiling >= 0:
		out = _enforce_rarity(out, table, luck_for_rarity, tags)

	# ④ 装备掉落（第一阶段核心掉率：由 LootTable.weapon_* 配置驱动）
	out = _append_weapon_drops(out, table, eff_luck)

	# ⑤ 保底武器（guarantee_weapon 且上面一件都没出）
	if table.guarantee_weapon and not _contains_weapon(out):
		var w := _pick_random_weapon(table.rarity_floor)
		if w:
			out.append(w)

	# ⑥ 数量夹取
	var min_r := table.min_results
	if out.size() < min_r:
		var extra_pool := table.get_entries_for(0, tags)
		while out.size() < min_r and not extra_pool.is_empty():
			var e = RngUtils.pick_weighted(rng, extra_pool,
				extra_pool.map(func(x: LootEntry) -> float: return x.weight))
			var s := _make_stack(e)
			if s == null:
				break
			out.append(s)
	if table.max_results > 0 and out.size() > table.max_results:
		out = out.slice(0, table.max_results)
	return out


## 按 WeaponRarityWeights 抽若干件装备
func _append_weapon_drops(
	stacks: Array[ItemStack], table: LootTable, luck: float
) -> Array[ItemStack]:
	if not table.has_weapon_drop():
		return stacks
	if not RngUtils.chance(rng, table.weapon_drop_chance):
		return stacks
	var n := rng.randi_range(
		table.weapon_count_range.x,
		maxi(table.weapon_count_range.x, table.weapon_count_range.y)
	)
	if table.extra_weapon_chance > 0.0 and RngUtils.chance(rng, table.extra_weapon_chance):
		n += 1
	var weights := table.get_weapon_rarity_weights()
	for i in n:
		var r := roll_rarity(luck * table.luck_influence, -1, -1, _rarity_weight_dict(weights))
		var w := _pick_random_weapon_exact(r)
		if w == null:
			w = _pick_random_weapon(-1)
		if w:
			stacks.append(w)
	return stacks


static func _rarity_weight_dict(weights: Array[float]) -> Dictionary:
	var d: Dictionary = {}
	for i in weights.size():
		d[i] = weights[i]
	return d


## 精确品质的随机武器（找不到就降级到更低品质）
func _pick_random_weapon_exact(rarity: int) -> ItemStack:
	for r in range(rarity, -1, -1):
		var pool: Array[WeaponData] = []
		for w in ConfigDB.weapons.values():
			if w.rarity == r and not WeaponRegistry.has_custom_implementation(w):
				pool.append(w)
		if not pool.is_empty():
			var picked: WeaponData = pool[rng.randi_range(0, pool.size() - 1)]
			return ItemStack.new(picked, 1)
	# 允许把「有专属实现的武器」也当掉落（例如 BOSS 出樱花霰弹枪）
	for w in ConfigDB.weapons.values():
		if w.rarity == rarity:
			return ItemStack.new(w, 1)
	return null


func _enforce_rarity(
	stacks: Array[ItemStack], table: LootTable, luck: float, tags: PackedStringArray
) -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for s in stacks:
		var ok := true
		if table.rarity_floor >= 0 and s.get_rarity() < table.rarity_floor:
			ok = false
		if table.rarity_ceiling >= 0 and s.get_rarity() > table.rarity_ceiling:
			ok = false
		if ok:
			result.append(s)
			continue
		# 重掷一件符合条件的
		var pool := table.get_entries_for(0, tags)
		var candidates: Array = []
		for e in pool:
			var it := ConfigDB.get_item(e.item_id)
			if it == null:
				continue
			if table.rarity_floor >= 0 and it.rarity < table.rarity_floor:
				continue
			if table.rarity_ceiling >= 0 and it.rarity > table.rarity_ceiling:
				continue
			candidates.append(e)
		if candidates.is_empty():
			continue
		var picked = RngUtils.pick_weighted(rng, candidates,
			candidates.map(func(x: LootEntry) -> float: return x.weight))
		var ns := _make_stack(picked)
		if ns:
			result.append(ns)
	return result


func _make_stack(e: LootEntry) -> ItemStack:
	if e == null or e.item_id == &"":
		return null
	# 特殊占位：随机武器
	if e.item_id == &"@random_weapon":
		var w := _pick_random_weapon_exact(e.force_rarity if e.force_rarity >= 0 else GameEnums.Rarity.COMMON)
		return w
	var item := ConfigDB.get_item(e.item_id)
	if item == null:
		return null
	var n := e.roll_count(rng)
	if n <= 0:
		return null
	return ItemStack.new(item, n)


func _contains_weapon(stacks: Array[ItemStack]) -> bool:
	for s in stacks:
		if s and s.data is WeaponData:
			return true
	return false


func _contains_rarity_at_least(stacks: Array[ItemStack], r: int) -> bool:
	for s in stacks:
		if s and s.get_rarity() >= r:
			return true
	return false


## 随机取一把武器（可限定品质下限）
func _pick_random_weapon(min_rarity: int = -1) -> ItemStack:
	var pool: Array[WeaponData] = []
	for w in ConfigDB.weapons.values():
		if min_rarity >= 0 and w.rarity < min_rarity:
			continue
		pool.append(w)
	if pool.is_empty():
		return null
	# 越高级越稀有
	var items: Array = []
	var weights: Array = []
	for w in pool:
		items.append(w)
		weights.append(1.0 / (1.0 + float(w.rarity) * 1.6))
	var picked: WeaponData = RngUtils.pick_weighted(rng, items, weights)
	return ItemStack.new(picked, 1)


# ---------------------------------------------------------------------------
# 敌人死亡掉落
# ---------------------------------------------------------------------------

## 敌人死亡时调用：掷宝箱 + 金币 + 直接掉落物。
## 返回在 parent 下生成的所有掉落节点（供 RunManager / 测试统计）。
func handle_enemy_death(
	data: EnemyData,
	world_position: Vector2,
	parent: Node,
	allow_chest: bool = true
) -> Array[Node]:
	var spawned: Array[Node] = []
	if data == null or parent == null:
		return spawned
	var luck := current_luck()

	# ① 宝箱（小怪 → 普通 / 精英 → 优秀 / BOSS → 稀有）
	var chest_chance := data.chest_drop_chance
	if data.tier == GameEnums.EnemyTier.ELITE:
		chest_chance = 1.0
	elif data.tier == GameEnums.EnemyTier.BOSS:
		chest_chance = 1.0
	if allow_chest and RngUtils.chance(rng, chest_chance):
		var chest := spawn_chest(data.get_chest_tier(), world_position, parent)
		if chest:
			spawned.append(chest)

	# ② 金币
	if data.gold_max > 0 and RngUtils.chance(rng, data.coin_drop_chance):
		var amount := rng.randi_range(data.gold_min, maxi(data.gold_min, data.gold_max))
		if data.tier == GameEnums.EnemyTier.ELITE:
			amount = int(amount * 1.8)
		elif data.tier == GameEnums.EnemyTier.BOSS:
			amount = int(amount * 4.0)
		var coin := spawn_coin(amount, world_position + RngUtils.in_ring(rng, 4, 10), parent)
		if coin:
			spawned.append(coin)

	# ③ 额外直接掉落（消耗品等）
	var table := ConfigDB.get_loot_table(data.loot_table_id)
	if table:
		var stacks := roll_table(table, luck, PackedStringArray([String(data.id)]))
		for s in stacks:
			if s.data is WeaponData:
				var n := spawn_weapon_pickup(s, world_position + RngUtils.in_ring(rng, 6, 14), parent)
				if n:
					spawned.append(n)
			else:
				var n2 := spawn_item_pickup(s, world_position + RngUtils.in_ring(rng, 6, 14), parent)
				if n2:
					spawned.append(n2)
	return spawned


# ---------------------------------------------------------------------------
# 宝箱
# ---------------------------------------------------------------------------

func spawn_chest(
	tier: int, world_position: Vector2, parent: Node, extra: Dictionary = {}
) -> Node:
	if parent == null:
		return null
	var scene: PackedScene = load(CHEST_SCENE) if ResourceLoader.exists(CHEST_SCENE) else null
	if scene == null:
		push_error("[LootService] 找不到宝箱场景: %s" % CHEST_SCENE)
		return null
	var chest := scene.instantiate()
	chest.set("tier", tier)
	if chest.has_method("configure"):
		chest.configure(tier, extra)
	parent.add_child(chest)
	if chest is Node2D:
		(chest as Node2D).global_position = world_position
	var sc: float = CHEST_SCALE_BY_TIER.get(tier, 1.0)
	if chest is Node2D:
		(chest as Node2D).scale = Vector2.ONE * sc
	EventBus.chest_spawned.emit(chest, tier)
	return chest


## 开箱：返回产出的 ItemStack 列表（调用方负责生成掉落物或直接进背包）
func open_chest(chest: Node) -> Array[ItemStack]:
	var tier: int = GameEnums.ChestTier.NORMAL
	if chest and chest.get("tier") != null:
		tier = int(chest.get("tier"))
	var table_id: StringName = CHEST_TABLE_BY_TIER.get(tier, &"chest_normal")
	var table := ConfigDB.get_loot_table(table_id)
	var rewards := roll_table(table)
	# 金币
	if table and table.gold_max > 0:
		var g := rng.randi_range(table.gold_min, maxi(table.gold_min, table.gold_max))
		if g > 0:
			GameState.add_gold(g)
	EventBus.chest_opened.emit(chest, tier, rewards)
	return rewards


# ---------------------------------------------------------------------------
# 掉落物实例化
# ---------------------------------------------------------------------------

func spawn_coin(amount: int, world_position: Vector2, parent: Node) -> Node:
	if amount <= 0 or parent == null:
		return null
	if not ResourceLoader.exists(COIN_SCENE):
		# 场景还没做好时降级为直接加钱，保证逻辑不中断
		GameState.add_gold(amount)
		return null
	var scene: PackedScene = load(COIN_SCENE)
	var n := scene.instantiate()
	n.set("amount", amount)
	parent.add_child(n)
	if n is Node2D:
		(n as Node2D).global_position = world_position
	return n


func spawn_item_pickup(stack: ItemStack, world_position: Vector2, parent: Node) -> Node:
	if stack == null or parent == null:
		return null
	if not ResourceLoader.exists(ITEM_PICKUP_SCENE):
		return null
	var scene: PackedScene = load(ITEM_PICKUP_SCENE)
	var n := scene.instantiate()
	n.set("stack", stack)
	parent.add_child(n)
	if n is Node2D:
		(n as Node2D).global_position = world_position
	EventBus.loot_dropped.emit(stack, world_position)
	return n


func spawn_weapon_pickup(stack: ItemStack, world_position: Vector2, parent: Node) -> Node:
	# 武器掉落复用 ItemPickup（它内部按 stack 类型决定表现）
	return spawn_item_pickup(stack, world_position, parent)


# ---------------------------------------------------------------------------
# 宝箱掉率说明（供文档/调试面板引用）
# ---------------------------------------------------------------------------

## 返回一份人类可读的掉率表，用于 docs 与调试面板保持一致
static func drop_rate_table() -> Array[Dictionary]:
	return [
		{"tier": "普通宝箱", "owner": "小怪", "table": "chest_normal",
		 "weapon": "60%", "rarity": "白 70% / 绿 25% / 蓝 5% / 橙 0%",
		 "gold": "3-10", "extra": "40% 出消耗品"},
		{"tier": "优秀宝箱", "owner": "精英怪", "table": "chest_fine",
		 "weapon": "100%（+35% 额外一件）", "rarity": "绿 45% / 蓝 45% / 橙 10%",
		 "gold": "15-35", "extra": "必出 1 件装备"},
		{"tier": "稀有宝箱", "owner": "BOSS", "table": "chest_rare",
		 "weapon": "100%（2 件，至少 1 件蓝以上）", "rarity": "蓝 80% / 橙 20%",
		 "gold": "60-120", "extra": "必出技能书 / 大药"},
	]
