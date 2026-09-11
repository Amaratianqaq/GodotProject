class_name ForestLevel
extends Node2D
## 森林关卡 —— 把 RoomGraph 翻译成「真实场景」（地形 / 装饰 / 敌人 / 宝箱 / 传送门）。
##
## ==================== 2.5D 像素表现 ====================
## · 地面/墙体走一张 TileMapLayer（不做 y-sort，永远在最底层）；
## · 树木、石头、灌木、敌人、玩家、掉落物全部放在 **同一个** y_sort_enabled
##   的容器 `EntityRoot` 里，靠 position.y 决定遮挡 —— 走到树后面会被挡住，
##   这就是 2.5D 的全部实现，没有任何 3D 节点。
## · 需要「离地」时（翻滚/飞行/击飞）改 Actor.z_height，精灵上移 + 影子缩小。
## ======================================================
##
## 【框架约束 · 必读】
## 1. 本文件是「关卡 = 生成数据 → 场景」的唯一翻译层。
##    地图拓扑只来自 ForestMapGenerator，禁止在这里写任何随机布局算法。
## 2. 随机必须使用 RunManager.map_rng（可复现），战斗随机用 RunManager.combat_rng。
## 3. 关卡必须在 _ready 里注册四类根节点到对应 group，供全局系统查找：
##      fx_root / entity_root / projectile_root / pickup_root
##    没有这些 group，CombatFx 与掉落物会挂错父节点导致特效/掉落丢失。
## 4. 房间清空判定集中在本文件（_update_room_state），敌人节点不参与。

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const ENEMY_SCENE := "res://scenes/enemies/Enemy.tscn"
const PORTAL_SCENE := "res://scenes/world/Portal.tscn"

@export_group("关卡配置")
## 地图生成配置（留空则用 ConfigDB 里的 forest_config）
@export var map_config: ForestMapConfig
## 指定种子（-1 = 用 RunManager 的 run_seed）
@export var level_seed: int = -1
## 是否生成玩家（调试时可以关掉）
@export var spawn_player: bool = true

# --- 构建出来的节点 ---
var graph: RoomGraph = null
var cfg: ForestMapConfig = null
var ground: TileMapLayer = null            ## 墙体层（带碰撞）
var underlay: TileMapLayer = null          ## 世界底色层（铺满整张地图，防止边缘露黑）
var entity_root: Node2D = null
var fx_root: Node2D = null
var projectile_root: Node2D = null
var pickup_root: Node2D = null
var props_root: Node2D = null
var player: Player = null
var exit_portal: Portal = null
var return_portal: Portal = null

# --- 内部状态 ---
## 双网格地表层：索引 = DualGrid.Terrain，共 4 层，靠图层顺序决定压盖
var _ground_layers: Array[TileMapLayer] = []
var _floor: Dictionary = {}        ## Vector2i -> 地表编号（DualGrid.Terrain）
var _walls: Dictionary = {}        ## Vector2i -> true（墙体）
var _blocked: Dictionary = {}      ## Vector2i -> true（被装饰物占据）
var _room_enemies: Dictionary = {} ## Vector2i(room cell) -> Array[Node]
var _current_room: RoomData = null
var _rng: RandomNumberGenerator = null
var _boss_defeated := false
var _elapsed := 0.0


func _ready() -> void:
	cfg = map_config if map_config else ConfigDB.get_forest_config()
	if cfg == null:
		push_error("[ForestLevel] 找不到森林地图配置")
		return
	_build_nodes()
	_generate()
	_paint_ground()
	_decorate()
	_spawn_player()
	_spawn_rooms_content()
	_place_portals()
	_finish_setup()
	print("[ForestLevel] 生成完成：%s" % graph)


# ---------------------------------------------------------------------------
# 节点骨架
# ---------------------------------------------------------------------------

## 双网格地表层的 z 序基准（越小越靠下）。
## 世界底色 −60、地表 −50..−47、墙体 −40 —— 顺序即压盖关系，不要随意调。
const Z_UNDERLAY := -60
const Z_GROUND_BASE := -50
const Z_WALL := -40


