extends Node
## 工程自检（场景式，可重复运行）。
##
## 【为什么不用 --script】
## Godot 的自动加载单例是在主循环启动后才注册为全局标识符的，
## 用 `--script` 跑校验器会导致所有引用 EventBus/ConfigDB 的脚本「假性编译失败」。
## 因此校验器必须作为一个 **场景** 启动，这样自动加载已就绪，校验才真实有效。
##
## 用法：
##   & "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" `
##       --headless --path E:\GodotProject res://tools/Validation.tscn
##
## 退出码：0 = 通过；1 = 有错误。输出以 `[VALIDATION]` 开头，便于脚本抓取。

const CHECK_DIRS := ["res://scripts", "res://tools"]
const SCENE_DIR := "res://scenes"

var _errors: PackedStringArray = PackedStringArray()
var _warnings: PackedStringArray = PackedStringArray()
var _checks: PackedStringArray = PackedStringArray()

var _n_scripts: int = 0
var _n_scenes: int = 0


func _ready() -> void:
	_log("=== SoulForest 工程自检 ===")
	await get_tree().process_frame

	_check_project_settings()
	_check_scripts()
	_check_scenes()
	_check_atlas()
	_check_config_db()
	_check_data_integrity()
	_check_sprite_content()
	_check_inventory()
	_check_loot()
	_check_skill_tree()
	_check_weapon_factory()
	_check_map_generation()
	_check_save_roundtrip()

	_report()
	get_tree().quit(0 if _errors.is_empty() else 1)


# ---------------------------------------------------------------------------
# 1. 工程设置
# ---------------------------------------------------------------------------
func _check_project_settings() -> void:
	var required := [
		"application/run/main_scene",
		"display/window/size/viewport_width",
		"display/window/size/viewport_height",
		"rendering/textures/canvas_textures/default_texture_filter",
	]
	for key in required:
		if not ProjectSettings.has_setting(key):
			_error("project.godot 缺少设置: %s" % key)
	var actions := [
		"move_up", "move_down", "move_left", "move_right",
		"fire", "roll", "interact", "inventory", "warehouse",
		"skill_tree", "pause", "use_potion", "drop_item",
	]
	for a in actions:
		if not InputMap.has_action(a):
			_error("缺少输入动作: %s" % a)
	var autoloads := [
		"EventBus", "ConfigDB", "SaveSystem", "GameState", "SceneRouter",
		"AudioManager", "SkillTreeService", "WarehouseService",
		"LootService", "RunManager",
	]
	for a in autoloads:
		if get_node_or_null("/root/" + a) == null:
			_error("自动加载单例未就绪: %s" % a)
	_check("工程设置与自动加载", true)


# ---------------------------------------------------------------------------
# 2. 脚本编译
# ---------------------------------------------------------------------------
func _check_scripts() -> void:
	var files: PackedStringArray = PackedStringArray()
	for d in CHECK_DIRS:
		_collect(d, ".gd", files)
	var bad := 0
	for f in files:
		if f.ends_with("tools/validation.gd"):
			continue
		_n_scripts += 1
		var s: Script = load(f)
		if s == null:
			_error("脚本加载失败: %s" % f)
			bad += 1
		elif not s.can_instantiate():
			_error("脚本无法实例化（编译失败）: %s" % f)
			bad += 1
	_check("脚本编译（%d 个）" % _n_scripts, bad == 0)


# ---------------------------------------------------------------------------
# 3. 场景加载
# ---------------------------------------------------------------------------
func _check_scenes() -> void:
	var files: PackedStringArray = PackedStringArray()
	_collect(SCENE_DIR, ".tscn", files)
	var bad := 0
	for f in files:
		_n_scenes += 1
		var ps: PackedScene = load(f)
		if ps == null:
			_error("场景加载失败: %s" % f)
			bad += 1
			continue
		var inst := ps.instantiate()
		if inst == null:
			_error("场景实例化失败: %s" % f)
			bad += 1
		else:
			inst.free()
	_check("场景加载（%d 个）" % _n_scenes, bad == 0)


