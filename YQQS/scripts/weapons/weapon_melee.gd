class_name WeaponMelee
extends WeaponBase
## 默认近战武器实现（挥砍扇形判定）。
##
## 【框架约束】
## 近战走「攻击盒开关」模型：activate(挥砍时长) → HitboxComponent 打开，
## 到期自动关闭。同一次挥砍内同一目标只结算一次（HitboxComponent 去重）。
## 第一阶段 12 把武器里的剑/斧/长枪/法杖（挥击形态）都走本实现。

var _swing_visual: Polygon2D = null
var _swing_tween: Tween = null


func _on_setup_done() -> void:
	_build_swing_visual()


func _build_swing_visual() -> void:
	if _swing_visual != null:
		return
	_swing_visual = Polygon2D.new()
	_swing_visual.name = "SwingArc"
	_swing_visual.visible = false
	_swing_visual.color = Color(1, 1, 1, 0.35)
	_swing_visual.z_index = 2
	var pts := PackedVector2Array()
	var arc := deg_to_rad(data.melee_arc_deg if data else 90.0)
	var r := data.melee_range if data else 20.0
	var steps := 10
	for i in steps + 1:
		var a := -arc * 0.5 + arc * (float(i) / float(steps))
		pts.append(Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2.ZERO)
	_swing_visual.polygon = pts
	add_child(_swing_visual)


func _do_fire() -> void:
	if data == null:
		return
	var crit := roll_crit()
	var info := build_damage(data.damage, crit)
	info.knockback = aim_direction * data.knockback
	info.tags.append("melee")
	_activate_hitbox(info, crit)
	_play_swing_visual()
	_play_fire_sfx()


func _activate_hitbox(info: DamageInfo, crit: bool) -> void:
	var hb := _get_melee_hitbox()
	if hb == null:
		# 没有攻击盒时降级：直接对扇形内敌人做一次范围判定
		_fallback_arc_damage(info)
		return
	hb.set_faction(_faction())
	hb.knockback_force = data.knockback
	hb.hitstop = 0.05
	# 按武器数据调整碰撞盒尺寸与偏移（用矩形近似扇形）
	_shape_melee_hitbox(hb)
	# 攻击盒朝向跟随瞄准方向
	hb.rotation = aim_direction.angle()
	hb.activate(data.melee_swing_time, info.amount, crit)


func _shape_melee_hitbox(hb: HitboxComponent) -> void:
	var shape_node := hb.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var arc := deg_to_rad(clampf(data.melee_arc_deg, 10.0, 350.0))
	var reach := maxf(6.0, data.melee_range)
	var height := maxf(6.0, 2.0 * reach * sin(arc * 0.5))
	var rect := RectangleShape2D.new()
	rect.size = Vector2(reach, height)
	shape_node.shape = rect
	shape_node.position = Vector2(reach * 0.5, 0.0)


func _fallback_arc_damage(info: DamageInfo) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var group := &"enemies" if _faction() == GameEnums.Faction.PLAYER else &"players"
	var half := deg_to_rad(data.melee_arc_deg) * 0.5
	for n in NodeUtils.all_in_radius(tree, group, global_position, data.melee_range + 8.0):
		var to := (n.global_position - global_position).normalized()
		if to.dot(aim_direction) < cos(half):
			continue
		var hb := n.find_child("Hurtbox", true, false) as HurtboxComponent
		if hb:
			hb.receive_hit(info.duplicate_info())


func _play_swing_visual() -> void:
	if _swing_visual == null:
		return
	_swing_visual.visible = true
	_swing_visual.rotation = aim_direction.angle() - deg_to_rad(data.melee_arc_deg) * 0.5
	_swing_visual.scale = Vector2(0.7, 0.7)
	_swing_visual.modulate.a = 0.6
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	_swing_tween.tween_property(_swing_visual, "rotation",
		aim_direction.angle() + deg_to_rad(data.melee_arc_deg) * 0.5, data.melee_swing_time)
	_swing_tween.tween_property(_swing_visual, "scale", Vector2.ONE * 1.15, data.melee_swing_time)
	_swing_tween.tween_property(_swing_visual, "modulate:a", 0.0, data.melee_swing_time)
	_swing_tween.chain().tween_callback(func() -> void:
		if _swing_visual:
			_swing_visual.visible = false)