func _build_nodes() -> void:
	# 背景（地图外的黑底）
	var bg := Polygon2D.new()
	bg.name = "Background"
	bg.color = Color("#0d0b1f")
	bg.z_index = -100
	bg.z_as_relative = false
	add_child(bg)

	# ============================================================
	#  地形：双网格（dual-grid）系统
	# ------------------------------------------------------------
	#  旧做法：一个 TileMapLayer，每个逻辑格塞一张 16px 图块。
	#  新做法：显示层整体偏移 (−8,−8)，每个显示格压 4 个逻辑格的公共角点，
	#          用 16 张角点瓦片覆盖全部组合 → 地貌成片、边界自动圆角。
	#
	#  ★ 三条硬约束（都是踩过坑换来的）：
	#   1. 每种地表各占一个 TileMapLayer —— set_cell 是**覆盖**不是叠加，
	#      写进同一层会让后写的整格盖掉先写的（表现为"某地表整片消失"）。
	#   2. 地表层**不放碰撞** —— 显示格偏移半格，碰撞会跟着偏半格，
	#      玩家会卡在看得见的地板外面。碰撞全部归 Walls 层。
	#   3. 世界底色必须**显式**用 z_index 压到最底，只靠 add_child 顺序不保险。
	# ============================================================
	var ground_ts := ForestTileset.get_ground_tileset()
	if ground_ts == null:
		push_error("[ForestLevel] 双网格地表图集缺失，地形将不可见")
	else:
		underlay = TileMapLayer.new()
		underlay.name = "GroundUnderlay"
		underlay.tile_set = ground_ts
		underlay.z_index = Z_UNDERLAY
		underlay.z_as_relative = false
		add_child(underlay)
		_ground_layers.clear()
		for t in 4:
			var gl := TileMapLayer.new()
			gl.name = "Ground%d" % t
			gl.tile_set = ground_ts
			# ★ 双网格的全部魔法：整个图层偏移半个瓦片
			gl.position = Vector2(-DualGrid.HALF, -DualGrid.HALF)
			gl.z_index = Z_GROUND_BASE + t
			gl.z_as_relative = false
			add_child(gl)
			_ground_layers.append(gl)

	ground = TileMapLayer.new()
	ground.name = "Walls"
	ground.tile_set = ForestTileset.get_wall_tileset()
	ground.z_index = Z_WALL
	ground.z_as_relative = false
	add_child(ground)

	# ★ 2.5D 核心：所有实体与装饰共用一个 y_sort 容器
	entity_root = Node2D.new()
	entity_root.name = "EntityRoot"
	entity_root.y_sort_enabled = true
	add_child(entity_root)
	NodeUtils.ensure_group(entity_root, &"entity_root")

	props_root = Node2D.new()
	props_root.name = "Props"
	props_root.y_sort_enabled = true
	entity_root.add_child(props_root)

	pickup_root = Node2D.new()
	pickup_root.name = "Pickups"
	pickup_root.y_sort_enabled = true
	entity_root.add_child(pickup_root)
	NodeUtils.ensure_group(pickup_root, &"pickup_root")

	projectile_root = Node2D.new()
	projectile_root.name = "Projectiles"
	projectile_root.y_sort_enabled = true
	entity_root.add_child(projectile_root)
	NodeUtils.ensure_group(projectile_root, &"projectile_root")

	fx_root = Node2D.new()
	fx_root.name = "FxRoot"
	fx_root.y_sort_enabled = true
	fx_root.z_index = 20
	fx_root.z_as_relative = false
	add_child(fx_root)
	NodeUtils.ensure_group(fx_root, &"fx_root")

	# 背景多边形稍后按地图尺寸设置
	_bg_polygon = bg


var _bg_polygon: Polygon2D = null


# ---------------------------------------------------------------------------
# 生成拓扑
# ---------------------------------------------------------------------------

func _generate() -> void:
	var s := level_seed
	if s < 0:
		if RunManager and RunManager.run_seed != 0:
			s = RunManager.run_seed
		else:
			s = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
			if RunManager:
				RunManager.start_run(s, 0)
	# 用 RunManager.map_rng 保证「同种子同地图」
	_rng = RunManager.map_rng if RunManager else RandomNumberGenerator.new()
	if _rng.seed != s:
		_rng.seed = s
	graph = ForestMapGenerator.generate(cfg, _rng)
	if RunManager:
		RunManager.register_level(self)
	EventBus.map_generated.emit(self, graph)