# ---------------------------------------------------------------------------
# 4. 美术资源
# ---------------------------------------------------------------------------
func _check_atlas() -> void:
	var missing: PackedStringArray = PackedStringArray()
	for key in Atlas.SHEETS.keys():
		var meta: Dictionary = Atlas.SHEETS[key]
		if not ResourceLoader.exists(Atlas.DIR + String(meta["file"])):
			missing.append(String(meta["file"]))
	if missing.is_empty():
		_check("美术图集（%d 张）" % Atlas.SHEETS.size(), true)
	else:
		_warn("尚未生成的美术资源 %d 张：%s" % [missing.size(), ", ".join(missing)])
		_check("美术图集", false)


# ---------------------------------------------------------------------------
# 5. 配置数据库
# ---------------------------------------------------------------------------
func _check_config_db() -> void:
	if not ConfigDB.is_loaded:
		_error("ConfigDB 未加载")
		return
	for e in ConfigDB.load_errors:
		_error("ConfigDB: " + e)
	# 第一阶段硬性内容要求
	_expect_count("角色", ConfigDB.characters.size(), 1)
	_expect_count("敌人", ConfigDB.enemies.size(), 8)
	_expect_count("掉落表", ConfigDB.loot_tables.size(), 6)
	_expect_count("技能树", ConfigDB.skill_trees.size(), 1)
	var ranger := ConfigDB.get_character(&"ranger")
	if ranger == null:
		_error("缺少角色 ranger（游侠）")
	var cherry := ConfigDB.get_weapon(&"cherry_shotgun")
	if cherry == null:
		_error("缺少武器 cherry_shotgun（樱花霰弹枪）")
	elif cherry.rarity != GameEnums.Rarity.LEGENDARY:
		_error("cherry_shotgun 必须是橙色传奇品质")
	_check("配置数据库（%s）" % ConfigDB.summary(), true)


func _expect_count(label: String, actual: int, expected: int) -> void:
	if actual < expected:
		_error("%s 数量不足：%d / 期望 %d" % [label, actual, expected])


# ---------------------------------------------------------------------------
# 6. 数据完整性
# ---------------------------------------------------------------------------
func _check_data_integrity() -> void:
	var ok := true
	# 每个品质 3 把「仅有贴图」的通用武器（有专属实现的传说武器不计入）
	for r in GameEnums.Rarity.values():
		var n := 0
		for w in ConfigDB.weapons_by_rarity(r):
			if not WeaponRegistry.has_custom_implementation(w):
				n += 1
		if n != 3:
			_error("品质「%s」通用武器数量 %d（应为 3）" % [GameEnums.rarity_name(r), n])
			ok = false
	# 命中/受击盒层配置
	if Layers.PLAYER_HITBOX_MASK != (Layers.ENEMY_HURTBOX | Layers.WORLD):
		_error("玩家攻击盒掩码配置异常")
		ok = false
	# 敌人行为类型合法
	var valid_behaviors := [
		&"chase_melee", &"ranged_kiter", &"erratic_flyer",
		&"hopper", &"charger", &"boss_summoner",
	]
	for e in ConfigDB.enemies.values():
		if not valid_behaviors.has(e.behavior):
			_error("敌人 %s 的行为类型未实现: %s" % [e.id, e.behavior])
			ok = false
	_check("数据完整性", ok)


# ---------------------------------------------------------------------------
# 6.5 美术内容抽查（headless 下无法看图，用像素统计代替肉眼）
# ---------------------------------------------------------------------------
## 某些图集是「部分填充」的（例如 props.png 每行只用了前 6 格）。
## 因此不检查「所有格子」，而是检查 **代码真正引用到的格子** 是否非空，
## 这才是真正会导致运行期空贴图的失败模式。
## 这张图集是否允许"空瓦片"（双网格地表图集的特权）
func _dual_grid_allows_empty(sheet_name: String) -> bool:
	return sheet_name == "tileset_forest_ground"


