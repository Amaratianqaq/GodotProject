extends SceneTree
# =============================================================================
#  gen_props.gd —— 森林场景道具生成器（《元气骑士前传》风格参考素材）
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_props.gd
#
#  产出（13 张独立 PNG，尺寸与 docs/10 §3.3 契约逐字一致）：
#    prop_tree_pine.png    32x48   落叶松（y-sort 锚点在**底部中央**）
#    prop_tree_dead.png    32x48   枯树
#    prop_tree_broad.png   48x64   阔叶树（比松树更大的剪影）
#    prop_rock_small.png   16x16   小石（无碰撞）
#    prop_rock_big.png     32x32   大石（有碰撞）
#    prop_stump.png        16x16   树桩
#    prop_bush.png         16x16   灌木
#    prop_flower_a.png     16x16   粉花
#    prop_flower_b.png     16x16   红花
#    prop_mushroom.png     16x16   蘑菇
#    prop_tall_grass.png   16x16   高草
#    prop_pebble.png       16x16   碎石（走廊装饰）
#    prop_fallen_log.png   32x16   倒木
#
#  【为什么从旧图集里拆出来】旧做法是把这些塞进 tileset_forest.png 的固定格子里，
#  于是尺寸被锁死在 16x16 —— 树只能是一格大的小图标，做不出前传那种大剪影。
#  拆成独立文件后每张可以有真实尺寸，也才谈得上"树的底部贴地、树冠往上长"。
#
#  【锚点约定】所有道具的**内容底边**贴到画布最下一行（不留边），
#  这样游戏侧只要把精灵按"底部中央"对齐格心即可，不需要逐个记偏移。
# =============================================================================

const OUT_DIR := "res://assets/sprites"


func L(rows: PackedStringArray, ox := 0, oy := 0, remap := {}) -> Array:
	return [rows, ox, oy, remap]


## 按目标尺寸建画布并叠层，最后描边
func _prop(w: int, h: int, layers: Array) -> Image:
	var img := RefArt.new_img(w, h)
	for l in layers:
		RefArt.blit(img, l[0], l[1], l[2], l[3] if l.size() > 3 else {})
	RefArt.outline(img, 0, 0, w, h)
	return img


## 把内容**底边贴到画布最下**、**水平居中**。
##
## 两个都是锚点契约的一部分：
##  · 贴底 —— 游戏侧统一按"底部中央"对齐格心，不贴底就会整体浮空；
##  · 水平居中 —— 否则精灵的视觉中心与格心错开，摆一排树会看出歪。
##    实测第一版松树的内容落在 0..20（32 宽画布），偏左 5px，就是因为没居中。
func _ground(img: Image) -> Image:
	var h := img.get_height()
	var w := img.get_width()
	var x0 := w
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.05:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if y1 < 0:
		return img
	var dy := (h - 1) - y1
	var content_w := x1 - x0 + 1
	var dx := int(roundf(float(w - content_w) / 2.0)) - x0
	if dy == 0 and dx == 0:
		return img
	return RefArt.shift_cell(img, dx, dy)


# =============================================================================
#  树（32x48 / 48x64）
# =============================================================================

## 落叶松：三层锥形树冠 + 露出的树干
var PINE := PackedStringArray([
	"                 kkk",
	"                kEEk",
	"               kEEEk",
	"              kEEEEk",
	"             kEEEEEk",
	"            kGGEEEEk",
	"           kGGGEEEgk",
	"          kGGGGEEggk",
	"         kGGGGGGgggk",
	"        kGGGGGGGgggk",
	"       kGGGGGGGGgggk",
	"      kGGGGGGGGGgggk",
	"     kGGGGGGGGGGgggk",
	"    kGGGGGGGGGGGgggk",
	"   kGGGGGGGGGGGGgggk",
	"  kGGGGGGGGGGGGGgggk",
	" kGGGGGGGGGGGGGGgggk",
	"kGGGGGGGGGGGGGGGgggk",
	"kggggggggggggggggggk",
	" kkkkkkkkkkkkkkkkkk",
	"       kEEEEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kEGGEk",
	"       kbbbbk",
	"       kbbbbk",
	"       kbbbbk",
	"       kbbbbk",
	"       kbbbbk",
	"      kbbbbbbk",
	"      kbbbbbbk",
	"     kbbbbbbbbk",
	"     kbbbbbbbbk",
	"    kbbbkkkkbbbk",
	"    kbbk    kbbk",
	"    kbbk    kbbk",
	"   kbbbk    kbbbk",
	"   kbbbk    kbbbk",
	"  kbbbbk    kbbbbk",
	"  kbbbbk    kbbbbk",
	" kbbbbbk    kbbbbbk",
	" kbbbbbk    kbbbbbk",
	"kbbbbbbk    kbbbbbbk",
	"kkkkkkkk    kkkkkkkk",
])

