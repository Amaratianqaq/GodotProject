extends SceneTree
# =============================================================================
#  gen_weapons.gd —— 武器图标生成器（《元气骑士前传》风格参考素材）
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_weapons.gd
#
#  产出：
#    weapons.png                72x96   24px x 3 列 x 4 行（12 把品质武器）
#    weapon_cherry_shotgun.png  48x48   单格（传奇品质，单独出图）
#
#  布局（与 scripts/core/atlas.gd 的 WEAPON_FRAMES 逐格对齐）：
#    行 = 品质  0 白·普通 / 1 绿·优秀 / 2 蓝·稀有 / 3 橙·传奇
#    列 = 该品质第几把
#    row 0  铁剑 iron_sword      木棒 wooden_club     猎弓 hunting_bow
#    row 1  精钢刃 fine_blade    战斧 battle_axe      短弓 short_bow
#    row 2  骑士大剑 knight_greatsword  白银长枪 silver_spear  秘银弓 mithril_bow
#    row 3  烈焰之刃 flame_brand  风暴弩 storm_crossbow  秘法法杖 arcane_staff
#
#  【统一约定】所有图标一律**从左下指向右上**（45° 摆放），
#  描边 1px 近黑，光源左上。三条都统一之后，12 把武器摆在一起才像一套。
#  品质差异靠"材质 + 宝石色"表达：白=铁木、绿=抛光绿宝石、蓝=蓝钢、橙=发光橙。
# =============================================================================

const OUT_DIR := "res://assets/sprites"
const CELL := 24
const COLS := 3
const ROWS := 4


func L(rows: PackedStringArray, ox := 0, oy := 0, remap := {}) -> Array:
	return [rows, ox, oy, remap]


func _cell(layers: Array) -> Image:
	var img := RefArt.new_img(CELL, CELL)
	for l in layers:
		RefArt.blit(img, l[0], l[1], l[2], l[3] if l.size() > 3 else {})
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


## 斜向刀身：从 (x0,y0) 到 (x1,y1) 的粗线 + 一侧高光 + 一侧暗部
func _blade(img: Image, x0: int, y0: int, x1: int, y1: int, key: String,
		hi: String, dark: String) -> void:
	RefArt.line(img, x0, y0, x1, y1, key)
	RefArt.line(img, x0 + 1, y0, x1 + 1, y1, hi)
	RefArt.line(img, x0 - 1, y0, x1 - 1, y1, dark)


## 底图：统一的斜向柄 + 护手，供各武器叠加
func _hilt(grip: String, guard: String) -> Array:
	return [L(PackedStringArray([
		"", "", "", "", "", "", "", "", "", "", "", "",
		"   kk", "  k" + grip + "k", "  k" + grip + "k", " k" + grip + grip + "k",
		" k" + grip + grip + "k", "k" + guard + guard + guard + guard + "k", " kkkkk",
		"", "", "", "", "",
	]))]


# =============================================================================
#  row 0 白色品质：铁剑 / 木棒 / 猎弓
# =============================================================================

func _iron_sword() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	_blade(img, 8, 15, 17, 5, "w", "W", "5")
	# 柄与护手
	RefArt.line(img, 5, 18, 8, 15, "B")
	RefArt.line(img, 3, 17, 6, 20, "6")
	RefArt.line(img, 4, 16, 7, 19, "7")
	RefArt.px(img, 5, 19, "b")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


func _wood_club() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 粗头木棒：越往上越粗
	for i in 12:
		var y := 19 - i
		var x := 6 + i / 2
		var w := 2 + i / 4
		RefArt.hline(img, x, x + w, y, "B" if i % 3 else "t")
	RefArt.px(img, 9, 6, "b")
	RefArt.px(img, 12, 7, "b")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


func _hunting_bow(gem := "", gem_hi := "") -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 弓臂：一道弧（用线段近似）
	RefArt.line(img, 15, 4, 12, 7, "t")
	RefArt.line(img, 12, 7, 10, 11, "t")
	RefArt.line(img, 10, 11, 10, 14, "t")
	RefArt.line(img, 10, 14, 12, 18, "t")
	RefArt.line(img, 12, 18, 15, 21, "t")
	# 高光
	RefArt.line(img, 16, 4, 13, 7, "T")
	RefArt.line(img, 11, 11, 11, 14, "T")
	# 弦
	RefArt.line(img, 15, 4, 15, 21, "w")
	RefArt.line(img, 15, 12, 8, 12, "6")
	RefArt.line(img, 8, 12, 15, 12, "6")
	# 宝石（绿/蓝品质用）
	if gem != "":
		RefArt.px(img, 10, 12, gem)
		RefArt.px(img, 11, 12, gem_hi)
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


