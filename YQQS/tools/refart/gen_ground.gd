extends SceneTree
# =============================================================================
#  gen_ground.gd —— 双网格地表图集生成器
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_ground.gd
#
#  产出：
#    assets/sprites/tileset_forest_ground.png   256x256，16 列 x 16 行，每格 16px
#      · 块 (0,0) col 0-3 / row 0-3  → 草地 GRASS   索引 0-15
#      · 块 (1,0) col 4-7 / row 0-3  → 泥土 DIRT    索引 0-15
#      · 块 (0,1) col 0-3 / row 4-7  → 石板 STONE   索引 0-15
#      · 块 (1,1) col 4-7 / row 4-7  → 圣坛 SANCTUM 索引 0-15
#      · 其余全透明（留给后续地图）
#    assets/sprites/tileset_forest_wall.png     128x128，8 列 x 8 行
#
#  几何权威：docs/10_美术素材规格与双网格瓦片契约.md §5
#    索引的位 = 哪些【屏幕象限】是地形：bit1=NW左上 bit2=NE右上 bit4=SW左下 bit8=SE右下
#    索引 → 图集槽位：col = idx % 4，row = idx / 4
#    渲染偏移：显示格整体 -8px（半个瓦片）
#
#  ★★ 索引/象限的映射**只在 tools/refart/dual_grid.gd 里定义一次**。
#     本文件一律调 RefDualGrid，不自己推导 —— 这个映射在开发中手推错过五次，
#     而且每次都只有逐像素比对才能发现（16px 尺度上肉眼看不出来）。
#
#  核心算法（tri-planar mask）：
#    一个显示格压在 4 个逻辑格的公共角点上，所以对格的每个像素分类：
#      · 某个象限的角是本地形 → 画（直边 / 内侧都走这条）
#      · 孤立的凸角（自己无、两个轴向邻居也无）→ 用内圆角裁掉
#    这个条件必须同时要求两个轴向邻居都无，否则 1 格宽的洞会被周围所有显示格
#    各自啃一口，放大成十字。
# =============================================================================

const OUT_DIR := "res://assets/sprites"

## 圆角半径。
## 【可改成 0.5 做"无圆角"验证】半径 0.5 时每个象限几乎整块实心 / 空白，
## 于是"某个逻辑格渲染成什么样"可以精确预测成 2x2 象限组合，
## 索引映射一旦写错立刻暴露（配合 verify_dualgrid.gd 的象限中心采样）。
## 出正式素材时用 7.0。
const RADIUS := 7.0

## 缺角处的背景色。注意：双网格只贴「属于本地形的象限」，背景象限会被丢弃，
## 所以这个颜色实际只在没有 underlay 兜底的调试场景里可见。
const BACKGROUND := "1"

# -----------------------------------------------------------------------------
#  四种地形的材质定义
# -----------------------------------------------------------------------------
#  base 基色 / dark 暗部 / light 亮部 / speck 斑点色 / root 交界处的根线色
const TERRAINS := [
	{
		"id": "GRASS",
		"base": "e", "dark": "G", "light": "E", "speck": "L",
		"root": "g",
	},
	{
		"id": "DIRT",
		"base": "B", "dark": "b", "light": "t", "speck": "T",
		"root": "b",
	},
	{
		"id": "STONE",
		"base": "6", "dark": "5", "light": "7", "speck": "e",
		"root": "5",
	},
	{
		"id": "SANCTUM",
		"base": "P", "dark": "n", "light": "p", "speck": "K",
		"root": "n",
	},
]


func _init() -> void:
	print("=== 双网格地表图集生成 ===")
	# 先把映射自检跑一遍：映射错了后面全是白干
	var bad := RefDualGrid.self_test()
	if not bad.is_empty():
		push_error("[gen_ground] RefDualGrid 自检失败：")
		for b in bad:
			push_error("   - " + String(b))
		quit(1)
		return
	print("  · RefDualGrid 映射自检 通过")

	RefArt.reset_stats()
	var dir_abs := ProjectSettings.globalize_path(OUT_DIR)

	_gen_ground(dir_abs)
	_gen_wall(dir_abs)

	RefArt.report("地表图集")
	quit(0)


