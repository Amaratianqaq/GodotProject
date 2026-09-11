extends SceneTree
## 第一阶段全部游戏数据生成器（一次性 / 可重复运行）。
##
## 运行：
##   & "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" `
##       --headless --path E:\GodotProject --script res://tools/gen_data.gd
##
## 【为什么用代码生成 .tres 而不是手写】
## 手写 .tres 极易漏字段、写错类型；代码生成可读、可 review、可 diff，
## 而且改数值只要改这里一个地方。生成的 .tres 仍然是标准资源，
## 之后完全可以在 Godot 编辑器里直接调，编辑器改动不会被本脚本覆盖
## （除非你再跑一次本脚本）。
##
## 【内容清单（第一阶段）】
##   物品：10 个（消耗品 + 材料 + 钥匙）
##   武器：12 把通用（白/绿/蓝/橙 各 3）+ 樱花霰弹枪（橙·传奇·完整实现）
##   角色：游侠 ×1
##   敌人：5 小怪 + 2 精英 + 1 BOSS
##   掉落表：3 宝箱 + 3 敌人
##   技能树：全局技能树 22 个节点 / 4 条分支
##   投射物：5 种预设
##   关卡：森林地图生成配置 ×1

const DATA := "res://data"

var _written: int = 0
var _errors: PackedStringArray = PackedStringArray()


func _init() -> void:
	print("[gen_data] 开始生成游戏数据 ...")
	_ensure_dirs()
	_gen_items()
	_gen_weapons()
	_gen_characters()
	_gen_enemies()
	_gen_loot_tables()
	_gen_skill_tree()
	_gen_projectiles()
	_gen_levels()
	print("[gen_data] 完成：写入 %d 个资源" % _written)
	if not _errors.is_empty():
		for e in _errors:
			push_error("[gen_data] " + e)
		quit(1)
		return
	quit(0)


# ---------------------------------------------------------------------------
# 基础设施
# ---------------------------------------------------------------------------

func _ensure_dirs() -> void:
	for d in ["items", "weapons", "characters", "enemies", "loot_tables",
			"skills", "projectiles", "levels", "themes"]:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(DATA.path_join(d))
		)


func _save(res: Resource, sub: String, file_name: String) -> void:
	var path := "%s/%s/%s.tres" % [DATA, sub, file_name]
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_errors.append("保存失败(%d): %s" % [err, path])
	else:
		_written += 1


# ---------------------------------------------------------------------------
# 物品
# ---------------------------------------------------------------------------

func _gen_items() -> void:
	# --- 回复药水 ---
	_item_consumable(&"hp_potion_small", "小治疗药水", GameEnums.Rarity.COMMON,
		Vector2i(3, 3), 25.0, 0.0, "回复 25 点生命。森林里最常见的补给。", 8)
	_item_consumable(&"hp_potion_large", "大治疗药水", GameEnums.Rarity.UNCOMMON,
		Vector2i(3, 3), 65.0, 0.0, "回复 65 点生命。瓶身更厚的浓缩配方。", 22)
	_item_consumable(&"mp_potion_small", "小能量药水", GameEnums.Rarity.COMMON,
		Vector2i(4, 3), 0.0, 30.0, "回复 30 点能量。", 8)
	_item_consumable(&"mp_potion_large", "大能量药水", GameEnums.Rarity.UNCOMMON,
		Vector2i(4, 3), 0.0, 75.0, "回复 75 点能量。", 22)
	_item_consumable(&"elixir_life", "生命精华", GameEnums.Rarity.RARE,
		Vector2i(3, 3), 999.0, 999.0, "同时回满生命与能量。BOSS 宝箱专属。", 120)

	# --- 材料 ---
	_item_material(&"wood", "木材", GameEnums.Rarity.COMMON, Vector2i(3, 7),
		"森林里随处可见的木料，可用于后续合成系统。", 2, 99)
	_item_material(&"slime_gel", "史莱姆凝胶", GameEnums.Rarity.COMMON, Vector2i(5, 7),
		"史莱姆体内凝结的胶质，黏糊糊的。", 3, 99)
	_item_material(&"goblin_fang", "哥布林獠牙", GameEnums.Rarity.UNCOMMON, Vector2i(4, 7),
		"哥布林的獠牙，是它们部族的战利品凭证。", 8, 99)
	_item_material(&"relic_shard", "遗迹碎片", GameEnums.Rarity.RARE, Vector2i(1, 7),
		"刻着古老纹路的碎片，来自森林深处的祭坛。", 25, 99)

	# --- 钥匙 / 卷轴 ---
	_item_material(&"forest_key", "森林钥匙", GameEnums.Rarity.RARE, Vector2i(2, 2),
		"可以打开森林中上锁的宝箱（第二阶段实装）。", 30, 9)
	var scroll := ItemData.new()
	scroll.id = &"ancient_scroll"
	scroll.display_name = "古老卷轴"
	scroll.description = "记载着森林传说的卷轴，可以卖个好价钱。"
	scroll.icon_sheet = "props"
	scroll.icon_cell = Vector2i(5, 3)
	scroll.item_type = GameEnums.ItemType.MATERIAL
	scroll.rarity = GameEnums.Rarity.UNCOMMON
	scroll.max_stack = 99
	scroll.sell_price = 12
	_save(scroll, "items", "ancient_scroll")


