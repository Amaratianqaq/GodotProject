class_name Projectile
extends Area2D
## 投射物 —— 所有子弹 / 箭矢 / 花瓣 / 法术弹的通用实现。
##
## 【框架约束 · 必读】
## 1. 投射物行为完全由 ProjectileData 驱动（motion / pierce / bounce / 拖尾…），
##    **不要** 为每种子弹新建一个脚本。需要全新行为时，
##    在 ProjectileData.motion 里加分支并同步更新文档。
## 2. 投射物只携带 DamageInfo 模板；每次命中都 duplicate() 后交给 Hurtbox，
##    绝不复用同一个 DamageInfo 实例。
## 3. 命中地形（WORLD / OBSTACLE 层）时按 bounce_left 决定弹射或销毁。

var data: ProjectileData = null
var direction: Vector2 = Vector2.RIGHT
var speed: float = 220.0
var info_template: DamageInfo = null
var owner_actor: Node2D = null
var faction: int = GameEnums.Faction.PLAYER

var pierce_left: int = 0
var bounce_left: int = 0
var life_left: float = 1.2
var is_dead: bool = false

var _sprite: Sprite2D = null
var _shape: CollisionShape2D = null
var _hit_ids: Dictionary = {}
var _homing_time: float = 0.0
var _wave_phase: float = 0.0
var _spawn_pos: Vector2 = Vector2.ZERO
var _trail_timer: float = 0.0
var _current_damage_mult: float = 1.0
var _trail_nodes: Array[Node] = []


func _ready() -> void:
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	_build_visual()


## 由 WeaponBase / EnemyBase 调用
func configure(
	p_info: DamageInfo,
	p_dir: Vector2,
	p_data: ProjectileData,
	p_speed: float = -1.0,
	p_owner: Node2D = null,
	p_faction: int = GameEnums.Faction.PLAYER
) -> void:
	info_template = p_info
	direction = p_dir.normalized()
	data = p_data if p_data else ProjectileData.new()
	speed = p_speed if p_speed > 0.0 else data.speed
	owner_actor = p_owner
	faction = p_faction
	pierce_left = data.pierce
	bounce_left = data.max_bounces
	life_left = data.lifetime
	_current_damage_mult = data.damage_mult
	_homing_time = data.homing_duration
	_spawn_pos = global_position
	_apply_layers()
	_build_visual()
	rotation = direction.angle() if data.rotate_to_direction else 0.0
	if data.sfx_spawn != "":
		AudioManager.play_sfx_2d(data.sfx_spawn, global_position)


func _apply_layers() -> void:
	collision_layer = Layers.PROJECTILE_LAYER
	match faction:
		GameEnums.Faction.PLAYER:
			collision_mask = Layers.PROJECTILE_MASK_VS_ENEMY
		GameEnums.Faction.ENEMY:
			collision_mask = Layers.PROJECTILE_MASK_VS_PLAYER
		_:
			collision_mask = Layers.PROJECTILE_MASK_VS_ENEMY | Layers.PROJECTILE_MASK_VS_PLAYER


func _build_visual() -> void:
	if data == null:
		return
	if _shape == null:
		_shape = CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = maxf(1.0, data.radius)
		_shape.shape = c
		add_child(_shape)
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.centered = true
		add_child(_sprite)
	# 图集贴图优先，否则用代码生成一个圆形光点
	var tex := _resolve_texture()
	if tex:
		_sprite.texture = tex
	else:
		_sprite.texture = _make_dot_texture(data.color, maxi(2, int(round(data.radius * 2.0))))
		_sprite.modulate = data.color


func _resolve_texture() -> Texture2D:
	if data == null:
		return null
	if data.sheet != "":
		return Atlas.frame(data.sheet, data.cell.x, data.cell.y)
	return null


static func _make_dot_texture(color: Color, size: int) -> Texture2D:
	var s := maxi(2, size)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(s - 1) * 0.5
	var r := c
	for y in s:
		for x in s:
			var d := Vector2(float(x) - c, float(y) - c).length()
			if d <= r + 0.35:
				var a := 1.0 if d <= r - 0.5 else 0.55
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * a))
	var tex := ImageTexture.create_from_image(img)
	return tex


# ---------------------------------------------------------------------------
# 运动
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	life_left -= delta
	if life_left <= 0.0:
		_expire()
		return
	_update_motion(delta)
	if data.trail_length > 0:
		_update_trail(delta)


func _update_motion(delta: float) -> void:
	if data.acceleration != 0.0:
		speed = maxf(0.0, speed + data.acceleration * delta)
	match data.motion:
		&"homing":
			_update_homing(delta)
		&"wave":
			_update_wave(delta)
		&"arc":
			_update_arc(delta)
		_:
			pass
	global_position += direction * speed * delta
	if data.rotate_to_direction:
		rotation = direction.angle()
	if _sprite and data.motion == &"homing":
		pass


