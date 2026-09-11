class_name LootEntry
extends Resource
## 掉落表条目。
##
## 【框架约束】
## 掉率是「配置」不是「代码」：调平衡只能改 .tres，禁止改 LootService 里的数字。

@export var item_id: StringName = &""
## 特殊占位 id：&"@random_weapon" 表示「随机一件武器」，配合 force_rarity 使用
@export var force_rarity: int = -1
## 权重（相对值，不必归一化）
@export var weight: float = 1.0
## 数量范围
@export var count_min: int = 1
@export var count_max: int = 1
## 只在该品质及以上出现（用于「稀有箱子只出绿以上」）
@export var min_rarity: int = -1
## 只在该品质及以下出现
@export var max_rarity: int = -1
## 附加条件标签（敌人 tag 满足任一即可；留空 = 无条件）
@export var require_tags: PackedStringArray = PackedStringArray()


func roll_count(rng: RandomNumberGenerator) -> int:
	if count_max <= count_min:
		return maxi(0, count_min)
	return rng.randi_range(count_min, count_max)


func is_valid_for(rarity: int, tags: PackedStringArray) -> bool:
	if min_rarity >= 0 and rarity < min_rarity:
		return false
	if max_rarity >= 0 and rarity > max_rarity:
		return false
	if not require_tags.is_empty():
		var ok := false
		for t in require_tags:
			if tags.has(t):
				ok = true
				break
		if not ok:
			return false
	return true


func _to_string() -> String:
	return "LootEntry(%s w=%.1f x%d-%d)" % [item_id, weight, count_min, count_max]
