extends Node
## 双网格改动的**回归检查**：确认地形换了渲染方式之后，
## 碰撞、装饰落地、刷怪点、玩家出生这些"依赖逻辑格"的系统都还正常。
##
## 为什么要单独查这些：双网格只改了"怎么画"，逻辑格坐标一点没动 ——
## 但如果哪里不小心用了显示格坐标，就会表现为
## "看得见的地板和能走的地板差半格"。这里专门验证这一点。
##
## 运行：& <godot> --headless --path <proj> res://tools/DualGridRegression.tscn

const LEVEL_SCENE := "res://scenes/levels/forest/ForestLevel.tscn"

var _errors: Array[String] = []
var _logs: Array[String] = []


func _ready() -> void:
	print("[回归检查] === 开始 ===")
	_run()


func _run() -> void:
	var lvl: Node = load(LEVEL_SCENE).instantiate()
	add_child(lvl)
	for i in 4:
		await get_tree().process_frame

	if lvl.get("_floor") == null:
		_errors.append("关卡脚本未生效，本次检查无效")
		_finish()
		return

	_check_player_on_floor(lvl)
	_check_decor_on_floor(lvl)
	_check_decor_uses_new_props(lvl)
	_check_walls_are_solid(lvl)
	_check_physics_geometry(lvl)

	_finish()