## 阔叶树：团状树冠（48x64）
var BROAD := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"                  kkkkkk",
	"               kkEEEEEEEEkk",
	"             kkEEEEEEEEEEEEkk",
	"            kEEEEEEEEEEEEEEEEk",
	"           kEEEEEEEEEEEEEEEEEEk",
	"          kEEEEEEEEEEEEEEEEEEEEk",
	"         kEEEEEEEEEEEEEEEEEEEEEEk",
	"        kEEEEEEEEEEEEEEEEEEEEEEEEk",
	"       kEEEEEEEEEEEEEEEEEEEEEEEEEEk",
	"      kGGEEEEEEEEEEEEEEEEEEEEEEEEEEk",
	"     kGGGEEEEEEEEEEEEEEEEEEEEEEEEEEgk",
	"    kGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEggk",
	"   kGGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEgggk",
	"  kGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEggggk",
	" kGGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEgggggk",
	"kGGGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEggggggk",
	"kGGGGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEgggggggk",
	"kGGGGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEgggggggk",
	"kGGGGGGGGGGEEEEEEEEEEEEEEEEEEEEEEgggggggggk",
	"kGGGGGGGGGGEEEEEEEEEEEEEEEEEEEEEEgggggggggk",
	"kGGGGGGGGGGGEEEEEEEEEEEEEEEEEEEEggggggggggk",
	"kGGGGGGGGGGGEEEEEEEEEEEEEEEEEEEEggggggggggk",
	"kGGGGGGGGGGGGEEEEEEEEEEEEEEEEEEgggggggggggk",
	"kGGGGGGGGGGGGEEEEEEEEEEEEEEEEEEgggggggggggk",
	" kGGGGGGGGGGGGEEEEEEEEEEEEEEEEgggggggggggk",
	" kGGGGGGGGGGGGGEEEEEEEEEEEEEEgggggggggggk",
	"  kGGGGGGGGGGGGGEEEEEEEEEEEEgggggggggggk",
	"   kGGGGGGGGGGGGGEEEEEEEEEEgggggggggggk",
	"    kGGGGGGGGGGGGGGEEEEEEggggggggggggk",
	"     kGGGGGGGGGGGGGGGEEgggggggggggggk",
	"      kkGGGGGGGGGGGGGgggggggggggggkk",
	"        kkkkkkkkkkkkkkkkkkkkkkkkkk",
	"                    kbbk",
	"                    kbbk",
	"                    kbbk",
	"                    kbbk",
	"                    kbbk",
	"                    kbbk",
	"                    kbbk",
	"                    kbbk",
	"                   kbbbbk",
	"                   kbbbbk",
	"                  kbbbbbbk",
	"                  kbbbbbbk",
	"                 kbbbkkbbbk",
	"                 kbbk  kbbk",
	"                 kbbk  kbbk",
	"                kbbbk  kbbbk",
	"                kbbbk  kbbbk",
	"               kbbbbk  kbbbbk",
	"               kbbbbk  kbbbbk",
	"              kbbbbbk  kbbbbbk",
	"             kbbbbbbk  kbbbbbbk",
	"             kbbbbbbk  kbbbbbbk",
	"            kbbbbbbbk  kbbbbbbbk",
	"            kbbbbbbbk  kbbbbbbbk",
	"           kbbbbbbbbk  kbbbbbbbbk",
	"           kkkkkkkkkk  kkkkkkkkkk",
])

## 枯树：歪斜的枝干（32x48）
var DEAD := PackedStringArray([
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
	"      kk",
	"     kbbk   kk",
	"     kbbk  kbbk",
	"     kbbkkkbbbkk",
	"     kbbbbbbbbbk",
	"      kbbbbbbbk",
	"       kbbbbbk",
	"        kbbbk",
	"        kbbbk  kk",
	"        kbbbk kbbk",
	"        kbbbk kbbk",
	"        kbbbbkbbbk",
	"        kbbbbbbbk",
	"         kbbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"         kbbbbk",
	"        kbbbbbbk",
	"        kbbbbbbk",
	"       kbbbbbbbbk",
	"       kbbbbbbbbk",
	"      kbbbkkkkbbbk",
	"      kbbk    kbbk",
	"     kbbbk    kbbbk",
	"     kbbbk    kbbbk",
	"    kbbbbk    kbbbbk",
	"    kbbbbk    kbbbbk",
	"   kbbbbbk    kbbbbbk",
])

# =============================================================================
#  石头 / 树桩 / 灌木（16x16、32x32）
# =============================================================================

var ROCK_SMALL := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"       kkkkkk",
	"      k777777k",
	"     k77666666k",
	"    k7766ee6665k",
	"    k7666eeee665k",
	"   k76666ee6665k",
	"   k66666666665k",
	"   k5555555555k",
	"    kkkkkkkkkk",
])

var ROCK_BIG := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"        kkkkkkkk",
	"      kk77777777kk",
	"     k777777777777k",
	"    k7776666666677k",
	"   k7776666666666775k",
	"   k77666ee6666666655k",
	"  k7766eeee6666ee66655k",
	"  k7666eeee666eeee6655k",
	"  k766666ee6666ee66655k",
	"  k6666666666666666655k",
	"  k6666666kk6666666655k",
	"  k5566666kk6666666555k",
	"  k5555666666666665555k",
	"  k5555555555555555555k",
	"   k55555555555555555k",
	"   k55555555555555555k",
	"    k555555555555555k",
	"    k555555555555555k",
	"     k5555555555555k",
	"     k555555555555k",
	"      k55555555kk",
	"       kkkkkkkk",
	"",
	"",
	"",
])

