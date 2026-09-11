class_name Interactable
extends Area2D
## 可交互物基类（宝箱 / 传送门 / NPC / 技能树祭坛）。
##
## 【框架约束 · 必读】
## 1. 所有可交互物必须继承本类并加入 group "interactable"，
##    Player 会自动找最近的一个并在按 E 时调用 interact()。
## 2. `can_interact()` 返回 false 时 Player 会跳过它（例如已开过的宝箱、
##    上锁的传送门）。
## 3. **配置注入顺序**：需要在 _ready() 里用到的字段，
##    必须在 add_child() 之前赋值（见 Enemy / Chest 的 configure 约定）。
## 4. 交互提示由基类统一画，子类不要自己再画一个。

signal activated(player: Node2D)

@export_group("交互")
## 提示文字（显示在物体上方，前面的按键图标由基类补）
@export var prompt: String = "交互"
## 是否显示提示
@export var show_prompt: bool = true
## 交互后是否禁用自身
@export var disable_after_use: bool = false

@export_group("表现")
## 高亮时的染色
@export var highlight_color: Color = Color("#ffd35c")
## 提示文字高度偏移
@export var prompt_offset_y: float = -18.0

var _highlighted: bool = false
var _used: bool = false
var _prompt_label: Label = null
var sprite: Sprite2D = null


func _ready() -> void:
	collision_layer = Layers.INTERACTABLE_LAYER
	collision_mask = Layers.INTERACTABLE_MASK
	monitoring = false
	monitorable = true
	NodeUtils.ensure_group(self, &"interactable")
	sprite = get_node_or_null("Sprite") as Sprite2D
	_build_prompt()
	_on_interactable_ready()


## 子类钩子
func _on_interactable_ready() -> void:
	pass


func _build_prompt() -> void:
	if not show_prompt:
		return
	_prompt_label = Label.new()
	_prompt_label.name = "Prompt"
	_prompt_label.text = "[E] " + prompt
	_prompt_label.add_theme_font_size_override("font_size", 7)
	_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.12))
	_prompt_label.add_theme_constant_override("outline_size", 3)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.size = Vector2(80, 12)
	_prompt_label.position = Vector2(-40, prompt_offset_y)
	_prompt_label.z_index = 30
	_prompt_label.z_as_relative = false
	_prompt_label.visible = false
	add_child(_prompt_label)


# ---------------------------------------------------------------------------
# 交互接口（Player 调用）
# ---------------------------------------------------------------------------

func can_interact(_player: Node2D) -> bool:
	return not _used


func interact(player: Node2D) -> void:
	if not can_interact(player):
		return
	if disable_after_use:
		_used = true
		set_highlight(false)
	activated.emit(player)
	_on_activated(player)


## 子类实现
func _on_activated(_player: Node2D) -> void:
	pass


func set_prompt_text(t: String) -> void:
	prompt = t
	if _prompt_label:
		_prompt_label.text = "[E] " + t


func get_prompt_text() -> String:
	return prompt


func is_used() -> bool:
	return _used


# ---------------------------------------------------------------------------
# 高亮
# ---------------------------------------------------------------------------

func set_highlight(v: bool) -> void:
	if _highlighted == v:
		return
	_highlighted = v
	if _prompt_label:
		_prompt_label.visible = v and show_prompt and can_interact(null)
	if sprite:
		if v:
			var tw := sprite.create_tween()
			tw.tween_property(sprite, "modulate", highlight_color, 0.10)
		else:
			var tw2 := sprite.create_tween()
			tw2.tween_property(sprite, "modulate", Color.WHITE, 0.10)


func is_highlighted() -> bool:
	return _highlighted
