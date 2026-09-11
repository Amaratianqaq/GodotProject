class_name HitboxComponent
extends Area2D
## 攻击盒组件 —— 挂到近战武器 / 敌人攻击判定上。
##
## 【框架约束 · 必读】
## 1. 攻击盒是「开关式」的：由武器/敌人 AI 调用 activate(duration) 打开，
##    到期自动关闭。**不要** 常驻开启，否则会出现擦身即伤。
## 2. 同一次激活内，同一个目标只结算一次（_hit_targets 去重），
##    这是近战多段判定的基础。
## 3. 伤害数值必须通过 DamageInfo 传递；攻击盒不自己算暴击，
##    暴击由武器在 activate 前决定（见 WeaponBase.roll_crit）。

@export var faction: GameEnums.Faction = GameEnums.Faction.PLAYER
## 基础伤害（每次 activate 可覆写）
@export var damage: float = 4.0
@export var damage_type: int = GameEnums.DamageType.PHYSICAL
@export var knockback_force: float = 60.0
@export var hitstop: float = 0.05
@export var screen_shake: float = 0.0
## 是否穿透护甲
@export var pierce_armor: bool = false
## 激活时长（<=0 表示由外部手动 deactivate）
@export var auto_duration: float = 0.12
## 是否多重命中（同一目标可被反复命中，用于持续伤害区）
@export var multi_hit: bool = false
## 多重命中的间隔（秒）
@export var multi_hit_interval: float = 0.25

signal hit_landed(target: Node2D, info: DamageInfo, actual_damage: float)

var owner_actor: Node2D = null
var is_active: bool = false

var _hit_targets: Dictionary = {}     ## instance_id -> 上次命中时间
var _active_timer: float = 0.0
var _info_template: DamageInfo = null

## 外部（武器）在 activate 前注入的额外倍率
var external_damage_mult: float = 1.0
var external_crit: bool = false


func _ready() -> void:
	owner_actor = _find_actor(get_parent())
	_apply_layers()
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)
	set_physics_process(true)


func _find_actor(n: Node) -> Node2D:
	var cur := n
	while cur:
		if cur is Node2D and cur.has_method("is_actor"):
			return cur as Node2D
		cur = cur.get_parent()
	return n as Node2D


func _apply_layers() -> void:
	match faction:
		GameEnums.Faction.PLAYER:
			collision_layer = Layers.PLAYER_HITBOX_LAYER
			collision_mask = Layers.PLAYER_HITBOX_MASK
		GameEnums.Faction.ENEMY:
			collision_layer = Layers.ENEMY_HITBOX_LAYER
			collision_mask = Layers.ENEMY_HITBOX_MASK
		_:
			collision_layer = 0
			collision_mask = 0


# ---------------------------------------------------------------------------
# 开关
# ---------------------------------------------------------------------------

## 打开攻击盒。可选覆写本次伤害。
func activate(
	p_duration: float = -1.0,
	p_damage: float = -1.0,
	p_crit: bool = false,
	p_mult: float = 1.0
) -> void:
	is_active = true
	monitoring = true
	_hit_targets.clear()
	external_crit = p_crit
	external_damage_mult = p_mult
	if p_damage >= 0.0:
		damage = p_damage
	var dur := auto_duration if p_duration < 0.0 else p_duration
	_active_timer = dur
	set_physics_process(true)


func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	monitoring = false
	_active_timer = 0.0


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	if _active_timer > 0.0:
		_active_timer -= delta
		if _active_timer <= 0.0:
			deactivate()


# ---------------------------------------------------------------------------
# 命中
# ---------------------------------------------------------------------------

func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return
	var hb := HurtboxComponent.from_area(area)
	if hb == null:
		return
	_try_hit(hb)


## 也可以主动检测（投射物式扫掠）用
func try_hit_hurtbox(hb: HurtboxComponent) -> bool:
	return _try_hit(hb)


func _try_hit(hb: HurtboxComponent) -> bool:
	var key := hb.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _hit_targets.has(key) and not multi_hit:
		return false
	if _hit_targets.has(key) and multi_hit:
		if now - float(_hit_targets[key]) < multi_hit_interval:
			return true
	if not hb.is_alive():
		return false

	var info := _build_info(hb)
	var actual := hb.receive_hit(info)
	_hit_targets[key] = now
	if actual > 0.0:
		hit_landed.emit(hb.owner_actor, info, actual)
	return true


func _build_info(hb: HurtboxComponent) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = damage * external_damage_mult
	info.damage_type = damage_type
	info.source = self
	info.attacker = owner_actor
	info.faction = faction
	info.crit = external_crit
	info.pierce_armor = pierce_armor
	info.hitstop = hitstop
	info.screen_shake = screen_shake
	info.hit_position = global_position
	var target := hb.owner_actor
	if target:
		var dir := (target.global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		info.hit_direction = dir
		info.knockback = dir * knockback_force
	return info


func set_faction(f: int) -> void:
	faction = f
	_apply_layers()


## 已命中过的目标数量（用于穿透计数）
func hit_count() -> int:
	return _hit_targets.size()
