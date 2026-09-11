class_name DualGrid
extends RefCounted
## 双网格（dual-grid）瓦片映射 —— 游戏侧运行时使用。
##
## 【这个文件是什么】
## 把「逻辑格 → 显示格索引」这条映射定义在一个地方，供 ForestLevel / ForestTileset
## 使用。**禁止在别处再推导一份** —— 这个 16 项映射在开发中改错过五次，
## 而且每次都只有逐像素比对才能发现（16px 尺度上肉眼看不出来）。
##
## 生成器侧有一份等价实现 tools/refart/dual_grid.gd（带 self_test()），
## 两边必须保持一致：改动这里请同步跑
##   tools/refart/gen_ground.gd（自带逐瓦片自检）
##   tools/refart/verify_dualgrid.gd（真渲染逐像素比对，必须全绿）
##
## 【渲染模型】
##   逻辑格（A 格）：决定"这里是不是草地" —— 数据、碰撞、刷怪都在这一层，
##                  坐标与房间/走廊/刷怪点完全一致，不需要任何换算。
##   显示格（B 格）：画图的位置，整个图层偏移 (−8,−8)（半个瓦片）。
##                  偏移后每个显示格恰好压在 4 个逻辑格的**公共角点**上，
##                  所以它只需要知道这 4 个逻辑格属于哪种地形 → 16 种组合
##                  → 16 张瓦片覆盖全部角点情形。
##
## 【索引位序】
##   索引 = 四个角是否本地形的位掩码（row-major）：
##       bit1(1) = NW 左上      bit2(2) = NE 右上
##       bit4(4) = SW 左下      bit8(8) = SE 右下
##   图集里第 i 个瓦片的槽位 = (i % 4, i / 4)，块内 4×4。
##
## 【为什么不是 47 张 blob】
##   传统自动图块要穷举「4 邻居 + 4 对角」的 47 种组合；双网格因为显示格只压角点，
##   只需 16 张。少掉的 31 张不是被省掉了，而是本来就不需要 —— 角点组合本来就
##   只有 16 种。省下来的是美术工作量，不是表现力。

const TILE := 16          ## 一个瓦片的边长（像素），必须等于 Atlas.TILE_SIZE
const HALF := 8           ## 显示层偏移量 = 半个瓦片
const COLS := 4           ## 每种地形在图集里占 4×4 格

## 索引位（四个角）
const B_NW := 1
const B_NE := 2
const B_SW := 4
const B_SE := 8

## 地表枚举 —— 与图集里 4×4 块的位置一一对应
enum Terrain {
	GRASS = 0,    ## 草地（房间默认）
	DIRT = 1,     ## 泥土（走廊 / 世界底色）
	STONE = 2,    ## 石板（入口房 / 遗迹）
	SANCTUM = 3,  ## 圣坛魔阵（BOSS 房）
}

## 每种地表在图集里的 4×4 块原点（以瓦片为单位）
const BLOCK_ORIGIN: Array[Vector2i] = [
	Vector2i(0, 0),   # GRASS
	Vector2i(4, 0),   # DIRT
	Vector2i(0, 4),   # STONE
	Vector2i(4, 4),   # SANCTUM
]


## 由四个角是否属于本地形，算出图集里的角点索引
static func index_of(nw: bool, ne: bool, sw: bool, se: bool) -> int:
	var i := 0
	if nw:
		i |= B_NW
	if ne:
		i |= B_NE
	if sw:
		i |= B_SW
	if se:
		i |= B_SE
	return i


## 索引 → 各象限是否实心
static func quadrants_of_index(idx: int) -> Dictionary:
	return {
		"NW": (idx & B_NW) != 0,
		"NE": (idx & B_NE) != 0,
		"SW": (idx & B_SW) != 0,
		"SE": (idx & B_SE) != 0,
	}


## 索引 → 图集里的 TileSet 图块坐标
static func tile_coords(terrain: int, idx: int) -> Vector2i:
	var b: Vector2i = BLOCK_ORIGIN[clampi(terrain, 0, BLOCK_ORIGIN.size() - 1)]
	return Vector2i(b.x + idx % COLS, b.y + idx / COLS)


## 满格索引（四角都是本地形）—— 世界底色层用它铺满
static func full_index() -> int:
	return B_NW | B_NE | B_SW | B_SE


## 由「四角是否本地形」直接给出 Figma 风格的查表键（给 is_solid 之类用）
static func key_of(nw: bool, ne: bool, sw: bool, se: bool) -> int:
	return index_of(nw, ne, sw, se)


## 自检：映射必须满足的基本性质。返回空数组表示通过。
## 游戏启动时（Validation）会调一次，防止这份实现与生成器侧漂移。
static func self_test() -> Array:
	var bad: Array = []
	# ① 四个单角
	var expect := {1: "NW", 2: "NE", 4: "SW", 8: "SE"}
	for idx in expect.keys():
		var q := quadrants_of_index(int(idx))
		var solid: Array = []
		for name in ["NW", "NE", "SW", "SE"]:
			if bool(q[name]):
				solid.append(name)
		if solid.size() != 1 or String(solid[0]) != String(expect[idx]):
			bad.append("idx %d 应为单象限 %s，实际 %s" % [idx, expect[idx], str(solid)])
	# ② 满格 / 空
	if not (quadrants_of_index(full_index())["NW"] and quadrants_of_index(full_index())["SE"]):
		bad.append("满格索引的象限不全")
	if index_of(false, false, false, false) != 0:
		bad.append("四角全假应得到索引 0")
	# ③ 往返一致
	for idx in 16:
		var q2 := quadrants_of_index(idx)
		var back := index_of(bool(q2["NW"]), bool(q2["NE"]), bool(q2["SW"]), bool(q2["SE"]))
		if back != idx:
			bad.append("idx %d 往返得到 %d" % [idx, back])
	# ④ 图块坐标必须落在各自 4×4 块内
	for t in 4:
		for idx in 16:
			var c := tile_coords(t, idx)
			var b: Vector2i = BLOCK_ORIGIN[t]
			if c.x < b.x or c.x >= b.x + COLS or c.y < b.y or c.y >= b.y + COLS:
				bad.append("地形 %d 索引 %d 的图块坐标 %s 越出块原点 %s" % [
					t, idx, str(c), str(b)])
	return bad
