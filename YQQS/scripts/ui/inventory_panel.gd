class_name InventoryPanel
extends Control
## 背包界面（Tab 打开）。
##
## 【框架约束 · 必读】
## 1. 面板只做「展示 + 发起操作」，所有数据变更走 GameState.inventory /
##    WarehouseService / Player.equip_weapon，禁止在这里直接改 slots 数组。
## 2. 交互约定（全局统一，仓库面板同样遵守）：
##      左键 = 主要操作（背包装备/使用；仓库取出）
##      右键 = 次要操作（1 个/丢弃）
##      Shift + 左键 = 批量（仓库里是全部同类）
## 3. 打开时自动暂停由 SceneRouter 统一处理，面板不要自己 set_paused。

const COLS := 6
const ROWS := 4

var grid: GridContainer
var slots: Array[ItemSlot] = []
var info_label: RichTextLabel
var stats_label: RichTextLabel
var title_label: Label
var equip_slots: Array[ItemSlot] = []
var _selected: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	EventBus.inventory_changed.connect(_refresh)
	EventBus.weapon_equipped.connect(func(_d: WeaponData, _s: int) -> void: _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		SceneRouter.close_panel(&"inventory")
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	add_child(UIKit.dimmer())

	var root := UIKit.hbox(8)
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.position = Vector2(240 - 218, 135 - 96)
	root.size = Vector2(436, 192)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- 左：背包格子 ----
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UIKit.wood_stylebox())
	left.custom_minimum_size = Vector2(210, 192)
	root.add_child(left)

	var lv := UIKit.vbox(4)
	left.add_child(lv)

	title_label = UIKit.label("背包", UIKit.FS_LARGE, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	lv.add_child(title_label)

	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	lv.add_child(grid)

	var inv := GameState.inventory
	var count := inv.slot_count if inv else Inventory.DEFAULT_SLOT_COUNT
	for i in count:
		var s := ItemSlot.new()
		s.index = i
		s.source = ItemSlot.Source.INVENTORY
		s.slot_clicked.connect(_on_slot_clicked)
		s.slot_hovered.connect(_on_slot_hovered)
		grid.add_child(s)
		slots.append(s)

	# ---- 右：角色信息 + 装备 ----
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UIKit.wood_stylebox())
	right.custom_minimum_size = Vector2(218, 192)
	root.add_child(right)

	var rv := UIKit.vbox(4)
	right.add_child(rv)

	rv.add_child(UIKit.label("角色", UIKit.FS_LARGE, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	var equip_row := UIKit.hbox(6)
	equip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 2:
		var es := ItemSlot.new()
		es.index = i
		es.source = ItemSlot.Source.NONE
		es.slot_size = 30
		es.slot_clicked.connect(_on_equip_slot_clicked)
		equip_row.add_child(es)
		equip_slots.append(es)
	rv.add_child(equip_row)

	stats_label = UIKit.rich_label("", UIKit.FS_TINY)
	stats_label.custom_minimum_size = Vector2(200, 62)
	rv.add_child(stats_label)

	info_label = UIKit.rich_label("把鼠标放到物品上查看详情。", UIKit.FS_TINY)
	info_label.custom_minimum_size = Vector2(200, 54)
	rv.add_child(info_label)

	var btns := UIKit.hbox(4)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var b_use := UIKit.button("使用", UIKit.FS_SMALL)
	b_use.pressed.connect(_use_selected)
	btns.add_child(b_use)
	var b_drop := UIKit.button("丢弃", UIKit.FS_SMALL)
	b_drop.pressed.connect(_drop_selected)
	btns.add_child(b_drop)
	var b_sort := UIKit.button("整理", UIKit.FS_SMALL)
	b_sort.pressed.connect(_sort)
	btns.add_child(b_sort)
	rv.add_child(btns)

	var b_close := UIKit.button("关闭 (Tab)", UIKit.FS_SMALL)
	b_close.pressed.connect(func() -> void: SceneRouter.close_panel(&"inventory"))
	rv.add_child(b_close)


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var inv := GameState.inventory
	if inv == null:
		return
	for i in slots.size():
		slots[i].set_stack(inv.get_slot(i) if i < inv.slot_count else null)
	var p := _player()
	var used := inv.used_slots()
	title_label.text = "背包  %d / %d" % [used, inv.slot_count]
	if p:
		for i in equip_slots.size():
			var w: Node2D = p.get_weapon_in_slot(i)
			var d = w.get("data") if w else null
			if d is WeaponData:
				equip_slots[i].set_stack(ItemStack.new(d, 1))
			else:
				equip_slots[i].set_stack(null)
	_update_stats()


func _update_stats() -> void:
	var cd := GameState.character_data
	if cd == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b]  Lv.%d" % [cd.display_name, GameState.player_level])
	lines.append("生命 %d/%d   护甲 %d/%d" % [
		int(GameState.get_max_hp()), int(GameState.get_max_hp()),
		int(GameState.get_max_armor()), int(GameState.get_max_armor())
	])
	lines.append("能量 %d" % int(GameState.get_max_mp()))
	lines.append("移速 %.0f   暴击 %.0f%%" % [
		GameState.get_move_speed(), GameState.get_crit_chance() * 100.0
	])
	lines.append("伤害倍率 %.0f%%   幸运 %.1f" % [
		GameState.get_damage_mult() * 100.0,
		GameState.get_stat(GameEnums.StatKind.LUCK)
	])
	lines.append("[i]%s[/i]" % cd.description.split("\n")[0])
	stats_label.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_slot_hovered(index: int, _source: int) -> void:
	var inv := GameState.inventory
	if inv == null:
		return
	var s := inv.get_slot(index)
	if s == null or s.is_empty():
		info_label.text = "把鼠标放到物品上查看详情。"
	else:
		info_label.text = UIKit.item_tooltip(s)


func _on_slot_clicked(index: int, _source: int, mouse_button: int) -> void:
	var inv := GameState.inventory
	if inv == null:
		return
	var s := inv.get_slot(index)
	if s == null or s.is_empty():
		_selected = -1
		return
	_selected = index
	if mouse_button == MOUSE_BUTTON_RIGHT:
		if s.data is WeaponData:
			_equip(index)
		else:
			_drop_index(index, 1)
		return
	# 左键：装备 / 使用 / 无操作
	if s.data is WeaponData:
		_equip(index)
	elif s.data is ConsumableData:
		_use_index(index)
	else:
		info_label.text = UIKit.item_tooltip(s) + "\n[color=#9a94a8]（材料：可在仓库中存放）[/color]"


func _on_equip_slot_clicked(index: int, _source: int, _button: int) -> void:
	var p := _player()
	if p == null:
		return
	var w: Node2D = p.get_weapon_in_slot(index)
	if w == null:
		return
	var d: WeaponData = w.get("data")
	if d == null:
		return
	var inv := GameState.inventory
	if inv.add_item(ItemStack.new(d, 1)) > 0:
		EventBus.toast.emit("背包已满，无法卸下武器", UIKit.COL_DANGER)
		return
	p.equip_weapon(null, index)
	EventBus.toast.emit("已卸下 %s" % d.display_name, UIKit.COL_TEXT_DIM)
	_refresh()


func _equip(index: int) -> void:
	var p := _player()
	if p == null:
		EventBus.toast.emit("当前没有可操作的角色", UIKit.COL_DANGER)
		return
	var inv := GameState.inventory
	var s := inv.get_slot(index)
	if s == null or not (s.data is WeaponData):
		return
	var wd: WeaponData = s.data
	var old := p.equip_weapon(wd, p.active_slot)
	inv.take_from_slot(index, 1)
	if old:
		inv.add_item(ItemStack.new(old, 1))
	EventBus.toast.emit("装备 %s" % wd.display_name, GameEnums.rarity_color(wd.rarity))
	_refresh()


func _use_selected() -> void:
	if _selected >= 0:
		_use_index(_selected)


func _use_index(index: int) -> void:
	var p := _player()
	if p == null:
		EventBus.toast.emit("关卡外无法使用消耗品", UIKit.COL_DANGER)
		return
	var inv := GameState.inventory
	var s := inv.get_slot(index)
	if s == null or not (s.data is ConsumableData):
		return
	p.use_consumable(index)
	_refresh()


func _drop_selected() -> void:
	if _selected >= 0:
		_drop_index(_selected, -1)


func _drop_index(index: int, amount: int) -> void:
	var p := _player()
	var inv := GameState.inventory
	if inv == null:
		return
	var s := inv.get_slot(index)
	if s == null or s.is_empty():
		return
	var taken := inv.take_from_slot(index, amount)
	if taken == null:
		return
	if p and is_instance_valid(p):
		LootService.spawn_item_pickup(taken, p.global_position + Vector2(0, 10), CombatFx.fx_parent(p))
	else:
		# 大厅里没有掉落物容器时直接消失（避免物品丢失提示冲突）
		GameState.inventory.add_item(taken)
		EventBus.toast.emit("这里不能丢弃物品", UIKit.COL_DANGER)
		return
	EventBus.toast.emit("丢弃了 %s" % taken.data.display_name, UIKit.COL_TEXT_DIM)
	_refresh()


func _sort() -> void:
	var inv := GameState.inventory
	if inv == null:
		return
	# 按「武器 → 消耗品 → 材料」，品质降序排列
	var stacks := inv.all_stacks()
	stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var ta := _type_order(a)
		var tb := _type_order(b)
		if ta != tb:
			return ta < tb
		if a.get_rarity() != b.get_rarity():
			return a.get_rarity() > b.get_rarity()
		return String(a.get_id()) < String(b.get_id()))
	for i in inv.slot_count:
		inv.slots[i] = null
	for s in stacks:
		inv.add_item(s)
	inv._emit_changed()
	_refresh()


func _type_order(s: ItemStack) -> int:
	if s.data is WeaponData:
		return 0
	if s.data is ConsumableData:
		return 1
	return 2


func _player() -> Player:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player") as Player
