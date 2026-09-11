class_name Atlas
extends RefCounted
## 精灵图集索引表 —— 代码与美术之间的唯一契约。
##
## 【框架约束】
## 1. 代码里 **禁止** 出现裸路径 PNG 或手写 Rect2 切图；一律走 Atlas.frame()。
## 2. 新增美术资源 → 在本文件登记表格式，再导出。
## 3. 所有图集必须关闭过滤（项目已设 default_texture_filter=0 最近邻）。

const DIR := "res://assets/sprites/"

## 图集元数据：cell 单元格边长（正方形），cols/rows 网格尺寸
const SHEETS := {
	"player_ranger":        {"file": "player_ranger.png",        "cell": 32, "cols": 4, "rows": 4},
	# --- 敌人图集：4x4（docs/10 §4.2 的选定方案）---
	# 旧版是 3x1（待机/走A/走B）。新版 16 格提供待机/走/攻击/受击/死亡/施法六类动作，
	# 与《元气骑士前传》的动作量匹配。帧号语义见 ENEMY_ANIMS。
	"enemy_slime":          {"file": "enemy_slime.png",          "cell": 32, "cols": 4, "rows": 4},
	"enemy_bat":            {"file": "enemy_bat.png",            "cell": 32, "cols": 4, "rows": 4},
	"enemy_mushroom":       {"file": "enemy_mushroom.png",       "cell": 32, "cols": 4, "rows": 4},
	"enemy_goblin":         {"file": "enemy_goblin.png",         "cell": 32, "cols": 4, "rows": 4},
	"enemy_goblin_archer":  {"file": "enemy_goblin_archer.png",  "cell": 32, "cols": 4, "rows": 4},
	"enemy_goblin_guard":   {"file": "enemy_goblin_guard.png",   "cell": 32, "cols": 4, "rows": 4},
	"boss_goblin_priest":   {"file": "boss_goblin_priest.png",   "cell": 64, "cols": 4, "rows": 4},
	"props":                {"file": "props.png",                "cell": 16, "cols": 16, "rows": 8},
	"weapons":              {"file": "weapons.png",              "cell": 24, "cols": 3, "rows": 4},
	"weapon_cherry_shotgun": {"file": "weapon_cherry_shotgun.png", "cell": 48, "cols": 1, "rows": 1},
	"tileset_forest":       {"file": "tileset_forest.png",       "cell": 16, "cols": 8, "rows": 8},
	# --- 双网格地表图集（新管线）---
	# 每种地形占 4×4 格，四种地形按 2×2 拼成 16×16 格。
	# 索引/槽位的换算一律走 DualGrid，**不要**在这里或别处手写取帧逻辑。
	# 详见 docs/10_美术素材规格与双网格瓦片契约.md §5
	"tileset_forest_ground": {"file": "tileset_forest_ground.png", "cell": 16, "cols": 16, "rows": 16},
	# --- 墙体/建筑图集（仍是传统 blob，不做双网格）---
	"tileset_forest_wall":  {"file": "tileset_forest_wall.png",   "cell": 16, "cols": 8, "rows": 8},
	"ui_panel":             {"file": "ui_panel.png",             "cell": 64, "cols": 1, "rows": 1},
	"ui_bar":               {"file": "ui_bar.png",               "cell": 16, "cols": 4, "rows": 2},
	# ui_bar 是"上血条 / 下蓝条"的一整张可拉伸图，不是图集 —— cols/rows 只用于登记。
	# 同样地，ui_bar_armor 与 ui_frame_rarity 下面都单独说明语义。
	"ui_bar_armor":         {"file": "ui_bar_armor.png",         "cell": 16, "cols": 4, "rows": 1},
	"ui_frame_rarity":      {"file": "ui_frame_rarity.png",      "cell": 16, "cols": 4, "rows": 1},
	# --- 特效序列图（帧序列，横向排列）---
	# 旧实现里命中火花/枪口闪光只是 props.png 里的**单张静态图**，
	# 靠代码改 scale/rotation 硬凑动感。序列图能让光效本身有形状变化。
	# 【尚未接入代码】CombatFx 目前仍用 props 里的单帧；这些图已按契约备好，
	# 换用它们需要改 combat_fx.gd（见 docs/10 §3.5）。
	"vfx_hit_spark":        {"file": "vfx_hit_spark.png",        "cell": 16, "cols": 6, "rows": 1},
	"vfx_muzzle_flash":     {"file": "vfx_muzzle_flash.png",     "cell": 16, "cols": 6, "rows": 1},
	"vfx_petal":            {"file": "vfx_petal.png",            "cell": 8,  "cols": 8, "rows": 2},
	"vfx_orb":              {"file": "vfx_orb.png",              "cell": 16, "cols": 4, "rows": 1},
	"vfx_arrow":            {"file": "vfx_arrow.png",            "cell": 16, "cols": 3, "rows": 1},
}

