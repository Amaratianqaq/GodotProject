class_name RefArt
extends RefCounted
## 参考素材生成器的共享绘图库（**仅供 tools/refart/* 使用，不参与游戏运行时**）。
##
## 【这个文件是什么】
## 把「画像素」的通用能力集中在这里：调色板、像素/形状绘制、ASCII 字符画、
## 双网格角点几何、图集切格、写盘与统计。
##
## 【它不管什么】
## - 不定义任何具体素材（角色/敌人/地形都各自的 gen_*.gd 里）
## - 不引用任何 autoload（这样 tools/refart/*.gd 可以被单独 headless 运行）
##
## 【框架约束】
## 1. 调色板只有 PAL 一张表，禁止在 gen_* 里出现裸 Color("#..."）。
## 2. 所有绘制都是**硬边**的：不插值、不抗锯齿、alpha 只能是 0 或 1。
## 3. 尺寸/网格必须与 docs/10_美术素材规格与双网格瓦片契约.md 一致。

# ---------------------------------------------------------------------------
#  调色板（docs/10 §1.1 的 32 色）
# ---------------------------------------------------------------------------

const PAL := {
	# 描边 / 中性
	"k": "#0d0b1f",  # 近黑描边
	"1": "#221a2e",  # 深紫灰（也是最底层背景土色）
	"2": "#3a3040",  # 中紫灰
	"3": "#5a4d63",  # 浅紫灰
	"4": "#8a7f92",  # 暖灰
	"w": "#c8c5bd",  # 灰白
	"W": "#ffffff",  # 纯白
	# 草 / 森林
	"g": "#243d1c",  # 深草绿
	"G": "#3a5c2a",  # 草绿暗
	"e": "#5c8f3a",  # 草绿
	"E": "#8fc75a",  # 亮草绿
	"L": "#c9e88a",  # 淡黄绿
	"y": "#d9c46a",  # 干草黄
	# 土 / 木 / 石
	"b": "#4a3524",  # 深棕
	"B": "#6b4a2f",  # 棕
	"t": "#a3713f",  # 木棕
	"T": "#d9a866",  # 浅木
	"5": "#7d7a75",  # 石暗
	"6": "#a8a49c",  # 石中
	"7": "#d6d2c8",  # 石亮
	# 遗迹 / 冷色
	"n": "#26303f",  # 深靛
	"N": "#3d5266",  # 靛蓝
	"c": "#5f86a6",  # 冷蓝
	"C": "#9fc4d9",  # 冰蓝
	# 危险 / 火焰 / 魔阵
	"r": "#7a2f3a",  # 暗红
	"R": "#c23a3a",  # 红
	"o": "#f2762e",  # 橙
	"O": "#ffc14d",  # 金
	"P": "#5d2a78",  # 深紫
	"p": "#b44ac9",  # 紫
	"K": "#f28fc9",  # 粉
	# 光效
	"f": "#8fe0f2",  # 冷光（契约里写作 #8fe0f2）
	"Y": "#ffe9a8",  # 暖光
	"Q": "#4fe0c0",  # 魔光青
}

## 16 个角点变体的索引值 = row*4 + col，也就是「哪些角是地形」的位掩码本身
## NW=bit3(8) NE=bit2(4) SW=bit1(2) SE=bit0(1)
## 顺序不是随便排的：它让同一个码值的格子恰好落在块内 (i%4, i/4) 的位置，
## 于是整块 4×4 呈现「双网格模板」的经典递进排列（详见 docs/10 §5.2）。
const TILE := 16
const HALF := 8

static var _cache := {}


static func col(key: String) -> Color:
	if _cache.has(key):
		return _cache[key]
	var hex: String = PAL.get(key, "#ff00ff")
	var s := hex.trim_prefix("#")
	var c := Color(1, 0, 1, 1)
	if s.length() >= 6:
		c.r = float(s.substr(0, 2).hex_to_int()) / 255.0
		c.g = float(s.substr(2, 2).hex_to_int()) / 255.0
		c.b = float(s.substr(4, 2).hex_to_int()) / 255.0
	c.a = 1.0
	_cache[key] = c
	return c


static func clear_col(key: String) -> Color:
	var c := col(key)
	c.a = 0.0
	return c


# ---------------------------------------------------------------------------
#  位运算 helper（GDScript 没有内置 bit 测试）
# ---------------------------------------------------------------------------

## sign > 0 时取 NW 位(8)，sign < 0 时取 SE 位(1)
static func bit_nw_se(pattern: int, sign: int) -> bool:
	return (pattern & (8 if sign > 0 else 1)) != 0


## sign > 0 时取 NE 位(4)，sign < 0 时取 SW 位(2)
static func bit_ne_sw(pattern: int, sign: int) -> bool:
	return (pattern & (4 if sign > 0 else 2)) != 0


static func has_bit(pattern: int, bit: int) -> bool:
	return (pattern & bit) != 0


# ---------------------------------------------------------------------------
#  画布
# ---------------------------------------------------------------------------

