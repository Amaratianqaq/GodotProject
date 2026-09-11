class_name Enemy
extends Actor
## 敌人（数据驱动，一个场景承载全部怪物）。
##
## 【框架约束 · 必读】
## 1. **不要** 给每种怪物新建继承本类的脚本。所有差异都必须通过
##    EnemyData 表达：数值走字段，行为走 `behavior` 分发到下面的
##    _behavior_*() 方法。
## 2. 需要全新行为时：新增一个 behavior 字符串 + 一个 _behavior_xxx() 方法
##    + EnemyData 里加对应参数，并同步更新 docs/03_数据与配置规范.md
##    与 tools/validation.gd 的合法行为列表。
## 3. 敌人死亡的表现/掉落统一走 `_on_death()` → LootService.handle_enemy_death()。
##    宝箱等级由 EnemyData.get_chest_tier() 推导（小怪=普通 / 精英=优秀 / BOSS=稀有）。
## 4. **配置注入顺序**：必须先 configure() 再 add_child()，
##    因为 _ready() 需要 data 才能初始化；顺序反了会直接报错。
## 5. AI 计时器自己维护，不用 Timer 节点（便于顿帧与暂停一致）。

enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVER, CHARGE, DEAD }

## 静态数据（add_child 之前由 configure() 注入）
var data: EnemyData = null

var state: int = State.IDLE
var target: Node2D = null
var room_cell: Vector2i = Vector2i(-1, -1)
var home_position: Vector2 = Vector2.ZERO

# --- 内部计时/状态 ---
var _state_timer: float = 0.0
var _attack_cd: float = 0.0
var _contact_hitbox: HitboxComponent = null
var _attack_hitbox: HitboxComponent = null
var _hp_bar: HealthBar = null
var _wander_dir: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _burst_left: int = 0
var _burst_timer: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _boss_pattern: StringName = &"fan"
var _anim_timer: float = 0.0
var _anim_step: int = 0
var _hop_timer: float = 0.0
var _hop_velocity: Vector2 = Vector2.ZERO


## 在 add_child 之前调用
func configure(d: EnemyData, p_room_cell: Vector2i = Vector2i(-1, -1)) -> void:
	data = d
	room_cell = p_room_cell


func _on_actor_ready() -> void:
	if data == null:
		push_error("[Enemy] 未注入 EnemyData（必须 configure() 后再 add_child）")
		queue_free()
		return
	faction = GameEnums.Faction.ENEMY
	NodeUtils.ensure_group(self, &"enemies")
	display_name = data.display_name
	move_speed = data.move_speed
	home_position = global_position
	_setup_visuals()
	_setup_vitals()
	_setup_hitboxes()
	_setup_health_bar()
	state = State.IDLE
	_attack_cd = randf_range(0.0, maxf(0.05, data.attack_cooldown * 0.5))
	if RunManager:
		RunManager.notify_enemy_spawned(self)
	if data.is_boss() and EventBus:
		EventBus.boss_spawned.emit(self)


func _sheet_cell_size() -> float:
	var key: String = Atlas.ENEMY_SHEETS.get(data.sheet_key, "enemy_slime")
	var meta: Dictionary = Atlas.SHEETS.get(key, {"cell": 32})
	return float(meta.get("cell", 32))


func _setup_visuals() -> void:
	if sprite:
		var tex := Atlas.enemy_frame(data.sheet_key, "idle", 0)
		if tex:
			sprite.texture = tex
		var s := data.sprite_scale
		sprite.scale = Vector2(s, s)
		sprite.modulate = data.sprite_modulate
		sprite_offset_y = -_sheet_cell_size() * 0.5 * s + 1.0
	fit_shadow_to_radius(data.body_radius)
	if data.hover_height > 0.0:
		set_z_height(data.hover_height)


func _setup_vitals() -> void:
	if vitals == null:
		return
	vitals.setup_simple(data.max_hp, data.armor, 0.0)
	vitals.damage_reduction = data.damage_reduction
	vitals.iframe_duration = 0.0   # 霰弹多弹丸必须能多次命中
	vitals.died.connect(_on_vitals_died)
	vitals.damaged.connect(_on_vitals_damaged)


