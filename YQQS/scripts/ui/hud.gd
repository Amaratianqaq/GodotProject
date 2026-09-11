class_name Hud
extends Control
## 游戏内 HUD（血/甲/蓝条、经验、金币、武器与弹药、技能冷却、BOSS 血条、提示）。
##
## 【框架约束 · 必读】
## 1. HUD 只订阅 EventBus 信号 + 每帧读取 GameState / RunManager / Player 的只读状态，
##    **绝不** 修改游戏数据。
## 2. 布局使用固定像素坐标（逻辑分辨率固定 480x270），
##    不依赖 anchor 计算，保证在任何窗口尺寸下观感一致。
## 3. 新增 HUD 元素请走 `_place()` 统一入口，保持 6px 边距规范。

const MARGIN := 6

# --- 左上：生命 / 护甲 / 能量 / 经验 ---
var hp_bar: StatBar
var armor_bar: StatBar
var mp_bar: StatBar
var xp_bar: StatBar
var level_label: Label

# --- 右上：金币 / 关卡信息 ---
var gold_label: Label
var info_label: Label

# --- 左下：武器 ---
var weapon_slots: Array = []          # [TextureRect, TextureRect]
var weapon_panels: Array = []         # [Panel, Panel]
var ammo_label: Label
var reload_bar: StatBar
var weapon_name_label: Label

# --- 右下：技能 ---
var skill_panel: Panel
var skill_icon: TextureRect
var skill_cd_bar: StatBar
var crit_ready_label: Label

# --- 顶部中央：BOSS 血条 ---
var boss_panel: Control
var boss_name: Label
var boss_bar: StatBar

# --- 底部中央：交互提示 / 提示条 ---
var prompt_label: Label
var toast_box: VBoxContainer

var _player: Player = null
var _boss: Node = null
var _toasts: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_hp_changed.connect(_on_hp)
	EventBus.player_armor_changed.connect(_on_armor)
	EventBus.player_mp_changed.connect(_on_mp)
	EventBus.player_level_changed.connect(_on_level)
	EventBus.gold_changed.connect(_on_gold)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)
	EventBus.toast.connect(_on_toast)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.skill_tree_changed.connect(_refresh_all)


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	c.custom_minimum_size = Vector2(w, h)


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	_build_vitals()
	_build_top_right()
	_build_weapon()
	_build_skill()
	_build_boss()
	_build_prompt_and_toasts()


func _build_vitals() -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UIKit.panel_stylebox(
		Color(0.06, 0.05, 0.12, 0.78), UIKit.COL_BORDER, 1))
	_place(panel, MARGIN, MARGIN, 132, 46)
	add_child(panel)

	level_label = UIKit.label("Lv.1 游侠", UIKit.FS_TINY, UIKit.COL_GOLD)
	_place(level_label, 4, 2, 124, 11)
	panel.add_child(level_label)

	hp_bar = StatBar.new()
	hp_bar.set_bar_colors(UIKit.COL_HP)
	hp_bar.text_size = UIKit.FS_TINY
	_place(hp_bar, 4, 14, 124, 11)
	panel.add_child(hp_bar)

	armor_bar = StatBar.new()
	armor_bar.set_bar_colors(Color("#4a8fd9"))
	armor_bar.show_ghost = false
	_place(armor_bar, 4, 26, 124, 5)
	panel.add_child(armor_bar)

	mp_bar = StatBar.new()
	mp_bar.set_bar_colors(Color("#4a8fd9"))
	_place(mp_bar, 4, 32, 124, 7)
	panel.add_child(mp_bar)

	xp_bar = StatBar.new()
	xp_bar.set_bar_colors(UIKit.COL_XP)
	xp_bar.show_ghost = false
	xp_bar.border_width = 1
	_place(xp_bar, 4, 40, 124, 4)
	panel.add_child(xp_bar)