func _item_consumable(
	id: StringName, name_cn: String, rarity: int, cell: Vector2i,
	heal: float, mp: float, desc: String, price: int
) -> void:
	var c := ConsumableData.new()
	c.id = id
	c.display_name = name_cn
	c.description = desc
	c.icon_sheet = "props"
	c.icon_cell = cell
	c.item_type = GameEnums.ItemType.CONSUMABLE
	c.rarity = rarity
	c.max_stack = 9
	c.sell_price = price
	c.heal_amount = heal
	c.mp_amount = mp
	c.fx_color = Color("#d94a4a") if heal > 0.0 else Color("#4a8fd9")
	c.use_time = 0.25
	_save(c, "items", String(id))


func _item_material(
	id: StringName, name_cn: String, rarity: int, cell: Vector2i,
	desc: String, price: int, max_stack: int
) -> void:
	var it := ItemData.new()
	it.id = id
	it.display_name = name_cn
	it.description = desc
	it.icon_sheet = "props"
	it.icon_cell = cell
	it.item_type = GameEnums.ItemType.MATERIAL
	it.rarity = rarity
	it.max_stack = max_stack
	it.sell_price = price
	_save(it, "items", String(id))


# ---------------------------------------------------------------------------
# 武器
# ---------------------------------------------------------------------------

func _gen_weapons() -> void:
	# ===== 白色 · 普通（3 把，仅有贴图）=====
	_weapon(&"iron_sword", "铁剑", GameEnums.Rarity.COMMON, GameEnums.WeaponKind.MELEE,
		5.0, 0.38, "森林冒险者的第一把剑。")
	_weapon(&"wooden_club", "木棒", GameEnums.Rarity.COMMON, GameEnums.WeaponKind.MELEE,
		6.5, 0.50, "粗糙但结实，击退效果意外地好。",
		{"knockback": 90.0, "melee_arc_deg": 80.0, "melee_range": 18.0})
	_weapon(&"hunting_bow", "猎弓", GameEnums.Rarity.COMMON, GameEnums.WeaponKind.BOW,
		4.0, 0.55, "游侠的初始武器：朴素、可靠、射程不错。",
		{"bullet_speed": 205.0, "bullet_lifetime": 1.4})

	# ===== 绿色 · 优秀（3 把，仅有贴图）=====
	_weapon(&"fine_blade", "精铁长剑", GameEnums.Rarity.UNCOMMON, GameEnums.WeaponKind.MELEE,
		9.0, 0.34, "锻造工艺明显好过一个档次的剑。")
	_weapon(&"battle_axe", "战斧", GameEnums.Rarity.UNCOMMON, GameEnums.WeaponKind.MELEE,
		12.0, 0.58, "挥击很慢，但一斧下去整片怪都得退。",
		{"knockback": 120.0, "melee_arc_deg": 130.0, "melee_range": 22.0})
	_weapon(&"short_bow", "短弓", GameEnums.Rarity.UNCOMMON, GameEnums.WeaponKind.BOW,
		7.0, 0.44, "拉弓更快，适合边跑边打。",
		{"bullet_speed": 235.0, "bullet_lifetime": 1.3})

	# ===== 蓝色 · 稀有（3 把，仅有贴图）=====
	_weapon(&"knight_greatsword", "骑士重剑", GameEnums.Rarity.RARE, GameEnums.WeaponKind.MELEE,
		16.0, 0.48, "王国骑士制式重剑，剑身刻着家徽。",
		{"melee_arc_deg": 115.0, "melee_range": 26.0, "knockback": 100.0})
	_weapon(&"silver_spear", "银枪", GameEnums.Rarity.RARE, GameEnums.WeaponKind.MELEE,
		13.0, 0.36, "攻击距离最长的近战武器，适合卡位。",
		{"melee_arc_deg": 45.0, "melee_range": 34.0})
	_weapon(&"mithril_bow", "秘银弓", GameEnums.Rarity.RARE, GameEnums.WeaponKind.BOW,
		12.0, 0.40, "秘银弓臂轻若无物，箭矢可以穿透两个目标。",
		{"bullet_speed": 260.0, "bullet_lifetime": 1.6, "pierce": 2})

	# ===== 橙色 · 传奇（3 把，仅有贴图）=====
	_weapon(&"flame_brand", "烈焰之刃", GameEnums.Rarity.LEGENDARY, GameEnums.WeaponKind.MELEE,
		22.0, 0.42, "剑刃永远在燃烧，挥动时会拖出火光。",
		{"melee_arc_deg": 105.0, "melee_range": 27.0, "knockback": 95.0})
	_weapon(&"storm_crossbow", "风暴弩", GameEnums.Rarity.LEGENDARY, GameEnums.WeaponKind.RANGED,
		11.0, 0.30, "一次射出三支带电的弩矢。",
		{"projectile_count": 3, "spread_deg": 14.0, "bullet_speed": 300.0,
		 "bullet_lifetime": 1.4, "magazine": 12, "reload_time": 1.6})
	_weapon(&"arcane_staff", "秘法法杖", GameEnums.Rarity.LEGENDARY, GameEnums.WeaponKind.STAFF,
		20.0, 0.62, "消耗能量发射会自动追踪的秘法弹。",
		{"energy_cost": 6.0, "bullet_speed": 165.0, "bullet_lifetime": 2.2,
		 "homing": true, "magazine": 0})

	# ===== 樱花霰弹枪（橙色 · 传奇 · 第一阶段唯一完整实现）=====
	var cherry := WeaponData.new()
	cherry.id = &"cherry_shotgun"
	cherry.display_name = "樱花霰弹枪"
	cherry.description = "复刻《元气骑士》樱花霰弹枪。\n一次射出 5 枚樱花瓣弹丸，花瓣会在墙上弹一次；\n贴脸时五瓣全中，是全游戏爆发最高的武器。"
	cherry.item_type = GameEnums.ItemType.WEAPON
	cherry.rarity = GameEnums.Rarity.LEGENDARY
	cherry.max_stack = 1
	cherry.sell_price = 320
	cherry.kind = GameEnums.WeaponKind.SHOTGUN
	cherry.damage = 4.5                 # 单枚花瓣伤害
	cherry.projectile_count = 5         # 五瓣散射
	cherry.spread_deg = 34.0
	cherry.fire_rate = 0.62
	cherry.magazine = 6
	cherry.reload_time = 1.50
	cherry.energy_cost = 4.0            # 每发消耗能量（参考原作）
	cherry.bullet_speed = 215.0
	cherry.bullet_lifetime = 0.62       # 霰弹射程短
	cherry.knockback = 34.0
	cherry.crit_bonus = 0.05
	cherry.shake_on_fire = 1.4
	cherry.muzzle_offset = Vector2(13, 0)
	cherry.script_path = "res://scripts/weapons/cherry_shotgun.gd"
	cherry.sfx_fire = "res://assets/audio/sfx/shotgun.wav"
	cherry.sfx_reload = "res://assets/audio/sfx/reload.wav"
	cherry.sfx_empty = "res://assets/audio/sfx/empty.wav"
	cherry.flavor_text = "「花瓣落尽之时，森林归于寂静。」—— 森林射手路线的终点"
	cherry.tags = PackedStringArray(["shotgun", "petal", "cherry", "boss_reward"])
	_save(cherry, "weapons", "cherry_shotgun")


