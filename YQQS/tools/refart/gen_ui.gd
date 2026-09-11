extends SceneTree
# =============================================================================
#  gen_ui.gd —— UI 素材生成器（《元气骑士前传》风格参考素材）
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_ui.gd
#
#  产出（尺寸与 docs/10 §3.4 契约一致）：
#    ui_panel.png        64x64   九宫格面板（木质外框 + 深色内部）
#    ui_bar.png          64x32   上=血条（红）下=蓝条（蓝），横向拉伸
#    ui_bar_armor.png    64x16   护甲条（钢灰），横向拉伸
#    ui_frame_rarity.png 64x16   品质框 4 格（16px x 4 列）
#
#  ★ **九宫格边距必须是 10px**，这是 scripts/ui/ui_kit.gd 的 wood_stylebox() 写死的：
#      sb.texture_margin_left/right/top/bottom = 10
#    也就是说 64x64 的面板里，**外圈 10px 是不被拉伸的框**，中间 44x44 会被平铺/拉伸。
#    所以花边、铆钉、描边都必须落在最外 10px 之内；
#    如果按"4px 边框"去画（文档里那句是早期草案），拉伸后框会糊成一团。
#  这是"文档与实现不一致时以实现为准"的一个实例 —— 已回填到 docs/10。
#
#  【条的画法】血条/蓝条是**横向拉伸**的单张图：
#    必须做到"水平方向完全均匀"，否则拉伸后会出现一条条竖纹。
#    所以上半/下半各自用竖直渐变，绝不加横向噪点。
# =============================================================================

const OUT_DIR := "res://assets/sprites"

## 与 ui_kit.gd 的 wood_stylebox() 保持一致，改一处必须改两处
const NINE_SLICE_MARGIN := 10


func _init() -> void:
	print("=== UI 素材生成 ===")
	RefArt.reset_stats()
	var dir := ProjectSettings.globalize_path(OUT_DIR)

	_gen_panel(dir)
	_gen_bar(dir)
	_gen_bar_armor(dir)
	_gen_rarity_frames(dir)

	RefArt.report("UI")
	quit(0)


# =============================================================================
#  ui_panel.png —— 64x64 九宫格
# =============================================================================

func _gen_panel(dir: String) -> void:
	var S := 64
	var m := NINE_SLICE_MARGIN
	var img := RefArt.new_img(S, S)

	# ① 内部：深色底（面板上要画文字与物品格，必须低对比、均匀）
	RefArt.fill_rect(img, m, m, S - 2 * m, S - 2 * m, "1")

	# ② 外框：雕刻木框（外圈 m 像素）
	RefArt.fill_rect(img, 0, 0, S, m, "t")
	RefArt.fill_rect(img, 0, S - m, S, m, "t")
	RefArt.fill_rect(img, 0, 0, m, S, "t")
	RefArt.fill_rect(img, S - m, 0, m, S, "t")
	# 顶面受光 / 底面背光（光源左上）
	RefArt.hline(img, 0, S - 1, 0, "B")
	RefArt.hline(img, 0, S - 1, 1, "T")
	RefArt.hline(img, 0, S - 1, S - 1, "b")
	RefArt.hline(img, 0, S - 1, S - 2, "B")
	RefArt.vline(img, 0, 0, S - 1, "B")
	RefArt.vline(img, 1, 0, S - 1, "T")
	RefArt.vline(img, S - 1, 0, S - 1, "b")
	RefArt.vline(img, S - 2, 0, S - 1, "B")
	# 最外一圈硬描边
	RefArt.hline(img, 0, S - 1, 0, "k")
	RefArt.hline(img, 0, S - 1, S - 1, "k")
	RefArt.vline(img, 0, 0, S - 1, "k")
	RefArt.vline(img, S - 1, 0, S - 1, "k")

	# ③ 木框内沿的两道石线（也落在 10px 内：8 与 9）
	RefArt.stroke_rect(img, m - 2, m - 2, S - 2 * (m - 2), S - 2 * (m - 2), "5")
	RefArt.stroke_rect(img, m - 1, m - 1, S - 2 * (m - 1), S - 2 * (m - 1), "2")

	# ④ 四角铆钉（在 10px 框内居中，且不会被拉伸）
	for p in [Vector2i(m / 2, m / 2), Vector2i(S - m / 2 - 1, m / 2),
			Vector2i(m / 2, S - m / 2 - 1), Vector2i(S - m / 2 - 1, S - m / 2 - 1)]:
		RefArt.disc(img, float(p.x), float(p.y), 3.0, "4")
		RefArt.disc(img, float(p.x), float(p.y), 2.0, "w")
		RefArt.px(img, p.x - 1, p.y - 1, "W")

	# ⑤ 木纹（只画在上下两条框上，且沿 x 方向稀疏 —— 九宫格会横向拉伸边框）
	for x in range(2, S - 2, 5):
		RefArt.px(img, x, 3, "b")
		RefArt.px(img, x + 2, S - 4, "b")

	RefArt.save(img, dir, "ui_panel.png")


