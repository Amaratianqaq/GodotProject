extends SceneTree
# =============================================================================
#  gen_pixel_assets.gd —— 代码驱动的像素美术生成器（Godot 4.x / headless）
# -----------------------------------------------------------------------------
#  运行方式：
#    & "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" `
#        --headless --path E:\GodotProject --script res://tools/gen_pixel_assets.gd
#
#  输出目录：res://assets/sprites/（14 张 PNG，按格子排列，供 AtlasTexture 切图）
#
#  设计思路（给后来的人类开发者）：
#    每一张精灵都由「ASCII 字符画（PackedStringArray）+ 调色板 P」定义。
#    字符画里每个字符 = 1 个像素，"." 和空格 = 透明。
#    想改美术，直接改下面的字符画即可，不需要任何美术软件。
#    纯几何的部分（噪点、渐变、圆、边框、进度条）用 helper 完成，因为用字符画写太啰嗦。
#
#  自检开关：
#    DUMP_ASCII = true 时，会把每张成品「回读」成字符画写到 user://ascii_*.txt，
#    便于在没有图像查看器的环境里确认每格不是空白或糊成一团。默认关闭。
# =============================================================================

const OUT_DIR := "res://assets/sprites"       # 输出目录
const RNG_SEED := 20240601                     # 固定随机种子，保证每次生成结果一致
const PREVIEW_SCALE := 0                       # >0 时额外输出放大预览到 user://preview/（调试用）
const DUMP_ASCII := false                      # 输出字符画自检文件到 user://ascii_*.txt（调试用，默认关闭）

var rng := RandomNumberGenerator.new()
var _col_cache := {}
var _failed := false
var _results: Array = []                       # [{name, w, h, bytes}]

# -----------------------------------------------------------------------------
#  调色板：键 = 单字符，值 = "#rrggbb" 或 "#rrggbbaa"
#  整体色调统一由这张表保证，不要随手加新颜色。
# -----------------------------------------------------------------------------
var P := {
	".": "#00000000",   # 透明
	"k": "#0d0b1f",     # 近黑描边
	"1": "#2b2138",     # 暗紫阴影
	"2": "#4a3b52",     # 中阴影
	"3": "#7a6a7d",     # 浅阴影 / 石
	"w": "#c8c5bd",     # 灰白
	"W": "#ffffff",     # 纯白
	"g": "#3a5c2a",     # 深绿
	"G": "#5c8f3a",     # 草绿
	"l": "#8fc75a",     # 亮绿
	"L": "#c9e88a",     # 淡绿
	"b": "#6b4a2f",     # 深棕
	"B": "#a3713f",     # 棕
	"t": "#d9a866",     # 浅棕 / 木
	"r": "#7a2f3a",     # 暗红
	"R": "#d94a4a",     # 红
	"o": "#f2a13b",     # 橙
	"y": "#ffd35c",     # 黄
	"n": "#2f5a8f",     # 深蓝
	"N": "#4a8fd9",     # 蓝
	"c": "#8fd3f2",     # 亮蓝
	"p": "#b44ac9",     # 紫
	"P": "#f28fc9",     # 樱花粉
	"m": "#8c5a3a",     # 木色
}

# =============================================================================
#  0. 入口
# =============================================================================

func _init() -> void:
	print("=== 像素资源生成开始 (seed=%d) ===" % RNG_SEED)
	var dir_abs := ProjectSettings.globalize_path(OUT_DIR)
	var mk := DirAccess.make_dir_recursive_absolute(dir_abs)
	if mk != OK:
		_fail("无法创建输出目录 %s (err=%d)" % [dir_abs, mk])
		_report()
		quit(1)
		return
	# --- 依次生成 14 张图 ---
	_gen_player()
	_gen_slime()
	_gen_bat()
	_gen_mushroom()
	_gen_goblin()
	_gen_goblin_archer()
	_gen_goblin_guard()
	_gen_boss_priest()
	_gen_props()
	_gen_weapons()
	_gen_cherry_shotgun()
	_gen_tileset()
	_gen_ui_panel()
	_gen_ui_bar()
	_report()
	quit(1 if _failed else 0)


# 失败处理：只报一次，最后 quit(1)
func _fail(msg: String) -> void:
	if not _failed:
		_failed = true
		push_error("[gen_pixel_assets] " + msg)


func _report() -> void:
	print("")
	print("===== 生成报告：res://assets/sprites/ =====")
	var total := 0
	for r in _results:
		print("%-28s %3dx%-3d %7d bytes" % [r["name"], r["w"], r["h"], r["bytes"]])
		total += int(r["bytes"])
	print("-------------------------------------------")
	print("共 %d 个文件，合计 %d bytes" % [_results.size(), total])
	if _failed:
		print("!! 生成过程中出现错误，见上方 push_error !!")


# =============================================================================
#  1. 基础工具
# =============================================================================

# 解析 "#rrggbb" / "#rrggbbaa"
func _col(hex: String) -> Color:
	if _col_cache.has(hex):
		return _col_cache[hex]
	var s := hex.trim_prefix("#")
	var c := Color(1, 1, 1, 1)
	if s.length() >= 6:
		c.r = float(s.substr(0, 2).hex_to_int()) / 255.0
		c.g = float(s.substr(2, 2).hex_to_int()) / 255.0
		c.b = float(s.substr(4, 2).hex_to_int()) / 255.0
	if s.length() >= 8:
		c.a = float(s.substr(6, 2).hex_to_int()) / 255.0
	_col_cache[hex] = c
	return c


func _new_img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _save(img: Image, fname: String) -> void:
	if _failed:
		return
	var abs_path := ProjectSettings.globalize_path(OUT_DIR + "/" + fname)
	var err := img.save_png(abs_path)
	if err != OK:
		_fail("写盘失败 %s (err=%d)" % [abs_path, err])
		return
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	_results.append({"name": fname, "w": img.get_width(), "h": img.get_height(), "bytes": bytes.size()})
	if PREVIEW_SCALE > 0:
		var pv := _new_img(img.get_width(), img.get_height())
		pv.copy_from(img)
		pv.resize(img.get_width() * PREVIEW_SCALE, img.get_height() * PREVIEW_SCALE, Image.INTERPOLATE_NEAREST)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://preview"))
		pv.save_png(ProjectSettings.globalize_path("user://preview/" + fname))


# =============================================================================
#  2. 绘图 helper（全部越界安全）
# =============================================================================

func px(img: Image, x: int, y: int, key: String) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if not P.has(key):
		_fail("调色板缺少字符 '%s'" % key)
		return
	img.set_pixel(x, y, _col(P[key]))


func px_set(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)


