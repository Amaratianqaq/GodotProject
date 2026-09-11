extends SceneTree
# =============================================================================
#  gen_vfx.gd —— 特效序列图生成器（《元气骑士前传》风格参考素材）
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/gen_vfx.gd
#
#  产出（尺寸与 docs/10 §3.5 契约一致）：
#    vfx_hit_spark.png      96x16   16px x 6 帧  命中火花（亮→炸开→余烬）
#    vfx_muzzle_flash.png   96x16   16px x 6 帧  枪口闪光（向右喷）
#    vfx_petal.png          64x16   8px  x 8 帧  樱花花瓣爆散
#    vfx_orb.png            64x16   16px x 4 帧  魔法弹（内部旋流，剪影不变）
#    vfx_arrow.png          48x16   16px x 3 帧  箭（带拖尾，越飞越长）
#
#  【为什么要拆成"帧序列图"】旧实现里命中火花 / 枪口闪光只是 props.png 里的
#  **单张静态图**，靠代码每帧改 scale/rotation 硬凑动感。
#  序列图能让光效本身有形状变化（星形→四瓣→余烬），这是"打击感"的主要来源。
#
#  【画帧序列的三条纪律】
#   1. 每帧尺寸必须完全一致，且内容**围绕同一个中心**生长/收缩，
#      否则播放时特效会"跳一下"。
#   2. 帧与帧之间要明显不同（首帧极小、中段最大、末帧几乎消失），
#      否则看不出是动画。
#   3. 允许留白，但**不能全空** —— 最后一帧也要有几个像素，
#      空帧会被校验器当成"缺素材"（这个坑在 BOSS 死亡帧上踩过）。
# =============================================================================

const OUT_DIR := "res://assets/sprites"


func _init() -> void:
	print("=== 特效序列图生成 ===")
	RefArt.reset_stats()
	var dir := ProjectSettings.globalize_path(OUT_DIR)

	_gen_hit_spark(dir)
	_gen_muzzle_flash(dir)
	_gen_petal(dir)
	_gen_orb(dir)
	_gen_arrow(dir)

	RefArt.report("特效")
	quit(0)


# =============================================================================
#  工具
# =============================================================================

## 按帧尺寸建序列图并逐帧贴入。
## cell_w/cell_h 分开传：花瓣是 8px 格，但整张表按契约高 16（上下留白），
## 所以"帧宽"和"画布高"不是同一个值 —— 用单一 cell 参数会得到 64x8。
func _sheet(frames: Array, cell_w: int, cell_h := 0) -> Image:
	var ch := cell_h if cell_h > 0 else cell_w
	var img := RefArt.new_img(cell_w * frames.size(), ch)
	for i in frames.size():
		var f: Image = frames[i]
		var dy := (ch - f.get_height()) / 2
		RefArt.blit_img(img, f, i * cell_w, dy)
	return img


## 四角星芒：r 为半径，key 为颜色。以 (cx,cy) 为中心，四个尖角 + 每 45° 收窄。
func _star(img: Image, cx: float, cy: float, r: float, key: String, thin: float) -> void:
	var steps := int(r * 8.0) + 8
	for i in steps + 1:
		var t := float(i) / float(steps)
		var ang := t * TAU
		# 星形极坐标：r * (1 + k*cos(4θ)) / (1+k)
		var k := 3.0
		var rr := r * (1.0 + k * cos(4.0 * ang)) / (1.0 + k)
		rr = maxf(rr, thin)
		var x := int(roundf(cx + cos(ang) * rr))
		var y := int(roundf(cy + sin(ang) * rr))
		RefArt.px(img, x, y, key)
	# 实心内芯
	RefArt.disc(img, cx, cy, maxf(r * 0.35, 0.8), key)


# =============================================================================
#  vfx_hit_spark.png —— 6 帧
# =============================================================================

