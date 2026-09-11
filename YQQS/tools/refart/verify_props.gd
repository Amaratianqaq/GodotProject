extends SceneTree
# 场景道具自检：尺寸、是否空、**底边是否贴到画布最后一行**（锚点契约）、配色合规。
#
# 【为什么专门查"底边贴底"】游戏侧统一按"底部中央"对齐格心。
# 如果哪张图的内容底边没到最后一行的，那件道具就会整体浮起来 ——
# 这种错误在单张图上看不出来，只有把所有道具并排才会发现。

const OUT_DIR := "res://assets/sprites"

const PROPS := [
	{"file": "prop_tree_pine.png", "w": 32, "h": 48},
	{"file": "prop_tree_dead.png", "w": 32, "h": 48},
	{"file": "prop_tree_broad.png", "w": 48, "h": 64},
	{"file": "prop_rock_small.png", "w": 16, "h": 16},
	{"file": "prop_rock_big.png", "w": 32, "h": 32},
	{"file": "prop_stump.png", "w": 16, "h": 16},
	{"file": "prop_bush.png", "w": 16, "h": 16},
	{"file": "prop_flower_a.png", "w": 16, "h": 16},
	{"file": "prop_flower_b.png", "w": 16, "h": 16},
	{"file": "prop_mushroom.png", "w": 16, "h": 16},
	{"file": "prop_tall_grass.png", "w": 16, "h": 16},
	{"file": "prop_pebble.png", "w": 16, "h": 16},
	{"file": "prop_fallen_log.png", "w": 32, "h": 16},
]

var _errors: Array[String] = []
var _logs: Array[String] = []


func _init() -> void:
	print("=== 场景道具自检 ===")
	print("文件                        尺寸      占用  底边贴底  用色")
	for p in PROPS:
		_check(p)
	print("")
	for l in _logs:
		print("[道具] ", l)
	if _errors.is_empty():
		print("⇒ 全部通过 ✅")
		quit(0)
	else:
		for e in _errors:
			print("[道具] [ERROR] ", e)
		quit(1)


func _check(p: Dictionary) -> void:
	var f: String = String(p["file"])
	var path := OUT_DIR + "/" + f
	if not ResourceLoader.exists(path):
		_errors.append("%s 不存在" % f)
		return
	var img: Image = load(path).get_image()
	var ww: int = p["w"]
	var hh: int = p["h"]
	if img.get_width() != ww or img.get_height() != hh:
		_errors.append("%s 尺寸 %dx%d，期望 %dx%d" % [
			f, img.get_width(), img.get_height(), ww, hh])
		return

	var filled := 0
	var y1 := -1
	var x0 := img.get_width()
	var x1 := -1
	var colors := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.05:
				continue
			filled += 1
			y1 = maxi(y1, y)
			x0 = mini(x0, x)
			x1 = maxi(x1, x)
			var h := c.to_html(false)
			colors[h] = true

	var ratio := float(filled) / float(ww * hh)
	var grounded := y1 == img.get_height() - 1
	print("%-26s %2dx%-2d  %5.1f%%  %-8s  %d 种" % [
		f, img.get_width(), img.get_height(), ratio * 100.0,
		"是" if grounded else "**否**", colors.size()])

	if filled == 0:
		_errors.append("%s 完全空白" % f)
		return
	if not grounded:
		_errors.append("%s 内容底边在 y=%d，画布高 %d —— 未贴底，道具会浮空" % [
			f, y1, img.get_height()])
	if ratio < 0.15:
		_errors.append("%s 只有 %.1f%% 的像素非空，太稀疏" % [f, ratio * 100.0])

	# 配色：必须落在 RefArt 调色板内
	var miss: Array = []
	for h in colors.keys():
		if not RefArt.PAL.values().has("#" + String(h)):
			miss.append(h)
	if not miss.is_empty():
		_errors.append("%s 用了调色板外的颜色 %s" % [f, str(miss)])

	_logs.append("%s  %dx%d  占用 %.0f%%  底边贴底=%s  水平 %d..%d" % [
		f, ww, hh, ratio * 100.0, "是" if grounded else "否", x0, x1])
