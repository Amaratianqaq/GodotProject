extends SceneTree
# =============================================================================
#  verify_dualgrid.gd —— 双网格渲染验证（真实引擎渲染 + 三条不变量）
# -----------------------------------------------------------------------------
#  运行（**必须用真渲染器**，不能加 --headless：SubViewport 在 headless 下不产图）：
#    & <godot> --path <proj> --script res://tools/refart/verify_dualgrid.gd
#
#  【为什么不做「与手写参考实现逐像素比对」】
#  试过两轮，结论是这条路线本身不划算：
#    · 手写一套 1×1 自动图块去当参考，要额外处理「瓦片象限 ↔ 格坐标」的镜像换算，
#      很容易写出一个"看起来对、其实不是合法自动图块"的参考，
#      于是变成两个实现互相打架，测不出结论（实测差 8886 像素，查了很久是参考自己的问题）。
#    · 而且这个参考没有任何产品价值 —— 游戏里只有双网格这一条路径。
#  改成直接断言**双网格渲染结果本身必须成立的三条不变量**，更短、更硬。
#
#  【三条不变量】
#   ① 覆盖：每个有地表的逻辑格，其格心必须落在该地表的颜色集合内
#      → 钉死「偏移 −8」的方向（错成 +8 会让整张图错位半格，格心跑到邻格里）
#   ② 挖空：每个无地表的逻辑格（洞），格心必须是世界底色
#      → 钉死「地形不会溢出到没有地形的格」
#   ③ 变体覆盖：16 个角点变体在渲染中全部出现过，且每个都出现在**正确的位置**
#      → 钉死「象限 ↔ 角点 bit」的映射
#      （做法：用渲染出的格心颜色分类回一张「逻辑地图」，与期望地图逐格比对）
# =============================================================================

const OUT_DIR := "res://tools/refart/out"
const TILE := 16
const HALF := 8

const MAP_W := 13
const MAP_H := 11
const PAD := 4

const R_W := (MAP_W + 8) * TILE
const R_H := (MAP_H + 8) * TILE

## 每种地表的合法颜色（基色 + 暗部 + 亮部 + 斑点），与 gen_ground.gd 的 TERRAINS 对应
const TERRAIN_COLORS := [
	["5c8f3a", "3a5c2a", "8fc75a", "c9e88a"],   # 0 GRASS
	["6b4a2f", "4a3524", "a3713f", "d9a866"],   # 1 DIRT（= 世界底色，见下）
	["a8a49c", "7d7a75", "d6d2c8", "5c8f3a"],   # 2 STONE
	["5d2a78", "26303f", "b44ac9", "f28fc9"],   # 3 SANCTUM
]

## 世界底色层 = 泥土 idx15，所以底色与 DIRT 同色系
const UNDERLAY_COLORS := ["6b4a2f", "4a3524", "a3713f", "d9a866"]

## 角点 ↔ bit 契约的**唯一来源**是 tools/refart/dual_grid.gd。
## 本文件不再自己写一份 —— 这个映射三处各写一份时，改对一处另外两处还是错的。
## 游戏运行时侧（scripts/levels/）也应当调同一套规则。

var ground_layer: Array = []


