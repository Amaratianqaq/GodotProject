class_name ForestMapConfig
extends Resource
## 森林关卡地图生成参数（数据驱动，改 .tres 即可调整关卡结构）。
##
## 【框架约束】
## 1. 地图生成器 **只** 读本配置，不允许硬编码房间尺寸/数量。
## 2. 房间坐标系：cell = 房间在房间网格上的格子；tile = 图块坐标（16px）。
##    房间内部 tile 矩形 = Vector2(cell) * cell_pitch，尺寸 = room_interior。
## 3. 走廊只连接 **轴相邻** 的房间格，因此走廊永远是直线，不需要拐弯算法。

@export_group("标识")
## 配置唯一 id（ConfigDB 用 get_forest_config() 按此查找）
@export var id: StringName = &"forest_config"
@export var display_name: String = "宁静森林"

@export_group("规模")
## 房间数量范围（含入口与 BOSS 房）
@export var room_count_min: int = 9
@export var room_count_max: int = 13
## 房间内部尺寸（图块数）
@export var room_interior: Vector2i = Vector2i(22, 16)
## 相邻房间原点之间的图块间距（必须大于 room_interior，差额即走廊长度）
@export var cell_pitch: Vector2i = Vector2i(30, 24)
## 走廊宽度（图块数，奇数最好看）
@export var corridor_width: int = 3
## 生成尝试上限（防止死循环）
@export var max_attempts: int = 400
## 允许成环的概率（0 = 纯树状；>0 会额外打通一条相邻房，形成环路）
@export var loop_chance: float = 0.18

@export_group("房间分配")
## 宝箱房数量
@export var treasure_rooms: int = 2
## 精英房数量
@export var elite_rooms: int = 2
## 是否把 BOSS 放在离入口最远的死路
@export var boss_at_dead_end: bool = true

@export_group("刷怪")
## 每个战斗房的敌人数量范围
@export var enemies_per_room: Vector2i = Vector2i(3, 6)
## 精英房敌人数量范围
@export var enemies_per_elite_room: Vector2i = Vector2i(2, 4)
## 房间内敌人离墙的最小距离（图块）
@export var enemy_wall_margin: int = 3
## 房间内敌人之间最小间距（图块）
@export var enemy_min_spacing: float = 3.0

@export_group("装饰密度（0~1）")
## 房间内树木数量系数
@export var tree_density: float = 0.055
## 岩石数量系数
@export var rock_density: float = 0.035
## 灌木/花草数量系数
@export var bush_density: float = 0.10
## 走廊内碎石装饰
@export var corridor_decor_density: float = 0.03
## 装饰物离房间墙的最小距离（图块）
@export var decor_wall_margin: int = 1
## 装饰物是否生成碰撞
@export var tree_has_collision: bool = true
@export var rock_has_collision: bool = true

@export_group("地表图块（双网格）")
## 【双网格模式】每种房间类型绑定**一种**地表，地表内部由 16 张角点瓦片自动衔接。
## 不再需要"多图块随机 + 过渡条"那套 —— 地貌的成片感与边界圆角由双网格负责。
## 缓存值对应 DualGrid.Terrain（0 草 / 1 泥 / 2 石 / 3 坛）。
## 这里用 int 而不是枚举类型：避免 Resource 默认值在自动加载注册前求值。
@export var room_ground_terrain: int = 0        ## 普通房间（战斗 / 精英）
@export var entrance_ground_terrain: int = 2    ## 入口房 → 石板
@export var treasure_ground_terrain: int = 0    ## 宝箱房 → 草地
@export var boss_ground_terrain: int = 3        ## BOSS 房 → 圣坛魔阵
@export var corridor_ground_terrain: int = 1    ## 走廊 → 泥土路
@export var underlay_terrain: int = 1           ## 世界底色（铺满整张地图，泥土）
## 墙体是否补一圈（地板 8 邻域里不是地板的格子填墙）
@export var walls_enabled: bool = true

@export_group("地表图块（旧：传统 1×1 平铺）")
## 【这套字段已退役】保留是为了兼容旧 .tres 与回退对比，双网格路径不读它们。
## 新地图请只填上面的 room_ground_terrain 等字段。
@export var floor_tiles: Array[int] = [
	Atlas.Tile.GRASS_1, Atlas.Tile.GRASS_2, Atlas.Tile.GRASS_3, Atlas.Tile.GRASS_4,
]
@export var floor_tile_weights: Array[float] = [1.0, 1.0, 1.0, 1.0]
@export var corridor_tiles: Array[int] = [Atlas.Tile.DIRT_1, Atlas.Tile.DIRT_2]
@export var corridor_tile_weights: Array[float] = [1.0, 1.0]
## 房间边缘一圈使用的地表（做视觉收边）
@export var floor_edge_tile: int = Atlas.Tile.GRASS_EDGE_A
@export var wall_tile: int = Atlas.Tile.CLIFF_SIDE
@export var wall_corner_tile: int = Atlas.Tile.MOSS_CLIFF
@export var treasure_room_floor: int = Atlas.Tile.LEAVES_GROUND
@export var boss_room_floor: int = Atlas.Tile.ALTAR_FLOOR
@export var entrance_room_floor: int = Atlas.Tile.STONE_1

@export_group("宝箱")
## 每个宝箱房放置的宝箱数
@export var chests_per_treasure_room: Vector2i = Vector2i(1, 2)
## 普通战斗房额外掉宝箱的概率（按房间，避免满地宝箱）
@export var room_chest_chance: float = 0.25
## 宝藏房宝箱等级
@export var treasure_chest_tier: int = GameEnums.ChestTier.FINE

@export_group("相机")
@export var camera_zoom: float = 1.0


func tile_size() -> int:
	return Atlas.TILE_SIZE


func room_size_px() -> Vector2i:
	return room_interior * Atlas.TILE_SIZE


func pitch_px() -> Vector2i:
	return cell_pitch * Atlas.TILE_SIZE