# ---------------------------------------------------------------------------
# 地形
# ---------------------------------------------------------------------------

## 地形绘制（双网格）。
##
## 【双网格怎么工作】
##   ① 逻辑格（A 格）：`_floor[c]` = 那里的地表编号。房间 / 走廊 / 刷怪 / 装饰
##      全部沿用逻辑格坐标，**不需要任何换算** —— 这是双网格相比"半格偏移方案"
##      最大的好处。
##   ② 显示格（B 格）：每个地表一个 TileMapLayer，整体偏移 (−8,−8)，
##      显示格 (col,row) 的索引由它压着的 4 个逻辑格决定：
##          NW 象限 ← 逻辑格 (col-1,row-1)      NE 象限 ← 逻辑格 (col,row-1)
##          SW 象限 ← 逻辑格 (col-1,row  )      SE 象限 ← 逻辑格 (col,row  )
##      索引换算走 DualGrid.index_of()，本文件不推导位序。
##   ③ 写入范围要**外扩 1 格** —— 显示网格比逻辑网格大一圈，
##      不外扩的话地图最右 / 最下一行会缺瓦片。
func _paint_ground() -> void:
	if graph == null:
		return
	_floor.clear()
	_walls.clear()

	# ① 房间地板：每种房间类型绑定一种地表
	for room in graph.all_rooms():
		var terrain := _room_floor_terrain(room)
		for y in range(room.interior.position.y, room.interior.position.y + room.interior.size.y):
			for x in range(room.interior.position.x, room.interior.position.x + room.interior.size.x):
				_floor[Vector2i(x, y)] = terrain

	# ② 走廊地板（后写覆盖房间，保证走廊永远连通）
	for rect in graph.corridors:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				_floor[Vector2i(x, y)] = cfg.corridor_ground_terrain

	# ③ 墙体：地板 8 邻域里「不是地板」的格子
	if cfg.walls_enabled:
		var around: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
		]
		for c in _floor.keys():
			for d in around:
				var n: Vector2i = c + d
				if not _floor.has(n):
					_walls[n] = true

	# ④ 写入：世界底色 → 各层地表 → 墙体
	_paint_underlay()
	_paint_ground_layers()

	if ground != null:
		for c in _walls.keys():
			ground.set_cell(c, ForestTileset.SOURCE_ID,
				ForestTileset.wall_coords(ForestTileset.DEFAULT_WALL_TILE))

	# ⑤ 背景多边形覆盖整张地图
	if _bg_polygon:
		var b := graph.tile_bounds_with_margin(6)
		var ts := float(Atlas.TILE_SIZE)
		var p0 := Vector2(b.position) * ts
		var p1 := Vector2(b.position + b.size) * ts
		_bg_polygon.polygon = PackedVector2Array([
			p0, Vector2(p1.x, p0.y), p1, Vector2(p0.x, p1.y)
		])

	print("[ForestLevel] 地形（双网格）：地板 %d 格 / 墙体 %d 格" % [
		_floor.size(), _walls.size()])


## 世界底色：整张地图铺满 underlay 地形的满格瓦片。
## 【为什么需要它】双网格的角点瓦片在"四角都不是本地形"的地方是空的，
## 如果没有底色，地图边缘会露出背景黑。铺一层底色后，
## 地表瓦片的圆角与落影就落在底色上，形成自然的过渡带。
func _paint_underlay() -> void:
	if underlay == null or graph == null:
		return
	underlay.clear()
	var full := DualGrid.full_index()
	var coords := DualGrid.tile_coords(cfg.underlay_terrain, full)
	var b := graph.tile_bounds_with_margin(3)
	for y in range(b.position.y, b.position.y + b.size.y):
		for x in range(b.position.x, b.position.x + b.size.x):
			underlay.set_cell(Vector2i(x, y), ForestTileset.SOURCE_ID, coords)


