class_name UIKit
extends RefCounted
## UI 工具箱 —— 全部界面共用的样式与控件工厂。
##
## 【框架约束 · 必读】
## 1. 项目采用「代码构建 UI」策略：.tscn 只放一个挂脚本的根节点，
##    子控件全部在 _ready() 里用本文件的工厂函数创建。
##    理由：本项目 UI 高度数据驱动（背包/仓库/技能树格子数量都随配置变化），
##    手写 .tscn 反而更难维护，且极易出错。
## 2. **禁止** 在界面对话里写颜色字面量；一律用 UIKit 的语义色常量。
## 3. 所有界面根节点必须是 Control 且铺满（PRESET_FULL_RECT），
##    由 SceneRouter 统一挂到 CanvasLayer(50) 下。
## 4. 字体走 ThemeDB.fallback_font（由 SceneRouter 设置的中文系统字体），
##    界面里只允许用 add_theme_font_size_override 调字号。

# ---------------------------------------------------------------------------
# 语义色
# ---------------------------------------------------------------------------

const COL_BG := Color("#141021")
const COL_PANEL := Color("#1e1830")
const COL_PANEL_DARK := Color("#0d0b1f")
const COL_BORDER := Color("#6b4a2f")
const COL_BORDER_LIGHT := Color("#a3713f")
const COL_TEXT := Color("#e8e4dc")
const COL_TEXT_DIM := Color("#9a94a8")
const COL_GOLD := Color("#ffd35c")
const COL_HP := Color("#d94a4a")
const COL_ARMOR := Color("#4a8fd9")
const COL_MP := Color("#4a8fd9")
const COL_XP := Color("#8fc75a")
const COL_DANGER := Color("#d94a4a")
const COL_OK := Color("#8fc75a")
const COL_SLOT_BG := Color("#241d38")
const COL_SLOT_HOVER := Color("#3a3050")

# ---------------------------------------------------------------------------
# 尺寸规范（像素 · 对应 480x270 逻辑分辨率）
# ---------------------------------------------------------------------------

const FS_TINY := 9
const FS_SMALL := 11
const FS_NORMAL := 13
const FS_LARGE := 18
const FS_TITLE := 24

const SLOT_SIZE := 26
const PADDING := 6


# ---------------------------------------------------------------------------
# 样式
# ---------------------------------------------------------------------------

## 深色面板样式（可指定描边色）
static func panel_stylebox(
	bg: Color = COL_PANEL, border: Color = COL_BORDER, width: int = 2
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = PADDING
	sb.content_margin_right = PADDING
	sb.content_margin_top = PADDING
	sb.content_margin_bottom = PADDING
	return sb


## 木质九宫格面板（用 ui_panel.png）
static func wood_stylebox() -> StyleBox:
	var tex := Atlas.sheet("ui_panel")
	if tex == null:
		return panel_stylebox(COL_PANEL, COL_BORDER, 2)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var m := 10
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = m + 2
	sb.content_margin_right = m + 2
	sb.content_margin_top = m + 2
	sb.content_margin_bottom = m + 2
	return sb


## 格子样式（带品质描边）
static func slot_stylebox(rarity: int = -1, hovered: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_SLOT_HOVER if hovered else COL_SLOT_BG
	var bc := Color(GameEnums.rarity_color(rarity)) if rarity >= 0 else COL_BORDER
	sb.border_color = bc
	sb.set_border_width_all(2 if rarity >= 0 else 1)
	return sb


# ---------------------------------------------------------------------------
# 控件工厂
# ---------------------------------------------------------------------------

static func label(
	text: String, size: int = FS_NORMAL, color: Color = COL_TEXT,
	align: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", COL_PANEL_DARK)
	l.add_theme_constant_override("outline_size", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich_label(text: String, size: int = FS_SMALL) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", COL_TEXT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, size: int = FS_NORMAL) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", COL_TEXT_DIM)
	_style_button(b)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", panel_stylebox(COL_SLOT_BG, COL_BORDER, 2))
	b.add_theme_stylebox_override("hover", panel_stylebox(COL_SLOT_HOVER, COL_BORDER_LIGHT, 2))
	b.add_theme_stylebox_override("pressed", panel_stylebox(COL_PANEL_DARK, COL_GOLD, 2))
	b.add_theme_stylebox_override("disabled", panel_stylebox(COL_PANEL_DARK, COL_BORDER, 1))
	b.add_theme_stylebox_override("focus", panel_stylebox(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))


## 带木质边框的面板容器
static func panel(title: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", wood_stylebox())
	if title != "":
		var v := VBoxContainer.new()
		v.name = "Root"
		var t := label(title, FS_LARGE, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		t.name = "Title"
		v.add_child(t)
		var sep := HSeparator.new()
		v.add_child(sep)
		p.add_child(v)
	return p


## 普通底色容器（无边框）
static func color_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 半透明全屏遮罩（模态面板背景）
static func dimmer(alpha: float = 0.62) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.03, 0.09, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## 水平分隔线（像素风：一条 2px 深色 + 一条 1px 亮色）
static func separator() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 3)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := ColorRect.new()
	a.color = COL_BORDER
	a.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	a.custom_minimum_size = Vector2(0, 2)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(a)
	return c


## 图标 + 文本的小行（用于 HUD 资源显示）
static func icon_text_row(icon_id: String, text: String, color: Color = COL_TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var tex := Atlas.ui_icon(icon_id)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(12, 12)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		h.add_child(tr)
	h.add_child(label(text, FS_SMALL, color))
	return h


## 品质名称文本（带品质色）
static func rarity_text(rarity: int, name_text: String) -> Label:
	var l := label(name_text, FS_SMALL, GameEnums.rarity_color(rarity))
	return l


# ---------------------------------------------------------------------------
# 布局辅助
# ---------------------------------------------------------------------------

static func vbox(separation: int = 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(min_size: Vector2 = Vector2.ZERO) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 居中容器
static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c


## 物品 tooltip 文本（BBCode）
static func item_tooltip(stack: ItemStack) -> String:
	if stack == null or stack.data == null:
		return ""
	var d := stack.data
	var col := GameEnums.rarity_color(d.rarity)
	var hex := "#" + col.to_html(false)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=%s][b]%s[/b][/color]" % [hex, d.display_name])
	lines.append("[color=#9a94a8]%s[/color]" % GameEnums.rarity_name(d.rarity))
	if d is WeaponData:
		var w: WeaponData = d
		lines.append("伤害 %.1f    射速 %.2fs" % [w.damage, w.fire_rate])
		if w.projectile_count > 1:
			lines.append("弹丸 %d   单发总伤 %.1f" % [w.projectile_count, w.total_damage_per_shot()])
		lines.append("DPS 约 %.1f" % w.estimated_dps())
		if w.magazine > 0:
			lines.append("弹匣 %d   换弹 %.2fs" % [w.magazine, w.reload_time])
		if w.energy_cost > 0.0:
			lines.append("耗能 %.0f" % w.energy_cost)
		if w.crit_bonus > 0.0:
			lines.append("暴击 +%.0f%%" % (w.crit_bonus * 100.0))
		if not WeaponRegistry.has_custom_implementation(w):
			lines.append("[color=#9a94a8]（第一阶段：仅有贴图，未实装专属机制）[/color]")
	if d is ConsumableData:
		lines.append("[(%s)]" % (d as ConsumableData).describe_effect())
	if d.description != "":
		lines.append("[i]%s[/i]" % d.description)
	if d.sell_price > 0:
		lines.append("[color=#ffd35c]售价 %d[/color]" % d.sell_price)
	return "\n".join(lines)
