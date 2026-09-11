class_name StatBlock
extends RefCounted
## 属性块 —— 基础值 + 加法修正 + 乘法修正，统一由 StatKind 索引。
##
## 【框架约束】
## 1. 属性读取统一走 get_stat()，永远不要直接读 base 字典。
## 2. 技能树 / 装备 / Buff 只能通过 add_flat / add_mult 注入，
##    不允许直接改 base（base 只属于角色基础配置 CharacterData）。
## 3. recalculate() 后的缓存值只读，修改修正后必须重新 recalculate()。

var base: Dictionary = {}       ## StatKind -> float（基础值）
var flat_mods: Dictionary = {}  ## StatKind -> float（加法修正汇总）
var mult_mods: Dictionary = {}  ## StatKind -> float（乘法修正汇总，1.0 = 无变化）

var _cache: Dictionary = {}


func _init(initial: Dictionary = {}) -> void:
	for k in initial.keys():
		base[k] = float(initial[k])
	recalculate()


func set_base(k: int, v: float) -> void:
	base[k] = v


func get_base(k: int) -> float:
	return float(base.get(k, 0.0))


## 注入一条加法修正
func add_flat(k: int, v: float) -> void:
	flat_mods[k] = float(flat_mods.get(k, 0.0)) + v
	_cache.erase(k)   # 关键：让缓存失效，否则 get_stat 会返回旧值


## 注入一条乘法修正（v 为增量，例如 +10% 传 0.10）
func add_mult(k: int, v: float) -> void:
	mult_mods[k] = float(mult_mods.get(k, 1.0)) + v
	_cache.erase(k)


func clear_mods() -> void:
	flat_mods.clear()
	mult_mods.clear()


## 读取最终属性值
func get_stat(k: int) -> float:
	if _cache.has(k):
		return _cache[k]
	return _compute(k)


func _compute(k: int) -> float:
	var v := get_base(k)
	v += float(flat_mods.get(k, 0.0))
	v *= float(mult_mods.get(k, 1.0))
	_cache[k] = v
	return v


func recalculate() -> void:
	_cache.clear()
	# 预计算所有出现过的键，避免运行时抖动
	for k in base.keys():
		_compute(k)
	for k in flat_mods.keys():
		_compute(k)
	for k in mult_mods.keys():
		_compute(k)


func duplicate_block() -> StatBlock:
	var s := StatBlock.new()
	s.base = base.duplicate()
	s.flat_mods = flat_mods.duplicate()
	s.mult_mods = mult_mods.duplicate()
	s.recalculate()
	return s


func _to_string() -> String:
	var parts: PackedStringArray = []
	for k in base.keys():
		parts.append("%s=%s" % [GameEnums.stat_name(k), get_stat(k)])
	return "StatBlock{%s}" % ", ".join(parts)