# =============================================================================
#  1. 角点几何
# =============================================================================

## 取某个象限的「是否本地形」标记。
## 参数用**象限名**（NW/NE/SW/SE）而不是位号 ——
## 位号在项目里被写错过多次，用名字之后这个错误类型不可能再出现。
func _quad_at(quads: Dictionary, sign_x: int, sign_y: int) -> bool:
	var name := ""
	name += "S" if sign_y > 0 else "N"
	name += "E" if sign_x > 0 else "W"
	return bool(quads.get(name, false))


## 该像素是否属于本地形
func _is_terrain(px_x: int, px_y: int, quads: Dictionary) -> bool:
	var dx := px_x - RefDualGrid.HALF
	var dy := px_y - RefDualGrid.HALF
	var sx := 1 if dx >= 0 else -1
	var sy := 1 if dy >= 0 else -1
	return _corner_or_round(px_x, px_y, sx, sy, quads, RADIUS)


## 单个象限的判定：
##   c = 本象限是否本地形
##   h = 水平方向邻居的象限      v = 垂直方向邻居的象限
##     c=1, h=1 或 v=1 → 实心（有邻居把它连起来，是直边或内侧）
##     c=1, h=0, v=0   → 这一角是孤立的凸角 → 用内圆角裁掉
##     c=0             → 该象限是背景
##
## 【为什么"孤立凸角"必须同时要求 h=0 且 v=0】
## 曾经只判断 c==1 就做内圆角裁切，结果：一个 1 格宽的洞会被周围所有含地形的
## 显示格各自按圆的形状啃一口，洞被放大成十字 / 菱形（实测格心被画成草地）。
## 加上 h/v 条件后，只有真正孤立的那个角会被裁成圆角，
## 直边与内侧完全不受影响 —— 洞的形状才是干净的 1 格正方形。
func _corner_or_round(px_x: int, px_y: int, sx: int, sy: int, quads: Dictionary, radius: float) -> bool:
	if not _quad_at(quads, sx, sy):
		return false
	if not _quad_at(quads, -sx, sy) and not _quad_at(quads, sx, -sy):
		return not _outside_round(px_x, px_y, sx, sy, radius)
	return true


## 弧线的圆心放在「象限靠格心那个角」上（sign>0 时为 8，否则 7）
func _outside_round(px_x: int, px_y: int, sign_x: int, sign_y: int, radius: float) -> bool:
	var cxp := float(RefDualGrid.HALF) if sign_x > 0 else float(RefDualGrid.HALF - 1)
	var cyp := float(RefDualGrid.HALF) if sign_y > 0 else float(RefDualGrid.HALF - 1)
	var dx := float(px_x) - cxp
	var dy := float(px_y) - cyp
	return dx * dx + dy * dy > radius * radius


# =============================================================================
#  2. 确定性噪声（必须周期 16 才能无缝平铺）
# =============================================================================

## 把哈希结果归一化到 [0,1)。
## 【为什么用掩码而不是直接除】_hash 返回完整 int64（可正可负），
## 早先按 2^31 归一化 → 结果恒 >= 1 → 所有像素都被判成同一档（实测的翻车原因）。
static func _unit(h: int) -> float:
	return float(h & 0x1FFFFFFFFFFFFF) / 9007199254740992.0


## 确定性的整数哈希。
## 【为什么不用大质数乘法做哈希】GDScript 的 int 溢出行为在不同运行中结果不一致
## （实测 hash % 13 的分布会整批漂移），生成器里绝对不能依赖它。
func _hash(a: int, b: int, salt: int) -> int:
	var h := (a & 7) * 374761393 + (b & 7) * 668265263 + salt * 1274126177
	h = (h ^ 61) ^ (h >> 11)
	h = h + (h << 3)
	h = h ^ (h >> 5)
	h = h * 2654435761
	return h ^ (h >> 13)