# =============================================================================
#  ui_bar.png —— 64x32，上血条下蓝条
# =============================================================================

## 画一条**水平均匀**的状态条：竖直 3 段渐变 + 顶部高光 + 底部描边。
## 绝不做横向噪点 —— 它会被横向拉伸，任何横向变化都会变成竖纹。
func _draw_bar(img: Image, y0: int, h: int, top: String, mid: String, bottom: String,
		hi: String) -> void:
	var w := img.get_width()
	for x in w:
		for i in h:
			var key := mid
			if i == 0:
				key = "k"
			elif i == 1:
				key = hi
			elif i == h - 1:
				key = "k"
			elif i == h - 2:
				key = bottom
			elif i < h / 2:
				key = top
			RefArt.px(img, x, y0 + i, key)


func _gen_bar(dir: String) -> void:
	var img := RefArt.new_img(64, 32)
	# 上 16：血条
	_draw_bar(img, 0, 16, "R", "R", "r", "Y")
	# 下 16：蓝条
	_draw_bar(img, 16, 16, "c", "c", "n", "C")
	RefArt.save(img, dir, "ui_bar.png")


func _gen_bar_armor(dir: String) -> void:
	var img := RefArt.new_img(64, 16)
	# 钢灰护甲条
	_draw_bar(img, 0, 16, "7", "6", "5", "W")
	RefArt.save(img, dir, "ui_bar_armor.png")


# =============================================================================
#  ui_frame_rarity.png —— 64x16，4 格品质框
# =============================================================================

## 16x16 空心品质框：2px 边 + 透明内芯
func _frame_cell(col: String, star: bool) -> Image:
	var img := RefArt.new_img(16, 16)
	for y in 16:
		for x in 16:
			var edge := x < 2 or y < 2 or x >= 14 or y >= 14
			if edge:
				RefArt.px(img, x, y, "k" if (x == 0 or y == 0 or x == 15 or y == 15) else col)
	# 顶面提亮
	RefArt.hline(img, 1, 14, 1, "W" if star else col)
	RefArt.hline(img, 1, 14, 14, "k")
	if star:
		# 顶部中央一颗小星
		RefArt.px(img, 8, 0, "W")
		RefArt.hline(img, 7, 9, 1, "W")
		RefArt.hline(img, 6, 10, 2, "W")
		RefArt.hline(img, 7, 9, 3, "O")
	return img


func _gen_rarity_frames(dir: String) -> void:
	var sheet := RefArt.new_img(64, 16)
	RefArt.put(sheet, _frame_cell("w", false), 16, 16, 0, 0)   # 普通 灰白
	RefArt.put(sheet, _frame_cell("e", false), 16, 16, 1, 0)   # 优秀 绿
	RefArt.put(sheet, _frame_cell("c", false), 16, 16, 2, 0)   # 稀有 蓝
	RefArt.put(sheet, _frame_cell("O", true), 16, 16, 3, 0)    # 传奇 橙 + 星
	RefArt.save(sheet, dir, "ui_frame_rarity.png")