func _setup_hitboxes() -> void:
	_contact_hitbox = find_child("ContactHitbox", true, false) as HitboxComponent
	if _contact_hitbox:
		_contact_hitbox.set_faction(GameEnums.Faction.ENEMY)
		_contact_hitbox.multi_hit = true
		_contact_hitbox.multi_hit_interval = 0.65
		_contact_hitbox.knockback_force = 70.0
		if data.contact_damage > 0.0:
			_contact_hitbox.activate(-1.0, data.contact_damage, false)
		else:
			_contact_hitbox.deactivate()
	_attack_hitbox = find_child("AttackHitbox", true, false) as HitboxComponent
	if _attack_hitbox:
		_attack_hitbox.set_faction(GameEnums.Faction.ENEMY)
		_attack_hitbox.deactivate()
		_attack_hitbox.hit_landed.connect(_on_attack_landed)


func _setup_health_bar() -> void:
	_hp_bar = HealthBar.new()
	var color := Color("#d94a4a")
	match data.tier:
		GameEnums.EnemyTier.ELITE: color = Color("#f2a13b")
		GameEnums.EnemyTier.BOSS: color = Color("#b44ac9")
	var w := 18.0 * data.hp_bar_scale()
	if data.is_boss():
		w = 60.0
	_hp_bar.setup(w, color, data.tier != GameEnums.EnemyTier.NORMAL)
	_hp_bar.y_offset = -_sheet_cell_size() * data.sprite_scale - 6.0
	_hp_bar.z_index = 10
	_hp_bar.z_as_relative = false
	add_child(_hp_bar)
	_update_health_bar()


func _update_health_bar() -> void:
	if _hp_bar == null or vitals == null:
		return
	_hp_bar.set_ratios(vitals.ratio_hp(), vitals.ratio_armor())


# ---------------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead or data == null:
		super._physics_process(delta)
		return
	if _state_timer > 0.0:
		_state_timer = maxf(0.0, _state_timer - delta)
	if _attack_cd > 0.0:
		_attack_cd = maxf(0.0, _attack_cd - delta)
	# 跳跃冲量衰减
	if _hop_timer > 0.0:
		_hop_timer = maxf(0.0, _hop_timer - delta)
		knockback_velocity += _hop_velocity * delta * 4.0
		if _hop_timer <= 0.0:
			_hop_velocity = Vector2.ZERO

	_update_target()
	_tick_behavior(delta)
	super._physics_process(delta)
	if sprite:
		sprite.position.x = 0.0


func _update_target() -> void:
	if target == null or not is_instance_valid(target) or bool(target.get("is_dead")):
		target = null
	var tree := get_tree()
	if tree == null:
		return
	var p := tree.get_first_node_in_group("player") as Node2D
	if p == null or bool(p.get("is_dead")):
		return
	var d := p.global_position.distance_to(global_position)
	if target == null and d <= data.detect_radius:
		target = p
	elif target != null and d > data.lose_radius:
		target = null


func _tick_behavior(delta: float) -> void:
	if state == State.DEAD:
		return
	match data.behavior:
		&"chase_melee": _behavior_chase_melee(delta)
		&"ranged_kiter": _behavior_ranged_kiter(delta)
		&"erratic_flyer": _behavior_erratic_flyer(delta)
		&"hopper": _behavior_hopper(delta)
		&"charger": _behavior_charger(delta)
		&"boss_summoner": _behavior_boss_summoner(delta)
		_: _behavior_chase_melee(delta)
	_update_animation(delta)


# ---------------------------------------------------------------------------
# 行为实现
# ---------------------------------------------------------------------------

func _distance_to_target() -> float:
	if target == null:
		return INF
	return global_position.distance_to(target.global_position)


func _dir_to_target() -> Vector2:
	if target == null:
		return Vector2.ZERO
	return (target.global_position - global_position).normalized()


func _rng() -> RandomNumberGenerator:
	return RunManager.combat_rng if RunManager else null


