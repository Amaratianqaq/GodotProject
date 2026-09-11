class_name Player
extends Actor
## 玩家角色控制器（第一阶段：游侠）。
##
## 【框架约束 · 必读】
## 1. 玩家所有数值都来自 GameState（CharacterData + 技能树），
##    本脚本 **不得** 出现任何硬编码的战斗数值。
## 2. 输入只在这里读取；其它系统（武器 / 技能）通过本脚本暴露的
##    get_move_input() / aim_direction 等接口取输入意图，不要各自读 Input。
## 3. 武器实例由 WeaponRegistry 创建并挂在 WeaponPivot 下，
##    换武器必须走 equip_weapon()，不要手动 add_child。
## 4. 玩家死亡只发信号（EventBus.player_died），由 RunManager 决定后续流程。

@export_group("玩家参数")
## 武器挂点路径
@export var weapon_pivot_path: NodePath
## 交互检测半径
@export var interact_radius: float = 26.0
## 瞄准死区（鼠标离角色小于该距离时不改变朝向）
@export var aim_deadzone: float = 6.0

# --- 运行时 ---
var character_data: CharacterData = null
## 当前装备（两个槽位）
var weapons: Array[Node2D] = [null, null]
var active_slot: int = 0
## 主动技能实例
var skill: CharacterSkill = null
## 翻滚等状态
var is_rolling: bool = false
var is_attacking: bool = false
var _guaranteed_crit_left: float = 0.0
var _crit_bonus: float = 0.0
var _interact_target: Node = null
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _weapon_pivot: Node2D = null
var _use_cooldown: float = 0.0
var _last_aim: Vector2 = Vector2.RIGHT


func _on_actor_ready() -> void:
	faction = GameEnums.Faction.PLAYER
	if not is_in_group("players"):
		add_to_group("players")
	if not is_in_group("player"):
		add_to_group("player")
	_weapon_pivot = get_node_or_null(weapon_pivot_path) as Node2D
	if _weapon_pivot == null:
		_weapon_pivot = find_child("WeaponPivot", true, false) as Node2D
	_setup_from_game_state()
	_setup_skill()
	fit_shadow_to_radius(6.0)
	GameState.player = self
	EventBus.player_spawned.emit(self)


# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _setup_from_game_state() -> void:
	character_data = GameState.character_data
	if character_data == null:
		push_error("[Player] GameState 没有角色数据")
		return
	display_name = character_data.display_name
	move_speed = GameState.get_move_speed()
	if vitals:
		vitals.setup_from_stats(GameState.stats, true, true)
		vitals.died.connect(_on_died)
		vitals.damaged.connect(_on_damaged)
	# 装备：读 GameState 里记录的武器（跨场景保留）。
	# 【注意】初始物资（start_items / start_gold）只在 GameState.reset_new_game() 发放，
	# 这里绝不能重复发，否则每次回大厅都会白送一份。
	var restored := false
	for i in weapons.size():
		var wid := GameState.get_equipped_weapon(i)
		if wid == &"":
			continue
		var w := ConfigDB.get_weapon(wid)
		if w:
			equip_weapon(w, i)
			restored = true
	if not restored:
		var start_weapon := ConfigDB.get_weapon(character_data.start_weapon_id)
		if start_weapon:
			equip_weapon(start_weapon, 0)


func _setup_skill() -> void:
	var path := character_data.skill_script if character_data else ""
	if path == "" or not ResourceLoader.exists(path):
		return
	var scr: Script = load(path)
	if scr == null:
		return
	var n := Node.new()
	n.set_script(scr)
	add_child(n)
	skill = n as CharacterSkill
	if skill:
		skill.setup(self)


func on_stats_rebuilt() -> void:
	## 技能树变化 → 重算上限（保留当前值比例）
	move_speed = GameState.get_move_speed()
	if vitals == null:
		return
	var hp_ratio := vitals.ratio_hp()
	var mp_ratio := vitals.ratio_mp()
	vitals.setup_from_stats(GameState.stats, true, false)
	vitals.set_hp_value(vitals.max_hp * hp_ratio)
	vitals.set_mp_value(vitals.max_mp * mp_ratio)


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func get_move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func aim_direction() -> Vector2:
	var m := get_global_mouse_position() - global_position
	if m.length() < aim_deadzone:
		return _last_aim
	_last_aim = m.normalized()
	return _last_aim


