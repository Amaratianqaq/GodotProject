class_name SkillTreePanel
extends Control
## 全局技能树界面（K 键打开）。
##
## 【框架约束 · 必读】
## 1. 节点布局完全由 SkillNodeData.grid_position 决定，面板不做自动排布。
## 2. 连线由 `_on_canvas_draw` 按 prerequisites 绘制，**不要** 手动画死线。
## 3. 点节点 → SkillTreeService.unlock()；面板不自己判断条件
##    （条件判断全在 can_unlock()，避免两处逻辑不一致）。

const CELL := Vector2(42, 34)
const NODE_SIZE := 30.0
const BRANCH_COLORS := {
	&"vitality": Color("#5c8f3a"),
	&"offense": Color("#d94a4a"),
	&"mobility": Color("#4a8fd9"),
	&"fortune": Color("#b44ac9"),
	&"general": Color("#7a6a7d"),
}

var canvas: Control
var node_buttons: Dictionary = {}      ## StringName -> Button
var points_label: Label
var detail: RichTextLabel
var title_label: Label
var _hovered: StringName = &""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	EventBus.skill_points_changed.connect(func(_p: int) -> void: _refresh())
	EventBus.skill_tree_changed.connect(_refresh)
	EventBus.skill_unlocked.connect(func(_id: StringName, _lv: int) -> void: _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree") or event.is_action_pressed("pause"):
		SceneRouter.close_panel(&"skill_tree")
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	add_child(UIKit.dimmer())

	var root := UIKit.vbox(4)
	root.position = Vector2(240 - 228, 135 - 126)
	root.size = Vector2(456, 252)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 标题栏
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UIKit.panel_stylebox(
		Color(0.08, 0.07, 0.14, 0.92), UIKit.COL_BORDER, 2))
	root.add_child(head)
	var hh := UIKit.hbox(8)
	head.add_child(hh)
	title_label = UIKit.label("全局技能树", UIKit.FS_NORMAL, UIKit.COL_GOLD)
	hh.add_child(title_label)
	hh.add_child(UIKit.spacer(Vector2(20, 1)))
	points_label = UIKit.label("", UIKit.FS_NORMAL, UIKit.COL_XP)
	hh.add_child(points_label)
	var b_respec := UIKit.button("洗点", UIKit.FS_SMALL)
	b_respec.pressed.connect(func() -> void:
		SkillTreeService.respec())
	hh.add_child(b_respec)
	var b_close := UIKit.button("关闭 (K)", UIKit.FS_SMALL)
	b_close.pressed.connect(func() -> void: SceneRouter.close_panel(&"skill_tree"))
	hh.add_child(b_close)

	# 树画布
	var tree_panel := PanelContainer.new()
	tree_panel.add_theme_stylebox_override("panel", UIKit.panel_stylebox(
		Color(0.05, 0.04, 0.11, 0.95), UIKit.COL_BORDER, 2))
	tree_panel.custom_minimum_size = Vector2(456, 178)
	root.add_child(tree_panel)

	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(440, 172)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_panel.add_child(canvas)
	canvas.draw.connect(_on_canvas_draw)

	_build_nodes()

	# 详情栏
	var detail_panel := PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", UIKit.panel_stylebox(
		Color(0.08, 0.07, 0.14, 0.92), UIKit.COL_BORDER, 2))
	detail_panel.custom_minimum_size = Vector2(456, 52)
	root.add_child(detail_panel)
	detail = UIKit.rich_label("把鼠标移到技能上查看说明。", UIKit.FS_TINY)
	detail.custom_minimum_size = Vector2(444, 46)
	detail_panel.add_child(detail)


func _build_nodes() -> void:
	var tree := SkillTreeService.tree
	if tree == null:
		return
	for n in tree.nodes:
		var b := Button.new()
		b.name = "Node_" + String(n.id)
		b.size = Vector2(NODE_SIZE, NODE_SIZE)
		b.position = _node_position(n)
		b.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = false
		b.text = ""
		b.icon = Atlas.skill_icon(n.icon_id)
		b.expand_icon = true
		b.add_theme_stylebox_override("normal", _node_style(n, false))
		b.add_theme_stylebox_override("hover", _node_style(n, true))
		b.add_theme_stylebox_override("pressed", _node_style(n, true))
		b.pressed.connect(_on_node_pressed.bind(n.id))
		b.mouse_entered.connect(_on_node_hover.bind(n.id))
		b.mouse_exited.connect(_on_node_unhover.bind(n.id))
		canvas.add_child(b)
		node_buttons[n.id] = b


func _node_position(n: SkillNodeData) -> Vector2:
	# grid_position 是「列/行」，转换成像素
	var origin := Vector2(10, 8)
	return origin + Vector2(float(n.grid_position.x) * CELL.x, float(n.grid_position.y) * CELL.y)


