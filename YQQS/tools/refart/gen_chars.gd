extends SceneTree
# =============================================================================
#  gen_chars.gd —— 角色 / 敌人图集生成器（《元气骑士前传》风格参考素材）
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_chars.gd
#
#  产出（覆盖到 assets/sprites/，文件名与 docs/10 契约逐字一致）：
#    player_ranger.png        128x128  32px x 4 列 x 4 行
#    enemy_slime.png          128x128  同上
#    enemy_bat.png            128x128
#    enemy_mushroom.png       128x128
#    enemy_goblin.png         128x128
#    enemy_goblin_archer.png  128x128
#    enemy_goblin_guard.png   128x128
#    boss_goblin_priest.png   256x256  64px x 4 列 x 4 行
#
#  【为什么要重画】旧素材是《元气骑士》地牢风（低饱和、偏暗）；
#  新地表（tools/refart/gen_ground.gd）是《元气骑士前传》风（明亮、成片）。
#  两套混在一屏里会像两个游戏 —— 本文件把角色侧统一到同一套 32 色调色板。
#
#  【画法】分层字符画（沿用 tools/gen_pixel_assets.gd 的办法）：
#    每个部位是一段 PackedStringArray，字符 = RefArt.PAL 的键，'.' = 透明；
#    _cell() 把若干层按偏移叠进一格，最后统一描边。
#    同一套身体复用出 16 个姿势，不必逐格手绘。
#
#  【帧号语义】与 Atlas.ENEMY_ANIMS 必须一致：
#    row 0: 0 待机   1 走A   2 走B   3 走C/落地
#    row 1: 4 攻击A  5 攻击B 6 攻击C 7 攻击D
#    row 2: 8 受击   9 眩晕  10 死亡A 11 死亡B
#    row 3: 12 警告  13 施法A 14 施法B 15 特殊
#
#  【写字符画的三条纪律】
#    1. 行长度必须完全一致（本文件统一用 22 列宽），短了不会报错但会静默错位。
#    2. 一律用 var，不用 const —— PackedStringArray 字面量不是常量表达式。
#    3. 先画宽后画窄的层：_cell() 按数组顺序叠加，后写的覆盖先写的。
# =============================================================================

const OUT_DIR := "res://assets/sprites"
const CELL := 32          ## 角色 / 小怪格子边长
const BOSS_CELL := 64     ## BOSS 格子边长

## 统一的行宽：所有字符画都按这个宽度写，偏移量才好算
const W := 22


# =============================================================================
#  1. 图层工具
# =============================================================================

func L(rows: PackedStringArray, ox := 0, oy := 0, remap := {}, scale := 1) -> Array:
	return [rows, ox, oy, remap, scale]


## 把若干层叠成一格并统一描边。
## 层的格式：[字符画, ox, oy, remap, scale]
## scale 的含义是「这段字符画是按 **1/scale 大小的格子**手写的」——
## scale=2 表示字符画本身只占半格，先画进临时小图再整数倍放大。
## **BOSS 的长袍不需要 scale**：那段字符画本来就是按 64 格手写的（宽 48 列）。
## 早先给它套了 2x，结果字符画先被塞进 32 的临时小图、右半边被裁掉，再放大成 64 ——
## 表现出来就是 BOSS 只占格子右下角一小块。判定办法见 check_chars_layout.gd 的水平范围。
func _cell(layers: Array, size := CELL) -> Image:
	var img := RefArt.new_img(size, size)
	for l in layers:
		var rows: PackedStringArray = l[0]
		var ox: int = l[1]
		var oy: int = l[2]
		var remap: Dictionary = l[3] if l.size() > 3 else {}
		var scale: int = l[4] if l.size() > 4 else 1
		if scale <= 1:
			RefArt.blit(img, rows, ox, oy, remap)
		else:
			# 先画到临时小图再整数放大。
			# 【注意】两张图都必须用 RefArt.new_img 建：混用 Image.create() 会因为
			# 返回类型与参数标注不一致而报 "Cannot pass a value of type Image as Image"。
			var small := size / scale
			var tmp := RefArt.new_img(small, small)
			RefArt.blit(tmp, rows, 0, 0, remap)
			var big := RefArt.new_img(size, size)
			for y in small:
				for x in small:
					var c := tmp.get_pixel(x, y)
					if c.a <= 0.5:
						continue
					for dy in scale:
						for dx in scale:
							big.set_pixel(x * scale + dx, y * scale + dy, c)
			RefArt.blit_img(img, big, 0, 0)
	RefArt.outline(img, 0, 0, size, size)
	return img


## 水平镜像一格（侧面朝右 → 侧面朝左）
func _mirror(cell: Image) -> Image:
	var out := RefArt.new_img(cell.get_width(), cell.get_height())
	for y in cell.get_height():
		for x in cell.get_width():
			var c := cell.get_pixel(x, y)
			if c.a > 0.5:
				out.set_pixel(cell.get_width() - 1 - x, y, c)
	return out


func _put(sheet: Image, col: int, row: int, cell: Image, size := CELL) -> void:
	RefArt.put(sheet, cell, size, size, col, row)