func _physics_process(delta: float) -> void:
	if _use_cooldown > 0.0:
		_use_cooldown = maxf(0.0, _use_cooldown - delta)
	if _guaranteed_crit_left > 0.0:
		_guaranteed_crit_left = maxf(0.0, _guaranteed_crit_left - delta)
	if is_dead:
		super._physics_process(delta)
		return
	_handle_movement(delta)
	_handle_aim()
	_handle_actions(delta)
	_update_weapons(delta)
	_update_animation(delta)
	_find_interactable()
	super._physics_process(delta)


func _handle_movement(delta: float) -> void:
	var input := get_move_input()
	if GameState.is_in_run and SceneRouter.any_panel_open():
		input = Vector2.ZERO
	if is_rolling:
		# 翻滚期间由技能接管位移，这里不再覆盖
		return
	desired_velocity = input * move_speed
	if input.length_squared() > 0.01:
		set_facing(input)


func _handle_aim() -> void:
	var dir := aim_direction()
	if dir.x != 0.0 and not is_rolling:
		if sprite:
			sprite.flip_h = dir.x < 0.0


func _handle_actions(delta: float) -> void:
	if SceneRouter.any_panel_open():
		return
	# 开火（按住连发）
	if Input.is_action_pressed("fire"):
		_try_attack()
	# 翻滚
	if Input.is_action_just_pressed("roll"):
		if skill:
			skill.try_use()
	# 交互
	if Input.is_action_just_pressed("interact"):
		_do_interact()
	# 换武器
	if InputMap.has_action("slot_1") and Input.is_action_just_pressed("slot_1"):
		switch_slot(0)
	if InputMap.has_action("slot_2") and Input.is_action_just_pressed("slot_2"):
		switch_slot(1)
	if InputMap.has_action("reload") and Input.is_action_just_pressed("reload"):
		reload_active_weapon()
	# 喝药
	if Input.is_action_just_pressed("use_potion"):
		use_best_potion()
	# UI
	if Input.is_action_just_pressed("inventory"):
		EventBus.ui_open_requested.emit(&"inventory")
	if Input.is_action_just_pressed("warehouse"):
		if not GameState.is_in_run:
			EventBus.ui_open_requested.emit(&"warehouse")
		else:
			EventBus.toast.emit("关卡内无法打开仓库", Color("#d94a4a"))
	if Input.is_action_just_pressed("skill_tree"):
		EventBus.ui_open_requested.emit(&"skill_tree")
	if Input.is_action_just_pressed("pause"):
		EventBus.ui_open_requested.emit(&"pause")


# ---------------------------------------------------------------------------
# 攻击
# ---------------------------------------------------------------------------

func _try_attack() -> void:
	var w := get_active_weapon()
	if w:
		w.call("update_aim", aim_direction())
		w.call("try_fire")
		return
	# 徒手：手刀（参考《元气骑士》近战）
	_unarmed_attack()


func _unarmed_attack() -> void:
	if _use_cooldown > 0.0:
		return
	var interval := character_data.melee_interval if character_data else 0.35
	_use_cooldown = interval
	var hb := find_child("MeleeHitbox", true, false) as HitboxComponent
	if hb == null:
		return
	var crit := consume_guaranteed_crit()
	var dmg := GameState.get_stat(GameEnums.StatKind.MELEE_DAMAGE) * GameState.get_damage_mult()
	if crit:
		dmg *= GameState.get_crit_mult()
	hb.set_faction(GameEnums.Faction.PLAYER)
	hb.knockback_force = 55.0
	hb.rotation = aim_direction().angle()
	var shape_node := hb.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node:
		var rect := RectangleShape2D.new()
		var reach := character_data.melee_range if character_data else 20.0
		rect.size = Vector2(reach, reach * 1.25)
		shape_node.shape = rect
		shape_node.position = Vector2(reach * 0.5, 0)
	hb.activate(0.12, dmg, crit)
	CombatFx.hit_spark(self, global_position + aim_direction() * 10.0, aim_direction(), 0.7)
	if crit:
		CombatFx.popup(self, global_position + Vector2(0, -18), "手刀暴击!", Color("#ffd35c"))


func _update_weapons(delta: float) -> void:
	var w := get_active_weapon()
	if w == null:
		return
	var dir := aim_direction()
	# 枪口跟随鼠标方向（手里有武器的视觉表现）
	if _weapon_pivot:
		_weapon_pivot.position = Vector2.ZERO
	w.global_position = global_position + Vector2(0, -9)
	w.call("update_aim", dir)
	# 朝上时武器画在角色身后
	w.z_index = 1 if dir.y > -0.25 else -1


# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------