func getpx(img: Image, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


# 把 ASCII 字符画贴到图上：. 和空格 = 透明；remap 可整块换色（受击闪白 / 品质换色等）
func blit_ascii(img: Image, rows: PackedStringArray, ox: int, oy: int, remap := {}) -> void:
	for yy in rows.size():
		var s: String = rows[yy]
		for xx in s.length():
			var ch := s[xx]
			if ch == "." or ch == " ":
				continue
			if remap.has(ch):
				ch = remap[ch]
			px(img, ox + xx, oy + yy, ch)


# 复制一份字符画并替换其中若干行（键 = 行号）
func _patch(rows: PackedStringArray, changes: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(rows)
	for k in changes.keys():
		var i := int(k)
		while out.size() <= i:
			out.append("")
		out[i] = String(changes[k])
	return out


# 只把指定行里的某些字符换成别的字符（宽度完全不变，适合做同一角色的换色/换朝向）
func _recolor_rows(rows: PackedStringArray, indices, map: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(rows)
	for i in indices:
		if i < 0 or i >= out.size():
			continue
		var s: String = out[i]
		var res := ""
		for c in s.length():
			var ch := s[c]
			res += String(map.get(ch, ch))
		out[i] = res
	return out


func fill_rect(img: Image, x: int, y: int, w: int, h: int, key: String) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(img, xx, yy, key)


func stroke_rect(img: Image, x: int, y: int, w: int, h: int, key: String) -> void:
	for xx in range(x, x + w):
		px(img, xx, y, key)
		px(img, xx, y + h - 1, key)
	for yy in range(y, y + h):
		px(img, x, yy, key)
		px(img, x + w - 1, yy, key)


func hline(img: Image, x0: int, x1: int, y: int, key: String) -> void:
	var a := mini(x0, x1)
	var b := maxi(x0, x1)
	for x in range(a, b + 1):
		px(img, x, y, key)


func vline(img: Image, x: int, y0: int, y1: int, key: String) -> void:
	var a := mini(y0, y1)
	var b := maxi(y0, y1)
	for y in range(a, b + 1):
		px(img, x, y, key)


# Bresenham 直线
func line(img: Image, x0: int, y0: int, x1: int, y1: int, key: String) -> void:
	var cx := x0
	var cy := y0
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
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


func fill_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, key: String) -> void:
	if rx <= 0 or ry <= 0:
		return
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var nx := float(x - cx) / float(rx)
			var ny := float(y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				px(img, x, y, key)


# 直接给颜色的椭圆填充（做半透明光晕）
func fill_ellipse_col(img: Image, cx: int, cy: int, rx: int, ry: int, col: Color) -> void:
	if rx <= 0 or ry <= 0:
		return
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var nx := float(x - cx) / float(rx)
			var ny := float(y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				px_set(img, x, y, col)


func stroke_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, key: String) -> void:
	if rx <= 0 or ry <= 0:
		return
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var nx := float(x - cx) / float(rx)
			var ny := float(y - cy) / float(ry)
			var d := nx * nx + ny * ny
			if d <= 1.0 and d >= 0.62:
				px(img, x, y, key)


# 竖直渐变填充（顶色 -> 底色）；only_opaque=true 时只染已经画过的像素（药水、水面等）
func shade_vertical(img: Image, x: int, y: int, w: int, h: int, top_key: String, bottom_key: String, only_opaque := false) -> void:
	if h <= 0:
		return
	var c0 := _col(P[top_key])
	var c1 := _col(P[bottom_key])
	for i in h:
		var t := 0.0 if h <= 1 else float(i) / float(h - 1)
		var col := c0.lerp(c1, t)
		for xx in range(x, x + w):
			if only_opaque:
				var cur := getpx(img, xx, y + i)
				if cur.a <= 0.0:
					continue
				col.a = cur.a
			px_set(img, xx, y + i, col)


# 水平渐变填充（左 -> 右）
func shade_horizontal(img: Image, x: int, y: int, w: int, h: int, left_key: String, right_key: String) -> void:
	if w <= 0:
		return
	var c0 := _col(P[left_key])
	var c1 := _col(P[right_key])
	for xx in range(x, x + w):
		var t := 0.0 if w <= 1 else float(xx - x) / float(w - 1)
		var col := c0.lerp(c1, t)
		for yy in range(y, y + h):
			px_set(img, xx, yy, col)


# 按数量撒噪点（用 rng，可复现）
func noise_scatter(img: Image, x: int, y: int, w: int, h: int, key: String, count: int) -> void:
	for i in count:
		var nx := x + rng.randi_range(0, maxi(0, w - 1))
		var ny := y + rng.randi_range(0, maxi(0, h - 1))
		px(img, nx, ny, key)


# 给所有不透明像素的外边缘描一圈近黑轮廓（像素画立体感的关键）
# 轮廓向「外」长 1px，所以字符画四周要留至少 1px 透明边距。
func outline_dark(img: Image, key := "k") -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := _new_img(w, h)
	src.copy_from(img)
	var c := _col(P[key])
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in dirs:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if src.get_pixel(nx, ny).a > 0.0:
					img.set_pixel(x, y, c)
					break


# 受击闪白：不透明像素整体推白，近黑轮廓变灰白，保持造型可读
func flash_white(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var lum := (c.r + c.g + c.b) / 3.0
			if lum < 0.16:
				img.set_pixel(x, y, Color(0.78, 0.78, 0.86, c.a))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, c.a))


# 设置区域整体透明度（史莱姆果冻感 / 影子）
func set_alpha_area(img: Image, x: int, y: int, w: int, h: int, a: float) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var c := getpx(img, xx, yy)
			if c.a <= 0.0:
				continue
			c.a = a
			px_set(img, xx, yy, c)


# 把 src 里不透明的像素叠到 dst 上（支持整体透明度倍率），不会擦掉 dst 已有的内容
func blit_over(dst: Image, src: Image, ox: int, oy: int, alpha_mul := 1.0) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			c.a *= alpha_mul
			px_set(dst, ox + x, oy + y, c)


# 把一张小图放进大图的格子里（格子坐标 = col/row，格子尺寸 cw/ch，dy 可整体上下微调）
func place(sheet: Image, cell: Image, col: int, row: int, cw: int, ch: int, dy := 0) -> void:
	sheet.blit_rect(cell, Rect2i(0, 0, cw, ch), Vector2i(col * cw, row * ch + dy))


# =============================================================================
#  3. 自检：把成品「回读」成字符画（DUMP_ASCII=true 时写到 user://ascii_*.txt）
# =============================================================================

func _char_for(c: Color) -> String:
	if c.a <= 0.05:
		return "."
	for key in P.keys():
		if key == ".":
			continue
		var pc := _col(P[key])
		if absf(pc.r - c.r) < 0.02 and absf(pc.g - c.g) < 0.02 and absf(pc.b - c.b) < 0.02:
			return key
	return "?"


func _dump_sheet(img: Image, cw: int, ch: int, title: String, names: Array) -> void:
	if not DUMP_ASCII:
		return
	var cols := img.get_width() / cw
	var rows := img.get_height() / ch
	var lines: PackedStringArray = []
	lines.append("<<< %s  %dx%d  cell=%dx%d >>>" % [title, img.get_width(), img.get_height(), cw, ch])
	# 汇总表：每格的不透明像素数 + 包围盒 —— 一眼看出哪一格是空的或糊成一团
	lines.append("--- 汇总：格坐标 / 名称 / 不透明像素数 / 包围盒 ---")
	for r in rows:
		for c in cols:
			var idx0 := r * cols + c
			var nm0: String = names[idx0] if idx0 < names.size() else ""
			var cnt := 0
			var solid := 0
			var bx0 := 999
			var by0 := 999
			var bx1 := -1
			var by1 := -1
			for y in ch:
				for x in cw:
					var a := img.get_pixel(c * cw + x, r * ch + y).a
					if a > 0.05:
						cnt += 1
						bx0 = mini(bx0, x)
						by0 = mini(by0, y)
						bx1 = maxi(bx1, x)
						by1 = maxi(by1, y)
					if a >= 0.95:
						solid += 1
			lines.append("  [%d,%d] %-16s px=%-4d solid=%-4d bbox=(%d,%d)-(%d,%d)" % [c, r, nm0, cnt, solid, bx0, by0, bx1, by1])
	for r in rows:
		for c in cols:
			var idx := r * cols + c
			var nm: String = names[idx] if idx < names.size() else ""
			lines.append("--- [%d,%d] %s ---" % [c, r, nm])
			for y in ch:
				var s := ""
				for x in cw:
					s += _char_for(img.get_pixel(c * cw + x, r * ch + y))
				lines.append(s)
	var abs_path := ProjectSettings.globalize_path("user://ascii_" + title + ".txt")
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		_fail("无法写自检文件 " + abs_path)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("[自检] " + abs_path)


# =============================================================================
#  4. 通用「角色格子」装配器
#     layers = [[字符画, ox, oy], ...] 或 [[字符画, ox, oy, 换色字典], ...]
#     先按顺序贴图层，最后自动描一圈近黑轮廓。
# =============================================================================

func _framed_cell(cw: int, ch: int, layers: Array) -> Image:
	var img := _new_img(cw, ch)
	for l in layers:
		var rows: PackedStringArray = l[0]
		var ox: int = l[1]
		var oy: int = l[2]
		var remap: Dictionary = l[3] if l.size() > 3 else {}
		blit_ascii(img, rows, ox, oy, remap)
	outline_dark(img)
	return img


# =============================================================================
#  5. player_ranger.png —— 游侠（绿斗篷 + 皮甲 + 手枪/短弓，兜帽 + 发光眼睛）
#     128x128，4 列 x 4 行，每格 32x32
# =============================================================================

# 正面（朝下）身体：只画到第 24 行，第 25 行以下交给腿的字符画。
# 头是 Q 版大头（13 行高），左上受光用 l/L，右侧背光用 g。
var BODY_DOWN := PackedStringArray([
	"",                             # 0  顶部留白
	"",                             # 1
	"",                             # 2
	"",                             # 3
	".............kkkkkk",          # 4  兜帽顶
	"...........kllllGGGGk",        # 5
	"..........klllGGGGGggk",       # 6
	"..........kllGGGGGGggk",       # 7
	"..........klGGGGGGGggk",       # 8
	"..........kgGGGGGGGGgk",       # 9
	"..........kg11111111gk",       # 10 兜帽里的暗部（脸洞）
	"..........kg11111111gk",       # 11
	"..........kg1yy11yy1gk",       # 12 发光的眼睛
	"..........kg1yy11yy1gk",       # 13
	"..........kg11222211gk",       # 14 下巴阴影
	"..........kg11111111gk",       # 15
	"..........kggGGGGGGggk",       # 16 兜帽下缘
	".........kggGGGGGGGGggk",      # 17 肩
	".........klGGGGGGGGGggk",      # 18 斗篷 + 皮甲
	".........klGbBBBBBBbGgk",      # 19
	".........klGbBBttBBbGgk",      # 20 胸甲高光
	".........klGbBByyBBbGgk",      # 21 腰带黄铜扣
	".........klGbBBBBBBbGgk",      # 22
	".........kgGbBBBBBBbGgk",      # 23
	".........kggggggggggggk",      # 24 斗篷下摆
])

# 正面腿：待机 / 迈步 A（右腿抬起）/ 迈步 B（左腿抬起），都从第 25 行开始
# 左右对称于格子中线（第 15.5 列）：每条腿 5px 宽（3px 颜色 + 两侧描边），
# 两腿之间留 2px 缝隙，避免描边糊成一团。
var LEGS_IDLE := PackedStringArray([
	"...........kbbbbbbbbk",        # 25 髋
	"..........kBbbk..kBbbk",       # 26 皮裤
	"..........kBbbk..kBbbk",       # 27
	".........kbBBbk..kbBBbk",      # 28 靴子
	".........111111..111111",      # 29 鞋底（脚底对齐格子底边，下面留 2px）
])

var LEGS_WALK_A := PackedStringArray([
	"...........kbbbbbbbbk",        # 25
	"..........kBbbk..kbbbk",       # 26 左腿落地，右腿抬起
	"..........kBbbk..kbBBbk",      # 27 抬起的右腿露出靴子
	".........kbBBbk",              # 28 左腿靴子
	".........111111",              # 29
])

var LEGS_WALK_B := PackedStringArray([
	"...........kbbbbbbbbk",        # 25
	"..........kbbbk..kBbbk",       # 26 左腿抬起，右腿落地
	".........kbBBbk..kBbbk",       # 27 抬起的左腿露出靴子
	".................kbBBbk",      # 28 右腿靴子
	".................111111",      # 29
])

# 侧面（朝右）身体：兜帽侧影，脸洞开在右侧，只有一只发光眼睛
var BODY_SIDE := PackedStringArray([
	"",                             # 0
	"",                             # 1
	"",                             # 2
	"",                             # 3
	"............kkkkkkkk",         # 4  兜帽顶
	"...........kllllGGGgk",        # 5
	"..........klllGGGGGggk",       # 6
	"..........kllGGGGGGggk",       # 7
	"..........klGGGGGGGggk",       # 8
	"..........klGGG11111gk",       # 9  脸洞（朝右）
	"..........klGGg111111k",       # 10
	"..........klGGg111111k",       # 11
	"..........klGGg11yy11k",       # 12 单只发光眼睛
	"..........klGGg11yy11k",       # 13
	"..........klGGg112211k",       # 14
	"..........klGGg111111k",       # 15
	"..........kggGGGGGGggk",       # 16
	".........kggGGGGGGGGggk",      # 17 肩
	".........klGGGGGGGGGggk",      # 18
	".........klGGbBBBBbGGgk",      # 19
	".........klGGbBBttbGGgk",      # 20 腰带
	".........klGGbBBBBbGGgk",      # 21
	".........klGGbBBBBbGGgk",      # 22
	".........kgGGbBBBBbGGgk",      # 23
	".........kggggggggggggk",      # 24 下摆
])

# 侧面腿：待机 / 迈步 A（前腿伸出）/ 迈步 B（另一条腿前迈）
var SLEGS_IDLE := PackedStringArray([
	"...........kbbbbbbk",          # 25
	"............kbBBbk",           # 26
	"............kbbbbk",           # 27
	"...........kbBBbbk",           # 28
	"...........1111111",           # 29
])

var SLEGS_A := PackedStringArray([
	"...........kbbbbbbk",          # 25
	"..........kbbk.kBBk",          # 26 后腿 / 前腿
	"..........kbbk.kBBk",          # 27
	".........kbbbk.kbbk",          # 28
	".........11111.1111",          # 29
])

var SLEGS_B := PackedStringArray([
	"...........kbbbbbbk",          # 25
	"..........kBBk.kbbk",          # 26
	"..........kBBk.kbbk",          # 27
	".........kbbk.kbbbk",          # 28
	".........1111.11111",          # 29
])

# 侧面的手臂 + 手枪（射击姿态用）
var ARM_IDLE := PackedStringArray([
	"kBBbk",                        # 垂下的手臂
	"kttbk",
	"kbbbk",
])

var ARM_SHOOT := PackedStringArray([
	"kBBBBBBk",                     # 前伸的手臂
	"kttttttk",
])

var PISTOL := PackedStringArray([
	"kkkkkk",                       # 套筒
	"kttttk",                       # 枪管高光
	"kbbbk.",                       # 握把
	"kbbk..",
	".kk...",
])

var MUZZLE_FLASH := PackedStringArray([
	".oyo.",
	"oyWyo",
	".oyo.",
])

# 翻滚时露出来的靴子尖
var ROLL_BOOT := PackedStringArray([
	"..kkk..",
	".kbbbk.",
	"..k1k..",
])

# 死亡：躺倒在地
var DEATH := PackedStringArray([
	"........kkkkkkkk",             # 兜帽
	".......kllGGGGGgk",
	".......kg111111gk",            # 闭着的眼睛
	"......kkggGGGGggkk",           # 肩
	"....kkGGbBBBBBBbGGkk",         # 躯干横躺
	"...kbbkkbbbbbbbbkkbbk",        # 手臂摊开
	"..k111k..kbBBk..k111k",        # 手脚
	"..kkkk....kkkk...kkkk",        # 轮廓收尾
])


func _gen_player() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var S := 32
	var sheet := _new_img(S * 4, S * 4)

	# 背面（朝上）：把正面脸洞里的暗色/眼睛整体换成兜帽背面绿色 —— 宽度不变，安全
	var body_up := _recolor_rows(BODY_DOWN, range(10, 16), {"1": "G", "2": "G", "y": "G"})
	var up_hl := PackedStringArray(["ll", "ll"])            # 后脑高光
	var quiver := PackedStringArray([                        # 背在身后的箭袋
		"t..t",
		".b.b",
		".b.b",
		"kbbbk",
		"kBBbk",
		"kbbbk",
	])

	# ---------- 第 0 行：朝下 待机 / 走A / 走B / 翻滚 ----------
	# 最后那个 -1：整格上移 1px，让脚底的描边落在第 29 行，格子底部留出真正的 2px 透明边距
	place(sheet, _framed_cell(S, S, [[BODY_DOWN, 0, 0], [LEGS_IDLE, 0, 25]]), 0, 0, S, S, -1)
	place(sheet, _framed_cell(S, S, [[BODY_DOWN, 0, 0], [LEGS_WALK_A, 0, 25]]), 1, 0, S, S, -1)
	place(sheet, _framed_cell(S, S, [[BODY_DOWN, 0, 0], [LEGS_WALK_B, 0, 25]]), 2, 0, S, S, -1)
	place(sheet, _roll_cell(S, "G", "g", "l"), 3, 0, S, S, -1)

	# ---------- 第 1 行：朝上 待机 / 走A / 走B / 翻滚 ----------
	place(sheet, _framed_cell(S, S, [[body_up, 0, 0], [up_hl, 12, 11], [quiver, 9, 13], [LEGS_IDLE, 0, 25]]), 0, 1, S, S, -1)
	place(sheet, _framed_cell(S, S, [[body_up, 0, 0], [up_hl, 12, 11], [quiver, 9, 13], [LEGS_WALK_A, 0, 25]]), 1, 1, S, S, -1)
	place(sheet, _framed_cell(S, S, [[body_up, 0, 0], [up_hl, 12, 11], [quiver, 9, 13], [LEGS_WALK_B, 0, 25]]), 2, 1, S, S, -1)
	place(sheet, _roll_cell(S, "g", "g", "G"), 3, 1, S, S, -1)

	# ---------- 第 2 行：朝右 待机 / 走A / 走B / 翻滚（朝左由代码水平翻转）----------
	place(sheet, _framed_cell(S, S, [[BODY_SIDE, 0, 0], [ARM_IDLE, 16, 18], [SLEGS_IDLE, 0, 25]]), 0, 2, S, S, -1)
	place(sheet, _framed_cell(S, S, [[BODY_SIDE, 0, 0], [ARM_IDLE, 16, 18], [SLEGS_A, 0, 25]]), 1, 2, S, S, -1)
	place(sheet, _framed_cell(S, S, [[BODY_SIDE, 0, 0], [ARM_IDLE, 16, 18], [SLEGS_B, 0, 25]]), 2, 2, S, S, -1)
	place(sheet, _roll_cell(S, "G", "g", "l"), 3, 2, S, S, -1)

	# ---------- 第 3 行：受击闪白 / 射击 / 死亡 / 冲刺 ----------
	# 受击：直接用朝下待机的格子整体推白
	var hit := _framed_cell(S, S, [[BODY_DOWN, 0, 0], [LEGS_IDLE, 0, 25]])
	flash_white(hit)
	place(sheet, hit, 0, 3, S, S, -1)

	# 射击：侧身、手臂前伸、手枪 + 枪口火焰（枪口在枪管最右端）
	var shoot := _framed_cell(S, S, [
		[BODY_SIDE, 0, 0], [ARM_SHOOT, 18, 19], [PISTOL, 25, 18], [SLEGS_IDLE, 0, 25],
	])
	blit_ascii(shoot, MUZZLE_FLASH, 30, 18)
	place(sheet, shoot, 1, 3, S, S, -1)

	# 死亡：躺倒
	place(sheet, _framed_cell(S, S, [[DEATH, 5, 21]]), 2, 3, S, S, -1)

	# 冲刺：躯干画两份做出「拉长」感 + 速度线
	var dash := _new_img(S, S)
	var torso: PackedStringArray = BODY_SIDE.slice(17, 25)
	blit_ascii(dash, BODY_SIDE, 0, -2)      # 整体上移 2px
	blit_ascii(dash, torso, 0, 17)          # 躯干再补一份，填满拉长后的腰部
	blit_ascii(dash, SLEGS_A, 0, 25)
	outline_dark(dash)
	# 速度线画在描边之后，避免被描边包住
	for i in 4:
		var yy := 14 + i * 4
		px_set(dash, 1 + i % 2, yy, Color(1, 1, 1, 0.45))
		px_set(dash, 3 - i % 2, yy, Color(1, 1, 1, 0.30))
		px_set(dash, 6 - i % 2, yy + 1, Color(1, 1, 1, 0.22))
	place(sheet, dash, 3, 3, S, S, -1)

	_save(sheet, "player_ranger.png")
	_dump_sheet(sheet, 32, 32, "player_ranger", [
		"下-待机", "下-走A", "下-走B", "下-翻滚",
		"上-待机", "上-走A", "上-走B", "上-翻滚",
		"右-待机", "右-走A", "右-走B", "右-翻滚",
		"受击闪白", "射击", "死亡", "冲刺",
	])


# 翻滚格子：蜷成一团的球 + 左侧残影
func _roll_cell(S: int, body_key: String, shade_key: String, hl_key: String) -> Image:
	var ball := _new_img(S, S)
	# 1) 球形身体（蜷缩），球底压在第 29 行（和站立的脚底齐平）
	fill_ellipse(ball, 16, 22, 8, 7, body_key)
	# 2) 下半部压暗，做出体积
	for y in range(22, 30):
		for x in range(7, 26):
			if ball.get_pixel(clampi(x, 0, S - 1), clampi(y, 0, S - 1)) == _col(P[body_key]):
				px(ball, x, y, shade_key)
	# 3) 左上高光
	fill_ellipse(ball, 12, 18, 3, 3, hl_key)
	# 4) 斗篷褶皱
	blit_ascii(ball, PackedStringArray(["..kkk..", ".k...k.", "k.....k"]), 12, 24)
	# 5) 露出来的靴子
	blit_ascii(ball, ROLL_BOOT, 19, 20)
	# 6) 缩在球里的头（露出一截兜帽）
	blit_ascii(ball, PackedStringArray(["kkkkkk", "kllGGk", "kg11gk", "kg11gk", "kggggk"]), 13, 12)
	outline_dark(ball)

	# 残影：向左平移 6px 的淡影
	var cell := _new_img(S, S)
	blit_over(cell, ball, -6, 0, 0.35)
	blit_over(cell, ball, 0, 0, 1.0)
	return cell


# =============================================================================
#  6. 敌人：史莱姆 / 蝙蝠 / 蘑菇（都是 96x32，3 格 32x32）
# =============================================================================

# 把字符画左右翻转（做左右翅膀、镜像部件用）
func _flip_rows(rows: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		var s: String = r
		var res := ""
		for i in range(s.length() - 1, -1, -1):
			res += s[i]
		out.append(res)
	return out


# --- 绿色半透明果冻史莱姆：身体用椭圆（圆润的果冻），五官/高光用字符画 ---
#     top = 顶部行号，底部永远压在第 29 行并被地面「切平」，形成圆顶造型
func _slime_cell(rx: int, top: int) -> Image:
	var c := _new_img(32, 32)
	var cy := 28                                          # 底部贴地
	var ry := cy - top
	for y in range(cy - ry, 30):
		var dy := float(y - cy) / float(ry)
		var w := rx
		if dy < 0.0:
			w = int(round(float(rx) * sqrt(max(0.0, 1.0 - dy * dy))))
		if w > 0:
			hline(c, 16 - w, 16 + w, y, "G")
	# 左上高光（果冻的通透感）
	var hx := 16 - int(rx / 2)
	var hy := top + int(ry / 2)
	fill_ellipse(c, hx, hy, maxi(2, int(rx / 3)), maxi(1, int(ry / 5)), "L")
	px(c, hx - 1, hy - 1, "W")
	px(c, hx, hy - 1, "W")
	# 底部压暗
	for y in range(cy - int(ry / 3), 30):
		for x in range(3, 30):
			if getpx(c, x, y) == _col(P["G"]):
				px(c, x, y, "g")
	# 眼睛（黑点 + 白高光）+ 小嘴
	var ey := top + int(ry * 0.62)
	fill_rect(c, 16 - int(rx / 2) - 1, ey, 2, 3, "1")
	fill_rect(c, 16 + int(rx / 2) - 1, ey, 2, 3, "1")
	px(c, 16 - int(rx / 2) - 1, ey, "W")
	px(c, 16 + int(rx / 2) - 1, ey, "W")
	px(c, 14, ey + 4, "k")
	px(c, 17, ey + 4, "k")
	px(c, 15, ey + 5, "k")
	px(c, 16, ey + 5, "k")
	# 半透明果冻感：整体略微透明（描边后仍不透明，造型不会散）
	set_alpha_area(c, 16 - rx - 1, top - 1, rx * 2 + 3, 30 - top + 1, 0.85)
	outline_dark(c)
	return c


func _gen_slime() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(96, 32)
	var idle := _slime_cell(11, 12)
	place(sheet, idle, 0, 0, 32, 32)
	place(sheet, _slime_cell(13, 19), 1, 0, 32, 32)      # 压扁
	var hit := _new_img(32, 32)
	hit.copy_from(idle)
	flash_white(hit)
	place(sheet, hit, 2, 0, 32, 32)
	_save(sheet, "enemy_slime.png")
	_dump_sheet(sheet, 32, 32, "enemy_slime", ["待机", "压扁", "受击闪白"])


# --- 紫色蝙蝠：身体 + 耳朵 + 红眼用字符画，翅膀两帧上下扇动 ---
var BAT_BODY := PackedStringArray([
	".kk...kk.",                     # 耳朵
	"kppk.kppk",
	"kpppkpppk",
	"kpRpppRpk",                     # 红眼
	"kpppppppk",
	".kpppppk.",
	"..kpppk..",
	"..kpppk..",
	"..kpppk..",
	"..kpppk..",
	"..kpppk..",
	"...kkk...",
	"..k.k.k..",                     # 爪子
])

var BAT_WING_UP := PackedStringArray([
	"kpk.........",
	"kPpk........",
	"kPPpk.......",
	".kPPpk......",
	".kPPPpk.....",
	"..kPPPppk...",
	"..kPpppppk..",
	"...kkkkkkk..",
])

var BAT_WING_DOWN := PackedStringArray([
	"............",
	".kpk........",
	".kPppk......",
	"..kPPpk.....",
	"..kPPPppk...",
	"...kPppppk..",
	"...kPPpppk..",
	"....kkkkkk..",
])


func _bat_cell(wing: PackedStringArray) -> Image:
	var c := _new_img(32, 32)
	blit_ascii(c, BAT_BODY, 12, 11)                      # 身体在正中
	blit_ascii(c, wing, 1, 12)                           # 左翅
	blit_ascii(c, _flip_rows(wing), 32 - 1 - 12, 12)     # 右翅（镜像，关于格子中线对称）
	outline_dark(c)
	return c


func _gen_bat() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(96, 32)
	var idle := _bat_cell(BAT_WING_UP)
	place(sheet, idle, 0, 0, 32, 32)
	place(sheet, _bat_cell(BAT_WING_DOWN), 1, 0, 32, 32)
	var hit := _new_img(32, 32)
	hit.copy_from(idle)
	flash_white(hit)
	place(sheet, hit, 2, 0, 32, 32)
	_save(sheet, "enemy_bat.png")
	_dump_sheet(sheet, 32, 32, "enemy_bat", ["翅膀上抬", "翅膀下压", "受击闪白"])


# --- 红伞白点蘑菇怪：伞盖 = 椭圆 + 白点，菌柄 = 矩形 + 五官 ---
func _mushroom_cell(walk: bool) -> Image:
	var c := _new_img(32, 32)
	# 菌柄（米白，左侧暗面）
	fill_rect(c, 12, 17, 8, 11, "t")
	fill_rect(c, 12, 17, 2, 11, "B")
	shade_vertical(c, 12, 24, 8, 4, "t", "b", true)
	# 伞盖
	fill_ellipse(c, 16, 13, 11, 7, "R")
	for y in range(17, 21):
		for x in range(4, 29):
			if getpx(c, x, y) == _col(P["R"]):
				px(c, x, y, "r")                            # 伞盖下沿压暗
	fill_ellipse(c, 13, 10, 3, 1, "o")                      # 左上受光的橙色反光
	# 菌褶
	fill_rect(c, 7, 19, 18, 2, "r")
	hline(c, 9, 22, 20, "k")
	# 白点（固定位置，不用随机，保证每次生成一致）
	blit_ascii(c, PackedStringArray([".WW.", "WWWW", ".WW."]), 8, 12)
	blit_ascii(c, PackedStringArray([".WW.", "WWWW", ".WW."]), 19, 15)
	blit_ascii(c, PackedStringArray([".W.", "WWW", ".W."]), 14, 7)
	# 五官画在菌柄上
	var dy := 1 if walk else 0
	fill_rect(c, 13, 21 + dy, 2, 2, "1")
	fill_rect(c, 17, 21 + dy, 2, 2, "1")
	px(c, 13, 21 + dy, "W")
	px(c, 17, 21 + dy, "W")
	hline(c, 14, 17, 25 + dy, "1")
	# 小脚
	fill_rect(c, 11, 27, 4, 2, "b")
	fill_rect(c, 17, 27, 4, 2, "b")
	fill_rect(c, 11, 29, 4, 1, "1")
	fill_rect(c, 17, 29, 4, 1, "1")
	outline_dark(c)
	return c


func _gen_mushroom() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(96, 32)
	var idle := _mushroom_cell(false)
	place(sheet, idle, 0, 0, 32, 32)
	place(sheet, _mushroom_cell(true), 1, 0, 32, 32)
	var hit := _new_img(32, 32)
	hit.copy_from(idle)
	flash_white(hit)
	place(sheet, hit, 2, 0, 32, 32)
	_save(sheet, "enemy_mushroom.png")
	_dump_sheet(sheet, 32, 32, "enemy_mushroom", ["待机", "行走", "受击闪白"])


# =============================================================================
#  7. 哥布林三兄弟：普通剑士 / 弓手 / 卫士（96x32，3 格 32x32）
# =============================================================================

# 哥布林的头：绿皮 + 尖耳朵 + 黄眼 + 獠牙（第 5~16 行，宽度 x10~21）
var GOB_HEAD := PackedStringArray([
	"............kkkkkk",             # 5  头顶
	"..........kkLLLLLLkk",           # 6
	"..........kLLLLLLLLGGk",         # 7
	"..........kLLLLLLLGGGk",         # 8
	"..........klLLGGGGGGGk",         # 9
	"..........kl11GGGG11gk",         # 10 眼窝
	"..........kl11GGGG11gk",         # 11
	"..........klyyGGGGyygk",         # 12 黄眼
	"..........kl1111111ggk",         # 13
	"..........klWkkkkkkWgk",         # 14 獠牙
	"..........kll111111ggk",         # 15
	"..........klLGGGGGGggk",         # 16
])

# 尖耳朵（5x4），左边画在 (6,8)，右边用镜像画在 (21,8)
var GOB_EAR := PackedStringArray([
	"kkk..",
	"klllk",
	".klk.",
	"..kk.",
])

# 哥布林躯干（褐色皮甲 + 绿皮肤），第 17~24 行
var GOB_TORSO := PackedStringArray([
	".........kggGGGGGGGGggk",        # 17 肩
	".........klGbbBBBBbbGgk",        # 18 皮甲
	".........klGbBBBBBbbGgk",        # 19
	".........klGbBBttBBbGgk",        # 20 腰带高光
	".........klGbBByyBBbGgk",        # 21 铜扣
	".........klGbbbbbbbbGgk",        # 22
	".........kgGbbbbbbbbGgk",        # 23
	".........kggggggggggggk",        # 24
])

# 哥布林腿：待机 / 迈步 A / 迈步 B（赤脚，脚掌深绿）
var GOB_LEGS_IDLE := PackedStringArray([
	"...........kbbbbbbbbk",          # 25 腰布
	"...........kllk..kllk",          # 26
	"...........kllk..kllk",          # 27
	"..........kgggk..kgggk",         # 28 脚掌
	"..........ggggg..ggggg",         # 29
])

var GOB_LEGS_A := PackedStringArray([
	"...........kbbbbbbbbk",
	"...........kllk..kllk",
	"...........kllk..kgggk",
	"..........kgggk",
	"..........ggggg",
])

var GOB_LEGS_B := PackedStringArray([
	"...........kbbbbbbbbk",
	"...........kllk..kllk",
	"..........kgggk..kllk",
	".................kgggk",
	".................ggggg",
])

# 短剑（斜 45°，刀尖朝右上）：护手 + 握把 + 金属刃
var SWORD_SHORT := PackedStringArray([
	"...kwk",
	"..kwWk",
	".kwWk.",
	"kwWk..",
	"kwk...",
	"ktk...",
	"kkk...",
	"kbk...",
	"kbk...",
	"kkk...",
])


func _goblin_cell(legs: PackedStringArray, arm_shift := 0, sword := true) -> Image:
	var c := _new_img(32, 32)
	blit_ascii(c, GOB_HEAD, 0, 5)
	blit_ascii(c, GOB_EAR, 6, 8)
	blit_ascii(c, _flip_rows(GOB_EAR), 21, 8)
	blit_ascii(c, GOB_TORSO, 0, 17)
	if sword:
		blit_ascii(c, SWORD_SHORT, 20 + arm_shift, 15)
	blit_ascii(c, legs, 0, 25)
	outline_dark(c)
	return c


func _gen_goblin() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(96, 32)
	place(sheet, _goblin_cell(GOB_LEGS_IDLE), 0, 0, 32, 32)
	place(sheet, _goblin_cell(GOB_LEGS_A, 0), 1, 0, 32, 32)
	place(sheet, _goblin_cell(GOB_LEGS_B, 1), 2, 0, 32, 32)
	_save(sheet, "enemy_goblin.png")
	_dump_sheet(sheet, 32, 32, "enemy_goblin", ["待机", "行走A", "行走B"])


# --- 哥布林弓手：羽毛头饰 + 木弓（弓身程序化画弧，弦和箭用直线）---
func _archer_cell(draw_bow: bool) -> Image:
	var c := _new_img(32, 32)
	# 羽毛头饰（插在头顶，红黄羽毛）
	blit_ascii(c, PackedStringArray([
		"..o.",
		".oyo",
		"oyR.",
		"oR..",
		"bb..",
	]), 16, 2)
	blit_ascii(c, GOB_HEAD, 0, 5)
	blit_ascii(c, GOB_EAR, 6, 8)
	blit_ascii(c, _flip_rows(GOB_EAR), 21, 8)
	blit_ascii(c, GOB_TORSO, 0, 17)
	# 木弓：右侧外凸的弧（上弓臂 + 下弓臂）+ 握把
	for i in 9:
		var t := float(i) / 8.0
		var bx := 22 + int(round(2.5 * sin(PI * t)))
		var by := 10 + i * 2
		px(c, bx, by, "b")
		px(c, bx - 1, by, "b")
	fill_rect(c, 23, 17, 4, 4, "m")                        # 握把（在弓腹一侧）
	if draw_bow:
		# 拉弓：弦被拉到左侧，箭已上弦
		line(c, 22, 10, 17, 18, "w")
		line(c, 22, 26, 17, 18, "w")
		hline(c, 18, 31, 18, "t")                          # 箭
		blit_ascii(c, PackedStringArray(["w"]), 31, 18)
	else:
		vline(c, 22, 10, 26, "w")                          # 松弛的弦
	blit_ascii(c, GOB_LEGS_IDLE, 0, 25)
	outline_dark(c)
	return c


func _gen_goblin_archer() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(96, 32)
	var idle := _archer_cell(false)
	place(sheet, idle, 0, 0, 32, 32)
	place(sheet, _archer_cell(true), 1, 0, 32, 32)
	var hit := _new_img(32, 32)
	hit.copy_from(idle)
	flash_white(hit)
	place(sheet, hit, 2, 0, 32, 32)
	_save(sheet, "enemy_goblin_archer.png")
	_dump_sheet(sheet, 32, 32, "enemy_goblin_archer", ["待机", "拉弓", "受击闪白"])


# --- 精英哥布林卫士：深色重甲头盔 + 盾牌，比普通哥布林更壮 ---
var GUARD_HEAD := PackedStringArray([
	"............kkkkkk",             # 5  头盔顶
	"..........kk333333kk",           # 6  金属
	"..........k3333333wwk",          # 7  高光
	"..........k333333322k",          # 8
	"..........k111111111k",          # 9  面罩
	"..........kl11GGGG11gk",         # 10 面罩缝隙里的眼睛
	"..........klyyGGGGyygk",         # 11
	"..........k111111111k",          # 12
	"..........klWkkkkkkWgk",         # 13 獠牙
	"..........kll1111112gk",         # 14
	"..........klLGGGGGG22k",         # 15
])


func _guard_cell(walk: bool, flash := false) -> Image:
	var c := _new_img(32, 32)
	# 更壮：躯干左右各加宽 1px
	fill_rect(c, 9, 17, 14, 8, "2")
	fill_rect(c, 9, 17, 2, 8, "1")
	fill_rect(c, 21, 17, 2, 8, "1")
	shade_vertical(c, 10, 17, 12, 8, "3", "1")
	fill_rect(c, 10, 20, 12, 1, "t")                      # 腰带
	fill_rect(c, 15, 20, 2, 2, "y")                       # 铜扣
	blit_ascii(c, GUARD_HEAD, 0, 5)
	blit_ascii(c, GOB_EAR, 6, 8)
	blit_ascii(c, _flip_rows(GOB_EAR), 21, 8)
	# 盾牌（左手，木质 + 金属边 + 中心圆凸）
	stroke_ellipse(c, 8, 21, 4, 6, "3")
	fill_ellipse(c, 8, 21, 4, 6, "B")
	stroke_ellipse(c, 8, 21, 4, 6, "3")
	fill_ellipse(c, 8, 21, 1, 2, "3")
	# 右手短剑
	blit_ascii(c, SWORD_SHORT, 21, 15)
	var legs := GOB_LEGS_IDLE
	if walk:
		legs = GOB_LEGS_A
	blit_ascii(c, legs, 0, 25)
	outline_dark(c)
	if flash:
		flash_white(c)
	return c


func _gen_goblin_guard() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(96, 32)
	place(sheet, _guard_cell(false), 0, 0, 32, 32)
	place(sheet, _guard_cell(true), 1, 0, 32, 32)
	place(sheet, _guard_cell(false, true), 2, 0, 32, 32)
	_save(sheet, "enemy_goblin_guard.png")
	_dump_sheet(sheet, 32, 32, "enemy_goblin_guard", ["待机", "行走", "受击闪白"])


# =============================================================================
#  8. boss_goblin_priest.png —— BOSS 哥布林大祭司（192x64，3 格 64x64）
#     紫金法袍 + 巨大兜帽 + 发光眼睛 + 木质法杖（顶端紫色法球）
#     造型思路：兜帽只写「左半边」字符画，右半边用镜像拼出来，保证左右完全对称
# =============================================================================

var PRIEST_HOOD_HALF := PackedStringArray([
	"......kkkkkk",                  # 兜帽顶
	"....kkPPPPPP",
	"..kkPPpppppp",
	".kkPpppppppp",
	"kkPppppppppp",
	"kPpppppppppp",
	"kPpyyyy11111",                  # 金色面部包边 + 兜帽里的暗部
	"kPpy11111111",
	"kPpy11yy1111",                  # 发光的眼睛
	"kPpy11yy1111",
	"kPpy11111111",
	"kPpy11111111",
	"kPpy11111111",
	"kPpy11111111",
	"kPpy11111111",
	"kPpyy1111111",
	"kPpppyy11111",
	"kPpppppyyyyy",                  # 金色滚边
	"kPpppppppppp",
	"kkpppppppppp",
])


func _boss_cell(cast: bool) -> Image:
	var c := _new_img(64, 64)
	# ---- 法杖（先画，让手臂压在上面）----
	fill_rect(c, 47, 12, 3, 46, "m")                     # 杖身
	fill_rect(c, 47, 12, 1, 46, "b")                     # 杖身暗面
	# 法球
	fill_ellipse(c, 48, 10, 6, 6, "p")
	fill_ellipse(c, 46, 8, 2, 2, "P")
	fill_ellipse(c, 48, 10, 6, 6, "p")                   # 再压一遍，保留月牙形高光
	stroke_ellipse(c, 48, 10, 6, 6, "n")
	if cast:
		# 施法帧：法球发光 + 环绕的魔力光环
		fill_ellipse_col(c, 48, 10, 11, 11, Color(0.71, 0.29, 0.79, 0.30))
		fill_ellipse_col(c, 48, 10, 8, 8, Color(0.95, 0.56, 0.79, 0.35))
		fill_ellipse(c, 48, 10, 8, 8, "p")
		fill_ellipse(c, 48, 10, 7, 7, "p")
		stroke_ellipse(c, 48, 10, 8, 8, "y")
		fill_ellipse(c, 46, 8, 3, 3, "W")
		for i in 6:
			var ang := float(i) * PI / 3.0
			px(c, 48 + int(round(10.0 * cos(ang))), 10 + int(round(10.0 * sin(ang))), "y")
			px(c, 48 + int(round(12.0 * cos(ang + 0.4))), 10 + int(round(12.0 * sin(ang + 0.4))), "P")
	# ---- 法袍：上窄下宽的梯形 + 紫色渐变 ----
	for y in range(26, 58):
		var t := float(y - 26) / 31.0
		var hw := int(round(lerpf(9.0, 17.0, t)))
		if cast:
			hw += int(round(1.5 * sin(float(y) * 0.6)))   # 施法时袍角飘动
		hline(c, 31 - hw, 32 + hw, y, "p")
	shade_vertical(c, 8, 26, 48, 32, "P", "1", true)
	# 金色滚边 + 腰带
	hline(c, 16, 47, 57, "y")
	hline(c, 16, 47, 56, "o")
	hline(c, 22, 41, 37, "y")
	hline(c, 22, 41, 38, "o")
	# 胸前金色护符
	blit_ascii(c, PackedStringArray([".y.", "yPy", ".y."]), 30, 41)
	# 袍子正面的开襟
	vline(c, 31, 39, 55, "o")
	vline(c, 32, 39, 55, "o")
	# ---- 兜帽（左半边 + 镜像）----
	blit_ascii(c, PRIEST_HOOD_HALF, 20, 6)
	blit_ascii(c, _flip_rows(PRIEST_HOOD_HALF), 32, 6)
	if cast:
		# 施法时眼睛更亮
		fill_rect(c, 26, 20, 2, 2, "W")
		fill_rect(c, 36, 20, 2, 2, "W")
	# ---- 手臂：袖子伸向法杖 ----
	for i in 12:
		var ax := 40 + i
		var ay := 30 + int(round(float(i) * 0.55))
		fill_rect(c, ax, ay, 2, 4, "p")
	# ---- 脚 ----
	fill_rect(c, 22, 58, 8, 4, "b")
	fill_rect(c, 34, 58, 8, 4, "b")
	fill_rect(c, 22, 61, 8, 1, "1")
	fill_rect(c, 34, 61, 8, 1, "1")
	outline_dark(c)
	return c


func _gen_boss_priest() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(192, 64)
	var idle := _boss_cell(false)
	place(sheet, idle, 0, 0, 64, 64)
	place(sheet, _boss_cell(true), 1, 0, 64, 64)
	var hit := _new_img(64, 64)
	hit.copy_from(idle)
	flash_white(hit)
	place(sheet, hit, 2, 0, 64, 64)
	_save(sheet, "boss_goblin_priest.png")
	_dump_sheet(sheet, 64, 64, "boss_goblin_priest", ["待机", "施法", "受击闪白"])


# =============================================================================
#  9. props.png —— 256x128，16 列 x 8 行，每格 16x16
#     格子左上角 = (col*16, row*16)
# =============================================================================

# 宝箱（关）：16x16，箱体占第 1~14 行
var CHEST_CLOSED := PackedStringArray([
	"................",
	"....kkkkkkkk....",
	"..kkbbbbbbbbkk..",
	".kbbBBBBBBBBbbk.",
	".kbBBBBBBBBBBbk.",
	".kbBBBBBBBBBBbk.",
	".kbbbbbbbbbbbbk.",
	".kkkkkkkkkkkkkk.",
	".kBBBBBBBBBBBBk.",
	".kBttttttttttBk.",
	".kBtttyyyytttBk.",
	".kBtttyyyytttBk.",
	".kBttttttttttBk.",
	".kBBBBBBBBBBBBk.",
	"..kkkkkkkkkkkk..",
	"................",
])

# 宝箱（开）：盖子掀起 + 里面一堆金币
var CHEST_OPEN := PackedStringArray([
	"................",
	"....kkkkkkkk....",
	"..kkbbbbbbbbkk..",
	".kbbBBBBBBBBbbk.",
	".kbbbbbbbbbbbbk.",
	".kkkkkkkkkkkkkk.",
	".kkkkkkkkkkkkkk.",
	".k111111111111k.",
	".k11yy1111yy11k.",
	".k1yyyyyyyyyy1k.",
	".k1yyyyyyyyyy1k.",
	".k11yyyyyyyy11k.",
	".k111111111111k.",
	".kkkkkkkkkkkkkk.",
	"................",
	"................",
])

# 宝箱上的品质宝石（叠在箱子正面，体现普通/优秀/稀有）
var CHEST_GEM := PackedStringArray([
	".y.",
	"yGy",
	".y.",
])

# 红心（回血）
var PROP_HEART := PackedStringArray([
	"................",
	"................",
	"...kkk...kkk....",
	"..kRRRk.kRRRk...",
	".kRWRRRkRRRRRk..",
	".kRWRRRRRRRRRk..",
	".kRRRRRRRRRRRk..",
	"..kRRRRRRRRRk...",
	"...kRRRRRRRk....",
	"....kRRRRRk.....",
	".....kRRRk......",
	"......kRk.......",
	".......k........",
	"................",
	"................",
	"................",
])

# 蓝宝石（回蓝）：12x9，画在 (2,3)
var PROP_GEM := PackedStringArray([
	"....kkkk....",
	"...kcWWck...",
	"..kcWWccNk..",
	".kccccccNNk.",
	"kcccccccNNNk",
	".kcccccNNNk.",
	"..kcccNNNk..",
	"...kcNNNk...",
	"....kkkk....",
])

# 钥匙：12x11，画在 (2,2)
var PROP_KEY := PackedStringArray([
	".kkkk.......",
	"ktyytk......",
	"ky11yk......",
	"ktyytk......",
	".kkkk.......",
	"..kyk.......",
	"..kyykkkk...",
	"..kyk.......",
	"..kyykkk....",
	"..kyk.......",
	"..kkk.......",
])

# 下楼梯 / 出口
var PROP_STAIRS := PackedStringArray([
	"................",
	"..kkkkkkkkkkkk..",
	"..k3333333333k..",
	"..kkkkkkkkkkkk..",
	"..k1111111111k..",
	"..k3222222223k..",
	"..kkkkkkkkkkkk..",
	"..k1111111111k..",
	"..k3322222223k..",
	"..kkkkkkkkkkkk..",
	"..k1111111111k..",
	"..k3333333333k..",
	"..kkkkkkkkkkkk..",
	"................",
	"................",
	"................",
])

# 小钱袋
var PROP_POUCH := PackedStringArray([
	"................",
	"................",
	"......kk........",
	".....kttk.......",
	"....kttttk......",
	"...kkttttkk.....",
	"..kbbbbbbbbk....",
	".kbbBBBBBBbbk...",
	".kbBByyyyBBbk...",
	".kbBByyyyBBbk...",
	".kbBBBBBBBBbk...",
	"..kbbbbbbbbk....",
	"...kkkkkkkk.....",
	"................",
	"................",
	"................",
])

# 命中火花（黄白星形）
var PROP_SPARK := PackedStringArray([
	"................",
	".......y........",
	"......yWy.......",
	"......yWy.......",
	"...y..yWy..y....",
	"...yyyyWyyyy....",
	"....yWWWWWy.....",
	"...yyyyWyyyy....",
	"...y..yWy..y....",
	"......yWy.......",
	"......yWy.......",
	".......y........",
	"................",
	"................",
	"................",
	"................",
])

# 枪口火焰
var PROP_MUZZLE := PackedStringArray([
	"................",
	"................",
	".........o......",
	"........oyo.....",
	".......oyWyo....",
	"..o...oyWWWyo...",
	".oyooooWWWWWoo..",
	".oyyooyWWWWWyo..",
	".oyooooWWWWWoo..",
	"..o...oyWWWyo...",
	".......oyWyo....",
	"........oyo.....",
	".........o......",
	"................",
	"................",
	"................",
])

# 药水（红）：把 R/r 换成 N/n 就是蓝药水
var PROP_POTION := PackedStringArray([
	"................",
	"................",
	"......kkk.......",
	"......kwk.......",
	".....kkwkk......",
	".....kwwwk......",
	"....kwWWWWk.....",
	"...kwWrrrrwk....",
	"...kwRrrrrwk....",
	"...kwRrrrrwk....",
	"...kwRRrrrwk....",
	"....kRRRRRk.....",
	".....kkkkk......",
	"................",
	"................",
	"................",
])

# 卷轴
var PROP_SCROLL := PackedStringArray([
	"................",
	"................",
	"..kkkkkkkkkkkk..",
	"..kttttttttttk..",
	"..kt11111111tk..",
	"..kttttttttttk..",
	"..kt1111111ttk..",
	"..kttttttttttk..",
	"..kt111111tttk..",
	"..kttttttttttk..",
	"..kttttttttttk..",
	"..kkkkkkkkkkkk..",
	"................",
	"................",
	"................",
	"................",
])

# --- 第 4 行：8 个技能图标（12x12 左右，画在 (2,2)）---
var ICON_ROLL := PackedStringArray([
	"..kk........",
	".kyyk.......",
	"kyyk........",
	"kyk...kk....",
	"kyk..kPPk...",
	"kyk..kPPk...",
	"kyyk..kk....",
	".kyyk.......",
	"..kkkkkkkk..",
])

var ICON_AIM := PackedStringArray([
	"...kkkkkk...",
	"..k......k..",
	".k...RR...k.",
	"k....RR....k",
	"k..RRRRRR..k",
	"k....RR....k",
	".k...RR...k.",
	"..k......k..",
	"...kkkkkk...",
])

var ICON_BURST := PackedStringArray([
	"............",
	"kyk..kyk..ky",
	"kWk..kWk..kW",
	"kyk..kyk..ky",
	"kkk..kkk..kk",
	"............",
	"kkk..kkk....",
	"kyk..kyk....",
	"kWk..kWk....",
	"kyk..kyk....",
	"kkk..kkk....",
])

var ICON_CRIT := PackedStringArray([
	".....yy.....",
	"..y..yy..y..",
	"...yyyyyy...",
	".yyyWWWWyyy.",
	"..yyWWWWyy..",
	".yyWWWWWWyy.",
	"...yyyyyy...",
	"..y..yy..y..",
	".....yy.....",
])

var ICON_LIFE := PackedStringArray([
	"...kkk..kkk.",
	"..kRRRkkRRRk",
	".kRRRRRRRRRk",
	".kRRRWRRRRRk",
	"..kRRWRRRRk.",
	"...kRWRRRk..",
	"....kRWRk...",
	".....kWk....",
	"......k.....",
])

var ICON_ENERGY := PackedStringArray([
	"....kkk.....",
	"...kcNk.....",
	"..kcNk......",
	".kcNkkkk....",
	"..kkNcck....",
	"....kNck....",
	"...kNck.....",
	"..kNk.......",
	".kkk........",
])

var ICON_MAGNET := PackedStringArray([
	"..kkkkkk....",
	".kRRkkRRk...",
	"kRRk..kRRk..",
	"kRRk..kRRk..",
	"kwwk..kwwk..",
	"kwwk..kwwk..",
	".kkk..kkk...",
])

var ICON_WIND := PackedStringArray([
	"............",
	"...kkkkkk...",
	"..kcccccck..",
	"...kkkkkk...",
	"............",
	".....kkkkkk.",
	"....kccccck.",
	".....kkkkkk.",
	"............",
	"..kkkkk.....",
	".kcccck.....",
	"..kkkkk.....",
])

# --- 第 5 行：8 个 UI 图标 ---
var ICON_BAG := PackedStringArray([
	"..kkkkkkkk..",
	".kbbbbbbbbk.",
	"kbbBBBBBBbbk",
	"kbBBBBBBBBbk",
	"kbBBkkkkBBbk",
	"kbBkyyyykBbk",
	"kbBkyyyykBbk",
	"kbBBkkkkBBbk",
	"kbBBBBBBBBbk",
	"kbbbbbbbbbbk",
	".kkkkkkkkkk.",
])

var ICON_TREE := PackedStringArray([
	".....GG.....",
	"...GGGGGG...",
	".GGGGGGGGGG.",
	"...GGGG.....",
	"...kbbk.....",
	"...kbbk.....",
	"..kbbbbk....",
	".kbbbbbbk...",
	"kkkkkkkkkk..",
])

var ICON_GEAR := PackedStringArray([
	"..k..kk..k..",
	"..kk333kkk..",
	".k33333333k.",
	"kk33kkkk333k",
	"k33kk11kk33k",
	"k33k1111k33k",
	"k33kk11kk33k",
	"kk33kkkk333k",
	".k33333333k.",
	"..kk333kkk..",
	"..k..kk..k..",
])

var ICON_CROSS := PackedStringArray([
	"kk........kk",
	"kRk......kRk",
	".kRk....kRk.",
	"..kRk..kRk..",
	"...kRkkRk...",
	"....kRRk....",
	"...kRkkRk...",
	"..kRk..kRk..",
	".kRk....kRk.",
	"kRk......kRk",
	"kk........kk",
])

var ICON_ARROW := PackedStringArray([
	".....k......",
	"....kWk.....",
	"...kWWk.....",
	"..kWWWWWWWk.",
	".kWWWWWWWWWk",
	"..kWWWWWWWk.",
	"...kWWk.....",
	"....kWk.....",
	".....k......",
])

var ICON_LOCK := PackedStringArray([
	"....kkkk....",
	"...k3333k...",
	"..k3kkkk3k..",
	"..k3k..k3k..",
	".kkkkkkkkkk.",
	".k33333333k.",
	".k33k11k33k.",
	".k33k11k33k.",
	".k33333333k.",
	".kkkkkkkkkk.",
])

# --- 第 7 行：森林场景装饰物 ---
var DECO_DOOR := PackedStringArray([
	".kkkkkkkkkk.",
	".kmmmmmmmmk.",
	".kmBBBBBBmk.",
	".kmBtttBBmk.",
	".kmBtytBBmk.",
	".kmBtttBBmk.",
	".kmBBBBBBmk.",
	".kmBtttBBmk.",
	".kmBtytBBmk.",
	".kmBBBBBBmk.",
	".kmmmmmmmmk.",
	".kkkkkkkkkk.",
])

var DECO_TORCH := PackedStringArray([
	"....oy......",
	"...oyyo.....",
	"..oyWWyo....",
	"..oyWWyo....",
	"...oyyo.....",
	"....yk......",
	"...kmmk.....",
	"...kmmk.....",
	"...kmmk.....",
	"...kmmk.....",
	"...kbbk.....",
	"....kk......",
])

var DECO_BARREL := PackedStringArray([
	"..kkkkkkkk..",
	".kmttttttmk.",
	"kmttBBBBttmk",
	"kmttBBBBttmk",
	"kmmmBBBBmmmk",
	"kmttBBBBttmk",
	"kmttBBBBttmk",
	"kmmmBBBBmmmk",
	"kmttBBBBttmk",
	".kmttttttmk.",
	"..kkkkkkkk..",
])

var DECO_CRATE := PackedStringArray([
	".kkkkkkkkkk.",
	".kmmmmmmmmk.",
	".kmBmmmmBmk.",
	".kmmBmmBmmk.",
	".kmmmBBmmmk.",
	".kmmBmmBmmk.",
	".kmBmmmmBmk.",
	".kmmmmmmmmk.",
	".kkkkkkkkkk.",
])

var DECO_BONES := PackedStringArray([
	"............",
	"..kk....kk..",
	".kwwk..kwwk.",
	"kwwwwkkwwwwk",
	".kwwk..kwwk.",
	"..kk....kk..",
	"...kwwwwk...",
	"..kwwwwwwk..",
	".kwwkkkkwwk.",
	"..kk....kk..",
])

var DECO_WEB := PackedStringArray([
	"ww..........",
	"w.ww........",
	"w...ww......",
	"w..w..ww....",
	"w.w..w..ww..",
	"ww..w..w..ww",
	"w.ww..w..w..",
	"w...wwwwww..",
	"w..w..w..w..",
	"w.w...w...w.",
	"ww....w....w",
])


# 金币（4 帧旋转）：用椭圆宽度模拟旋转，边缘深橙，正面亮黄
func _coin_cell(rx: int) -> Image:
	var c := _new_img(16, 16)
	if rx <= 1:
		fill_rect(c, 7, 3, 2, 10, "o")
		fill_rect(c, 7, 3, 1, 10, "y")
	else:
		fill_ellipse(c, 8, 8, rx, 6, "o")
		fill_ellipse(c, 8, 8, maxi(1, rx - 2), 5, "y")
		if rx >= 4:
			fill_ellipse(c, 6, 6, maxi(1, int(rx / 3)), 2, "W")
			# 币面的星形纹路
			px(c, 8, 5, "o")
			px(c, 8, 11, "o")
			px(c, 5, 8, "o")
			px(c, 11, 8, "o")
	outline_dark(c)
	return c


# 传送门：蓝色漩涡（同心椭圆 + 高光点）
func _portal_cell() -> Image:
	var c := _new_img(16, 16)
	stroke_ellipse(c, 8, 8, 7, 7, "n")
	stroke_ellipse(c, 8, 8, 6, 6, "N")
	stroke_ellipse(c, 8, 8, 4, 4, "c")
	fill_ellipse(c, 8, 8, 2, 2, "W")
	for i in 5:
		var ang := float(i) * 1.25
		px(c, 8 + int(round(5.0 * cos(ang))), 8 + int(round(5.0 * sin(ang))), "W")
		px(c, 8 + int(round(3.0 * cos(ang + 0.8))), 8 + int(round(3.0 * sin(ang + 0.8))), "c")
	outline_dark(c, "n")
	return c


# 椭圆阴影（半透明黑）
func _shadow_cell() -> Image:
	var c := _new_img(16, 16)
	fill_ellipse_col(c, 8, 12, 6, 3, Color(0, 0, 0, 0.35))
	fill_ellipse_col(c, 8, 12, 4, 2, Color(0, 0, 0, 0.45))
	return c


# 品质边框：2px 外框 + 四角装饰，用于道具格
func _border_cell(key: String) -> Image:
	var c := _new_img(16, 16)
	stroke_rect(c, 0, 0, 16, 16, key)
	stroke_rect(c, 1, 1, 14, 14, key)
	# 四角装饰
	blit_ascii(c, PackedStringArray(["kk", "k."]), 2, 2)
	blit_ascii(c, PackedStringArray(["kk", ".k"]), 12, 2)
	blit_ascii(c, PackedStringArray(["k.", "kk"]), 2, 12)
	blit_ascii(c, PackedStringArray([".k", "kk"]), 12, 12)
	return c


func _gen_props() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(256, 128)

	# ---------- 第 0 行：三种品质的宝箱（关/开）----------
	var tiers := [
		{"key": "w", "gem": {"y": "w", "G": "w"}},        # 普通：铁皮
		{"key": "l", "gem": {"y": "y", "G": "l"}},        # 优秀：绿宝石
		{"key": "c", "gem": {"y": "y", "G": "N"}},        # 稀有：蓝宝石
	]
	for i in 3:
		var tier: Dictionary = tiers[i]
		# 关着的箱子
		var closed := _new_img(16, 16)
		blit_ascii(closed, CHEST_CLOSED, 0, 0, {"B": String(tier["key"])})
		blit_ascii(closed, CHEST_GEM, 6, 9, tier["gem"])
		outline_dark(closed)
		place(sheet, closed, i * 2, 0, 16, 16)
		# 打开的箱子
		var opened := _new_img(16, 16)
		blit_ascii(opened, CHEST_OPEN, 0, 0)
		outline_dark(opened)
		place(sheet, opened, i * 2 + 1, 0, 16, 16)

	# ---------- 第 1 行：金币旋转 4 帧 ----------
	var coin_rx := [7, 5, 3, 1]
	for i in 4:
		place(sheet, _coin_cell(coin_rx[i]), i, 1, 16, 16)

	# ---------- 第 2 行 ----------
	place(sheet, _boxed(PROP_HEART), 0, 2, 16, 16)
	place(sheet, _boxed(PROP_GEM, 2, 3), 1, 2, 16, 16)
	place(sheet, _boxed(PROP_KEY, 2, 2), 2, 2, 16, 16)
	place(sheet, _portal_cell(), 3, 2, 16, 16)
	place(sheet, _boxed(PROP_STAIRS), 4, 2, 16, 16)
	place(sheet, _boxed(PROP_POUCH), 5, 2, 16, 16)

	# ---------- 第 3 行 ----------
	place(sheet, _shadow_cell(), 0, 3, 16, 16)
	place(sheet, _boxed(PROP_SPARK), 1, 3, 16, 16)
	place(sheet, _boxed(PROP_MUZZLE), 2, 3, 16, 16)
	place(sheet, _boxed(PROP_POTION), 3, 3, 16, 16)
	# 蓝药水 = 红药水换色
	var blue := _new_img(16, 16)
	blit_ascii(blue, PROP_POTION, 0, 0, {"R": "N", "r": "n"})
	outline_dark(blue)
	place(sheet, blue, 4, 3, 16, 16)
	place(sheet, _boxed(PROP_SCROLL), 5, 3, 16, 16)

	# ---------- 第 4 行：技能图标 ----------
	var skill_icons := [ICON_ROLL, ICON_AIM, ICON_BURST, ICON_CRIT, ICON_LIFE, ICON_ENERGY, ICON_MAGNET, ICON_WIND]
	for i in skill_icons.size():
		place(sheet, _boxed(skill_icons[i], 2, 2), i, 4, 16, 16)

	# ---------- 第 5 行：UI 图标 ----------
	place(sheet, _coin_cell(7), 0, 5, 16, 16)
	place(sheet, _boxed(ICON_BAG, 2, 3), 1, 5, 16, 16)
	# 仓库箱子：复用宝箱造型，换成冷色调
	var wh := _new_img(16, 16)
	blit_ascii(wh, CHEST_CLOSED, 0, 0, {"B": "N", "b": "n", "t": "c"})
	outline_dark(wh)
	place(sheet, wh, 2, 5, 16, 16)
	place(sheet, _boxed(ICON_TREE, 2, 3), 3, 5, 16, 16)
	place(sheet, _boxed(ICON_GEAR, 2, 2), 4, 5, 16, 16)
	place(sheet, _boxed(ICON_CROSS, 2, 2), 5, 5, 16, 16)
	place(sheet, _boxed(ICON_ARROW, 2, 3), 6, 5, 16, 16)
	place(sheet, _boxed(ICON_LOCK, 2, 3), 7, 5, 16, 16)

	# ---------- 第 6 行：品质边框 ----------
	place(sheet, _border_cell("w"), 0, 6, 16, 16)
	place(sheet, _border_cell("G"), 1, 6, 16, 16)
	place(sheet, _border_cell("N"), 2, 6, 16, 16)
	place(sheet, _border_cell("o"), 3, 6, 16, 16)

	# ---------- 第 7 行：森林装饰 ----------
	place(sheet, _boxed(DECO_DOOR, 2, 2), 0, 7, 16, 16)
	place(sheet, _boxed(DECO_TORCH, 2, 1), 1, 7, 16, 16)
	place(sheet, _boxed(DECO_BARREL, 2, 2), 2, 7, 16, 16)
	place(sheet, _boxed(DECO_CRATE, 2, 3), 3, 7, 16, 16)
	place(sheet, _boxed(DECO_BONES, 2, 2), 4, 7, 16, 16)
	place(sheet, _boxed(DECO_WEB, 0, 0), 5, 7, 16, 16)

	_save(sheet, "props.png")
	# 自检用的名字表：必须按「格子顺序」摆放（index = row * 16 + col）
	var nm: Array = []
	for i in 128:
		nm.append("")
	nm[0] = "宝箱-普通-关"
	nm[1] = "宝箱-普通-开"
	nm[2] = "宝箱-优秀-关"
	nm[3] = "宝箱-优秀-开"
	nm[4] = "宝箱-稀有-关"
	nm[5] = "宝箱-稀有-开"
	nm[16] = "金币1"
	nm[17] = "金币2"
	nm[18] = "金币3"
	nm[19] = "金币4"
	nm[32] = "红心"
	nm[33] = "蓝宝石"
	nm[34] = "钥匙"
	nm[35] = "传送门"
	nm[36] = "楼梯"
	nm[37] = "钱袋"
	nm[48] = "阴影"
	nm[49] = "命中火花"
	nm[50] = "枪口火焰"
	nm[51] = "红药水"
	nm[52] = "蓝药水"
	nm[53] = "卷轴"
	nm[64] = "技能-翻滚"
	nm[65] = "技能-精准"
	nm[66] = "技能-连射"
	nm[67] = "技能-暴击"
	nm[68] = "技能-生命"
	nm[69] = "技能-能量"
	nm[70] = "技能-拾取"
	nm[71] = "技能-疾风"
	nm[80] = "UI-金币"
	nm[81] = "UI-背包"
	nm[82] = "UI-仓库"
	nm[83] = "UI-技能树"
	nm[84] = "UI-齿轮"
	nm[85] = "UI-关闭"
	nm[86] = "UI-箭头"
	nm[87] = "UI-锁"
	nm[96] = "边框-白"
	nm[97] = "边框-绿"
	nm[98] = "边框-蓝"
	nm[99] = "边框-橙"
	nm[112] = "门"
	nm[113] = "火把"
	nm[114] = "木桶"
	nm[115] = "木箱"
	nm[116] = "骨头"
	nm[117] = "蜘蛛网"
	_dump_sheet(sheet, 16, 16, "props", nm)


# 把字符画贴进某个格子并描边（ox/oy 为格内偏移）
func _boxed(rows: PackedStringArray, ox := 0, oy := 0) -> Image:
	var c := _new_img(16, 16)
	blit_ascii(c, rows, ox, oy)
	outline_dark(c)
	return c


# =============================================================================
#  10. weapons.png —— 96x72，4 列 x 3 行，每格 24x24（12 把武器）
#      第 0 行 = 白色（普通）/ 第 1 行 = 绿色（优秀）/ 第 2 行 = 蓝色（稀有）
#      全部斜 45° 摆放：从「左下」指向「右上」，刀锋朝右上。
#      品质差异靠「造型」而不是单纯换色：普通=素面，优秀=加绿宝石+纹路，
#      稀有=加蓝宝石+发光符文+更华丽的护手/装饰。
# =============================================================================

func _erase(c: Image, x: int, y: int) -> void:
	px_set(c, x, y, Color(0, 0, 0, 0))


# 斜 45° 的刃/杆：沿 y 偏移若干像素做出厚度，再补高光与暗面
func _bar(c: Image, x0: int, y0: int, x1: int, y1: int, body: String, hi: String, shadow: String, thick: int) -> void:
	for i in thick:
		line(c, x0, y0 + i, x1, y1 + i, body)
	line(c, x0, y0, x1, y1, hi)
	line(c, x0, y0 + thick - 1, x1, y1 + thick - 1, shadow)


# 小宝石（菱形）
func _gem(c: Image, cx: int, cy: int, key: String, hi := "W") -> void:
	px(c, cx, cy - 1, key)
	px(c, cx - 1, cy, key)
	px(c, cx + 1, cy, key)
	px(c, cx, cy + 1, key)
	px(c, cx, cy, hi)


# 木弓：A、B 是弓梢，控制点朝右上凸出，弦是 A-B 直线
func _bow(c: Image, ax: int, ay: int, bx: int, by: int, ctrl_x: int, ctrl_y: int, key: String, hi: String) -> void:
	var steps := 26
	for i in steps + 1:
		var t := float(i) / float(steps)
		var it := 1.0 - t
		var x := int(round(it * it * ax + 2.0 * it * t * ctrl_x + t * t * bx))
		var y := int(round(it * it * ay + 2.0 * it * t * ctrl_y + t * t * by))
		px(c, x, y, key)
		px(c, x - 1, y, key)
		if i % 6 == 3:
			px(c, x, y, hi)
	line(c, ax, ay, bx, by, "w")                      # 弓弦


func _gen_weapons() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	# 72x96：3 列 x 4 行，每格 24x24。
	# 行 = 品质（白/绿/蓝/橙），列 = 该品质的第几把；格子左上角 = (col*24, row*24)
	var sheet := _new_img(72, 96)
	var C := 24

	# ---------- 第 0 行：白色品质（普通）----------
	place(sheet, _wpn_iron_sword(), 0, 0, C, C)          # (0,0) 铁剑
	place(sheet, _wpn_wood_club(), 1, 0, C, C)           # (1,0) 木棒
	place(sheet, _wpn_bow("b", "t", "", 0), 2, 0, C, C)  # (2,0) 猎弓

	# ---------- 第 1 行：绿色品质（优秀）----------
	place(sheet, _wpn_fine_sword(), 0, 1, C, C)          # (0,1) 精铁长剑
	place(sheet, _wpn_axe(), 1, 1, C, C)                 # (1,1) 战斧
	place(sheet, _wpn_bow("m", "l", "l", 2), 2, 1, C, C) # (2,1) 短弓

	# ---------- 第 2 行：蓝色品质（稀有）----------
	place(sheet, _wpn_knight_sword(), 0, 2, C, C)        # (0,2) 骑士重剑
	place(sheet, _wpn_silver_spear(), 1, 2, C, C)        # (1,2) 银枪
	place(sheet, _wpn_bow("m", "N", "N", 3), 2, 2, C, C) # (2,2) 秘银弓

	# ---------- 第 3 行：橙色品质（传奇）----------
	place(sheet, _wpn_flame_blade(), 0, 3, C, C)         # (0,3) 烈焰之刃
	place(sheet, _wpn_storm_crossbow(), 1, 3, C, C)      # (1,3) 风暴弩
	place(sheet, _wpn_arcane_staff(), 2, 3, C, C)        # (2,3) 秘法法杖

	_save(sheet, "weapons.png")
	_dump_sheet(sheet, C, C, "weapons", [
		"白-铁剑", "白-木棒", "白-猎弓",
		"绿-精铁长剑", "绿-战斧", "绿-短弓",
		"蓝-骑士重剑", "蓝-银枪", "蓝-秘银弓",
		"橙-烈焰之刃", "橙-风暴弩", "橙-秘法法杖",
	])


# 白：朴素铁剑（细刃 + 简单十字护手）
func _wpn_iron_sword() -> Image:
	var c := _new_img(24, 24)
	line(c, 5, 21, 9, 17, "b")                            # 握把
	line(c, 5, 20, 9, 16, "B")
	line(c, 6, 16, 11, 21, "3")                           # 十字护手（垂直于刃）
	_gem(c, 8, 18, "3", "w")
	_bar(c, 9, 15, 19, 5, "w", "W", "3", 3)               # 剑身
	line(c, 19, 4, 20, 3, "W")                            # 剑尖
	outline_dark(c)
	return c


# 白：粗木棒（上粗下细 + 木瘤）
func _wpn_wood_club() -> Image:
	var c := _new_img(24, 24)
	_bar(c, 4, 20, 13, 11, "b", "B", "b", 3)
	_bar(c, 10, 12, 18, 5, "B", "t", "b", 6)              # 加粗的棒头
	blit_ascii(c, PackedStringArray([".b.", "bBb", ".t."]), 13, 6)
	blit_ascii(c, PackedStringArray([".b.", "bBb"]), 16, 10)
	outline_dark(c)
	return c


# 白：猎弓（素木弓）
func _wpn_bow(wood: String, hi: String, gem_key: String, gem_count: int) -> Image:
	var c := _new_img(24, 24)
	_bow(c, 5, 4, 18, 20, 21, 6, wood, hi)                # 弓身（斜 45°）
	# 弓梢装饰
	blit_ascii(c, PackedStringArray(["kk", "k" + hi]), 4, 3)
	blit_ascii(c, PackedStringArray([hi + "k", "kk"]), 17, 19)
	if gem_count >= 1:
		_gem(c, 12, 9, gem_key)
	if gem_count >= 2:
		_gem(c, 9, 14, gem_key)
	if gem_count >= 3:
		_gem(c, 15, 12, gem_key)
		line(c, 10, 6, 18, 14, "c")                       # 稀有：发光装饰线
	outline_dark(c)
	return c


# =============================================================================
#  10.5 橙色品质（传奇）三把 —— 造型明显比蓝色更华丽：更宽的刃/更重的机械结构、
#       宝石 + 发光符文 + 半透明光晕，并且每把都有独立的「传奇特征」：
#       烈焰之刃 = 火焰纹 + 炽热刃口；风暴弩 = 蓝色电弧 + 发光箭矢；秘法法杖 = 悬浮法球 + 符文环
# =============================================================================

# 刃身上的火焰纹路（小字符画，贴在宽刃上）
var FLAME_MARK := PackedStringArray([
	".y.",
	"yoy",
	"yoy",
	".o.",
	".R.",
])

# 橙：烈焰之刃（宽刃 + 火焰纹 + 剑格橙红宝石 + 炽热发光边缘）
func _wpn_flame_blade() -> Image:
	var c := _new_img(24, 24)
	# 炽热光晕（垫底，半透明，压得比较淡，保证刀身轮廓清晰）
	fill_ellipse_col(c, 15, 11, 10, 10, Color(0.95, 0.63, 0.23, 0.16))
	fill_ellipse_col(c, 16, 8, 7, 7, Color(0.85, 0.29, 0.29, 0.14))
	# 握把 + 橙金剑格
	line(c, 3, 22, 8, 17, "b")
	line(c, 3, 21, 8, 16, "B")
	line(c, 4, 15, 13, 24, "o")
	line(c, 5, 15, 13, 23, "y")
	_gem(c, 8, 19, "R", "y")                              # 剑格上的橙红宝石
	# 宽刃（比骑士重剑更长，斜 45°）
	_bar(c, 9, 14, 21, 2, "w", "W", "3", 5)
	line(c, 9, 13, 21, 1, "y")                            # 上刃口：炽热发光
	line(c, 10, 14, 21, 3, "o")
	line(c, 11, 12, 20, 3, "3")                           # 血槽
	# 刃身火焰纹
	blit_ascii(c, FLAME_MARK, 11, 9)
	blit_ascii(c, FLAME_MARK, 15, 5)
	blit_ascii(c, FLAME_MARK, 18, 2)
	outline_dark(c)
	return c


# 橙：风暴弩（机械重弩 + 弩臂蓝色电弧 + 箭槽发光箭矢，橙金配色）
func _wpn_storm_crossbow() -> Image:
	var c := _new_img(24, 24)
	# 电弧光晕
	fill_ellipse_col(c, 13, 10, 10, 10, Color(0.29, 0.56, 0.85, 0.13))
	fill_ellipse_col(c, 12, 13, 7, 7, Color(0.95, 0.63, 0.23, 0.13))
	# 弩臂（垂直于弩身，斜 45°）+ 弓弦
	_bow(c, 9, 2, 20, 13, 20, 2, "3", "w")
	# 弩臂上的蓝色电弧 / 风纹
	blit_ascii(c, PackedStringArray(["cNc", ".N.", "NcN"]), 10, 3)
	blit_ascii(c, PackedStringArray(["NcN", ".N.", "cNc"]), 16, 9)
	blit_ascii(c, PackedStringArray(["NcN", ".N."]), 13, 6)
	# 橙金机械弩身（比普通弩更粗）
	_bar(c, 4, 21, 16, 9, "b", "o", "b", 4)
	line(c, 4, 21, 16, 9, "y")                            # 机身金色高光
	# 机匣齿轮 + 铆钉
	fill_ellipse(c, 9, 16, 3, 3, "o")
	fill_ellipse(c, 9, 16, 2, 2, "3")
	px(c, 9, 16, "y")
	fill_ellipse(c, 6, 19, 2, 2, "3")
	px(c, 6, 19, "w")
	# 箭槽里发光的箭矢（沿弩身方向）
	_bar(c, 8, 18, 20, 6, "y", "W", "o", 2)
	line(c, 20, 5, 22, 3, "W")                            # 箭头
	blit_ascii(c, PackedStringArray([".y.", "yWy", ".y."]), 19, 4)
	outline_dark(c)
	return c


# 橙：秘法法杖（悬浮橙色法球 + 环绕符文环 + 藤蔓宝石杖身）
func _wpn_arcane_staff() -> Image:
	var c := _new_img(24, 24)
	# 法球光晕
	fill_ellipse_col(c, 17, 6, 9, 9, Color(0.95, 0.63, 0.23, 0.17))
	fill_ellipse_col(c, 17, 6, 6, 6, Color(0.95, 0.56, 0.79, 0.13))
	# 杖身（木杖）
	_bar(c, 4, 21, 13, 12, "b", "m", "b", 3)
	# 缠绕的藤蔓 + 叶子
	for i in 11:
		var vx := 5 + i
		var vy := 20 - i
		px(c, vx + (i % 2), vy, "g")
		px(c, vx + (i % 2) + 1, vy, "G")
		if i % 3 == 0:
			px(c, vx - 1, vy, "l")
			px(c, vx + 2, vy - 1, "l")
	# 杖身镶嵌的宝石
	_gem(c, 9, 16, "o")
	_gem(c, 11, 13, "y")
	# 法球（悬浮：与杖身之间留出空隙，靠光点连接）
	fill_ellipse(c, 17, 6, 4, 4, "o")
	stroke_ellipse(c, 17, 6, 4, 4, "R")
	fill_ellipse(c, 15, 4, 2, 2, "y")
	px(c, 15, 4, "W")
	px(c, 16, 5, "W")
	# 佛珠般的符文环（环绕法球一圈）
	for i in 8:
		var ang := float(i) * TAU / 8.0
		px(c, 17 + int(round(7.0 * cos(ang))), 6 + int(round(7.0 * sin(ang))), "y")
	for i in 4:
		var ang2 := float(i) * TAU / 4.0 + 0.4
		px(c, 17 + int(round(5.5 * cos(ang2))), 6 + int(round(5.5 * sin(ang2))), "P")
	# 悬浮连接的光点
	px(c, 14, 11, "y")
	px(c, 15, 10, "o")
	px(c, 13, 10, "P")
	outline_dark(c)
	return c


# 绿：精铁长剑（更长更宽 + 绿宝石 + 刃面纹路）
func _wpn_fine_sword() -> Image:
	var c := _new_img(24, 24)
	line(c, 4, 21, 8, 17, "b")
	line(c, 4, 20, 8, 16, "B")
	line(c, 5, 15, 12, 22, "l")                           # 绿色护手
	line(c, 6, 14, 13, 21, "G")
	_gem(c, 8, 18, "l")
	_bar(c, 9, 14, 20, 3, "w", "W", "3", 4)               # 更长的剑身
	line(c, 11, 12, 19, 4, "3")                           # 血槽纹路
	_gem(c, 14, 9, "l")                                   # 剑身镶绿宝石
	line(c, 20, 2, 21, 1, "W")
	outline_dark(c)
	return c


# 绿：战斧（长柄 + 弯月斧刃 + 绿宝石）
func _wpn_axe() -> Image:
	var c := _new_img(24, 24)
	_bar(c, 4, 21, 16, 9, "m", "B", "b", 3)               # 斧柄
	fill_ellipse(c, 18, 7, 6, 6, "3")                     # 斧头（先画圆）
	for y in 24:
		for x in 24:
			if x + y < 21:                                 # 切掉左下，做出弯月刃
				_erase(c, x, y)
	fill_ellipse(c, 16, 9, 3, 3, "3")
	line(c, 16, 3, 21, 8, "w")                            # 刃口高光
	line(c, 15, 4, 20, 9, "W")
	_gem(c, 15, 9, "l")
	outline_dark(c)
	return c


# 蓝：骑士重剑（宽刃 + 华丽护手 + 蓝宝石 + 微光）
func _wpn_knight_sword() -> Image:
	var c := _new_img(24, 24)
	fill_ellipse_col(c, 14, 10, 11, 11, Color(0.29, 0.56, 0.85, 0.18))   # 蓝色微光
	line(c, 4, 21, 8, 17, "b")
	line(c, 4, 20, 8, 16, "B")
	line(c, 4, 14, 13, 23, "y")                           # 金色护手
	line(c, 5, 14, 13, 22, "o")
	_gem(c, 8, 18, "N")
	_bar(c, 9, 13, 21, 1, "w", "W", "3", 5)               # 宽刃
	line(c, 11, 11, 20, 2, "3")
	_gem(c, 13, 9, "N")
	_gem(c, 16, 6, "N")
	outline_dark(c)
	return c


# 蓝：银枪（超长杆 + 银白叶形枪头 + 蓝光符文 + 红缨）
func _wpn_silver_spear() -> Image:
	var c := _new_img(24, 24)
	fill_ellipse_col(c, 17, 8, 7, 7, Color(0.29, 0.56, 0.85, 0.12))       # 蓝色微光
	_bar(c, 3, 22, 16, 9, "m", "B", "b", 2)               # 枪杆（很长）
	blit_ascii(c, PackedStringArray(["cNc", ".N."]), 12, 12)             # 杆上的蓝符文
	blit_ascii(c, PackedStringArray([".R.", "RRR", ".R."]), 14, 10)      # 红缨
	# 叶形银枪头（银白为主，蓝光描边）
	fill_ellipse(c, 18, 6, 3, 5, "w")
	for y in 24:
		for x in 24:
			if getpx(c, x, y) == _col(P["w"]) and x < 16:
				_erase(c, x, y)
	line(c, 17, 2, 19, 4, "W")                            # 枪尖高光
	line(c, 16, 4, 18, 8, "W")
	line(c, 20, 5, 20, 9, "3")                            # 枪头暗面
	stroke_ellipse(c, 18, 6, 3, 5, "c")                   # 蓝光边缘
	_gem(c, 18, 6, "N")                                   # 枪头蓝宝石
	outline_dark(c)
	return c


# =============================================================================
#  11. weapon_cherry_shotgun.png —— 48x48，橙色传奇「樱花霰弹枪」
#      粗短枪管 + 木托 + 缠绕的樱花枝与花瓣 + 枪管上一朵大樱花 + 橙粉微光
# =============================================================================

func _gen_cherry_shotgun() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var c := _new_img(48, 48)
	# 橙色传奇微光（半透明，垫在最底下）
	fill_ellipse_col(c, 24, 24, 22, 18, Color(0.95, 0.63, 0.23, 0.16))
	fill_ellipse_col(c, 22, 20, 16, 13, Color(0.95, 0.56, 0.79, 0.16))
	# 木托（左下，粗壮）
	fill_ellipse(c, 9, 38, 6, 4, "m")
	fill_ellipse(c, 9, 38, 5, 3, "B")
	_bar(c, 8, 39, 17, 30, "m", "B", "b", 5)
	# 枪机/机匣
	fill_rect(c, 15, 28, 8, 8, "b")
	fill_rect(c, 16, 29, 6, 3, "o")
	fill_rect(c, 16, 29, 6, 1, "y")
	# 双管（粗短的霰弹枪管，斜 45°）
	_bar(c, 18, 32, 42, 8, "b", "o", "b", 6)
	_bar(c, 20, 36, 44, 12, "b", "o", "b", 6)
	line(c, 19, 31, 43, 7, "y")                           # 枪管高光
	line(c, 21, 35, 45, 11, "y")
	# 枪口（加粗的喇叭口）
	fill_rect(c, 40, 5, 5, 5, "o")
	fill_rect(c, 41, 6, 3, 3, "k")
	fill_rect(c, 39, 9, 5, 5, "o")
	fill_rect(c, 40, 10, 3, 3, "k")
	# 樱花枝：缠绕枪管的棕色枝干
	for i in 14:
		var t := float(i) / 13.0
		var x := int(round(lerpf(14.0, 40.0, t)))
		var y := int(round(lerpf(34.0, 6.0, t) + 5.0 * sin(t * 9.0)))
		px(c, x, y, "b")
		px(c, x, y + 1, "b")
		if i % 4 == 2:
			px(c, x + 1, y - 1, "b")
	# 枪管上一朵明显的樱花（5 瓣 + 黄花心）
	var fx := 31
	var fy := 17
	for i in 5:
		var ang := float(i) * TAU / 5.0 - PI / 2.0
		var px_ := fx + int(round(4.0 * cos(ang)))
		var py_ := fy + int(round(4.0 * sin(ang)))
		fill_ellipse(c, px_, py_, 2, 2, "P")
		px(c, px_, py_, "W")
	fill_ellipse(c, fx, fy, 2, 2, "y")
	px(c, fx, fy, "W")
	# 散落的花瓣
	var petals := [Vector2i(11, 27), Vector2i(20, 20), Vector2i(38, 22), Vector2i(27, 30), Vector2i(43, 16), Vector2i(15, 15)]
	for pt in petals:
		blit_ascii(c, PackedStringArray([".PP.", "PPPP", ".PP."]), pt.x, pt.y)
	outline_dark(c)
	_save(c, "weapon_cherry_shotgun.png")
	_dump_sheet(c, 48, 48, "weapon_cherry_shotgun", ["樱花霰弹枪"])


# =============================================================================
#  13/14. ui_panel.png（64x64 九宫格面板）与 ui_bar.png（64x32 血条/蓝条）
# =============================================================================

func _gen_ui_panel() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var c := _new_img(64, 64)
	# 深色底（保证文字可读）
	fill_rect(c, 0, 0, 64, 64, "1")
	fill_rect(c, 3, 3, 58, 58, "k")
	fill_rect(c, 4, 4, 56, 56, "1")
	# 木质外框
	fill_rect(c, 0, 0, 64, 3, "m")
	fill_rect(c, 0, 61, 64, 3, "m")
	fill_rect(c, 0, 0, 3, 64, "m")
	fill_rect(c, 61, 0, 3, 64, "m")
	shade_vertical(c, 0, 0, 64, 3, "B", "b")
	hline(c, 0, 63, 0, "B")
	hline(c, 0, 63, 63, "b")
	vline(c, 0, 0, 63, "B")
	vline(c, 63, 0, 63, "b")
	# 石质内框
	stroke_rect(c, 3, 3, 58, 58, "3")
	stroke_rect(c, 4, 4, 56, 56, "2")
	# 四角铆钉
	for p in [Vector2i(7, 7), Vector2i(53, 7), Vector2i(7, 53), Vector2i(53, 53)]:
		fill_ellipse(c, p.x + 1, p.y + 1, 3, 3, "3")
		fill_ellipse(c, p.x + 1, p.y + 1, 2, 2, "w")
		px(c, p.x, p.y, "W")
	# 木纹
	noise_scatter(c, 0, 0, 64, 3, "b", 40)
	noise_scatter(c, 0, 61, 64, 3, "b", 40)
	_save(c, "ui_panel.png")
	_dump_sheet(c, 64, 64, "ui_panel", ["九宫格面板"])


func _gen_ui_bar() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var c := _new_img(64, 32)
	# 上半：血条（红 -> 暗红渐变 + 顶部高光）
	shade_vertical(c, 0, 0, 64, 16, "R", "r")
	hline(c, 0, 63, 1, "W")
	hline(c, 0, 63, 2, "o")
	hline(c, 0, 63, 0, "r")
	hline(c, 0, 63, 15, "k")
	vline(c, 63, 0, 15, "r")
	# 下半：蓝条（蓝 -> 深蓝渐变 + 顶部高光）
	shade_vertical(c, 0, 16, 64, 16, "N", "n")
	hline(c, 0, 63, 17, "W")
	hline(c, 0, 63, 18, "c")
	hline(c, 0, 63, 16, "n")
	hline(c, 0, 63, 31, "k")
	vline(c, 63, 16, 31, "n")
	# 中缝
	hline(c, 0, 63, 14, "k")
	hline(c, 0, 63, 30, "k")
	_save(c, "ui_bar.png")
	_dump_sheet(c, 64, 32, "ui_bar", ["血条上/蓝条下"])


# =============================================================================
#  12. tileset_forest.png —— 128x128，8 列 x 8 行，每格 16x16
#      TILE 索引 = row * 8 + col
#      地面/水体这类「纯噪点」地块用程序化铺底，造型类地块（树、岩壁、建筑、
#      祭坛、地刺等）用字符画 + 描边，保证风格统一且可手改。
# =============================================================================

# 铺底：底色 + 若干组噪点 [[颜色字符, 数量], ...]
func _t_ground(base_key: String, spec: Array) -> Image:
	var c := _new_img(16, 16)
	fill_rect(c, 0, 0, 16, 16, base_key)
	for s in spec:
		noise_scatter(c, 0, 0, 16, 16, String(s[0]), int(s[1]))
	return c


# 在铺底上放一个「带描边的小物件」（物件单独画一层再描边，避免被地面吃掉轮廓）
func _t_object(rows: PackedStringArray, ox: int, oy: int, base_key: String, spec: Array) -> Image:
	var base := _t_ground(base_key, spec)
	var obj := _new_img(16, 16)
	blit_ascii(obj, rows, ox, oy)
	outline_dark(obj)
	blit_over(base, obj, 0, 0)
	return base


# 铺底 + 椭圆石块/灌木（带高光和描边）
func _t_blob(cx: int, cy: int, rx: int, ry: int, key: String, hi_key: String, base_key: String, spec: Array) -> Image:
	var base := _t_ground(base_key, spec)
	var obj := _new_img(16, 16)
	fill_ellipse(obj, cx, cy, rx, ry, key)
	fill_ellipse(obj, cx - int(rx / 3), cy - int(ry / 3), maxi(1, int(rx / 2)), maxi(1, int(ry / 2)), hi_key)
	outline_dark(obj)
	blit_over(base, obj, 0, 0)
	return base


func _put_tile(sheet: Image, idx: int, cell: Image) -> void:
	place(sheet, cell, idx % 8, idx / 8, 16, 16)


func _gen_tileset() -> void:
	if _failed:
		return
	rng.seed = RNG_SEED
	var sheet := _new_img(128, 128)

	# ---------- 第 0 行：地面（草地 4 变体 / 泥土 / 石板路）----------
	for v in 4:
		_tile_grass(v, sheet, v)
	_put_tile(sheet, 4, _t_ground("B", [["b", 34], ["t", 22], ["3", 6]]))              # 泥土
	_put_tile(sheet, 5, _t_ground("b", [["B", 30], ["t", 10], ["k", 5]]))              # 深泥土
	_tile_stone_path(sheet, 6, false)                                                  # 石板路
	_tile_stone_path(sheet, 7, true)                                                   # 石板路(裂纹)

	# ---------- 第 1 行：过渡 / 特殊地面 ----------
	_tile_edge(sheet, 8, "G", "B")                                                     # 草泥边界 1
	_tile_edge(sheet, 9, "B", "G")                                                     # 草泥边界 2
	_tile_bushy(sheet, 10, 3)
	_tile_bushy(sheet, 11, 6)
	_put_tile(sheet, 12, _t_ground("t", [["B", 30], ["y", 8]]))                        # 沙地
	_put_tile(sheet, 13, _t_ground("3", [["2", 40], ["w", 26], ["k", 14]]))            # 碎石地
	var shallow := _t_ground("c", [["N", 16], ["W", 10]])
	set_alpha_area(shallow, 0, 0, 16, 16, 0.85)
	_put_tile(sheet, 14, shallow)                                                      # 浅水
	_put_tile(sheet, 15, _t_ground("n", [["N", 22], ["c", 10]]))                       # 深水

	# ---------- 第 2 行：地表小物件（不遮挡视线）----------
	_put_tile(sheet, 16, _t_blob(8, 11, 4, 3, "3", "w", "G", [["g", 22], ["l", 12]]))  # 小石头
	_tile_bush(sheet, 17)                                                              # 灌木
	_tile_flower(sheet, 18, "P", "y")                                                  # 小花(粉)
	_tile_flower(sheet, 19, "R", "y")                                                  # 小花(红)
	_tile_small_mushroom(sheet, 20)                                                    # 蘑菇装饰
	_tile_stump(sheet, 21)                                                             # 树桩
	_tile_tall_grass(sheet, 22)                                                        # 高草
	_tile_log(sheet, 23)                                                               # 倒木

	# ---------- 第 3 行：树木（遮挡类）----------
	_tile_canopy(sheet)                                                                # 24~27 树冠 4 块
	_tile_trunk(sheet, 28)                                                             # 树干
	_tile_pine(sheet, 29)                                                              # 松树
	_tile_dead_tree(sheet, 30)                                                         # 枯树
	_tile_big_stump(sheet, 31)                                                         # 大树桩

	# ---------- 第 4 行：墙体 / 悬崖 ----------
	for i in 8:
		_tile_cliff(sheet, 32 + i, i)

	# ---------- 第 5 行：建筑 / 营地 ----------
	_tile_wood_floor(sheet, 40, 0)
	_tile_wood_floor(sheet, 41, 1)
	_tile_brick(sheet, 42, false)
	_tile_brick(sheet, 43, true)
	_tile_tent(sheet, 44)
	_tile_fence(sheet, 45)
	_tile_bridge(sheet, 46, 0)
	_tile_bridge(sheet, 47, 1)

	# ---------- 第 6 行：祭坛 / 特殊 ----------
	_tile_altar(sheet, 48)
	_tile_magic_circle(sheet, 49, true)
	_tile_magic_circle(sheet, 50, false)
	_put_tile(sheet, 51, _t_ground("3", [["2", 30], ["G", 34], ["g", 20]]))            # 苔藓石
	_tile_vine(sheet, 52)
	_tile_leaves(sheet, 53)
	_put_tile(sheet, 54, _t_ground("b", [["1", 40], ["B", 16]]))                       # 泥沼
	_tile_pit(sheet, 55)

	# ---------- 第 7 行：杂项 ----------
	_put_tile(sheet, 56, _t_ground("k", []))                                           # 全黑（碰撞填充）
	var dark := _t_ground("1", [])
	set_alpha_area(dark, 0, 0, 16, 16, 0.55)
	_put_tile(sheet, 57, dark)                                                         # 半透明黑影
	_tile_moss_wall(sheet, 58)
	_tile_cave(sheet, 59)
	_tile_spikes(sheet, 60, false)
	_tile_spikes(sheet, 61, true)
	_tile_chest_base(sheet, 62)
	_tile_teleport(sheet, 63)

	_save(sheet, "tileset_forest.png")
	var names: Array = []
	for i in 64:
		names.append("TILE %d (col%d,row%d)" % [i, i % 8, i / 8])
	_dump_sheet(sheet, 16, 16, "tileset_forest", names)


# --- 草地：4 种细微噪点变体 ---
func _tile_grass(variant: int, sheet: Image, idx: int) -> void:
	var c := _t_ground("G", [["g", 24 + variant * 10], ["l", 12 + variant * 6]])
	for i in 3 + variant * 2:
		var x := rng.randi_range(1, 14)
		var y := rng.randi_range(3, 14)
		px(c, x, y, "l")
		px(c, x, y - 1, "l")
		px(c, x + 1, y, "g")
	_put_tile(sheet, idx, c)


# --- 石板路：规整石块 + 可选裂纹 ---
func _tile_stone_path(sheet: Image, idx: int, cracked: bool) -> void:
	var c := _t_ground("3", [["2", 22], ["w", 16]])
	hline(c, 0, 15, 0, "2")
	hline(c, 0, 15, 8, "2")
	vline(c, 7, 0, 7, "2")
	vline(c, 15, 8, 15, "2")
	if cracked:
		line(c, 2, 2, 6, 6, "1")
		line(c, 9, 10, 13, 13, "1")
		line(c, 10, 2, 13, 5, "1")
	_put_tile(sheet, idx, c)


# --- 两种地面的斜向过渡边界 ---
func _tile_edge(sheet: Image, idx: int, top_key: String, bottom_key: String) -> void:
	var c := _t_ground(top_key, [["g", 18], ["l", 10]] if top_key == "G" else [["b", 22]])
	for x in 16:
		var edge := 8 + int(round(2.5 * sin(float(x) * 0.8)))
		for y in range(edge, 16):
			px(c, x, y, bottom_key)
			if rng.randf() < 0.25:
				px(c, x, y, "b" if bottom_key == "B" else "g")
	_put_tile(sheet, idx, c)


# --- 茂密草丛 ---
func _tile_bushy(sheet: Image, idx: int, count: int) -> void:
	var c := _t_ground("G", [["g", 26], ["l", 14]])
	for i in count:
		var x := rng.randi_range(1, 13)
		var y := rng.randi_range(6, 14)
		blit_ascii(c, PackedStringArray(["l.l", ".l.", "l.l"]), x, y)
	_put_tile(sheet, idx, c)


# --- 灌木丛（带果实）---
func _tile_bush(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"....kkkk....",
		"..kkggGGkk..",
		".kggGGGGGgk.",
		"kgGGlllGGGgk",
		"kGGllRllGGGk",
		"kGGGlllGGGgk",
		"kggGGGGGGggk",
		".kkgggggkkk.",
		"...kkkkk....",
	])
	_put_tile(sheet, idx, _t_object(rows, 2, 5, "G", [["g", 24], ["l", 12]]))


# --- 小花 ---
func _tile_flower(sheet: Image, idx: int, petal: String, core: String) -> void:
	var rows := PackedStringArray([
		"..k" + petal + "k..",
		".k" + petal + core + petal + "k.",
		"..k" + petal + "k..",
		"...g...",
		"...g...",
		"..gg...",
	])
	_put_tile(sheet, idx, _t_object(rows, 5, 6, "G", [["g", 24], ["l", 12]]))


# --- 装饰蘑菇 ---
func _tile_small_mushroom(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"..kkkk..",
		".kRRRRk.",
		"kRWRRWRk",
		"kRRRRRRk",
		".kkttkk.",
		"..kttk..",
		"..kttk..",
	])
	_put_tile(sheet, idx, _t_object(rows, 4, 6, "G", [["g", 24], ["l", 12]]))


# --- 树桩 ---
func _tile_stump(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"..kkkkkk..",
		".kmBBBBmk.",
		"kmBtttBBmk",
		"kmBtttBBmk",
		"kmmmmmmmmk",
		".kkmmmmkk.",
		"..kkkkkk..",
	])
	_put_tile(sheet, idx, _t_object(rows, 3, 6, "G", [["g", 24], ["l", 12]]))