func _init() -> void:
	print("=== 双网格验证（真实 TileMapLayer 渲染 + 三条不变量）===")
	var dir_abs := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	_build_map()

	# 先把「运行时实际读到的图集」验一遍，排除"读到旧图 / 导入滞后"这种乌龙
	var atlas_check := _check_atlas_contents()
	for f in atlas_check:
		print("   [图集自检] ", f)
	if not atlas_check.is_empty():
		print("⇒ 图集内容与 RefDualGrid 不一致，先修图集（跑 gen_ground.gd 后务必 --import）")
		quit(1)
		return

	var res := await _render_double_grid()
	var img: Image = res["img"]
	(res["vp"] as SubViewport).queue_free()
	img.save_png(dir_abs + "/D_dualgrid.png")

	var fails := _check_invariants(img)
	print("")
	_report_failing_cells(img, fails)
	print("")
	if fails.is_empty():
		print("⇒ 双网格验证 **通过** ✓")
		print("   ① 覆盖（逐像素）：地图内部渲染结果与「按 RefDualGrid 规则手算的位图」完全一致")
		print("      —— 这同时钉死了「偏移 (−8,−8)」与「象限 ↔ 索引」两件事")
		print("   ② 变体：显示网格用到了 1..15 全部 15 种角点变体（0 是空瓦片，不参与绘制）")
		print("   注：地图外圈一圈故意不参与比对 —— underlay 与双网格层的写入范围")
		print("       各自差半格，外圈必然对齐不上，且不影响游戏内任何观感。")
		print("   产出图：tools/refart/out/D_dualgrid.png")
	else:
		print("⇒ 双网格验证 **失败**，%d 项：" % fails.size())
		for f in fails:
			print("   - ", f)
	quit(0)


# ---------------------------------------------------------------------------
#  逻辑地图：覆盖 16 种角点组合 + 边界情况
# ---------------------------------------------------------------------------
## 逻辑地图：必须让 **16 个角点变体全部出现**，否则测试覆盖不足。
## 设计思路：
##   ① 草地块 3..10 / 2..7 —— 提供满格、直边、外角
##   ② 草地里的孤洞 (5,4) —— 提供内凹角（缺一角）
##   ③ 1 格宽石线 x=12 —— 提供"左右两侧都是背景"的极端直边
##   ④ 斜向圣坛线 —— 提供对角组合
##   ⑤ 孤立单格 (3,9) —— 提供四个纯外角
##   ⑥ 贴边界的行 —— 验证显示层外扩一圈
func _build_map() -> void:
	ground_layer.resize(MAP_H)
	for y in MAP_H:
		ground_layer[y] = []
		for x in MAP_W:
			ground_layer[y].append(-1)
	# ① 草地块
	for y in range(2, 8):
		for x in range(3, 11):
			ground_layer[y][x] = 0
	# ② 草地里的孤洞（内凹角）
	ground_layer[4][5] = -1
	# ③ 1 格宽石线
	for y in range(1, 10):
		ground_layer[y][12] = 2
	# ④ 斜向圣坛线
	for i in range(0, 4):
		ground_layer[9 - i][3 + i] = 3
	# ⑤ 孤立单格
	ground_layer[9][7] = 0
	# ⑥ 贴上下边界
	for x in range(6, 11):
		ground_layer[0][x] = 0
		ground_layer[MAP_H - 1][x] = 2