## 周期 16 的**可平铺**块状噪声：16px 瓦片上放一张 4px 间距的菱形晶格。
## 像素 p 的菱形 = 覆盖 p 的 [l, l+4) 区间，l = floor((p+2)/4)*4 % 16；
## 取值 = 四个角点的双线性插值。
## 【为什么无缝】整条链上只出现 %16 与 floor/4，没有任何绝对坐标依赖，
## x=0 与 x=16 得到完全相同的 (l, 权重)，所以相邻两瓦片接缝像素一致。
func _noise16(x: int, y: int, salt: int, cell: int) -> float:
	var xm := x % 16
	var ym := y % 16
	var lx := ((xm + cell / 2) / cell) * cell % 16
	var ly := ((ym + cell / 2) / cell) * cell % 16

	var v00 := _unit(_hash(lx, ly, salt))
	var v10 := _unit(_hash((lx + cell) % 16, ly, salt))
	var v01 := _unit(_hash(lx, (ly + cell) % 16, salt))
	var v11 := _unit(_hash((lx + cell) % 16, (ly + cell) % 16, salt))

	var fx := (float(xm - lx) + float(cell) / 2.0) / float(cell)
	var fy := (float(ym - ly) + float(cell) / 2.0) / float(cell)

	var a := v00 + (v10 - v00) * fx
	var b := v01 + (v11 - v01) * fx
	return absf(a + (b - a) * fy)


## 细碎斑点用的**纯哈希**（不是插值噪声）：必须落在单个像素上，
## 插值噪声会糊成一块块云，拼起来像脏渍而不是"颗粒"。
func _speck(x: int, y: int, salt: int) -> float:
	return _unit(_hash(x % 16, y % 16, salt))


## 地表底色：基色为主 + 少量噪点压暗 / 提亮 + 单像素斑点。
## 【配比目标】基色约 70%、暗部约 12%、亮部约 12%、斑点约 6%。
## 基色占太少会变成"一块亮一块暗"的花被子，失掉成片地貌的干净感。
func _ground_color(x: int, y: int, terrain: Dictionary) -> Color:
	var key := String(terrain["base"])
	var n := _noise16(x, y, 11, 4)
	if n > 0.72:
		key = String(terrain["dark"])
	elif n < 0.30:
		key = String(terrain["light"])
	if _speck(x, y, 29) > 0.955:
		key = String(terrain["speck"])
	return RefArt.col(key)


# =============================================================================
#  3. 生成一个角点瓦片
# =============================================================================

## quads: {"NW":bool,"NE":bool,"SW":bool,"SE":bool} —— 哪些屏幕象限是本地形
func _tile(terrain: Dictionary, quads: Dictionary) -> Image:
	var img := RefArt.new_img(RefDualGrid.TILE, RefDualGrid.TILE)
	# 逐像素判定地形 / 背景。**背景保持透明**：
	# 世界的底色由运行时的一张 underlay 图块负责（契约 §5.6），
	# 这样 16 张瓦片里只有真正的地形像素会被写上去。
	for y in RefDualGrid.TILE:
		for x in RefDualGrid.TILE:
			if _is_terrain(x, y, quads):
				RefArt.px_c(img, x, y, _ground_color(x, y, terrain))
	# 交界处的根线 / 内侧亮边（让圆角边界读得出来）
	_edge_pass(img, terrain)
	# 【注意】这里**不做**"背景侧接触落影"：
	#   双网格只贴属于本地形的象限，背景象限会被丢弃 →
	#   画在背景侧的落影永远显示不出来，还可能被邻格地形色覆盖。
	#   交界处的深色感由地形侧的根线给出，已经足够。
	return img


