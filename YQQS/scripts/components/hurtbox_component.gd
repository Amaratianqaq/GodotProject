class_name HurtboxComponent
extends Area2D
## 受击盒组件 —— 挂到任何可以受伤的 Actor 上。
##
## 【框架约束 · 必读】
## 1. 每个可受伤实体 **必须且只能有一个** HurtboxComponent。
## 2. 受击盒只做「接收并转交」：真正的结算在 VitalsComponent。
## 3. 同阵营不互相伤害：由 receive_hit() 里的 faction 判断，
##    攻击方不需要自己判阵营。

## 该受击盒所属阵营
@export var faction: GameEnums.Faction = GameEnums.Faction.ENEMY
## 关联的数值组件（不填则自动向上查找）
@export var vitals_path: NodePath

signal hit_received(info: DamageInfo, actual_damage: float)

var vitals: VitalsComponent = null
var owner_actor: Node2D = null
## 受击点是否偏向身体中心（投射物用）
var last_hit_info: DamageInfo = null


func _ready() -> void:
	owner_actor = _find_actor(get_parent())
	if vitals_path != NodePath():
		vitals = get_node_or_null(vitals_path) as VitalsComponent
	if vitals == null:
		vitals = _find_vitals(owner_actor if owner_actor else get_parent())
	_apply_layers()


func _find_actor(n: Node) -> Node2D:
	var cur := n
	while cur:
		if cur is Node2D and cur.has_method("is_actor"):
			return cur as Node2D
		cur = cur.get_parent()
	return n as Node2D


func _find_vitals(n: Node) -> VitalsComponent:
	if n == null:
		return null
	for c in n.get_children():
		if c is VitalsComponent:
			return c
	return null


func _apply_layers() -> void:
	match faction:
		GameEnums.Faction.PLAYER:
			collision_layer = Layers.PLAYER_HURTBOX_LAYER
			collision_mask = Layers.PLAYER_HURTBOX_MASK
		GameEnums.Faction.ENEMY:
			collision_layer = Layers.ENEMY_HURTBOX_LAYER
			collision_mask = Layers.ENEMY_HURTBOX_MASK
		_:
			collision_layer = 0
			collision_mask = 0
	monitoring = false
	monitorable = true


# ---------------------------------------------------------------------------
# 受击
# ---------------------------------------------------------------------------

## 接收一次伤害。返回实际造成的伤害（0 表示被闪避/免疫/阵营相同）。
func receive_hit(info: DamageInfo) -> float:
	if info == null or vitals == null:
		return 0.0
	if not can_be_hit_by(info):
		return 0.0
	if vitals.is_invulnerable():
		return 0.0
	var actual := vitals.apply_damage(info)
	if actual > 0.0:
		last_hit_info = info
		hit_received.emit(info, actual)
	return actual


## 该伤害能否命中本受击盒
func can_be_hit_by(info: DamageInfo) -> bool:
	if info.faction == GameEnums.Faction.NEUTRAL:
		return true
	return info.faction != faction


func get_faction() -> int:
	return faction


func is_alive() -> bool:
	return vitals != null and not vitals.is_dead()


## 便捷：不构造 DamageInfo 直接打固定伤害
func take_simple_damage(amount: float, source: Node = null) -> float:
	var d := DamageInfo.make(amount, source, source, GameEnums.Faction.NEUTRAL)
	d.can_be_blocked = true
	return receive_hit(d)


static func from_area(area: Area2D) -> HurtboxComponent:
	if area is HurtboxComponent:
		return area as HurtboxComponent
	return null
