class_name PanelAltar
extends Interactable
## 通用「打开某个 UI 面板」的交互物（大厅里的仓库箱 / 技能树祭坛等）。
##
## 【框架约束】
## 大厅里所有「设施」都用本类 + panel_id 表达，
## 不要再为每个设施写一个脚本。

@export var panel_id: StringName = &"warehouse"
@export var icon_prop: Vector2i = Vector2i(2, 5)   ## props 图集里的图标
@export var accent: Color = Color("#a3713f")


func _on_interactable_ready() -> void:
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	if sprite.texture == null:
		sprite.texture = Atlas.prop(icon_prop)
	sprite.modulate = accent
	add_shadow()
	# 呼吸光效
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(sprite, "modulate", accent.lightened(0.35), 0.9)
	tw.tween_property(sprite, "modulate", accent, 0.9)


func add_shadow() -> void:
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = Atlas.prop(Atlas.PROP_SHADOW)
	sh.scale = Vector2(0.45, 0.22)
	sh.position = Vector2(0, 1)
	sh.z_index = -1
	add_child(sh)


func _on_activated(_player: Node2D) -> void:
	EventBus.ui_open_requested.emit(panel_id)