## 在「地形 → 背景」的边界上：地形侧压一道深色根线，受光侧跟一行亮边
func _edge_pass(img: Image, terrain: Dictionary) -> void:
	var to_root: Array[Vector2i] = []
	var to_light: Array[Vector2i] = []
	for y in RefDualGrid.TILE:
		for x in RefDualGrid.TILE:
			if not RefArt.opaque(img, x, y):
				continue
			var exposed := false
			if not RefArt.opaque(img, x + 1, y) or not RefArt.opaque(img, x - 1, y) \
					or not RefArt.opaque(img, x, y + 1) or not RefArt.opaque(img, x, y - 1):
				exposed = true
			if not exposed:
				continue
			# 光源在左上：靠下 / 靠右的暴露面压暗，靠上 / 靠左的暴露面提亮
			var lower := not RefArt.opaque(img, x, y + 1) or not RefArt.opaque(img, x + 1, y)
			if lower:
				to_root.append(Vector2i(x, y))
			else:
				to_light.append(Vector2i(x, y))
	for p in to_root:
		RefArt.px(img, p.x, p.y, String(terrain["root"]))
	for p in to_light:
		RefArt.px(img, p.x, p.y, String(terrain["light"]))


# =============================================================================
#  4. 组装地表图集
# =============================================================================

func _gen_ground(dir_abs: String) -> void:
	var sheet := RefArt.new_img(256, 256)
	for t in TERRAINS.size():
		var terrain: Dictionary = TERRAINS[t]
		for i in 16:
			# 哪些象限实心 —— 直接问 RefDualGrid，本文件不自己推导位序
			var quads: Dictionary = RefDualGrid.quadrants_of_index(i)
			var cell := _tile(terrain, quads)
			var at := RefDualGrid.atlas_coords(t, i)
			RefArt.put(sheet, cell, RefDualGrid.TILE, RefDualGrid.TILE, at.x, at.y)
			_assert_tile_quads(sheet, at, i, terrain)
		print("  - %-8s 块 %s 索引 0-15 OK" % [
			terrain["id"], str(RefDualGrid.BLOCK_ORIGIN[t])])
	# 自检：可平铺性（满格瓦片左右列 / 上下行必须逐像素一致）
	_verify_seamless(sheet)
	RefArt.save(sheet, dir_abs, "tileset_forest_ground.png")


## 自检：把刚写进图集的瓦片读回来，确认「实心象限」正好等于该索引的位。
## 位序一旦写反，这里立刻红。
func _assert_tile_quads(sheet: Image, at: Vector2i, idx: int, terrain: Dictionary) -> void:
	var ox := at.x * RefDualGrid.TILE
	var oy := at.y * RefDualGrid.TILE
	# 每个象限取「靠格心」的像素：圆的圆心在格心附近，靠格心必落在实心侧
	var probes := {
		"NW": Vector2i(3, 3), "NE": Vector2i(12, 3),
		"SW": Vector2i(3, 12), "SE": Vector2i(12, 12),
	}
	var want: Dictionary = RefDualGrid.quadrants_of_index(idx)
	for k in probes.keys():
		var p: Vector2i = probes[k]
		var got := RefArt.opaque(sheet, ox + p.x, oy + p.y)
		if got != bool(want[k]):
			push_error("[gen_ground] 瓦片自检失败：%s idx=%d 象限 %s 期望实心=%s 实际=%s" % [
				terrain["id"], idx, k, str(want[k]), str(got)])


