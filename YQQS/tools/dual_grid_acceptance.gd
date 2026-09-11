extends Node
## 双网格地形运行时验收 —— **场景形态**（必须在场景里跑，不能用 --script）。
##
## 【为什么不是 --script】
## Godot 的自动加载单例是在主循环启动后才注册为全局标识符的，
## 所以 `--script` 跑的脚本里引用 ConfigDB / EventBus 会假性报
## "Identifier not found"，进而让 ForestLevel 整个编译失败、
## instantiate 出来的是个空壳 Node2D —— 所有检查都会静默跳过。
## 本文件就是为了不出现这种"假绿灯"：第一件事就是确认关卡脚本真的生效了。
##
## 运行：
##   & <godot> --headless --path <proj> res://tools/DualGridAcceptance.tscn
## 退出码 0 = 全部通过。

const LEVEL_SCENE := "res://scenes/levels/forest/ForestLevel.tscn"

## 各地表在图集里用到的颜色（gen_ground.gd 的 TERRAINS：基色/暗部/亮部/斑点）
const TERRAIN_COLORS := [
	["5c8f3a", "3a5c2a", "8fc75a", "c9e88a"],   # 0 GRASS
	["6b4a2f", "4a3524", "a3713f", "d9a866"],   # 1 DIRT
	["a8a49c", "7d7a75", "d6d2c8"],             # 2 STONE
	["5d2a78", "26303f", "b44ac9", "f28fc9"],   # 3 SANCTUM
]

var _errors: Array[String] = []
var _logs: Array[String] = []


func _ready() -> void:
	print("[双网格验收] === 开始 ===")
	_run()


func _run() -> void:
	# ① 先把映射本身的契约验一遍（游戏侧 DualGrid vs 生成器侧 RefDualGrid）
	_check_dual_grid_contract()

	var scene: PackedScene = load(LEVEL_SCENE)
	var lvl: Node = scene.instantiate()
	add_child(lvl)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# ★ 防"假绿灯"：确认关卡脚本真的执行了
	var underlay = lvl.get("underlay")
	var floor_data = lvl.get("_floor")
	if underlay == null and floor_data == null:
		_errors.append("关卡脚本未生效（instantiate 得到空壳节点），本次验收无效")
		_finish()
		return

	_check_structure(lvl)
	_check_layer_cells(lvl)
	_check_terrain_coverage(lvl)
	_check_corner_variety(lvl)

	_finish()


