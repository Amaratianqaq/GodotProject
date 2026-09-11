class_name ForestTileset
extends RefCounted
## 从 assets/sprites/ 的图集**代码构建** TileSet（含物理碰撞）。
##
## 【双网格管线 —— 当前使用】
##   地表用 `tileset_forest_ground.png`（16×16 格，每种地形 4×4 角点瓦片）。
##   地表层**不放碰撞**：碰撞偏移半格是双网格的经典 bug，
##   所有碰撞都放在墙体层（见 §双网格契约）。
##   索引换算一律走 `DualGrid`，本文件不推导位序。
##
## 【旧管线 —— 保留用于对照回归】
##   传统 1×1 用 `tileset_forest.png`（8×8 格）+ `get_tileset()`。
##   双网格验证通过后，这条路径只剩 Lobby 在用。
##
## 【为什么用代码建 TileSet】
##   一是避免手写 .tscn 里巨大的内嵌 TileSet 资源（易错、不可读），
##   二是图块与 Atlas / DualGrid 同源，改图只需要改一处。
##
## 【框架约束】
##   新增图块 → 先加 Atlas.Tile 枚举与 SOLID_TILES 登记，不要在关卡代码里硬编码索引。

const ATLAS_COLS := 8
const ATLAS_ROWS := 8
const SOURCE_ID := 0
const PHYSICS_LAYER := 0

## 双网格地表图集的网格尺寸（16×16 格）
const GROUND_COLS := 16
const GROUND_ROWS := 16

## 会产生碰撞的图块（墙 / 悬崖 / 树干 / 障碍物）
const SOLID_TILES: Array[int] = [
	Atlas.Tile.TRUNK, Atlas.Tile.PINE, Atlas.Tile.DEAD_TREE, Atlas.Tile.BIG_STUMP,
	Atlas.Tile.CLIFF_TOP_L, Atlas.Tile.CLIFF_TOP_M, Atlas.Tile.CLIFF_TOP_R,
	Atlas.Tile.CLIFF_SIDE, Atlas.Tile.CLIFF_BOTTOM,
	Atlas.Tile.CLIFF_CORNER_L, Atlas.Tile.CLIFF_CORNER_R, Atlas.Tile.CLIFF_INNER,
	Atlas.Tile.MOSS_CLIFF,
	Atlas.Tile.FENCE, Atlas.Tile.BRICK, Atlas.Tile.BRICK_BROKEN, Atlas.Tile.TENT,
	Atlas.Tile.PIT, Atlas.Tile.SPIKE_A, Atlas.Tile.SPIKE_B,
	Atlas.Tile.WATER_DEEP, Atlas.Tile.SWAMP,
]

## 水面（只挡移动，不挡子弹），第一阶段暂时与 SOLID 一致处理
const BLOCKING_ONLY_TILES: Array[int] = []

## 墙体图集里会产生碰撞的图块索引。
## 对应 gen_ground.gd 的 _cliff_* / _structure / _hazard / _misc 里"实心"的那批。
## 说明：row 0/2 是悬崖上沿/下沿（实心岩体）、row 3 是侧壁（实心）、
## row 4 是建筑（木地板/砖墙/帐篷/栅栏/桥：除木地板外都挡路）、
## row 6 是危险物（尖刺/深水/熔岩挡路，浅水/传送台不挡）。
const WALL_SOLID_TILES: Array[int] = [
	0, 1, 2, 3, 4, 5, 6, 7,               # 悬崖上沿
	8, 9, 10, 11, 12, 13, 14, 15,         # 悬崖侧面
	16, 17, 18, 19, 20, 21, 22, 23,       # 悬崖下沿
	24, 25, 26, 27, 28, 29, 30, 31,       # 左右边界
	42, 43, 44, 45,                       # 砖墙 / 破损砖 / 帐篷 / 栅栏
	46, 47,                               # 桥（横/竖）
	53, 54, 55,                           # 泥沼 / 坑洞 / 尖刺 A
	48, 49, 50, 51, 52,                   # 危险物行
	60, 61,
]

static var _cached: TileSet = null
static var _ground_cached: TileSet = null
static var _wall_cached: TileSet = null


## 旧管线：传统 1×1 图集（Lobby 仍在用）
static func get_tileset() -> TileSet:
	if _cached != null:
		return _cached
	var tex := Atlas.tile_atlas()
	if tex == null:
		push_error("[ForestTileset] 缺少地表图集，请先运行 tools/gen_pixel_assets.gd")
		return null

	var ts := TileSet.new()
	ts.tile_size = Vector2i(Atlas.TILE_SIZE, Atlas.TILE_SIZE)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(Atlas.TILE_SIZE, Atlas.TILE_SIZE)
	for y in ATLAS_ROWS:
		for x in ATLAS_COLS:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, SOURCE_ID)

	_add_physics_layer(ts)
	var square := _unit_square()
	for t in SOLID_TILES:
		_add_box(src, t, square)
	for t in BLOCKING_ONLY_TILES:
		_add_box(src, t, square)

	_cached = ts
	print("[ForestTileset] 已构建传统 1x1 TileSet：%d x %d 图块，%d 个碰撞块" % [
		ATLAS_COLS, ATLAS_ROWS, SOLID_TILES.size() + BLOCKING_ONLY_TILES.size()
	])
	return ts


