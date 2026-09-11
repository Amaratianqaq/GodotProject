class_name RoomGraph
extends RefCounted
## 地图拓扑图 —— 地图生成系统的唯一产物。
##
## 【框架约束】
## 1. 生成算法（ForestMapGenerator）只允许产出本对象；渲染、刷怪、放宝箱
##    由 ForestLevel 从本对象读取，二者不得互相越权。
## 2. 所有随机必须来自构造时传入的 RandomNumberGenerator（可播种复现）。
## 3. 房间必须以 (0,0) 为起点做一次 BFS，depth 由 BFS 填充，
##    不允许出现 depth == -1（不可达）的房间。

var seed_value: int = 0
var rooms: Dictionary = {}          ## Vector2i -> RoomData
var start_cell: Vector2i = Vector2i.ZERO
var boss_cell: Vector2i = Vector2i.ZERO
var bounds: Rect2i = Rect2i()       ## 所有房间外接的图块矩形
## 所有走廊的图块矩形（由生成器填充；渲染时直接铺地板）
var corridors: Array[Rect2i] = []
var generation_log: PackedStringArray = PackedStringArray()


func add_room(room: RoomData) -> void:
	rooms[room.cell] = room
	_grow_bounds(room)


func get_room(cell: Vector2i) -> RoomData:
	return rooms.get(cell, null)


func has_room(cell: Vector2i) -> bool:
	return rooms.has(cell)


func get_room_at_world(p: Vector2) -> RoomData:
	var cell_px := float(Atlas.TILE_SIZE)
	for r in rooms.values():
		var rect := Rect2(
			Vector2(r.interior.position) * cell_px,
			Vector2(r.interior.size) * cell_px
		)
		if rect.has_point(p):
			return r
	return null


func all_rooms() -> Array[RoomData]:
	var out: Array[RoomData] = []
	for v in rooms.values():
		out.append(v)
	return out


## 是否所有格子都已连通（BFS 后不应有 depth < 0 的房间）
func is_fully_connected() -> bool:
	for r in rooms.values():
		if r.depth < 0:
			return false
	return true


## 整张地图的图块包围盒（含走廊，向外扩 2 格给墙体留位置）
func tile_bounds_with_margin(margin: int = 2) -> Rect2i:
	var r := Rect2i()
	var first := true
	for room in rooms.values():
		if first:
			r = room.interior
			first = false
		else:
			r = r.merge(room.interior)
	for c in corridors:
		r = r.merge(c)
	return r.grow(margin)


func room_count() -> int:
	return rooms.size()


func room_size_px() -> Vector2:
	if rooms.is_empty():
		return Vector2.ZERO
	var r: RoomData = rooms.values()[0]
	return Vector2(r.interior.size) * float(Atlas.TILE_SIZE)


func _grow_bounds(room: RoomData) -> void:
	if room.interior.size == Vector2i.ZERO:
		return   # 几何还没算，跳过（几何算完后会 recompute_bounds）
	if bounds.size == Vector2i.ZERO:
		bounds = room.interior
	else:
		bounds = bounds.merge(room.interior)


## 重新计算整张地图的图块包围盒。
## 【重要】房间的 interior 是在拓扑生成之后才算出来的，
## 所以几何阶段结束必须调用一次，否则 bounds 会是空矩形（相机会被锁死）。
func recompute_bounds() -> void:
	bounds = Rect2i()
	var first := true
	for r in rooms.values():
		if first:
			bounds = r.interior
			first = false
		else:
			bounds = bounds.merge(r.interior)


## 世界像素坐标下的整张地图包围盒
func world_bounds() -> Rect2:
	return Rect2(
		Vector2(bounds.position) * float(Atlas.TILE_SIZE),
		Vector2(bounds.size) * float(Atlas.TILE_SIZE)
	)


## 邻居房间格子
func neighbor_cells(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in GameEnums.DIR_VECTORS.values():
		var n: Vector2i = cell + d
		if rooms.has(n):
			out.append(n)
	return out


## 从起点做 BFS，填充每个房间的 depth 与 neighbors。
## 返回不可达房间列表（正常情况下应为空）。
func build_distances(from_cell: Vector2i) -> Array[Vector2i]:
	for r in rooms.values():
		r.depth = -1
		r.neighbors = neighbor_cells(r.cell)
	var queue: Array[Vector2i] = [from_cell]
	var root: RoomData = get_room(from_cell)
	if root:
		root.depth = 0
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var cur_room: RoomData = get_room(cur)
		if cur_room == null:
			continue
		for n in cur_room.neighbors:
			var nr: RoomData = get_room(n)
			if nr == null or nr.depth >= 0:
				continue
			nr.depth = cur_room.depth + 1
			queue.append(n)
	var unreachable: Array[Vector2i] = []
	for r in rooms.values():
		if r.depth < 0:
			unreachable.append(r.cell)
	return unreachable


## 距离起点最远的房间（BOSS 房用）
func farthest_from(from_cell: Vector2i) -> Vector2i:
	var best := from_cell
	var best_d := -1
	for r in rooms.values():
		if r.depth > best_d:
			best_d = r.depth
			best = r.cell
	return best


## 只保留一个最优的 BOSS 房：优先「最远且是死路」
func pick_boss_cell(from_cell: Vector2i) -> Vector2i:
	var best := from_cell
	var best_score := -1e9
	for r in rooms.values():
		if r.cell == from_cell:
			continue
		var score := float(r.depth) * 10.0
		if r.is_dead_end():
			score += 25.0
		if r.kind == GameEnums.RoomKind.EMPTY:
			score += 5.0
		if score > best_score:
			best_score = score
			best = r.cell
	return best


## 房间之间最短路径（格子序列）
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not rooms.has(from_cell) or not rooms.has(to_cell):
		return []
	var prev: Dictionary = {from_cell: from_cell}
	var queue: Array[Vector2i] = [from_cell]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur == to_cell:
			break
		for n in neighbor_cells(cur):
			if prev.has(n):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(to_cell):
		return []
	var path: Array[Vector2i] = []
	var c := to_cell
	while c != from_cell:
		path.push_front(c)
		c = prev[c]
	path.push_front(from_cell)
	return path


## 统计各类型房间数量
func count_kind(kind: int) -> int:
	var n := 0
	for r in rooms.values():
		if r.kind == kind:
			n += 1
	return n


## 按类型取房间列表
func rooms_of_kind(kind: int) -> Array[RoomData]:
	var out: Array[RoomData] = []
	for r in rooms.values():
		if r.kind == kind:
			out.append(r)
	return out


## 按 depth 排序（用于放置递进内容）
func rooms_sorted_by_depth() -> Array[RoomData]:
	var arr := all_rooms()
	arr.sort_custom(func(a: RoomData, b: RoomData) -> bool: return a.depth < b.depth)
	return arr


func log_line(s: String) -> void:
	generation_log.append(s)


func dump_log() -> String:
	return "\n".join(generation_log)


func _to_string() -> String:
	return "RoomGraph(seed=%d rooms=%d start=%s boss=%s bounds=%s)" % [
		seed_value, rooms.size(), start_cell, boss_cell, bounds
	]