func _weapon(
	id: StringName, name_cn: String, rarity: int, kind: int,
	damage: float, fire_rate: float, desc: String, extra: Dictionary = {}
) -> void:
	var w := WeaponData.new()
	w.id = id
	w.display_name = name_cn
	w.description = desc
	w.item_type = GameEnums.ItemType.WEAPON
	w.rarity = rarity
	w.max_stack = 1
	w.kind = kind
	w.damage = damage
	w.fire_rate = fire_rate
	# 品质影响售价（仅展示用）
	w.sell_price = int([10, 25, 60, 150][rarity]) + int(damage)

	# 按武器类型给一套合理默认值
	match kind:
		GameEnums.WeaponKind.MELEE:
			w.melee_arc_deg = 95.0
			w.melee_range = 23.0
			w.melee_swing_time = 0.18
			w.knockback = 80.0
			w.magazine = 0
		GameEnums.WeaponKind.BOW:
			w.bullet_speed = 220.0
			w.bullet_lifetime = 1.35
			w.knockback = 45.0
			w.magazine = 0        # 弓不需要换弹
			w.crit_bonus = 0.02
		GameEnums.WeaponKind.RANGED:
			w.bullet_speed = 280.0
			w.bullet_lifetime = 1.4
			w.magazine = 12
			w.reload_time = 1.4
			w.knockback = 30.0
		GameEnums.WeaponKind.STAFF:
			w.magazine = 0
			w.knockback = 25.0
		_:
			pass

	# 逐条覆盖
	if extra.has("melee_arc_deg"): w.melee_arc_deg = extra["melee_arc_deg"]
	if extra.has("melee_range"): w.melee_range = extra["melee_range"]
	if extra.has("knockback"): w.knockback = extra["knockback"]
	if extra.has("bullet_speed"): w.bullet_speed = extra["bullet_speed"]
	if extra.has("bullet_lifetime"): w.bullet_lifetime = extra["bullet_lifetime"]
	if extra.has("projectile_count"): w.projectile_count = extra["projectile_count"]
	if extra.has("spread_deg"): w.spread_deg = extra["spread_deg"]
	if extra.has("magazine"): w.magazine = extra["magazine"]
	if extra.has("reload_time"): w.reload_time = extra["reload_time"]
	if extra.has("energy_cost"): w.energy_cost = extra["energy_cost"]
	if extra.has("crit_bonus"): w.crit_bonus = extra["crit_bonus"]
	if extra.has("homing"):
		# 追踪弹用投射物数据表达
		var pd := ProjectileData.new()
		pd.id = StringName("%s_bolt" % id)
		pd.speed = w.bullet_speed
		pd.lifetime = w.bullet_lifetime
		pd.motion = &"homing"
		pd.homing_turn_speed = 4.2
		pd.homing_duration = 1.8
		pd.radius = 4.0
		pd.color = Color("#8fd3f2")
		pd.trail_color = Color("#c9e88a")
		pd.trail_length = 6
		pd.glow = true
		w.projectile_data = pd
	if extra.has("pierce"):
		var pd2 := ProjectileData.new()
		pd2.id = StringName("%s_arrow" % id)
		pd2.speed = w.bullet_speed
		pd2.lifetime = w.bullet_lifetime
		pd2.pierce = extra["pierce"]
		pd2.pierce_damage_keep = 0.85
		pd2.radius = 3.0
		pd2.color = Color("#c9e88a")
		pd2.trail_length = 4
		w.projectile_data = pd2
	_save(w, "weapons", String(id))


# ---------------------------------------------------------------------------
# 角色（游侠）
# ---------------------------------------------------------------------------