## 逐地表写入双网格层
func _paint_ground_layers() -> void:
	if _ground_layers.is_empty() or graph == null:
		return
	for gl in _ground_layers:
		gl.clear()

	var b := graph.tile_bounds_with_margin(2)
	# ★ 外扩 1 格：显示网格比逻辑网格大一圈，不外扩会让最右/最下缺一行
	for row in range(b.position.y - 1, b.position.y + b.size.y + 1):
		for col in range(b.position.x - 1, b.position.x + b.size.x + 1):
			for t in 4:
				var idx := _dual_index_at(col, row, t)
				if idx == 0:
					continue
				_ground_layers[t].set_cell(
					Vector2i(col, row), ForestTileset.SOURCE_ID,
					DualGrid.tile_coords(t, idx))


## 显示格 (col,row) 在地表 t 下的角点索引。
## 四个参数依次是「屏幕左上 / 右上 / 左下 / 右下」四个象限是否为地表 t。
func _dual_index_at(col: int, row: int, t: int) -> int:
	return DualGrid.index_of(
		_terrain_at(col - 1, row - 1) == t,   # NW ← 逻辑格 (col-1,row-1)
		_terrain_at(col, row - 1) == t,       # NE ← 逻辑格 (col,   row-1)
		_terrain_at(col - 1, row) == t,       # SW ← 逻辑格 (col-1, row)
		_terrain_at(col, row) == t)           # SE ← 逻辑格 (col,   row)


## 逻辑格的地表编号，-1 = 没有地表
func _terrain_at(x: int, y: int) -> int:
	var v = _floor.get(Vector2i(x, y))
	return int(v) if v != null else -1


## 房间类型 → 地表编号
func _room_floor_terrain(room: RoomData) -> int:
	match room.kind:
		GameEnums.RoomKind.ENTRANCE: return cfg.entrance_ground_terrain
		GameEnums.RoomKind.TREASURE: return cfg.treasure_ground_terrain
		GameEnums.RoomKind.BOSS: return cfg.boss_ground_terrain
	return cfg.room_ground_terrain


# ---------------------------------------------------------------------------
# 装饰
# ---------------------------------------------------------------------------

func _decorate() -> void:
	if props_root == null:
		return
	var tree_count := 0
	var rock_count := 0
	var bush_count := 0

	for room in graph.all_rooms():
		var area := room.interior.size.x * room.interior.size.y
		# 出生房与 BOSS 房留出活动空间
		var density_mul := 1.0
		match room.kind:
			GameEnums.RoomKind.ENTRANCE: density_mul = 0.4
			GameEnums.RoomKind.BOSS: density_mul = 0.5
			GameEnums.RoomKind.TREASURE: density_mul = 0.7
			_: density_mul = 1.0

		tree_count += _scatter_in_room(
			room, int(float(area) * cfg.tree_density * density_mul),
			[_deco_tree, _deco_pine, _deco_dead_tree], true
		)
		rock_count += _scatter_in_room(
			room, int(float(area) * cfg.rock_density * density_mul),
			[_deco_rock, _deco_stump], cfg.rock_has_collision
		)
		bush_count += _scatter_in_room(
			room, int(float(area) * cfg.bush_density * density_mul),
			[_deco_bush, _deco_flower, _deco_mushroom, _deco_grass], false
		)

	# 走廊碎石
	for rect in graph.corridors:
		var area2 := rect.size.x * rect.size.y
		_scatter_in_rect(rect, int(float(area2) * cfg.corridor_decor_density),
			[_deco_rock_small, _deco_grass], false)

	print("[ForestLevel] 装饰：树 %d / 岩石 %d / 灌木花草 %d" % [tree_count, rock_count, bush_count])


func _scatter_in_room(
	room: RoomData, count: int, makers: Array, with_collision: bool
) -> int:
	return _scatter_in_rect(room.interior, count, makers, with_collision, room)