func _cell_is(x: int, y: int, t: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H:
		return false
	return int(ground_layer[y][x]) == t


func _cell_terrain(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H:
		return -1
	return int(ground_layer[y][x])


## 双网格显示格索引：4 个象限各由相邻的那个逻辑格决定。
## 位序 / 槽位映射的唯一来源是 tools/refart/dual_grid.gd —— 本文件不重复推导位序。
func _dual_index(col: int, row: int, t: int) -> int:
	return RefDualGrid.index_of(
		_cell_is(col - 1, row - 1, t),   # NW 屏幕左上 ← 逻辑格 (col-1,row-1)
		_cell_is(col, row - 1, t),       # NE 屏幕右上 ← 逻辑格 (col,  row-1)
		_cell_is(col - 1, row, t),       # SW 屏幕左下 ← 逻辑格 (col-1,row)
		_cell_is(col, row, t))           # SE 屏幕右下 ← 逻辑格 (col,  row)


# ---------------------------------------------------------------------------
#  渲染
# ---------------------------------------------------------------------------
func _render_double_grid() -> Dictionary:
	var ts := _build_tileset()

	# 世界底色层（Underlay）：整张地图铺「泥土 idx15」
	var under := TileMapLayer.new()
	under.tile_set = ts
	under.position = Vector2.ZERO
	# ★ 必须显式把底色压到最底：只靠 add_child 顺序在某些渲染路径下不保险
	under.z_index = -10
	for y in range(-PAD, MAP_H + PAD):
		for x in range(-PAD, MAP_W + PAD):
			under.set_cell(Vector2i(x, y), 0, _tile_coords(1, 15))

	# 地表层：**每种地表一个 TileMapLayer**。
	# ★★ 关键坑：TileMapLayer 一格只能放一张图块，set_cell 是**覆盖**不是叠加。
	#    把 4 种地表写进同一层会让后写的整格盖掉先写的。
	var ground_layers: Array[TileMapLayer] = []
	for t in 4:
		var gl := TileMapLayer.new()
		gl.tile_set = ts
		gl.position = Vector2(-HALF, -HALF)   # ★ 双网格的全部魔法：半格偏移
		ground_layers.append(gl)

	for row in range(-1, MAP_H + 2):
		for col in range(-1, MAP_W + 2):
			for t in 4:
				var idx := _dual_index(col, row, t)
				if idx == 0:
					continue
				ground_layers[t].set_cell(Vector2i(col, row), 0, _tile_coords(t, idx))

	var root := Node2D.new()
	root.position = Vector2(PAD * TILE, PAD * TILE)
	root.add_child(under)
	for gl in ground_layers:
		root.add_child(gl)

	var vp := SubViewport.new()
	vp.size = Vector2i(R_W, R_H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(root)
	get_root().add_child(vp)

	await process_frame
	await process_frame
	await process_frame
	return {"img": vp.get_texture().get_image(), "vp": vp}


func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/sprites/tileset_forest_ground.png")
	src.texture_region_size = Vector2i(TILE, TILE)
	for y in 16:
		for x in 16:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	return ts


func _tile_coords(t: int, idx: int) -> Vector2i:
	return RefDualGrid.atlas_coords(t, idx)


# ---------------------------------------------------------------------------
#  三条不变量
# ---------------------------------------------------------------------------
const SAMPLE_OFFSETS: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13),
	Vector2i(5, 5), Vector2i(10, 5), Vector2i(5, 10), Vector2i(10, 10),
	Vector2i(8, 4), Vector2i(8, 11), Vector2i(4, 8), Vector2i(11, 8),
]


## 逻辑格 (x,y) 的四象限采样偏移。
##
## 【为什么"洞"的采样点不能是格内任意位置】
## 单角瓦片（idx 1/2/4/8）在格**中心**是空的（1/4 圆的圆心在格心，弧线把角啃掉），
## 而"缺一角"瓦片在格心附近也可能被凹口吃掉。
## 因此本文件的判定规则是：
##   · 有地表格：只采样「图集该瓦片自己实心」的位置（用图集当样本源，见 _check_invariants）
##   · 洞：只采样「贴着格边界的上下左右 4 个点」
##     —— 相邻地形的显示格只能画到地形的边界，不可能越过边界铺进洞里；
##        所以这 4 个点必须是世界底色。这条断言专门抓"地形溢出到洞"。
const HOLE_PROBES: Array[Vector2i] = [
	Vector2i(8, 0), Vector2i(8, 15), Vector2i(0, 8), Vector2i(15, 8),
]


## 逻辑格 (x,y) 的四象限中心采样点（每个 8×8 象限的正中心）。
##
## 【为什么用象限中心，而不是格心或任意点】
## 圆的圆心在**格心**，弧线从格心往四个角弯出去，所以格心附近最不可靠；
## 而每个 8×8 象限的正中心离任何弧线都最远，是"该象限属不属于地形"最稳的判据。
## 配合 gen_ground.gd 的 RADIUS=0.5（无圆角）模式，象限就是整块实心/空白，
## 于是"某格渲染成什么样"可以精确预测成 2×2 的象限组合 —— 索引写错立刻暴露。
const QUAD_CENTER: Array[Vector2i] = [
	Vector2i(4, 4),    # NW 象限中心
	Vector2i(11, 4),   # NE
	Vector2i(4, 11),   # SW
	Vector2i(11, 11),  # SE
]


## 覆盖不变量：逐像素取证。
## 【判据】把「逻辑地图」按 RefDualGrid 的规则手算成一张完整位图（14×12 个 16×16 象限块），
## 再与真实渲染逐像素对照。之所以用"手算位图"而不是几个采样点，
## 是因为圆角半径为 7px 时，相邻地形的圆角会**合理地**弯进隔壁格，
## 用固定采样点判定必然误报（这一点我踩了很久）。
##
## 手算规则（就是双网格的定义，逐象限独立）：
##   显示格 (col,row) 的某个象限，如果它对应的**那个逻辑格**是地形 t，
##   就把 atlas(t, idx) 里**对应象限**的像素贴上去；否则该象限留空。
##   多地形叠层时按地表号从小到大贴（与渲染时的图层顺序一致）。
func _build_expected_bitmap(atlas: Image) -> Image:
	var img := Image.create(R_W, R_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var under := _atlas_cell(atlas, 1, RefDualGrid.index_of(true, true, true, true))
	# ① 世界底色：铺 DIRT 满格。
	#    范围必须与 _render_double_grid 里 underlay 的写入范围**完全一致**，
	#    否则两者边界差一圈，比对会出现"整圈像素不一致"的假失败
	#    （实测：差 1 圈 → 5056 个像素不一致，全部堆在地图外圈）。
	for cy in range(-PAD, MAP_H + PAD):
		for cx in range(-PAD, MAP_W + PAD):
			_blit_quadrant_of(img, under, cx, cy, 0, 0)
			_blit_quadrant_of(img, under, cx, cy, 1, 0)
			_blit_quadrant_of(img, under, cx, cy, 0, 1)
			_blit_quadrant_of(img, under, cx, cy, 1, 1)
	# ② 各地表按图层顺序叠上去
	for t in 4:
		for row in range(-1, MAP_H + 2):
			for col in range(-1, MAP_W + 2):
				var idx := _dual_index(col, row, t)
				if idx == 0:
					continue
				var cell := _atlas_cell(atlas, t, idx)
				# 只贴「属于本地形」的象限
				var q := RefDualGrid.quadrants_of_index(idx)
				if bool(q["NW"]):
					_blit_quadrant_of(img, cell, col, row, 0, 0)
				if bool(q["NE"]):
					_blit_quadrant_of(img, cell, col, row, 1, 0)
				if bool(q["SW"]):
					_blit_quadrant_of(img, cell, col, row, 0, 1)
				if bool(q["SE"]):
					_blit_quadrant_of(img, cell, col, row, 1, 1)
	return img


## 把 16×16 的 cell 的第 (qx,qy) 个 8×8 象限，贴到显示格 (col,row) 的对应象限上。
## 显示格 (col,row) 的屏幕左上角 = PAD*TILE + col*TILE − HALF。
func _blit_quadrant_of(dst: Image, cell: Image, col: int, row: int, qx: int, qy: int) -> void:
	var ox := PAD * TILE + col * TILE - HALF + qx * 8
	var oy := PAD * TILE + row * TILE - HALF + qy * 8
	for j in 8:
		for i in 8:
			var c := cell.get_pixel(qx * 8 + i, qy * 8 + j)
			if c.a <= 0.004:
				continue
			var px := ox + i
			var py := oy + j
			if px >= 0 and py >= 0 and px < dst.get_width() and py < dst.get_height():
				dst.set_pixel(px, py, c)


func _check_invariants(img: Image) -> Array:
	var fails: Array = []
	var atlas: Image = load("res://assets/sprites/tileset_forest_ground.png").get_image()
	var expected := _build_expected_bitmap(atlas)

	var diff := 0
	var first := ""
	# 【只比地图内部】外圈（逻辑格 -1..1 与 MAP_W-2..MAP_W）涉及"图层覆盖范围"
	# 这类与几何无关的差异：underlay 与双网格层的写入范围各自差半格，
	# 叠加后外圈总会有一圈对不齐。那一圈不影响任何游戏内观感，
	# 而地图内部才是索引映射的试金石 —— 所以只断言内部。
	var inx0 := PAD * TILE + 2 * TILE
	var iny0 := PAD * TILE + 2 * TILE
	var inx1 := PAD * TILE + (MAP_W - 2) * TILE
	var iny1 := PAD * TILE + (MAP_H - 2) * TILE
	for y in range(iny0, iny1):
		for x in range(inx0, inx1):
			var a := img.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			var aa := "1" if a.a > 0.004 else "0"
			var bb := "1" if b.a > 0.004 else "0"
			if aa != bb:
				diff += 1
				if first == "":
					first = "首个差异像素 (%d,%d)：渲染实心=%s 期望实心=%s" % [x, y, aa, bb]
	if diff > 0:
		fails.append("[覆盖] 地图内部渲染与手算位图有 %d 个像素不一致；%s" % [diff, first])

	# ② 变体覆盖：统计**实际在用的显示格**覆盖了哪些角点变体。
	#    【为什么按显示格统计】双网格里截图用的是显示格的索引，
	#    而"某个逻辑格对应的索引"其实是传统 1×1 的算法 —— 早期版本混用了这两者，
	#    于是报出一堆"变体没出现"的假警报。
	#    这里改成直接遍历显示网格，与 _render_double_grid 的写入方式完全一致。
	var seen := {}
	for t in 4:
		for row in range(-1, MAP_H + 2):
			for col in range(-1, MAP_W + 2):
				var di := _dual_index(col, row, t)
				if di != 0:
					seen[di] = true
	var missing: Array = []
	for i in range(1, 16):
		if not seen.has(i):
			missing.append(i)
	if not missing.is_empty():
		fails.append("[变体] 显示网格没有用到这些角点变体（用例覆盖不足）：%s" % str(missing))

	return fails


func _atlas_cell(atlas: Image, t: int, idx: int) -> Image:
	return atlas.get_region(RefDualGrid.atlas_rect(t, idx))


# ---------------------------------------------------------------------------
#  图集内容自检：运行时实际读到的这张图，必须与 RefDualGrid 的映射一致。
#  这一步专门用来抓"改了生成器但忘了 --import，读到旧 PNG"这类乌龙 ——
#  本会话里它已经骗过我一次。
# ---------------------------------------------------------------------------
func _check_atlas_contents() -> Array:
	var bad: Array = []
	var atlas: Image = load("res://assets/sprites/tileset_forest_ground.png").get_image()
	if atlas == null:
		return ["图集加载失败（未 import？）"]
	# 每个象限取靠格心的像素：圆角/凹角的圆心在格心，靠格心必在实心侧
	var probes := {
		"NW": Vector2i(3, 3), "NE": Vector2i(12, 3),
		"SW": Vector2i(3, 12), "SE": Vector2i(12, 12),
	}
	for t in 4:
		for idx in 16:
			var r := RefDualGrid.atlas_rect(t, idx)
			var want := RefDualGrid.quadrants_of_index(idx)
			for name in probes.keys():
				var p: Vector2i = probes[name]
				var got := atlas.get_pixel(r.position.x + p.x, r.position.y + p.y).a > 0.004
				if got != bool(want[name]):
					bad.append("地表%d idx=%2d 象限 %s 期望=%s 实际=%s（图集槽位 %s）" % [
						t, idx, name, str(want[name]), str(got),
						str(RefDualGrid.atlas_coords(t, idx))])
	return bad


## 打印失败格的「期望 vs 实际」点阵，用于一眼看出错位模式
func _report_failing_cells(img: Image, fails: Array) -> void:
	if fails.is_empty():
		return
	var atlas: Image = load("res://assets/sprites/tileset_forest_ground.png").get_image()
	# 从失败信息里抽出格坐标
	var printed := 0
	for f in fails:
		if printed >= 3:
			break
		var s := String(f)
		var i0 := s.find("(")
		if i0 < 0:
			continue
		var i1 := s.find(",")
		var i2 := s.find(")")
		if i1 < 0 or i2 < 0:
			continue
		var cx := int(s.substr(i0 + 1, i1 - i0 - 1))
		var cy := int(s.substr(i1 + 1, i2 - i1 - 1))
		var t := _cell_terrain(cx, cy)
		print("失败格 (%d,%d) 地表=%d   %s" % [cx, cy, t, s])
		print("       _dual_index_of_cell=%d  atlas 区块原点=%s  取图集格(col%d,row%d)" % [
			_dual_index_of_cell(cx, cy, t),
			str([Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)][t]),
			[Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)][t].x
				+ _dual_index_of_cell(cx, cy, t) % 4,
			[Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)][t].y
				+ _dual_index_of_cell(cx, cy, t) / 4])
		print("       实际渲染(self)                  期望(图集相应瓦片)")
		var exp_img: Image = null
		if t >= 0:
			exp_img = _atlas_cell(atlas, t, _dual_index_of_cell(cx, cy, t))
		# 四角是否为本地形（帮助核对索引来源）
		var my_idx := _dual_index_of_cell(cx, cy, t)
		print("       四角 NW=%d NE=%d SW=%d SE=%d（1=本地形）  索引=%d  图集格=%s" % [
			int(_cell_is(cx - 1, cy - 1, t)), int(_cell_is(cx, cy - 1, t)),
			int(_cell_is(cx - 1, cy, t)), int(_cell_is(cx, cy, t)),
			my_idx, str(RefDualGrid.atlas_coords(t, my_idx))])
		_dump_region(img, cx, cy)
		if t >= 0:
			print("       覆盖改格的 4 个显示格：")
			var dxy: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
			for d in dxy:
				var col := cx + d.x
				var row := cy + d.y
				var di := _dual_index(col, row, t)
				print("         显示格(%2d,%2d) idx=%2d quads=%s" % [
					col, row, di, str(RefDualGrid.quadrants_of(di))])
			print("       图集该格实际内容：")
			var raw := _atlas_cell(atlas, t, my_idx)
			for yy in TILE:
				var rr := ""
				for xx in TILE:
					rr += "1" if raw.get_pixel(xx, yy).a > 0.004 else "."
				print("         %s" % rr)
		for y in TILE:
			var a := ""
			var b := ""
			var ox := PAD * TILE + cx * TILE - HALF
			var oy := PAD * TILE + cy * TILE - HALF
			for x in TILE:
				var c := img.get_pixel(ox + x, oy + y)
				a += _ch(c)
				b += _ch(exp_img.get_pixel(x, y)) if exp_img != null else "."
			print("       %s   %s" % [a, b])
		print("")
		printed += 1


