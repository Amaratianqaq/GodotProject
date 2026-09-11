class_name VitalsComponent
extends Node
## 血量 / 护甲 / 蓝条组件 —— 生命蓝条系统的唯一实现。
##
## 【框架约束 · 必读】
## 1. **禁止** 任何其它代码直接修改 hp / armor / mp 字段，
##    一律走 apply_damage / heal / restore_mp / consume_mp / add_armor。
## 2. 伤害结算顺序固定（不允许各武器自行计算）：
##      原始伤害 → 伤害减免(damage_reduction)
##      → 护甲吸收（pierce_armor 可跳过）→ 生命扣除
##    暴击倍率由攻击方在生成 DamageInfo 前乘好，本组件不再乘。
## 3. 无敌帧（i-frame）分两种：
##      - invincible 布尔量：翻滚等主动无敌，完全免疫
##      - invincible_time > 0：受击后的短暂无敌
##    玩家的受击无敌由 CharacterData 决定，默认 0.55s；
##    敌人默认 0s，否则霰弹枪的多弹丸打不出多发伤害。
## 4. 死亡只发一次 died 信号（_dead 标记），调用方负责做_死亡表现。

signal hp_changed(current: float, maximum: float)
signal armor_changed(current: float, maximum: float)
signal mp_changed(current: float, maximum: float)
signal died()
signal damaged(info: DamageInfo, actual_damage: float)
signal healed(amount: float)
signal mp_consumed_rejected(required: float, current: float)

## 是否为玩家（决定是否向 EventBus 广播血蓝变化）
@export var is_player: bool = false

var max_hp: float = 50.0
var max_armor: float = 0.0
var max_mp: float = 0.0

var hp: float = 50.0
var armor: float = 0.0
var mp: float = 0.0

## 伤害减免比例（0.1 = 减伤 10%）
var damage_reduction: float = 0.0
## 主动无敌（翻滚 / 冲刺）
var invincible: bool = false
## 受击后无敌剩余时间
var invincible_time: float = 0.0
## 受击无敌时长（每次受击重置）
var iframe_duration: float = 0.0

## 玩家默认受击无敌时长（秒）
## 【设计说明】玩家必须有受击无敌，否则霰弹枪级别的多弹丸齐射会瞬间秒杀；
## 敌人则必须为 0，否则「一发霰弹五瓣全中」只算一次伤害，霰弹枪的核心玩法就没了。
const PLAYER_IFRAME := 0.55

var armor_regen_delay: float = 2.5
var armor_regen_rate: float = 8.0
var mp_regen: float = 3.0
var hp_regen: float = 0.0

var _time_since_damage: float = 999.0
var _dead: bool = false
var _regen_enabled: bool = true


func _ready() -> void:
	set_process(true)


## 用属性块初始化（玩家用 CharacterData+技能树 生成的 StatBlock）
func setup_from_stats(block: StatBlock, player: bool = false, refill: bool = true) -> void:
	is_player = player
	max_hp = maxf(1.0, block.get_stat(GameEnums.StatKind.MAX_HP))
	max_armor = maxf(0.0, block.get_stat(GameEnums.StatKind.MAX_ARMOR))
	max_mp = maxf(0.0, block.get_stat(GameEnums.StatKind.MAX_MP))
	armor_regen_delay = block.get_stat(GameEnums.StatKind.ARMOR_REGEN_DELAY)
	armor_regen_rate = maxf(0.0, block.get_stat(GameEnums.StatKind.ARMOR_REGEN_RATE))
	mp_regen = maxf(0.0, block.get_stat(GameEnums.StatKind.MP_REGEN))
	hp_regen = maxf(0.0, block.get_stat(GameEnums.StatKind.HP_REGEN))
	# 玩家开受击无敌，敌人不开（见 PLAYER_IFRAME 的说明）
	iframe_duration = PLAYER_IFRAME if is_player else 0.0
	if refill:
		hp = max_hp
		armor = max_armor
		mp = max_mp
	else:
		hp = minf(hp, max_hp)
		armor = minf(armor, max_armor)
		mp = minf(mp, max_mp)
	_dead = false
	_broadcast_all()


## 简单初始化（敌人用）
func setup_simple(p_hp: float, p_armor: float = 0.0, p_mp: float = 0.0) -> void:
	max_hp = maxf(1.0, p_hp)
	max_armor = maxf(0.0, p_armor)
	max_mp = maxf(0.0, p_mp)
	hp = max_hp
	armor = max_armor
	mp = max_mp
	armor_regen_rate = 0.0
	mp_regen = 0.0
	hp_regen = 0.0
	_dead = false
	_broadcast_all()


func _process(delta: float) -> void:
	if _dead:
		return
	_time_since_damage += delta
	if invincible_time > 0.0:
		invincible_time = maxf(0.0, invincible_time - delta)
	if not _regen_enabled:
		return
	# 护甲回充（脱战延迟后）
	if max_armor > 0.0 and armor_regen_rate > 0.0 and armor < max_armor:
		if _time_since_damage >= armor_regen_delay:
			_set_armor(armor + armor_regen_rate * delta)
	# 能量回复
	if max_mp > 0.0 and mp_regen > 0.0 and mp < max_mp:
		_set_mp(mp + mp_regen * delta)
	# 生命回复
	if hp_regen > 0.0 and hp < max_hp:
		_set_hp(hp + hp_regen * delta)