# --- 高草 ---
func _tile_tall_grass(sheet: Image, idx: int) -> void:
	var c := _t_ground("G", [["g", 26], ["l", 14]])
	for i in 7:
		var x := 1 + i * 2
		var h := rng.randi_range(4, 8)
		vline(c, x, 15 - h, 15, "g")
		vline(c, x + 1, 15 - h + 1, 15, "l")
		px(c, x, 15 - h, "L")
	_put_tile(sheet, idx, c)


# --- 倒木 ---
func _tile_log(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"kkkkkkkkkkkkkk",
		"kmmmmmmmmmmmmk",
		"kBtttttttttBk.",
		"kBtttttttttBk.",
		"kbbbbbbbbbbk..",
		".kkkkkkkkkk...",
	])
	_put_tile(sheet, idx, _t_object(rows, 1, 8, "G", [["g", 24], ["l", 12]]))


# --- 树冠：先在 32x32 上画一整团，再切成 4 块 16x16 放进 [0,3][1,3][2,3][3,3] ---
func _tile_canopy(sheet: Image) -> void:
	var big := _new_img(32, 32)
	fill_ellipse(big, 16, 16, 15, 15, "g")
	for i in 10:
		var ang := rng.randf() * TAU
		var r := rng.randf() * 12.0
		fill_ellipse(big, 16 + int(cos(ang) * r), 16 + int(sin(ang) * r), rng.randi_range(3, 6), rng.randi_range(3, 5), "G" if i % 2 == 0 else "g")
	for i in 16:                                        # 顶部亮叶
		var x := rng.randi_range(2, 29)
		var y := rng.randi_range(1, 16)
		fill_ellipse(big, x, y, 2, 2, "l")
		px(big, x, y - 1, "L")
	outline_dark(big)
	# 切块：左上(0,3) 右上(1,3) 左下(2,3) 右下(3,3)
	sheet.blit_rect(big, Rect2i(0, 0, 16, 16), Vector2i(0, 48))
	sheet.blit_rect(big, Rect2i(16, 0, 16, 16), Vector2i(16, 48))
	sheet.blit_rect(big, Rect2i(0, 16, 16, 16), Vector2i(32, 48))
	sheet.blit_rect(big, Rect2i(16, 16, 16, 16), Vector2i(48, 48))