func _finish() -> void:
	print("")
	print("[双网格验收] === 结果 ===")
	for l in _logs:
		print("[双网格验收]   OK  ", l)
	if _errors.is_empty():
		print("[双网格验收] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for e in _errors:
			print("[双网格验收]   [ERROR] ", e)
		get_tree().quit(1)


# ---------------------------------------------------------------------------
#  ① 映射契约
# ---------------------------------------------------------------------------
func _check_dual_grid_contract() -> void:
	var bad := DualGrid.self_test()
	if bad.is_empty():
		_logs.append("DualGrid.self_test() 通过（索引↔象限、往返一致、图块坐标在块内）")
	else:
		for b in bad:
			_errors.append("DualGrid 自检失败: " + String(b))
	# 游戏侧与生成器侧必须一致：抽查几个锚点
	var anchors := {1: "NW", 2: "NE", 4: "SW", 8: "SE"}
	for idx in anchors.keys():
		var q := DualGrid.quadrants_of_index(int(idx))
		var solid := 0
		for name in ["NW", "NE", "SW", "SE"]:
			if bool(q[name]):
				solid += 1
		if solid != 1 or not bool(q[String(anchors[idx])]):
			_errors.append("DualGrid 锚点 idx=%d 应为单象限 %s" % [idx, anchors[idx]])
	_logs.append("DualGrid 锚点抽查通过（1=NW 2=NE 4=SW 8=SE）")


# ---------------------------------------------------------------------------
#  ② 节点结构
# ---------------------------------------------------------------------------
func _check_structure(lvl: Node) -> void:
	var underlay = lvl.get("underlay")
	var layers: Array = lvl.get("_ground_layers")
	var ground = lvl.get("ground")

	if underlay == null:
		_errors.append("缺少 GroundUnderlay 层（世界底色）—— 地图边缘会露黑")
	else:
		_logs.append("GroundUnderlay 存在，z_index=%d" % underlay.z_index)

	if layers.size() != 4:
		_errors.append("双网格地表层数量 = %d，期望 4" % layers.size())
	else:
		_logs.append("4 个双网格地表层齐备")

	if ground == null:
		_errors.append("缺少 Walls 层")
	else:
		var pl: int = ground.tile_set.get_physics_layers_count()
		if pl <= 0:
			_errors.append("Walls 层没有物理层 —— 玩家会穿墙")
		else:
			_logs.append("Walls 层存在，物理层 %d 个（碰撞归这里）" % pl)

	# ★ 硬约束：地表层不能有物理层，否则碰撞随显示层偏移半格
	var offset_bad := 0
	var phys_bad := 0
	for gl in layers:
		if gl.tile_set.get_physics_layers_count() != 0:
			phys_bad += 1
		if gl.position != Vector2(-DualGrid.HALF, -DualGrid.HALF):
			offset_bad += 1
	if phys_bad > 0:
		_errors.append("%d 个地表层带物理层 —— 双网格的碰撞必须只放墙体层" % phys_bad)
	if offset_bad > 0:
		_errors.append("%d 个地表层偏移不是 (-8,-8)" % offset_bad)
	if phys_bad == 0 and offset_bad == 0:
		_logs.append("地表层：无物理层、偏移均为 (-8,-8)")


# ---------------------------------------------------------------------------
#  ③ 写入情况
# ---------------------------------------------------------------------------
func _check_layer_cells(lvl: Node) -> void:
	var underlay = lvl.get("underlay")
	var layers: Array = lvl.get("_ground_layers")
	var under_n: int = underlay.get_used_cells().size() if underlay != null else 0
	if under_n <= 0:
		_errors.append("底色层没有写入任何格子")
	else:
		_logs.append("底色层 %d 格" % under_n)

	var per: Array[int] = []
	var total := 0
	for gl in layers:
		var n: int = gl.get_used_cells().size()
		per.append(n)
		total += n
	print("[双网格验收] 各地表层格数（0草 1泥 2石 3坛）: ", per, " 合计 ", total)
	if total <= 0:
		_errors.append("双网格地表层一格都没写进去")
		return
	_logs.append("双网格地表层合计 %d 格" % total)
	if per[0] <= 0:
		_errors.append("草地层为空 —— 普通房间应当是草地")
	else:
		_logs.append("草地层 %d 格（普通房间地表就位）" % per[0])
	# 走廊用的是泥土，必须有内容
	if per[1] <= 0:
		_errors.append("泥土层为空 —— 走廊应当是泥土路")
	else:
		_logs.append("泥土层 %d 格（走廊地表就位）" % per[1])


# ---------------------------------------------------------------------------
#  ④ 四种地表是否都真的用上了
# ---------------------------------------------------------------------------
func _check_terrain_coverage(lvl: Node) -> void:
	var floor_data: Dictionary = lvl.get("_floor")
	var kinds := {}
	for v in floor_data.values():
		kinds[int(v)] = int(kinds.get(int(v), 0)) + 1
	print("[双网格验收] 逻辑格地表分布: ", kinds)
	var missing: Array = []
	for t in [0, 1, 2, 3]:
		if not kinds.has(t):
			missing.append(t)
	if missing.is_empty():
		_logs.append("四种地表（草/泥/石/坛）全部出现在地图上")
	else:
		_errors.append("这些地表一处都没用到：%s（房间类型→地表映射有问题？）" % str(missing))


# ---------------------------------------------------------------------------
#  ⑤ 角点变体是否真的多样（"不是退化回 1x1 平铺"的量化判据）
# ---------------------------------------------------------------------------
## 【为什么需要这条】双网格的价值在于「地貌成片 + 边界自动圆角」。
## 如果每种地表只用满格（idx 15），就退化成了旧的 1×1 平铺：
## 画面看着"有颜色"，但地貌没有衔接感 —— 这正是要换掉的东西。
## 所以要同时确认两件事：
##   ① 满格瓦片占多数（说明有"成片"的区域）
##   ② 但**同时**存在相当数量的部分角点变体（说明边界被圆角处理了）
## 这两条一起成立，才算真的在做双网格。
##
## 【关于"渲染出来了吗"】本文件不自己截图判断 —— SubViewport 只渲染**自己的子节点**，
## 而关卡是兄弟节点，自己搭一个 SubViewport 是拍不到关卡的（会得到纯色，
## 从而误报"地形没画出来"）。渲染验收交给 docs/screenshots 的截图工具。
func _check_corner_variety(lvl: Node) -> void:
	var layers: Array = lvl.get("_ground_layers")
	var full_idx := DualGrid.full_index()
	var per_terrain_full: Array[int] = []
	var per_terrain_total: Array[int] = []
	var distinct := {}
	for t in layers.size():
		var full_n := 0
		var cells: Array = layers[t].get_used_cells()
		var fc := DualGrid.tile_coords(t, full_idx)
		for c in cells:
			var coords: Vector2i = layers[t].get_cell_atlas_coords(c)
			distinct[coords] = true
			if coords == fc:
				full_n += 1
		per_terrain_full.append(full_n)
		per_terrain_total.append(cells.size())
	print("[双网格验收] 满格瓦片数（0草 1泥 2石 3坛）: ", per_terrain_full, " / 总数 ", per_terrain_total)
	print("[双网格验收] 用到的不同图块坐标种类 = %d（上限 64 = 4 地形 x 16 角点）" % distinct.size())
	if distinct.size() < 16:
		_errors.append("只用到 %d 种图块，双网格的角点衔接基本没生效" % distinct.size())
	else:
		_logs.append("用到 %d 种角点瓦片（四种地形都在做衔接）" % distinct.size())

	var g_total: int = per_terrain_total[0]
	var g_full: int = per_terrain_full[0]
	if g_total > 0:
		var r := float(g_full) / float(g_total)
		if r < 0.3:
			_errors.append("草地满格瓦片只占 %.0f%% —— 地貌太碎，不像成片草地" % (r * 100.0))
		elif r > 0.995:
			_errors.append("草地几乎全是满格瓦片 —— 没有边界圆角，双网格退化成 1x1 平铺")
		else:
			_logs.append("草地满格占 %.0f%%（成片 %d 格 + 边界变体 %d 格）" % [
				r * 100.0, g_full, g_total - g_full])
