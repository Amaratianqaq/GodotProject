class_name HealthBar
extends Node2D
## 敌人头顶血条 / 精英与 BOSS 的长血条。
##
## 【框架约束】
## 玩家血条在 HUD（CanvasLayer）里，**不** 使用本类；
## 本类只用于世界内的敌人。

@export var width: float = 20.0
@export var height: float = 3.0
@export var show_when_full: bool = false
@export var y_offset: float = -20.0

var _ratio: float = 1.0
var _armor_ratio: float = 0.0
var _flash: float = 0.0
var _visible: bool = false

const BG_COLOR := Color(0.05, 0.04, 0.12, 0.85)
const HP_COLOR := Color("#d94a4a")
const HP_COLOR_ELITE := Color("#f2a13b")
const HP_COLOR_BOSS := Color("#b44ac9")
const ARMOR_COLOR := Color("#4a8fd9")
const BORDER_COLOR := Color(0.02, 0.02, 0.06, 1.0)

var hp_color: Color = HP_COLOR


func setup(p_width: float, p_color: Color, always_visible: bool = false) -> void:
	width = p_width
	hp_color = p_color
	show_when_full = always_visible
	queue_redraw()


func set_ratios(hp_ratio: float, armor_ratio: float) -> void:
	var nhp := clampf(hp_ratio, 0.0, 1.0)
	if not is_equal_approx(nhp, _ratio):
		_flash = 0.12
	_ratio = nhp
	_armor_ratio = clampf(armor_ratio, 0.0, 1.0)
	_visible = show_when_full or _ratio < 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


func _draw() -> void:
	if not _visible:
		return
	var w := width
	var h := height
	var origin := Vector2(-w * 0.5, y_offset)
	# 边框
	draw_rect(Rect2(origin - Vector2.ONE, Vector2(w + 2, h + 2)), BORDER_COLOR, true)
	# 底
	draw_rect(Rect2(origin, Vector2(w, h)), BG_COLOR, true)
	# 护甲（铺在血条上方一层薄条）
	if _armor_ratio > 0.0:
		draw_rect(Rect2(origin, Vector2(w * _armor_ratio, h * 0.45)), ARMOR_COLOR, true)
	# 生命
	var hp_w := w * _ratio
	if hp_w > 0.0:
		draw_rect(Rect2(origin, Vector2(hp_w, h)), hp_color, true)
		# 高光
		draw_rect(Rect2(origin + Vector2(0, 0), Vector2(hp_w, 1.0)),
			Color(1, 1, 1, 0.35), true)
	# 受击闪白
	if _flash > 0.0:
		draw_rect(Rect2(origin, Vector2(w, h)), Color(1, 1, 1, _flash * 4.0), true)