## 格内内容的包围盒，返回 Vector4i(x0, y0, x1, y1)；全空时 x1/y1 < 0。
##
## 【为什么不用 bb.w / bb.z 之类的分量名】Vector4i 的分量是 x, y, z, w，
## 于是 y1 对应的是 `.w`、x1 对应 `.z` —— 极易搞混。
## 曾经把 "内容的底边 y1" 写成 `.w`（其实是 x1），结果落地对齐整段错位、
## BOSS 也被裁到只剩一角。所以这里一律用具名的局部变量，不直接点分量。
func _bbox(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.05:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "empty": x1 < 0}


## 把一组格整体下移，使内容的**下缘**贴到距格底 `bottom_margin` 像素处。
##
## 【为什么必须做这一步】2.5D 里精灵的锚点在**脚下**（Actor 的碰撞体原点在地面平面），
## 所以每格内容的底边必须贴近格子下缘。字符画是按"从上往下数"写的，
## 很容易在格子底部留出一片空白 —— 那样角色会整体"浮在空中"，
## 而且 32px 的格子里白白浪费 6~8 行。
##
## 【为什么用统一偏移，而不是逐格对齐】逐格对齐会让每帧各自贴底，
## 于是"跳跃/下蹲"这类本该改变高度的姿势被压平，动画会抖。
## 这里只按**参考帧**算一次偏移量，整组同移，姿势的相对高度差就保住了。
func _baseline(cells: Array, bottom_margin := 2, ref_index := 0) -> Array:
	if cells.is_empty():
		return cells
	var size: int = cells[0].get_width()
	var probe: Image = cells[clampi(ref_index, 0, cells.size() - 1)]
	var bb := _bbox(probe)
	if bool(bb["empty"]):
		return cells
	var content_bottom: int = int(bb["y1"])
	var want_bottom := size - 1 - bottom_margin
	var shift := want_bottom - content_bottom
	if shift == 0:
		return cells
	var out: Array = []
	for c in cells:
		out.append(RefArt.shift_cell(c, 0, shift))
	return out


## 把一套 16 格按固定顺序摆进 4x4 表。
## bottom_margin > 0 时先做落地对齐（见 _baseline）；< 0 表示不对齐（用于飞行怪）。
## ref_index 指定用哪一帧做对齐基准（默认待机帧）。
func _sheet_from_cells(cells: Array, size := CELL, bottom_margin := 2, ref_index := 0) -> Image:
	var ordered := cells
	if bottom_margin >= 0:
		ordered = _baseline(cells, bottom_margin, ref_index)
	var sheet := RefArt.new_img(size * 4, size * 4)
	for i in mini(ordered.size(), 16):
		_put(sheet, i % 4, i / 4, ordered[i], size)
	return sheet


# =============================================================================
#  2. 游侠（player_ranger）
# =============================================================================

var HERO_DOWN := PackedStringArray([
	"",
	"",
	"",
	"",
	"         kkkkkk",              # 兜帽顶
	"       kEEEEeeee",
	"      kEEEeeeeegk",
	"      kEEeeeeeggk",
	"      kEeeeeeeegk",
	"      kgeeeeeeegk",
	"      kg1111111gk",            # 帽檐阴影
	"      kg1111111gk",
	"      kg1WW11WW1gk",           # 眼睛
	"      kg1WW11WW1gk",
	"      kg11122111gk",           # 下巴
	"      kg1111111gk",
	"      kggeeeeeegk",
	"     kggeeeeeeeegk",           # 肩
	"     kEeeeeeeeeegk",           # 斗篷 + 皮甲
	"     kEebBBBBBBbegk",
	"     kEebBBttBBbegk",          # 胸甲高光
	"     kEebBBOOBBbegk",          # 腰带铜扣
	"     kEebBBBBBBbegk",
	"     kgebBBBBBBbegk",
	"     kggeeeeeeeegk",
])

var HERO_UP := PackedStringArray([
	"",
	"",
	"",
	"",
	"         kkkkkk",
	"       kEEEEeeee",
	"      kEEEeeeeegk",
	"      kEEeeeeeggk",
	"      kEeeeeeeegk",
	"      kg1111111gk",            # 帽后（无脸）
	"      kg1111111gk",
	"      kg1111111gk",
	"      kg1111111gk",
	"      kg1111111gk",
	"      kg1111111gk",
	"      kg1111111gk",
	"      kggeeeeeegk",
	"     kggeeeeeeeegk",
	"     kEeeeeeeeeegk",
	"     kEeKKKKKKKegk",           # 樱粉围巾
	"     kEeKKKKKKKegk",
	"     kEebBBBBBBbegk",
	"     kEebBBBBBBbegk",
	"     kgebBBBBBBbegk",
	"     kggeeeeeeeegk",
])

