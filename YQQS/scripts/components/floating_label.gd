class_name FloatingLabel
extends Node2D
## 飘字（伤害数字 / 拾取提示 / 暴击）。
##
## 【框架约束】
## 1. 飘字 **不参与物理**，不碰撞，z_index 固定高位。
## 2. 所有飘字通过 CombatFx 静态方法生成，禁止在业务代码里手搓 Label。
## 3. 飘字数量上限由 CombatFx.MAX_FLOATING 控制，防止刷屏掉帧。

var label: Label = null
var _velocity := Vector2(0, -26)
var _life := 0.0
var _max_life := 0.75


static func spawn(
	parent: Node,
	pos: Vector2,
	text: String,
	color: Color = Color.WHITE,
	font_size: int = 8,
	crit: bool = false
) -> FloatingLabel:
	if parent == null or not is_instance_valid(parent):
		return null
	var fl := FloatingLabel.new()
	fl._max_life = 0.95 if crit else 0.72
	fl._velocity = Vector2(randf_range(-9.0, 9.0), -34.0 if crit else -26.0)
	parent.add_child(fl)
	fl.global_position = pos + Vector2(randf_range(-3, 3), -2)
	fl._build(text, color, font_size, crit)
	return fl


func _build(text: String, color: Color, font_size: int, crit: bool) -> void:
	z_index = 200
	z_as_relative = false
	label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(64, 16)
	label.position = Vector2(-32, -8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.12, 1.0))
	label.add_theme_constant_override("outline_size", 3 if crit else 2)
	add_child(label)
	if crit:
		scale = Vector2(1.45, 1.45)


func _process(delta: float) -> void:
	_life += delta
	var t := _life / _max_life
	if t >= 1.0:
		queue_free()
		return
	_velocity.y += 92.0 * delta
	global_position += _velocity * delta
	if label:
		label.modulate.a = 1.0 - clampf((t - 0.55) / 0.45, 0.0, 1.0)
	if t < 0.18:
		var s := lerpf(1.5, 1.0, t / 0.18)
		if _max_life > 0.9:
			s *= 1.35
		scale = Vector2(s, s)