var STUMP := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkkkk",
	"     kTTTTTTTTk",
	"    kTtTttTttTtk",
	"    kTttTttTttTk",
	"    ktTttTttTtTk",
	"    kTttTttTttTk",
	"    ktTTTTTTTTtk",
	"     kbbbbbbbbk",
	"     kkkkkkkkkk",
])

var BUSH := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkk",
	"    kkEEEEEEkk",
	"   kEEEEEEEEEEk",
	"  kEEEEEEEEEEEEk",
	"  kEGEEEEEEEEGGk",
	"  kGGGEEEEEEGGGk",
	"  kGGGGGGGGGGGGk",
	"   kkkkkkkkkkkk",
])

var FLOWER_A := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kKKk",
	"     kKKKKKk",
	"     kKOOKKk",
	"     kKKKKKk",
	"      kKKk",
	"       kEk",
	"       kEk",
	"       kGk",
])

var FLOWER_B := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"      kRRk",
	"     kRRRRRk",
	"     kROORRk",
	"     kRRRRRk",
	"      kRRk",
	"       kEk",
	"       kEk",
	"       kGk",
])

var MUSHROOM := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkk",
	"     kRRRRRRk",
	"    kRWWRRWWRk",
	"    kRRRRRRRRk",
	"    krrrrrrrrk",
	"     k777777k",
	"     k777777k",
	"     k777777k",
	"     k666666k",
	"      kkkkkk",
])

var TALL_GRASS := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"",
	"     kE    kE",
	"    kEEk  kEEk",
	"    kEGk  kEGk",
	"   kEEGk kEEGk",
	"   kEGGkkEGGk",
	"   kEGGkkEGGk",
	"  kEGGGkkEGGGk",
	"  kGGGGkkGGGGk",
	"  kkkkkkkkkkkk",
])

var PEBBLE := PackedStringArray([
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
	"      kkk",
	"   kkkk66k",
	"  k6666665k",
	"  k6666555k",
	"  k5555555k",
	"   kkkkkkkk",
])

## 倒木（横躺）
var FALLEN_LOG := PackedStringArray([
	"",
	"",
	"",
	"",
	"",
	"",
	"      kkkkkkkkkkkkkkkkkk",
	"    kkTTTTTTTTTTTTTTTTTTkk",
	"   kTtTttTttTttTttTttTttTk",
	"  kTttTttTttTttTttTttTttTtk",
	"  ktTTTTTTTTTTTTTTTTTTTTTtk",
	"  kEEEEEEEEeEEEEEEEEeEEEEEk",
	"  kGGGGGGGGGGGGGGGGGGGGGGGk",
	"   kbbbbbbbbbbbbbbbbbbbbbk",
	"    kkkkkkkkkkkkkkkkkkkkkk",
	"",
])

# =============================================================================
#  入口
# =============================================================================

func _init() -> void:
	print("=== 森林场景道具生成（新调色板）===")
	RefArt.reset_stats()
	var dir := ProjectSettings.globalize_path(OUT_DIR)

	_save_prop(dir, "prop_tree_pine.png", 32, 48, [L(PINE)])
	_save_prop(dir, "prop_tree_broad.png", 48, 64, [L(BROAD)])
	_save_prop(dir, "prop_tree_dead.png", 32, 48, [L(DEAD)])
	_save_prop(dir, "prop_rock_small.png", 16, 16, [L(ROCK_SMALL)])
	_save_prop(dir, "prop_rock_big.png", 32, 32, [L(ROCK_BIG)])
	_save_prop(dir, "prop_stump.png", 16, 16, [L(STUMP)])
	_save_prop(dir, "prop_bush.png", 16, 16, [L(BUSH)])
	_save_prop(dir, "prop_flower_a.png", 16, 16, [L(FLOWER_A)])
	_save_prop(dir, "prop_flower_b.png", 16, 16, [L(FLOWER_B)])
	_save_prop(dir, "prop_mushroom.png", 16, 16, [L(MUSHROOM)])
	_save_prop(dir, "prop_tall_grass.png", 16, 16, [L(TALL_GRASS)])
	_save_prop(dir, "prop_pebble.png", 16, 16, [L(PEBBLE)])
	_save_prop(dir, "prop_fallen_log.png", 32, 16, [L(FALLEN_LOG)])

	RefArt.report("场景道具")
	quit(0)


## 生成 + 落地对齐 + 存盘。
## 所有道具都把内容底边顶到画布最后一行 —— 游戏侧就能统一按"底部中央"对齐，
## 不用为每张图单独记一个偏移量。
func _save_prop(dir: String, fname: String, w: int, h: int, layers: Array) -> void:
	var img := _prop(w, h, layers)
	img = _ground(img)
	RefArt.save(img, dir, fname)