## 满格瓦片（四象限全实心）必须能无缝自接。
## 【断言什么】地形覆盖范围在左右 / 上下边界上必须逐像素一致
## （x=0 与 x=15 列的地形 / 背景归属相同、y=0 与 y=15 行相同）。
## 颜色本身允许不同：细碎斑点本来就该跨格变化；
## 真正肉眼可见的接缝全部来自形状不对齐。
func _verify_seamless(sheet: Image) -> void:
	var all_ok := true
	for t in TERRAINS.size():
		var full_idx := RefDualGrid.index_of(true, true, true, true)
		var at := RefDualGrid.atlas_coords(t, full_idx)
		var ox := at.x * RefDualGrid.TILE
		var oy := at.y * RefDualGrid.TILE
		var ok := true
		for i in RefDualGrid.TILE:
			if RefArt.opaque(sheet, ox, oy + i) != RefArt.opaque(sheet, ox + RefDualGrid.TILE - 1, oy + i):
				ok = false
				break
			if RefArt.opaque(sheet, ox + i, oy) != RefArt.opaque(sheet, ox + i, oy + RefDualGrid.TILE - 1):
				ok = false
				break
		if not ok:
			all_ok = false
		print("  - %-8s 满格瓦片无缝自接：%s" % [
			TERRAINS[t]["id"], "通过" if ok else "**失败**"])
	if all_ok:
		print("  => 地表图集可无缝平铺")


# =============================================================================
#  5. 墙体 / 建筑图集（128x128，8x8）
# =============================================================================

func _gen_wall(dir_abs: String) -> void:
	var sheet := RefArt.new_img(128, 128)
	for i in 64:
		RefArt.put(sheet, _wall_tile(i), RefDualGrid.TILE, RefDualGrid.TILE, i % 8, i / 8)
	RefArt.save(sheet, dir_abs, "tileset_forest_wall.png")


func _wall_tile(i: int) -> Image:
	var img := RefArt.new_img(RefDualGrid.TILE, RefDualGrid.TILE)
	var row := i / 8
	var c := i % 8
	match row:
		0:
			_cliff_top(img, c)
		1:
			_cliff_face(img, c)
		2:
			_cliff_bottom(img, c)
		3:
			_cliff_side(img, c)
		4:
			_structure(img, c)
		5:
			_ritual(img, c)
		6:
			_hazard(img, c)
		7:
			_misc(img, c)
	return img


func _cliff_top(img: Image, c: int) -> void:
	RefArt.fill_rect(img, 0, 0, 16, 16, "b")
	RefArt.fill_rect(img, 0, 0, 16, 6, "6")
	RefArt.hline(img, 0, 15, 0, "7")
	RefArt.hline(img, 0, 15, 5, "5")
	for x in 16:
		if _hash(x, c, 3) % 5 == 0:
			RefArt.px(img, x, 4, "7")
	var left_end := c == 0 or c == 5 or c == 4
	var right_end := c == 3 or c == 6 or c == 4
	if left_end:
		RefArt.vline(img, 0, 0, 15, "k")
		RefArt.px(img, 1, 0, "7")
	if right_end:
		RefArt.vline(img, 15, 0, 15, "k")
	if c == 7:
		RefArt.fill_rect(img, 5, 0, 6, 7, "b")
		RefArt.hline(img, 5, 10, 6, "k")
		RefArt.hline(img, 5, 10, 0, "5")
	if c == 1 or c == 2:
		for x in range(2, 14, 5):
			RefArt.px(img, x, 3, "5")


func _cliff_face(img: Image, c: int) -> void:
	RefArt.fill_rect(img, 0, 0, 16, 16, "B")
	match c:
		0:
			RefArt.band_v(img, 0, 0, 16, 16, ["b"])
			RefArt.hline(img, 0, 15, 0, "k")
		1:
			RefArt.fill_rect(img, 0, 0, 16, 16, "t")
			RefArt.hline(img, 0, 15, 0, "T")
		2, 3:
			RefArt.fill_rect(img, 0, 0, 16, 16, "t")
			for y in range(3 + c, 16, 6):
				RefArt.hline(img, 0, 15, y, "b")
		4:
			RefArt.fill_rect(img, 0, 0, 16, 16, "t")
			for i in 9:
				RefArt.px(img, (i * 2 - (i % 2)) % 16, (3 + i) % 16, "e")
			RefArt.hline(img, 0, 15, 0, "G")
		5:
			RefArt.band_v(img, 0, 0, 16, 16, ["T", "t", "B", "b"])
		6:
			RefArt.fill_rect(img, 0, 0, 16, 16, "B")
			for i in 6:
				var x := 2 + (i * 3) % 13
				var y := 3 + (i * 5) % 12
				RefArt.px(img, x, y, "k")
				RefArt.px(img, x + 1, y, "b")
		7:
			RefArt.band_v(img, 0, 0, 16, 16, ["t", "B", "b", "k"])
	RefArt.hline(img, 0, 15, 15, "k")


