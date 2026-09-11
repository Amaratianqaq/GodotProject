extends SceneTree
# =============================================================================
#  gen_props_atlas.gd —— props.png 生成器（16 列 x 8 行，每格 16px）
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_props_atlas.gd
#
#  产出：assets/sprites/props.png  256x128
#
#  逐格语义**必须**与 scripts/core/atlas.gd 的常量表逐格对齐 ——
#  那个文件是代码与美术之间的契约。布局（docs/10 §4.3）：
#    row 0  宝箱 6 个：普通关/开 优秀关/开 稀有关/开（col 6-15 留空）
#    row 1  金币 4 帧（col 4-15 留空）
#    row 2  心 / 蓝宝石 / 钥匙 / 传送门 / 出口 / 钱袋
#    row 3  影子 / 命中火花 / 枪口闪光 / 红药 / 蓝药 / 卷轴
#    row 4  技能图标 8 个：roll precision multishot crit vitality energy magnet swift
#    row 5  UI 图标 8 个：coin bag warehouse skilltree gear close arrow lock
#    row 6  品质框 4 个：普通 优秀 稀有 传奇
#    row 7  装饰 6 个：门 / 火把 / 木桶 / 木箱 / 骸骨 / 蛛网
# =============================================================================

const OUT_DIR := "res://assets/sprites"
const CELL := 16
const COLS := 16
const ROWS := 8


func L(rows: PackedStringArray, ox := 0, oy := 0, remap := {}) -> Array:
	return [rows, ox, oy, remap]


func _cell(layers: Array, outline := false) -> Image:
	var img := RefArt.new_img(CELL, CELL)
	for l in layers:
		RefArt.blit(img, l[0], l[1], l[2], l[3] if l.size() > 3 else {})
	if outline:
		RefArt.outline(img, 0, 0, CELL, CELL)
	return img


# =============================================================================
#  row 0 宝箱（关 / 开）—— 三种品质用不同木色与宝石色区分
# =============================================================================

func _chest(closed: bool, wood: String, band: String, gem: String) -> Image:
	if closed:
		var rows := PackedStringArray([
			"  kkkkkkkkkkkk  ",
			" k" + _rep(wood, 10) + "k ",
			" k" + band + band + _rep(wood, 6) + band + band + "k ",
			" k" + _rep(wood, 10) + "k ",
			" kkkkkkkkkkkk  ",
			" k" + _rep(wood, 10) + "k ",
			" k" + _rep(wood, 4) + gem + _rep(wood, 5) + "k ",
			" k" + _rep(wood, 10) + "k ",
			" k" + band + band + _rep(wood, 6) + band + band + "k ",
			" k" + _rep(wood, 10) + "k ",
			" kkkkkkkkkkkk  ",
		])
		return _cell([L(rows, 1, 3)], true)
	# 开：盖子立起来 + 内部亮
	var rows2 := PackedStringArray([
		"  kkkkkkkkkkkk  ",
		" k" + band + _rep(wood, 8) + band + "k ",
		" k" + _rep(wood, 10) + "k ",
		" kkkkkkkkkkkk  ",
		" k" + _rep("k", 10) + "k ",
		" k" + _rep("O", 2) + _rep("k", 6) + _rep("O", 2) + "k ",
		" k" + _rep("k", 10) + "k ",
		" k" + _rep(wood, 10) + "k ",
		" k" + band + band + _rep(wood, 6) + band + band + "k ",
		" k" + _rep(wood, 10) + "k ",
		" kkkkkkkkkkkk  ",
	])
	return _cell([L(rows2, 1, 3)], true)


func _rep(ch: String, n: int) -> String:
	var s := ""
	for i in n:
		s += ch
	return s


# =============================================================================
#  row 1 金币 4 帧
# =============================================================================

func _coin(phase: int) -> Image:
	# phase 0 正面 1 转45 2 侧面 3 转45
	var widths := [6, 4, 1, 4]
	var w: int = widths[phase]
	var half := w / 2
	var rows := PackedStringArray()
	rows.append("")
	rows.append("")
	rows.append("")
	rows.append("")
	var top := 3
	var bot := 12
	for y in range(top, bot + 1):
		var cy := float(y) - float(top + bot) / 2.0
		var span := int(roundf(sqrt(maxf(float(half * half) - cy * cy, 0.0))))
		var line := ""
		for x in 16:
			var cx := absf(float(x) - 7.5)
			if cx <= float(span) + 0.5:
				if cx >= float(span) - 0.5:
					line += "b"
				elif y == top + 1:
					line += "O"
				else:
					line += "O"
			else:
				line += "."
		rows.append(line)
	return _cell([L(rows)], true)