func _scatter_in_rect(
	rect: Rect2i, count: int, makers: Array, with_collision: bool, room: RoomData = null
) -> int:
	var placed := 0
	var margin := cfg.decor_wall_margin
	var attempts := 0
	var max_attempts := count * 12 + 8
	var door_tiles: Array[Vector2i] = []
	if room:
		for d in room.doors.values():
			door_tiles.append(d)
	while placed < count and attempts < max_attempts:
		attempts += 1
		var x := _rng.randi_range(rect.position.x + margin, rect.position.x + rect.size.x - 1 - margin)
		var y := _rng.randi_range(rect.position.y + margin, rect.position.y + rect.size.y - 1 - margin)
		var c := Vector2i(x, y)
		if _blocked.has(c) or _walls.has(c) or not _floor.has(c):
			continue
		# 别堵门：门附近 2 格内不放有碰撞的装饰
		if with_collision and _too_close_to_any(c, door_tiles, 2):
			continue
		var maker: Callable = makers[_rng.randi_range(0, makers.size() - 1)]
		var node: Node2D = maker.call(c)
		if node == null:
			continue
		_blocked[c] = true
		if with_collision:
			_add_obstacle_body(node, 5.0)
		placed += 1
	return placed


func _too_close_to_any(c: Vector2i, list: Array[Vector2i], dist: int) -> bool:
	for d in list:
		if absi(d.x - c.x) <= dist and absi(d.y - c.y) <= dist:
			return true
	return false


# --- 具体装饰工厂 ---
#
# 【双网格之后装饰怎么放】
# 逻辑格坐标一点没变（装饰仍按格心摆），只是贴图换成了**独立道具 PNG**。
# 独立道具的锚点契约是「内容底边贴画布最下、水平居中」，所以这里统一：
#   holder.position = 格心
#   sprite.offset   = (0, -h/2)  → 让精灵的底边正好落在格心
# 于是"树的根扎在格心、树冠往上长"，走到树后面会被挡住（y-sort 看 holder.position.y）。
#
# 【为什么不再用 scale】旧实现靠 scale 1.15~1.45 把 16x16 的小图标撑成大树，
# 结果是放大后的像素块比场景里其它东西粗一倍。现在树本身就是 32x48 / 48x64，
# 保持 1:1 反而比例正确。

## 装饰统一用 Node2D 容器承载（Sprite + 可选碰撞体）
## prop_id 见 Atlas.PROP_FILES；scale_v 仅用于轻微的大小变化（默认 1.0）
func _make_deco(cell: Vector2i, prop_id: String, scale_v := 1.0) -> Node2D:
	var holder := Node2D.new()
	holder.position = _cell_to_world(cell)
	holder.y_sort_enabled = true
	if props_root:
		props_root.add_child(holder)
	var s := Sprite2D.new()
	var tex := Atlas.prop_texture(prop_id)
	if tex == null:
		holder.queue_free()
		return holder
	s.texture = tex
	s.centered = true
	s.scale = Vector2(scale_v, scale_v)
	s.flip_h = _rng.randf() < 0.5
	# 底边贴格心：精灵半高上移，让"根部"落在 holder 原点上
	s.position = Vector2(0, -float(tex.get_height()) * scale_v * 0.5)
	s.z_index = 0
	holder.add_child(s)
	return holder


func _add_obstacle_body(holder: Node2D, radius: float) -> void:
	var body := StaticBody2D.new()
	body.name = "Obstacle"
	body.collision_layer = Layers.OBSTACLE
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	cs.position = Vector2(0, -3)
	body.add_child(cs)
	holder.add_child(body)


func _deco_tree(cell: Vector2i) -> Node2D:
	# 阔叶树 / 落叶松随机，做出森林的层次
	if _rng.randf() < 0.45:
		return _make_deco(cell, "tree_broad")
	return _make_deco(cell, "tree_pine")


func _deco_pine(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "tree_pine")


func _deco_dead_tree(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "tree_dead")


func _deco_rock(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "rock_big")


func _deco_rock_small(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "rock_small")


func _deco_stump(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "stump")


func _deco_bush(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "bush")


func _deco_flower(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "flower_a" if _rng.randf() < 0.5 else "flower_b")


func _deco_mushroom(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "mushroom")


func _deco_grass(cell: Vector2i) -> Node2D:
	return _make_deco(cell, "tall_grass")


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(Atlas.TILE_SIZE) + Vector2(8, 8)


# ---------------------------------------------------------------------------
# 玩家
# ---------------------------------------------------------------------------