var HERO_SIDE := PackedStringArray([
	"",
	"",
	"",
	"",
	"        kkkkkk",
	"     kkEEEEeeee",
	"    kEEEEeeeeegk",
	"    kEEeeeeeeegk",
	"    kEeeeeeeeegk",
	"    kgeeeeeeeegk",
	"    kg11111111gk",
	"    kg1WW11111gk",             # 单眼
	"    kg1WW11111gk",
	"    kg1111111gk",
	"    kg1112111gk",
	"    kg1111111gk",
	"    kggeeeeeeegk",
	"   kggeeeeeeeeegk",
	"   kEeeeeeeeeeegk",
	"   kEeKKKKKKKKegk",            # 围巾在颈侧
	"   kEebBBBBBBbegk",
	"   kEebBBBBBBbegk",
	"   kEebBBBBBBbegk",
	"   kgebBBBBBBbegk",
	"   kggeeeeeeeegk",
])

var LEGS_IDLE := PackedStringArray([
	"     kbbbbbbbbk",
	"    kBbbk..kBbbk",
	"    kBbbk..kBbbk",
	"   kbBBbk..kbBBbk",
	"  111111..111111",
])

var LEGS_A := PackedStringArray([
	"     kbbbbbbbbk",
	"    kBbbk.kBbbk",
	"   kBbbk...kBbbk",
	"  kbBBbk...kbBBk",
	" 111111...11111",
])

var LEGS_B := PackedStringArray([
	"     kbbbbbbbbk",
	"    kBbbk.kBbbk",
	"     kBbbk.kBbbk",
	"    kbBBbk.kbBBb",
	"   111111.11111",
])

## 翻滚：缩成一团
var ROLL_BALL := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"       kkkkkkkk",
	"     kkEEEEeeeegk",
	"    kEEEEeeeeeeegk",
	"   kEEeeeeeeeeeeegk",
	"   kEeeeKKKKeeeeegk",
	"   keeeKKKKKKeeeegk",
	"   keeeeKKKKeeeeegk",
	"   kwweeeeeeeeewgk",
	"   kEeeeeeeeeeeegk",
	"    kEeeeeeeeeeegk",
	"    kkeeeeeeeeegk",
	"      kggggggk",
	"       kkkkkk",
	"",
	"",
	"",
])

## 受击：后倾 + 红闪
var HURT_BODY := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"        kkkkkk",
	"      kEEEeeee",
	"      kEEeeeggk",
	"      kEeeeeegk",
	"      kgeeeeeegk",
	"      kg1RR111gk",
	"      kg1RR111gk",
	"      kg1WW11Wgk",
	"      kg111111gk",
	"      kg111211gk",
	"      kg111111gk",
	"      kggeeeeegk",
	"     kgggeeeeegk",
	"    kEeRRRRRRRgk",
	"    kEeRRRRRRRgk",
	"    kEebBBBBBbegk",
	"    kEebBBBBBbegk",
	"    kgebBBBBBbegk",
	"    kggeeeeeeeegk",
	"     kgggggggggk",
])

## 死亡：平躺
var DEAD_BODY := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkkkkkkkk",
	"    kkEEEeeeeeeeeeegk",
	"  kEEEeeeeeeeeeeeeeegk",
	" kEeeeeeeeeeeeeeeeeeegk",
	" kgeeeeee11111111eeeeegk",
	" kgeeeeee1kk11kk1eeeeeegk",     # 闭眼
	" kgeeeeeeeeeeeeeeeeeeeeegk",
	" kgggeeeeeeeeeeeeeeeeeegk",
	"   kggggggggggggggggggk",
	"",
	"",
	"",
])

## 弓（叠在侧面身体上）
var BOW := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"             kTTk",
	"            TkkTk",
	"           Tk..kk",
	"           Tk...k",
	"          Tk....k",
	"          Tk....k",
	"          Tk....k",
	"           Tk...k",
	"           Tk..kk",
	"            TkkTk",
	"             kTTk",
])

func _build_player_sheet() -> Image:
	var side_idle := _cell([L(HERO_SIDE), L(LEGS_IDLE)])
	var side_a := _cell([L(HERO_SIDE), L(LEGS_A)])
	var side_b := _cell([L(HERO_SIDE), L(LEGS_B)])
	var roll := _cell([L(ROLL_BALL)])
	return _sheet_from_cells([
		# row 0 向下
		_cell([L(HERO_DOWN), L(LEGS_IDLE)]),
		_cell([L(HERO_DOWN), L(LEGS_A)]),
		_cell([L(HERO_DOWN), L(LEGS_B)]),
		roll,
		# row 1 向上
		_cell([L(HERO_UP), L(LEGS_IDLE)]),
		_cell([L(HERO_UP), L(LEGS_A)]),
		_cell([L(HERO_UP), L(LEGS_B)]),
		roll,
		# row 2 侧面
		side_idle, side_a, side_b, roll,
		# row 3 特殊：受击 / 拉弓 / 死亡 / 冲刺（镜像侧面）
		_cell([L(HURT_BODY), L(LEGS_IDLE)]),
		_cell([L(HERO_SIDE), L(BOW), L(LEGS_IDLE)]),
		_cell([L(DEAD_BODY)]),
		_mirror(side_a),
	])


# =============================================================================
#  3. 史莱姆（enemy_slime）
# =============================================================================