# =============================================================================
#  row 2-3 拾取物与图标
# =============================================================================

var HEART := PackedStringArray([
	"",
	"",
	"",
	"   kRk  kRk",
	"  kRRRkkRRRk",
	"  kRWRRRRRRk",
	"  kRRRRRRRRk",
	"  kRRRRRRRRk",
	"   kRRRRRRk",
	"    kRRRRk",
	"     kRRk",
	"      kk",
	"",
	"",
	"",
	"",
])

var GEM_BLUE := PackedStringArray([
	"",
	"",
	"",
	"     kCk",
	"    kCCCk",
	"   kCCCCCk",
	"  kCCccCCCk",
	"  kCccccCCk",
	"   kccccck",
	"    kccck",
	"     kck",
	"      k",
	"",
	"",
	"",
	"",
])

var KEY := PackedStringArray([
	"",
	"",
	"",
	"",
	"     kOOkk",
	"    kOk..kOk",
	"    kOkkkkOk",
	"     kOOOOOk",
	"      kOOOk",
	"      kOOk",
	"      kOkk",
	"      kOOk",
	"      kOOk",
	"      kkkk",
	"",
	"",
])

var PORTAL := PackedStringArray([
	"",
	"",
	"    kkkkkkkk",
	"   k66666666k",
	"  k6NNNNNNNN6k",
	"  k6NCCCCCCN6k",
	"  k6NCnnnnCN6k",
	"  k6NCnWWnCN6k",
	"  k6NCnnnnCN6k",
	"  k6NCCCCCCN6k",
	"  k6NNNNNNNN6k",
	"   k66666666k",
	"    kkkkkkkk",
	"",
	"",
	"",
])

var EXIT_SIGN := PackedStringArray([
	"",
	"",
	"   kkkkkkkkkkkk",
	"   kwwwwwwwwwwk",
	"   kwkkkkkkkkwk",
	"   kwkOOOOOOkwk",
	"   kwkOkkkkOkwk",
	"   kwkOkwwkOkwk",
	"   kwkOkkkkOkwk",
	"   kwkOOOOOOkwk",
	"   kwkkkkkkkkwk",
	"   kwwwwwwwwwwk",
	"   kkkkkkkkkkkk",
	"",
	"",
	"",
])

var POUCH := PackedStringArray([
	"",
	"",
	"",
	"",
	"    kkkkkkkk",
	"   kBBBBBBBBk",
	"  kBBBBBBBBBBk",
	"  kBBOOOOOOBBk",
	"  kBBOOOOOOBBk",
	"  kBBBBBBBBBBk",
	"   kbbbbbbbbk",
	"    kkkkkkkk",
	"",
	"",
	"",
	"",
])

## 影子：柔和黑椭圆（会按 z_height 缩放，所以不能带描边色）
var SHADOW := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"    kkkkkkkk",
	"   k11111111k",
	"   k11111111k",
	"    kkkkkkkk",
	"",
	"",
	"",
	"",
])

var HIT_SPARK := PackedStringArray([
	"",
	"",
	"",
	"       W",
	"       y",
	"   W   y   W",
	"    y  y  y",
	"     y y y",
	"  yyWyyyyyyyWyy",
	"     y y y",
	"    y  y  y",
	"   W   y   W",
	"       y",
	"       y",
	"",
	"",
])

var MUZZLE_FLASH := PackedStringArray([
	"",
	"",
	"",
	"",
	"        y",
	"       yWy",
	"      yWWWy",
	"  yyyyWWWWWyyyy",
	"   yyyWWWWWy",
	"    yyWWWyy",
	"     yWyy",
	"      yy",
	"",
	"",
	"",
	"",
])

var POTION_HP := PackedStringArray([
	"",
	"",
	"",
	"      kkkk",
	"      kbbk",
	"     kkRRkk",
	"    kRRRRRRk",
	"   kRRWRRRRRk",
	"   kRWRRRRRRk",
	"   kRRRRRRRrk",
	"   kRRRRRRRrk",
	"    krrrrrrk",
	"     kkkkkk",
	"",
	"",
	"",
])

var POTION_MP := PackedStringArray([
	"",
	"",
	"",
	"      kkkk",
	"      kbbk",
	"     kkNNkk",
	"    kNNNNNNk",
	"   kNNCNNNNNk",
	"   kNCNNNNNNk",
	"   kNNNNNNNnk",
	"   kNNNNNNNnk",
	"    knnnnnnk",
	"     kkkkkk",
	"",
	"",
	"",
])

