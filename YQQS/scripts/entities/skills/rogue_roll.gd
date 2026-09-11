class_name RogueRoll
extends CharacterSkill
## 游侠技能 · 翻滚（参考《元气骑士》游侠 Rogue）
##
## ================= 原型机制 =================
## · 向前翻滚一段距离，翻滚期间 **无敌**；
## · 翻滚结束后约 0.6 秒内，下一次攻击必定暴击；
## · 冷却短、无耗蓝，是游侠「贴身 — 翻滚 — 暴击」循环的核心。
##
## ================= 本项目实现 =================
## · 位移用速度冲量实现（保持与地形碰撞），并叠加 2.5D 的 z_height 抛物线，
##   视觉上像一个真正的翻滚；
## · 翻滚帧使用 player_ranger 图集的第 4 帧（翻滚姿态）；
## · 技能树联动：
##     - 标签 `double_roll`  → 充能数 +1（可以连续滚两次）
##     - 属性 ROLL_DISTANCE  → 翻滚距离
##     - 属性 ROLL_COOLDOWN  → 冷却
## ============================================

## 翻滚基础时长（秒）
const ROLL_TIME := 0.30
## 翻滚基础距离（像素）
const ROLL_DISTANCE := 68.0
## 翻滚最高抬升（2.5D 视觉高度）
const ROLL_PEAK_HEIGHT := 7.0
## 翻滚结束后的必暴窗口（秒）
const GUARANTEED_CRIT_WINDOW := 0.65
## 翻滚过程中的速度线数量
const DASH_AFTERIMAGE_COUNT := 4

var _rolling := false
var _roll_dir: Vector2 = Vector2.RIGHT
var _roll_elapsed := 0.0
var _roll_total := 0.0
var _afterimage_accum := 0.0


func _ready() -> void:
	skill_id = &"roll"
	base_cooldown = 1.20
	mp_cost = 0.0


## 翻滚推进放在 _physics_process 里，而不是用 `await physics_frame` 的 while 循环。
## 【为什么】headless / 高帧率环境下 process delta 与 physics delta 不一致，
## 用 process delta 累加但等 physics_frame 会让时长严重失真。
func _physics_process(delta: float) -> void:
	if not _rolling:
		return
	_advance_roll(delta)


func _advance_roll(delta: float) -> void:
	_roll_elapsed += delta
	var p := clampf(_roll_elapsed / maxf(0.01, _roll_total), 0.0, 1.0)
	# 速度：先快后慢（缓出）
	var speed := (roll_distance() / maxf(0.05, _roll_total)) * (1.0 - p * 0.55)
	if character and is_instance_valid(character):
		character.set("desired_velocity", _roll_dir * speed)
		# 2.5D：抛物线抬升
		if character.has_method("set_z_height"):
			character.call("set_z_height", sin(p * PI) * ROLL_PEAK_HEIGHT)
	# 残影
	_afterimage_accum += delta
	var step := maxf(0.03, _roll_total / float(DASH_AFTERIMAGE_COUNT))
	if _afterimage_accum >= step:
		_afterimage_accum = 0.0
		_spawn_afterimage()
	if _roll_elapsed >= _roll_total:
		_end_roll()


func _end_roll() -> void:
	_rolling = false
	if character and is_instance_valid(character):
		if character.has_method("set_z_height"):
			character.call("set_z_height", 0.0)
		if character.has_method("play_roll_end"):
			character.call("play_roll_end")
		if character.has_method("grant_guaranteed_crit"):
			character.call("grant_guaranteed_crit", GUARANTEED_CRIT_WINDOW)
	var vitals: VitalsComponent = character.get("vitals") if character else null
	if vitals:
		vitals.invincible = false
	EventBus.toast.emit("翻滚！下次攻击必定暴击", Color("#f28fc9"))
	finish()


# ---------------------------------------------------------------------------
# 冷却与充能
# ---------------------------------------------------------------------------

func cooldown_scale() -> float:
	## 技能树的「翻滚冷却」属性是一个乘区（基础值 1.2 由 CharacterData 提供，
	## 这里直接读最终值，避免双重计算）
	if GameState and GameState.stats:
		var cd := GameState.get_stat(GameEnums.StatKind.ROLL_COOLDOWN)
		if cd > 0.0:
			# 与角色基础冷却的比例作为缩放系数
			var base_role := 1.2
			if GameState.character_data:
				base_role = maxf(0.05, GameState.character_data.skill_cooldown)
			return clampf(cd / base_role, 0.25, 2.0)
	return 1.0


func max_charges() -> int:
	var n := 1
	if SkillTreeService and SkillTreeService.has_tag("double_roll"):
		n += 1
	return n


func roll_distance() -> float:
	if GameState and GameState.stats:
		return maxf(24.0, GameState.get_stat(GameEnums.StatKind.ROLL_DISTANCE))
	return ROLL_DISTANCE


# ---------------------------------------------------------------------------
# 施放
# ---------------------------------------------------------------------------

func _perform() -> void:
	if character == null:
		finish()
		return
	_roll_dir = _pick_direction()
	_rolling = true
	_roll_elapsed = 0.0
	_roll_total = ROLL_TIME * _roll_scale()
	_afterimage_accum = 0.0

	# 无敌 + 锁朝向
	var vitals: VitalsComponent = character.get("vitals")
	if vitals:
		vitals.invincible = true
	character.set("facing", _roll_dir)
	if character.has_method("play_roll_animation"):
		character.call("play_roll_animation", _roll_dir)

	AudioManager.play_sfx_2d("res://assets/audio/sfx/roll.wav", character.global_position)
	_spawn_dust()
	# 后续推进交给 _physics_process，_end_roll() 里统一收尾


## 翻滚方向：优先当前移动输入，其次朝向
func _pick_direction() -> Vector2:
	var input := Vector2.ZERO
	if character and character.has_method("get_move_input"):
		input = character.call("get_move_input")
	if input.length_squared() > 0.01:
		return input.normalized()
	var f = character.get("facing")
	if f is Vector2 and (f as Vector2).length_squared() > 0.01:
		return (f as Vector2).normalized()
	return Vector2.DOWN


func _roll_scale() -> float:
	# 距离越长，时长略增，保证视觉速度一致
	return clampf(roll_distance() / ROLL_DISTANCE, 0.7, 1.5)


func _spawn_dust() -> void:
	CombatFx.spawn_sprite_burst(
		character, character.global_position, Atlas.prop(Atlas.PROP_HIT_SPARK),
		5, Color("#d9a866"), 26.0
	)


func _spawn_afterimage() -> void:
	if character == null:
		return
	var spr = character.get("sprite")
	if not (spr is Sprite2D):
		return
	var src: Sprite2D = spr
	if src.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = src.texture
	ghost.flip_h = src.flip_h
	ghost.global_position = src.global_position
	ghost.scale = src.scale
	ghost.modulate = Color(0.85, 0.95, 1.0, 0.45)
	ghost.z_index = 1
	var parent := CombatFx.fx_parent(character)
	if parent == null:
		return
	parent.add_child(ghost)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_property(ghost, "scale", ghost.scale * 0.85, 0.22)
	tw.chain().tween_callback(ghost.queue_free)