func _update_animation(delta: float) -> void:
	if sprite == null or is_dead:
		return
	if is_rolling:
		return
	var moving := desired_velocity.length_squared() > 4.0
	_anim_timer += delta
	var step := 0
	if moving:
		var speed_factor := 0.14
		if _anim_timer >= speed_factor:
			_anim_timer = 0.0
			_anim_frame = (_anim_frame + 1) % 4
		step = [0, 1, 0, 2][_anim_frame]
	var dir := get_move_input()
	if dir.length_squared() < 0.01:
		dir = aim_direction()
	var tex := Atlas.player_frame(dir, step)
	if tex:
		sprite.texture = tex
		# 朝左时水平翻转（图集只有朝右的侧面帧）
		if absf(dir.x) > absf(dir.y):
			sprite.flip_h = dir.x < 0.0


func play_roll_animation(dir: Vector2) -> void:
	is_rolling = true
	if sprite:
		var tex := Atlas.frame("player_ranger", Atlas.P_ROLL_SIDE.x, Atlas.P_ROLL_SIDE.y)
		if absf(dir.y) > absf(dir.x):
			tex = Atlas.frame("player_ranger", Atlas.P_ROLL_DOWN.x, Atlas.P_ROLL_DOWN.y)
		else:
			tex = Atlas.frame("player_ranger", Atlas.P_ROLL_SIDE.x, Atlas.P_ROLL_SIDE.y)
		if tex:
			sprite.texture = tex
		sprite.flip_h = dir.x < 0.0


func play_roll_end() -> void:
	is_rolling = false
	set_z_height(0.0)


# ---------------------------------------------------------------------------
# 必暴标记（游侠翻滚联动）
# ---------------------------------------------------------------------------

func grant_guaranteed_crit(duration: float) -> void:
	_guaranteed_crit_left = maxf(_guaranteed_crit_left, duration)


func consume_guaranteed_crit() -> bool:
	if _guaranteed_crit_left > 0.0:
		_guaranteed_crit_left = 0.0
		return true
	return false


func get_crit_bonus() -> float:
	return _crit_bonus


func add_crit_bonus(v: float) -> void:
	_crit_bonus += v


# ---------------------------------------------------------------------------
# 武器
# ---------------------------------------------------------------------------

func get_active_weapon() -> Node2D:
	if active_slot < 0 or active_slot >= weapons.size():
		return null
	return weapons[active_slot]


func get_weapon_in_slot(i: int) -> Node2D:
	if i < 0 or i >= weapons.size():
		return null
	return weapons[i]


## 装备武器到指定槽位（0 / 1）。返回被替换下来的 WeaponData（可为 null）。
func equip_weapon(data: WeaponData, slot: int = -1) -> WeaponData:
	if data == null:
		return null
	var s := slot
	if s < 0:
		s = 0 if weapons[0] == null else 1
	s = clampi(s, 0, weapons.size() - 1)
	var old_data: WeaponData = null
	if weapons[s] != null and is_instance_valid(weapons[s]):
		old_data = weapons[s].get("data")
		weapons[s].queue_free()
	var parent := _weapon_pivot if _weapon_pivot else self
	var w := WeaponRegistry.create_and_setup(data, self, parent)
	weapons[s] = w
	if w:
		if w.has_signal("fired"):
			w.fired.connect(_on_weapon_fired)
	active_slot = s
	# 记录到 GameState，保证换场景 / 回大厅后武器不丢
	GameState.set_equipped_weapon(s, data.id)
	EventBus.weapon_equipped.emit(data, s)
	return old_data


func switch_slot(i: int) -> void:
	if i == active_slot:
		return
	if get_weapon_in_slot(i) == null:
		return
	if get_active_weapon() and is_instance_valid(get_active_weapon()):
		get_active_weapon().visible = false
	active_slot = i
	if get_active_weapon():
		get_active_weapon().visible = true
	var d = get_active_weapon().get("data")
	if d is WeaponData:
		EventBus.weapon_equipped.emit(d, i)


func reload_active_weapon() -> void:
	var w := get_active_weapon()
	if w:
		w.call("start_reload")


func _on_weapon_fired(_w: Node, _d: WeaponData) -> void:
	# 开火时轻微后坐位移，增强手感
	set_z_height(maxf(z_height, 0.8))


func drop_active_weapon() -> void:
	## 丢弃当前武器到地上（F 键）
	var w := get_active_weapon()
	if w == null:
		return
	var d: WeaponData = w.get("data")
	if d == null:
		return
	LootService.spawn_weapon_pickup(
		ItemStack.new(d, 1), global_position + aim_direction() * 12.0,
		CombatFx.fx_parent(self)
	)
	_clear_slot(active_slot)