static var _texture_cache: Dictionary = {}


## 取得整张贴图（带缓存）
static func sheet(name: String) -> Texture2D:
	if _texture_cache.has(name):
		return _texture_cache[name]
	if not SHEETS.has(name):
		push_warning("[Atlas] 未登记的图集: %s" % name)
		return null
	var path: String = DIR + SHEETS[name]["file"]
	if not ResourceLoader.exists(path):
		push_warning("[Atlas] 贴图不存在: %s（请先运行 tools/gen_pixel_assets.gd）" % path)
		return null
	var tex: Texture2D = load(path)
	_texture_cache[name] = tex
	return tex


## 按格子坐标取帧
static func frame(sheet_name: String, col: int, row: int) -> AtlasTexture:
	var meta: Dictionary = SHEETS.get(sheet_name, {})
	if meta.is_empty():
		return null
	var tex := sheet(sheet_name)
	if tex == null:
		return null
	var c: int = meta["cell"]
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * c, row * c, c, c)
	at.filter_clip = true
	return at


## 按线性索引取帧（row * cols + col）
static func cell(sheet_name: String, index: int) -> AtlasTexture:
	var meta: Dictionary = SHEETS.get(sheet_name, {})
	if meta.is_empty():
		return null
	var cols: int = meta["cols"]
	return frame(sheet_name, index % cols, index / cols)


# ---------------------------------------------------------------------------
# 玩家帧（player_ranger.png，4x4）
# ---------------------------------------------------------------------------

const P_IDLE_DOWN := Vector2i(0, 0)
const P_WALK_A_DOWN := Vector2i(1, 0)
const P_WALK_B_DOWN := Vector2i(2, 0)
const P_ROLL_DOWN := Vector2i(3, 0)

const P_IDLE_UP := Vector2i(0, 1)
const P_WALK_A_UP := Vector2i(1, 1)
const P_WALK_B_UP := Vector2i(2, 1)
const P_ROLL_UP := Vector2i(3, 1)

const P_IDLE_SIDE := Vector2i(0, 2)
const P_WALK_A_SIDE := Vector2i(1, 2)
const P_WALK_B_SIDE := Vector2i(2, 2)
const P_ROLL_SIDE := Vector2i(3, 2)

const P_HURT := Vector2i(0, 3)
const P_ATTACK := Vector2i(1, 3)
const P_DEAD := Vector2i(2, 3)
const P_DASH := Vector2i(3, 3)


static func player_frame(dir: Vector2, frame_index: int) -> AtlasTexture:
	## dir: 朝向向量；frame_index: 0 待机 / 1 行走A / 2 行走B / 3 翻滚
	var row := 2  # 侧面
	if absf(dir.y) > absf(dir.x):
		row = 0 if dir.y > 0.0 else 1
	var f := frame("player_ranger", clampi(frame_index, 0, 3), row)
	return f


# ---------------------------------------------------------------------------
# 敌人帧
# ---------------------------------------------------------------------------

const ENEMY_SHEETS := {
	"slime": "enemy_slime",
	"bat": "enemy_bat",
	"mushroom": "enemy_mushroom",
	"goblin": "enemy_goblin",
	"goblin_archer": "enemy_goblin_archer",
	"goblin_guard": "enemy_goblin_guard",
	"goblin_priest": "boss_goblin_priest",
}

