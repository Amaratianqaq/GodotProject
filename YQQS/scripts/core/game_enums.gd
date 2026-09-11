class_name GameEnums
extends RefCounted
## 全局枚举与品质常量 —— 整个项目的「公共词表」。
##
## 【框架约束】
## 任何模块都不允许再自行定义与品质 / 伤害类型 / 稀有度相关的枚举或魔法数字，
## 一律引用本文件。新增枚举值必须追加在末尾，禁止插入到中间（会破坏存档兼容）。

# ---------------------------------------------------------------------------
# 品质
# ---------------------------------------------------------------------------

## 第一阶段品质：白色（普通）→ 绿色（优秀）→ 蓝色（稀有）→ 橙色（传奇）
enum Rarity {
	COMMON,     ## 白色 · 普通
	UNCOMMON,   ## 绿色 · 优秀
	RARE,       ## 蓝色 · 稀有
	LEGENDARY,  ## 橙色 · 传奇
}

const RARITY_COUNT := 4

const RARITY_NAMES := {
	Rarity.COMMON: "普通",
	Rarity.UNCOMMON: "优秀",
	Rarity.RARE: "稀有",
	Rarity.LEGENDARY: "传奇",
}

const RARITY_COLORS := {
	Rarity.COMMON: Color("#c8c5bd"),
	Rarity.UNCOMMON: Color("#5c8f3a"),
	Rarity.RARE: Color("#4a8fd9"),
	Rarity.LEGENDARY: Color("#f2a13b"),
}

## 品质权重基准（掉落用）。数值越大越常见。
const RARITY_BASE_WEIGHT := {
	Rarity.COMMON: 100.0,
	Rarity.UNCOMMON: 40.0,
	Rarity.RARE: 12.0,
	Rarity.LEGENDARY: 2.5,
}

## 品质对武器数值的期望倍率（后续实现武器代码时使用，第一阶段仅作参考）
const RARITY_STAT_MULT := {
	Rarity.COMMON: 1.00,
	Rarity.UNCOMMON: 1.25,
	Rarity.RARE: 1.60,
	Rarity.LEGENDARY: 2.10,
}


static func rarity_name(r: int) -> String:
	return RARITY_NAMES.get(r, "未知")


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS.get(r, Color.WHITE)


static func rarity_from_string(s: String) -> int:
	match s.to_lower():
		"common", "white", "普通", "白色": return Rarity.COMMON
		"uncommon", "green", "优秀", "绿色": return Rarity.UNCOMMON
		"rare", "blue", "稀有", "蓝色": return Rarity.RARE
		"legendary", "orange", "传奇", "橙色": return Rarity.LEGENDARY
	return Rarity.COMMON


# ---------------------------------------------------------------------------
# 物品
# ---------------------------------------------------------------------------

enum ItemType {
	WEAPON,
	CONSUMABLE,
	MATERIAL,
	GOLD,
	KEY,
	CHEST,
}

enum WeaponKind {
	NONE,
	MELEE,      ## 近战（剑/斧/锤）
	RANGED,     ## 单发远程（手枪/步枪）
	SHOTGUN,    ## 霰弹（多弹丸散射）
	BOW,        ## 弓/弩（蓄力）
	STAFF,      ## 法杖（消耗能量）
}


# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

enum DamageType { PHYSICAL, ENERGY, POISON, FIRE, TRUE }

enum Faction { PLAYER, ENEMY, NEUTRAL }

enum EnemyTier {
	NORMAL,   ## 普通小怪
	ELITE,    ## 精英怪
	BOSS,     ## 首领
}

enum ChestTier {
	NORMAL,   ## 普通宝箱 —— 小怪掉落
	FINE,     ## 优秀宝箱 —— 精英怪掉落
	RARE,     ## 稀有宝箱 —— BOSS 掉落
}


# ---------------------------------------------------------------------------
# 地图 / 关卡
# ---------------------------------------------------------------------------