# --- 树干 ---
func _tile_trunk(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		".kbbbbbbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kbBmmBbk.",
		".kkbbbbkk.",
	])
	_put_tile(sheet, idx, _t_object(rows, 3, 2, "G", [["g", 24], ["l", 12]]))


# --- 松树 ---
func _tile_pine(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"......kk......",
		".....kggk.....",
		"....kgGGgk....",
		"...kgGGGGgk...",
		"..kgGGllGGgk..",
		".....kggk.....",
		"....kgGGgk....",
		"...kgGGlGgk...",
		"..kgGGGGGGgk..",
		".....kbbk.....",
		".....kbbk.....",
	])
	_put_tile(sheet, idx, _t_object(rows, 1, 3, "G", [["g", 24], ["l", 12]]))


# --- 枯树 ---
func _tile_dead_tree(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"..k......k..",
		"..kk....kk..",
		"...kk..kk...",
		"....kkkk....",
		"..k..kk..k..",
		".kk.kkkk.kk.",
		"..k..kk..k..",
		".....kk.....",
		".....kk.....",
		".....kk.....",
		"....kkkk....",
	])
	_put_tile(sheet, idx, _t_object(rows, 2, 3, "G", [["g", 24], ["l", 12]]))


# --- 大树桩 ---
func _tile_big_stump(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"..kkkkkkkk..",
		".kmBttttBmk.",
		"kmBt3t3tBmk.",
		"kmBtttttBmk.",
		"kmBt3t3tBmk.",
		"kmmmmmmmmmk.",
		"kbbbbbbbbbk.",
		".kkkkkkkkk..",
	])
	_put_tile(sheet, idx, _t_object(rows, 2, 5, "G", [["g", 24], ["l", 12]]))


