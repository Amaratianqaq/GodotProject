class_name CharacterSkill
extends Node
## 角色主动技能基类（参考《元气骑士》每个角色的专属技能）。
##
## 【框架约束 · 必读】
## 1. 每个角色一个技能脚本，通过 CharacterData.skill_script 挂载。
##    技能脚本必须继承本类并实现 `_perform()`。
## 2. 冷却、耗蓝、可用性判断都由本基类统一处理；
##    子类只能通过 `_on_use_start()` / `_on_use_end()` 扩展表现。
## 3. 技能不得直接改血量；只能通过 Actor 的公开接口
##    （apply_knockback / set_z_height / vitals.heal ...）作用。
## 4. 技能树标签（SkillTreeService.has_tag）是技能读取「全局强化」的唯一途径。

signal used()
signal use_failed(reason: String)

## 技能 id（与 CharacterData.skill_id 一致）
var skill_id: StringName = &"skill"
## 冷却时长（秒）—— 会被技能树 ROLL_COOLDOWN 等属性修正，见 cooldown_scale()
var base_cooldown: float = 1.2
## 耗蓝
var mp_cost: float = 0.0
## 施放中
var is_active: bool = false
## 剩余冷却
var cooldown_left: float = 0.0
## 剩余可用次数（多段技能用，如「双翻滚」）
var charges: int = 1

## 角色节点（Actor）
var character: Node2D = null


func setup(p_character: Node2D) -> void:
	character = p_character


func _process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)


# ---------------------------------------------------------------------------
# 可用性
# ---------------------------------------------------------------------------

func can_use() -> bool:
	if character == null or not is_instance_valid(character):
		return false
	if bool(character.get("is_dead")):
		return false
	if is_active:
		return false
	if cooldown_left > 0.0:
		return false
	if mp_cost > 0.0:
		var v: VitalsComponent = character.get("vitals")
		if v and v.mp < mp_cost:
			return false
	return true


## 技能树对冷却的影响（覆写可自定义，例如游侠吃 ROLL_COOLDOWN）
func cooldown_scale() -> float:
	return 1.0


func effective_cooldown() -> float:
	return maxf(0.05, base_cooldown * cooldown_scale())


func cooldown_ratio() -> float:
	var cd := effective_cooldown()
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - cooldown_left / cd, 0.0, 1.0)


# ---------------------------------------------------------------------------
# 使用
# ---------------------------------------------------------------------------

func try_use() -> bool:
	if not can_use():
		use_failed.emit("技能不可用")
		return false
	if mp_cost > 0.0:
		var v: VitalsComponent = character.get("vitals")
		if v and not v.consume_mp(mp_cost):
			use_failed.emit("能量不足")
			return false
	is_active = true
	cooldown_left = effective_cooldown()
	used.emit()
	_on_use_start()
	_perform()
	return true


## 子类必须实现：一次技能的全部效果（可以 await）
func _perform() -> void:
	push_warning("[CharacterSkill] _perform 未实现: %s" % skill_id)
	is_active = false


## 子类钩子
func _on_use_start() -> void:
	pass


func _on_use_end() -> void:
	pass


## 子类在效果结束时调用
func finish() -> void:
	is_active = false
	_on_use_end()