func _gen_characters() -> void:
	var r := CharacterData.new()
	r.id = &"ranger"
	r.display_name = "游侠"
	r.description = "参考《元气骑士》游侠设计的机动型射手。\n" \
		+ "生命与护甲偏低，但拥有全游戏最高的基础暴击率，\n" \
		+ "以及独一无二的「翻滚」：翻滚期间无敌，结束后短时间内下一次攻击必定暴击。\n" \
		+ "玩法核心是贴身输出 → 翻滚穿身位 → 暴击爆发。"
	r.sprite_sheet = "player_ranger"
	r.accent_color = Color("#5c8f3a")
	r.unlocked = true
	r.unlock_cost = 0

	# 属性：参考元气骑士游侠（生命 5 / 护甲 4 / 能量 80 / 暴击 10%），
	# 按 ARPG 口径把生命与护甲放大 10 倍
	r.max_hp = 50.0
	r.max_armor = 40.0
	r.max_mp = 80.0
	r.move_speed = 78.0
	r.crit_chance = 0.10
	r.crit_mult = 2.0
	r.melee_damage = 4.0
	r.armor_regen_delay = 2.5
	r.armor_regen_rate = 8.0
	r.mp_regen = 3.0
	r.hp_regen = 0.0
	r.pickup_radius = 26.0

	r.skill_id = &"roll"
	r.skill_name = "翻滚"
	r.skill_description = "向移动方向翻滚一段距离，翻滚期间完全无敌；\n" \
		+ "翻滚结束后 0.65 秒内，下一次攻击必定暴击。\n" \
		+ "冷却 1.2 秒，不消耗能量。"
	r.skill_script = "res://scripts/entities/skills/rogue_roll.gd"
	r.skill_cooldown = 1.20
	r.skill_mp_cost = 0.0
	r.skill_icon = "roll"

	r.start_weapon_id = &"hunting_bow"
	r.start_gold = 0
	r.start_items = [&"hp_potion_small", &"mp_potion_small"]

	r.melee_interval = 0.35
	r.melee_range = 20.0
	_save(r, "characters", "ranger")


# ---------------------------------------------------------------------------
# 敌人
# ---------------------------------------------------------------------------

func _gen_enemies() -> void:
	# ===== 普通小怪 ×5 =====
	_enemy(&"slime", "史莱姆", "slime", GameEnums.EnemyTier.NORMAL, {
		"hp": 18.0, "speed": 30.0, "contact": 4.0, "behavior": &"hopper",
		"radius": 6.0, "xp": 6, "gold": Vector2i(1, 3), "chest_chance": 0.30,
		"detect": 130.0, "desc": "森林里最常见的软体魔物。会一蹦一蹦地扑过来。",
	})
	_enemy(&"bat", "森林蝙蝠", "bat", GameEnums.EnemyTier.NORMAL, {
		"hp": 12.0, "speed": 54.0, "contact": 3.0, "behavior": &"erratic_flyer",
		"radius": 5.0, "hover": 10.0, "xp": 5, "gold": Vector2i(1, 3), "chest_chance": 0.25,
		"detect": 165.0, "desc": "飞得歪歪扭扭，很难打中，但很脆。",
	})
	_enemy(&"mushroom", "蘑菇怪", "mushroom", GameEnums.EnemyTier.NORMAL, {
		"hp": 26.0, "speed": 26.0, "contact": 5.0, "behavior": &"hopper",
		"radius": 6.5, "xp": 8, "gold": Vector2i(2, 4), "chest_chance": 0.35,
		"detect": 140.0, "desc": "孢子鼓鼓囊囊，跳得很重。",
	})
	_enemy(&"goblin", "哥布林剑士", "goblin", GameEnums.EnemyTier.NORMAL, {
		"hp": 30.0, "speed": 42.0, "attack": 7.0, "behavior": &"charger",
		"radius": 6.5, "xp": 10, "gold": Vector2i(2, 5), "chest_chance": 0.40,
		"detect": 170.0, "charge_windup": 0.60, "desc": "会先蓄力再直线冲锋，冲锋前会发抖。",
	})
	_enemy(&"goblin_archer", "哥布林弓手", "goblin_archer", GameEnums.EnemyTier.NORMAL, {
		"hp": 22.0, "speed": 38.0, "attack": 6.0, "behavior": &"ranged_kiter",
		"radius": 6.0, "xp": 10, "gold": Vector2i(2, 5), "chest_chance": 0.40,
		"detect": 200.0, "attack_range": 120.0, "projectile_speed": 150.0,
		"desc": "保持距离放箭，靠近它反而会后退。",
	})

	# ===== 精英 ×2 =====
	_enemy(&"goblin_guard", "哥布林卫士", "goblin_guard", GameEnums.EnemyTier.ELITE, {
		"hp": 120.0, "armor": 25.0, "speed": 44.0, "attack": 13.0,
		"behavior": &"charger", "radius": 7.5, "xp": 40,
		"gold": Vector2i(8, 16), "chest_chance": 1.0, "detect": 190.0,
		"charge_windup": 0.5, "scale": 1.12,
		"desc": "披着重甲的哥布林精锐，冲锋又快又痛。",
	})
	_enemy(&"goblin_chief", "哥布林督军", "goblin", GameEnums.EnemyTier.ELITE, {
		"hp": 95.0, "armor": 12.0, "speed": 50.0, "attack": 11.0,
		"behavior": &"charger", "radius": 7.0, "xp": 40,
		"gold": Vector2i(8, 16), "chest_chance": 1.0, "detect": 210.0,
		"charge_windup": 0.4, "scale": 1.35,
		"modulate": Color(0.78, 0.62, 0.62),
		"desc": "比普通哥布林壮一圈的督军，皮肤泛着暗红。",
	})

	# ===== BOSS ×1 =====
	_enemy(&"goblin_priest", "哥布林大祭司", "goblin_priest", GameEnums.EnemyTier.BOSS, {
		"hp": 900.0, "armor": 60.0, "dr": 0.12, "speed": 36.0, "attack": 15.0,
		"behavior": &"boss_summoner", "radius": 14.0, "xp": 400,
		"gold": Vector2i(60, 120), "chest_chance": 1.0, "detect": 320.0,
		"attack_range": 130.0, "attack_cooldown": 1.9, "attack_windup": 0.75,
		"attack_recover": 0.55, "projectile_count": 5, "projectile_spread_deg": 46.0,
		"projectile_speed": 135.0, "burst_count": 3, "burst_interval": 0.22,
		"scale": 1.0, "desc": "森林深处的统治者。会扇形齐射、环形弹幕，并召唤哥布林援军。",
	})


