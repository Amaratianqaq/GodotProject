class_name RoomData
extends RefCounted
## 一个房间的「数据层」表示（纯数据，不含场景节点）。
##
## 【框架约束】
## 1. 地图生成器只产出 RoomGraph / RoomData，**不** 直接实例化场景。
##    ForestLevel 负责把 RoomData 翻译成 TileMapLayer + 场景节点。
## 2. 房间坐标系统一使用 **图块坐标**（tile），像素坐标 = tile * 16。
## 3. 房间之间只允许通过 doors 里的门洞连通；门洞在墙体图块上开门。

var index: int = -1                  ## 生成顺序索引，用于日志与命名
var cell: Vector2i = Vector2i.ZERO   ## 在房间网格上的格子坐标
var kind: int = GameEnums.RoomKind.EMPTY

## 房间内部（可活动区域）的图块矩形，不含墙
var interior: Rect2i = Rect2i()
## 方向(Dir) -> 门洞中心图块坐标
var doors: Dictionary = {}
## 世界像素坐标下的房间中心
var center_px: Vector2 = Vector2.ZERO

# --- 运行时状态（生成时初始化，游戏中更新） ---
var discovered: bool = false         ## 玩家是否已进入过
var cleared: bool = false            ## 敌人是否已清空
var enemy_budget: int = 0            ## 该房间计划生成的敌人数量
var spawned_enemies: Array = []      ## 已生成的敌人（弱引用数组）
var chest_spawn_points: Array[Vector2] = []
var enemy_spawn_points: Array[Vector2] = []
var decorated: bool = false

## BFS 距离（从入口算起），用于分配房间类型
var depth: int = 0
## 图上的邻居格子
var neighbors: Array[Vector2i] = []


func is_dead_end() -> bool:
	return neighbors.size() <= 1


func dir_to(other_cell: Vector2i) -> int:
	var d := other_cell - cell
	if d == Vector2i(0, -1):
		return GameEnums.Dir.N
	if d == Vector2i(1, 0):
		return GameEnums.Dir.E
	if d == Vector2i(0, 1):
		return GameEnums.Dir.S
	if d == Vector2i(-1, 0):
		return GameEnums.Dir.W
	return -1


func door_position(dir: int) -> Vector2i:
	return doors.get(dir, Vector2i(-1, -1))


func has_door(dir: int) -> bool:
	return doors.has(dir)


func get_interior_world_rect() -> Rect2:
	return Rect2(
		Vector2(interior.position) * float(Atlas.TILE_SIZE),
		Vector2(interior.size) * float(Atlas.TILE_SIZE)
	)


func get_random_point_inside(rng: RandomNumberGenerator, margin: int = 2) -> Vector2:
	var x := rng.randi_range(interior.position.x + margin, interior.position.x + interior.size.x - margin)
	var y := rng.randi_range(interior.position.y + margin, interior.position.y + interior.size.y - margin)
	return Vector2(x, y) * float(Atlas.TILE_SIZE) + Vector2(8, 8)


func contains_world_point(p: Vector2) -> bool:
	return get_interior_world_rect().has_point(p)


func _to_string() -> String:
	return "Room#%d(cell=%s kind=%s depth=%d doors=%d)" % [
		index, cell, GameEnums.RoomKind.keys()[kind], depth, doors.size()
	]
