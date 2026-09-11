extends SceneTree
# 角色图集的**落地检查**：每格内容在 32x32 里的垂直位置。
#
# 【为什么查这个】2.5D 里精灵的锚点在脚下（Actor 的碰撞体原点在地面平面），
# 所以每格内容的**底部**应当贴近格子下缘。如果内容整体偏高，
# 角色会看着"飘在空中"；如果超出格子，会被静默裁掉（RefArt.blit 越界安全，
# 不报错）—— 那种情况最难发现。

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


func _init() -> void:
	print("=== 角色图集落地检查（内容在格内的垂直范围）===")
	for s in SHEETS:
		_report(s)
	quit(0)


func _report(s: Dictionary) -> void:
	var path: String = OUT_DIR + "/" + String(s["file"])
	if not ResourceLoader.exists(path):
		return
	var img: Image = load(path).get_image()
	var cell: int = s["cell"]
	var cols: int = s["cols"]
	var rows: int = s["rows"]
	print("")
	print("%s  (%dpx 格)" % [s["file"], cell])
	print("  帧号 内容行范围  高  距下缘  水平范围")
	for r in rows:
		for c in cols:
			var miny := cell
			var maxy := -1
			var minx := cell
			var maxx := -1
			for y in cell:
				for x in cell:
					if img.get_pixel(c * cell + x, r * cell + y).a > 0.05:
						miny = mini(miny, y)
						maxy = maxi(maxy, y)
						minx = mini(minx, x)
						maxx = maxi(maxx, x)
			var idx := r * cols + c
			if maxy < 0:
				print("  %2d   （空）" % idx)
				continue
			print("  %2d   %2d..%-2d    %2d   %d      %2d..%-2d" % [
				idx, miny, maxy, maxy - miny + 1, cell - 1 - maxy, minx, maxx])
