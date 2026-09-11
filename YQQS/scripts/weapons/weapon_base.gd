class_name WeaponBase
extends Node2D
## 武器基类 —— 所有武器的公共骨架（冷却、弹药、换弹、开火分发、投射物生成）。
##
## 【框架约束 · 必读】
## 1. 一把武器 = 一个 WeaponData(.tres) + 可选的一个专属脚本(.gd)。
##    WeaponData.script_path 为空时，由 WeaponRegistry 回退到按 kind 分发的
##    默认实现（weapon_ranged.gd / weapon_melee.gd）。
##    → 第一阶段 12 把品质武器就是这种「只有贴图、没有专属实现」的状态。
## 2. 子类只允许覆写 `_do_fire()`（一次开火的全部表现）与
##    `_do_reload_start()`；冷却、弹药、输入全部由基类处理。
## 3. 暴击在武器层掷骰（roll_crit），把结果写进 DamageInfo.crit，
##    受击方不再重复掷骰 —— 保证「一次射击只有一次暴击判定」。
## 4. 武器不直接改目标血量，只能通过 DamageInfo / HitboxComponent。
## 5. 子类开火时必须调用 `consume_shot()` 来扣弹与进入冷却。

signal fired(weapon: Node, data: WeaponData)
signal reload_started(weapon: Node, duration: float)
signal reload_finished(weapon: Node)
signal ammo_changed(current: int, maximum: int)
signal dry_fire(weapon: Node)

## 武器静态数据
var data: WeaponData = null
## 持有者（Actor）
var holder: Node2D = null
## 朝向（世界坐标单位向量）
var aim_direction: Vector2 = Vector2.RIGHT
## 炮口世界坐标（投射物出生点）
var muzzle_point: Vector2 = Vector2.ZERO

var ammo: int = 0
var is_reloading: bool = false
var is_firing: bool = false

var _cooldown: float = 0.0
var _reload_timer: float = 0.0
var _sprite: Sprite2D = null
var _rng := RandomNumberGenerator.new()
var _recoil_offset: Vector2 = Vector2.ZERO
var _shot_count: int = 0


func _ready() -> void:
	_rng.randomize()
	z_index = 1
	_build_visual()


func setup(p_data: WeaponData, p_holder: Node2D) -> void:
	data = p_data
	holder = p_holder
	ammo = data.magazine if data.magazine > 0 else 0
	_build_visual()
	_refresh_visual()
	_on_setup_done()


## 子类钩子
func _on_setup_done() -> void:
	pass


func _build_visual() -> void:
	if data == null:
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.centered = true
		add_child(_sprite)
	_sprite.texture = data.get_icon()
	if _sprite.texture is AtlasTexture:
		(_sprite.texture as AtlasTexture).filter_clip = true


func _refresh_visual() -> void:
	if _sprite == null:
		return
	var flip := aim_direction.x < 0.0
	_sprite.flip_v = flip
	position = _recoil_offset


# ---------------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if data == null:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _recoil_offset.length_squared() > 0.01:
		_recoil_offset = _recoil_offset.move_toward(Vector2.ZERO, 130.0 * delta)
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
	# 视觉朝向前进方向
	if holder and is_instance_valid(holder):
		var sp = holder.get("sprite")
		if sp is Sprite2D and _sprite:
			_sprite.flip_v = aim_direction.x < 0.0
	_update_sprite_transform()


func _update_sprite_transform() -> void:
	if _sprite == null:
		return
	_sprite.position = _recoil_offset