func _spawn_player() -> void:
	if not spawn_player:
		return
	var scene: PackedScene = load(PLAYER_SCENE)
	if scene == null:
		push_error("[ForestLevel] 找不到玩家场景")
		return
	var inst := scene.instantiate()
	entity_root.add_child(inst)
	player = inst as Player
	var start_room := graph.get_room(graph.start_cell)
	var pos := graph.room_size_px() * 0.5
	if start_room:
		pos = Vector2(start_room.interior.position) * float(Atlas.TILE_SIZE) \
			+ Vector2(start_room.interior.size) * float(Atlas.TILE_SIZE) * 0.5
	player.global_position = pos
	_setup_camera(pos)


func _setup_camera(_center: Vector2) -> void:
	if player == null:
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var wb := graph.world_bounds()
	cam.limit_left = int(wb.position.x) - 32
	cam.limit_top = int(wb.position.y) - 32
	cam.limit_right = int(wb.position.x + wb.size.x) + 32
	cam.limit_bottom = int(wb.position.y + wb.size.y) + 32
	cam.zoom = Vector2.ONE * cfg.camera_zoom
	cam.make_current()


# ---------------------------------------------------------------------------
# 房间内容（敌人 / 宝箱）
# ---------------------------------------------------------------------------

func _spawn_rooms_content() -> void:
	for room in graph.all_rooms():
		_collect_spawn_points(room)
		if room.kind == GameEnums.RoomKind.BOSS:
			_spawn_boss(room)
		else:
			_spawn_room_enemies(room)
		_spawn_room_chests(room)


## 计算房间内的可用刷怪点
func _collect_spawn_points(room: RoomData) -> void:
	room.enemy_spawn_points.clear()
	room.chest_spawn_points.clear()
	var margin := cfg.enemy_wall_margin
	var door_tiles: Array[Vector2i] = []
	for d in room.doors.values():
		door_tiles.append(d)
	var tries := 0
	var want := room.enemy_budget + 6
	while room.enemy_spawn_points.size() < want and tries < want * 20:
		tries += 1
		var x := _rng.randi_range(
			room.interior.position.x + margin,
			room.interior.position.x + room.interior.size.x - 1 - margin
		)
		var y := _rng.randi_range(
			room.interior.position.y + margin,
			room.interior.position.y + room.interior.size.y - 1 - margin
		)
		var c := Vector2i(x, y)
		if _blocked.has(c) or _walls.has(c) or not _floor.has(c):
			continue
		if _too_close_to_any(c, door_tiles, 2):
			continue
		var p := _cell_to_world(c)
		var too_close := false
		for existing in room.enemy_spawn_points:
			if existing.distance_to(p) < cfg.enemy_min_spacing * float(Atlas.TILE_SIZE):
				too_close = true
				break
		if too_close:
			continue
		room.enemy_spawn_points.append(p)
	room.chest_spawn_points.clear()
	for p in room.enemy_spawn_points:
		room.chest_spawn_points.append(p)


func _spawn_room_enemies(room: RoomData) -> void:
	if room.enemy_budget <= 0:
		room.cleared = true
		return
	var pool: Array[EnemyData] = []
	if room.kind == GameEnums.RoomKind.ELITE:
		pool = ConfigDB.forest_elite_enemies()
	if pool.is_empty():
		pool = ConfigDB.forest_normal_enemies()
	if pool.is_empty():
		push_error("[ForestLevel] 没有任何可刷的敌人数据")
		return
	var list: Array[Node] = []
	for i in room.enemy_budget:
		var pick: EnemyData = RngUtils.pick_weighted(
			_rng, pool, pool.map(func(e: EnemyData) -> float: return e.spawn_weight)
		)
		if pick == null:
			continue
		var pos := _pick_spawn_position(room)
		var e := _instantiate_enemy(pick, pos, room.cell)
		if e:
			list.append(e)
	_room_enemies[room.cell] = list


func _pick_spawn_position(room: RoomData) -> Vector2:
	if not room.enemy_spawn_points.is_empty():
		var i := _rng.randi_range(0, room.enemy_spawn_points.size() - 1)
		return room.enemy_spawn_points[i]
	return room.get_random_point_inside(_rng, cfg.enemy_wall_margin)


