extends Control
## 启动 / 标题界面。
##
## 【框架约束 · 必读】
## 1. 主场景固定是 Boot.tscn（见 project.godot）。
##    它的唯一职责是：初始化存档 → 让玩家选择「继续 / 新档」→ 进入大厅。
## 2. 不要在 Boot 里放任何游戏逻辑。
## 3. 首次启动没有任何存档时，直接开新档并进大厅。

var _menu: VBoxContainer
var _slots_box: VBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	SceneRouter.set_fade_black()
	await get_tree().process_frame
	SceneRouter.fade_in(0.6)


func _build() -> void:
	var bg := UIKit.color_rect(Color("#0d0b1f"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题
	var title := UIKit.label("SOUL FOREST", 46, Color("#8fc75a"), HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 24)
	title.size = Vector2(480, 52)
	add_child(title)

	var sub := UIKit.label("元气骑士前传 · 类 2.5D 像素动作 RPG · 第一阶段：宁静森林",
		UIKit.FS_SMALL, UIKit.COL_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 74)
	sub.size = Vector2(480, 14)
	add_child(sub)

	_status = UIKit.label("", UIKit.FS_TINY, UIKit.COL_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_status.position = Vector2(0, 238)
	_status.size = Vector2(480, 12)
	add_child(_status)

	_menu = UIKit.vbox(6)
	_menu.position = Vector2(240 - 70, 110)
	_menu.size = Vector2(140, 130)
	add_child(_menu)

	var b_continue := UIKit.button("继续游戏", UIKit.FS_NORMAL)
	b_continue.pressed.connect(_on_continue)
	b_continue.disabled = not SaveSystem.has_any_save()
	_menu.add_child(b_continue)

	var b_new := UIKit.button("新游戏", UIKit.FS_NORMAL)
	b_new.pressed.connect(_on_new_game)
	_menu.add_child(b_new)

	var b_quit := UIKit.button("退出", UIKit.FS_SMALL)
	b_quit.pressed.connect(func() -> void: get_tree().quit())
	_menu.add_child(b_quit)

	_slots_box = UIKit.vbox(2)
	_slots_box.position = Vector2(240 - 110, 176)
	_slots_box.size = Vector2(220, 60)
	add_child(_slots_box)
	_refresh_slots()


func _refresh_slots() -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	var any := false
	for meta in SaveSystem.list_slots():
		if not bool(meta.get("exists", false)):
			continue
		any = true
		var s: Dictionary = meta.get("summary", {})
		var txt := "存档 %d · %s Lv.%d · 金币 %d · 最高层 %d" % [
			int(meta["slot"]) + 1, String(s.get("character", "?")),
			int(s.get("level", 1)), int(s.get("gold", 0)), int(s.get("best_floor", 0)) + 1
		]
		_slots_box.add_child(UIKit.label(txt, UIKit.FS_TINY, UIKit.COL_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	if any:
		_status.text = "点击「继续游戏」读取 1 号存档；或开始新游戏"
	else:
		_status.text = "未找到存档，将开始新游戏"
	# 有存档时把继续按钮的禁用状态更新
	if _menu.get_child_count() > 0:
		var b := _menu.get_child(0) as Button
		if b:
			b.disabled = not SaveSystem.has_any_save()


func _on_continue() -> void:
	SaveSystem.load_or_new(0)
	_enter_lobby()


func _on_new_game() -> void:
	SaveSystem.new_game(0)
	SaveSystem.save_game(0)
	_enter_lobby()


func _enter_lobby() -> void:
	SceneRouter.go_to(GameEnums.SCENE_LOBBY, 0.35)