var SLIME_TALL := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"        kkkkkkkk",
	"      kEEEEEEEEeek",
	"     kEEEEEEEEEEeegk",
	"    kEEEEEEEEEEEEeegk",
	"    kEEeeeeeeeeeeegk",
	"   kEEeeeeeeeeeeeeegk",
	"   kEEeeeeeeeeeeeeegk",
	"  kEEeeeeeeeeeeeeeeegk",
	"  kEEeeeeeeeeeeeeeeegk",
	"  kEeeeeeeeeeeeeeeeegk",
	"  kEeeekk1111kkeeeeegk",
	"  keeeekW1kk1Wkeeeeegk",
	"  keeeeekkkkkeeeeeeegk",
	"  keeeeee11eeeeeeeeegk",
	"  keeeeeeeeeeeeeeeeegk",
	"  kgeeeeeeeeeeeeeeeegk",
	"  kgggeeeeeeeeeeeegggk",
	"   kkggggggggggggggk",
	"",
	"",
	"",
	"",
	"",
	"",
])

var SLIME_MID := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"       kkkkkkkkk",
	"     kEEEEEEEEEeek",
	"    kEEEEEEEEEEEeegk",
	"    kEEeeeeeeeeeeegk",
	"   kEEeeeeeeeeeeeeegk",
	"   kEEeeeeeeeeeeeeegk",
	"  kEEeeeeeeeeeeeeeeegk",
	"  keeeekk1111kkeeeeegk",
	"  keeeekW1kk1Wkeeeeegk",
	"  keeeeekkkkkeeeeeeegk",
	"  keeeeee11eeeeeeeeegk",
	"  keeeeeeeeeeeeeeeeegk",
	"  kgeeeeeeeeeeeeeeeegk",
	"  kgggeeeeeeeeeeeegggk",
	"   kkggggggggggggggk",
	"",
	"",
	"",
	"",
	"",
	"",
])

var SLIME_SQUASH := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkkkkkk",
	"    kEEEEEEEEEEEeek",
	"   kEEeeeeeeeeeeeeegk",
	"  kEEeeeeeeeeeeeeeeegk",
	"  keeeekk1111kkeeeeegk",
	"  keeeekW1kk1Wkeeeeegk",
	"  keeeeekkkkkeeeeeeegk",
	"  keeeeee11eeeeeeeeegk",
	"  keeeeeeeeeeeeeeeeegk",
	"  kgeeeeeeeeeeeeeeeegk",
	"  kgggeeeeeeeeeeeegggk",
	"   kkggggggggggggggk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

var SLIME_CORE := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"         kGGk",
	"        kGGGGk",
	"        kGGGGk",
	"         kGGk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

var SLIME_LEAF := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"         kGGk",
	"        kGEEK",
	"        kGEEK",
	"         kGGk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

var SLIME_LUNGE := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"        kkkkkkkk",
	"      kEEEEEEEEeek",
	"     kEEEEEEEEEEeegk",
	"    kEEEEEEEEEEEEeegk",
	"    kEEeeeeeeeeeeegk",
	"   kEEeeeeeeeeeeeeegk",
	"  kEEeeeeeeeeeeeeeeegk",
	"  kEeeekk1111kkeeeeegk",
	"  keeeekW1kk1Wkeeeeegk",
	"  keeeeekkkkkeeeeeeegk",
	"  keeeeee1111eeeeeeegk",
	"  keeeeeekkkkeeeeeeeegk",
	"  keeeeeeeeeeeeeeeeegk",
	"  keeeeeeeeeeeeeeeeegk",
	"  kgeeeeeeeeeeeeeeeegk",
	"  kgggeeeeeeeeeeeegggk",
	"   kkggggggggggggggk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

func _build_slime_sheet() -> Image:
	var leaf := L(SLIME_LEAF)
	var core := L(SLIME_CORE)
	var hurt_tint := {"e": "R", "E": "R", "G": "r"}
	var warn_tint := {"E": "O", "e": "o"}
	return _sheet_from_cells([
		_cell([L(SLIME_TALL), core, leaf]),
		_cell([L(SLIME_SQUASH), core, leaf]),
		_cell([L(SLIME_MID), core, leaf]),
		_cell([L(SLIME_TALL), core, leaf]),
		_cell([L(SLIME_SQUASH), core, leaf]),
		_cell([L(SLIME_LUNGE), core, leaf]),
		_cell([L(SLIME_TALL), core, leaf]),
		_cell([L(SLIME_SQUASH), core, leaf]),
		_cell([L(SLIME_MID, 0, 0, hurt_tint), core, leaf]),
		_cell([L(SLIME_SQUASH, 0, 0, {"W": "O"}), core, leaf]),
		_cell([L(SLIME_SQUASH), core]),
		_cell([L(SLIME_SQUASH), core]),
		_cell([L(SLIME_TALL, 0, 0, warn_tint), core]),
		_cell([L(SLIME_TALL), core, leaf]),
		_cell([L(SLIME_LUNGE, 0, 0, {"E": "O"}), core]),
		_cell([L(SLIME_TALL), core, leaf]),
	])


