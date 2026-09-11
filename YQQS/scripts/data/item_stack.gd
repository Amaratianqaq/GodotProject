class_name ItemStack
extends RefCounted
## 运行时物品实例（ItemData + 数量 + 实例化附加信息）。
##
## 【框架约束】
## 1. 背包 / 仓库 / 掉落物 一律存 ItemStack，不存 ItemData。
## 2. 序列化只存 data.id，不存整个 Resource（版本升级时靠 ConfigDB 重新解析）。
## 3. 数量为 0 时视为空槽，由容器负责清理。

var data: ItemData = null
var count: int = 1

## 实例化附加数据（第一阶段预留：附魔、词条、耐久）
var instance_data: Dictionary = {}


func _init(p_data: ItemData = null, p_count: int = 1) -> void:
	data = p_data
	count = p_count


func is_empty() -> bool:
	return data == null or count <= 0


func get_id() -> StringName:
	return data.id if data else &""


func get_display_name() -> String:
	return data.display_name if data else ""


func get_rarity() -> int:
	return data.rarity if data else GameEnums.Rarity.COMMON


func get_icon() -> Texture2D:
	return data.get_icon() if data else null


func get_max_stack() -> int:
	return data.max_stack if data else 1


## 尝试合并另一堆叠，返回未能放入的剩余数量
func merge(other: ItemStack) -> int:
	if is_empty() or other.is_empty() or data != other.data:
		return other.count
	var space := get_max_stack() - count
	var moved := mini(space, other.count)
	count += moved
	other.count -= moved
	return other.count


func split(n: int) -> ItemStack:
	var take := clampi(n, 0, count)
	count -= take
	var s := ItemStack.new(data, take)
	if not instance_data.is_empty():
		s.instance_data = instance_data.duplicate()
	return s


func clone_stack() -> ItemStack:
	var s := ItemStack.new(data, count)
	s.instance_data = instance_data.duplicate()
	return s


func to_dict() -> Dictionary:
	return {
		"id": String(get_id()),
		"count": count,
		"inst": instance_data.duplicate(),
	}


## 从字典还原。
## 【重要】resolver 是「物品 id → ItemData」的解析函数，由调用方注入
## （通常是 ConfigDB.get_item）。**故意不在这里直接写 ConfigDB**，
## 否则 ItemStack → ConfigDB → ItemData → ItemStack 会形成编译期循环依赖。
static func from_dict(d: Dictionary, resolver: Callable = Callable()) -> ItemStack:
	var item_id := StringName(d.get("id", ""))
	var item: ItemData = null
	if item_id != &"" and resolver.is_valid():
		item = resolver.call(item_id) as ItemData
	if item == null:
		push_warning("[ItemStack] 无法还原物品 id: %s（存档可能来自旧版本）" % item_id)
		return null
	var s := ItemStack.new(item, int(d.get("count", 1)))
	var inst = d.get("inst", {})
	if inst is Dictionary:
		s.instance_data = inst
	return s


func _to_string() -> String:
	return "ItemStack(%s x%d)" % [get_id(), count]