static func new_img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func px(img: Image, x: int, y: int, key: String) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, col(key))


static func px_c(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)


static func getp(img: Image, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


static func opaque(img: Image, x: int, y: int) -> bool:
	return getp(img, x, y).a > 0.5


static func fill_rect(img: Image, x: int, y: int, w: int, h: int, key: String) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(img, xx, yy, key)


static func rect_c(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px_c(img, xx, yy, c)


static func hline(img: Image, x0: int, x1: int, y: int, key: String) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		px(img, x, y, key)


## 空心矩形（只画一圈边框，线宽 1px）
static func stroke_rect(img: Image, x: int, y: int, w: int, h: int, key: String) -> void:
	hline(img, x, x + w - 1, y, key)
	hline(img, x, x + w - 1, y + h - 1, key)
	vline(img, x, y, y + h - 1, key)
	vline(img, x + w - 1, y, y + h - 1, key)


static func vline(img: Image, x: int, y0: int, y1: int, key: String) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		px(img, x, y, key)


static func line(img: Image, x0: int, y0: int, x1: int, y1: int, key: String) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var cx := x0
	var cy := y0
	while true:
		px(img, cx, cy, key)
		if cx == x1 and cy == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			cx += sx
		if e2 <= dx:
			err += dx
			cy += sy


## 实心圆（用距离平方判定，硬边）
static func disc(img: Image, cx: float, cy: float, r: float, key: String) -> void:
	fill_shape(img, cx, cy, r, func(x: int, y: int) -> bool: return true, key)


## 按谓词填充一个圆域；pred(local_x, local_y) 决定是否落笔
static func fill_shape(img: Image, cx: float, cy: float, r: float, pred: Callable, key: String) -> void:
	var x0 := int(floor(cx - r)) - 1
	var x1 := int(ceil(cx + r)) + 1
	var y0 := int(floor(cy - r)) - 1
	var y1 := int(ceil(cy + r)) + 1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			if dx * dx + dy * dy > r * r:
				continue
			if pred.call(x, y):
				px(img, x, y, key)


## 实心椭圆
static func ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, key: String) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (float(x) + 0.5 - cx) / maxf(rx, 0.001)
			var dy := (float(y) + 0.5 - cy) / maxf(ry, 0.001)
			if dx * dx + dy * dy <= 1.0:
				px(img, x, y, key)


## 竖直**分段**着色：把高度分成若干段，每段填一种**调色板内**的颜色。
##
## 【为什么不用 shade_v】shade_v 做的是线性插值，会生成调色板之外的颜色
## （例如 #6b4a2f 渐变到 #0d0b1f，中间会产生 28 种没人选过的紫灰）。
## 像素画里渐变本来就该是**硬分段**的，而不是连续过渡 ——
## 连续过渡放大后会出现"脏色带"，也是 verify_all_assets.gd 会拦下来的问题。
static func band_v(img: Image, x: int, y: int, w: int, h: int, keys: Array) -> void:
	if keys.is_empty() or h <= 0:
		return
	for i in h:
		var seg := int(float(i) / float(h) * float(keys.size()))
		seg = clampi(seg, 0, keys.size() - 1)
		var key := String(keys[seg])
		for xx in range(x, x + w):
			if opaque(img, xx, y + i):
				px(img, xx, y + i, key)


## 竖直渐变填充（仅对已不透明的像素着色）。
## ⚠️ 会产生调色板外的插值色 —— 只用于**不要求配色合规**的临时图。
## 正式素材请用 band_v()。
static func shade_v(img: Image, x: int, y: int, w: int, h: int, top: String, bottom: String) -> void:
	for yy in range(y, y + h):
		var t := float(yy - y) / maxf(float(h - 1), 1.0)
		var c := col(top).lerp(col(bottom), t)
		c.a = 1.0
		for xx in range(x, x + w):
			if opaque(img, xx, yy):
				px_c(img, xx, yy, c)


## 水平渐变
static func shade_h(img: Image, x: int, y: int, w: int, h: int, left: String, right: String) -> void:
	for xx in range(x, x + w):
		var t := float(xx - x) / maxf(float(w - 1), 1.0)
		var c := col(left).lerp(col(right), t)
		c.a = 1.0
		for yy in range(y, y + h):
			if opaque(img, xx, yy):
				px_c(img, xx, yy, c)


# ---------------------------------------------------------------------------
#  ASCII 字符画
# ---------------------------------------------------------------------------

## 贴字符画：'.' 与空格 = 透明；remap 可整块换色
static func blit(img: Image, rows: PackedStringArray, ox: int, oy: int, remap := {}) -> void:
	for yy in rows.size():
		var s: String = rows[yy]
		for xx in s.length():
			var ch := s[xx]
			if ch == "." or ch == " ":
				continue
			if remap.has(ch):
				ch = String(remap[ch])
			px(img, ox + xx, oy + yy, ch)


## 只替换指定行里的字符（宽度不变，适合换朝向/换色）
static func recolor(rows: PackedStringArray, indices: Array, map: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(rows)
	for i in indices:
		var idx := int(i)
		if idx < 0 or idx >= out.size():
			continue
		var s: String = out[idx]
		var res := ""
		for c in s.length():
			res += String(map.get(s[c], s[c]))
		out[idx] = res
	return out


## 水平翻转字符画
static func flip_h(rows: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		out.append(_reverse(r))
	return out


static func _reverse(s: String) -> String:
	var res := ""
	for i in range(s.length() - 1, -1, -1):
		res += s[i]
	return res


# ---------------------------------------------------------------------------
#  描边 / 修边
# ---------------------------------------------------------------------------

## 给所有不透明像素的外缘加一圈描边色（只在透明处落笔，不会变胖）
static func outline(img: Image, x: int, y: int, w: int, h: int, key := "k") -> void:
	var adds: Array[Vector2i] = []
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if opaque(img, xx, yy):
				continue
			var touch := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if opaque(img, xx + d.x, yy + d.y):
					touch = true
					break
			if touch:
				adds.append(Vector2i(xx, yy))
	for p in adds:
		px(img, p.x, p.y, key)


## 把内容整体平移（在单格内用）。**越界即丢弃**（不报错）——
## 否则贴底对齐时很容易在 Image.set_pixel 上触发 "Index out of bounds"。
static func shift_cell(cell: Image, dx: int, dy: int) -> Image:
	var w := cell.get_width()
	var h := cell.get_height()
	var out := new_img(w, h)
	for y in h:
		for x in w:
			var c := cell.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			out.set_pixel(nx, ny, c)
	return out


# ---------------------------------------------------------------------------
#  图集切格
# ---------------------------------------------------------------------------

## 把 cell 放进 sheet 的 (col,row) 格
static func put(sheet: Image, cell: Image, cw: int, ch: int, col_i: int, row_i: int) -> void:
	blit_img(sheet, cell, col_i * cw, row_i * ch)


## 把 cell 放到以 (origin.x, origin.y) 格为左上角的 4×4 块内第 index 格
static func put_in_block(sheet: Image, cell: Image, cw: int, ch: int, origin: Vector2i, index: int) -> void:
	put(sheet, cell, cw, ch, origin.x + index % 4, origin.y + index / 4)


static func blit_img(sheet: Image, cell: Image, ox: int, oy: int) -> void:
	for y in cell.get_height():
		for x in cell.get_width():
			var c := cell.get_pixel(x, y)
			if c.a > 0.5:
				sheet.set_pixel(ox + x, oy + y, c)


static func put_at(sheet: Image, cell: Image, cell_w: int, cell_h: int, col_i: int, row_i: int) -> void:
	put(sheet, cell, cell_w, cell_h, col_i, row_i)


# ---------------------------------------------------------------------------
#  写盘与统计
# ---------------------------------------------------------------------------

static var saved: Array = []


static func save(img: Image, dir_abs: String, fname: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var path := dir_abs + "/" + fname
	var err := img.save_png(path)
	if err != OK:
		push_error("[RefArt] 写盘失败 %s (err=%d)" % [path, err])
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	saved.append({"name": fname, "w": img.get_width(), "h": img.get_height(), "bytes": bytes.size()})
	print("  ✓ %-32s %3dx%-3d %7d bytes" % [fname, img.get_width(), img.get_height(), bytes.size()])


static func reset_stats() -> void:
	saved.clear()


static func report(title: String) -> void:
	print("")
	print("===== %s：共 %d 个文件 =====" % [title, saved.size()])
	var total := 0
	for r in saved:
		total += int(r["bytes"])
	print("合计 %d bytes" % total)


# ---------------------------------------------------------------------------
#  自检：打印 ASCII 概览（没有图像查看器时的唯一验证手段）
# ---------------------------------------------------------------------------

static func dump_cell(img: Image, cw: int, ch: int, col_i: int, row_i: int, title := "") -> void:
	var ox := col_i * cw
	var oy := row_i * ch
	if title != "":
		print("--- %s ---" % title)
	for y in range(oy, oy + ch):
		var s := ""
		for x in range(ox, ox + cw):
			s += _char_for(getp(img, x, y))
		print(s)


static func dump_grid(img: Image, cw: int, ch: int, cols: int, rows: int, title := "") -> void:
	if title != "":
		print("--- %s ---" % title)
	for ry in rows:
		for y in range(ry * ch, (ry + 1) * ch):
			var s := ""
			for rx in cols:
				for x in range(rx * cw, (rx + 1) * cw):
					s += _char_for(getp(img, x, y))
				s += "|"
			print(s)
		print("".lpad(cols * (cw + 1), "-"))


static func _char_for(c: Color) -> String:
	if c.a < 0.5:
		return "."
	# 找到调色板里最接近的字符
	var best := "?"
	var best_d := 999.0
	for k in PAL.keys():
		var pc := col(k)
		var d := absf(pc.r - c.r) + absf(pc.g - c.g) + absf(pc.b - c.b)
		if d < best_d:
			best_d = d
			best = k
	return best