func _enemy(id: StringName, name_cn: String, sheet: String, tier: int, p: Dictionary) -> void:
	var e := EnemyData.new()
	e.id = id
	e.display_name = name_cn
	e.sheet_key = sheet
	e.tier = tier
	e.description = p.get("desc", "")
	e.max_hp = p.get("hp", 20.0)
	e.armor = p.get("armor", 0.0)
	e.damage_reduction = p.get("dr", 0.0)
	e.move_speed = p.get("speed", 34.0)
	e.contact_damage = p.get("contact", 0.0)
	e.attack_damage = p.get("attack", e.contact_damage)
	e.behavior = p.get("behavior", &"chase_melee")
	e.body_radius = p.get("radius", 7.0)
	e.hover_height = p.get("hover", 0.0)
	e.sprite_scale = p.get("scale", 1.0)
	e.detect_radius = p.get("detect", 150.0)
	e.lose_radius = e.detect_radius * 2.2
	e.attack_range = p.get("attack_range", 22.0)
	e.attack_cooldown = p.get("attack_cooldown", 1.2)
	e.attack_windup = p.get("attack_windup", 0.25)
	e.attack_recover = p.get("attack_recover", 0.35)
	e.projectile_speed = p.get("projectile_speed", 140.0)
	e.projectile_count = p.get("projectile_count", 1)
	e.projectile_spread_deg = p.get("projectile_spread_deg", 0.0)
	e.burst_count = p.get("burst_count", 1)
	e.burst_interval = p.get("burst_interval", 0.12)
	e.charge_windup = p.get("charge_windup", 0.6)
	e.xp_reward = p.get("xp", 8)
	var gold: Vector2i = p.get("gold", Vector2i(1, 4))
	e.gold_min = gold.x
	e.gold_max = gold.y
	e.coin_drop_chance = p.get("coin_chance", 0.6)
	e.chest_drop_chance = p.get("chest_chance", 1.0)
	e.sprite_modulate = p.get("modulate", Color.WHITE)
	e.pack_min = p.get("pack_min", 1)
	e.pack_max = p.get("pack_max", 3)
	e.spawn_weight = p.get("weight", 1.0)
	# 掉落表
	match tier:
		GameEnums.EnemyTier.ELITE: e.loot_table_id = &"enemy_elite"
		GameEnums.EnemyTier.BOSS: e.loot_table_id = &"enemy_boss"
		_: e.loot_table_id = &"enemy_normal"
	# 音效
	e.sfx_hurt = "res://assets/audio/sfx/hurt.wav"
	e.sfx_attack = "res://assets/audio/sfx/enemy_attack.wav"
	e.sfx_die = "res://assets/audio/sfx/enemy_die.wav"
	_save(e, "enemies", String(id))


# ---------------------------------------------------------------------------
# 掉落表
# ---------------------------------------------------------------------------