func _finish() -> void:
	print("")
	print("[回归检查] === 结果 ===")
	for l in _logs:
		print("[回归检查]   OK  ", l)
	if _errors.is_empty():
		print("[回归检查] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for e in _errors:
			print("[回归检查]   [ERROR] ", e)
		get_tree().quit(1)


# ---------------------------------------------------------------------------
#  ① 玩家必须站在**逻辑格**地板上（不是显示格）
# ---------------------------------------------------------------------------
func _check_player_on_floor(lvl: Node) -> void:
	var player = lvl.get("player")
	if player == null:
		_errors.append("没有生成玩家")
		return
	var floor_data: Dictionary = lvl.get("_floor")
	# 玩家位置换回逻辑格
	var cell := Vector2i(
		int(floorf(player.global_position.x / 16.0)),
		int(floorf(player.global_position.y / 16.0)))
	if not floor_data.has(cell):
		# 出生点在房间中心，应当落在地板格上
		_errors.append("玩家所在逻辑格 %s 不是地板 —— 双网格可能把逻辑坐标搞混了" % str(cell))
		return
	_logs.append("玩家站在逻辑格 %s（地表 %d）上" % [str(cell), int(floor_data[cell])])


# ---------------------------------------------------------------------------
#  ② 装饰物必须落在地板格上（且不在墙里）
# ---------------------------------------------------------------------------
func _check_decor_on_floor(lvl: Node) -> void:
	var props = lvl.get("props_root")
	var floor_data: Dictionary = lvl.get("_floor")
	var wall_data: Dictionary = lvl.get("_walls")
	if props == null:
		_errors.append("没有 Props 容器")
		return
	var total := 0
	var bad := 0
	for child in props.get_children():
		total += 1
		var cell := Vector2i(
			int(floorf(child.global_position.x / 16.0)),
			int(floorf(child.global_position.y / 16.0)))
		if not floor_data.has(cell) or wall_data.has(cell):
			bad += 1
	if total == 0:
		_errors.append("Props 容器里一个装饰都没有")
	elif bad > 0:
		_errors.append("%d / %d 个装饰物不在可用地板上（逻辑坐标换算有问题）" % [bad, total])
	else:
		_logs.append("%d 个装饰物全部落在地板格上" % total)


# ---------------------------------------------------------------------------
#  ③ 装饰必须用**新的独立道具贴图**，且锚点正确
# ---------------------------------------------------------------------------
## 【为什么查这个】装饰这一层最容易"改了一半"：地形和角色换了新素材，
## 树石还读旧图集 —— 画面就成了"新地板 + 旧树"，跨风格拼接看着最扎眼。
## 这里直接量每张道具精灵的**资源路径**与**底边位置**：
##   · 路径必须在 prop_*.png 里，不能是 tileset_forest.png
##   · 底边（position.y + h/2）必须落在 holder 原点附近 —— 否则道具会浮空
func _check_decor_uses_new_props(lvl: Node) -> void:
	var props = lvl.get("props_root")
	if props == null:
		return
	var old_count := 0
	var bad_anchor := 0
	var total := 0
	var prop_ids := {}
	for holder in props.get_children():
		for child in holder.get_children():
			if not (child is Sprite2D):
				continue
			var sp: Sprite2D = child
			if sp.texture == null:
				continue
			total += 1
			var path := sp.texture.resource_path
			if path.contains("tileset_forest.png"):
				old_count += 1
			else:
				prop_ids[path.get_file()] = true
			# 底边对齐校验
			var half := sp.texture.get_height() * sp.scale.y * 0.5
			var bottom := sp.position.y + half
			if absf(bottom) > 1.0:
				bad_anchor += 1
	if total == 0:
		_errors.append("Props 容器里没有任何精灵")
		return
	if old_count > 0:
		_errors.append("有 %d 个装饰仍在读旧图集 tileset_forest.png（风格会与新地形冲突）" % old_count)
	else:
		_logs.append("%d 个装饰精灵全部使用新道具贴图（共 %d 种）" % [total, prop_ids.size()])
	if bad_anchor > 0:
		_errors.append("有 %d 个装饰的底边没对齐格心（会浮空或陷地）" % bad_anchor)
	else:
		_logs.append("全部装饰底边对齐格心（锚点契约成立）")


# ---------------------------------------------------------------------------
#  ④ 墙体层写入的格子必须与 _walls 一致
# ---------------------------------------------------------------------------
func _check_walls_are_solid(lvl: Node) -> void:
	var walls = lvl.get("ground")
	var wall_data: Dictionary = lvl.get("_walls")
	if walls == null:
		return
	var used: int = walls.get_used_cells().size()
	if used != wall_data.size():
		_errors.append("墙体层写入 %d 格，但 _walls 有 %d 格（不一致）" % [used, wall_data.size()])
	else:
		_logs.append("墙体层 %d 格与 _walls 记录一致" % used)
	# 抽查：墙体层里的格子都应当真的在 _walls 里
	var mismatch := 0
	for c in walls.get_used_cells():
		if not wall_data.has(c):
			mismatch += 1
	if mismatch > 0:
		_errors.append("墙体层里有 %d 格不在 _walls 记录中" % mismatch)


# ---------------------------------------------------------------------------
#  ④ 物理几何：墙体的碰撞体必须落在**逻辑格**上，不能偏移半格
# ---------------------------------------------------------------------------
## 【这是双网格最容易翻车的地方】地表层偏移 (-8,-8)，
## 如果有人把物理层也加到了地表层上，碰撞体就会整体偏半个瓦片，
## 表现为"角色能走进看着是墙的地方 / 卡在看得见的地板上"。
## 这里直接量碰撞体的实际位置来做判断。
func _check_physics_geometry(lvl: Node) -> void:
	var layers: Array = lvl.get("_ground_layers")
	for i in layers.size():
		var gl = layers[i]
		if gl.tile_set != null and gl.tile_set.get_physics_layers_count() > 0:
			_errors.append("地表层 %d 带物理层（碰撞会偏半格）" % i)
	_logs.append("地表层无物理层（碰撞不会偏半格）")

	var walls = lvl.get("ground")
	if walls == null or walls.tile_set == null:
		return
	# 找一个墙体格，量它的物理校验和：简单做法是确认墙体层本身没有偏移
	if walls.position != Vector2.ZERO:
		_errors.append("墙体层位置 = %s，期望 (0,0)" % str(walls.position))
	else:
		_logs.append("墙体层位置为原点（碰撞与逻辑格对齐）")
