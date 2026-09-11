class_name Portal
extends Interactable
## 传送门 / 出口（大厅 → 森林；BOSS 房 → 结算回大厅）。
##
## 【框架约束】
## 传送逻辑不写在本文件里：本类只发 `used` 信号，
## 由关卡（ForestLevel）或大厅（Lobby）决定「传到哪去」，
## 保证关卡流程集中在一个地方，方便后续加第二关。

enum Kind { ENTER_FOREST, EXIT_TO_LOBBY, NEXT_FLOOR, LOCKED }

@export var kind: int = Kind.ENTER_FOREST
## 未解锁时的提示
@export var locked_prompt: String = "封印中…"

var _label: Label = null


func _on_interactable_ready() -> void:
	prompt = _prompt_for_kind()
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	if sprite.texture == null:
		sprite.texture = Atlas.prop(Atlas.PROP_PORTAL)
	# 门的呼吸光
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(self, "modulate:a", 0.72, 0.8)
	tw.tween_property(self, "modulate:a", 1.0, 0.8)
	add_shadow()


func add_shadow() -> void:
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = Atlas.prop(Atlas.PROP_SHADOW)
	sh.scale = Vector2(0.5, 0.25)
	sh.position = Vector2(0, 1)
	sh.z_index = -1
	add_child(sh)


func _prompt_for_kind() -> String:
	match kind:
		Kind.ENTER_FOREST: return "进入森林"
		Kind.EXIT_TO_LOBBY: return "返回大厅"
		Kind.NEXT_FLOOR: return "前往下一层"
		Kind.LOCKED: return "封印中"
	return "传送"


func set_kind(k: int) -> void:
	kind = k
	set_prompt_text(_prompt_for_kind())


func can_interact(_player: Node2D) -> bool:
	return kind != Kind.LOCKED


func _on_activated(_player: Node2D) -> void:
	AudioManager.play_sfx_2d("res://assets/audio/sfx/portal.wav", global_position)
	# 使用时的一次性特效
	CombatFx.spawn_sprite_burst(
		self, global_position, Atlas.prop(Atlas.PROP_HIT_SPARK), 8, Color("#8fd3f2"), 40.0
	)