func _gen_hit_spark(dir: String) -> void:
	var C := 16
	var frames: Array = []
	# 帧 0：极小亮芯
	var f0 := RefArt.new_img(C, C)
	RefArt.disc(f0, 8.0, 8.0, 2.0, "W")
	frames.append(f0)
	# 帧 1：白色星芒展开
	var f1 := RefArt.new_img(C, C)
	_star(f1, 8.0, 8.0, 5.0, "W", 1.0)
	frames.append(f1)
	# 帧 2：最宽，橙色边
	var f2 := RefArt.new_img(C, C)
	_star(f2, 8.0, 8.0, 7.0, "O", 1.5)
	_star(f2, 8.0, 8.0, 3.0, "W", 1.0)
	RefArt.px(f2, 1, 8, "o")
	RefArt.px(f2, 14, 8, "o")
	RefArt.px(f2, 8, 1, "o")
	RefArt.px(f2, 8, 14, "o")
	frames.append(f2)
	# 帧 3：塌缩，橙红
	var f3 := RefArt.new_img(C, C)
	_star(f3, 8.0, 8.0, 5.0, "o", 1.5)
	RefArt.disc(f3, 8.0, 8.0, 2.0, "R")
	frames.append(f3)
	# 帧 4：余烬四散
	var f4 := RefArt.new_img(C, C)
	for p in [Vector2i(3, 4), Vector2i(12, 5), Vector2i(4, 12), Vector2i(11, 11),
			Vector2i(8, 3), Vector2i(8, 13)]:
		RefArt.px(f4, p.x, p.y, "O")
		RefArt.px(f4, p.x, p.y + 1, "r")
	frames.append(f4)
	# 帧 5：将灭的余烬。
	# 【注意】这一帧必须**看得见**（不是留白）：
	#   Validation 要求每个被引用的格子至少 4% 实心，而 16x16 的 4% ≈ 10 像素。
	#   早先只点了 3 个像素 → 被当成"空素材"拒掉（vfx_hit_spark 帧 5 报空格子）。
	#   顺便，动画的最后一帧本来就该是"暗淡但还在"的余烬，而不是凭空消失。
	var f5 := RefArt.new_img(C, C)
	for p in [Vector2i(3, 3), Vector2i(4, 12), Vector2i(11, 6), Vector2i(12, 12),
			Vector2i(7, 9), Vector2i(9, 10), Vector2i(2, 8), Vector2i(13, 4),
			Vector2i(6, 13), Vector2i(10, 3), Vector2i(5, 6), Vector2i(11, 9)]:
		RefArt.px(f5, p.x, p.y, "r")
	frames.append(f5)
	RefArt.save(_sheet(frames, C), dir, "vfx_hit_spark.png")


# =============================================================================
#  vfx_muzzle_flash.png —— 6 帧，向右喷
# =============================================================================

func _gen_muzzle_flash(dir: String) -> void:
	var C := 16
	var frames: Array = []
	# 帧 0：贴枪口的小亮芯（起点固定在左侧中央，方便对齐枪管）
	var f0 := RefArt.new_img(C, C)
	RefArt.disc(f0, 4.0, 8.0, 2.0, "W")
	frames.append(f0)
	# 帧 1：四芒
	var f1 := RefArt.new_img(C, C)
	_star(f1, 5.0, 8.0, 4.0, "Y", 1.0)
	frames.append(f1)
	# 帧 2：最宽六瓣
	var f2 := RefArt.new_img(C, C)
	_star(f2, 6.0, 8.0, 7.0, "O", 1.2)
	_star(f2, 5.0, 8.0, 3.0, "Y", 1.0)
	RefArt.px(f2, 13, 8, "o")
	frames.append(f2)
	# 帧 3：裂成火舌
	var f3 := RefArt.new_img(C, C)
	RefArt.line(f3, 4, 8, 12, 4, "o")
	RefArt.line(f3, 4, 8, 13, 8, "O")
	RefArt.line(f3, 4, 8, 12, 12, "o")
	RefArt.disc(f3, 4.0, 8.0, 2.0, "Y")
	frames.append(f3)
	# 帧 4：火星四溅。注意 16x16 的 4% 底线 ≈ 10 像素，别画太少
	var f4 := RefArt.new_img(C, C)
	for p in [Vector2i(6, 4), Vector2i(7, 5), Vector2i(9, 6), Vector2i(10, 7),
			Vector2i(7, 11), Vector2i(8, 12), Vector2i(11, 10), Vector2i(12, 5),
			Vector2i(5, 7), Vector2i(4, 10), Vector2i(9, 9), Vector2i(6, 8)]:
		RefArt.px(f4, p.x, p.y, "o")
	frames.append(f4)
	# 帧 5：将灭的火星（同样必须 ≥4% 实心，见上面命中火花的说明）
	var f5 := RefArt.new_img(C, C)
	for p in [Vector2i(4, 6), Vector2i(5, 9), Vector2i(7, 5), Vector2i(8, 8),
			Vector2i(9, 11), Vector2i(6, 12), Vector2i(10, 6), Vector2i(3, 11),
			Vector2i(11, 9), Vector2i(7, 10), Vector2i(12, 7), Vector2i(5, 4)]:
		RefArt.px(f5, p.x, p.y, "r")
	RefArt.px(f5, 4, 8, "o")
	frames.append(f5)
	RefArt.save(_sheet(frames, C), dir, "vfx_muzzle_flash.png")


# =============================================================================
#  vfx_petal.png —— 8 帧，8x8
# =============================================================================

## 一片小花瓣（8x8 格内）
func _petal(img: Image, cx: float, cy: float, h: bool) -> void:
	if h:
		RefArt.hline(img, int(cx), int(cx) + 2, int(cy), "K")
		RefArt.px(img, int(cx) + 1, int(cy) - 1, "W")
	else:
		RefArt.vline(img, int(cx), int(cy), int(cy) + 2, "K")
		RefArt.px(img, int(cx) - 1, int(cy) + 1, "W")