## 动画名 → 该动画使用的帧索引序列（每帧 1 格，4x4 网格）
##
## 帧号语义（与 tools/refart/gen_chars.gd 的组装顺序一致，docs/10 §4.2）：
##   row 0: 0 待机   1 走A   2 走B   3 走C/落地
##   row 1: 4 攻击A  5 攻击B 6 攻击C 7 攻击D
##   row 2: 8 受击   9 眩晕  10 死亡A 11 死亡B
##   row 3: 12 警告  13 施法A 14 施法B 15 特殊
##
## 【为什么 idle 用 [0,3] 而不是只 [0]】双帧呼吸比单帧生动，
## 而 0/3 在四张表里都是同一姿势，看不出跳变。
## 【为什么 walk 用 [1,0,2,0]】起步—中位—落脚—中位，是 4 拍循环的标准做法。
const ENEMY_ANIMS := {
	"idle": [0, 3],
	"walk": [1, 0, 2, 0],
	"attack": [4, 5, 6, 7],
	"hurt": [8],
	"die": [10, 11],
	"cast": [13, 14],
}


static func enemy_frame(sheet_key: String, anim: String, step: int) -> AtlasTexture:
	var sheet_name: String = ENEMY_SHEETS.get(sheet_key, "enemy_slime")
	var seq: Array = ENEMY_ANIMS.get(anim, [0])
	var idx: int = seq[step % seq.size()]
	return cell(sheet_name, idx)


# ---------------------------------------------------------------------------
# 道具帧（props.png，16 列 x 8 行，每格 16px）
# ---------------------------------------------------------------------------

const CHEST_CLOSED := {
	GameEnums.ChestTier.NORMAL: Vector2i(0, 0),
	GameEnums.ChestTier.FINE: Vector2i(2, 0),
	GameEnums.ChestTier.RARE: Vector2i(4, 0),
}
const CHEST_OPEN := {
	GameEnums.ChestTier.NORMAL: Vector2i(1, 0),
	GameEnums.ChestTier.FINE: Vector2i(3, 0),
	GameEnums.ChestTier.RARE: Vector2i(5, 0),
}

const PROP_COIN_1 := Vector2i(0, 1)
const PROP_COIN_2 := Vector2i(1, 1)
const PROP_COIN_3 := Vector2i(2, 1)
const PROP_COIN_4 := Vector2i(3, 1)

const PROP_HEART := Vector2i(0, 2)
const PROP_MANA := Vector2i(1, 2)
const PROP_KEY := Vector2i(2, 2)
const PROP_PORTAL := Vector2i(3, 2)
const PROP_EXIT := Vector2i(4, 2)
const PROP_POUCH := Vector2i(5, 2)

const PROP_SHADOW := Vector2i(0, 3)
const PROP_HIT_SPARK := Vector2i(1, 3)
const PROP_MUZZLE_FLASH := Vector2i(2, 3)
const PROP_POTION_HP := Vector2i(3, 3)
const PROP_POTION_MP := Vector2i(4, 3)
const PROP_SCROLL := Vector2i(5, 3)

## 技能图标（第 4 行）
const SKILL_ICONS := {
	"roll": Vector2i(0, 4),
	"precision": Vector2i(1, 4),
	"multishot": Vector2i(2, 4),
	"crit": Vector2i(3, 4),
	"vitality": Vector2i(4, 4),
	"energy": Vector2i(5, 4),
	"magnet": Vector2i(6, 4),
	"swift": Vector2i(7, 4),
}

## UI 图标（第 5 行）
const UI_ICONS := {
	"coin": Vector2i(0, 5),
	"bag": Vector2i(1, 5),
	"warehouse": Vector2i(2, 5),
	"skilltree": Vector2i(3, 5),
	"gear": Vector2i(4, 5),
	"close": Vector2i(5, 5),
	"arrow": Vector2i(6, 5),
	"lock": Vector2i(7, 5),
}

## 品质边框（第 6 行）
const RARITY_FRAME := {
	GameEnums.Rarity.COMMON: Vector2i(0, 6),
	GameEnums.Rarity.UNCOMMON: Vector2i(1, 6),
	GameEnums.Rarity.RARE: Vector2i(2, 6),
	GameEnums.Rarity.LEGENDARY: Vector2i(3, 6),
}

## 场景装饰（第 7 行）
const DECO_DOOR := Vector2i(0, 7)
const DECO_TORCH := Vector2i(1, 7)
const DECO_BARREL := Vector2i(2, 7)
const DECO_CRATE := Vector2i(3, 7)
const DECO_BONES := Vector2i(4, 7)
const DECO_WEB := Vector2i(5, 7)


static func prop(v: Vector2i) -> AtlasTexture:
	return frame("props", v.x, v.y)