## 近战追击：追到攻击距离 → 前摇 → 挥击 → 后摇
func _behavior_chase_melee(delta: float) -> void:
	match state:
		State.IDLE:
			desired_velocity = Vector2.ZERO
			if target:
				_set_state(State.CHASE)
		State.CHASE:
			if target == null:
				_set_state(State.IDLE)
				return
			var d := _distance_to_target()
			var dir := _dir_to_target()
			if d <= data.attack_range:
				desired_velocity = Vector2.ZERO
				if _attack_cd <= 0.0:
					_begin_windup()
			else:
				desired_velocity = dir * move_speed
				set_facing(dir)
		State.WINDUP:
			desired_velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_perform_melee_attack()
				_set_state(State.RECOVER, data.attack_recover)
		State.RECOVER:
			desired_velocity = desired_velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _state_timer <= 0.0:
				_set_state(State.CHASE)


## 远程风筝：太近后退、太远靠近、在射程内开火
func _behavior_ranged_kiter(delta: float) -> void:
	var ideal := data.attack_range * 0.72
	match state:
		State.IDLE:
			desired_velocity = Vector2.ZERO
			if target:
				_set_state(State.CHASE)
		State.CHASE:
			if target == null:
				_set_state(State.IDLE)
				return
			var d := _distance_to_target()
			var dir := _dir_to_target()
			set_facing(dir)
			if d > data.attack_range:
				desired_velocity = dir * move_speed
			elif d < ideal * 0.75:
				desired_velocity = -dir * move_speed * 0.85
			else:
				_wander_timer -= delta
				if _wander_timer <= 0.0:
					_wander_timer = randf_range(0.6, 1.4)
					_wander_dir = dir.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
				desired_velocity = _wander_dir * move_speed * 0.55
			if _attack_cd <= 0.0 and d <= data.attack_range:
				_begin_windup()
		State.WINDUP:
			desired_velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_perform_ranged_attack()
				_set_state(State.RECOVER, data.attack_recover)
		State.RECOVER:
			desired_velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_set_state(State.CHASE)


## 乱飞（蝙蝠）：正弦飘移 + 接触伤害
func _behavior_erratic_flyer(delta: float) -> void:
	if target == null:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(0.8, 1.8)
			_wander_dir = RngUtils.inside_unit_circle(_rng())
		desired_velocity = _wander_dir * move_speed * 0.6
		_apply_hover()
		return
	var dir := _dir_to_target()
	var wobble := dir.orthogonal() * sin(Time.get_ticks_msec() * 0.006) * 0.75
	desired_velocity = (dir + wobble).normalized() * move_speed
	set_facing(dir)
	_apply_hover()


func _apply_hover() -> void:
	if data.hover_height <= 0.0:
		return
	set_z_height(data.hover_height + sin(Time.get_ticks_msec() * 0.004) * 3.0)


## 跳跃（史莱姆 / 蘑菇）：蓄力压扁 → 跳 → 落地停顿
func _behavior_hopper(delta: float) -> void:
	match state:
		State.IDLE, State.RECOVER:
			desired_velocity = Vector2.ZERO
			_squash(1.12, 0.88)
			if _state_timer <= 0.0:
				_set_state(State.WINDUP, randf_range(0.35, 0.7))
		State.WINDUP:
			desired_velocity = Vector2.ZERO
			var t := 1.0 - clampf(_state_timer / 0.6, 0.0, 1.0)
			_squash(1.0 + t * 0.22, 1.0 - t * 0.22)
			if _state_timer <= 0.0:
				_hop()
		State.CHASE:
			var p := clampf(1.0 - _state_timer / 0.42, 0.0, 1.0)
			set_z_height(sin(p * PI) * 11.0)
			_squash(0.92, 1.08)
			if _state_timer <= 0.0:
				set_z_height(0.0)
				_squash(1.15, 0.85)
				_attack_cd = data.attack_cooldown
				_set_state(State.RECOVER, randf_range(0.3, 0.6))


func _hop() -> void:
	var dir := _dir_to_target()
	if dir == Vector2.ZERO:
		dir = RngUtils.inside_unit_circle(_rng())
	_hop_velocity = dir.normalized() * (move_speed * 2.6)
	_hop_timer = 0.42
	set_facing(dir)
	_set_state(State.CHASE, 0.42)