# =============================================================================
#  4. 蝙蝠（enemy_bat）—— 悬空，翅膀三种开合 + 收拢
# =============================================================================

## 翅膀：完全上举
var BAT_WING_UP := PackedStringArray([
	"  kk            kk",
	" kppk          kppk",
	"kppppk        kppppk",
	"kpppppk      kpppppk",
	"kppppppk    kppppppk",
	" kppppppk  kppppppk",
	"  kppppppkkppppppk",
	"   kppppppppppppk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

## 翅膀：平展
var BAT_WING_MID := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"kkkkkkkkkkkkkkkkkkkkk",
	"kppppppppppppppppppppk",
	"kpppppppppppppppppppk",
	" kppppppppppppppppk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

## 翅膀：下垂
var BAT_WING_DOWN := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"   kppppppppppppk",
	"  kppppppkkppppppk",
	" kppppppk  kppppppk",
	"kppppppk    kppppppk",
	"kpppppk      kpppppk",
	"kppppk        kppppk",
	" kppk          kppk",
	"  kk            kk",
	"",
	"",
	"",
	"",
	"",
	"",
])

## 翅膀：收拢贴肩
var BAT_WING_FOLD := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkkkk",
	"     kppppppppk",
	"    kpppppppppppk",
	"    kpppppppppppk",
	"     kppppppppk",
	"      kkkkkkkk",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
])

## 身体（悬空）：紫灰毛 + 大眼 + 小尖牙
var BAT_BODY := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"         kkkkkk",
	"        k333333k",
	"       k33333333k",
	"       k3OO33OO3k",            # 黄眼
	"       k3W1331W3k",
	"       k333kk333k",
	"       k3Wk33kW3k",            # 尖牙
	"       k33333333k",
	"        k3333333k",
	"        kk3333kk",
	"          kkkk",
])

## 张嘴（攻击）
var BAT_BODY_OPEN := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"         kkkkkk",
	"        k333333k",
	"       k33333333k",
	"       k3RR33RR3k",            # 怒目
	"       k3W1331W3k",
	"       k333kk333k",
	"       k3WW33WW3k",            # 大张的嘴
	"       k3WkkkkW3k",
	"        k3WWWWW3k",
	"        kk3333kk",
	"          kkkk",
])

func _build_bat_sheet() -> Image:
	var body := L(BAT_BODY)
	var body_open := L(BAT_BODY_OPEN)
	var up := _cell([L(BAT_WING_UP), body])
	var mid := _cell([L(BAT_WING_MID), body])
	var down := _cell([L(BAT_WING_DOWN), body])
	var fold := _cell([L(BAT_WING_FOLD), body])
	var bite := _cell([L(BAT_WING_MID), body_open])
	var dive := _cell([L(BAT_WING_UP), body_open])
	return _sheet_from_cells([
		# row 0 悬停循环：全上 / 中 / 全下 / 收拢
		up, mid, down, fold,
		# row 1 攻击：尖叫 / 俯冲 / 抓击 / 收势
		bite, dive, _cell([L(BAT_WING_DOWN), body_open]), mid,
		# row 2 反应：受击 / 眩晕 / 死亡A / 死亡B
		_cell([L(BAT_WING_MID, 0, 0, {"3": "R", "p": "r"}), body]),
		_cell([L(BAT_WING_DOWN, 0, 0, {"3": "p"}), body]),
		_cell([L(BAT_WING_FOLD), body]),
		_cell([L(BAT_WING_MID, 0, 0, {"O": "k"}), body]),
		# row 3 特殊：警告 / 蓄力 / 吐弹 / 倒挂
		_cell([L(BAT_WING_MID, 0, 0, {"3": "O"}), body]),
		fold,
		_cell([L(BAT_WING_UP), L(BAT_BODY_OPEN, 0, 0, {"3": "p"})]),
		fold,
	], CELL, -1)   # 飞行怪不贴地：保持悬空感，不做落地对齐


# =============================================================================
#  5. 蘑菇（enemy_mushroom）
# =============================================================================

var MUSH_CAP := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"        kkkkkkkk",
	"      kRRRRRRRRRRk",
	"     kRROORRRROORRk",          # 白斑
	"    kRRRRRRRRRRRRRRk",
	"   kRROORRRRRRROORRRk",
	"   kRRRRRRRRRRRRRRRRk",
	"   krrrrrrrrrrrrrrrrk",
	"    kkkkkkkkkkkkkkkk",
])

## 菌柄 + 生气的脸 + 小短腿
var MUSH_STEM := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      k7777777777k",
	"      k6777777776k",
	"      k6k1k77k1k6k",           # 生气的眼
	"      k6kk1k1kkk6k",
	"      k6777kk7776k",           # 撇嘴
	"      k6677777766k",
	"      k6666666666k",
	"      k5k6666k5k",
	"      k55k55k55k",
])

## 一跳（腿收起）
var MUSH_STEM_JUMP := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      k7777777777k",
	"      k6777777776k",
	"      k6k1k77k1k6k",
	"      k6kk1k1kkk6k",
	"      k6777kk7776k",
	"      k6677777766k",
	"      k6666666666k",
	"       k56666665k",
	"        k55kk55k",
])