func _node_style(n: SkillNodeData, hovered: bool) -> StyleBoxFlat:
	var lv := SkillTreeService.get_level(n.id)
	var col := Color(BRANCH_COLORS.get(n.branch, Color("#7a6a7d")))
	var can := bool(SkillTreeService.can_unlock(n.id)["ok"])
	var sb := StyleBoxFlat.new()
	if lv > 0:
		sb.bg_color = col.darkened(0.35)
		sb.border_color = col.lightened(0.3)
	elif can:
		sb.bg_color = Color(0.14, 0.12, 0.22)
		sb.border_color = READY_BORDER
	else:
		sb.bg_color = Color(0.09, 0.08, 0.15)
		sb.border_color = Color(0.28, 0.25, 0.35)
	if hovered:
		sb.border_color = READY_BORDER
	sb.set_border_width_all(2)
	if n.is_keystone:
		sb.set_border_width_all(3)
	return sb


const READY_BORDER := Color("#ffd35c")


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var tree := SkillTreeService.tree
	if tree == null:
		return
	points_label.text = "技能点 %d   角色等级 %d" % [
		SkillTreeService.points, GameState.player_level
	]
	for n in tree.nodes:
		var b: Button = node_buttons.get(n.id)
		if b == null:
			continue
		b.add_theme_stylebox_override("normal", _node_style(n, false))
		b.add_theme_stylebox_override("hover", _node_style(n, true))
		var lv := SkillTreeService.get_level(n.id)
		var maxlv := n.max_level
		if lv > 0:
			b.text = "%d/%d" % [lv, maxlv]
			b.add_theme_font_size_override("font_size", UIKit.FS_TINY)
			b.add_theme_color_override("font_color", UIKit.COL_TEXT)
		else:
			b.text = "0/%d" % maxlv
			b.add_theme_font_size_override("font_size", UIKit.FS_TINY)
			b.add_theme_color_override("font_color", UIKit.COL_TEXT_DIM)
		b.tooltip_text = "%s\n%s" % [n.display_name, n.description]
	canvas.queue_redraw()
	if _hovered != &"":
		_show_detail(_hovered)


func _show_detail(id: StringName) -> void:
	var n := SkillTreeService.tree.get_node_by_id(id)
	if n == null:
		return
	var lv := SkillTreeService.get_level(id)
	var res := SkillTreeService.can_unlock(id)
	var lines: PackedStringArray = PackedStringArray()
	var col: Color = BRANCH_COLORS.get(n.branch, Color("#7a6a7d"))
	lines.append("[color=#%s][b]%s[/b][/color]  %d/%d 级" % [
		col.to_html(false), n.display_name, lv, n.max_level
	])
	lines.append(n.description)
	if not n.effects.is_empty():
		var effs: PackedStringArray = PackedStringArray()
		for e in n.effects:
			effs.append(e.describe(maxi(1, lv if lv > 0 else 1)))
		lines.append("[color=#8fc75a]当前效果：%s[/color]" % "，".join(effs))
	if not n.granted_tags.is_empty():
		lines.append("[color=#f28fc9]解锁能力：%s[/color]" % ", ".join(n.granted_tags))
	if lv < n.max_level:
		if res["ok"]:
			lines.append("[color=#ffd35c]点击升级（消耗 %d 技能点）[/color]" % n.cost_to_upgrade(lv))
		else:
			lines.append("[color=#d94a4a]%s[/color]" % res["reason"])
	else:
		lines.append("[color=#8fc75a]已满级[/color]")
	detail.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_node_pressed(id: StringName) -> void:
	SkillTreeService.unlock(id)
	_refresh()


func _on_node_hover(id: StringName) -> void:
	_hovered = id
	_show_detail(id)


func _on_node_unhover(id: StringName) -> void:
	if _hovered == id:
		_hovered = &""
		detail.text = "把鼠标移到技能上查看说明。"


# ---------------------------------------------------------------------------
# 连线绘制
# ---------------------------------------------------------------------------

func _on_canvas_draw() -> void:
	var tree := SkillTreeService.tree
	if tree == null:
		return
	for n in tree.nodes:
		var to_pos := _node_position(n) + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5)
		for pre_id in n.prerequisites:
			var pre := tree.get_node_by_id(pre_id)
			if pre == null:
				continue
			var from_pos := _node_position(pre) + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5)
			var unlocked := SkillTreeService.get_level(pre_id) > 0
			var col := Color("#ffd35c") if (unlocked and SkillTreeService.get_level(n.id) > 0) else \
				(Color("#8a7f5a") if unlocked else Color("#38304a"))
			# 先画一条粗底线再画亮线，得到像素风的描边感
			canvas.draw_line(from_pos, to_pos, Color(0.03, 0.02, 0.08, 0.9), 4.0)
			canvas.draw_line(from_pos, to_pos, col, 2.0)