func _update_homing(delta: float) -> void:
	if _homing_time <= 0.0:
		return
	_homing_time -= delta
	var target := _find_nearest_target()
	if target == null:
		return
	var want := (target.global_position - global_position).normalized()
	var cur := direction.angle()
	var tgt := want.angle()
	var diff := wrapf(tgt - cur, -PI, PI)
	var turn := clampf(diff, -data.homing_turn_speed * delta, data.homing_turn_speed * delta)
	direction = Vector2.RIGHT.rotated(cur + turn)


func _update_wave(delta: float) -> void:
	_wave_phase += delta * data.wave_frequency
	var perp := direction.orthogonal()
	global_position += perp * sin(_wave_phase) * data.wave_amplitude * delta


func _update_arc(delta: float) -> void:
	# 抛物：向下加速
	direction = direction.rotated(data.wave_amplitude * 0.01 * delta)


func _find_nearest_target() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var group := &"enemies" if faction == GameEnums.Faction.PLAYER else &"players"
	return NodeUtils.nearest_in_group(tree, group, global_position, 220.0)


func _update_trail(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = 0.035
	var spark := HitSpark.spawn(
		CombatFx.fx_parent(self), global_position, _resolve_texture(),
		0.18, 0.9, 0.15, data.trail_color
	)


# ---------------------------------------------------------------------------
# 命中
# ---------------------------------------------------------------------------

func _on_area_entered(area: Area2D) -> void:
	if is_dead:
		return
	var hb := HurtboxComponent.from_area(area)
	if hb == null:
		return
	if info_template and not hb.can_be_hit_by(info_template):
		return
	var key := hb.get_instance_id()
	if _hit_ids.has(key):
		return
	if not hb.is_alive():
		return
	_hit_ids[key] = true

	var info := info_template.duplicate_info() if info_template else DamageInfo.make(1.0, self, owner_actor, faction)
	info.amount *= _current_damage_mult
	info.source = self
	info.attacker = owner_actor
	info.hit_position = global_position
	info.hit_direction = direction
	if info.knockback == Vector2.ZERO:
		info.knockback = direction * 40.0

	var actual := hb.receive_hit(info)
	if actual > 0.0:
		_spawn_hit_vfx(info.hit_direction, info.crit, actual)
	if data.sfx_hit != "":
		AudioManager.play_sfx_2d(data.sfx_hit, global_position)

	# 穿透 / 销毁
	if pierce_left > 0:
		pierce_left -= 1
		_current_damage_mult *= data.pierce_damage_keep
		if data.destroy_on_hit and pierce_left <= 0:
			_destroy()
	elif data.destroy_on_hit:
		_destroy()


func _on_body_entered(body: Node2D) -> void:
	if is_dead:
		return
	# 命中墙 / 障碍
	if bounce_left > 0:
		_bounce_off(body)
	else:
		_spawn_wall_vfx()
		_destroy()


func _bounce_off(body: Node2D) -> void:
	bounce_left -= 1
	# 用最近的碰撞法线近似反弹：比较四个方向的重叠深度
	var normal := _estimate_wall_normal()
	if normal == Vector2.ZERO:
		normal = -direction
	direction = direction.bounce(normal).normalized()
	speed *= data.bounce_damping
	_current_damage_mult *= data.bounce_damage_keep
	_hit_ids.clear()
	AudioManager.play_sfx_2d("res://assets/audio/sfx/bounce.wav", global_position)
	CombatFx.hit_spark(self, global_position, normal, 0.8)


func _estimate_wall_normal() -> Vector2:
	var space := get_world_2d().direct_space_state
	if space == null:
		return Vector2.ZERO
	var params := PhysicsPointQueryParameters2D.new()
	params.position = global_position
	params.collide_with_bodies = true
	params.collision_mask = Layers.WORLD | Layers.OBSTACLE
	params.collide_with_areas = false
	var hits := space.intersect_point(params, 4)
	if hits.is_empty():
		return -direction
	var best: Vector2 = Vector2.ZERO
	for h in hits:
		var col: Vector2 = h.get("normal", Vector2.ZERO)
		if col.length_squared() > best.length_squared():
			best = col
	return best.normalized() if best != Vector2.ZERO else -direction


func _spawn_hit_vfx(dir: Vector2, crit: bool, dmg: float) -> void:
	match data.hit_vfx:
		&"spark":
			CombatFx.hit_spark(self, global_position, dir, 1.0)
		&"petal":
			CombatFx.spawn_sprite_burst(self, global_position,
				Atlas.prop(Atlas.PROP_HIT_SPARK), 4, data.trail_color, 26.0)
		_:
			pass


func _spawn_wall_vfx() -> void:
	CombatFx.hit_spark(self, global_position, -direction, 0.7)


func _destroy() -> void:
	if is_dead:
		return
	is_dead = true
	monitoring = false
	queue_free()


func _expire() -> void:
	_destroy()


func _to_string() -> String:
	return "Projectile(dmg=%.1f pierce=%d bounce=%d)" % [
		info_template.amount if info_template else 0.0, pierce_left, bounce_left
	]
