class_name Inventory
extends RefCounted
## 背包模型（纯数据，不依赖任何 UI）。
##
## 【框架约束】
## 1. 背包只有「操作成功/失败」的语义，**不** 负责播放音效 / 弹提示；
##    这些由订阅 EventBus.inventory_changed 的 UI 层负责。
## 2. 任何修改背包的操作必须走本类的方法，禁止外部直接改 slots 数组。
## 3. 槽位顺序稳定：新增物品优先填已有同类堆叠，其次填第一个空槽。

const DEFAULT_SLOT_COUNT := 24

var slot_count: int = DEFAULT_SLOT_COUNT
var slots: Array[ItemStack] = []


func _init(count: int = DEFAULT_SLOT_COUNT) -> void:
	slot_count = maxi(1, count)
	slots.resize(slot_count)


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func is_valid_index(i: int) -> bool:
	return i >= 0 and i < slot_count


func get_slot(i: int) -> ItemStack:
	if not is_valid_index(i):
		return null
	return slots[i]


func set_slot(i: int, stack: ItemStack) -> void:
	if not is_valid_index(i):
		return
	slots[i] = stack if (stack and not stack.is_empty()) else null
	_emit_changed()


func is_empty() -> bool:
	for s in slots:
		if s and not s.is_empty():
			return false
	return true


func used_slots() -> int:
	var n := 0
	for s in slots:
		if s and not s.is_empty():
			n += 1
	return n


func free_slots() -> int:
	return slot_count - used_slots()


func count_of(item_id: StringName) -> int:
	var n := 0
	for s in slots:
		if s and s.get_id() == item_id:
			n += s.count
	return n


func has_item(item_id: StringName, amount: int = 1) -> bool:
	return count_of(item_id) >= amount


func find_slot_of(item_id: StringName) -> int:
	for i in slot_count:
		var s := slots[i]
		if s and s.get_id() == item_id:
			return i
	return -1


func first_empty_slot() -> int:
	for i in slot_count:
		if slots[i] == null or slots[i].is_empty():
			return i
	return -1


func all_stacks() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for s in slots:
		if s and not s.is_empty():
			out.append(s)
	return out


func total_items() -> int:
	var n := 0
	for s in slots:
		if s:
			n += s.count
	return n


# ---------------------------------------------------------------------------
# 修改
# ---------------------------------------------------------------------------

## 放入物品。返回 **未能放入的剩余数量**（0 = 全部放入）。
func add_item(stack: ItemStack) -> int:
	if stack == null or stack.is_empty():
		return 0
	var remaining := stack.count
	var max_stack := stack.get_max_stack()

	# ① 先补已有堆叠
	if max_stack > 1:
		for i in slot_count:
			if remaining <= 0:
				break
			var s := slots[i]
			if s and not s.is_empty() and s.data == stack.data and s.count < max_stack:
				var space := max_stack - s.count
				var moved := mini(space, remaining)
				s.count += moved
				remaining -= moved

	# ② 再开新槽
	while remaining > 0:
		var idx := first_empty_slot()
		if idx < 0:
			break
		var take := mini(remaining, max_stack)
		slots[idx] = ItemStack.new(stack.data, take)
		remaining -= take
		if take <= 0:
			break

	if remaining != stack.count:
		_emit_changed()
	return remaining


## 按 id 扣除数量，返回是否成功（不足则不扣除）
func remove_item(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if count_of(item_id) < amount:
		return false
	var remaining := amount
	for i in slot_count:
		if remaining <= 0:
			break
		var s := slots[i]
		if s == null or s.is_empty() or s.get_id() != item_id:
			continue
		var take := mini(s.count, remaining)
		s.count -= take
		remaining -= take
		if s.count <= 0:
			slots[i] = null
	_emit_changed()
	return true


## 从指定槽位取出 n 个，返回取出的堆叠（可能为 null）
func take_from_slot(i: int, n: int = -1) -> ItemStack:
	if not is_valid_index(i):
		return null
	var s := slots[i]
	if s == null or s.is_empty():
		return null
	var take := s.count if n < 0 else clampi(n, 1, s.count)
	var out := s.split(take)
	if s.count <= 0:
		slots[i] = null
	_emit_changed()
	return out


## 交换两个槽位
func swap_slots(a: int, b: int) -> void:
	if not is_valid_index(a) or not is_valid_index(b) or a == b:
		return
	var tmp := slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	_emit_changed()


## 合并同 id 的堆叠并整理（左对齐）
func compact() -> void:
	var stacks := all_stacks()
	for i in slot_count:
		slots[i] = null
	for s in stacks:
		add_item(s)
	_emit_changed()


## 清空
func clear() -> void:
	for i in slot_count:
		slots[i] = null
	_emit_changed()


func grow(new_count: int) -> void:
	if new_count <= slot_count:
		return
	slot_count = new_count
	slots.resize(slot_count)
	_emit_changed()


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var arr: Array = []
	for i in slot_count:
		var s := slots[i]
		arr.append(s.to_dict() if (s and not s.is_empty()) else null)
	return {"slots": slot_count, "items": arr}


func from_dict(d: Dictionary) -> void:
	slot_count = maxi(1, int(d.get("slots", DEFAULT_SLOT_COUNT)))
	slots.clear()
	slots.resize(slot_count)
	var arr: Array = d.get("items", [])
	for i in mini(arr.size(), slot_count):
		if arr[i] == null:
			continue
		if arr[i] is Dictionary:
			slots[i] = ItemStack.from_dict(arr[i], _item_resolver)
	_emit_changed()


## 物品 id → ItemData 的解析函数（注入给 ItemStack.from_dict）
func _item_resolver(id: StringName) -> ItemData:
	return ConfigDB.get_item(id)


func _emit_changed() -> void:
	if EventBus:
		EventBus.inventory_changed.emit()
