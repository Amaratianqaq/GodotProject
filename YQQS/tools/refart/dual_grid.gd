class_name RefDualGrid
extends RefCounted
## 双网格（dual-grid）瓦片映射 —— **生成器/验证器侧**的实现。
##
## 【为什么叫 RefDualGrid 而不是 DualGrid】
## 游戏运行时侧已经有一个 `scripts/core/dual_grid.gd`（class_name DualGrid）。
## 两者是同一套映射的两份实现（生成器侧带 self_test，游戏侧供 ForestLevel 用），
## 名字必须不同，否则 GDScript 全局类名冲突。
## 改动任一份后，请同时跑：
##   tools/refart/gen_ground.gd（自带逐瓦片自检）
##   tools/refart/verify_dualgrid.gd（真渲染逐像素比对，必须全绿）
##
## 【这个文件是什么】
## 把「象限 ↔ 索引」和「索引 ↔ 图集槽位」这两件最容易搞反的事集中在一个类里。
## 生成器（gen_ground.gd）、验证器（verify_dualgrid.gd）、游戏运行时
## （scripts/levels/*）都必须调它，**禁止各自再写一份**。
##
## 【为什么值得单独抽一个类】
## 这个映射开发中前后写错过五次：读过 180°、90°、"线性律不成立"的误判，
## 以及最阴的一次 —— 本文件里出现了**重名函数**，我改的那份被前面那份遮蔽，
## 于是"改了代码但行为不变"，白查了很久。
##   ⇒ 教训：这样一个 16 项的映射，就写一张表 + 一个自检，不要现场推导。
##
## 【渲染模型】
##   逻辑格（A 格）：决定"这里是不是草地" —— 数据、碰撞、刷怪都在这一层
##   显示格（B 格）：画图的位置，整体偏移 (−8,−8)，即 −半个瓦片
##   一个显示格恰好压在 4 个逻辑格的**公共角点**上，所以显示格只需要知道
##   这 4 个逻辑格属于哪种地形 → 16 种组合 → 16 张瓦片覆盖全部角点情形。
##
## 【象限 ↔ 索引 的映射】
##   索引 = 四个角是否属于本地形的位掩码（linear / row-major）：
##       bit1(1) = NW 左上      bit2(2) = NE 右上
##       bit4(4) = SW 左下      bit8(8) = SE 右下
##   槽位 = (idx % 4, idx / 4)：
##       col 0→左  1→右  2→左  3→右        row 0→上  1→下  2→上  3→下
##   槽位图案与"哪些象限实心"完全一致，因为 col 的低位就是 NW/SW 的位、
##   row 的低位就是 NW/NE 的位 —— 两边用的是同一套编码。
##
##   自检锚点（self_test() 会验证，必须全过）：
##     idx 0    → 空（四象限都没有）
##     idx 1    → NW 单象限      idx 2 → NE       idx 4 → SW       idx 8 → SE
##     idx 3    → 左半（NW+SW）  idx 12 → 上半（NW+NE）  idx 10 → 右半   idx 5 → 下半
##     idx 15   → 满格（四象限全实心，可无缝自接）

const TILE := 16
const HALF := 8

## 角点 → 位。位序就是「NW 最低位、SE 最高位」的 row-major。
const B_NW := 1
const B_NE := 2
const B_SW := 4
const B_SE := 8

## 四种地表在图集里的 4×4 块原点（以 16px 格为单位）
const BLOCK_ORIGIN: Array[Vector2i] = [
	Vector2i(0, 0),   # 0 GRASS   草地
	Vector2i(4, 0),   # 1 DIRT    泥土
	Vector2i(0, 4),   # 2 STONE   石板
	Vector2i(4, 4),   # 3 SANCTUM 圣坛
]

const QUAD_NAMES: Array[String] = ["NW", "NE", "SW", "SE"]


## 索引 → 各象限是否实心
static func quadrants_of_index(idx: int) -> Dictionary:
	return {
		"NW": (idx & B_NW) != 0,
		"NE": (idx & B_NE) != 0,
		"SW": (idx & B_SW) != 0,
		"SE": (idx & B_SE) != 0,
	}


