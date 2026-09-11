extends Node
## ConfigDB —— 全局配置数据库（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 游戏里所有「物品 / 武器 / 角色 / 敌人 / 掉落表 / 技能树 / 投射物」都必须是
##    res://data/** 下的 .tres 资源，由本单例在启动时扫描加载。
##    代码里 **禁止** 硬编码任何数值表。
## 2. 取数据一律使用 get_xxx(id)；找不到会 push_error 并返回 null，
##    调用方必须做 null 判断（框架不允许静默失败）。
## 3. 新增内容 = 往对应目录放 .tres 文件（或跑 tools/gen_data.gd 生成），
##    无需修改本文件。
## 4. 目录扫描兼容导出后的 .remap，因此本文件在导出构建里同样可用。

const DATA_DIRS := {
	"items": "res://data/items",
	"weapons": "res://data/weapons",
	"characters": "res://data/characters",
	"enemies": "res://data/enemies",
	"loot_tables": "res://data/loot_tables",
	"skills": "res://data/skills",
	"projectiles": "res://data/projectiles",
	"levels": "res://data/levels",
}

var items: Dictionary = {}        ## StringName -> ItemData（含 WeaponData）
var weapons: Dictionary = {}      ## StringName -> WeaponData
var characters: Dictionary = {}   ## StringName -> CharacterData
var enemies: Dictionary = {}      ## StringName -> EnemyData
var loot_tables: Dictionary = {}  ## StringName -> LootTable
var skill_trees: Dictionary = {}  ## StringName -> SkillTreeData
var projectiles: Dictionary = {}  ## StringName -> ProjectileData
var forest_maps: Dictionary = {}  ## StringName -> ForestMapConfig

var is_loaded: bool = false
var load_errors: PackedStringArray = PackedStringArray()
var load_stats: Dictionary = {}


func _ready() -> void:
	reload()


# ---------------------------------------------------------------------------
# 加载
# ---------------------------------------------------------------------------

func reload() -> void:
	items.clear()
	weapons.clear()
	characters.clear()
	enemies.clear()
	loot_tables.clear()
	skill_trees.clear()
	projectiles.clear()
	forest_maps.clear()
	load_errors.clear()
	load_stats.clear()

	_scan("items", func(r: Resource) -> void:
		if r is ItemData:
			_register_item(r, "items"))
	_scan("weapons", func(r: Resource) -> void:
		if r is WeaponData:
			_register_item(r, "weapons"))
	_scan("characters", func(r: Resource) -> void:
		if r is CharacterData:
			_register_unique(characters, r.id, r, "characters"))
	_scan("enemies", func(r: Resource) -> void:
		if r is EnemyData:
			_register_unique(enemies, r.id, r, "enemies"))
	_scan("loot_tables", func(r: Resource) -> void:
		if r is LootTable:
			_register_unique(loot_tables, r.id, r, "loot_tables"))
	_scan("skills", func(r: Resource) -> void:
		if r is SkillTreeData:
			_register_unique(skill_trees, r.id, r, "skills"))
	_scan("projectiles", func(r: Resource) -> void:
		if r is ProjectileData:
			_register_unique(projectiles, r.id, r, "projectiles"))
	_scan("levels", func(r: Resource) -> void:
		if r is ForestMapConfig:
			_register_unique(forest_maps, r.id, r, "levels"))

	is_loaded = true
	_validate()

	print("[ConfigDB] 加载完成：物品 %d（其中武器 %d）/ 角色 %d / 敌人 %d / 掉落表 %d / 技能树 %d / 投射物 %d" % [
		items.size(), weapons.size(), characters.size(),
		enemies.size(), loot_tables.size(), skill_trees.size(), projectiles.size()
	])
	if not load_errors.is_empty():
		for e in load_errors:
			push_error("[ConfigDB] " + e)


func _scan(dir_key: String, handler: Callable) -> void:
	var dir_path: String = DATA_DIRS[dir_key]
	var files := _list_resources(dir_path)
	var ok := 0
	for path in files:
		var res: Resource = load(path)
		if res == null:
			load_errors.append("无法加载资源: %s" % path)
			continue
		handler.call(res)
		ok += 1
	load_stats[dir_key] = ok