# --- 岩壁 8 种：顶左 / 顶中 / 顶右 / 侧面 / 底部 / 左角 / 右角 / 内角 ---
func _tile_cliff(sheet: Image, idx: int, kind: int) -> void:
	var c := _t_ground("3", [["2", 30], ["w", 14]])
	hline(c, 0, 15, 0, "2")
	hline(c, 0, 15, 15, "1")
	vline(c, 0, 0, 15, "2")
	vline(c, 15, 0, 15, "2")
	match kind:
		0:                                          # 顶左：草皮 + 高光
			fill_rect(c, 0, 0, 16, 4, "G")
			hline(c, 0, 15, 4, "g")
			hline(c, 0, 15, 5, "1")
			vline(c, 0, 0, 15, "l")
		1:                                          # 顶中：草皮
			fill_rect(c, 0, 0, 16, 4, "G")
			hline(c, 0, 15, 4, "g")
			hline(c, 0, 15, 5, "1")
		2:                                          # 顶右：草皮 + 暗右边
			fill_rect(c, 0, 0, 16, 4, "G")
			hline(c, 0, 15, 4, "g")
			hline(c, 0, 15, 5, "1")
			vline(c, 15, 0, 15, "1")
		3:                                          # 侧面：竖向裂缝
			line(c, 3, 1, 3, 14, "2")
			line(c, 9, 0, 11, 15, "1")
			line(c, 13, 2, 13, 13, "2")
		4:                                          # 底部：暗底 + 碎石
			hline(c, 0, 15, 13, "1")
			hline(c, 0, 15, 14, "2")
			noise_scatter(c, 0, 10, 16, 4, "k", 10)
		5:                                          # 左角：左侧受光
			fill_rect(c, 0, 0, 3, 16, "w")
			vline(c, 3, 0, 15, "2")
			line(c, 8, 1, 8, 14, "2")
		6:                                          # 右角：右侧背光
			fill_rect(c, 13, 0, 3, 16, "1")
			vline(c, 12, 0, 15, "2")
			line(c, 6, 1, 6, 14, "2")
		7:                                          # 内角：左上凹角
			fill_rect(c, 0, 0, 5, 5, "1")
			hline(c, 0, 4, 5, "2")
			vline(c, 5, 0, 4, "2")
			line(c, 9, 6, 13, 12, "2")
	_put_tile(sheet, idx, c)