## 由「四个象限是否实心」算出索引（就是拼位掩码）
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


## 由 [NW, NE, SW, SE] 的 0/1 掩码算索引
static func index_of_mask(mask: Array) -> int:
	return index_of(int(mask[0]) != 0, int(mask[1]) != 0, int(mask[2]) != 0, int(mask[3]) != 0)


## 索引 → 图集里的 (col,row)。
## 索引的位直接对应**贴图内的半区**（见文件头那张表）：
##   bit1(左) → col 0/1 内取一个、bit2(右) → col 2/3 内取一个
##   bit4(上) → row 0/1 内取一个、bit8(下) → row 2/3 内取一个
## 也就是低 2 位取列、高 2 位取行 —— 朴素的行主序 (idx % 4, idx / 4)。
## 【重要】这里**不要**再做任何 ^1 / 取反之类的"修正"：
## 曾经按"象限感觉反了"的直觉加过 ^1，结果满格瓦片不再无缝、边界用例全错。
## 判定手段：gen_ground.gd 的 `_verify_seamless()` 与 `self_test()`，两者必须都过。
static func atlas_coords(terrain: int, idx: int) -> Vector2i:
	var b: Vector2i = BLOCK_ORIGIN[terrain]
	return Vector2i(b.x + idx % 4, b.y + idx / 4)


## 索引 → 图集里的像素矩形
static func atlas_rect(terrain: int, idx: int) -> Rect2i:
	var c := atlas_coords(terrain, idx)
	return Rect2i(c.x * TILE, c.y * TILE, TILE, TILE)


## 索引里有哪些象限是实心（调试用）
static func quadrants_of(idx: int) -> Array:
	var q := quadrants_of_index(idx)
	var out: Array = []
	for name in QUAD_NAMES:
		if bool(q[name]):
			out.append(name)
	return out


## 索引是否满格（四角都是本地形）—— 只有满格瓦片才要求能无缝自接
static func is_full(idx: int) -> bool:
	var q := quadrants_of_index(idx)
	return bool(q["NW"]) and bool(q["NE"]) and bool(q["SW"]) and bool(q["SE"])


## 自检：返回空数组表示通过。
static func self_test() -> Array:
	var bad: Array = []
	# ① 锚点表：索引 → 应有的实心象限
	# 槽位图案 = idx 的位掩码（linear / row-major）：
	#     1=NW  2=NE  4=SW  8=SE
	# 于是 idx = 各角位之和，例如 idx 12 = 4|8 = SW+SE = 下半边。
	var anchors := {
		0: [], 1: ["NW"], 2: ["NE"], 3: ["NW", "NE"],
		4: ["SW"], 5: ["NW", "SW"], 6: ["NE", "SW"], 7: ["NW", "NE", "SW"],
		8: ["SE"], 9: ["NW", "SE"], 10: ["NE", "SE"],
		11: ["NW", "NE", "SE"], 12: ["SW", "SE"],
		13: ["NW", "SW", "SE"], 14: ["NE", "SW", "SE"], 15: ["NW", "NE", "SW", "SE"],
	}
	for idx in anchors.keys():
		var got := quadrants_of(int(idx))
		var want: Array = anchors[idx]
		var gs := got.duplicate()
		var ws := want.duplicate()
		gs.sort()
		ws.sort()
		if gs != ws:
			bad.append("idx %2d 期望 %s，实际 %s" % [idx, str(ws), str(gs)])
	# ② 满格 / 空
	if not is_full(15):
		bad.append("idx 15 必须是满格")
	if index_of(false, false, false, false) != 0:
		bad.append("四象限全假必须得到 idx 0")
	# ③ 往返一致
	for idx in 16:
		var q := quadrants_of_index(idx)
		var back := index_of(bool(q["NW"]), bool(q["NE"]), bool(q["SW"]), bool(q["SE"]))
		if back != idx:
			bad.append("idx %d 往返不一致：得到 %d" % [idx, back])
	return bad