func _build_top_right() -> void:
	gold_label = UIKit.label("0", UIKit.FS_SMALL, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(gold_label, 480 - MARGIN - 120, MARGIN, 120, 13)
	add_child(gold_label)

	info_label = UIKit.label("", UIKit.FS_TINY, UIKit.COL_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(info_label, 480 - MARGIN - 200, MARGIN + 13, 200, 11)
	add_child(info_label)


func _build_weapon() -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UIKit.panel_stylebox(
		Color(0.06, 0.05, 0.12, 0.78), UIKit.COL_BORDER, 1))
	_place(panel, MARGIN, 270 - MARGIN - 40, 128, 40)
	add_child(panel)

	for i in 2:
		var p := Panel.new()
		p.add_theme_stylebox_override("panel", UIKit.slot_stylebox(-1, i == 0))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(p, 3 + i * 26, 12, 24, 24)
		panel.add_child(p)
		weapon_panels.append(p)

		var tr := TextureRect.new()
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 2
		tr.offset_top = 2
		tr.offset_right = -2
		tr.offset_bottom = -2
		p.add_child(tr)
		weapon_slots.append(tr)

	weapon_name_label = UIKit.label("徒手", UIKit.FS_TINY, UIKit.COL_TEXT)
	_place(weapon_name_label, 56, 3, 70, 11)
	panel.add_child(weapon_name_label)

	ammo_label = UIKit.label("", UIKit.FS_SMALL, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(ammo_label, 56, 15, 68, 13)
	panel.add_child(ammo_label)

	reload_bar = StatBar.new()
	reload_bar.set_bar_colors(UIKit.COL_GOLD)
	reload_bar.show_ghost = false
	_place(reload_bar, 56, 30, 68, 6)
	panel.add_child(reload_bar)


func _build_skill() -> void:
	skill_panel = Panel.new()
	skill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_panel.add_theme_stylebox_override("panel", UIKit.slot_stylebox(-1, false))
	_place(skill_panel, 480 - MARGIN - 28, 270 - MARGIN - 28, 28, 28)
	add_child(skill_panel)

	skill_icon = TextureRect.new()
	skill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skill_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_icon.offset_left = 3
	skill_icon.offset_top = 3
	skill_icon.offset_right = -3
	skill_icon.offset_bottom = -3
	skill_panel.add_child(skill_icon)

	skill_cd_bar = StatBar.new()
	skill_cd_bar.vertical = true
	skill_cd_bar.set_bar_colors(Color(0.05, 0.04, 0.12, 0.72))
	skill_cd_bar.show_ghost = false
	skill_cd_bar.border_width = 0
	_place(skill_cd_bar, 480 - MARGIN - 28, 270 - MARGIN - 28, 28, 28)
	skill_cd_bar.ratio = 1.0
	add_child(skill_cd_bar)

	crit_ready_label = UIKit.label("", UIKit.FS_TINY, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_place(crit_ready_label, 480 - MARGIN - 88, 270 - MARGIN - 42, 60, 11)
	add_child(crit_ready_label)


func _build_boss() -> void:
	boss_panel = Control.new()
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(boss_panel, 140, 8, 200, 22)
	boss_panel.visible = false
	add_child(boss_panel)

	boss_name = UIKit.label("哥布林大祭司", UIKit.FS_TINY, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_place(boss_name, 0, 0, 200, 12)
	boss_panel.add_child(boss_name)

	boss_bar = StatBar.new()
	boss_bar.set_bar_colors(Color("#b44ac9"))
	boss_bar.show_ghost = true
	_place(boss_bar, 0, 13, 200, 9)
	boss_panel.add_child(boss_bar)


func _build_prompt_and_toasts() -> void:
	prompt_label = UIKit.label("", UIKit.FS_SMALL, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_place(prompt_label, 140, 220, 200, 14)
	add_child(prompt_label)

	toast_box = UIKit.vbox(2)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	_place(toast_box, 120, 168, 240, 46)
	add_child(toast_box)


# ---------------------------------------------------------------------------
# 每帧刷新
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_weapon_live()
	_update_skill_live()
	_update_boss_live()
	_update_prompt()
	_update_info()
	_update_toasts(_delta)


func _update_weapon_live() -> void:
	var p := _get_player()
	if p == null:
		return
	var w := p.get_active_weapon()
	for i in weapon_slots.size():
		var wp: Node2D = p.get_weapon_in_slot(i)
		var d = wp.get("data") if wp else null
		weapon_slots[i].texture = d.get_icon() if d is WeaponData else null
		var active := i == p.active_slot
		weapon_panels[i].add_theme_stylebox_override("panel",
			UIKit.slot_stylebox(d.rarity if d is WeaponData else -1, active))
	if w == null:
		weapon_name_label.text = "徒手（手刀）"
		ammo_label.text = ""
		reload_bar.set_ratio(0.0)
		return
	var wd: WeaponData = w.get("data")
	if wd == null:
		return
	weapon_name_label.text = wd.display_name
	var is_reloading: bool = bool(w.get("is_reloading"))
	if is_reloading:
		ammo_label.text = "装填中…"
		reload_bar.set_ratio(float(w.call("get_reload_ratio")))
	elif wd.magazine > 0:
		ammo_label.text = "%d / %d" % [int(w.get("ammo")), wd.magazine]
		reload_bar.set_ratio(float(w.call("get_cooldown_ratio")))
	else:
		ammo_label.text = "∞"
		reload_bar.set_ratio(float(w.call("get_cooldown_ratio")))


func _update_skill_live() -> void:
	var p := _get_player()
	if p == null:
		return
	if skill_icon.texture == null and p.character_data:
		skill_icon.texture = p.character_data.get_skill_icon()
	if p.skill:
		var r := p.skill.cooldown_ratio()
		# 冷却条从上往下退（未就绪时遮住图标）
		skill_cd_bar.set_ratio(1.0 - r)
		skill_cd_bar.visible = r < 1.0
	else:
		skill_cd_bar.visible = false
	crit_ready_label.text = "必暴就绪" if p.guaranteed_crit_active() else ""


func _update_boss_live() -> void:
	if _boss == null or not is_instance_valid(_boss):
		boss_panel.visible = false
		return
	var v: VitalsComponent = _boss.get("vitals")
	if v == null or v.is_dead():
		boss_panel.visible = false
		return
	boss_panel.visible = true
	boss_bar.set_ratio(v.ratio_hp())
	var d = _boss.get("data")
	if d is EnemyData:
		boss_name.text = "%s  %d / %d" % [d.display_name, int(v.hp), int(v.max_hp)]


func _update_prompt() -> void:
	var p := _get_player()
	if p == null:
		prompt_label.text = ""
		return
	var t := p.get_interact_target()
	if t and t.has_method("get_prompt_text"):
		prompt_label.text = "[E] " + String(t.call("get_prompt_text"))
	elif t and t.get("prompt") != null:
		prompt_label.text = "[E] " + String(t.get("prompt"))
	else:
		prompt_label.text = ""


func _update_info() -> void:
	if RunManager == null or not RunManager.run_active:
		info_label.text = ""
		return
	info_label.text = "楼层 %d · 击杀 %d · 种子 %d" % [
		RunManager.floor_index + 1, RunManager.enemies_killed, RunManager.run_seed % 100000
	]


func _update_toasts(delta: float) -> void:
	var i := _toasts.size() - 1
	while i >= 0:
		var e: Dictionary = _toasts[i]
		e["life"] = float(e["life"]) - delta
		var lbl: Label = e["label"]
		if is_instance_valid(lbl):
			var l := float(e["life"])
			lbl.modulate.a = clampf(l / 0.5, 0.0, 1.0)
		if float(e["life"]) <= 0.0:
			if is_instance_valid(lbl):
				lbl.queue_free()
			_toasts.remove_at(i)
		i -= 1


func _get_player() -> Player:
	if _player and is_instance_valid(_player):
		return _player
	var tree := get_tree()
	if tree == null:
		return null
	_player = tree.get_first_node_in_group("player") as Player
	return _player


# ---------------------------------------------------------------------------
# 信号回调
# ---------------------------------------------------------------------------

func _on_player_spawned(p: Node) -> void:
	_player = p as Player
	_refresh_all()


func _refresh_all() -> void:
	if GameState == null:
		return
	var cur_hp := GameState.get_max_hp()
	var cur_armor := GameState.get_max_armor()
	var cur_mp := GameState.get_max_mp()
	var p := _get_player()
	if p and p.vitals:
		cur_hp = p.vitals.hp
		cur_armor = p.vitals.armor
		cur_mp = p.vitals.mp
	_on_hp(cur_hp, GameState.get_max_hp())
	_on_armor(cur_armor, GameState.get_max_armor())
	_on_mp(cur_mp, GameState.get_max_mp())
	_on_level(GameState.player_level, GameState.player_xp,
		GameState.xp_needed_for_level(GameState.player_level))
	_on_gold(GameState.gold)


func _on_hp(cur: float, mx: float) -> void:
	hp_bar.set_ratio(cur / maxf(1.0, mx))
	hp_bar.text = "%d / %d" % [int(ceil(cur)), int(mx)]


func _on_armor(cur: float, mx: float) -> void:
	armor_bar.set_ratio(0.0 if mx <= 0.0 else cur / mx)
	armor_bar.visible = mx > 0.0


func _on_mp(cur: float, mx: float) -> void:
	mp_bar.set_ratio(0.0 if mx <= 0.0 else cur / mx)
	mp_bar.text = "%d / %d" % [int(ceil(cur)), int(mx)]


func _on_level(lv: int, xp: int, xp_next: int) -> void:
	var name_cn := "游侠"
	if GameState and GameState.character_data:
		name_cn = GameState.character_data.display_name
	level_label.text = "Lv.%d %s" % [lv, name_cn]
	xp_bar.set_ratio(0.0 if xp_next <= 0 else float(xp) / float(xp_next))


func _on_gold(amount: int) -> void:
	gold_label.text = "金币 %d" % amount


func _on_weapon_equipped(_data: WeaponData, _slot: int) -> void:
	_update_weapon_live()


func _on_toast(text: String, color: Color) -> void:
	if toast_box == null:
		return
	var l := UIKit.label(text, UIKit.FS_SMALL, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(240, 12)
	toast_box.add_child(l)
	_toasts.append({"label": l, "life": 2.4})
	# 超过 4 条就清掉最旧的
	while _toasts.size() > 4:
		var old: Dictionary = _toasts.pop_front()
		var ol = old["label"]
		if is_instance_valid(ol):
			ol.queue_free()


func _on_boss_spawned(b: Node) -> void:
	_boss = b
	boss_panel.visible = true
	_on_toast("BOSS 出现！", Color("#b44ac9"))
	EventBus.screen_shake_requested.emit(3.0, 0.5)


func _on_boss_defeated() -> void:
	boss_panel.visible = false
	_boss = null


func _on_room_entered(_room: RoomData, kind: int) -> void:
	match kind:
		GameEnums.RoomKind.TREASURE:
			_on_toast("发现宝箱房", Color("#ffd35c"))
		GameEnums.RoomKind.ELITE:
			_on_toast("精英怪出没", Color("#f2a13b"))
		_:
			pass


func _on_item_picked_up(stack: ItemStack, _pos: Vector2) -> void:
	if stack == null or stack.data == null:
		return
	var is_weapon := stack.data is WeaponData
	var is_rare := stack.get_rarity() >= GameEnums.Rarity.RARE
	if is_weapon or is_rare:
		_on_toast("获得 %s" % stack.data.display_name, GameEnums.rarity_color(stack.get_rarity()))
