class_name WarehousePanel
extends Control
## 仓库界面（I 键 / 大厅仓库箱打开）。
##
## 【框架约束 · 必读】
## 1. 仓库只在 **大厅** 可用（关卡内 Player 会拦截并提示）。
## 2. 所有搬运逻辑在 WarehouseService 里，本面板只调用它的公开方法。
## 3. 交互约定与背包面板保持一致：
##      左键 = 整叠搬运；右键 = 只搬 1 个；Shift+左键 = 同类全搬。

const WH_COLS := 10
const WH_ROWS := 6

var inv_grid: GridContainer
var wh_grid: GridContainer
var inv_slots: Array[ItemSlot] = []
var wh_slots: Array[ItemSlot] = []
var info_label: RichTextLabel
var title_label: Label
var wh_title: Label
var _last_index: int = -1
var _last_source: int = ItemSlot.Source.NONE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	EventBus.warehouse_changed.connect(_refresh)
	EventBus.inventory_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("warehouse") or event.is_action_pressed("pause"):
		SceneRouter.close_panel(&"warehouse")
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	add_child(UIKit.dimmer())

	var root := UIKit.vbox(4)
	root.position = Vector2(240 - 224, 135 - 108)
	root.size = Vector2(448, 216)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var head := UIKit.hbox(6)
	title_label = UIKit.label("仓库", UIKit.FS_LARGE, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title_label.custom_minimum_size = Vector2(448, 18)
	head.add_child(title_label)
	root.add_child(head)

	var cols := UIKit.hbox(6)
	root.add_child(cols)

	# ---- 左：仓库 ----
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UIKit.wood_stylebox())
	left.custom_minimum_size = Vector2(292, 150)
	cols.add_child(left)
	var lv := UIKit.vbox(2)
	left.add_child(lv)

	wh_title = UIKit.label("", UIKit.FS_SMALL, UIKit.COL_TEXT_DIM)
	lv.add_child(wh_title)

	wh_grid = GridContainer.new()
	wh_grid.columns = WH_COLS
	wh_grid.add_theme_constant_override("h_separation", 2)
	wh_grid.add_theme_constant_override("v_separation", 2)
	lv.add_child(wh_grid)

	if WarehouseService.store == null:
		WarehouseService.store = Inventory.new(WarehouseService.DEFAULT_SLOT_COUNT)
	for i in WarehouseService.store.slot_count:
		var s := ItemSlot.new()
		s.index = i
		s.source = ItemSlot.Source.WAREHOUSE
		s.slot_size = 24
		s.slot_clicked.connect(_on_slot_clicked)
		s.slot_hovered.connect(_on_slot_hovered)
		wh_grid.add_child(s)
		wh_slots.append(s)

	# ---- 右：背包 + 操作 ----
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UIKit.wood_stylebox())
	right.custom_minimum_size = Vector2(150, 150)
	cols.add_child(right)
	var rv := UIKit.vbox(3)
	right.add_child(rv)

	rv.add_child(UIKit.label("背包", UIKit.FS_SMALL, UIKit.COL_TEXT_DIM))
	inv_grid = GridContainer.new()
	inv_grid.columns = 5
	inv_grid.add_theme_constant_override("h_separation", 2)
	inv_grid.add_theme_constant_override("v_separation", 2)
	rv.add_child(inv_grid)

	var inv := GameState.inventory
	for i in inv.slot_count:
		var s := ItemSlot.new()
		s.index = i
		s.source = ItemSlot.Source.INVENTORY
		s.slot_size = 24
		s.slot_clicked.connect(_on_slot_clicked)
		s.slot_hovered.connect(_on_slot_hovered)
		inv_grid.add_child(s)
		inv_slots.append(s)

	var b_all := UIKit.button("一键存入材料", UIKit.FS_TINY)
	b_all.pressed.connect(_deposit_all)
	rv.add_child(b_all)
	var b_sort := UIKit.button("整理仓库", UIKit.FS_TINY)
	b_sort.pressed.connect(func() -> void:
		WarehouseService.sort_store()
		_refresh())
	rv.add_child(b_sort)

	info_label = UIKit.rich_label("左键整叠搬运 · 右键单个 · Shift+左键同类全搬", UIKit.FS_TINY)
	info_label.custom_minimum_size = Vector2(292, 36)
	root.add_child(info_label)

	var b_close := UIKit.button("关闭 (I)", UIKit.FS_SMALL)
	b_close.pressed.connect(func() -> void: SceneRouter.close_panel(&"warehouse"))
	root.add_child(b_close)


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var wh := WarehouseService.store
	var inv := GameState.inventory
	if wh == null or inv == null:
		return
	title_label.text = "仓库  (账号级持久存储)"
	wh_title.text = "仓库容量 %d / %d" % [wh.used_slots(), wh.slot_count]
	for i in wh_slots.size():
		wh_slots[i].set_stack(wh.get_slot(i) if i < wh.slot_count else null)
	for i in inv_slots.size():
		inv_slots[i].set_stack(inv.get_slot(i) if i < inv.slot_count else null)
	# 保持信息栏内容
	if _last_source == ItemSlot.Source.NONE:
		info_label.text = "左键整叠搬运 · 右键单个 · Shift+左键同类全搬"


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_slot_hovered(index: int, source: int) -> void:
	var st: ItemStack = null
	if source == ItemSlot.Source.WAREHOUSE:
		st = WarehouseService.store.get_slot(index)
	else:
		st = GameState.inventory.get_slot(index)
	_last_index = index
	_last_source = source
	if st == null or st.is_empty():
		info_label.text = "左键整叠搬运 · 右键单个 · Shift+左键同类全搬"
	else:
		var where := "仓库 → 背包" if source == ItemSlot.Source.WAREHOUSE else "背包 → 仓库"
		info_label.text = UIKit.item_tooltip(st) + "\n[color=#8fd3f2]左键：%s[/color]" % where


func _on_slot_clicked(index: int, source: int, mouse_button: int) -> void:
	var inv := GameState.inventory
	if source == ItemSlot.Source.WAREHOUSE:
		var amount := -1 if mouse_button == MOUSE_BUTTON_LEFT else 1
		if Input.is_key_pressed(KEY_SHIFT):
			amount = -1
		WarehouseService.withdraw_to_inventory(inv, index, amount)
	else:
		var amount := -1 if mouse_button == MOUSE_BUTTON_LEFT else 1
		if Input.is_key_pressed(KEY_SHIFT):
			amount = -1
		WarehouseService.deposit_from_inventory(inv, index, amount)
	_refresh()


func _deposit_all() -> void:
	var n := WarehouseService.deposit_all_materials(GameState.inventory)
	if n <= 0:
		EventBus.toast.emit("没有可存入的材料", UIKit.COL_TEXT_DIM)
	_refresh()