func _clear_slot(slot: int) -> void:
	if slot < 0 or slot >= weapons.size():
		return
	if weapons[slot] and is_instance_valid(weapons[slot]):
		weapons[slot].queue_free()
	weapons[slot] = null
	GameState.set_equipped_weapon(slot, &"")


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _find_interactable() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var best: Node = null
	var best_d := interact_radius * interact_radius
	for n in tree.get_nodes_in_group("interactable"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if n.has_method("can_interact") and not bool(n.call("can_interact", self)):
			continue
		var d := (n as Node2D).global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != _interact_target:
		if _interact_target and is_instance_valid(_interact_target) and _interact_target.has_method("set_highlight"):
			_interact_target.call("set_highlight", false)
		_interact_target = best
		if _interact_target and _interact_target.has_method("set_highlight"):
			_interact_target.call("set_highlight", true)


func _do_interact() -> void:
	if _interact_target == null or not is_instance_valid(_interact_target):
		return
	if _interact_target.has_method("interact"):
		_interact_target.call("interact", self)


func get_interact_target() -> Node:
	return _interact_target


# ---------------------------------------------------------------------------
# 消耗品
# ---------------------------------------------------------------------------

## 使用背包第 index 格的消耗品
func use_consumable(index: int) -> bool:
	var stack := GameState.inventory.get_slot(index)
	if stack == null or stack.data == null:
		return false
	var cd := stack.data as ConsumableData
	if cd == null:
		return false
	return _apply_consumable(cd, index)


func use_best_potion() -> bool:
	## 按「当前最缺」的原则挑一个药：血低于 60% 优先回血，否则回蓝
	var inv := GameState.inventory
	var want_hp := vitals != null and vitals.ratio_hp() < 0.6
	var best_index := -1
	for i in inv.slot_count:
		var s := inv.get_slot(i)
		if s == null or not (s.data is ConsumableData):
			continue
		var cd: ConsumableData = s.data
		if want_hp and cd.heal_amount > 0.0:
			best_index = i
			break
		if not want_hp and cd.mp_amount > 0.0:
			best_index = i
			break
		if best_index < 0:
			best_index = i
	if best_index < 0:
		EventBus.toast.emit("没有可用的消耗品", Color("#d94a4a"))
		return false
	return use_consumable(best_index)


func _apply_consumable(cd: ConsumableData, index: int) -> bool:
	if vitals == null:
		return false
	if cd.heal_amount > 0.0:
		vitals.heal(cd.heal_amount)
	if cd.mp_amount > 0.0:
		vitals.restore_mp(cd.mp_amount)
	if cd.armor_amount > 0.0:
		vitals.add_armor(cd.armor_amount)
	if cd.sfx_use != "":
		AudioManager.play_sfx(cd.sfx_use)
	CombatFx.popup(self, global_position + Vector2(0, -20), cd.display_name, cd.fx_color)
	CombatFx.spawn_sprite_burst(
		self, global_position, Atlas.prop(Atlas.PROP_HIT_SPARK), 6, cd.fx_color, 30.0
	)
	if cd.consume_on_use:
		GameState.inventory.take_from_slot(index, 1)
	return true


# ---------------------------------------------------------------------------
# 受伤 / 死亡
# ---------------------------------------------------------------------------

func _on_damaged(info: DamageInfo, actual: float) -> void:
	if actual <= 0.0:
		return
	flash_white()
	CombatFx.damage_number(
		self, global_position + Vector2(0, -18), actual, info.crit,
		Color("#ff8a8a") if not info.crit else Color("#ffd35c")
	)
	apply_knockback(info.knockback)
	EventBus.screen_shake_requested.emit(1.6, 0.18)


func _on_died() -> void:
	die()


func die() -> void:
	if is_dead:
		return
	super.die()
	desired_velocity = Vector2.ZERO
	if sprite:
		var tex := Atlas.frame("player_ranger", Atlas.P_DEAD.x, Atlas.P_DEAD.y)
		if tex:
			sprite.texture = tex
	set_z_height(0.0)
	AudioManager.play_sfx("res://assets/audio/sfx/player_die.wav")
	EventBus.player_died.emit()


# ---------------------------------------------------------------------------
# 信息
# ---------------------------------------------------------------------------

func skill_cooldown_ratio() -> float:
	return skill.cooldown_ratio() if skill else 1.0


func skill_icon() -> Texture2D:
	return character_data.get_skill_icon() if character_data else null


func guaranteed_crit_active() -> bool:
	return _guaranteed_crit_left > 0.0