# --- 木地板 ---
func _tile_wood_floor(sheet: Image, idx: int, variant: int) -> void:
	var c := _t_ground("m", [["B", 26], ["b", 20]])
	if variant == 0:
		for y in range(3, 16, 5):
			hline(c, 0, 15, y, "b")
			hline(c, 0, 15, y + 1, "B")
		vline(c, 5, 0, 15, "b")
		vline(c, 11, 0, 15, "b")
	else:
		# 横纹木板
		for y in range(0, 16, 4):
			hline(c, 0, 15, y, "b")
			hline(c, 0, 15, y + 1, "B")
		vline(c, 7, 0, 15, "b")
	_put_tile(sheet, idx, c)


# --- 石砖 / 破损石砖 ---
func _tile_brick(sheet: Image, idx: int, broken: bool) -> void:
	var c := _t_ground("3", [["2", 20], ["w", 12]])
	for y in [0, 8]:
		hline(c, 0, 15, y, "2")
		hline(c, 0, 15, y + 1, "w")
	for y in [4, 12]:
		hline(c, 0, 15, y, "1")
	vline(c, 7, 0, 7, "2")
	vline(c, 3, 8, 15, "2")
	vline(c, 11, 8, 15, "2")
	if broken:
		line(c, 2, 4, 6, 7, "1")
		line(c, 10, 9, 14, 12, "1")
		noise_scatter(c, 0, 0, 16, 16, "k", 12)
	_put_tile(sheet, idx, c)