func _cliff_bottom(img: Image, c: int) -> void:
	RefArt.fill_rect(img, 0, 0, 16, 16, "b")
	RefArt.hline(img, 0, 15, 11, "k")
	RefArt.fill_rect(img, 0, 12, 16, 4, "k")
	if c == 0 or c == 4:
		RefArt.vline(img, 0, 0, 15, "k")
	if c == 3 or c == 7:
		RefArt.vline(img, 15, 0, 15, "k")
	if c == 4 or c == 5:
		RefArt.fill_rect(img, 4, 11, 8, 5, "b")
		RefArt.hline(img, 4, 11, 11, "k")
	if c == 6 or c == 7:
		RefArt.hline(img, 0, 15, 10, "k")
		RefArt.hline(img, 0, 15, 11, "b")


func _cliff_side(img: Image, c: int) -> void:
	RefArt.fill_rect(img, 0, 0, 16, 16, "b")
	match c:
		0:
			RefArt.fill_rect(img, 0, 0, 8, 16, "t")
			RefArt.vline(img, 0, 0, 15, "k")
			RefArt.vline(img, 8, 0, 15, "k")
		1:
			RefArt.fill_rect(img, 7, 0, 9, 16, "t")
			RefArt.vline(img, 7, 0, 15, "k")
		2:
			RefArt.fill_rect(img, 8, 0, 8, 16, "t")
			RefArt.vline(img, 0, 0, 15, "k")
			RefArt.vline(img, 8, 0, 15, "k")
		3:
			RefArt.fill_rect(img, 0, 0, 9, 16, "t")
			RefArt.vline(img, 9, 0, 15, "k")
		4:
			RefArt.fill_rect(img, 0, 0, 16, 16, "k")
		5:
			RefArt.fill_rect(img, 0, 0, 16, 16, "k")
			for i in 7:
				RefArt.px(img, 2 + (i * 5) % 12, 2 + (i * 3) % 12, "G")
		6:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			RefArt.fill_rect(img, 5, 5, 6, 6, "k")
		7:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			RefArt.fill_rect(img, 0, 0, 6, 6, "k")
			RefArt.fill_rect(img, 10, 10, 6, 6, "k")


