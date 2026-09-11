class_name ForestMapGenerator
extends RefCounted
## 森林关卡地图生成器 —— 纯拓扑，不碰任何场景节点。
##
## 【算法】随机生长 + 死路分配
##   1. 从 (0,0) 开始，反复「随机挑一个已有房间 → 随机方向 → 若该格无相邻房间则生长」，
##      直到房间数达到目标。这保证图一定是连通的（生成即连通，无需修复）。
##   2. 按 loop_chance 额外打通少数相邻房，制造环路（避免地图太像树）。
##   3. 从入口做 BFS 得到 depth，然后按 depth / 死路属性分配房间类型：
##        depth 0                     → 入口房
##        最远且是死路                 → BOSS 房
##        剩余死路（按 depth 降序）    → 宝箱房
##        depth 靠前的普通房           → 精英房
##        其余                        → 普通战斗房
##   4. 计算每个房间的门位置与走廊矩形。
##
## 【框架约束 · 必读】
## 1. 生成过程 **只** 允许使用传入的 RandomNumberGenerator，
##    禁止 randf()/randi()，否则同种子地图无法复现。
## 2. 输出只有 RoomGraph；渲染由 ForestLevel 负责，本文件不得引用任何场景。
## 3. 本文件必须保持「无副作用」：不读存档、不发信号、不访问 ConfigDB。

const DIRS := [GameEnums.Dir.N, GameEnums.Dir.E, GameEnums.Dir.S, GameEnums.Dir.W]


## 主入口
static func generate(cfg: ForestMapConfig, rng: RandomNumberGenerator) -> RoomGraph:
	var graph := RoomGraph.new()
	graph.seed_value = int(rng.seed)

	var target := rng.randi_range(cfg.room_count_min, cfg.room_count_max)
	graph.log_line("目标房间数 %d" % target)

	# --- ① 生长拓扑 ---
	var start_cell := Vector2i.ZERO
	graph.add_room(_make_room(start_cell, graph.rooms.size()))
	graph.start_cell = start_cell

	var attempts := 0
	while graph.room_count() < target and attempts < cfg.max_attempts:
		attempts += 1
		var cells: Array = graph.rooms.keys()
		var base: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var dir: int = DIRS[rng.randi_range(0, DIRS.size() - 1)]
		var cand: Vector2i = base + GameEnums.DIR_VECTORS[dir]
		if graph.has_room(cand):
			continue
		# 避免房间挤成一坨：候选格周围最多只能有 1 个已有房间
		var adj := graph.neighbor_cells(cand).size()
		if adj > 1:
			continue
		if adj == 1 and not RngUtils.chance(rng, cfg.loop_chance):
			# 允许成环：决定「打通」就保留，否则跳过这个候选
			continue
		graph.add_room(_make_room(cand, graph.rooms.size()))

	# 兜底：如果因为约束太严没长够，就放宽限制再长一轮
	if graph.room_count() < maxi(3, cfg.room_count_min / 2):
		graph.log_line("约束过严，放宽后补充生长")
		var guard := 0
		while graph.room_count() < cfg.room_count_min and guard < cfg.max_attempts:
			guard += 1
			var cells2: Array = graph.rooms.keys()
			var base2: Vector2i = cells2[rng.randi_range(0, cells2.size() - 1)]
			var dir2: int = DIRS[rng.randi_range(0, DIRS.size() - 1)]
			var cand2: Vector2i = base2 + GameEnums.DIR_VECTORS[dir2]
			if graph.has_room(cand2):
				continue
			graph.add_room(_make_room(cand2, graph.rooms.size()))

	graph.log_line("实际房间数 %d（尝试 %d 次）" % [graph.room_count(), attempts])

	# --- ② 计算几何 ---
	_compute_geometry(graph, cfg)

	# --- ③ BFS 距离 ---
	var unreachable := graph.build_distances(start_cell)
	if not unreachable.is_empty():
		graph.log_line("警告：存在 %d 个不可达房间" % unreachable.size())

	# --- ④ 分配房间类型 ---
	_assign_room_kinds(graph, cfg, rng)

	# --- ⑤ 门与走廊 ---
	_build_doors_and_corridors(graph, cfg)

	graph.log_line("BOSS 房 %s（深度 %d）" % [
		graph.boss_cell, graph.get_room(graph.boss_cell).depth
	])
	return graph