var SCROLL := PackedStringArray([
	"",
	"",
	"",
	"    kkkkkkkk",
	"   kTTTTTTTTk",
	"   kTttttttTk",
	"   kTtTTTTtTk",
	"   kTttttttTk",
	"   kTtTTTTtTk",
	"   kTttttttTk",
	"   kTTTTTTTTk",
	"    kkkkkkkk",
	"",
	"",
	"",
	"",
])

# =============================================================================
#  row 4 技能图标（深色圆底盘 + 符号）
# =============================================================================

func _emblem(symbol: PackedStringArray) -> Image:
	var disc := PackedStringArray([
		"",
		"     kkkkkk",
		"   kk222222kk",
		"  k2222222222k",
		"  k2222222222k",
		" k222222222222k",
		" k222222222222k",
		" k222222222222k",
		" k222222222222k",
		" k222222222222k",
		"  k2222222222k",
		"  k2222222222k",
		"   kk222222kk",
		"     kkkkkk",
		"",
		"",
	])
	return _cell([L(disc), L(symbol)])


var IC_ROLL := PackedStringArray([
	"", "", "", "",
	"       kk", "      kk", "     kkk", "    kcWk", "   kccWk",
	"  kccWk", " kccWk", " kcWk", " kkk", "", "", "",
])

var IC_PRECISION := PackedStringArray([
	"", "", "", "", "      k", "   kkkkkkk", "  k   k   k", "  k   k   k",
	"kkkkkkkkkkkk", "  k   k   k", "  k   k   k", "   kkkkkkk", "      k", "", "", "",
])

var IC_BURST := PackedStringArray([
	"", "", "", "  k   k   k", "   k  k  k", "    k k k", "     kkk",
	"kkkkkyyykkkkk", "     kkk", "    k k k", "   k  k  k", "  k   k   k", "", "", "", "",
])

var IC_CRIT := PackedStringArray([
	"", "", "", "       W", "   y  y  y", "    y y y", "  yyRyyyyyRyy",
	"    y y y", "   y  y  y", "       y", "", "", "", "", "", "",
])

var IC_LIFE := PackedStringArray([
	"", "", "", "", "   kRk  kRk", "  kRRRkkRRRk", "  kRWRRRRRRk",
	"  kRRRRRRRRk", "   kRRRRRRk", "    kRRRRk", "     kRRk", "      kk", "", "", "", "",
])

var IC_ENERGY := PackedStringArray([
	"", "", "", "      kf", "     kff", "    kfff", "   kffff", "  kfffff",
	"   kffff", "  kfff", " kff", " kf", " k", "", "", "",
])

var IC_MAGNET := PackedStringArray([
	"", "", "", "   kkkk", "  kC  Ck", "  kC  Ck", "  kC  Ck", "  kC  Ck",
	"  kCkkCk", "  kCk kCk", "  kkk kkk", "", "    O", "   kOk", "", "",
])

var IC_SWIFT := PackedStringArray([
	"", "", "", "  kkk", " kWWWk", "kWkkkk", "kWWWk", "kWkkkk",
	"kWk", "kk", "  k", "   k", "    k", "     k", "", "",
])

# =============================================================================
#  row 5 UI 图标
# =============================================================================

var UI_COIN_STACK := PackedStringArray([
	"", "", "", "     kkkk", "    kOOOOOk", "    kOOOOOk", "   kkkkkkkk",
	"   kOOOOOOk", "   kOOOOOOk", "  kkkkkkkkk", "  kOOOOOOOk", "  kOOOOOOOk",
	"   kkkkkkk", "", "", "",
])

var UI_BAG := PackedStringArray([
	"", "", "      kkk", "     kBBk", "    kkkkkkkk", "   kBBBBBBBBk",
	"  kBBBBBBBBBBk", "  kBBBBBBBBBBk", "  kBBBBBBBBBBk", "  kBBBBBBBBBBk",
	"  kBBBBBBBBBBk", "   kkkkkkkkkk", "", "", "", "",
])

var UI_WAREHOUSE := PackedStringArray([
	"", "", "   kkkkkkkkkk", "  kTTTTTTTTTTk", "  kTkkkkkkkkTk",
	"  kTkTTTTTTkTk", "  kTkkkkkkkkTk", "  kTkTTTTTTkTk", "  kTkkkkkkkkTk",
	"  kTkTTTTTTkTk", "  kkkkkkkkkkkk", "", "", "", "", "",
])