# --- 帐篷布 ---
func _tile_tent(sheet: Image, idx: int) -> void:
	var c := _t_ground("t", [["B", 24]])
	for i in 5:
		line(c, i * 4, 15, i * 4 + 8, 0, "B")
		line(c, i * 4 + 1, 15, i * 4 + 9, 0, "b")
	hline(c, 0, 15, 15, "b")
	_put_tile(sheet, idx, c)


# --- 栅栏 ---
func _tile_fence(sheet: Image, idx: int) -> void:
	var rows := PackedStringArray([
		"kkkkkkkkkkkkkkkk",
		"kmmkmmmmkmmmmkmm",
		"kBmkBmmmBkmmmBmk",
		"kkkkkkkkkkkkkkkk",
		"kmmkmmmmkmmmmkmm",
		"kBmkBmmmBkmmmBmk",
		"kkkkkkkkkkkkkkkk",
	])
	_put_tile(sheet, idx, _t_object(rows, 0, 4, "G", [["g", 24], ["l", 12]]))


# --- 木桥（横 / 竖）---
func _tile_bridge(sheet: Image, idx: int, vertical: int) -> void:
	var c := _t_ground("m", [["B", 30], ["b", 16]])
	if vertical == 0:
		for y in range(0, 16, 4):
			hline(c, 0, 15, y, "b")
			hline(c, 0, 15, y + 1, "B")
		vline(c, 0, 0, 15, "b")
		vline(c, 15, 0, 15, "b")
	else:
		for x in range(0, 16, 4):
			vline(c, x, 0, 15, "b")
			vline(c, x + 1, 0, 15, "B")
		hline(c, 0, 15, 0, "b")
		hline(c, 0, 15, 15, "b")
	_put_tile(sheet, idx, c)