func _build_mushroom_sheet() -> Image:
	var cap := L(MUSH_CAP)
	var stem := L(MUSH_STEM)
	var stem_jump := L(MUSH_STEM_JUMP)
	var tilt_l := L(MUSH_CAP, -1, 0)
	var tilt_r := L(MUSH_CAP, 1, 0)
	var hurt := {"R": "r", "7": "r", "6": "1"}
	var warn := {"R": "O"}
	return _sheet_from_cells([
		# row 0 待机：站 / 左倾 / 右倾 / 跳跃
		_cell([cap, stem]),
		_cell([tilt_l, stem]),
		_cell([tilt_r, stem]),
		_cell([L(MUSH_CAP, 0, -2), stem_jump]),
		# row 1 攻击：下蹲 / 头槌 / 吐孢 / 收势
		_cell([L(MUSH_CAP, 0, 2), L(MUSH_STEM, 0, 2)]),
		_cell([L(MUSH_CAP, 0, -2), L(MUSH_STEM, 0, -2)]),
		_cell([L(MUSH_CAP, 0, 0, warn), stem]),
		_cell([cap, stem]),
		# row 2 反应：受击 / 眩晕 / 死亡A / 死亡B
		_cell([L(MUSH_CAP, 0, 0, hurt), L(MUSH_STEM, 0, 0, hurt)]),
		_cell([L(MUSH_CAP, -1, 0, {"R": "p"}), stem]),
		_cell([L(MUSH_CAP, 0, 12), L(MUSH_STEM, 0, 6)]),
		_cell([L(MUSH_CAP, 0, 14)]),
		# row 3 特殊：警告 / 吐孢 / 释放 / 硬化
		_cell([L(MUSH_CAP, 0, 0, warn), stem]),
		_cell([L(MUSH_CAP, 0, -1, {"R": "p"}), stem]),
		_cell([L(MUSH_CAP, 0, 0, {"R": "K"}), stem]),
		_cell([L(MUSH_CAP, 0, 0, {"R": "6", "O": "7"}), stem]),
	])


# =============================================================================
#  6. 哥布林家族（goblin / archer / guard）
#    三者共用同一副绿皮肤身体，只在头饰与手持物上区分 ——
#    这样一眼就能看出是同一族，符合原作的表现习惯。
# =============================================================================

## 头（绿皮肤 + 大眼 + 獠牙）
var GOB_HEAD := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"        kkkkkk",
	"      kEEEEEEEek",
	"     kEEEEEEEEegk",
	"     kEEeeeeeeggk",
	"     kEe1111e11gkk",          # 眼窝
	"     kEe1OO1e1Ogk",
	"     kEe1111e11gk",
	"     kEeeeeeeeeegk",
	"     kEeWkkkkWegk",           # 獠牙
	"     kEeeeeeeeeegk",
	"      kEeeeeeeegk",
	"       kggggggk",
])

## 尖耳朵（左右各一）
var GOB_EAR_L := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"  kkk",
	" kEEk",
	"kEEk",
	" kEk",
	"  kk",
])

var GOB_EAR_R := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"     kkk",
	"     kEEk",
	"      kEEk",
	"      kEk",
	"       kk",
])

## 躯干（褐皮甲）
var GOB_TORSO := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"     kggEEEEEEEEggk",
	"     kEgbbBBBBbbEgk",
	"     kEgbBBBBBBbEgk",
	"     kEgbBBttBBbEgk",
	"     kEgbBBOOBBbEgk",
	"     kEgbbbbbbbbEgk",
	"     kgggggggggggk",
])

## 腿：待机 / 迈步A / 迈步B
var GOB_LEGS_IDLE := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kbbbbbbbbk",
	"      kEEk..kEEk",
	"      kEEk..kEEk",
	"     kgggk..kgggk",
	"     gggg....gggg",
])

var GOB_LEGS_A := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kbbbbbbbbk",
	"      kEEk.kEEk",
	"     kEEk...kEEk",
	"    kgggk...kgggk",
	"   gggg.....gggg",
])

var GOB_LEGS_B := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kbbbbbbbbk",
	"      kEEk.kEEk",
	"      kEEk.kEEk",
	"     kgggk.kgggk",
	"     gggg.ggggg",
])

## 短剑（哥布林小兵）
var GOB_SWORD := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"                k6k",
	"                k6k",
	"                k6k",
	"                k6k",
	"               kkkkk",
	"               kbbk",
	"               kbbk",
	"                kk",
])

## 弓（哥布林弓手）
var GOB_BOW := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"            kTTk",
	"           TkkTk",
	"          Tk..kk",
	"          Tk...k",
	"         Tk....k",
	"         Tk....k",
	"          Tk...k",
	"          Tk..kk",
	"           TkkTk",
])

## 盾（哥布林卫兵）
var GOB_SHIELD := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"   kkkkkkk",
	"  kTTTTTTk",
	"  kT6666Tk",
	"  kT6ww6Tk",
	"  kT6666Tk",
	"  kTTTTTTk",
	"   kkkkkkk",
	"",
	"",
])

