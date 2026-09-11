class_name DamageInfo
extends RefCounted
## 伤害数据包 —— 战斗系统唯一的伤害载体。
##
## 【框架约束】
## 1. 任何造成伤害的地方都必须构造 DamageInfo 并通过 Hurtbox 传递；
##    禁止直接修改目标的 hp。
## 2. DamageInfo 是一次性的：命中多个目标时要 duplicate()，不要复用同一个实例。
## 3. 伤害结算顺序固定为：
##      原始伤害 → 攻击方倍率 → 暴击 → 防御方伤害减免 → 护甲吸收 → 生命扣除
##    由 VitalsComponent.apply_damage() 统一实现，不允许各武器自行计算。

var amount: float = 0.0                       ## 结算前的基础伤害
var damage_type: int = GameEnums.DamageType.PHYSICAL
var source: Node = null                       ## 伤害来源节点（武器/投射物/敌人）
var attacker: Node = null                     ## 伤害归属者（角色 Actor）
var faction: int = GameEnums.Faction.NEUTRAL  ## 来源阵营，用于友军伤害判定
var knockback: Vector2 = Vector2.ZERO         ## 击退向量（已含力度）
var crit: bool = false                        ## 是否暴击
var pierce_armor: bool = false                ## 无视护甲
var can_be_blocked: bool = true               ## 是否可被格挡/闪避
var hit_position: Vector2 = Vector2.ZERO      ## 命中点（用于特效/飘字）
var hit_direction: Vector2 = Vector2.ZERO     ## 命中方向（用于击退与出血方向）
var tags: PackedStringArray = PackedStringArray()  ## 标签，例如 "melee" "explosion" "petal"
var hitstop: float = 0.045                    ## 命中顿帧时长（秒）
var screen_shake: float = 0.0                 ## 屏幕震动强度


static func make(
	p_amount: float,
	p_source: Node = null,
	p_attacker: Node = null,
	p_faction: int = GameEnums.Faction.NEUTRAL
) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = p_amount
	d.source = p_source
	d.attacker = p_attacker
	d.faction = p_faction
	return d


func duplicate_info() -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount
	d.damage_type = damage_type
	d.source = source
	d.attacker = attacker
	d.faction = faction
	d.knockback = knockback
	d.crit = crit
	d.pierce_armor = pierce_armor
	d.can_be_blocked = can_be_blocked
	d.hit_position = hit_position
	d.hit_direction = hit_direction
	d.tags = tags.duplicate()
	d.hitstop = hitstop
	d.screen_shake = screen_shake
	return d


func with_knockback(dir: Vector2, force: float) -> DamageInfo:
	knockback = dir.normalized() * force
	return self


func with_tag(t: String) -> DamageInfo:
	if not tags.has(t):
		tags.append(t)
	return self


func has_tag(t: String) -> bool:
	return tags.has(t)


func _to_string() -> String:
	return "[DamageInfo %.1f %s crit=%s from=%s]" % [
		amount, GameEnums.DamageType.keys()[damage_type], crit,
		attacker.name if attacker else "<none>",
	]
