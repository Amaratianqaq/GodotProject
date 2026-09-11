class_name CharacterData
extends Resource
## 可玩角色（英雄）静态数据。
##
## 【框架约束】
## 1. 第一阶段只有「游侠」一个角色，但数据结构必须支持多角色（大厅角色选择）。
## 2. 角色只描述「基础属性 + 主动技能 + 初始武器」；
##    角色成长（等级、技能树）是全局的，不写在这里。
## 3. 新增角色 = 新建 .tres + 在 ConfigDB 的 characters 目录自动扫描到，
##    不需要改任何代码。

@export_group("标识")
@export var id: StringName = &"ranger"
@export var display_name: String = "游侠"
@export_multiline var description: String = ""
## Atlas 中的角色图集名
@export var sprite_sheet: String = "player_ranger"
## 角色卡片主题色
@export var accent_color: Color = Color("#5c8f3a")
## 大厅内是否可选（未解锁角色置 false）
@export var unlocked: bool = true
## 解锁条件描述（未解锁时显示）
@export var unlock_hint: String = ""
## 默认解锁所需金币（0 = 免费）
@export var unlock_cost: int = 0

@export_group("基础属性")
## 生命上限
@export var max_hp: float = 50.0
## 护甲上限（脱战后自动回充的「蓝甲」）
@export var max_armor: float = 40.0
## 能量上限（蓝条）
@export var max_mp: float = 80.0
## 移动速度（像素/秒）
@export var move_speed: float = 78.0
## 基础暴击率
@export var crit_chance: float = 0.10
## 暴击倍率
@export var crit_mult: float = 2.0
## 手刀（徒手近战）伤害
@export var melee_damage: float = 4.0
## 护甲开始回充的脱战延迟（秒）
@export var armor_regen_delay: float = 2.5
## 护甲回充速度（点/秒）
@export var armor_regen_rate: float = 8.0
## 能量自然回复（点/秒）
@export var mp_regen: float = 3.0
## 生命自然回复（点/秒，通常为 0）
@export var hp_regen: float = 0.0
## 基础拾取半径
@export var pickup_radius: float = 26.0

@export_group("主动技能")
## 技能 ID（用于 UI 图标与标签查询）
@export var skill_id: StringName = &"roll"
## 技能显示名
@export var skill_name: String = "翻滚"
@export_multiline var skill_description: String = ""
## 技能实现脚本（必须实现 CharacterSkill 接口）
@export_file("*.gd") var skill_script: String = "res://scripts/entities/skills/rogue_roll.gd"
## 技能冷却（秒）
@export var skill_cooldown: float = 1.20
## 技能耗蓝
@export var skill_mp_cost: float = 0.0
## 技能图标 key（Atlas.SKILL_ICONS）
@export var skill_icon: String = "roll"

@export_group("初始装备")
## 出生自带的武器 id
@export var start_weapon_id: StringName = &"iron_sword"
## 出生自带的金币
@export var start_gold: int = 0
## 出生自带的消耗品
@export var start_items: Array[StringName] = []

@export_group("近战手感")
## 徒手攻击间隔
@export var melee_interval: float = 0.35
## 徒手攻击距离
@export var melee_range: float = 20.0


## 生成角色基础属性块
func build_stat_block() -> StatBlock:
	var b := StatBlock.new()
	b.set_base(GameEnums.StatKind.MAX_HP, max_hp)
	b.set_base(GameEnums.StatKind.MAX_ARMOR, max_armor)
	b.set_base(GameEnums.StatKind.MAX_MP, max_mp)
	b.set_base(GameEnums.StatKind.MOVE_SPEED, move_speed)
	b.set_base(GameEnums.StatKind.CRIT_CHANCE, crit_chance)
	b.set_base(GameEnums.StatKind.CRIT_MULT, crit_mult)
	b.set_base(GameEnums.StatKind.MELEE_DAMAGE, melee_damage)
	b.set_base(GameEnums.StatKind.ARMOR_REGEN_DELAY, armor_regen_delay)
	b.set_base(GameEnums.StatKind.ARMOR_REGEN_RATE, armor_regen_rate)
	b.set_base(GameEnums.StatKind.MP_REGEN, mp_regen)
	b.set_base(GameEnums.StatKind.HP_REGEN, hp_regen)
	b.set_base(GameEnums.StatKind.PICKUP_RANGE, pickup_radius)
	b.set_base(GameEnums.StatKind.DAMAGE_MULT, 1.0)
	b.set_base(GameEnums.StatKind.FIRE_RATE, 1.0)
	b.set_base(GameEnums.StatKind.RELOAD_SPEED, 1.0)
	b.set_base(GameEnums.StatKind.LUCK, 0.0)
	b.set_base(GameEnums.StatKind.ROLL_COOLDOWN, skill_cooldown)
	b.set_base(GameEnums.StatKind.ROLL_DISTANCE, 68.0)
	b.recalculate()
	return b


func get_skill_icon() -> Texture2D:
	return Atlas.skill_icon(skill_icon)


func _to_string() -> String:
	return "CharacterData(%s/%s)" % [id, display_name]
