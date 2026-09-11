class_name ItemSlot
extends Panel
## 物品格子控件（背包 / 仓库通用）。
##
## 【框架约束 · 必读】
## 1. 格子只负责「显示 + 发出交互意图」，**不直接改背包/仓库数据**；
##    数据搬运一律由持有格子的面板调用 Inventory / WarehouseService 的方法。
## 2. 索引语义：背包面板用 (index)；仓库面板用 (index, source)，
##    source 见 SlotSource 枚举，面板据此分发。
## 3. 品质用格子描边色表达，不额外加图标，保持画面干净。

enum Source { NONE, INVENTORY, WAREHOUSE }

signal slot_clicked(index: int, source: int, mouse_button: int)
signal slot_hovered(index: int, source: int)

@export var index: int = -1
@export var source: int = Source.NONE
@export var slot_size: int = UIKit.SLOT_SIZE

var stack: ItemStack = null

var _icon: TextureRect = null
var _count: Label = null
var _lock: TextureRect = null
var _hovered: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(slot_size, slot_size)
	size = Vector2(slot_size, slot_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UIKit.slot_stylebox(-1, false))
	_build()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_stack(null)


func _build() -> void:
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 3
	_icon.offset_top = 3
	_icon.offset_right = -3
	_icon.offset_bottom = -3
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count = UIKit.label("", UIKit.FS_TINY, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_count.offset_top = -12
	_count.offset_right = -2
	_count.name = "Count"
	add_child(_count)

	_lock = TextureRect.new()
	_lock.name = "Lock"
	_lock.texture = Atlas.ui_icon("lock")
	_lock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lock.custom_minimum_size = Vector2(10, 10)
	_lock.visible = false
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock)


# ---------------------------------------------------------------------------
# 显示
# ---------------------------------------------------------------------------

func set_stack(s: ItemStack, locked: bool = false) -> void:
	stack = s
	var empty := s == null or s.is_empty()
	if _icon:
		_icon.texture = null if empty else s.get_icon()
		_icon.modulate = Color.WHITE
	if _count:
		_count.text = "" if empty or s.count <= 1 else str(s.count)
	if _lock:
		_lock.visible = locked
	var rarity := -1 if empty else s.get_rarity()
	add_theme_stylebox_override("panel", UIKit.slot_stylebox(rarity, _hovered))
	tooltip_text = "" if empty else UIKit.item_tooltip(s)
	mouse_default_cursor_shape = Control.CURSOR_ARROW if empty else Control.CURSOR_POINTING_HAND


func get_stack() -> ItemStack:
	return stack


func is_empty() -> bool:
	return stack == null or stack.is_empty()


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	_hovered = true
	add_theme_stylebox_override("panel", UIKit.slot_stylebox(-1 if is_empty() else stack.get_rarity(), true))
	slot_hovered.emit(index, source)


func _on_mouse_exited() -> void:
	_hovered = false
	add_theme_stylebox_override("panel", UIKit.slot_stylebox(-1 if is_empty() else stack.get_rarity(), false))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.shift_pressed and not mb.ctrl_pressed:
				slot_clicked.emit(index, source, mb.button_index)
			elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.shift_pressed:
				slot_clicked.emit(index, source, MOUSE_BUTTON_RIGHT)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				slot_clicked.emit(index, source, MOUSE_BUTTON_LEFT)


## 供面板外部高亮（例如键盘选择）
func set_selected(v: bool) -> void:
	if v:
		add_theme_stylebox_override("panel", UIKit.slot_stylebox(
			-1 if is_empty() else stack.get_rarity(), true))
	else:
		_on_mouse_exited()