func _structure(img: Image, c: int) -> void:
	match c:
		0, 1:
			RefArt.fill_rect(img, 0, 0, 16, 16, "T")
			for y in 16:
				if y % 4 == 3:
					RefArt.hline(img, 0, 15, y, "t")
			if c == 1:
				for x in [3, 11]:
					RefArt.vline(img, x, 0, 15, "b")
					RefArt.vline(img, x + 1, 0, 15, "t")
		2, 3:
			RefArt.fill_rect(img, 0, 0, 16, 16, "6")
			for y in range(0, 16, 4):
				RefArt.hline(img, 0, 15, y, "5")
				var off := 0 if (y / 4) % 2 == 0 else 4
				for x in range(off, 16, 8):
					RefArt.vline(img, x, y, y + 3, "5")
			if c == 3:
				for i in 5:
					RefArt.px(img, 2 + (i * 7) % 13, 3 + (i * 5) % 11, "k")
		4:
			RefArt.fill_rect(img, 0, 0, 16, 16, "G")
			for y in 16:
				var half := y / 2 + 1
				for x in range(8 - half, 8 + half):
					RefArt.px(img, x, y, "K" if y < 8 else "R")
			RefArt.vline(img, 8, 0, 15, "k")
			RefArt.hline(img, 0, 15, 15, "k")
		5:
			RefArt.fill_rect(img, 0, 0, 16, 16, "G")
			RefArt.hline(img, 0, 15, 5, "T")
			RefArt.hline(img, 0, 15, 6, "t")
			RefArt.hline(img, 0, 15, 10, "T")
			RefArt.hline(img, 0, 15, 11, "t")
			for x in [2, 13]:
				RefArt.fill_rect(img, x, 2, 2, 14, "B")
		6:
			RefArt.fill_rect(img, 0, 0, 16, 16, "n")
			RefArt.hline(img, 0, 15, 0, "T")
			RefArt.hline(img, 0, 15, 1, "t")
			RefArt.hline(img, 0, 15, 15, "k")
			for x in range(0, 16, 5):
				RefArt.vline(img, x, 0, 15, "b")
		7:
			RefArt.fill_rect(img, 0, 0, 16, 16, "n")
			RefArt.vline(img, 0, 0, 15, "T")
			RefArt.vline(img, 1, 0, 15, "t")
			RefArt.vline(img, 15, 0, 15, "k")
			for y in range(0, 16, 5):
				RefArt.hline(img, 0, 15, y, "b")


func _ritual(img: Image, c: int) -> void:
	match c:
		0:
			RefArt.fill_rect(img, 0, 0, 16, 16, "6")
			RefArt.hline(img, 0, 15, 0, "7")
			RefArt.hline(img, 0, 15, 15, "5")
			RefArt.vline(img, 0, 0, 15, "5")
			RefArt.vline(img, 15, 0, 15, "5")
		1:
			RefArt.fill_rect(img, 0, 0, 16, 16, "P")
			RefArt.ellipse(img, 8, 8, 5, 5, "p")
			RefArt.ellipse(img, 8, 8, 2, 2, "K")
			RefArt.px(img, 8, 8, "W")
		2:
			RefArt.fill_rect(img, 0, 0, 16, 16, "P")
			for i in range(16):
				RefArt.px(img, i, (i % 3) * 6 + 2, "p")
				RefArt.px(img, i, 15 - ((i % 3) * 6 + 2), "p")
		3:
			RefArt.fill_rect(img, 0, 0, 16, 16, "6")
			for i in 6:
				RefArt.px(img, 1 + (i * 5) % 14, 1 + (i * 7) % 14, "e")
			RefArt.hline(img, 0, 15, 0, "7")
		4:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			for i in 5:
				var x := 2 + i * 3
				RefArt.line(img, x, 0, x + 1, 15, "E")
				RefArt.line(img, x + 1, 0, x, 15, "G")
		5:
			RefArt.fill_rect(img, 0, 0, 16, 16, "B")
			for i in 7:
				RefArt.px(img, 1 + (i * 3) % 14, 2 + (i * 5) % 12, "t")
				RefArt.px(img, 2 + (i * 7) % 13, 3 + (i * 3) % 11, "O")
		6:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			RefArt.fill_rect(img, 0, 8, 16, 8, "G")
			RefArt.hline(img, 0, 15, 8, "g")
			for i in 5:
				RefArt.px(img, 1 + (i * 4) % 14, 2 + (i * 3) % 5, "E")
		7:
			RefArt.fill_rect(img, 0, 0, 16, 16, "k")
			RefArt.fill_rect(img, 1, 1, 14, 14, "1")
			RefArt.hline(img, 0, 15, 0, "b")
			RefArt.hline(img, 0, 15, 15, "b")
			RefArt.vline(img, 0, 0, 15, "b")
			RefArt.vline(img, 15, 0, 15, "b")