var UI_SKILLTREE := PackedStringArray([
	"", "", "      kkkk", "     kEEEEk", "     kEEEEk", "      kkkk",
	"     kk  kk", "    kk    kk", "   kkk    kkk", "  kEEEEk kEEEEk",
	"  kEEEEk kEEEEk", "  kkkkkk kkkkkk", "", "", "", "",
])

var UI_GEAR := PackedStringArray([
	"", "", "    kk  kk", "   k6kkkk6k", "  k66666666k", " k6666666666k",
	"kk666kkkk666kk", "kk66k    k66kk", "kk66k    k66kk", "kk666kkkk666kk",
	" k6666666666k", "  k66666666k", "   k6kkkk6k", "    kk  kk", "", "",
])

var UI_CLOSE := PackedStringArray([
	"", "", "  kk        kk", "  kWk      kWk", "   kWk    kWk", "    kWk  kWk",
	"     kWkkWk", "      kWWk", "      kWWk", "     kWkkWk", "    kWk  kWk",
	"   kWk    kWk", "  kWk      kWk", "  kk        kk", "", "",
])

var UI_ARROW := PackedStringArray([
	"", "", "", "   kk", "   kWk", "   kWWk", "   kWWWk", "kkkWWWWWk",
	"kkkWWWWWk", "   kWWWk", "   kWWk", "   kWk", "   kk", "", "", "",
])

var UI_LOCK := PackedStringArray([
	"", "", "     kkkk", "    k6  6k", "    k6  6k", "   kkkkkkkk",
	"   kOOOOOOk", "   kOOkkOOk", "   kOOkkOOk", "   kOOOOOOk",
	"   kkkkkkkk", "", "", "", "", "",
])

# =============================================================================
#  row 6 品质框（16x16 空心边框）
# =============================================================================

func _rarity_frame(col: String, star: bool) -> Image:
	var rows := PackedStringArray([
		"kkkkkkkkkkkkkkkk",
		"k" + col + col + _rep(col, 12) + col + col + "k",
	])
	var body: Array = []
	body.append("kkkkkkkkkkkkkkkk")
	body.append("k" + _rep(col, 14) + "k")
	for i in 10:
		body.append("k" + col + _rep(".", 12) + col + "k")
	body.append("k" + _rep(col, 14) + "k")
	body.append("kkkkkkkkkkkkkkkk")
	var packed := PackedStringArray()
	for s in body:
		packed.append(s)
	if star:
		return _cell([L(packed), L(PackedStringArray([
			"", "", "       W", "      kWk", "     kWWWk", "    kWWWWWk",
			"", "", "", "", "", "", "", "", "", "",
		]))])
	return _cell([L(packed)])


# =============================================================================
#  row 7 场景装饰
# =============================================================================

var DECO_DOOR := PackedStringArray([
	"",
	"   kkkkkkkkkk",
	"   kBBBBBBBBk",
	"   kBbbbbbbBk",
	"   kBbBBBBbBk",
	"   kBbBttBbBk",
	"   kBbBBBBbBk",
	"   kBbbbbbbBk",
	"   kBbBBBBbBk",
	"   kBbBttBbBk",
	"   kBbBBBBbBk",
	"   kBbbbbbbBk",
	"   kBBBBBBBBk",
	"   kkkkkkkkkk",
	"",
	"",
])

var DECO_TORCH := PackedStringArray([
	"",
	"      kOk",
	"     kOOOk",
	"    kOOOOOk",
	"    kOfOOk",
	"     kOOOk",
	"      kbk",
	"      kbk",
	"      kbk",
	"      kbk",
	"      kbk",
	"      kbk",
	"     kbbbk",
	"     kkkkk",
	"",
	"",
])

var DECO_BARREL := PackedStringArray([
	"",
	"",
	"    kkkkkkkk",
	"   kTTTTTTTTk",
	"   k66666666k",
	"   kTbbbbbbTk",
	"   kTTTTTTTTk",
	"   k66666666k",
	"   kTbbbbbbTk",
	"   kTTTTTTTTk",
	"   k66666666k",
	"   kTTTTTTTTk",
	"    kkkkkkkk",
	"",
	"",
	"",
])

var DECO_CRATE := PackedStringArray([
	"",
	"",
	"   kkkkkkkkkk",
	"   kTTTTTTTTk",
	"   kTbTTTTbTk",
	"   kTTbTTbTTk",
	"   kTTTbbTTTk",
	"   kTTTbbTTTk",
	"   kTTbTTbTTk",
	"   kTbTTTTbTk",
	"   kTTTTTTTTk",
	"   kkkkkkkkkk",
	"",
	"",
	"",
	"",
])