# ---------------------------------------------------------------------------
# ① 房间对象
# ---------------------------------------------------------------------------

static func _make_room(cell: Vector2i, index: int) -> RoomData:
	var r := RoomData.new()
	r.cell = cell
	r.index = index
	r.kind = GameEnums.RoomKind.EMPTY
	r.depth = -1
	return r


# ---------------------------------------------------------------------------
# ② 几何
# ---------------------------------------------------------------------------

static func _compute_geometry(graph: RoomGraph, cfg: ForestMapConfig) -> void:
	var ts := float(cfg.tile_size())
	for r in graph.all_rooms():
		r.interior = Rect2i(cell_to_tile_origin(r.cell, cfg), cfg.room_interior)
		r.center_px = Vector2(
			float(r.interior.position.x) + float(r.interior.size.x) * 0.5,
			float(r.interior.position.y) + float(r.interior.size.y) * 0.5
		) * ts
	# 几何算完才能确定整体包围盒（相机 limit 依赖它）
	graph.recompute_bounds()


## 房间格 → 房间内部左上角图块坐标
static func cell_to_tile_origin(cell: Vector2i, cfg: ForestMapConfig) -> Vector2i:
	return Vector2i(cell.x * cfg.cell_pitch.x, cell.y * cfg.cell_pitch.y)


# ---------------------------------------------------------------------------
# ④ 房间类型
# ---------------------------------------------------------------------------

static func _assign_room_kinds(
	graph: RoomGraph, cfg: ForestMapConfig, rng: RandomNumberGenerator
) -> void:
	var start := graph.get_room(graph.start_cell)
	if start:
		start.kind = GameEnums.RoomKind.ENTRANCE

	# BOSS：最远且（优先）死路
	var boss_cell := graph.pick_boss_cell(graph.start_cell)
	if cfg.boss_at_dead_end:
		# 在「最远 25% 且是死路」里随机挑一个，增加变化
		var candidates: Array[RoomData] = []
		var max_depth := 0
		for r in graph.all_rooms():
			max_depth = maxi(max_depth, r.depth)
		for r in graph.all_rooms():
			if r.cell == graph.start_cell:
				continue
			if r.depth >= int(float(max_depth) * 0.75) and r.is_dead_end():
				candidates.append(r)
		if not candidates.is_empty():
			var picked: RoomData = candidates[rng.randi_range(0, candidates.size() - 1)]
			boss_cell = picked.cell
	graph.boss_cell = boss_cell
	var boss_room := graph.get_room(boss_cell)
	if boss_room:
		boss_room.kind = GameEnums.RoomKind.BOSS

	# 宝箱房：优先死路（且不是 BOSS），按 depth 从远到近
	var dead_ends: Array[RoomData] = []
	for r in graph.all_rooms():
		if r.kind != GameEnums.RoomKind.EMPTY:
			continue
		if r.is_dead_end():
			dead_ends.append(r)
	dead_ends.sort_custom(func(a: RoomData, b: RoomData) -> bool: return a.depth > b.depth)
	var treasure_assigned := 0
	for r in dead_ends:
		if treasure_assigned >= cfg.treasure_rooms:
			break
		r.kind = GameEnums.RoomKind.TREASURE
		treasure_assigned += 1

	# 精英房：在剩下的普通房里，取 depth 较深的几个
	var normals: Array[RoomData] = []
	for r in graph.all_rooms():
		if r.kind == GameEnums.RoomKind.EMPTY:
			normals.append(r)
	normals.sort_custom(func(a: RoomData, b: RoomData) -> bool: return a.depth > b.depth)
	var elite_assigned := 0
	for r in normals:
		if elite_assigned >= cfg.elite_rooms:
			break
		if r.depth <= 0:
			continue
		r.kind = GameEnums.RoomKind.ELITE
		elite_assigned += 1

	# 其余 → 普通战斗房
	for r in graph.all_rooms():
		if r.kind == GameEnums.RoomKind.EMPTY:
			r.kind = GameEnums.RoomKind.COMBAT

	# 每个房间的刷怪预算
	for r in graph.all_rooms():
		match r.kind:
			GameEnums.RoomKind.ENTRANCE:
				r.enemy_budget = 0
			GameEnums.RoomKind.TREASURE:
				r.enemy_budget = rng.randi_range(0, 2)
			GameEnums.RoomKind.ELITE:
				r.enemy_budget = rng.randi_range(
					cfg.enemies_per_elite_room.x, cfg.enemies_per_elite_room.y
				)
			GameEnums.RoomKind.BOSS:
				r.enemy_budget = 1   # BOSS 本体
			_:
				r.enemy_budget = rng.randi_range(
					cfg.enemies_per_room.x, cfg.enemies_per_room.y
				)


