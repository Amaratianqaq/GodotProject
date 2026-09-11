class_name EnemyData
extends Resource
## 敌人静态数据 + 行为参数。
##
## 【框架约束】
## 1. 敌人 AI 一律由 EnemyBase 根据 behavior 字段分发到对应 State 脚本，
##    不允许为每个怪物单独写一个继承 EnemyBase 的场景脚本（会导致无法数据驱动）。
## 2. 掉落：敌人只声明 loot_table_id 与 chest_tier，
##    具体概率全部写在 LootTable 资源里（见 res://data/loot_tables/）。
## 3. 死亡掉落的宝箱等级由 tier 决定（第一阶段规则）：
##       NORMAL 小怪 → ChestTier.NORMAL 普通宝箱
##       ELITE  精英 → ChestTier.FINE   优秀宝箱
##       BOSS   首领 → ChestTier.RARE   稀有宝箱

@export_group("标识")
@export var id: StringName = &"slime"
@export var display_name: String = "史莱姆"
@export_multiline var description: String = ""
## Atlas.ENEMY_SHEETS 的 key
@export var sheet_key: String = "slime"
## 精灵整体缩放（1 = 32px 原尺寸）
@export var sprite_scale: float = 1.0
## 精灵染色（复用同一套贴图做出变体，例如「哥布林督军」= 深色哥布林）
@export var sprite_modulate: Color = Color.WHITE
## 碰撞体半径
@export var body_radius: float = 7.0
## 视觉高度偏移（2.5D：让飞行怪浮空）
@export var hover_height: float = 0.0

@export_group("分级")
@export var tier: GameEnums.EnemyTier = GameEnums.EnemyTier.NORMAL
## 掉落宝箱等级（不填则按 tier 自动推导）
@export var chest_tier_override: int = -1
## 掉落表 id（res://data/loot_tables/*.tres 的 id）
@export var loot_table_id: StringName = &"enemy_normal"

@export_group("属性")
@export var max_hp: float = 20.0
@export var armor: float = 0.0
## 伤害减免（0.1 = 减伤 10%）
@export var damage_reduction: float = 0.0
@export var move_speed: float = 34.0
## 接触伤害（撞到玩家造成的伤害）
@export var contact_damage: float = 4.0
## 主动攻击伤害
@export var attack_damage: float = 5.0

@export_group("AI")
## 行为类型：chase_melee / ranged_kiter / erratic_flyer / hopper / charger / boss_summoner
@export var behavior: StringName = &"chase_melee"
## 发现玩家的距离
@export var detect_radius: float = 150.0
## 脱战距离
@export var lose_radius: float = 300.0
## 攻击距离（近战=挥击距离，远程=开火距离）
@export var attack_range: float = 20.0
## 进入攻击距离后停下并攻击
@export var attack_cooldown: float = 1.20
## 攻击前摇（秒）
@export var attack_windup: float = 0.25
## 攻击后摇（秒）
@export var attack_recover: float = 0.35
## 远程/特殊攻击的投射物场景
@export_file("*.tscn") var projectile_scene: String = ""
## 投射物速度
@export var projectile_speed: float = 130.0
## 单次攻击弹丸数
@export var projectile_count: int = 1
## 单次攻击的投射物伤害倍率（× attack_damage）
@export var projectile_damage_mult: float = 1.0
## 投射物散布（度）
@export var projectile_spread_deg: float = 0.0
## 单次齐射持续时间（BOSS 多段攻击用）
@export var burst_count: int = 1
@export var burst_interval: float = 0.12
## 冲锋型怪物的冲锋速度倍率
@export var charge_speed_mult: float = 2.6
## 冲锋前摇
@export var charge_windup: float = 0.6

@export_group("奖励")
@export var xp_reward: int = 8
@export var gold_min: int = 1
@export var gold_max: int = 4
## 掉落宝箱的概率（1.0 = 必掉）
@export var chest_drop_chance: float = 1.0
## 是否直接掉落金币堆（除宝箱外额外）
@export var coin_drop_chance: float = 0.6
@export var coin_drop_min: int = 1
@export var coin_drop_max: int = 5

@export_group("地图生成")
## 生成权重（越大越常见）
@export var spawn_weight: float = 1.0
## 在房间里一次生成的数量范围
@export var pack_min: int = 1
@export var pack_max: int = 3

@export_group("表现")
## 受击闪白时长
@export var hurt_flash_time: float = 0.10
## 死亡特效缩放
@export var death_scale: float = 1.4
@export var sfx_hurt: String = ""
@export var sfx_attack: String = ""
@export var sfx_die: String = ""


## 推导出的宝箱等级
func get_chest_tier() -> int:
	if chest_tier_override >= 0:
		return chest_tier_override
	match tier:
		GameEnums.EnemyTier.ELITE: return GameEnums.ChestTier.FINE
		GameEnums.EnemyTier.BOSS: return GameEnums.ChestTier.RARE
	return GameEnums.ChestTier.NORMAL


## 是否为 BOSS
func is_boss() -> bool:
	return tier == GameEnums.EnemyTier.BOSS


## 精英/BOSS 血条需要的比例
func hp_bar_scale() -> float:
	match tier:
		GameEnums.EnemyTier.ELITE: return 1.35
		GameEnums.EnemyTier.BOSS: return 3.0
	return 1.0


func _to_string() -> String:
	return "EnemyData(%s/%s/%s hp=%.0f)" % [
		id, display_name, GameEnums.EnemyTier.keys()[tier], max_hp
	]