func _required_cells(sheet_name: String, cols: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match sheet_name:
		"props":
			for v in Atlas.CHEST_CLOSED.values():
				out.append(v)
			for v in Atlas.CHEST_OPEN.values():
				out.append(v)
			out.append_array([
				Atlas.PROP_COIN_1, Atlas.PROP_COIN_2, Atlas.PROP_COIN_3, Atlas.PROP_COIN_4,
				Atlas.PROP_HEART, Atlas.PROP_MANA, Atlas.PROP_KEY, Atlas.PROP_PORTAL,
				Atlas.PROP_EXIT, Atlas.PROP_POUCH,
				Atlas.PROP_SHADOW, Atlas.PROP_HIT_SPARK, Atlas.PROP_MUZZLE_FLASH,
				Atlas.PROP_POTION_HP, Atlas.PROP_POTION_MP, Atlas.PROP_SCROLL,
				Atlas.DECO_DOOR, Atlas.DECO_TORCH, Atlas.DECO_BARREL, Atlas.DECO_CRATE,
				Atlas.DECO_BONES, Atlas.DECO_WEB,
			])
			for v in Atlas.SKILL_ICONS.values():
				out.append(v)
			for v in Atlas.UI_ICONS.values():
				out.append(v)
			for v in Atlas.RARITY_FRAME.values():
				out.append(v)
		"weapons":
			for v in Atlas.WEAPON_FRAMES.values():
				out.append(v)
		"tileset_forest_ground":
			# 双网格地表图集：只有 4 个 4×4 块是有效数据（4 种地形 × 16 角点），
			# 其余格子**故意留空**给后续地图（洞穴/雪原/沙漠…）。
			# 如果按"整张填满"来要求，会报 196 个空格的假错误 —— 实测就是这样。
			# 索引 → 槽位的换算一律走 DualGrid，别在这里手写。
			for t in 4:
				for i in 16:
					out.append(DualGrid.tile_coords(t, i))
		"tileset_forest_wall":
			# 墙体图集 8×8 全部有效
			for r in rows:
				for c in cols:
					out.append(Vector2i(c, r))
		"ui_frame_rarity":
			# 4 个品质框，第 0 列起连续 4 格
			for c in 4:
				out.append(Vector2i(c, 0))
		"ui_bar_armor":
			# 是一整张可横向拉伸的单图，不是格子图集。
			# 只要求最左一格有内容（避免整张空图漏过检查）。
			out.append(Vector2i(0, 0))
		"ui_bar":
			# 同上：上血条 / 下蓝条各取一格代表
			out.append(Vector2i(0, 0))
			out.append(Vector2i(0, 1))
		_:
			# 其余图集要求整张填满
			for r in rows:
				for c in cols:
					out.append(Vector2i(c, r))
	return out


func _check_sprite_content() -> void:
	var ok := true
	var report: PackedStringArray = PackedStringArray()
	var checked_cells := 0
	for key in Atlas.SHEETS.keys():
		var meta: Dictionary = Atlas.SHEETS[key]
		var path: String = Atlas.DIR + String(meta["file"])
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			_error("贴图加载失败: %s" % path)
			ok = false
			continue
		var img: Image = tex.get_image()
		if img == null:
			_error("贴图没有图像数据: %s" % path)
			ok = false
			continue
		var cell: int = meta["cell"]
		var cols: int = meta["cols"]
		var rows: int = meta["rows"]
		var colors: Dictionary = {}
		var empty_cells: PackedStringArray = PackedStringArray()
		for v in _required_cells(key, cols, rows):
			checked_cells += 1
			var filled := 0
			for y in range(v.y * cell, min((v.y + 1) * cell, img.get_height())):
				for x in range(v.x * cell, min((v.x + 1) * cell, img.get_width())):
					var px := img.get_pixel(x, y)
					if px.a > 0.05:
						filled += 1
						colors[px.to_rgba32()] = true
			if float(filled) / float(cell * cell) < 0.04:
				empty_cells.append("%d,%d" % [v.x, v.y])
		if not empty_cells.is_empty():
			if _dual_grid_allows_empty(key):
				# 双网格里索引 0 = "四角都不是本地形" = 该位置没有任何地形。
				# 双网格渲染时**只画属于本地形的象限**，所以这种瓦片永远不会被贴上去，
				# 留空是设计的一部分，不是素材缺失。
				var real: PackedStringArray = PackedStringArray()
				for e in empty_cells:
					if not Atlas.is_dual_grid_empty_slot(e):
						real.append(e)
				if real.is_empty():
					continue
				empty_cells = real
			_error("图集 %s 被代码引用但为空的格子 %d 个: %s" % [
				meta["file"], empty_cells.size(), ", ".join(empty_cells)
			])
			ok = false
		report.append("%-24s %3dx%-3d 用色 %2d" % [
			meta["file"], img.get_width(), img.get_height(), colors.size()
		])
	for line in report:
		_log("    · " + line)
	_check("美术图集内容抽查（%d 张 / %d 个被引用格子）" % [report.size(), checked_cells], ok)


# ---------------------------------------------------------------------------
# 7. 背包
# ---------------------------------------------------------------------------
func _check_inventory() -> void:
	var ok := true
	var inv := Inventory.new(6)
	var item := ConfigDB.get_item(&"hp_potion_small")
	if item == null:
		_error("缺少消耗品 hp_potion_small")
		return
	if inv.add_item(ItemStack.new(item, 5)) != 0:
		_error("背包 add_item 未能全部放入")
		ok = false
	if inv.count_of(&"hp_potion_small") != 5:
		_error("背包计数错误")
		ok = false
	if not inv.remove_item(&"hp_potion_small", 3):
		_error("背包扣除失败")
		ok = false
	if inv.count_of(&"hp_potion_small") != 2:
		_error("背包扣除后计数错误")
		ok = false
	# 存档往返
	var d := inv.to_dict()
	var inv2 := Inventory.new(6)
	inv2.from_dict(d)
	if inv2.count_of(&"hp_potion_small") != 2:
		_error("背包序列化往返失败")
		ok = false
	_check("背包系统", ok)


# ---------------------------------------------------------------------------
# 8. 掉落
# ---------------------------------------------------------------------------
func _check_loot() -> void:
	var ok := true
	for tier in [GameEnums.ChestTier.NORMAL, GameEnums.ChestTier.FINE, GameEnums.ChestTier.RARE]:
		var tid: StringName = LootService.CHEST_TABLE_BY_TIER[tier]
		var table := ConfigDB.get_loot_table(tid)
		if table == null:
			_error("缺少宝箱掉落表: %s" % tid)
			ok = false
			continue
		# 各掷 200 次，统计是否有产出
		var empty := 0
		var weapon_hits := 0
		var rarity_counts := {0: 0, 1: 0, 2: 0, 3: 0}
		for i in 200:
			var res := LootService.roll_table(table, 0.0)
			if res.is_empty():
				empty += 1
			for s in res:
				rarity_counts[s.get_rarity()] = int(rarity_counts.get(s.get_rarity(), 0)) + 1
				if s.data is WeaponData:
					weapon_hits += 1
		_log("    · %s：200 次开箱 → 空手 %d，产出武器 %d 件，品质分布 白%d/绿%d/蓝%d/橙%d" % [
			tid, empty, weapon_hits,
			rarity_counts[0], rarity_counts[1], rarity_counts[2], rarity_counts[3]
		])
		if table.guarantee_weapon and weapon_hits < 150:
			_error("%s 保底武器失效（200 次只出 %d 件）" % [tid, weapon_hits])
			ok = false
	# 品质抽取的幸运影响
	var low := 0
	var high := 0
	for i in 500:
		if LootService.roll_rarity(0.0) >= GameEnums.Rarity.RARE:
			low += 1
		if LootService.roll_rarity(5.0) >= GameEnums.Rarity.RARE:
			high += 1
	if high <= low:
		_error("幸运值没有提升高品质概率（luck0=%d, luck5=%d）" % [low, high])
		ok = false
	_log("    · 幸运影响：蓝+概率 luck0=%d/500 → luck5=%d/500" % [low, high])
	_check("掉落与宝箱系统", ok)


# ---------------------------------------------------------------------------
# 9. 技能树
# ---------------------------------------------------------------------------
func _check_skill_tree() -> void:
	var ok := true
	var tree := SkillTreeService.tree
	if tree == null:
		_error("技能树未加载")
		return
	if not tree.find_cycles().is_empty():
		_error("技能树存在环")
		ok = false
	var base := GameState.character_data.build_stat_block()
	var before := base.get_stat(GameEnums.StatKind.MAX_HP)
	SkillTreeService.reset()
	SkillTreeService.set_points(99)
	# 点满第一个无前置的战力节点
	var target: SkillNodeData = null
	for n in tree.nodes:
		if n.prerequisites.is_empty() and n.has_effect_on(GameEnums.StatKind.MAX_HP):
			target = n
			break
	if target == null:
		_warn("技能树里没有「无前置且加生命」的节点，跳过效果验证")
	else:
		for i in target.max_level:
			SkillTreeService.unlock(target.id, true)
		var block2 := GameState.character_data.build_stat_block()
		SkillTreeService.apply_to(block2)
		block2.recalculate()
		var after := block2.get_stat(GameEnums.StatKind.MAX_HP)
		if after <= before:
			_error("技能树效果未生效：MAX_HP %.1f → %.1f" % [before, after])
			ok = false
		_log("    · 技能 %s 点满后 MAX_HP %.1f → %.1f" % [target.id, before, after])
	# 序列化往返
	var d := SkillTreeService.to_dict()
	var pts := SkillTreeService.points
	SkillTreeService.from_dict(d)
	if SkillTreeService.points != pts:
		_error("技能树序列化往返失败")
		ok = false
	SkillTreeService.reset()
	_check("全局技能树", ok)


# ---------------------------------------------------------------------------
# 10. 武器工厂
# ---------------------------------------------------------------------------
func _check_weapon_factory() -> void:
	var ok := true
	var holder := CharacterBody2D.new()
	holder.set_script(load("res://scripts/entities/actor.gd"))
	add_child(holder)
	for w in ConfigDB.all_weapons():
		var n := WeaponRegistry.create_node(w)
		if n == null:
			_error("武器创建失败: %s" % w.id)
			ok = false
			continue
		if not (n is WeaponBase):
			_error("武器 %s 的实现不是 WeaponBase" % w.id)
			ok = false
		n.free()
	# 樱花霰弹枪专属实现校验
	var cherry := ConfigDB.get_weapon(&"cherry_shotgun")
	var cn := WeaponRegistry.create_node(cherry)
	if not (cn is WeaponCherryShotgun):
		_error("樱花霰弹枪没有加载到专属实现脚本")
		ok = false
	else:
		add_child(cn)
		cn.call("setup", cherry, holder)
		_log("    · %s" % cn.call("describe_last_shot"))
		cn.queue_free()
	holder.queue_free()
	var custom := 0
	for w in ConfigDB.all_weapons():
		if WeaponRegistry.has_custom_implementation(w):
			custom += 1
	_log("    · 12 把品质武器中已有专属实现的：%d 把（其余走默认实现，第一阶段符合预期）" % custom)
	_check("武器工厂", ok)


# ---------------------------------------------------------------------------
# 11. 地图生成
# ---------------------------------------------------------------------------
func _check_map_generation() -> void:
	var ok := true
	var cfg := ConfigDB.get_forest_config()
	if cfg == null:
		_error("找不到森林地图配置 forest_config")
		_check("森林地图生成", false)
		return
	for seed_i in 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed_i
		var graph: RoomGraph = ForestMapGenerator.generate(cfg, rng)
		if graph == null:
			_error("地图生成返回 null（seed %d）" % rng.seed)
			ok = false
			continue
		var unreachable: Array = graph.build_distances(graph.start_cell)
		if not unreachable.is_empty():
			_error("地图存在不可达房间 %d 个（seed %d）" % [unreachable.size(), rng.seed])
			ok = false
		if graph.get_room(graph.boss_cell) == null:
			_error("地图没有 BOSS 房（seed %d）" % rng.seed)
			ok = false
		var kinds: Dictionary = {}
		for r in graph.all_rooms():
			kinds[GameEnums.RoomKind.keys()[r.kind]] = int(kinds.get(GameEnums.RoomKind.keys()[r.kind], 0)) + 1
		_log("    · seed %d：%d 个房间 %s" % [rng.seed, graph.room_count(), str(kinds)])
	# ---- 同种子可复现 ----
	var g1: RoomGraph = _gen_with_seed(cfg, 4242)
	var g2: RoomGraph = _gen_with_seed(cfg, 4242)
	if g1 == null or g2 == null or g1.room_count() != g2.room_count():
		_error("同种子生成结果不一致（地图不可复现）")
		ok = false
	else:
		var same := true
		for r in g1.all_rooms():
			var r2 := g2.get_room(r.cell)
			if r2 == null or r2.kind != r.kind or r2.doors.size() != r.doors.size():
				same = false
				break
		if not same:
			_error("同种子房间布局不一致")
			ok = false
		else:
			_log("    · 同种子可复现性校验通过（seed 4242）")
	# ---- 不同种子应产生不同地图 ----
	var g3: RoomGraph = _gen_with_seed(cfg, 777)
	if g1 != null and g3 != null and g1.bounds == g3.bounds and g1.room_count() == g3.room_count():
		var identical := true
		for r in g1.all_rooms():
			if not g3.has_room(r.cell):
				identical = false
				break
		if identical:
			_error("不同种子产生了完全相同的地图")
			ok = false
	_check("森林地图生成（5 个随机种子）", ok)


func _gen_with_seed(cfg: ForestMapConfig, s: int) -> RoomGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return ForestMapGenerator.generate(cfg, rng)


# ---------------------------------------------------------------------------
# 12. 存档往返
# ---------------------------------------------------------------------------
func _check_save_roundtrip() -> void:
	var ok := true
	var backup_gold := GameState.gold
	var backup_lv := GameState.player_level
	GameState.add_gold(777)
	GameState.player_level = 7
	var slot := 2  # 用 2 号槽做测试，避免污染玩家的 0 号槽
	if not SaveSystem.save_game(slot):
		_error("存档写入失败")
		ok = false
	else:
		GameState.add_gold(-777)
		GameState.player_level = 1
		if not SaveSystem.load_game(slot):
			_error("存档读取失败")
			ok = false
		else:
			if GameState.player_level != 7:
				_error("存档往返后等级不一致：%d" % GameState.player_level)
				ok = false
		SaveSystem.delete_slot(slot)
	GameState.gold = backup_gold
	GameState.player_level = backup_lv
	_check("存档系统往返", ok)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _collect(dir_path: String, ext: String, out: PackedStringArray) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.begins_with("."):
			f = da.get_next()
			continue
		var full := dir_path.path_join(f)
		if da.current_is_dir():
			_collect(full, ext, out)
		elif f.ends_with(ext):
			out.append(full)
		f = da.get_next()
	da.list_dir_end()


func _check(label: String, ok: bool) -> void:
	_checks.append("%s %s" % ["[PASS]" if ok else "[FAIL]", label])
	_log("  %s %s" % ["✓" if ok else "✗", label])


func _error(msg: String) -> void:
	_errors.append(msg)
	_log("  [ERROR] " + msg)


func _warn(msg: String) -> void:
	_warnings.append(msg)
	_log("  [WARN] " + msg)


func _log(s: String) -> void:
	print("[VALIDATION] " + s)


func _report() -> void:
	_log("=== 结果 ===")
	_log("脚本 %d · 场景 %d · 检查项 %d" % [_n_scripts, _n_scenes, _checks.size()])
	if _warnings.is_empty():
		_log("警告：0")
	else:
		_log("警告 %d 条" % _warnings.size())
	if _errors.is_empty():
		_log("错误：0 —— 全部通过 ✅")
	else:
		_log("错误 %d 条：" % _errors.size())
		for e in _errors:
			_log("  [ERROR] " + e)