# =============================================================================
#  row 1 绿色品质
# =============================================================================

func _fine_blade() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	_blade(img, 7, 16, 18, 4, "7", "W", "5")
	RefArt.line(img, 4, 19, 7, 16, "B")
	RefArt.line(img, 2, 18, 5, 21, "e")
	RefArt.line(img, 3, 17, 6, 20, "E")
	RefArt.px(img, 3, 20, "O")   # 柄尾绿宝石座
	RefArt.px(img, 4, 20, "O")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


func _battle_axe() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 柄
	RefArt.line(img, 5, 20, 15, 6, "B")
	RefArt.line(img, 6, 20, 16, 6, "t")
	# 斧刃（单刃，宽扇形）
	var t := PackedStringArray([
		"", "", "", "", "", "",
		"             kkkk",
		"           kk7777kk",
		"          k77777777k",
		"         k7777777777k",
		"         k77766666",
		"        k77766",
		"        k7666",
		"        k666",
		"        k66",
		"", "", "", "", "", "", "", "", "",
	])
	RefArt.blit(img, t, 0, 0)
	RefArt.px(img, 10, 8, "e")
	RefArt.px(img, 9, 12, "e")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


# =============================================================================
#  row 2 蓝色品质
# =============================================================================

func _knight_greatsword() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 宽刃巨剑
	for i in 14:
		var y := 18 - i
		var x := 7 + i
		RefArt.px(img, x, y, "c")
		RefArt.px(img, x + 1, y, "C")
		RefArt.px(img, x + 2, y, "c")
		RefArt.px(img, x + 3, y, "n")
	# 金色护手
	RefArt.line(img, 2, 18, 8, 21, "O")
	RefArt.line(img, 3, 17, 9, 20, "y")
	# 柄
	RefArt.line(img, 3, 21, 6, 22, "B")
	RefArt.px(img, 4, 22, "c")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


func _silver_spear() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 长杆（几乎对角）
	RefArt.line(img, 2, 22, 16, 8, "t")
	RefArt.line(img, 3, 22, 17, 8, "T")
	RefArt.line(img, 1, 22, 15, 8, "B")
	# 叶形枪头
	var tip := PackedStringArray([
		"", "", "", "", "", "",
		"                kk",
		"               k77k",
		"              k7WW7k",
		"             k77WW77k",
		"              k7WW7k",
		"               k77k",
		"                kk",
		"", "", "", "", "", "", "", "", "", "", "",
	])
	RefArt.blit(img, tip, 0, 0)
	# 蓝流苏
	RefArt.px(img, 14, 10, "c")
	RefArt.px(img, 13, 11, "c")
	RefArt.px(img, 15, 11, "n")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


# =============================================================================
#  row 3 橙色品质（发光）
# =============================================================================

func _flame_brand() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 暗色刀身 + 刃口橙色火焰
	_blade(img, 6, 17, 18, 4, "1", "2", "k")
	RefArt.line(img, 7, 17, 19, 4, "o")
	RefArt.line(img, 6, 16, 18, 3, "O")
	RefArt.px(img, 14, 7, "Y")
	RefArt.px(img, 16, 5, "Y")
	# 护手与柄
	RefArt.line(img, 3, 19, 8, 22, "B")
	RefArt.line(img, 4, 18, 9, 21, "t")
	RefArt.px(img, 4, 21, "o")
	# 余烬
	RefArt.px(img, 20, 2, "O")
	RefArt.px(img, 21, 4, "o")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


func _storm_crossbow() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 弩身
	RefArt.line(img, 4, 19, 16, 9, "5")
	RefArt.line(img, 5, 20, 17, 10, "6")
	RefArt.line(img, 3, 18, 15, 8, "7")
	# 弩臂（横向）
	RefArt.line(img, 8, 6, 8, 15, "B")
	RefArt.line(img, 9, 6, 9, 15, "t")
	# 弦
	RefArt.line(img, 8, 6, 14, 11, "w")
	RefArt.line(img, 8, 15, 14, 11, "w")
	# 箭
	RefArt.line(img, 12, 12, 13, 11, "O")
	# 闪电弧
	RefArt.px(img, 6, 5, "f")
	RefArt.px(img, 7, 4, "f")
	RefArt.px(img, 11, 5, "f")
	RefArt.px(img, 12, 4, "f")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