# ---------------------------------------------------------------------------
# ⑤ 门与走廊
# ---------------------------------------------------------------------------

static func _build_doors_and_corridors(graph: RoomGraph, cfg: ForestMapConfig) -> void:
	graph.corridors.clear()
	# 半宽（走廊宽度为奇数时对称）
	var half := cfg.corridor_width / 2
	for r in graph.all_rooms():
		for n_cell in graph.neighbor_cells(r.cell):
			# 只处理「正向」的一侧，避免重复生成走廊
			if not _is_forward(r.cell, n_cell):
				continue
			var other := graph.get_room(n_cell)
			if other == null:
				continue
			var d := r.dir_to(n_cell)
			_build_corridor(graph, r, other, d, half, cfg)


## 只处理 N/E 两个方向，保证每对相邻房只生成一次走廊
static func _is_forward(a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	return delta == Vector2i(0, -1) or delta == Vector2i(1, 0)


static func _build_corridor(
	graph: RoomGraph, a: RoomData, b: RoomData, dir: int, half: int, cfg: ForestMapConfig
) -> void:
	var rect := Rect2i()
	var door_a := Vector2i.ZERO
	var door_b := Vector2i.ZERO

	if dir == GameEnums.Dir.E:
		var y := a.interior.position.y + a.interior.size.y / 2
		var x0 := a.interior.position.x + a.interior.size.x
		var x1 := b.interior.position.x - 1
		rect = Rect2i(x0, y - half, maxi(1, x1 - x0 + 1), cfg.corridor_width)
		# 门 = 房间内部贴着走廊那一列/行（刷怪与装饰时避开）
		door_a = Vector2i(a.interior.position.x + a.interior.size.x - 1, y)
		door_b = Vector2i(b.interior.position.x, y)
		a.doors[GameEnums.Dir.E] = door_a
		b.doors[GameEnums.Dir.W] = door_b
	elif dir == GameEnums.Dir.N:
		var x := a.interior.position.x + a.interior.size.x / 2
		var y0 := b.interior.position.y + b.interior.size.y
		var y1 := a.interior.position.y - 1
		rect = Rect2i(x - half, y0, cfg.corridor_width, maxi(1, y1 - y0 + 1))
		door_a = Vector2i(x, a.interior.position.y)
		door_b = Vector2i(x, b.interior.position.y + b.interior.size.y - 1)
		a.doors[GameEnums.Dir.N] = door_a
		b.doors[GameEnums.Dir.S] = door_b
	else:
		return
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	graph.corridors.append(rect)
	graph.log_line("走廊 %s ↔ %s : %s" % [a.cell, b.cell, rect])