static func skill_icon(id: String) -> AtlasTexture:
	if not SKILL_ICONS.has(id):
		return frame("props", 0, 4)
	var v: Vector2i = SKILL_ICONS[id]
	return frame("props", v.x, v.y)


static func ui_icon(id: String) -> AtlasTexture:
	if not UI_ICONS.has(id):
		return null
	var v: Vector2i = UI_ICONS[id]
	return frame("props", v.x, v.y)


static func rarity_frame(r: int) -> AtlasTexture:
	var v: Vector2i = RARITY_FRAME.get(r, Vector2i(0, 6))
	return frame("props", v.x, v.y)


# ---------------------------------------------------------------------------
# 武器图标（weapons.png，3 列 x 4 行，每格 24px）
# 行 = 品质（0 白 / 1 绿 / 2 蓝 / 3 橙），列 = 该品质第几把
# ---------------------------------------------------------------------------

## 武器 id → 图集格子。48x48 的樱花霰弹枪单独用 CHERRY_SHOTGUN_SHEET。
const WEAPON_FRAMES := {
	# 白色 · 普通
	"iron_sword": Vector2i(0, 0),
	"wooden_club": Vector2i(1, 0),
	"hunting_bow": Vector2i(2, 0),
	# 绿色 · 优秀
	"fine_blade": Vector2i(0, 1),
	"battle_axe": Vector2i(1, 1),
	"short_bow": Vector2i(2, 1),
	# 蓝色 · 稀有
	"knight_greatsword": Vector2i(0, 2),
	"silver_spear": Vector2i(1, 2),
	"mithril_bow": Vector2i(2, 2),
	# 橙色 · 传奇
	"flame_brand": Vector2i(0, 3),
	"storm_crossbow": Vector2i(1, 3),
	"arcane_staff": Vector2i(2, 3),
}

const CHERRY_SHOTGUN_SHEET := "weapon_cherry_shotgun"


static func weapon_icon(weapon_id: StringName) -> Texture2D:
	var id := String(weapon_id)
	if WEAPON_FRAMES.has(id):
		var v: Vector2i = WEAPON_FRAMES[id]
		return frame("weapons", v.x, v.y)
	# 未单独出图的武器 → 用一个通用占位（铁剑），避免运行时空贴图
	push_warning("[Atlas] 武器 %s 未登记图标，使用占位图" % id)
	return frame("weapons", 0, 0)


static func cherry_shotgun_icon() -> Texture2D:
	return sheet(CHERRY_SHOTGUN_SHEET)


# ---------------------------------------------------------------------------
# 地表图块（tileset_forest.png，8 列 x 8 行）
# ---------------------------------------------------------------------------

const TILE_SIZE := 16

enum Tile {
	GRASS_1 = 0, GRASS_2, GRASS_3, GRASS_4,
	DIRT_1, DIRT_2, STONE_1, STONE_2,
	GRASS_EDGE_A, GRASS_EDGE_B, BUSH_TALL_A, BUSH_TALL_B,
	SAND, GRAVEL, WATER_SHALLOW, WATER_DEEP,
	PEBBLE = 16, BUSH, FLOWER_A, FLOWER_B, MUSHROOM_DECO, STUMP, TALL_GRASS, LOG,
	TREE_TL = 24, TREE_TR = 25, TREE_BL = 26, TREE_BR = 27, TRUNK, PINE, DEAD_TREE, BIG_STUMP,
	CLIFF_TOP_L = 32, CLIFF_TOP_M, CLIFF_TOP_R, CLIFF_SIDE, CLIFF_BOTTOM, CLIFF_CORNER_L, CLIFF_CORNER_R, CLIFF_INNER,
	WOOD_FLOOR = 40, WOOD_FLOOR_H, BRICK, BRICK_BROKEN, TENT, FENCE, BRIDGE_H, BRIDGE_V,
	ALTAR_FLOOR = 48, MAGIC_CIRCLE_C, MAGIC_CIRCLE_E, MOSS_STONE, VINE_GROUND, LEAVES_GROUND, SWAMP, PIT,
	BLACK = 56, SHADOW_TILE, MOSS_CLIFF, CAVE_MOUTH, SPIKE_A, SPIKE_B, CHEST_BASE, TELEPORT_PAD,
}