var DECO_BONES := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"   kk        kk",
	"  kwwk      kwwk",
	"   kwwkkkkkkwwk",
	"    kwwwwwwwwk",
	"     kkkkkkkk",
	"    kwwk  kwwk",
	"   kwwk    kwwk",
	"    kk      kk",
	"",
	"",
])

var DECO_WEB := PackedStringArray([
	"kkk kkk kkk kkkk",
	"k w k w k w k  w",
	"k  ww  w  ww   k",
	"k   wwwwwwww   k",
	"k  w w    w w  k",
	"k w   w  w   w k",
	"kwww  www  wwwkk",
	"kw  wwwwwww  w k",
	"k  ww  w  ww   k",
	"k w  w w w  w  k",
	"kw  w  w  w  w k",
	"k w  w   w  w  k",
	"k  w   w   w   k",
	"k w     w    w k",
	"k              k",
	"kkkkkkkkkkkkkkkk",
])

# =============================================================================
#  入口
# =============================================================================

func _init() -> void:
	print("=== props.png 生成 ===")
	RefArt.reset_stats()
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	var sheet := RefArt.new_img(CELL * COLS, CELL * ROWS)

	# --- row 0 宝箱 ---
	_put(sheet, 0, 0, _chest(true, "B", "6", "O"))
	_put(sheet, 1, 0, _chest(false, "B", "6", "O"))
	_put(sheet, 2, 0, _chest(true, "B", "6", "e"))
	_put(sheet, 3, 0, _chest(false, "B", "6", "e"))
	_put(sheet, 4, 0, _chest(true, "b", "O", "c"))
	_put(sheet, 5, 0, _chest(false, "b", "O", "c"))

	# --- row 1 金币 4 帧 ---
	for i in 4:
		_put(sheet, i, 1, _coin(i))

	# --- row 2 拾取物 ---
	_put(sheet, 0, 2, _cell([L(HEART)], true))
	_put(sheet, 1, 2, _cell([L(GEM_BLUE)], true))
	_put(sheet, 2, 2, _cell([L(KEY)], true))
	_put(sheet, 3, 2, _cell([L(PORTAL)], true))
	_put(sheet, 4, 2, _cell([L(EXIT_SIGN)], true))
	_put(sheet, 5, 2, _cell([L(POUCH)], true))

	# --- row 3 影子与特效 ---
	_put(sheet, 0, 3, _cell([L(SHADOW)]))
	_put(sheet, 1, 3, _cell([L(HIT_SPARK)]))
	_put(sheet, 2, 3, _cell([L(MUZZLE_FLASH)]))
	_put(sheet, 3, 3, _cell([L(POTION_HP)], true))
	_put(sheet, 4, 3, _cell([L(POTION_MP)], true))
	_put(sheet, 5, 3, _cell([L(SCROLL)], true))

	# --- row 4 技能图标 ---
	var skills := [IC_ROLL, IC_PRECISION, IC_BURST, IC_CRIT,
		IC_LIFE, IC_ENERGY, IC_MAGNET, IC_SWIFT]
	for i in 8:
		_put(sheet, i, 4, _emblem(skills[i]))

	# --- row 5 UI 图标 ---
	var uis := [UI_COIN_STACK, UI_BAG, UI_WAREHOUSE, UI_SKILLTREE,
		UI_GEAR, UI_CLOSE, UI_ARROW, UI_LOCK]
	for i in 8:
		_put(sheet, i, 5, _cell([L(uis[i])], true))

	# --- row 6 品质框 ---
	_put(sheet, 0, 6, _rarity_frame("w", false))
	_put(sheet, 1, 6, _rarity_frame("e", false))
	_put(sheet, 2, 6, _rarity_frame("c", false))
	_put(sheet, 3, 6, _rarity_frame("O", true))

	# --- row 7 场景装饰 ---
	_put(sheet, 0, 7, _cell([L(DECO_DOOR)], true))
	_put(sheet, 1, 7, _cell([L(DECO_TORCH)], true))
	_put(sheet, 2, 7, _cell([L(DECO_BARREL)], true))
	_put(sheet, 3, 7, _cell([L(DECO_CRATE)], true))
	_put(sheet, 4, 7, _cell([L(DECO_BONES)], true))
	_put(sheet, 5, 7, _cell([L(DECO_WEB)], true))

	RefArt.save(sheet, dir, "props.png")
	RefArt.report("props 图集")
	quit(0)


func _put(sheet: Image, col: int, row: int, cell: Image) -> void:
	RefArt.put(sheet, cell, CELL, CELL, col, row)