## 铁锅头盔（卫兵）
var GOB_HELMET := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"      kkkkkkkkk",
	"     k66666666k",
	"     k77777777k",
	"     k66666666k",
	"     kkk6666kkk",
])

## 皮帽（弓手）
var GOB_CAP := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"     kkkkkkkkk",
	"    kBBBBBBBBk",
	"    kbBBBBBBbk",
	"     kkkkkkkkk",
])

## 法杖（BOSS 用，画在 64 格上）
var PRIEST_STAFF := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"                            kkkk",
	"                           kKKKKk",
	"                          kKKppKKk",
	"                          kKppppKk",
	"                          kKKppKKk",
	"                           kKKKKk",
	"                            kkkk",
	"                            kTTk",
	"                            kTTk",
	"                            kBBk",
	"                            kBBk",
	"                            kBBk",
	"                            kBBk",
	"                            kBBk",
	"                            kBBk",
	"                            kBBk",
	"                            kBBk",
	"                           kkkkkk",
])

## 兜帽长袍（BOSS 身体，画在 64 格上）
var PRIEST_ROBE := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"                          kkkkkkkk",
	"                        kkpppppppppkk",
	"                       kpPPPPPPPPPPPpk",
	"                      kpPPPPPPPPPPPPPpk",
	"                      kpPP111111111PPpk",
	"                      kpPP1KK111KK1PPpk",     # 发光的眼
	"                      kpPP1KK111KK1PPpk",
	"                      kpPP111111111PPpk",
	"                      kpPPP1111111PPPpk",
	"                      kpPPPPPP1PPPPPPpk",
	"                      kpPPPPPPPPPPPPPPpk",
	"                     kpPPPPOOOOOOPPPPpk",     # 金饰
	"                     kpPPPPPOOOOOOPPPPpk",
	"                    kpPPPPPPPPPPPPPPPPPPk",
	"                    kpPPPPPPPPPPPPPPPPPPk",
	"                   kpPPPPPPPPPPPPPPPPPPPPpk",
	"                   kpPPPPPPPPPPPPPPPPPPPPpk",
	"                  kpPPPPPPPPPPPPPPPPPPPPPPpk",
	"                  kpPPPPPPPPPPPPPPPPPPPPPPpk",
	"                 kpPPPPPPPPPPPPPPPPPPPPPPPPpk",
	"                 kpPPPPPPPPPPPPPPPPPPPPPPPPpk",
	"                kpPPPOOPPPPPPPPPPPPPPOOPPPPpk",
	"                kpPPPPPPPPPPPPPPPPPPPPPPPPPPk",
	"                kppppppppppppppppppppppppppppk",
	"                 kkkkkkkkkkkkkkkkkkkkkkkkkkkk",
])

func _goblin_base(legs: PackedStringArray, hat: Array, hand: Array,
		tint := {}) -> Image:
	var layers: Array = [L(GOB_EAR_L), L(GOB_EAR_R)]
	layers.append(L(GOB_HEAD, 0, 0, tint))
	layers.append_array(hat)
	layers.append(L(GOB_TORSO, 0, 0, tint))
	layers.append(L(legs, 0, 0, tint))
	layers.append_array(hand)
	return _cell(layers)


func _build_goblin_sheet(hat: Array, hand: Array, hat_open: Array) -> Image:
	var hurt := {"E": "R", "e": "r"}
	var warn := {"O": "R"}
	# 挥击用的持械层：有武器时把武器挪个位置做出挥砍感
	var swing_low := []
	var swing_high := []
	if not hand.is_empty():
		swing_low.append(L(GOB_SWORD, 1, 2))
		swing_high.append(L(GOB_SWORD, -1, 3))
	return _sheet_from_cells([
		# row 0 待机 / 走 A / 走 B / 走 C
		_goblin_base(GOB_LEGS_IDLE, hat, hand),
		_goblin_base(GOB_LEGS_A, hat, hand),
		_goblin_base(GOB_LEGS_B, hat, hand),
		_goblin_base(GOB_LEGS_A, hat, hand),
		# row 1 攻击：蓄力 / 挥击 / 二次 / 收势
		_goblin_base(GOB_LEGS_IDLE, hat, hand, warn),
		_goblin_base(GOB_LEGS_A, hat, swing_low, warn),
		_goblin_base(GOB_LEGS_B, hat, swing_high, {}),
		_goblin_base(GOB_LEGS_IDLE, hat, hand, {}),
		# row 2 反应：受击 / 眩晕 / 死亡 A / 死亡 B
		_goblin_base(GOB_LEGS_IDLE, hat, hand, hurt),
		_goblin_base(GOB_LEGS_B, hat_open, hand),
		_goblin_base(GOB_LEGS_IDLE, hat, [], {"E": "g", "e": "G"}),
		_goblin_base(GOB_LEGS_B, hat, [], {"E": "g", "e": "G"}),
		# row 3 特殊：警告 / 施法 / 释放 / 突进
		_goblin_base(GOB_LEGS_IDLE, hat, hand, warn),
		_goblin_base(GOB_LEGS_A, hat, hand, {"O": "Q"}),
		_goblin_base(GOB_LEGS_B, hat, hand, {}),
		_goblin_base(GOB_LEGS_A, hat, hand, {}),
	])