func _gen_petal(dir: String) -> void:
	var C := 8
	var frames: Array = []
	# 8 帧：从中心一簇 → 向外散开 → 只剩两片
	#
	# 【为什么帧 0/1 就画了 3~4 片、末帧还留 2 片】
	# 8x8 的格子只有 64 像素，Validation 的 4% 底线 ≈ 3 像素。
	# 如果按"从 1 片开始、到 0 片结束"来画，头尾都会被判成空素材。
	# 而且 8px 的花瓣本来就该成簇出现（单瓣在 8px 里几乎看不见）。
	var layout := [
		[[4, 4, 1], [4, 3, 0], [3, 4, 1], [5, 5, 0], [5, 3, 1], [3, 5, 0]],
		[[4, 4, 1], [5, 3, 0], [3, 5, 1], [5, 5, 0], [2, 4, 1], [6, 4, 0], [4, 2, 1]],
		[[3, 2, 1], [6, 3, 0], [2, 5, 1], [6, 6, 0], [4, 4, 1], [1, 3, 0]],
		[[2, 1, 1], [7, 3, 0], [1, 6, 1], [6, 7, 0], [4, 3, 1], [3, 5, 0]],
		[[1, 1, 1], [7, 2, 0], [0, 6, 1], [6, 7, 0], [3, 5, 1], [5, 4, 0]],
		[[1, 0, 1], [7, 1, 0], [0, 7, 1], [5, 4, 0], [3, 3, 1]],
		[[0, 0, 1], [7, 0, 0], [4, 6, 1], [2, 3, 0], [6, 5, 1]],
		[[1, 7, 1], [6, 1, 0], [3, 3, 1], [5, 5, 0], [7, 6, 1]],
	]
	for li in layout.size():
		var f := RefArt.new_img(C, C)
		for p in layout[li]:
			_petal(f, float(p[0]), float(p[1]), int(p[2]) == 1)
		frames.append(f)
	# 帧是 8x8，但契约要求整张表 64x16（上下各留 4px 空白）——
	# 这样小花瓣在 16px 的特效容器里也是垂直居中的。
	RefArt.save(_sheet(frames, C, 16), dir, "vfx_petal.png")


# =============================================================================
#  vfx_orb.png —— 4 帧，16x16（剪影不变，只转内部旋流）
# =============================================================================

func _gen_orb(dir: String) -> void:
	var C := 16
	var frames: Array = []
	# 外部轮廓 4 帧完全一致，只有内部两条弧在转
	for phase in 4:
		var f := RefArt.new_img(C, C)
		RefArt.disc(f, 8.0, 8.0, 6.0, "P")          # 深紫核心
		RefArt.disc(f, 8.0, 8.0, 5.0, "p")          # 紫中环
		# 内部旋流：两条弧，按 phase 旋转
		for i in 40:
			var t := float(i) / 40.0
			var ang := t * TAU + float(phase) * (TAU / 4.0)
			var r := 2.0 + 2.5 * sin(t * PI)
			var x := int(roundf(8.0 + cos(ang) * r))
			var y := int(roundf(8.0 + sin(ang) * r))
			RefArt.px(f, x, y, "K")
		# 左上高光（固定，保持剪影与光源一致）
		RefArt.px(f, 5, 4, "W")
		RefArt.px(f, 6, 4, "K")
		RefArt.px(f, 4, 5, "K")
		# 环绕的小亮点：位置随 phase 变，做出"在转"的感觉
		for k in 3:
			var a2 := float(phase) * (TAU / 4.0) + float(k) * (TAU / 3.0)
			var px_ := int(roundf(8.0 + cos(a2) * 7.0))
			var py_ := int(roundf(8.0 + sin(a2) * 7.0))
			RefArt.px(f, px_, py_, "W")
		frames.append(f)
	RefArt.save(_sheet(frames, C), dir, "vfx_orb.png")


# =============================================================================
#  vfx_arrow.png —— 3 帧，16x16（拖尾越来越长）
# =============================================================================

func _gen_arrow(dir: String) -> void:
	var C := 16
	var frames: Array = []
	for phase in 3:
		var f := RefArt.new_img(C, C)
		var tail: int = [0, 4, 8][phase]
		# 箭杆：向右，箭尖在 x=14
		RefArt.line(f, 4, 8, 12, 8, "B")
		RefArt.line(f, 4, 7, 12, 7, "t")
		# 箭头
		RefArt.line(f, 12, 5, 15, 8, "7")
		RefArt.line(f, 12, 8, 15, 8, "7")
		RefArt.line(f, 12, 11, 15, 8, "7")
		RefArt.line(f, 12, 6, 14, 8, "w")
		RefArt.line(f, 12, 10, 14, 8, "6")
		# 尾羽
		RefArt.line(f, 4, 6, 2, 8, "w")
		RefArt.line(f, 4, 10, 2, 8, "w")
		# 拖尾：动的速度线，越长表示飞得越快
		for i in tail:
			var x := 3 - i
			if x < 0:
				break
			RefArt.line(f, x, 7, x, 9, "W")
		frames.append(f)
	RefArt.save(_sheet(frames, C), dir, "vfx_arrow.png")