func _spawn_boss(room: RoomData) -> void:
	var boss := ConfigDB.forest_boss()
	if boss == null:
		push_warning("[ForestLevel] 没有配置 BOSS")
		room.cleared = true
		return
	var pos := Vector2(room.interior.position) * float(Atlas.TILE_SIZE) \
		+ Vector2(room.interior.size) * float(Atlas.TILE_SIZE) * 0.5
	var e := _instantiate_enemy(boss, pos, room.cell)
	_room_enemies[room.cell] = [e] if e else []
	# 进 BOSS 房时横幅提示（由 HUD 订阅 boss_spawned 实现）


func _instantiate_enemy(data: EnemyData, pos: Vector2, room_cell: Vector2i) -> Node2D:
	var scene: PackedScene = load(ENEMY_SCENE)
	if scene == null:
		return null
	var e := scene.instantiate()
	# configure 必须在 add_child 之前
	e.call("configure", data, room_cell)
	entity_root.add_child(e)
	(e as Node2D).global_position = pos
	return e


func _spawn_room_chests(room: RoomData) -> void:
	var count := 0
	var tier := GameEnums.ChestTier.NORMAL
	match room.kind:
		GameEnums.RoomKind.TREASURE:
			count = _rng.randi_range(cfg.chests_per_treasure_room.x, cfg.chests_per_treasure_room.y)
			tier = cfg.treasure_chest_tier
		GameEnums.RoomKind.COMBAT, GameEnums.RoomKind.ELITE:
			if RngUtils.chance(_rng, cfg.room_chest_chance):
				count = 1
		GameEnums.RoomKind.BOSS:
			count = 1
			tier = GameEnums.ChestTier.RARE
		_:
			count = 0
	for i in count:
		var pos := _pick_spawn_position(room)
		if room.kind == GameEnums.RoomKind.BOSS:
			pos = Vector2(room.interior.position) * float(Atlas.TILE_SIZE) \
				+ Vector2(room.interior.size) * float(Atlas.TILE_SIZE) * 0.5 \
				+ Vector2(0, 26)
		LootService.spawn_chest(tier, pos, entity_root)


# ---------------------------------------------------------------------------
# 传送门
# ---------------------------------------------------------------------------

func _place_portals() -> void:
	var start_room := graph.get_room(graph.start_cell)
	if start_room:
		return_portal = _make_portal(
			Portal.Kind.EXIT_TO_LOBBY,
			Vector2(start_room.interior.position) * float(Atlas.TILE_SIZE) \
				+ Vector2(14, 14)
		)
		if return_portal:
			return_portal.set_prompt_text("返回大厅（放弃本局）")
			return_portal.activated.connect(_on_return_portal_used)
	# BOSS 房出口：击败 BOSS 后启用
	var boss_room := graph.get_room(graph.boss_cell)
	if boss_room:
		var p := Vector2(boss_room.interior.position) * float(Atlas.TILE_SIZE) \
			+ Vector2(boss_room.interior.size) * float(Atlas.TILE_SIZE) * 0.5
		exit_portal = _make_portal(Portal.Kind.LOCKED, p + Vector2(0, -40))
		if exit_portal:
			exit_portal.visible = false
			exit_portal.activated.connect(_on_exit_portal_used)


func _make_portal(kind: int, pos: Vector2) -> Portal:
	var scene: PackedScene = load(PORTAL_SCENE)
	if scene == null:
		return null
	var p := scene.instantiate() as Portal
	entity_root.add_child(p)
	p.global_position = pos
	p.set_kind(kind)
	return p


## 出生点传送门：放弃本局回大厅
func _on_return_portal_used(_pl: Node2D) -> void:
	if RunManager:
		RunManager.end_run(false)
	SceneRouter.go_to(GameEnums.SCENE_LOBBY)