## 冲锋（哥布林）：拉开距离 → 蓄力 → 直线冲锋
func _behavior_charger(delta: float) -> void:
	match state:
		State.IDLE:
			desired_velocity = Vector2.ZERO
			if target:
				_set_state(State.CHASE)
		State.CHASE:
			if target == null:
				_set_state(State.IDLE)
				return
			var dir := _dir_to_target()
			var d := _distance_to_target()
			set_facing(dir)
			if d < data.attack_range * 0.8:
				desired_velocity = -dir * move_speed
			else:
				desired_velocity = dir * move_speed
			if _attack_cd <= 0.0 and d < data.detect_radius * 0.85:
				_charge_dir = dir
				_set_state(State.WINDUP, data.charge_windup)
		State.WINDUP:
			desired_velocity = desired_velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			_charge_dir = _dir_to_target()
			set_facing(_charge_dir)
			if sprite:
				sprite.position.x = randf_range(-1.2, 1.2)
			if _state_timer <= 0.0:
				_set_state(State.CHARGE, 0.55)
		State.CHARGE:
			desired_velocity = _charge_dir * move_speed * data.charge_speed_mult
			if _state_timer <= 0.0:
				_attack_cd = data.attack_cooldown
				_set_state(State.RECOVER, data.attack_recover)
		State.RECOVER:
			desired_velocity = desired_velocity.move_toward(Vector2.ZERO, 500.0 * delta)
			if _state_timer <= 0.0:
				_set_state(State.CHASE)


## BOSS：扇形齐射 + 环形弹幕 + 召唤小怪
func _behavior_boss_summoner(delta: float) -> void:
	match state:
		State.IDLE:
			desired_velocity = Vector2.ZERO
			if target:
				_set_state(State.CHASE)
		State.CHASE:
			if target == null:
				_set_state(State.IDLE)
				return
			var dir := _dir_to_target()
			var d := _distance_to_target()
			set_facing(dir)
			if d > data.attack_range * 0.8:
				desired_velocity = dir * move_speed
			elif d < data.attack_range * 0.45:
				desired_velocity = -dir * move_speed * 0.7
			else:
				desired_velocity = dir.orthogonal() * move_speed * 0.5
			if _attack_cd <= 0.0:
				_boss_choose_attack()
		State.WINDUP:
			desired_velocity = Vector2.ZERO
			_boss_cast_glow()
			if _state_timer <= 0.0:
				_boss_execute()
		State.ATTACK:
			if _burst_left > 0:
				_burst_timer -= delta
				if _burst_timer <= 0.0:
					_burst_timer = maxf(0.05, data.burst_interval)
					_burst_left -= 1
					_boss_fire_volley()
			else:
				_set_state(State.RECOVER, data.attack_recover)
		State.RECOVER:
			desired_velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_attack_cd = data.attack_cooldown
				_set_state(State.CHASE)


func _boss_choose_attack() -> void:
	var r := randf()
	if r < 0.45:
		_boss_pattern = &"fan"
	elif r < 0.8:
		_boss_pattern = &"ring"
	else:
		_boss_pattern = &"summon"
	_set_state(State.WINDUP, maxf(0.15, data.attack_windup))


func _boss_cast_glow() -> void:
	var dur := maxf(0.05, data.attack_windup)
	var t := 1.0 - clampf(_state_timer / dur, 0.0, 1.0)
	flash_white(0.06, Color(0.75, 0.45, 1.0, 1.0))
	set_z_height(data.hover_height + sin(t * PI) * 5.0)


func _boss_execute() -> void:
	match _boss_pattern:
		&"fan":
			_burst_left = maxi(1, data.burst_count)
			_burst_timer = 0.0
			_set_state(State.ATTACK)
		&"ring":
			_boss_fire_ring()
			_set_state(State.RECOVER, data.attack_recover)
		&"summon":
			_boss_summon()
			_set_state(State.RECOVER, data.attack_recover)
		_:
			_set_state(State.RECOVER)
	set_z_height(data.hover_height)


