class_name LootTable
extends Resource
## 掉落表 —— 敌人死亡掉落、宝箱开启、房间奖励全部走这里。
##
## 【框架约束】
## 1. 任何「掉什么」都必须先在本资源里配好，代码只负责调用 LootService.roll()。
## 2. 抽取流程（LootService.roll_table）固定为：
##      ① 必定掉落 guaranteed（每条独立判定）
##      ② 按 empty_weight 判定是否「空手」
##      ③ 按 roll_count 次做加权抽取，每次独立判定品质门限
## 3. 品质提升（幸运值 luck）在 LootService 里统一施加，
##    LootTable 本身只描述基准概率。

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("抽取次数")
## 从 entries 里独立抽取的次数
@export var roll_count: int = 1
## 「空手」权重（与 entries 总权重竞争，实现「有概率不掉东西」）
@export var empty_weight: float = 0.0
## 最少产出条目数（保证下限）
@export var min_results: int = 0
## 最多产出条目数
@export var max_results: int = 8

@export_group("必定掉落")
## 无视权重，每条独立判定（probability 是 0..1 的概率）
@export var guaranteed: Array[LootEntry] = []
@export var guaranteed_chances: Array[float] = []

@export_group("随机掉落")
@export var entries: Array[LootEntry] = []

@export_group("金币")
@export var gold_min: int = 0
@export var gold_max: int = 0
## 出金币的概率
@export var gold_chance: float = 1.0

@export_group("特殊规则")
## 至少产出一件武器（宝箱用；由 weapon_drop_* 控制具体分布）
@export var guarantee_weapon: bool = false
## 产出物品的品质下限（-1 = 不限制）
@export var rarity_floor: int = -1
## 产出物品的品质上限（-1 = 不限制）
@export var rarity_ceiling: int = -1
## 品质提升强度（0 = 不受幸运影响；1 = 全额受幸运影响）
@export var luck_influence: float = 1.0

@export_group("装备掉落（第一阶段的核心掉率配置）")
## 出装备的概率（0 = 不出装备）
@export var weapon_drop_chance: float = 0.0
## 出装备的数量范围
@export var weapon_count_range: Vector2i = Vector2i(1, 1)
## 装备品质权重，顺序必须是 [白, 绿, 蓝, 橙]（会在初始化时校验长度）
@export var weapon_rarity_weights: Array[float] = [70.0, 25.0, 5.0, 0.0]
## 在 weapon_count_range 之外，额外再出一件装备的概率
@export var extra_weapon_chance: float = 0.0


## 是否配置了装备掉落
func has_weapon_drop() -> bool:
	if weapon_drop_chance <= 0.0:
		return false
	var total := 0.0
	for w in weapon_rarity_weights:
		total += maxf(0.0, w)
	return total > 0.0


func get_weapon_rarity_weights() -> Array[float]:
	## 保证长度为 4（缺的补 0）
	var out: Array[float] = []
	for i in GameEnums.RARITY_COUNT:
		out.append(weapon_rarity_weights[i] if i < weapon_rarity_weights.size() else 0.0)
	return out


func get_entries_for(rarity: int, tags: PackedStringArray) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for e in entries:
		if e.is_valid_for(rarity, tags):
			out.append(e)
	return out


func _to_string() -> String:
	return "LootTable(%s rolls=%d entries=%d)" % [id, roll_count, entries.size()]