func set_regen_enabled(v: bool) -> void:
	_regen_enabled = v


# ---------------------------------------------------------------------------
# 伤害
# ---------------------------------------------------------------------------

## 是否处于无敌状态
func is_invulnerable() -> bool:
	return _dead or invincible or invincible_time > 0.0


## 结算一次伤害，返回实际造成的总伤害（护甲+生命）
func apply_damage(info: DamageInfo) -> float:
	if _dead or info == null:
		return 0.0
	if invincible:
		return 0.0
	if invincible_time > 0.0 and info.can_be_blocked:
		return 0.0

	var raw: float = maxf(0.0, info.amount)
	raw *= (1.0 - clampf(damage_reduction, 0.0, 0.95))
	var total := raw

	# ① 护甲吸收
	if not info.pierce_armor and armor > 0.0 and raw > 0.0:
		var absorbed := minf(armor, raw)
		_set_armor(armor - absorbed)
		raw -= absorbed

	# ② 生命扣除
	if raw > 0.0:
		_set_hp(hp - raw)

	_time_since_damage = 0.0
	if iframe_duration > 0.0 and info.can_be_blocked:
		invincible_time = iframe_duration

	damaged.emit(info, total)
	if is_player:
		EventBus.damage_dealt.emit(get_parent(), info)
	if info.hitstop > 0.0:
		EventBus.hitstop_requested.emit(info.hitstop)
	if info.screen_shake > 0.0:
		EventBus.screen_shake_requested.emit(info.screen_shake, 0.16)

	if hp <= 0.0:
		_die()
	return total


func kill(silent: bool = false) -> void:
	if _dead:
		return
	_set_hp(0.0)
	if not silent:
		_die()
	else:
		_dead = true


func _die() -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	died.emit()


func is_dead() -> bool:
	return _dead


# ---------------------------------------------------------------------------
# 恢复
# ---------------------------------------------------------------------------

func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := hp
	_set_hp(hp + amount)
	var gained := hp - before
	if gained > 0.0:
		healed.emit(gained)
	return gained


func add_armor(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := armor
	_set_armor(armor + amount)
	return armor - before


func restore_mp(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := mp
	_set_mp(mp + amount)
	return mp - before


## 消耗能量。不足返回 false 且不扣。
func consume_mp(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if mp < amount:
		mp_consumed_rejected.emit(amount, mp)
		return false
	_set_mp(mp - amount)
	return true


# ---------------------------------------------------------------------------
# 内部 setter（统一广播）
# ---------------------------------------------------------------------------

func _set_hp(v: float) -> void:
	var nv := clampf(v, 0.0, max_hp)
	if is_equal_approx(nv, hp):
		return
	hp = nv
	hp_changed.emit(hp, max_hp)
	if is_player:
		EventBus.player_hp_changed.emit(hp, max_hp)


func _set_armor(v: float) -> void:
	var nv := clampf(v, 0.0, max_armor)
	if is_equal_approx(nv, armor):
		return
	armor = nv
	armor_changed.emit(armor, max_armor)
	if is_player:
		EventBus.player_armor_changed.emit(armor, max_armor)


func _set_mp(v: float) -> void:
	var nv := clampf(v, 0.0, max_mp)
	if is_equal_approx(nv, mp):
		return
	mp = nv
	mp_changed.emit(mp, max_mp)
	if is_player:
		EventBus.player_mp_changed.emit(mp, max_mp)


## 直接设置当前值（上限变化后重同步用）。外部请用这三个公开方法。
func set_hp_value(v: float) -> void:
	_set_hp(v)


func set_armor_value(v: float) -> void:
	_set_armor(v)


func set_mp_value(v: float) -> void:
	_set_mp(v)


func _broadcast_all() -> void:
	hp_changed.emit(hp, max_hp)
	armor_changed.emit(armor, max_armor)
	mp_changed.emit(mp, max_mp)
	if is_player:
		EventBus.player_hp_changed.emit(hp, max_hp)
		EventBus.player_armor_changed.emit(armor, max_armor)
		EventBus.player_mp_changed.emit(mp, max_mp)


# ---------------------------------------------------------------------------
# 序列化（存档只存玩家）
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"hp": hp, "armor": armor, "mp": mp}

func from_dict(d: Dictionary) -> void:
	_set_hp(float(d.get("hp", max_hp)))
	_set_armor(float(d.get("armor", max_armor)))
	_set_mp(float(d.get("mp", max_mp)))


func ratio_hp() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func ratio_armor() -> float:
	return armor / max_armor if max_armor > 0.0 else 0.0


func ratio_mp() -> float:
	return mp / max_mp if max_mp > 0.0 else 0.0
