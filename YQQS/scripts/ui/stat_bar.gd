class_name StatBar
extends Control
## 像素风数据条（生命 / 护甲 / 能量 / 经验 / BOSS 血条 / 装填进度）。
##
## 【框架约束】
## 所有条形显示统一用本控件，禁止在界面里用 ProgressBar + 主题 hack，
## 因为像素风需要精确的 1px 描边与「延迟残影」反馈。

@export var fill_color: Color = Color("#d94a4a")
@export var bg_color: Color = Color("#0d0b1f")
@export var border_color: Color = Color("#6b4a2f")
## 数值文本（留空则不显示）
@export var text: String = ""
@export var text_color: Color = Color("#e8e4dc")
@export var text_size: int = UIKit.FS_TINY
## 是否显示延迟残影（受伤时掉血更明显）
@export var show_ghost: bool = true
## 每秒残影追赶速度（比例）
@export var ghost_speed: float = 1.6
## 是否垂直填充（技能冷却用）
@export var vertical: bool = false
## 边框宽度
@export var border_width: int = 1

var ratio: float = 1.0
var _ghost: float = 1.0
var _flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_ratio(v: float, flash: bool = false) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if nv < ratio and show_ghost:
		_flash = 0.18
	ratio = nv
	if _ghost < ratio:
		_ghost = ratio
	queue_redraw()


func set_bar_colors(fill: Color, bg: Color = Color("#0d0b1f"), border: Color = Color("#6b4a2f")) -> void:
	fill_color = fill
	bg_color = bg
	border_color = border
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	if _ghost > ratio:
		_ghost = maxf(ratio, _ghost - ghost_speed * delta)
		dirty = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	# 底
	draw_rect(Rect2(Vector2.ZERO, s), bg_color, true)
	# 残影
	if show_ghost and _ghost > ratio:
		if vertical:
			var gh := s.y * _ghost
			draw_rect(Rect2(0, s.y - gh, s.x, gh), Color(1, 1, 1, 0.22), true)
		else:
			draw_rect(Rect2(0, 0, s.x * _ghost, s.y), Color(1, 1, 1, 0.22), true)
	# 填充
	if vertical:
		var fh := s.y * ratio
		draw_rect(Rect2(0, s.y - fh, s.x, fh), fill_color, true)
		if fh > 1.0:
			draw_rect(Rect2(0, s.y - fh, s.x, 1.0), fill_color.lightened(0.45), true)
	else:
		var fw := s.x * ratio
		draw_rect(Rect2(0, 0, fw, s.y), fill_color, true)
		if fw > 1.0:
			draw_rect(Rect2(0, 0, fw, maxf(1.0, s.y * 0.28)), fill_color.lightened(0.35), true)
	# 受击闪白
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, _flash * 3.2), true)
	# 边框
	if border_width > 0:
		draw_rect(Rect2(Vector2.ZERO, s), border_color, false, float(border_width))
	# 文本
	if text != "":
		var font := ThemeDB.fallback_font
		if font == null:
			return
		var fs := text_size
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2((s.x - ts.x) * 0.5, (s.y + ts.y * 0.62) * 0.5)
		# 描边
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				draw_string(font, pos + Vector2(ox, oy), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.04, 0.12, 0.95))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
