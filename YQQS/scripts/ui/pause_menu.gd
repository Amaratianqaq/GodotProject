class_name PauseMenu
extends Control
## 暂停菜单（Esc）。
##
## 【框架约束】
## 暂停/恢复统一走 SceneRouter.set_paused()，关卡内的物理与 AI 会自动冻结
## （因为主场景未设置 PROCESS_MODE_ALWAYS）。

var _stats: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		SceneRouter.close_panel(&"pause")
		get_viewport().set_input_as_handled()


func _build() -> void:
	add_child(UIKit.dimmer(0.7))

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.wood_stylebox())
	box.custom_minimum_size = Vector2(240, 190)
	box.position = Vector2(240 - 120, 135 - 95)
	add_child(box)

	var v := UIKit.vbox(6)
	box.add_child(v)

	v.add_child(UIKit.label("暂停", UIKit.FS_TITLE, UIKit.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	_stats = UIKit.rich_label("", UIKit.FS_TINY)
	_stats.custom_minimum_size = Vector2(216, 56)
	v.add_child(_stats)
	_refresh_stats()

	var b_resume := UIKit.button("继续游戏", UIKit.FS_NORMAL)
	b_resume.pressed.connect(func() -> void: SceneRouter.close_panel(&"pause"))
	v.add_child(b_resume)

	var b_save := UIKit.button("保存游戏", UIKit.FS_NORMAL)
	b_save.pressed.connect(_save)
	v.add_child(b_save)

	var b_lobby := UIKit.button("返回大厅", UIKit.FS_NORMAL)
	b_lobby.pressed.connect(_return_lobby)
	v.add_child(b_lobby)

	if not GameState.is_in_run:
		b_lobby.disabled = false
		b_lobby.text = "返回大厅"

	var b_quit := UIKit.button("退出游戏", UIKit.FS_SMALL)
	b_quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(b_quit)


func _refresh_stats() -> void:
	var lines: PackedStringArray = PackedStringArray()
	if GameState.character_data:
		lines.append("角色：%s  Lv.%d" % [
			GameState.character_data.display_name, GameState.player_level
		])
	lines.append("金币：%d    技能点：%d" % [GameState.gold, SkillTreeService.points])
	lines.append("已解锁技能：%d 项" % _unlocked_count())
	if RunManager.run_active:
		lines.append("[color=#8fd3f2]%s[/color]" % RunManager.summary_text())
	else:
		lines.append("[color=#9a94a8]当前在大厅[/color]")
	_stats.text = "\n".join(lines)


func _unlocked_count() -> int:
	if SkillTreeService.tree == null:
		return 0
	var n := 0
	for node in SkillTreeService.tree.nodes:
		if SkillTreeService.get_level(node.id) > 0:
			n += 1
	return n


func _save() -> void:
	if SaveSystem.save_game():
		EventBus.toast.emit("已保存到槽位 %d" % SaveSystem.current_slot, UIKit.COL_OK)


func _return_lobby() -> void:
	if RunManager.run_active:
		RunManager.end_run(false)
	SceneRouter.close_all_panels()
	SceneRouter.go_to(GameEnums.SCENE_LOBBY)
