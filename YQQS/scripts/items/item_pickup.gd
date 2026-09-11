class_name ItemPickup
extends PickupBase
## 物品掉落物（武器 / 消耗品 / 材料通用）。
##
## 【框架约束】
## 武器掉落与普通物品掉落共用本类：按 stack.data 的类型决定外观与拾取行为。
## 武器进「武器槽」需要玩家在背包里操作，所以武器拾取只进背包。

## 要拾取的堆叠（add_child 之前必须注入）
var stack: ItemStack = null

var _label: Label = null


func _on_pickup_ready() -> void:
	if stack == null or stack.data == null:
		push_warning("[ItemPickup] 未注入 ItemStack，自动销毁")
		queue_free()
		return
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.texture = stack.get_icon()
	var is_weapon := stack.data is WeaponData
	sprite.scale = Vector2(0.9, 0.9) if is_weapon else Vector2.ONE
	add_shadow(0.3 if is_weapon else 0.22)
	# 品质描边光晕：用一层放大的半透明贴图近似
	_add_rarity_glow()
	# 数量标签
	if stack.count > 1:
		_label = Label.new()
		_label.text = "x%d" % stack.count
		_label.add_theme_font_size_override("font_size", 7)
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.12))
		_label.add_theme_constant_override("outline_size", 2)
		_label.position = Vector2(1, 0)
		add_child(_label)
	# 品质特效：传奇品质带粉色/橙色火花
	if stack.get_rarity() >= GameEnums.Rarity.RARE:
		CombatFx.spawn_sprite_burst(
			self, global_position, Atlas.prop(Atlas.PROP_HIT_SPARK),
			4, GameEnums.rarity_color(stack.get_rarity()), 22.0
		)


func _add_rarity_glow() -> void:
	if stack == null or stack.data == null:
		return
	var r := stack.get_rarity()
	if r < GameEnums.Rarity.UNCOMMON:
		return
	var frame := Atlas.rarity_frame(r)
	if frame == null:
		return
	var glow := Sprite2D.new()
	glow.name = "RarityGlow"
	glow.texture = frame
	glow.modulate = GameEnums.rarity_color(r)
	glow.modulate.a = 0.45
	glow.scale = Vector2(1.1, 1.1)
	glow.z_index = -1
	add_child(glow)
	# 呼吸
	var tw := glow.create_tween()
	tw.set_loops()
	tw.tween_property(glow, "modulate:a", 0.8, 0.7)
	tw.tween_property(glow, "modulate:a", 0.35, 0.7)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_bob(delta, -1.0)


func _collect(player: Node2D) -> bool:
	if stack == null or stack.is_empty():
		return true
	var inv := GameState.inventory
	var leftover := inv.add_item(stack)
	var taken := stack.count - leftover
	if taken <= 0:
		EventBus.toast.emit("背包已满", Color("#d94a4a"))
		# 背包满时不销毁，留在地上
		return false
	AudioManager.play_sfx("res://assets/audio/sfx/pickup.wav", 0.12)
	var col := GameEnums.rarity_color(stack.get_rarity())
	spawn_pickup_text("%s ×%d" % [stack.data.display_name, taken], col)
	EventBus.item_picked_up.emit(stack, global_position)
	GameState.log_loot(stack)
	queue_free()
	return true