static func tile_atlas() -> Texture2D:
	return sheet("tileset_forest")


static func tile_region(tile_id: int) -> Rect2:
	var cols: int = SHEETS["tileset_forest"]["cols"]
	var c: int = SHEETS["tileset_forest"]["cell"]
	return Rect2((tile_id % cols) * c, (tile_id / cols) * c, c, c)


# ---------------------------------------------------------------------------
# 双网格地表图集（tileset_forest_ground.png，16 列 x 16 行，每格 16px）
# ---------------------------------------------------------------------------
#
#  布局：4 种地形按 2×2 排列，每种占 4×4 格（16 个角点变体）。
#        其余格子**故意留空**，给后续地图（洞穴/雪原/沙漠…）。
#
#  索引语义与槽位换算**唯一来源是 DualGrid**（scripts/core/dual_grid.gd）。
#  本文件只提供"取整块贴图"与"判断某个槽位是否是刻意的空瓦片"这两个工具。

static func ground_atlas() -> Texture2D:
	return sheet("tileset_forest_ground")


static func wall_atlas() -> Texture2D:
	return sheet("tileset_forest_wall")


# ---------------------------------------------------------------------------
# 场景道具（独立 PNG，非图集）
# ---------------------------------------------------------------------------
#
# 【为什么单独拆出来】旧做法是把树木/石头/灌木塞进 tileset_forest.png 的固定格子，
# 于是尺寸被锁死在 16x16 —— 树只能是一格大的小图标，做不出《元气骑士前传》
# 那种大剪影。拆成独立文件后每张可以有真实尺寸，树冠才长得起来。
#
# 【锚点契约】每张图的内容**底边贴画布最下、水平居中**（见 tools/refart/gen_props.gd
# 的 _ground()）。游戏侧因此只需把精灵按"底部中央"对齐格心，不必逐张记偏移。
# 这条契约由 tools/refart/verify_props.gd 断言。

const PROP_FILES := {
	"tree_pine": "prop_tree_pine.png",        # 32x48
	"tree_dead": "prop_tree_dead.png",        # 32x48
	"tree_broad": "prop_tree_broad.png",      # 48x64
	"rock_small": "prop_rock_small.png",      # 16x16
	"rock_big": "prop_rock_big.png",          # 32x32
	"stump": "prop_stump.png",                # 16x16
	"bush": "prop_bush.png",                  # 16x16
	"flower_a": "prop_flower_a.png",          # 16x16
	"flower_b": "prop_flower_b.png",          # 16x16
	"mushroom": "prop_mushroom.png",          # 16x16
	"tall_grass": "prop_tall_grass.png",      # 16x16
	"pebble": "prop_pebble.png",              # 16x16
	"fallen_log": "prop_fallen_log.png",      # 32x16
}

static var _prop_cache: Dictionary = {}


## 取一张独立道具贴图（带缓存）。未登记的名字返回 null。
static func prop_texture(prop_id: String) -> Texture2D:
	if _prop_cache.has(prop_id):
		return _prop_cache[prop_id]
	if not PROP_FILES.has(prop_id):
		push_warning("[Atlas] 未登记的道具: %s" % prop_id)
		return null
	var path: String = DIR + PROP_FILES[prop_id]
	if not ResourceLoader.exists(path):
		push_warning("[Atlas] 道具贴图不存在: %s（请先跑 tools/refart/gen_props.gd）" % path)
		return null
	var tex: Texture2D = load(path)
	_prop_cache[prop_id] = tex
	return tex


## 判断一个 "col,row" 形式的槽位是否是双网格图集里**刻意留空**的瓦片。
##
## 双网格只画「属于本地形的象限」，所以「四角都不是本地形」（索引 0）的瓦片
## 永远不会被贴上去 —— 留空是设计的一部分。校验器不该把它当成素材缺失。
## 入参就是校验器拼出来的 "col,row" 字符串（见 tools/validation.gd）。
static func is_dual_grid_empty_slot(slot: String) -> bool:
	var parts := slot.split(",")
	if parts.size() != 2:
		return false
	var target := Vector2i(parts[0].to_int(), parts[1].to_int())
	var empty_idx := DualGrid.index_of(false, false, false, false)
	for t in 4:
		if DualGrid.tile_coords(t, empty_idx) == target:
			return true
	return false