func _arcane_staff() -> Image:
	var img := RefArt.new_img(CELL, CELL)
	# 杖身（带节）
	RefArt.line(img, 4, 22, 12, 13, "B")
	RefArt.line(img, 5, 22, 13, 13, "t")
	RefArt.px(img, 7, 19, "b")
	RefArt.px(img, 9, 17, "b")
	# 顶部爪状托
	RefArt.line(img, 12, 13, 11, 9, "T")
	RefArt.line(img, 13, 13, 15, 9, "T")
	# 悬浮紫水晶
	RefArt.disc(img, 13.0, 7.0, 3.0, "p")
	RefArt.disc(img, 13.0, 6.5, 2.0, "K")
	RefArt.px(img, 12, 6, "W")
	# 金色符文点
	RefArt.px(img, 10, 10, "O")
	RefArt.px(img, 16, 10, "O")
	RefArt.outline(img, 0, 0, CELL, CELL)
	return img


# =============================================================================
#  樱花霰弹枪（48x48 单图）
# =============================================================================

func _cherry_shotgun() -> Image:
	var S := 48
	var img := RefArt.new_img(S, S)
	# 双管：从右下伸向左上
	for i in 22:
		var x := 10 + i
		var y := 34 - i
		RefArt.px(img, x, y, "5")
		RefArt.px(img, x, y + 1, "7")
		RefArt.px(img, x, y + 2, "5")
		RefArt.px(img, x, y + 3, "3")
		RefArt.px(img, x, y + 4, "2")
	# 枪口（左上端）发光
	RefArt.disc(img, 11.0, 33.0, 4.0, "o")
	RefArt.disc(img, 11.0, 33.0, 2.5, "O")
	RefArt.px(img, 10, 32, "Y")
	# 机匣 / 扳机（中段加厚）
	RefArt.fill_rect(img, 24, 22, 8, 8, "5")
	RefArt.fill_rect(img, 25, 23, 6, 6, "6")
	RefArt.px(img, 29, 28, "k")
	# 樱木托（右下）
	var t := PackedStringArray([
		"", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
		"", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
		"", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
		"                       kkkkkkk",
		"                      kBBBBBBk",
		"                     kBbbbbbbBk",
		"                     kBbBBBBBBk",
		"                    kBbBBBBBBk",
		"                    kBbBBBBBBk",
		"                   kBbBBBBBBk",
		"                   kBbBBBBBk",
		"                  kBbBBBBBBk",
		"                  kBBBBBBBk",
		"                  kkkkkkkkk",
	])
	RefArt.blit(img, t, 0, 0)
	# 粉樱贴花 + 飘落花瓣
	for p in [Vector2i(30, 30), Vector2i(33, 28), Vector2i(27, 33), Vector2i(35, 33)]:
		RefArt.disc(img, float(p.x), float(p.y), 2.0, "K")
		RefArt.px(img, p.x, p.y, "W")
	RefArt.px(img, 8, 26, "K")
	RefArt.px(img, 6, 29, "K")
	RefArt.px(img, 16, 22, "K")
	RefArt.px(img, 40, 18, "K")
	RefArt.px(img, 43, 22, "P")
	# 金色雕纹
	RefArt.line(img, 26, 24, 36, 24, "O")
	RefArt.line(img, 26, 25, 36, 25, "O")
	RefArt.outline(img, 0, 0, S, S)
	return img


# =============================================================================
#  入口
# =============================================================================

func _init() -> void:
	print("=== 武器图标生成 ===")
	RefArt.reset_stats()
	var dir := ProjectSettings.globalize_path(OUT_DIR)

	var sheet := RefArt.new_img(CELL * COLS, CELL * ROWS)
	# row 0 白
	_put(sheet, 0, 0, _iron_sword())
	_put(sheet, 1, 0, _wood_club())
	_put(sheet, 2, 0, _hunting_bow())
	# row 1 绿
	_put(sheet, 0, 1, _fine_blade())
	_put(sheet, 1, 1, _battle_axe())
	_put(sheet, 2, 1, _hunting_bow("e", "E"))
	# row 2 蓝
	_put(sheet, 0, 2, _knight_greatsword())
	_put(sheet, 1, 2, _silver_spear())
	_put(sheet, 2, 2, _hunting_bow("c", "C"))
	# row 3 橙
	_put(sheet, 0, 3, _flame_brand())
	_put(sheet, 1, 3, _storm_crossbow())
	_put(sheet, 2, 3, _arcane_staff())

	RefArt.save(sheet, dir, "weapons.png")
	RefArt.save(_cherry_shotgun(), dir, "weapon_cherry_shotgun.png")
	RefArt.report("武器图标")
	quit(0)


func _put(sheet: Image, col: int, row: int, cell: Image) -> void:
	RefArt.put(sheet, cell, CELL, CELL, col, row)
