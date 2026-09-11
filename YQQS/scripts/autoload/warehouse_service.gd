extends Node
## WarehouseService —— 仓库（自动加载单例，持久化）。
##
## 【框架约束 · 必读】
## 1. 仓库是「账号级」持久容器，与背包（GameState.inventory）分离。
##    仓库只在 **大厅** 可交互；关卡内不允许开仓库（第一阶段规则）。
## 2. 仓库物品永不丢失：空间不足时存入失败并给玩家提示，
##    不允许静默丢弃物品。
## 3. UI 只做展示与拖拽发起，真正的搬运逻辑都在本文件里，
##    这样仓库逻辑可在无 UI 的自动化测试里直接调用。

const DEFAULT_SLOT_COUNT := 60

var store: Inventory = null
## 仓库扩容次数（第二阶段商店用）
var expansions: int = 0


func _ready() -> void:
	store = Inventory.new(DEFAULT_SLOT_COUNT)
	store.slots.resize(DEFAULT_SLOT_COUNT)


func get_capacity() -> int:
	return DEFAULT_SLOT_COUNT + expansions * 20


# ---------------------------------------------------------------------------
# 存取
# ---------------------------------------------------------------------------

## 把背包第 from_index 格（或全部同类）存入仓库
## 返回实际存入的数量
func deposit_from_inventory(inv: Inventory, from_index: int, amount: int = -1) -> int:
	if inv == null or store == null:
		return 0
	var stack := inv.get_slot(from_index)
	if stack == null or stack.is_empty():
		return 0
	var take := stack.count if amount < 0 else clampi(amount, 1, stack.count)
	var moved := stack.split(take)
	if stack.count <= 0:
		inv.set_slot(from_index, null)
	inv._emit_changed()
	var leftover := store.add_item(moved)
	var stored := take - leftover
	if leftover > 0:
		# 仓库满 → 退回背包
		var back := ItemStack.new(moved.data, leftover)
		inv.add_item(back)
		EventBus.toast.emit("仓库已满", Color("#d94a4a"))
	if stored > 0:
		EventBus.warehouse_changed.emit()
		EventBus.toast.emit("存入 %s ×%d" % [moved.data.display_name, stored], Color("#8fc75a"))
	return stored


## 把仓库第 from_index 格取回背包
func withdraw_to_inventory(inv: Inventory, from_index: int, amount: int = -1) -> int:
	if inv == null or store == null:
		return 0
	var stack := store.get_slot(from_index)
	if stack == null or stack.is_empty():
		return 0
	var take := stack.count if amount < 0 else clampi(amount, 1, stack.count)
	var moved := stack.split(take)
	if stack.count <= 0:
		store.set_slot(from_index, null)
	var leftover := inv.add_item(moved)
	var taken := take - leftover
	if leftover > 0:
		store.add_item(ItemStack.new(moved.data, leftover))
		EventBus.toast.emit("背包已满", Color("#d94a4a"))
	if taken > 0:
		EventBus.warehouse_changed.emit()
		EventBus.inventory_changed.emit()
		EventBus.toast.emit("取出 %s ×%d" % [moved.data.display_name, taken], Color("#8fd3f2"))
	return taken


## 一键把背包中所有可堆叠材料存入仓库
func deposit_all_materials(inv: Inventory) -> int:
	if inv == null:
		return 0
	var total := 0
	for i in inv.slot_count:
		var s := inv.get_slot(i)
		if s == null or s.is_empty():
			continue
		if s.data.item_type == GameEnums.ItemType.MATERIAL:
			total += deposit_from_inventory(inv, i, -1)
	return total


## 直接把一个堆叠塞进仓库（掉落/奖励用，不经过背包）
func store_stack(stack: ItemStack) -> int:
	if store == null or stack == null:
		return 0
	var leftover := store.add_item(stack)
	if leftover > 0:
		EventBus.toast.emit("仓库已满，%s 遗失" % stack.data.display_name, Color("#d94a4a"))
	EventBus.warehouse_changed.emit()
	return stack.count - leftover


func find_slot(item_id: StringName) -> int:
	return store.find_slot_of(item_id) if store else -1


## 排序：按品质从高到低、同品质按 id
func sort_store() -> void:
	if store == null:
		return
	var stacks := store.all_stacks()
	stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		if a.get_rarity() != b.get_rarity():
			return a.get_rarity() > b.get_rarity()
		return String(a.get_id()) < String(b.get_id()))
	for i in store.slot_count:
		store.slots[i] = null
	for s in stacks:
		store.add_item(s)
	EventBus.warehouse_changed.emit()


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"store": store.to_dict() if store else {},
		"expansions": expansions,
	}


func from_dict(d: Dictionary) -> void:
	if store == null:
		store = Inventory.new(DEFAULT_SLOT_COUNT)
	store.from_dict(d.get("store", {}))
	expansions = int(d.get("expansions", 0))
	EventBus.warehouse_changed.emit()


func reset() -> void:
	if store == null:
		store = Inventory.new(DEFAULT_SLOT_COUNT)
	else:
		store.clear()
	expansions = 0
	EventBus.warehouse_changed.emit()