# ---------------------------------------------------------------------------
#  双网格地表 TileSet
# ---------------------------------------------------------------------------

## 双网格地表层的 TileSet。
## 【关键】**不加物理层** —— 双网格显示格整体偏移半个瓦片，
## 如果在那里放碰撞，碰撞体也会偏移半格，玩家会"卡在看得见的地板外面"，
## 或者穿进墙里。碰撞全部交给墙体层。
static func get_ground_tileset() -> TileSet:
	if _ground_cached != null:
		return _ground_cached
	var tex := Atlas.sheet("tileset_forest_ground")
	if tex == null:
		push_error("[ForestTileset] 缺少双网格地表图集，请先运行 tools/refart/gen_ground.gd")
		return null

	var ts := TileSet.new()
	ts.tile_size = Vector2i(DualGrid.TILE, DualGrid.TILE)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(DualGrid.TILE, DualGrid.TILE)
	for y in GROUND_ROWS:
		for x in GROUND_COLS:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, SOURCE_ID)

	_ground_cached = ts
	print("[ForestTileset] 已构建双网格地表 TileSet：%d x %d 格，无物理层（碰撞归墙体层）" % [
		GROUND_COLS, GROUND_ROWS
	])
	return ts


# ---------------------------------------------------------------------------
#  墙体 TileSet
# ---------------------------------------------------------------------------

## 墙体图集（tileset_forest_wall.png，8×8）构建的 TileSet，带物理层。
static func get_wall_tileset() -> TileSet:
	if _wall_cached != null:
		return _wall_cached
	var tex := Atlas.sheet("tileset_forest_wall")
	if tex == null:
		push_error("[ForestTileset] 缺少墙体图集，请先运行 tools/refart/gen_ground.gd")
		return null

	var ts := TileSet.new()
	ts.tile_size = Vector2i(Atlas.TILE_SIZE, Atlas.TILE_SIZE)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(Atlas.TILE_SIZE, Atlas.TILE_SIZE)
	for y in ATLAS_ROWS:
		for x in ATLAS_COLS:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, SOURCE_ID)

	_add_physics_layer(ts)
	var square := _unit_square()
	for t in WALL_SOLID_TILES:
		_add_box(src, t, square)

	_wall_cached = ts
	print("[ForestTileset] 已构建墙体 TileSet：%d 个碰撞块 / 64" % WALL_SOLID_TILES.size())
	return ts


## 墙体图集里某个索引的图块坐标
static func wall_coords(tile_id: int) -> Vector2i:
	return Vector2i(tile_id % ATLAS_COLS, tile_id / ATLAS_COLS)


## 默认墙体图块：悬崖侧壁（实心、朝向中性，适合当通用边界）
const DEFAULT_WALL_TILE := 8


# ---------------------------------------------------------------------------
#  内部工具
# ---------------------------------------------------------------------------

static func _add_physics_layer(ts: TileSet) -> void:
	ts.add_physics_layer(PHYSICS_LAYER)
	ts.set_physics_layer_collision_layer(PHYSICS_LAYER, Layers.WORLD)
	ts.set_physics_layer_collision_mask(PHYSICS_LAYER, 0)


static func _unit_square() -> PackedVector2Array:
	var half := float(Atlas.TILE_SIZE) * 0.5
	return PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])


static func _add_box(src: TileSetAtlasSource, tile_id: int, points: PackedVector2Array) -> void:
	var coords := tile_coords(tile_id)
	var td := src.get_tile_data(coords, 0)
	if td == null:
		return
	td.add_collision_polygon(PHYSICS_LAYER)
	td.set_collision_polygon_points(PHYSICS_LAYER, 0, points)


static func tile_coords(tile_id: int) -> Vector2i:
	return Vector2i(tile_id % ATLAS_COLS, tile_id / ATLAS_COLS)


## 一个图块是否会挡路（旧管线用）
static func is_solid(tile_id: int) -> bool:
	return SOLID_TILES.has(tile_id) or BLOCKING_ONLY_TILES.has(tile_id)


## 墙体图集里某个索引是否挡路
static func is_wall_solid(tile_id: int) -> bool:
	return WALL_SOLID_TILES.has(tile_id)