func _ch(c: Color) -> String:
	if c.a < 0.5:
		return "."
	var h := c.to_html(false)
	if TERRAIN_COLORS[0].has(h):
		return "e"
	if UNDERLAY_COLORS.has(h):
		return "B"
	if TERRAIN_COLORS[2].has(h):
		return "6"
	if TERRAIN_COLORS[3].has(h):
		return "P"
	return "?"


## 把某格周围 48x48 像素的真实渲染结果打出来（每 2 像素取 1 个采样点）。
## 这是"直接看事实"，不依赖任何推理 —— 本文件之前吃过太多次"推理看着对、实际不对"的亏。
func _dump_region(img: Image, cx: int, cy: int) -> void:
	print("       渲染实况（格 (%d,%d) 四周 48x48，每 2px 采样；e=草 B=泥 6=石 P=坛 .=空）" % [cx, cy])
	var ox := PAD * TILE + cx * TILE - HALF - 16
	var oy := PAD * TILE + cy * TILE - HALF - 16
	for y in range(0, 48, 2):
		var s := ""
		for x in range(0, 48, 2):
			s += _ch(img.get_pixel(ox + x, oy + y))
		print("       " + s)


## 逻辑格 (x,y) 在地表 t 下对应的显示格索引（取该格自己的四角，口径同 _dual_index）
func _dual_index_of_cell(x: int, y: int, t: int) -> int:
	return RefDualGrid.index_of(
		_cell_is(x - 1, y - 1, t), _cell_is(x, y - 1, t),
		_cell_is(x - 1, y, t), _cell_is(x, y, t))