func _gen_loot_tables() -> void:
	# ===== 普通宝箱（小怪掉落）=====
	var cn := LootTable.new()
	cn.id = &"chest_normal"
	cn.display_name = "普通宝箱"
	cn.roll_count = 2
	cn.empty_weight = 15.0
	cn.weapon_drop_chance = 0.60
	cn.weapon_count_range = Vector2i(1, 1)
	cn.weapon_rarity_weights = [70.0, 25.0, 5.0, 0.0]   # 白70 / 绿25 / 蓝5 / 橙0
	cn.gold_min = 3
	cn.gold_max = 10
	cn.gold_chance = 1.0
	cn.min_results = 1
	cn.max_results = 4
	cn.entries = [
		_loot(&"hp_potion_small", 34.0, 1, 1),
		_loot(&"mp_potion_small", 28.0, 1, 1),
		_loot(&"slime_gel", 26.0, 1, 3),
		_loot(&"wood", 22.0, 1, 3),
	]
	_save(cn, "loot_tables", "chest_normal")

	# ===== 优秀宝箱（精英怪掉落）=====
	var cf := LootTable.new()
	cf.id = &"chest_fine"
	cf.display_name = "优秀宝箱"
	cf.roll_count = 2
	cf.empty_weight = 4.0
	cf.weapon_drop_chance = 1.0
	cf.weapon_count_range = Vector2i(1, 1)
	cf.weapon_rarity_weights = [0.0, 45.0, 45.0, 10.0]  # 绿45 / 蓝45 / 橙10
	cf.extra_weapon_chance = 0.35                       # 额外再来一件
	cf.gold_min = 15
	cf.gold_max = 35
	cf.min_results = 2
	cf.max_results = 5
	cf.entries = [
		_loot(&"hp_potion_large", 30.0, 1, 1),
		_loot(&"mp_potion_large", 24.0, 1, 1),
		_loot(&"goblin_fang", 30.0, 1, 2),
		_loot(&"ancient_scroll", 16.0, 1, 1),
	]
	_save(cf, "loot_tables", "chest_fine")

	# ===== 稀有宝箱（BOSS 掉落）=====
	var cr := LootTable.new()
	cr.id = &"chest_rare"
	cr.display_name = "稀有宝箱"
	cr.roll_count = 3
	cr.empty_weight = 0.0
	cr.weapon_drop_chance = 1.0
	cr.weapon_count_range = Vector2i(2, 3)
	cr.weapon_rarity_weights = [0.0, 0.0, 80.0, 20.0]   # 蓝80 / 橙20
	cr.gold_min = 60
	cr.gold_max = 120
	cr.min_results = 3
	cr.max_results = 7
	cr.entries = [
		_loot(&"hp_potion_large", 30.0, 1, 2),
		_loot(&"mp_potion_large", 26.0, 1, 2),
		_loot(&"relic_shard", 26.0, 1, 2),
		_loot(&"elixir_life", 12.0, 1, 1),
		_loot(&"forest_key", 10.0, 1, 1),
	]
	cr.guaranteed = [_loot(&"forest_key", 1.0, 1, 1)]
	cr.guaranteed_chances = [0.35]
	_save(cr, "loot_tables", "chest_rare")

	# ===== 敌人直接掉落 =====
	var en := LootTable.new()
	en.id = &"enemy_normal"
	en.display_name = "小怪掉落"
	en.roll_count = 1
	en.empty_weight = 68.0
	en.weapon_drop_chance = 0.05
	en.weapon_rarity_weights = [80.0, 20.0, 0.0, 0.0]
	en.entries = [
		_loot(&"slime_gel", 30.0, 1, 1),
		_loot(&"wood", 26.0, 1, 2),
		_loot(&"hp_potion_small", 20.0, 1, 1),
		_loot(&"mp_potion_small", 16.0, 1, 1),
	]
	_save(en, "loot_tables", "enemy_normal")

	var ee := LootTable.new()
	ee.id = &"enemy_elite"
	ee.display_name = "精英掉落"
	ee.roll_count = 2
	ee.empty_weight = 22.0
	ee.weapon_drop_chance = 0.30
	ee.weapon_rarity_weights = [10.0, 60.0, 30.0, 0.0]
	ee.entries = [
		_loot(&"goblin_fang", 30.0, 1, 2),
		_loot(&"hp_potion_large", 24.0, 1, 1),
		_loot(&"mp_potion_large", 20.0, 1, 1),
		_loot(&"ancient_scroll", 14.0, 1, 1),
		_loot(&"relic_shard", 12.0, 1, 1),
	]
	_save(ee, "loot_tables", "enemy_elite")

	var eb := LootTable.new()
	eb.id = &"enemy_boss"
	eb.display_name = "BOSS 掉落"
	eb.roll_count = 4
	eb.empty_weight = 0.0
	eb.weapon_drop_chance = 1.0
	eb.weapon_count_range = Vector2i(1, 2)
	eb.weapon_rarity_weights = [0.0, 0.0, 85.0, 15.0]
	eb.gold_min = 40
	eb.gold_max = 80
	eb.min_results = 4
	eb.entries = [
		_loot(&"relic_shard", 30.0, 1, 3),
		_loot(&"hp_potion_large", 26.0, 1, 2),
		_loot(&"mp_potion_large", 22.0, 1, 2),
		_loot(&"elixir_life", 12.0, 1, 1),
		_loot(&"forest_key", 10.0, 1, 1),
	]
	_save(eb, "loot_tables", "enemy_boss")


func _loot(id: StringName, weight: float, cmin: int, cmax: int) -> LootEntry:
	var e := LootEntry.new()
	e.item_id = id
	e.weight = weight
	e.count_min = cmin
	e.count_max = cmax
	return e


# ---------------------------------------------------------------------------
# 技能树
# ---------------------------------------------------------------------------

