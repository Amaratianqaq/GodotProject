class_name HitSpark
extends Node2D
## 命中火花 / 枪口火焰 / 通用一次性粒子精灵。
##
## 【框架约束】
## 一次性特效统一走 CombatFx.spawn_*，本类只负责自己播放完就 queue_free。

var _life := 0.0
var _max_life := 0.16
var _start_scale := 1.0
var _end_scale := 1.7
var _follow: Node2D = null
var _follow_offset := Vector2.ZERO
var _spin := 0.0
## 初速度（外部可直接设置，用于爆散粒子）
var _velocity := Vector2.ZERO
var _gravity := 0.0


static func spawn(
	parent: Node,
	pos: Vector2,
	tex: Texture2D,
	life: float = 0.16,
	start_scale: float = 1.0,
	end_scale: float = 1.7,
	color: Color = Color.WHITE,
	rotation_rad: float = -1.0
) -> HitSpark:
	if parent == null or not is_instance_valid(parent) or tex == null:
		return null
	var s := HitSpark.new()
	s._max_life = life
	s._start_scale = start_scale
	s._end_scale = end_scale
	parent.add_child(s)
	s.global_position = pos
	var sr := Sprite2D.new()
	sr.texture = tex
	sr.modulate = color
	s.add_child(sr)
	s.scale = Vector2.ONE * start_scale
	s.rotation = rotation_rad if rotation_rad >= 0.0 else randf() * TAU
	s._spin = randf_range(-2.0, 2.0)
	return s


## 跟随某个节点的特效（例如挂在投射物上的拖尾）
static func spawn_follow(
	parent: Node,
	target: Node2D,
	offset: Vector2,
	tex: Texture2D,
	life: float,
	color: Color = Color.WHITE
) -> HitSpark:
	var s := spawn(parent, target.global_position + offset, tex, life, 0.75, 0.1, color)
	if s:
		s._follow = target
		s._follow_offset = offset
	return s


func _process(delta: float) -> void:
	_life += delta
	var t := _life / _max_life
	if t >= 1.0:
		queue_free()
		return
	if _follow and is_instance_valid(_follow):
		global_position = _follow.global_position + _follow_offset
	elif _velocity != Vector2.ZERO or _gravity != 0.0:
		_velocity.y += _gravity * delta
		global_position += _velocity * delta
	scale = Vector2.ONE * lerpf(_start_scale, _end_scale, t)
	rotation += _spin * delta
	modulate.a = 1.0 - t * t