# --- 紫纹祭坛地砖 ---
func _tile_altar(sheet: Image, idx: int) -> void:
	var c := _t_ground("2", [["1", 26], ["3", 14]])
	stroke_rect(c, 2, 2, 12, 12, "p")
	stroke_rect(c, 3, 3, 10, 10, "n")
	blit_ascii(c, PackedStringArray(["kppk", "pWWp", "kppk"]), 6, 6)
	_put_tile(sheet, idx, c)


# --- 魔法阵中心 / 边缘 ---
func _tile_magic_circle(sheet: Image, idx: int, center: bool) -> void:
	var c := _t_ground("1", [["2", 24], ["p", 12]])
	if center:
		stroke_ellipse(c, 8, 8, 6, 6, "p")
		# 六芒星
		for i in 3:
			var ang := float(i) * PI / 3.0
			line(c,
				8 + int(round(5.0 * cos(ang))), 8 + int(round(5.0 * sin(ang))),
				8 + int(round(5.0 * cos(ang + 2.0))), 8 + int(round(5.0 * sin(ang + 2.0))), "P")
		blit_ascii(c, PackedStringArray(["PWP", "WPW", "PWP"]), 7, 7)
	else:
		stroke_ellipse(c, 8, 8, 9, 9, "p")
		stroke_ellipse(c, 8, 8, 8, 8, "P")
		hline(c, 0, 15, 0, "p")
		hline(c, 0, 15, 15, "p")
	_put_tile(sheet, idx, c)


# --- 藤蔓地面 ---
func _tile_vine(sheet: Image, idx: int) -> void:
	var c := _t_ground("G", [["g", 26], ["l", 12]])
	for i in 3:
		var x := 2 + i * 5
		for y in 16:
			px(c, x + int(round(1.5 * sin(float(y) * 0.6 + float(i)))), y, "g")
			px(c, x + 1 + int(round(1.5 * sin(float(y) * 0.6 + float(i)))), y, "l")
	_put_tile(sheet, idx, c)


# --- 落叶地面 ---
func _tile_leaves(sheet: Image, idx: int) -> void:
	var c := _t_ground("B", [["b", 24], ["t", 16]])
	for i in 10:
		var x := rng.randi_range(1, 13)
		var y := rng.randi_range(1, 13)
		blit_ascii(c, PackedStringArray([".o.", "oyo", ".o."]), x, y)
	_put_tile(sheet, idx, c)


# --- 深坑 ---
func _tile_pit(sheet: Image, idx: int) -> void:
	var c := _t_ground("1", [["k", 30], ["2", 12]])
	hline(c, 0, 15, 0, "3")
	hline(c, 0, 15, 1, "2")
	fill_rect(c, 3, 4, 10, 9, "k")
	_put_tile(sheet, idx, c)


# --- 苔藓岩壁 ---
func _tile_moss_wall(sheet: Image, idx: int) -> void:
	var c := _t_ground("3", [["2", 26], ["1", 14]])
	for i in 5:
		var x := rng.randi_range(0, 14)
		var y := rng.randi_range(0, 12)
		fill_ellipse(c, x, y, rng.randi_range(1, 3), rng.randi_range(1, 2), "G")
		px(c, x, y, "l")
	hline(c, 0, 15, 0, "2")
	hline(c, 0, 15, 15, "1")
	_put_tile(sheet, idx, c)


# --- 洞口 ---
func _tile_cave(sheet: Image, idx: int) -> void:
	var c := _t_ground("3", [["2", 26], ["1", 14]])
	fill_ellipse(c, 8, 11, 6, 6, "k")
	for y in 16:
		for x in 16:
			if c.get_pixel(x, y) == _col(P["k"]) and y < 6:
				px(c, x, y, "3")
	fill_ellipse(c, 8, 12, 6, 5, "k")
	stroke_ellipse(c, 8, 10, 6, 6, "2")
	_put_tile(sheet, idx, c)


# --- 地刺（金属 / 骨刺两种朝向）---
func _tile_spikes(sheet: Image, idx: int, bone: bool) -> void:
	var base_key := "1" if bone else "2"
	var tip_key := "w" if bone else "3"
	var c := _t_ground(base_key, [["k", 26], ["2", 12]])
	var rows := PackedStringArray([
		".k...k...k..",
		"kwk.kwk.kwk.",
		"kwk.kwk.kwk.",
		"k" + tip_key + "k.k" + tip_key + "k.k" + tip_key + "k.",
		"k" + tip_key + tip_key + "kk" + tip_key + tip_key + "kk" + tip_key + tip_key + "k.",
		"kkkkkkkkkkkk",
	])
	var obj := _new_img(16, 16)
	blit_ascii(obj, rows, 0, 9)
	blit_over(c, obj, 0, 0)
	if bone:
		hline(c, 0, 15, 15, "1")
	_put_tile(sheet, idx, c)


# --- 宝箱底座 ---
func _tile_chest_base(sheet: Image, idx: int) -> void:
	var c := _t_ground("2", [["1", 24], ["3", 12]])
	fill_rect(c, 2, 6, 12, 8, "3")
	fill_rect(c, 3, 7, 10, 6, "2")
	stroke_rect(c, 2, 6, 12, 8, "w")
	for x in range(3, 13, 3):
		vline(c, x, 8, 12, "1")
	_put_tile(sheet, idx, c)


# --- 传送台 ---
func _tile_teleport(sheet: Image, idx: int) -> void:
	var c := _t_ground("2", [["1", 20], ["3", 14]])
	fill_rect(c, 1, 1, 14, 14, "3")
	fill_rect(c, 2, 2, 12, 12, "1")
	stroke_ellipse(c, 8, 8, 6, 6, "N")
	stroke_ellipse(c, 8, 8, 4, 4, "c")
	fill_ellipse(c, 8, 8, 2, 2, "W")
	for i in 4:
		px(c, 8 + int(round(5.0 * cos(float(i) * PI / 2.0))), 8 + int(round(5.0 * sin(float(i) * PI / 2.0))), "c")
	_put_tile(sheet, idx, c)