func _gen_skill_tree() -> void:
	var tree := SkillTreeData.new()
	tree.id = &"global_tree"
	tree.display_name = "全局技能树"
	tree.description = "跨角色、跨关卡、跨存档保留的通用成长树。\n" \
		+ "每升一级获得 1 点技能点。四条分支：生存 / 进攻 / 敏捷 / 幸运。"
	tree.grid_size = Vector2i(7, 5)
	var nodes: Array[SkillNodeData] = []

	# ===== 生存分支 vitality =====
	nodes.append(_skill(&"v_hp1", "强健体魄", "vitality", Vector2i(1, 4), "vitality", 3,
		[_eff(GameEnums.StatKind.MAX_HP, 8.0)],
		"生命上限 +8 / 级"))
	nodes.append(_skill(&"v_hp2", "生命涌动", "vitality", Vector2i(1, 3), "vitality", 3,
		[_eff(GameEnums.StatKind.MAX_HP, 14.0)],
		"生命上限 +14 / 级", [&"v_hp1"], [2]))
	nodes.append(_skill(&"v_armor1", "铁壁", "vitality", Vector2i(2, 4), "vitality", 3,
		[_eff(GameEnums.StatKind.MAX_ARMOR, 6.0)],
		"护甲上限 +6 / 级"))
	nodes.append(_skill(&"v_armor2", "护甲强化", "vitality", Vector2i(2, 3), "vitality", 3,
		[_eff(GameEnums.StatKind.ARMOR_REGEN_RATE, 1.6), _eff(GameEnums.StatKind.ARMOR_REGEN_DELAY, -0.25)],
		"护甲回复速度 +1.6/级，回复延迟 -0.25s/级", [&"v_armor1"], [2]))
	nodes.append(_skill(&"v_regen", "再生之息", "vitality", Vector2i(1, 2), "vitality", 2,
		[_eff(GameEnums.StatKind.HP_REGEN, 0.6)],
		"每秒回复 0.6 生命 / 级", [&"v_hp2"], [2]))

	# ===== 进攻分支 offense =====
	nodes.append(_skill(&"o_dmg1", "锋利", "offense", Vector2i(3, 4), "offense", 3,
		[_eff(GameEnums.StatKind.DAMAGE_MULT, 0.05, true)],
		"全部伤害 +5% / 级"))
	nodes.append(_skill(&"o_crit1", "精准打击", "offense", Vector2i(4, 4), "offense", 3,
		[_eff(GameEnums.StatKind.CRIT_CHANCE, 0.03)],
		"暴击率 +3% / 级"))
	nodes.append(_skill(&"o_dmg2", "战意", "offense", Vector2i(3, 3), "offense", 3,
		[_eff(GameEnums.StatKind.DAMAGE_MULT, 0.07, true)],
		"全部伤害 +7% / 级", [&"o_dmg1"], [2]))
	nodes.append(_skill(&"o_crit2", "致命一击", "offense", Vector2i(4, 3), "offense", 3,
		[_eff(GameEnums.StatKind.CRIT_MULT, 0.18)],
		"暴击伤害 +18% / 级", [&"o_crit1"], [2]))
	nodes.append(_skill(&"o_melee", "手刀专精", "offense", Vector2i(3, 2), "offense", 3,
		[_eff(GameEnums.StatKind.MELEE_DAMAGE, 3.0)],
		"徒手伤害 +3 / 级", [&"o_dmg2"], [2]))
	nodes.append(_skill(&"o_keystone", "狂怒之心", "offense", Vector2i(4, 2), "offense", 1,
		[_eff(GameEnums.StatKind.DAMAGE_MULT, 0.15, true), _eff(GameEnums.StatKind.CRIT_CHANCE, 0.05)],
		"全部伤害 +15%，暴击率 +5%", [&"o_crit2", &"o_dmg2"], [2, 2], true))

	# ===== 敏捷分支 mobility =====
	nodes.append(_skill(&"m_speed1", "疾风步", "mobility", Vector2i(5, 4), "mobility", 3,
		[_eff(GameEnums.StatKind.MOVE_SPEED, 4.0)],
		"移动速度 +4 / 级"))
	nodes.append(_skill(&"m_reload", "快速换弹", "mobility", Vector2i(5, 3), "mobility", 3,
		[_eff(GameEnums.StatKind.RELOAD_SPEED, 0.10, true)],
		"换弹速度 +10% / 级"))
	nodes.append(_skill(&"m_fire", "急速射击", "mobility", Vector2i(5, 2), "mobility", 3,
		[_eff(GameEnums.StatKind.FIRE_RATE, 0.08, true)],
		"射速 +8% / 级", [&"m_reload"], [2]))
	nodes.append(_skill(&"m_roll1", "翻滚精通", "mobility", Vector2i(6, 4), "mobility", 3,
		[_eff(GameEnums.StatKind.ROLL_COOLDOWN, -0.10, true)],
		"翻滚冷却 -10% / 级"))
	nodes.append(_skill(&"m_roll2", "翻滚距离", "mobility", Vector2i(6, 3), "mobility", 2,
		[_eff(GameEnums.StatKind.ROLL_DISTANCE, 12.0)],
		"翻滚距离 +12 像素 / 级", [&"m_roll1"], [1]))
	nodes.append(_skill(&"m_keystone", "双翻滚", "mobility", Vector2i(6, 2), "mobility", 1,
		[], "翻滚可以连续使用两次（充能 +1）", [&"m_roll1"], [3], true,
		PackedStringArray(["double_roll"])))

	# ===== 幸运分支 fortune =====
	nodes.append(_skill(&"f_luck1", "幸运", "fortune", Vector2i(0, 4), "fortune", 3,
		[_eff(GameEnums.StatKind.LUCK, 0.8)],
		"幸运 +0.8 / 级（提高高品质掉落概率）"))
	nodes.append(_skill(&"f_pickup", "磁力吸附", "fortune", Vector2i(0, 3), "fortune", 2,
		[_eff(GameEnums.StatKind.PICKUP_RANGE, 14.0)],
		"拾取范围 +14 / 级", [&"f_luck1"], [1]))
	nodes.append(_skill(&"f_mp", "能量涌动", "fortune", Vector2i(0, 2), "fortune", 3,
		[_eff(GameEnums.StatKind.MAX_MP, 12.0), _eff(GameEnums.StatKind.MP_REGEN, 0.9)],
		"能量上限 +12 / 级，能量回复 +0.9/s / 级"))
	nodes.append(_skill(&"f_keystone", "贪婪之心", "fortune", Vector2i(0, 1), "fortune", 1,
		[_eff(GameEnums.StatKind.LUCK, 2.5), _eff(GameEnums.StatKind.PICKUP_RANGE, 20.0)],
		"幸运 +2.5，拾取范围 +20", [&"f_luck1"], [3], true))
	nodes.append(_skill(&"f_cherry", "樱花精通", "fortune", Vector2i(1, 1), "fortune", 1,
		[], "樱花霰弹枪：每发多射 1 枚花瓣，且散布收紧 20%",
		[&"f_luck1"], [2], true, PackedStringArray(["cherry_mastery"])))

	# 自动连线辅助：让排布更整齐（按 grid_position 排序）
	nodes.sort_custom(func(a: SkillNodeData, b: SkillNodeData) -> bool:
		if a.grid_position.y != b.grid_position.y:
			return a.grid_position.y < b.grid_position.y
		return a.grid_position.x < b.grid_position.x)
	tree.nodes = nodes
	_save(tree, "skills", "global_tree")


