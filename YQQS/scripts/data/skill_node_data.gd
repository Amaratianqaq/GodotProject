class_name SkillNodeData
extends Resource
## 技能树节点定义。
##
## 【框架约束】
## 1. 技能树是「全局」的：跨角色、跨关卡、跨存档保留（存于 user:// 存档）。
## 2. 节点 id 全局唯一；prerequisites 只允许引用已存在的节点 id，
##    不允许出现环（SkillTreeService 初始化时会做环检测，发现环直接报错）。
## 3. grid_position 是技能树面板里的网格坐标（单位：格），
##    由 UI 负责画连线，数据层不管布局算法。

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = "未命名技能"
@export_multiline var description: String = ""
## 图标 key，对应 Atlas.SKILL_ICONS
@export var icon_id: String = "roll"

@export_group("树结构")
## 所属分支（用于配色与分组，如 "rogue" / "general"）
@export var branch: StringName = &"general"
## 面板网格坐标
@export var grid_position: Vector2i = Vector2i.ZERO
## 前置技能（全部点满才能解锁本节点）
@export var prerequisites: Array[StringName] = []
## 前置节点需要的最低等级（与 prerequisites 一一对应；为空则默认 1）
@export var prerequisite_levels: Array[int] = []

@export_group("等级与消耗")
@export var max_level: int = 1
## 每级消耗技能点
@export var cost_per_level: int = 1
## 解锁本节点额外需要的角色等级（全局等级）
@export var required_player_level: int = 1

@export_group("效果")
## 每级属性效果
@export var effects: Array[StatEffect] = []
## 解锁的能力标签（供代码查询，例如 "double_roll" "petal_bounce"）
@export var granted_tags: PackedStringArray = PackedStringArray()

@export_group("表现")
@export var is_keystone: bool = false   ## 关键天赋（更大更亮）
@export var sort_order: int = 0


func total_cost(to_level: int) -> int:
	return cost_per_level * maxi(1, to_level)


func cost_to_upgrade(from_level: int) -> int:
	if from_level >= max_level:
		return 0
	return cost_per_level


func describe_effects(level: int = 1) -> String:
	var parts: PackedStringArray = []
	for e in effects:
		parts.append(e.describe(level))
	if parts.is_empty():
		return description
	return "\n".join(parts)


func has_effect_on(stat: int) -> bool:
	for e in effects:
		if e.stat == stat:
			return true
	return false


func _to_string() -> String:
	return "SkillNodeData(%s)" % id