func _boss_fire_volley() -> void:
	if target == null:
		return
	var base := _dir_to_target()
	var count := maxi(1, data.projectile_count)
	var spread := deg_to_rad(data.projectile_spread_deg)
	for i in count:
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		_spawn_projectile(base.rotated(t * spread), 1.0)
	CombatFx.muzzle_flash(self, global_position, base, 1.6)
	AudioManager.play_sfx_2d(data.sfx_attack, global_position)


func _boss_fire_ring() -> void:
	var count := 12
	var offset := randf() * TAU
	for i in count:
		var dir := Vector2.RIGHT.rotated(offset + TAU * float(i) / float(count))
		_spawn_projectile(dir, 0.8)
	CombatFx.spawn_sprite_burst(
		self, global_position, Atlas.prop(Atlas.PROP_HIT_SPARK), 12, Color("#b44ac9"), 45.0
	)
	AudioManager.play_sfx_2d(data.sfx_attack, global_position)


func _boss_summon() -> void:
	var pool := ConfigDB.forest_normal_enemies()
	if pool.is_empty():
		return
	var parent := _entity_parent()
	if parent == null:
		return
	var pick: EnemyData = RngUtils.pick_weighted(
		_rng(), pool, pool.map(func(e: EnemyData) -> float: return e.spawn_weight)
	)
	if pick == null:
		return
	var scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	if scene == null:
		return
	for i in 2:
		var e := scene.instantiate()
		# configure 必须在 add_child 之前
		e.call("configure", pick, room_cell)
		parent.add_child(e)
		(e as Node2D).global_position = global_position + RngUtils.in_ring(_rng(), 22.0, 40.0)
	CombatFx.spawn_sprite_burst(
		self, global_position, Atlas.prop(Atlas.PROP_HIT_SPARK), 10, Color("#b44ac9"), 38.0
	)
	EventBus.toast.emit("哥布林大祭司召唤了援军！", Color("#b44ac9"))


# ---------------------------------------------------------------------------
# 状态与攻击
# ---------------------------------------------------------------------------

func _set_state(s: int, timer: float = 0.0) -> void:
	state = s
	_state_timer = timer


func _begin_windup() -> void:
	_set_state(State.WINDUP, data.attack_windup)
	flash_white(maxf(0.06, data.attack_windup * 0.6), Color(1.0, 0.45, 0.4, 1.0))


func _perform_melee_attack() -> void:
	_attack_cd = data.attack_cooldown
	var dir := _dir_to_target()
	if _attack_hitbox == null:
		_try_contact_attack()
		return
	_attack_hitbox.rotation = dir.angle()
	_attack_hitbox.knockback_force = 90.0
	_attack_hitbox.activate(0.16, data.attack_damage, false)
	CombatFx.hit_spark(self, global_position + dir * data.attack_range * 0.6, dir, 0.9)
	AudioManager.play_sfx_2d(data.sfx_attack, global_position)


## 没有独立攻击盒时（史莱姆这类），靠接触盒补一次攻击伤害
func _try_contact_attack() -> void:
	if _contact_hitbox == null:
		return
	_contact_hitbox.activate(0.18, data.attack_damage, false)
	await get_tree().create_timer(0.22).timeout
	if not is_dead and _contact_hitbox and is_instance_valid(_contact_hitbox):
		if data.contact_damage > 0.0:
			_contact_hitbox.activate(-1.0, data.contact_damage, false)
		else:
			_contact_hitbox.deactivate()


func _perform_ranged_attack() -> void:
	_attack_cd = data.attack_cooldown
	var dir := _dir_to_target()
	var count := maxi(1, data.projectile_count)
	var spread := deg_to_rad(data.projectile_spread_deg)
	for i in count:
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		_spawn_projectile(dir.rotated(t * spread), data.projectile_damage_mult)
	CombatFx.muzzle_flash(self, global_position + dir * 8.0, dir, 1.0)
	AudioManager.play_sfx_2d(data.sfx_attack, global_position)


