class_name StatEffect
extends Resource
## 一条属性效果（技能树 / 装备 / Buff 通用）。
##
## 【框架约束】
## 效果只描述「每级加多少」，不做任何运行时逻辑。
## 运行时由 StatBlock.add_flat / add_mult 注入。

@export var stat: GameEnums.StatKind = GameEnums.StatKind.MAX_HP
## 每级增量。is_mult=true 时是「每级百分比」，如 0.05 表示每级 +5%
@export var per_level: float = 0.0
## true = 乘法修正（百分比），false = 加法修正（绝对值）
@export var is_mult: bool = false


func apply_to(block: StatBlock, level: int) -> void:
	if level <= 0 or is_zero_approx(per_level):
		return
	var total := per_level * float(level)
	if is_mult:
		block.add_mult(stat, total)
	else:
		block.add_flat(stat, total)


func describe(level: int = 1) -> String:
	var v := per_level * float(maxi(1, level))
	var s := GameEnums.format_stat(stat, v)
	return "%s %s" % [GameEnums.stat_name(stat), s]


func duplicate_effect() -> StatEffect:
	var e := StatEffect.new()
	e.stat = stat
	e.per_level = per_level
	e.is_mult = is_mult
	return e
