class_name Chest
extends Interactable
## 随机掉落宝箱（普通 / 优秀 / 稀有）。
##
## 【框架约束 · 必读】
## 1. 宝箱等级由 `tier`（GameEnums.ChestTier）决定，**必须在 add_child 之前**
##    通过 configure() 注入；掉落内容全部来自 LootService 的掉落表
##    （chest_normal / chest_fine / chest_rare），本文件不写任何掉率。
## 2. 开箱产出的东西以「掉落物」形式散落到地面，由玩家自己拾取，
##    这样才有开箱手感；金币除外（直接入账并飘字）。
## 3. 分类规则（第一阶段）：小怪掉普通箱 / 精英掉优秀箱 / BOSS 掉稀有箱，
##    由 EnemyData.get_chest_tier() 决定，见 LootService.handle_enemy_death()。

## 宝箱等级（GameEnums.ChestTier）
@export var tier: int = GameEnums.ChestTier.NORMAL
## 开箱后散落物的弹出距离
@export var scatter_radius: float = 16.0
## 开箱特效强度
@export var burst_count: int = 10

var _opened: bool = false
var _open_sprite: AtlasTexture = null
var _closed_sprite: AtlasTexture = null
var _lid_tween: Tween = null


## 在 add_child 之前调用
func configure(p_tier: int, _extra: Dictionary = {}) -> void:
	tier = p_tier


func _on_interactable_ready() -> void:
	prompt = _tier_prompt()
	_closed_sprite = Atlas.frame("props", Atlas.CHEST_CLOSED[tier].x, Atlas.CHEST_CLOSED[tier].y)
	_open_sprite = Atlas.frame("props", Atlas.CHEST_OPEN[tier].x, Atlas.CHEST_OPEN[tier].y)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.texture = _closed_sprite
	sprite.z_index = 1
	_add_glow()
	# 宝箱是「有实体」的，防止玩家站在箱子上
	_build_body()


func _tier_prompt() -> String:
	match tier:
		GameEnums.ChestTier.FINE: return "优秀宝箱"
		GameEnums.ChestTier.RARE: return "稀有宝箱"
	return "普通宝箱"


func _add_glow() -> void:
	if tier == GameEnums.ChestTier.NORMAL:
		return
	var frame := Atlas.rarity_frame(
		GameEnums.Rarity.UNCOMMON if tier == GameEnums.ChestTier.FINE else GameEnums.Rarity.RARE
	)
	if frame == null:
		return
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = frame
	glow.modulate = GameEnums.rarity_color(
		GameEnums.Rarity.UNCOMMON if tier == GameEnums.ChestTier.FINE else GameEnums.Rarity.RARE
	)
	glow.modulate.a = 0.5
	glow.scale = Vector2(1.15, 1.15)
	glow.z_index = 0
	add_child(glow)
	var tw := glow.create_tween()
	tw.set_loops()
	tw.tween_property(glow, "modulate:a", 0.85, 0.6)
	tw.tween_property(glow, "modulate:a", 0.35, 0.6)


## 宝箱挡住走廊会很难受，所以只做「软阻挡」：不加物理体，仅在地面画阴影
func _build_body() -> void:
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = Atlas.prop(Atlas.PROP_SHADOW)
	sh.scale = Vector2(0.7, 0.35)
	sh.position = Vector2(0, 2)
	sh.z_index = -1
	add_child(sh)


# ---------------------------------------------------------------------------
# 开箱
# ---------------------------------------------------------------------------

func can_interact(_player: Node2D) -> bool:
	return not _opened


func _on_activated(player: Node2D) -> void:
	if _opened:
		return
	_opened = true
	set_prompt_text("已开启")
	if _prompt_label:
		_prompt_label.visible = false

	# 开盖动画
	if sprite and _open_sprite:
		sprite.texture = _open_sprite
	_shake_open()

	AudioManager.play_sfx_2d("res://assets/audio/sfx/chest_open.wav", global_position)
	EventBus.screen_shake_requested.emit(1.2, 0.15)

	# 掷掉落（全部逻辑在 LootService 里）
	var rewards := LootService.open_chest(self)
	_scatter_rewards(rewards)
	_spawn_burst()

	# 稀有箱额外给点金币
	if tier == GameEnums.ChestTier.RARE:
		var g := LootService.rng.randi_range(60, 120)
		GameState.add_gold(g)
		CombatFx.popup(self, global_position + Vector2(0, -20), "+%d 金币" % g, Color("#ffd35c"))

	disable_after_use = true


func _shake_open() -> void:
	if sprite == null:
		return
	if _lid_tween and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.tween_property(sprite, "scale", Vector2(1.22, 1.22), 0.08)
	_lid_tween.tween_property(sprite, "scale", Vector2.ONE, 0.16)


func _spawn_burst() -> void:
	var color := Color("#ffd35c")
	if tier == GameEnums.ChestTier.FINE:
		color = Color("#8fc75a")
	elif tier == GameEnums.ChestTier.RARE:
		color = Color("#4a8fd9")
	CombatFx.spawn_sprite_burst(
		self, global_position + Vector2(0, -4),
		Atlas.prop(Atlas.PROP_HIT_SPARK), burst_count, color, 46.0
	)


## 把奖励散落到地面（生成 ItemPickup 节点）
func _scatter_rewards(rewards: Array) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in rewards.size():
		var item: ItemStack = rewards[i]
		if item == null or item.is_empty():
			continue
		var ang := TAU * (float(i) / maxf(1.0, float(rewards.size()))) + randf() * 0.5
		var offset := Vector2(cos(ang), sin(ang)) * scatter_radius
		var node := LootService.spawn_item_pickup(
			item, global_position + Vector2(0, -2) + offset, parent
		)
		if node and node is Node2D:
			# 首个奖励必定弹出得更远一点，视觉上更明显
			(node as Node2D).set("pop_speed", 40.0 + float(i) * 4.0)
		EventBus.loot_dropped.emit(item, global_position + offset)


func get_tier() -> int:
	return tier