func _hazard(img: Image, c: int) -> void:
	match c:
		0, 1:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			for i in range(0, 16, 4):
				for y in range(12, 3, -1):
					RefArt.px(img, i + 1, y, "7")
					RefArt.px(img, i + 2, y, "6")
				RefArt.px(img, i + 1, 3, "w")
			if c == 1:
				RefArt.ellipse(img, 8, 12, 3, 2, "w")
				RefArt.px(img, 7, 12, "k")
				RefArt.px(img, 9, 12, "k")
		2:
			RefArt.fill_rect(img, 0, 0, 16, 16, "n")
			for i in 8:
				RefArt.hline(img, 0, 15, i * 2, "N")
		3:
			RefArt.fill_rect(img, 0, 0, 16, 16, "c")
			for i in 8:
				RefArt.hline(img, 0, 15, i * 2, "C")
		4:
			RefArt.fill_rect(img, 0, 0, 16, 16, "o")
			for i in 6:
				RefArt.px(img, 2 + (i * 5) % 12, 3 + (i * 7) % 10, "O")
				RefArt.px(img, 3 + (i * 3) % 11, 5 + (i * 5) % 9, "R")
		5:
			RefArt.fill_rect(img, 0, 0, 16, 16, "N")
			RefArt.ellipse(img, 8, 8, 6, 6, "C")
			RefArt.ellipse(img, 8, 8, 3, 3, "n")
			RefArt.px(img, 8, 8, "W")
		6:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			RefArt.fill_rect(img, 2, 6, 12, 10, "B")
			RefArt.hline(img, 2, 13, 6, "t")
		7:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			RefArt.fill_rect(img, 4, 2, 8, 14, "B")
			RefArt.fill_rect(img, 2, 4, 12, 2, "t")
			RefArt.px(img, 5, 6, "R")
			RefArt.px(img, 10, 6, "R")


func _misc(img: Image, c: int) -> void:
	match c:
		0:
			RefArt.fill_rect(img, 0, 0, 16, 16, "k")
		1:
			RefArt.fill_rect(img, 0, 0, 16, 16, "1")
		2:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			for i in 8:
				RefArt.px(img, 1 + (i * 3) % 14, 1 + (i * 5) % 14, "G")
				RefArt.px(img, 2 + (i * 5) % 13, 2 + (i * 3) % 13, "e")
		3:
			RefArt.fill_rect(img, 0, 0, 16, 16, "5")
			RefArt.ellipse(img, 8, 9, 6, 6, "k")
			RefArt.ellipse(img, 8, 10, 4, 4, "1")
			RefArt.hline(img, 0, 15, 0, "b")
		4:
			RefArt.fill_rect(img, 0, 0, 16, 16, "6")
			for i in 4:
				RefArt.fill_rect(img, 1 + i * 4, 4 + i * 3, maxi(14 - i * 4, 1), 3,
					"7" if i % 2 == 0 else "5")
		5:
			RefArt.fill_rect(img, 0, 0, 16, 16, "T")
			for x in range(0, 16, 5):
				RefArt.vline(img, x, 0, 15, "t")
			RefArt.hline(img, 0, 15, 0, "t")
		6:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			RefArt.ellipse(img, 8, 11, 4, 2, "B")
			RefArt.line(img, 5, 10, 7, 5, "B")
			RefArt.line(img, 11, 10, 9, 5, "B")
			RefArt.ellipse(img, 8, 5, 2, 3, "o")
			RefArt.px(img, 8, 7, "O")
			RefArt.px(img, 8, 6, "Y")
		7:
			RefArt.fill_rect(img, 0, 0, 16, 16, "b")
			for i in 5:
				RefArt.ellipse(img, 2 + (i * 4) % 13, 3 + (i * 3) % 12, 2, 1, "w")
			RefArt.ellipse(img, 8, 6, 3, 3, "6")
			RefArt.px(img, 7, 6, "k")
			RefArt.px(img, 9, 6, "k")
			RefArt.hline(img, 7, 9, 8, "k")