enum RoomKind {
	ENTRANCE,   ## 出生房
	COMBAT,     ## 普通战斗房
	TREASURE,   ## 宝箱房
	ELITE,      ## 精英房
	BOSS,       ## BOSS 房
	SHOP,       ## 商店房（第二阶段）
	EMPTY,      ## 空地/连接房
}

## 方向（用于房间连通）
enum Dir { N, E, S, W }

const DIR_VECTORS := {
	Dir.N: Vector2i(0, -1),
	Dir.E: Vector2i(1, 0),
	Dir.S: Vector2i(0, 1),
	Dir.W: Vector2i(-1, 0),
}

const DIR_OPPOSITE := {
	Dir.N: Dir.S,
	Dir.E: Dir.W,
	Dir.S: Dir.N,
	Dir.W: Dir.E,
}


# ---------------------------------------------------------------------------
# 技能树
# ---------------------------------------------------------------------------

enum StatKind {
	MAX_HP,        ## 生命上限
	MAX_ARMOR,     ## 护甲上限
	MAX_MP,        ## 能量上限
	MOVE_SPEED,    ## 移动速度
	DAMAGE_MULT,   ## 全局伤害倍率
	MELEE_DAMAGE,  ## 手刀伤害
	CRIT_CHANCE,   ## 暴击率
	CRIT_MULT,     ## 暴击倍率
	FIRE_RATE,     ## 射速
	RELOAD_SPEED,  ## 换弹速度
	MP_REGEN,      ## 能量回复
	HP_REGEN,      ## 生命回复
	PICKUP_RANGE,  ## 拾取范围
	ROLL_COOLDOWN, ## 翻滚冷却
	ROLL_DISTANCE, ## 翻滚距离
	LUCK,          ## 幸运（提升品质掉率）
	ARMOR_REGEN_DELAY, ## 护甲开始回复的延迟
	ARMOR_REGEN_RATE,  ## 护甲回复速度（点/秒）
}

const STAT_NAMES := {
	StatKind.MAX_HP: "生命上限",
	StatKind.MAX_ARMOR: "护甲上限",
	StatKind.MAX_MP: "能量上限",
	StatKind.MOVE_SPEED: "移动速度",
	StatKind.DAMAGE_MULT: "伤害加成",
	StatKind.MELEE_DAMAGE: "手刀伤害",
	StatKind.CRIT_CHANCE: "暴击率",
	StatKind.CRIT_MULT: "暴击伤害",
	StatKind.FIRE_RATE: "射速",
	StatKind.RELOAD_SPEED: "换弹速度",
	StatKind.MP_REGEN: "能量回复",
	StatKind.HP_REGEN: "生命回复",
	StatKind.PICKUP_RANGE: "拾取范围",
	StatKind.ROLL_COOLDOWN: "翻滚冷却",
	StatKind.ROLL_DISTANCE: "翻滚距离",
	StatKind.LUCK: "幸运",
	StatKind.ARMOR_REGEN_DELAY: "护甲回复延迟",
	StatKind.ARMOR_REGEN_RATE: "护甲回复速度",
}

## 该属性是否以百分比显示
const STAT_IS_PERCENT := {
	StatKind.DAMAGE_MULT: true,
	StatKind.CRIT_CHANCE: true,
	StatKind.ROLL_COOLDOWN: true,
}


static func stat_name(k: int) -> String:
	return STAT_NAMES.get(k, "未知属性")


static func format_stat(k: int, v: float) -> String:
	if STAT_IS_PERCENT.get(k, false):
		return "%+.1f%%" % (v * 100.0)
	if absf(v - roundf(v)) < 0.001:
		return "%+d" % int(roundf(v))
	return "%+.2f" % v


# ---------------------------------------------------------------------------
# 场景 ID
# ---------------------------------------------------------------------------

const SCENE_LOBBY := "lobby"
const SCENE_FOREST := "forest"

const SCENE_PATHS := {
	SCENE_LOBBY: "res://scenes/lobby/Lobby.tscn",
	SCENE_FOREST: "res://scenes/levels/forest/ForestLevel.tscn",
}


# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://save_slot_0.save"