func _eff(stat: int, per_level: float, is_mult: bool = false) -> StatEffect:
	var e := StatEffect.new()
	e.stat = stat
	e.per_level = per_level
	e.is_mult = is_mult
	return e


func _skill(
	id: StringName, name_cn: String, branch: StringName, grid: Vector2i, _b: String,
	max_level: int, effects: Array, desc: String,
	prereq: Array = [], prereq_lv: Array = [], keystone: bool = false,
	tags: PackedStringArray = PackedStringArray()
) -> SkillNodeData:
	var n := SkillNodeData.new()
	n.id = id
	n.display_name = name_cn
	n.branch = branch
	n.grid_position = grid
	n.max_level = max_level
	n.cost_per_level = 1
	n.required_player_level = 1
	n.description = desc
	var typed: Array[StatEffect] = []
	for e in effects:
		typed.append(e)
	n.effects = typed
	var pre: Array[StringName] = []
	for p in prereq:
		pre.append(StringName(p))
	n.prerequisites = pre
	var prelv: Array[int] = []
	for p in prereq_lv:
		prelv.append(int(p))
	n.prerequisite_levels = prelv
	n.is_keystone = keystone
	n.granted_tags = tags
	n.icon_id = _icon_for_branch(branch, keystone)
	return n


func _icon_for_branch(branch: StringName, keystone: bool) -> String:
	match branch:
		&"vitality": return "vitality"
		&"offense": return "crit" if keystone else "precision"
		&"mobility": return "roll" if keystone else "swift"
		&"fortune": return "magnet"
	return "multishot"


# ---------------------------------------------------------------------------
# 投射物预设
# ---------------------------------------------------------------------------

func _gen_projectiles() -> void:
	_proj(&"bullet_basic", &"straight", 280.0, 1.4, 3.0, Color("#ffd35c"), 4)
	_proj(&"arrow", &"straight", 240.0, 1.5, 2.5, Color("#c9e88a"), 4)
	_proj(&"enemy_bolt", &"straight", 150.0, 1.9, 3.5, Color("#d94a4a"), 3)
	_proj(&"boss_orb", &"straight", 135.0, 2.2, 4.5, Color("#b44ac9"), 5)

	# 樱花花瓣：可弹墙一次、伤害与速度衰减
	var petal := ProjectileData.new()
	petal.id = &"cherry_petal"
	petal.speed = 215.0
	petal.lifetime = 0.62
	petal.motion = &"straight"
	petal.radius = 3.0
	petal.max_bounces = 1
	petal.bounce_damping = 0.88
	petal.bounce_damage_keep = 0.75
	petal.pierce = 0
	petal.damage_mult = 1.0
	petal.color = Color("#f28fc9")
	petal.trail_color = Color("#f9c8e4")
	petal.trail_length = 5
	petal.rotate_to_direction = true
	petal.hit_vfx = &"petal"
	_save(petal, "projectiles", "cherry_petal")


func _proj(
	id: StringName, motion: StringName, speed: float, life: float,
	radius: float, color: Color, trail: int
) -> void:
	var p := ProjectileData.new()
	p.id = id
	p.motion = motion
	p.speed = speed
	p.lifetime = life
	p.radius = radius
	p.color = color
	p.trail_color = color
	p.trail_length = trail
	p.rotate_to_direction = true
	p.hit_vfx = &"spark"
	_save(p, "projectiles", String(id))


# ---------------------------------------------------------------------------
# 关卡配置
# ---------------------------------------------------------------------------

func _gen_levels() -> void:
	var c := ForestMapConfig.new()
	c.room_count_min = 9
	c.room_count_max = 13
	c.room_interior = Vector2i(22, 16)
	c.cell_pitch = Vector2i(30, 24)
	c.corridor_width = 3
	c.max_attempts = 400
	c.loop_chance = 0.18
	c.treasure_rooms = 2
	c.elite_rooms = 2
	c.boss_at_dead_end = true
	c.enemies_per_room = Vector2i(3, 6)
	c.enemies_per_elite_room = Vector2i(2, 4)
	c.enemy_wall_margin = 3
	c.enemy_min_spacing = 3.0
	c.tree_density = 0.055
	c.rock_density = 0.030
	c.bush_density = 0.10
	c.corridor_decor_density = 0.03
	c.tree_has_collision = true
	c.rock_has_collision = true
	c.chests_per_treasure_room = Vector2i(1, 2)
	c.room_chest_chance = 0.25
	c.treasure_chest_tier = GameEnums.ChestTier.FINE
	c.camera_zoom = 1.0
	_save(c, "levels", "forest_config")