func update_aim(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	aim_direction = dir.normalized()
	var off := 0.0
	if data:
		off = data.muzzle_offset.x
	muzzle_point = global_position + aim_direction * off
	if _sprite:
		_sprite.flip_v = aim_direction.x < 0.0


func set_holder_position(p: Vector2) -> void:
	global_position = p


# ---------------------------------------------------------------------------
# 开火
# ---------------------------------------------------------------------------

func can_fire() -> bool:
	if data == null or is_reloading:
		return false
	if _cooldown > 0.0:
		return false
	if data.magazine > 0 and ammo <= 0:
		return false
	if data.energy_cost > 0.0:
		var v := _get_vitals()
		if v and v.mp < data.energy_cost:
			return false
	return true


## 供 AI / 输入层调用
func try_fire() -> bool:
	if not can_fire():
		if data.magazine > 0 and ammo <= 0 and not is_reloading:
			_play_empty()
			start_reload()
		return false
	# 能量消耗
	if data.energy_cost > 0.0:
		var v := _get_vitals()
		if v and not v.consume_mp(data.energy_cost):
			return false
	is_firing = true
	_do_fire()
	consume_shot()
	fired.emit(self, data)
	EventBus.weapon_fired.emit(self, data)
	return true


## 扣弹 + 进入冷却 + 后坐
func consume_shot() -> void:
	_cooldown = _effective_fire_interval()
	if data.magazine > 0:
		ammo = maxi(0, ammo - 1)
		ammo_changed.emit(ammo, data.magazine)
		if ammo <= 0:
			start_reload()
	_recoil_offset = -aim_direction * 2.0
	_shot_count += 1
	if data.shake_on_fire > 0.0:
		EventBus.screen_shake_requested.emit(data.shake_on_fire, 0.10)


## 实际射击间隔（受攻速加成影响）
func _effective_fire_interval() -> float:
	var rate := 1.0
	if holder and holder.get("faction") == GameEnums.Faction.PLAYER and GameState:
		rate = maxf(0.1, GameState.get_stat(GameEnums.StatKind.FIRE_RATE))
	return maxf(0.02, data.fire_rate / rate)


## 子类唯一的实现入口
func _do_fire() -> void:
	push_warning("[WeaponBase] _do_fire 未实现: %s" % data.id)


## 子类覆写以自定义换弹行为
func _do_reload_start() -> void:
	pass


# ---------------------------------------------------------------------------
# 换弹
# ---------------------------------------------------------------------------

func start_reload() -> void:
	if data == null or data.magazine <= 0 or is_reloading:
		return
	if ammo >= data.magazine:
		return
	is_reloading = true
	var speed := 1.0
	if holder and holder.get("faction") == GameEnums.Faction.PLAYER and GameState:
		speed = maxf(0.1, GameState.get_stat(GameEnums.StatKind.RELOAD_SPEED))
	_reload_timer = maxf(0.05, data.reload_time / speed)
	_do_reload_start()
	reload_started.emit(self, _reload_timer)
	EventBus.weapon_reload_started.emit(self, _reload_timer)


func _finish_reload() -> void:
	is_reloading = false
	_reload_timer = 0.0
	ammo = data.magazine
	ammo_changed.emit(ammo, data.magazine)
	reload_finished.emit(self)
	EventBus.weapon_reload_finished.emit(self)


func get_reload_ratio() -> float:
	if not is_reloading or data == null or data.reload_time <= 0.0:
		return 0.0
	return 1.0 - clampf(_reload_timer / maxf(0.01, data.reload_time), 0.0, 1.0)


func get_cooldown_ratio() -> float:
	var interval := _effective_fire_interval()
	if interval <= 0.0:
		return 0.0
	return 1.0 - clampf(_cooldown / interval, 0.0, 1.0)


# ---------------------------------------------------------------------------
# 伤害构造
# ---------------------------------------------------------------------------

## 掷暴击。
## 【重要】游侠翻滚后有一个「下次攻击必定暴击」的窗口，
## 由持有者（Player）持有该状态，武器通过 consume_guaranteed_crit() 消费它。
## 这样「必暴」是一次性的，且与暴击率无关。
func roll_crit() -> bool:
	if holder and holder.has_method("consume_guaranteed_crit"):
		if bool(holder.call("consume_guaranteed_crit")):
			return true
	var chance := data.crit_bonus
	if holder and holder.get("faction") == GameEnums.Faction.PLAYER and GameState:
		chance += GameState.get_crit_chance()
	if holder and holder.has_method("get_crit_bonus"):
		chance += float(holder.call("get_crit_bonus"))
	return _rng.randf() < clampf(chance, 0.0, 0.95)


## 全局伤害倍率（玩家吃技能树加成）
func damage_multiplier() -> float:
	if holder and holder.get("faction") == GameEnums.Faction.PLAYER and GameState:
		return GameState.get_damage_mult()
	return 1.0


## 构造一发伤害（已含暴击与倍率）
func build_damage(base_damage: float, crit: bool, mult: float = 1.0) -> DamageInfo:
	var amount := base_damage * damage_multiplier() * mult
	if crit:
		var cm := 2.0
		if holder and holder.get("faction") == GameEnums.Faction.PLAYER and GameState:
			cm = GameState.get_crit_mult()
		amount *= cm
	var info := DamageInfo.make(amount, self, holder, _faction())
	info.crit = crit
	info.damage_type = GameEnums.DamageType.PHYSICAL
	info.tags.append("weapon")
	return info


func _faction() -> int:
	if holder:
		var f = holder.get("faction")
		if f != null:
			return int(f)
	return GameEnums.Faction.PLAYER


func _get_vitals() -> VitalsComponent:
	if holder == null:
		return null
	return holder.get("vitals") as VitalsComponent


# ---------------------------------------------------------------------------
# 投射物
# ---------------------------------------------------------------------------

## 生成一发投射物。返回节点（失败为 null）。
func spawn_projectile(
	dir: Vector2,
	pdata: ProjectileData,
	info: DamageInfo,
	speed: float = -1.0,
	spawn_pos: Vector2 = Vector2.INF
) -> Node2D:
	var scene_path := data.projectile_scene
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/projectiles/Projectile.tscn"
	if not ResourceLoader.exists(scene_path):
		push_error("[WeaponBase] 投射物场景缺失: %s" % scene_path)
		return null
	var ps: PackedScene = load(scene_path)
	var p := ps.instantiate()
	var parent := _projectile_parent()
	if parent == null:
		return null
	parent.add_child(p)
	var pos := muzzle_point if spawn_pos == Vector2.INF else spawn_pos
	if p is Node2D:
		(p as Node2D).global_position = pos
	p.call("configure", info, dir.normalized(), pdata, speed, holder, _faction())
	return p


func _projectile_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var n := tree.get_first_node_in_group("projectile_root")
	if n and is_instance_valid(n):
		return n
	return tree.current_scene


# ---------------------------------------------------------------------------
# 近战
# ---------------------------------------------------------------------------

## 触发一次近战挥砍（默认实现用；专属脚本可覆写）
func melee_swing() -> void:
	var hb := _get_melee_hitbox()
	if hb == null:
		return
	var crit := roll_crit()
	var info := build_damage(data.damage, crit)
	hb.pierce_armor = false
	hb.activate(data.melee_swing_time, info.amount, crit)
	hb.knockback_force = data.knockback


func _get_melee_hitbox() -> HitboxComponent:
	if holder == null:
		return null
	return holder.find_child("MeleeHitbox", true, false) as HitboxComponent


# ---------------------------------------------------------------------------
# 表现
# ---------------------------------------------------------------------------

func _play_fire_sfx() -> void:
	var path := data.sfx_fire
	if path.is_empty():
		return
	if holder:
		AudioManager.play_sfx_2d(path, global_position)
	else:
		AudioManager.play_sfx(path)


func _play_empty() -> void:
	dry_fire.emit(self)
	if data.sfx_empty != "":
		AudioManager.play_sfx(data.sfx_empty)


func muzzle_world_position() -> Vector2:
	if data == null:
		return global_position
	return global_position + aim_direction * data.muzzle_offset.x


func _to_string() -> String:
	return "Weapon(%s)" % (data.id if data else "null")