func _spawn_projectile(dir: Vector2, dmg_mult: float) -> Node2D:
	var raw := data.attack_damage * dmg_mult
	var info := DamageInfo.make(raw, self, self, GameEnums.Faction.ENEMY)
	info.knockback = dir * 50.0
	info.tags.append("enemy_projectile")
	var pd := ProjectileData.new()
	pd.speed = data.projectile_speed
	pd.lifetime = 1.9
	pd.radius = 3.5
	pd.color = Color("#b44ac9") if data.is_boss() else Color("#d94a4a")
	pd.trail_color = pd.color
	pd.trail_length = 3
	pd.rotate_to_direction = true
	var scene_path := data.projectile_scene
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/projectiles/Projectile.tscn"
	if not ResourceLoader.exists(scene_path):
		return null
	var parent := _entity_parent()
	if parent == null:
		return null
	var ps: PackedScene = load(scene_path)
	var p := ps.instantiate()
	parent.add_child(p)
	if p is Node2D:
		(p as Node2D).global_position = global_position + dir * 9.0
	p.call("configure", info, dir, pd, data.projectile_speed, self, GameEnums.Faction.ENEMY)
	return p


func _entity_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var n := tree.get_first_node_in_group("entity_root")
	if n and is_instance_valid(n):
		return n
	return tree.current_scene


func _on_attack_landed(_target: Node2D, _info: DamageInfo, _dmg: float) -> void:
	EventBus.screen_shake_requested.emit(0.8, 0.12)


# ---------------------------------------------------------------------------
# 伤害反应
# ---------------------------------------------------------------------------

func _on_vitals_damaged(info: DamageInfo, actual: float) -> void:
	flash_white()
	if info.knockback != Vector2.ZERO:
		apply_knockback(info.knockback * 0.06)
	if _hp_bar:
		_update_health_bar()
	# 受击打断前摇（BOSS 除外，保持压迫感）
	if data != null and not data.is_boss() and state == State.WINDUP:
		_set_state(State.CHASE)


func _on_vitals_died() -> void:
	_on_death()


func _on_death() -> void:
	if is_dead:
		return
	state = State.DEAD
	super.die()
	if _contact_hitbox:
		_contact_hitbox.deactivate()
	if _attack_hitbox:
		_attack_hitbox.deactivate()
	if _hp_bar:
		_hp_bar.visible = false
	CombatFx.death_burst(
		self, global_position, _death_color(),
		22 if (data and data.is_boss()) else (10 if (data and data.tier == GameEnums.EnemyTier.ELITE) else 6)
	)
	if data and data.sfx_die != "":
		AudioManager.play_sfx_2d(data.sfx_die, global_position)
	if data and data.is_boss():
		EventBus.screen_shake_requested.emit(6.0, 0.6)
	# 掉落（宝箱 / 金币 / 直接掉落）
	var parent := _entity_parent()
	if parent and data:
		LootService.handle_enemy_death(data, global_position, parent)
	# 广播
	if data:
		EventBus.enemy_died.emit(self, data.tier, global_position)
		if data.is_boss():
			EventBus.boss_defeated.emit()
		GameState.add_xp(data.xp_reward)
	# 死亡动画
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.4, 0.4), 0.28)
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(queue_free)


func _death_color() -> Color:
	match data.tier:
		GameEnums.EnemyTier.ELITE: return Color("#f2a13b")
		GameEnums.EnemyTier.BOSS: return Color("#b44ac9")
	return Color("#d94a4a")


# ---------------------------------------------------------------------------
# 表现
# ---------------------------------------------------------------------------

func _squash(sx: float, sy: float) -> void:
	if sprite == null or data == null:
		return
	var s := data.sprite_scale
	sprite.scale = sprite.scale.lerp(Vector2(s * sx, s * sy), 0.35)


func _update_animation(delta: float) -> void:
	if sprite == null or data == null:
		return
	if data.behavior == &"hopper" or state == State.WINDUP or state == State.CHARGE:
		return
	var moving := desired_velocity.length_squared() > 4.0
	var anim := "walk" if moving else "idle"
	_anim_timer += delta
	if _anim_timer >= 0.16:
		_anim_timer = 0.0
		_anim_step += 1
	var tex := Atlas.enemy_frame(data.sheet_key, anim, _anim_step)
	if tex:
		sprite.texture = tex


func get_enemy_data() -> EnemyData:
	return data


func is_elite() -> bool:
	return data != null and data.tier == GameEnums.EnemyTier.ELITE


func is_boss() -> bool:
	return data != null and data.is_boss()
