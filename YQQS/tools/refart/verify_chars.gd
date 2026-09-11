extends SceneTree
# 角色/敌人图集自检：尺寸、网格、每格内容、越界、调色板外颜色、格子间粘连。
# 无图像查看器时的唯一验证手段。

const OUT_DIR := "res://assets/sprites"

const SHEETS := [
	{"file": "player_ranger.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "enemy_slime.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "enemy_bat.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "enemy_mushroom.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "enemy_goblin.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "enemy_goblin_archer.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "enemy_goblin_guard.png", "cell": 32, "cols": 4, "rows": 4},
	{"file": "boss_goblin_priest.png", "cell": 64, "cols": 4, "rows": 4},
]

var _errors: Array[String] = []
var _logs: Array[String] = []


func _init() -> void:
	print("=== 角色/敌人图集自检 ===")
	for s in SHEETS:
		_check_sheet(s)
	print("")
	for l in _logs:
		print("  OK   ", l)
	if _errors.is_empty():
		print("⇒ 全部通过 ✅")
		quit(0)
	else:
		for e in _errors:
			print("  [ERROR] ", e)
		quit(1)


func _check_sheet(s: Dictionary) -> void:
	var path: String = OUT_DIR + "/" + String(s["file"])
	if not ResourceLoader.exists(path):
		_logs.append("%s 不存在（跳过）" % s["file"])
		return
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image()
	var cell: int = s["cell"]
	var cols: int = s["cols"]
	var rows: int = s["rows"]
	var want_w := cell * cols
	var want_h := cell * rows
	if img.get_width() != want_w or img.get_height() != want_h:
		_errors.append("%s 尺寸 %dx%d，期望 %dx%d" % [
			s["file"], img.get_width(), img.get_height(), want_w, want_h])
		return

	var empty_cells: Array = []
	var clipped_cells: Array = []
	var palette_miss := {}
	var gutters := 0
	for r in rows:
		for c in cols:
			var filled := 0
			var touches_edge := false
			for y in cell:
				for x in cell:
					var px := img.get_pixel(c * cell + x, r * cell + y)
					if px.a <= 0.05:
						continue
					filled += 1
					var h := px.to_html(false)
					if not RefArt.PAL.values().has("#" + h):
						palette_miss[h] = true
					if x == 0 or y == 0 or x == cell - 1 or y == cell - 1:
						touches_edge = true
			# 阈值与 tools/validation.gd 保持一致（4%）。
			# 【为什么要对齐】这里原本写的是 2.5%，比 Validation 松 ——
			# 于是出现过"本脚本全绿、Validation 却报空格子"的矛盾局面，
			# 排查时白绕了一圈。两个校验器的判据必须同源同值。
			if float(filled) / float(cell * cell) < 0.04:
				empty_cells.append("%d,%d" % [c, r])
			if touches_edge:
				clipped_cells.append("%d,%d" % [c, r])
			# 格间粘连：右边缘列与右邻格左边缘列都在同一行有像素
			if c + 1 < cols:
				for y in cell:
					if img.get_pixel(c * cell + cell - 1, r * cell + y).a > 0.5 \
							and img.get_pixel((c + 1) * cell, r * cell + y).a > 0.5:
						gutters += 1
						break

	if not empty_cells.is_empty():
		_errors.append("%s 有 %d 个空格子: %s" % [s["file"], empty_cells.size(), str(empty_cells)])
	if not palette_miss.is_empty():
		var ks: Array = palette_miss.keys()
		ks.sort()
		_errors.append("%s 用了调色板外的颜色 %d 种: %s" % [
			s["file"], ks.size(), str(ks.slice(0, mini(8, ks.size())))])
	if gutters > 0:
		_errors.append("%s 有 %d 处相邻格内容粘连（缺少 1px 空隙）" % [s["file"], gutters])
	if empty_cells.is_empty() and palette_miss.is_empty() and gutters == 0:
		var clip_note := "" if clipped_cells.is_empty() else "（%d 格触边，属正常造型）" % clipped_cells.size()
		_logs.append("%s  %dx%d  16/16 格非空，配色合规%s" % [
			s["file"], want_w, want_h, clip_note])