# =============================================================================
#  7. BOSS：哥布林大祭司（64 格）
# =============================================================================

func _build_priest_sheet() -> Image:
	# 【注意】长袍的字符画本来就是按 64 格手写的（内容约 26 行 x 48 列），
	# 所以**不加 scale**，直接画进 64 格。给它套 scale 会造成"先裁掉右半边再放大"。
	var robe := L(PRIEST_ROBE)
	var robeless := {"P": "1", "p": "2"}
	var enraged := {"p": "O", "K": "W", "P": "p"}
	var hurt := {"P": "r", "p": "r"}
	var staff := L(PRIEST_STAFF)
	var S := BOSS_CELL
	# 在 64 格里把长袍**下压**一点：内容只占 26 行，贴着底部才有 BOSS 的分量。
	var Y := 6
	var idle := _cell([L(PRIEST_ROBE, 0, Y), L(PRIEST_STAFF, 0, Y)], S)
	var cast_a := _cell([L(PRIEST_ROBE, 0, Y - 2), L(PRIEST_STAFF, 0, Y)], S)
	var cast_b := _cell([L(PRIEST_ROBE, 0, Y - 3, enraged), L(PRIEST_STAFF, 0, Y)], S)
	return _sheet_from_cells([
		# row 0 待机循环
		idle,
		_cell([L(PRIEST_ROBE, 0, Y + 1), L(PRIEST_STAFF, 0, Y)], S),
		_cell([L(PRIEST_ROBE, 0, Y - 1), L(PRIEST_STAFF, 0, Y)], S),
		_cell([L(PRIEST_ROBE, 0, Y - 2), L(PRIEST_STAFF, 0, Y)], S),
		# row 1 近战连击
		_cell([L(PRIEST_ROBE, -2, Y), L(PRIEST_STAFF, -4, Y - 4)], S),
		_cell([L(PRIEST_ROBE, 0, Y), L(PRIEST_STAFF, 2, Y + 4)], S),
		_cell([L(PRIEST_ROBE, 2, Y), L(PRIEST_STAFF, 3, Y)], S),
		idle,
		# row 2 施法
		cast_a, cast_b,
		_cell([L(PRIEST_ROBE, 0, Y, enraged), L(PRIEST_STAFF, 0, Y)], S),
		_cell([L(PRIEST_ROBE, 0, Y - 4, enraged), L(PRIEST_STAFF, 0, Y - 4)], S),
		# row 3 特殊：受击 / 狂暴 / 死亡A（长袍瘫落） / 死亡B（只剩法杖）
		_cell([L(PRIEST_ROBE, 0, Y, hurt), L(PRIEST_STAFF, 0, Y)], S),
		_cell([L(PRIEST_ROBE, 0, Y - 2, enraged), L(PRIEST_STAFF, 0, Y - 6)], S),
		_cell([L(PRIEST_ROBE, 0, Y + 14, robeless)], S),
		# 死亡 B：残余的魔力水晶落在地上（原作的收尾方式）。
		# 【注意填充率】Validation 要求每个被引用的格子至少有 4% 的像素是实心。
		# 之前这里只放一根孤零零的法杖，填充率不到 4%，被当成"空素材"拒掉 ——
		# 表现是 Validation 报 "被代码引用但为空的格子 3,3"。所以这一帧要画得实一点：
		# 瘫落的长袍 + 立在地上的法杖，既好看又过得了检查。
		_cell([L(PRIEST_ROBE, 0, Y + 12, robeless), L(PRIEST_STAFF, 0, 10)], S),
	], S, 2, 0)


# =============================================================================
#  8. 入口
# =============================================================================

func _init() -> void:
	print("=== 角色 / 敌人图集生成（新调色板）===")
	RefArt.reset_stats()
	var dir := ProjectSettings.globalize_path(OUT_DIR)

	var empty: Array = []
	RefArt.save(_build_player_sheet(), dir, "player_ranger.png")
	RefArt.save(_build_slime_sheet(), dir, "enemy_slime.png")
	RefArt.save(_build_bat_sheet(), dir, "enemy_bat.png")
	RefArt.save(_build_mushroom_sheet(), dir, "enemy_mushroom.png")
	RefArt.save(_build_goblin_sheet(empty, [L(GOB_SWORD)], empty), dir, "enemy_goblin.png")
	RefArt.save(_build_goblin_sheet([L(GOB_CAP)], [L(GOB_BOW)], [L(GOB_CAP, 0, 1)]),
		dir, "enemy_goblin_archer.png")
	RefArt.save(_build_goblin_sheet([L(GOB_HELMET)], [L(GOB_SHIELD)], [L(GOB_HELMET, 0, 2)]),
		dir, "enemy_goblin_guard.png")
	RefArt.save(_build_priest_sheet(), dir, "boss_goblin_priest.png")

	RefArt.report("角色 / 敌人图集")
	quit(0)