## BOSS 房出口：通关回大厅
func _on_exit_portal_used(_pl: Node2D) -> void:
	if RunManager:
		RunManager.end_run(true)
	SceneRouter.go_to(GameEnums.SCENE_LOBBY)


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func _finish_setup() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.player_died.connect(_on_player_died)
	if RunManager:
		RunManager.run_active = true
	AudioManager.play_bgm("res://assets/audio/bgm/forest.ogg")
	# HUD（挂在独立 CanvasLayer 上，不受暂停影响）
	var hud_scene: PackedScene = load("res://scenes/ui/Hud.tscn")
	if hud_scene:
		var layer := CanvasLayer.new()
		layer.name = "HudLayer"
		layer.layer = 10
		add_child(layer)
		layer.add_child(hud_scene.instantiate())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not SceneRouter.any_panel_open():
		SceneRouter.open_panel(&"pause", SceneRouter.PANEL_SCENES[&"pause"])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_elapsed += delta
	_update_current_room()


func _update_current_room() -> void:
	var room := graph.get_room_at_world(player.global_position)
	if room == _current_room:
		return
	_current_room = room
	if room == null:
		return
	if not room.discovered:
		room.discovered = true
	if room.kind == GameEnums.RoomKind.BOSS:
		EventBus.toast.emit("BOSS 房 · 哥布林大祭司", Color("#b44ac9"))
	EventBus.room_entered.emit(room, room.kind)
	_check_room_cleared(room)


func _on_enemy_died(enemy: Node, _tier: int, _pos: Vector2) -> void:
	for cell in _room_enemies.keys():
		var list: Array = _room_enemies[cell]
		if list.has(enemy):
			list.erase(enemy)
		var room := graph.get_room(cell)
		if room:
			_check_room_cleared(room)


func _check_room_cleared(room: RoomData) -> void:
	if room.cleared:
		return
	var list: Array = _room_enemies.get(room.cell, [])
	var alive := 0
	for e in list:
		if e != null and is_instance_valid(e) and not bool(e.get("is_dead")):
			alive += 1
	if alive > 0:
		return
	if room.kind == GameEnums.RoomKind.BOSS and not _boss_defeated:
		return
	room.cleared = true
	# 清空奖励：给一点金币与经验
	if room.kind != GameEnums.RoomKind.ENTRANCE:
		var g := 4 + room.depth * 2
		GameState.add_gold(g)
		EventBus.room_cleared.emit(room)
		AudioManager.play_sfx("res://assets/audio/sfx/room_clear.wav")
		CombatFx.popup(player, player.global_position + Vector2(0, -24),
			"房间已清空 +%d 金币" % g, Color("#ffd35c"))


func _on_boss_defeated() -> void:
	if _boss_defeated:
		return
	_boss_defeated = true
	# 解锁出口传送门
	var boss_room := graph.get_room(graph.boss_cell)
	if boss_room:
		boss_room.cleared = true
		EventBus.room_cleared.emit(boss_room)
	if exit_portal:
		exit_portal.visible = true
		exit_portal.set_kind(Portal.Kind.EXIT_TO_LOBBY)
		var tw := exit_portal.create_tween()
		tw.tween_property(exit_portal, "scale", Vector2(1.6, 1.6), 0.22)
		tw.tween_property(exit_portal, "scale", Vector2.ONE, 0.3)
	EventBus.toast.emit("哥布林大祭司已被击败！出口已开启", Color("#f2a13b"))
	EventBus.screen_shake_requested.emit(5.0, 0.5)


func _on_player_died() -> void:
	EventBus.toast.emit("你倒下了……", Color("#d94a4a"))


# 传送门交互由 Portal 发出，这里统一处理关卡流程
func connect_portal(portal: Portal, handler: Callable) -> void:
	if portal:
		portal.activated.connect(handler)


func get_current_room() -> RoomData:
	return _current_room


func elapsed() -> float:
	return _elapsed


# ---------------------------------------------------------------------------
# 调试
# ---------------------------------------------------------------------------

func debug_report() -> String:
	if graph == null:
		return "未生成"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("种子 %d" % graph.seed_value)
	lines.append("房间 %d / 走廊 %d" % [graph.room_count(), graph.corridors.size()])
	for kind in GameEnums.RoomKind.values():
		var n := graph.count_kind(kind)
		if n > 0:
			lines.append("%s x%d" % [GameEnums.RoomKind.keys()[kind], n])
	lines.append("存活敌人 %d" % RunManager.alive_enemy_count())
	return "\n".join(lines)