## 列出目录下所有 Resource 路径（兼容导出后的 .remap / .res）
static func _list_resources(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var raw := DirAccess.get_files_at(dir_path)
	for f in raw:
		if f.ends_with(".remap"):
			f = f.substr(0, f.length() - ".remap".length())
		elif f.ends_with(".import"):
			continue
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		if seen.has(f):
			continue
		seen[f] = true
		out.append(dir_path.path_join(f))
	return out


func _register_item(r: ItemData, source: String) -> void:
	if r.id == &"":
		load_errors.append("%s 目录下有物品未设置 id" % source)
		return
	if items.has(r.id):
		load_errors.append("物品 id 重复: %s" % r.id)
		return
	items[r.id] = r
	if r is WeaponData:
		weapons[r.id] = r


func _register_unique(dict: Dictionary, id: StringName, r: Resource, source: String) -> void:
	if id == &"":
		load_errors.append("%s 目录下有资源未设置 id（%s）" % [source, r.resource_path])
		return
	if dict.has(id):
		load_errors.append("%s id 重复: %s" % [source, id])
		return
	dict[id] = r


# ---------------------------------------------------------------------------
# 校验
# ---------------------------------------------------------------------------

func _validate() -> void:
	# 武器品质分布（第一阶段要求：每个品质 3 把「仅有贴图」的通用武器，
	# 樱花霰弹枪这类有专属实现的传说武器不计入这 3 把）
	var by_rarity: Dictionary = {}
	for w in weapons.values():
		if WeaponRegistry.has_custom_implementation(w):
			continue
		by_rarity[w.rarity] = int(by_rarity.get(w.rarity, 0)) + 1
	for r in GameEnums.Rarity.values():
		var n: int = int(by_rarity.get(r, 0))
		if n != 3:
			load_errors.append("品质「%s」的通用武器数量为 %d（第一阶段要求 3 把）" % [
				GameEnums.rarity_name(r), n
			])
	# 樱花霰弹枪必须在场且为橙色传奇
	var cherry := get_weapon(&"cherry_shotgun")
	if cherry == null:
		load_errors.append("缺少终极武器 cherry_shotgun（樱花霰弹枪）")
	elif cherry.rarity != GameEnums.Rarity.LEGENDARY:
		load_errors.append("cherry_shotgun 必须为橙色传奇品质")
	elif not WeaponRegistry.has_custom_implementation(cherry):
		load_errors.append("cherry_shotgun 必须配置专属实现脚本")
	# 掉落表完整性
	for lt in loot_tables.values():
		if lt.weapon_rarity_weights.size() != GameEnums.RARITY_COUNT:
			load_errors.append("掉落表 %s 的 weapon_rarity_weights 长度应为 %d" % [
				lt.id, GameEnums.RARITY_COUNT
			])
		for pool in [lt.entries, lt.guaranteed]:
			for e in pool:
				if e.item_id == &"" or String(e.item_id).begins_with("@"):
					continue
				if not items.has(e.item_id):
					load_errors.append("掉落表 %s 引用了不存在的物品: %s" % [lt.id, e.item_id])
	# 技能树环检测
	for t in skill_trees.values():
		var tree_res: SkillTreeData = t
		var cyc: Array = tree_res.find_cycles()
		if not cyc.is_empty():
			load_errors.append("技能树 %s 存在环: %s" % [tree_res.id, cyc])
		var miss: Array = tree_res.find_missing_prerequisites()
		if not miss.is_empty():
			load_errors.append("技能树 %s 存在悬空前置: %s" % [tree_res.id, miss])
	# 掉落表引用的物品是否存在（上面已校验，这里只补「敌人 → 掉落表」的引用）
	for e in enemies.values():
		if e.loot_table_id != &"" and not loot_tables.has(e.loot_table_id):
			load_errors.append("敌人 %s 引用了不存在的掉落表: %s" % [e.id, e.loot_table_id])


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func get_item(id: StringName) -> ItemData:
	if id == &"":
		return null
	if items.has(id):
		return items[id]
	push_error("[ConfigDB] 未知物品 id: %s" % id)
	return null


func get_weapon(id: StringName) -> WeaponData:
	if id == &"":
		return null
	if weapons.has(id):
		return weapons[id]
	push_error("[ConfigDB] 未知武器 id: %s" % id)
	return null


func get_character(id: StringName) -> CharacterData:
	if characters.has(id):
		return characters[id]
	push_error("[ConfigDB] 未知角色 id: %s" % id)
	return null


func get_enemy(id: StringName) -> EnemyData:
	if enemies.has(id):
		return enemies[id]
	push_error("[ConfigDB] 未知敌人 id: %s" % id)
	return null


func get_loot_table(id: StringName) -> LootTable:
	if loot_tables.has(id):
		return loot_tables[id]
	push_error("[ConfigDB] 未知掉落表 id: %s" % id)
	return null


func get_skill_tree(id: StringName) -> SkillTreeData:
	if skill_trees.has(id):
		return skill_trees[id]
	push_error("[ConfigDB] 未知技能树 id: %s" % id)
	return null


func get_projectile(id: StringName) -> ProjectileData:
	if projectiles.has(id):
		return projectiles[id]
	return null


## 森林第一关的地图生成配置
func get_forest_config() -> ForestMapConfig:
	if forest_maps.has(&"forest_config"):
		return forest_maps[&"forest_config"]
	for c in forest_maps.values():
		return c
	push_error("[ConfigDB] 未找到森林地图配置（res://data/levels/forest_config.tres）")
	return null


# ---------------------------------------------------------------------------
# 批量查询
# ---------------------------------------------------------------------------

func all_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w in weapons.values():
		out.append(w)
	out.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return String(a.id) < String(b.id))
	return out


func weapons_by_rarity(rarity: int) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w in all_weapons():
		if w.rarity == rarity:
			out.append(w)
	return out


func all_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for i in items.values():
		out.append(i)
	return out


func all_characters() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c in characters.values():
		out.append(c)
	out.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		return String(a.id) < String(b.id))
	return out


func all_enemies() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for e in enemies.values():
		out.append(e)
	return out


func enemies_by_tier(tier: int) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for e in enemies.values():
		if e.tier == tier:
			out.append(e)
	return out


## 可在森林第一层刷出的普通小怪
func forest_normal_enemies() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for e in enemies.values():
		if e.tier == GameEnums.EnemyTier.NORMAL and e.spawn_weight > 0.0:
			out.append(e)
	return out


func forest_elite_enemies() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for e in enemies.values():
		if e.tier == GameEnums.EnemyTier.ELITE:
			out.append(e)
	return out


func forest_boss() -> EnemyData:
	for e in enemies.values():
		if e.tier == GameEnums.EnemyTier.BOSS:
			return e
	return null


func get_global_tree() -> SkillTreeData:
	return skill_trees.get(&"global_tree", null)


## 统计信息（调试面板用）
func summary() -> String:
	return "物品 %d / 武器 %d / 角色 %d / 敌人 %d / 掉落表 %d / 技能树 %d" % [
		items.size(), weapons.size(), characters.size(),
		enemies.size(), loot_tables.size(), skill_trees.size()
	]
