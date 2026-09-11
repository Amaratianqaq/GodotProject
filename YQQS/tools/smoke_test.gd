extends Node
## 运行时冒烟测试（场景式，headless 可跑）。
##
## 用法：
##   & godot --headless --path E:\GodotProject res://tools/SmokeTest.tscn
##
## 它做的是「静态校验做不到」的事：真的把关卡和大厅跑起来，
## 生成地图、刷怪、开火、命中、开箱、清房、切场景，并检查运行时状态。
## 退出码 0 = 通过。

const FOREST_SCENE := "res://scenes/levels/forest/ForestLevel.tscn"
const LOBBY_SCENE := "res://scenes/lobby/Lobby.tscn"

var _errors: PackedStringArray = PackedStringArray()
var _steps: PackedStringArray = PackedStringArray()
var _level: ForestLevel = null
var _player: Player = null


func _ready() -> void:
	_log("=== 运行时冒烟测试 ===")
	await get_tree().process_frame
	await _test_forest()
	await _test_lobby()
	_report()
	get_tree().quit(0 if _errors.is_empty() else 1)


# ---------------------------------------------------------------------------
# 森林关卡
# ---------------------------------------------------------------------------

func _test_forest() -> void:
	_log("--- 关卡：宁静森林 ---")
	if RunManager:
		RunManager.start_run(20240601, 0)
	var ps: PackedScene = load(FOREST_SCENE)
	if ps == null:
		_error("无法加载关卡场景")
		return
	_level = ps.instantiate() as ForestLevel
	add_child(_level)
	await _wait_frames(6)

	if _level.graph == null:
		_error("地图未生成")
		return
	_check("地图生成", _level.graph.room_count() >= 5,
		"%d 个房间 / %d 条走廊" % [_level.graph.room_count(), _level.graph.corridors.size()])
	_check("地形已铺设", _level.ground != null and _level.ground.get_used_cells().size() > 200,
		"%d 个地板格" % (_level.ground.get_used_cells().size() if _level.ground else 0))

	_player = _level.player
	if _player == null:
		_error("玩家未生成")
		return
	_check("玩家生成", true, "位置 %s" % str(_player.global_position))

	# 属性与血蓝
	var v := _player.vitals
	if v == null:
		_error("玩家缺少 VitalsComponent")
	else:
		_check("血蓝系统初始化", v.max_hp > 0.0 and v.max_mp > 0.0,
			"HP %.0f / 护甲 %.0f / MP %.0f" % [v.max_hp, v.max_armor, v.max_mp])

	# 敌人
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check("敌人已刷出", enemies.size() >= 5, "%d 只" % enemies.size())

	# 宝箱
	var chests := 0
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Chest:
			chests += 1
	_check("宝箱已放置", chests >= 1, "%d 个" % chests)

	# ---- 开火 ----
	await _test_weapon_fire()

	# ---- 伤害链路：手动打一只怪 ----
	await _test_damage_pipeline(enemies)

	# ---- 开箱 ----
	await _test_chest_opening()

	# ---- 清空 BOSS 房（直接把 BOSS 打死，验证掉落 + 出口解锁）----
	await _test_boss_kill()

	# ---- 玩家受伤/死亡链路 ----
	_test_player_damage()

	# ---- 命中顿帧 ----
	await _test_hitstop()

	# ---- 玩家技能（翻滚）----
	await _test_roll()


func _test_weapon_fire() -> void:
	var w := _player.get_active_weapon()
	if w == null:
		_warn("玩家没有初始武器")
		return
	var before := _count_projectiles()
	for i in 3:
		w.call("try_fire")
		await _wait_frames(3)
	var after := _count_projectiles()
	_check("武器开火", after > before, "%s 发射后场上投射物 %d → %d" % [
		String(w.get("data").id), before, after
	])
	# 换装樱花霰弹枪
	var cherry := ConfigDB.get_weapon(&"cherry_shotgun")
	if cherry == null:
		_error("找不到樱花霰弹枪")
		return
	_player.equip_weapon(cherry, 0)
	await _wait_frames(3)
	var w2 := _player.get_active_weapon()
	if w2 == null or not (w2 is WeaponCherryShotgun):
		_error("樱花霰弹枪未能装备到玩家身上")
		return
	_check("装备樱花霰弹枪", true, String(w2.call("describe_last_shot")))
	var b2 := _count_projectiles()
	w2.call("try_fire")
	await _wait_frames(3)
	var a2 := _count_projectiles()
	_check("樱花霰弹枪 5 瓣散射", a2 - b2 >= 4, "射出 %d 枚花瓣" % (a2 - b2))
	_check("弹药与换弹状态", int(w2.get("ammo")) < 6, "剩余弹药 %d / 6" % int(w2.get("ammo")))


func _test_damage_pipeline(enemies: Array) -> void:
	if enemies.is_empty():
		return
	var victim: Enemy = null
	for e in enemies:
		if e is Enemy and is_instance_valid(e) and not e.is_dead:
			victim = e
			break
	if victim == null:
		return
	var hp_before := victim.vitals.hp
	var info := DamageInfo.make(12.0, _player, _player, GameEnums.Faction.PLAYER)
	info.crit = true
	var hb := victim.get_hurtbox()
	if hb == null:
		_error("敌人缺少 Hurtbox")
		return
	var dealt := hb.receive_hit(info)
	_check("伤害结算链路", dealt > 0.0 and victim.vitals.hp < hp_before,
		"造成 %.1f 伤害（%.1f → %.1f）" % [dealt, hp_before, victim.vitals.hp])
	# 同阵营不应受伤
	var allied := DamageInfo.make(50.0, victim, victim, GameEnums.Faction.ENEMY)
	var hp2 := victim.vitals.hp
	hb.receive_hit(allied)
	_check("同阵营免伤", is_equal_approx(victim.vitals.hp, hp2), "HP 未变化")
	# 无敌帧
	var info2 := DamageInfo.make(50.0, _player, _player, GameEnums.Faction.PLAYER)
	victim.vitals.invincible = true
	var hp3 := victim.vitals.hp
	hb.receive_hit(info2)
	_check("无敌状态免疫", is_equal_approx(victim.vitals.hp, hp3), "HP 未变化")
	victim.vitals.invincible = false


func _test_chest_opening() -> void:
	var chest: Chest = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Chest and not n.is_used():
			chest = n
			break
	if chest == null:
		_warn("场景里没有可开的宝箱，跳过")
		return
	var pickups_before := _count_pickups()
	var gold_before := GameState.gold
	chest.interact(_player)
	await _wait_frames(6)
	var pickups_after := _count_pickups()
	_check("开箱产出掉落物", pickups_after > pickups_before,
		"掉落物 %d → %d，金币 %d → %d" % [
			pickups_before, pickups_after, gold_before, GameState.gold
		])
	_check("宝箱不可重复开启", not chest.can_interact(_player), "")


func _test_boss_kill() -> void:
	var boss: Enemy = null
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Enemy and n.is_boss():
			boss = n
			break
	if boss == null:
		_warn("没有找到 BOSS（可能没刷出 BOSS 房）")
		return
	var pickups_before := _count_pickups()
	boss.vitals.kill()
	await _wait_frames(10)
	var pickups_after := _count_pickups()
	_check("BOSS 击杀 → 掉落", pickups_after > pickups_before,
		"掉落物 %d → %d" % [pickups_before, pickups_after])
	_check("BOSS 死亡后出口解锁", _level.exit_portal != null and _level.exit_portal.visible,
		"出口 %s" % ("已出现" if _level.exit_portal and _level.exit_portal.visible else "未出现"))
	_check("RunManager 击杀计数", RunManager.enemies_killed > 0,
		"击杀 %d / 生成 %d" % [RunManager.enemies_killed, RunManager.enemies_spawned])


func _test_player_damage() -> void:
	var v := _player.vitals
	if v == null:
		return
	var hp0 := v.hp
	var armor0 := v.armor
	var info := DamageInfo.make(15.0, null, null, GameEnums.Faction.ENEMY)
	v.invincible_time = 0.0
	v.apply_damage(info)
	var armor_lost := armor0 - v.armor
	_check("玩家护甲优先承伤", armor_lost > 0.0 and is_equal_approx(v.hp, hp0),
		"护甲 %.0f → %.0f，生命保持 %.0f" % [armor0, v.armor, v.hp])
	# 打光护甲后开始掉血
	v.set_armor_value(0.0)
	v.invincible_time = 0.0
	var hp1 := v.hp
	v.apply_damage(DamageInfo.make(10.0))
	_check("护甲清空后扣血", v.hp < hp1, "%.0f → %.0f" % [hp1, v.hp])
	# 治疗
	var healed := v.heal(20.0)
	_check("治疗生效", healed > 0.0, "回复 %.1f" % healed)
	var mp0 := v.mp
	v.consume_mp(10.0)
	_check("能量消耗", v.mp < mp0, "%.0f → %.0f" % [mp0, v.mp])
	# 玩家受击无敌帧：否则多弹丸齐射会瞬间秒杀
	_check("玩家受击无敌帧", v.iframe_duration > 0.0,
		"iframe = %.2fs" % v.iframe_duration)
	v.invincible_time = 0.0
	v.apply_damage(DamageInfo.make(5.0))
	var iframe_after := v.invincible_time
	var hp_after_iframe := v.hp
	v.apply_damage(DamageInfo.make(5.0))
	_check("无敌期间免疫伤害", iframe_after > 0.0 and is_equal_approx(v.hp, hp_after_iframe),
		"无敌剩余 %.2fs，HP 保持 %.0f" % [iframe_after, v.hp])
	# 敌人不应有受击无敌（否则霰弹枪多弹丸只算一次）
	var any_enemy: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and is_instance_valid(e) and not e.is_dead:
			any_enemy = e
			break
	if any_enemy and any_enemy.vitals:
		_check("敌人无受击无敌", is_zero_approx(any_enemy.vitals.iframe_duration),
			"iframe = %.2fs（霰弹枪可多段命中）" % any_enemy.vitals.iframe_duration)


func _test_hitstop() -> void:
	## 命中顿帧必须接入并会自动恢复，否则时间会被永久压住。
	## 【测试要点】time_scale 压到很低时，一个 physics frame 的真实耗时会被拉长，
	## 所以「顿帧是否生效」必须在 emit 之后**同步**读取，
	## 不能等一帧再读（那时顿帧已经自然结束了）。
	Engine.time_scale = 1.0
	RunManager.reset_time_scale()   # 清掉之前命中残留的顿帧，保证这次请求一定被接受
	var leftover: float = RunManager._hitstop_left
	EventBus.hitstop_requested.emit(0.05)
	var during := Engine.time_scale
	await _wait_frames(30)
	var after := Engine.time_scale
	_check("命中顿帧接入并自动恢复", during < 1.0 and is_equal_approx(after, 1.0),
		"请求前残留 %.4fs · 顿帧中 time_scale=%.3f → 恢复后 %.2f" % [leftover, during, after])
	Engine.time_scale = 1.0


func _test_roll() -> void:
	if _player.skill == null:
		_warn("玩家没有主动技能")
		return
	_player.skill.cooldown_left = 0.0
	var ok := _player.skill.try_use()
	_check("游侠翻滚技能", ok, "冷却 %.2fs，必暴窗口 %.2fs" % [
		_player.skill.effective_cooldown(), RogueRoll.GUARANTEED_CRIT_WINDOW
	])
	await _wait_frames(24)
	_check("翻滚后获得必暴", _player.guaranteed_crit_active(), "必暴就绪")
	var consumed := _player.consume_guaranteed_crit()
	_check("必暴可被武器消费", consumed and not _player.guaranteed_crit_active(), "")


# ---------------------------------------------------------------------------
# 大厅
# ---------------------------------------------------------------------------

func _test_lobby() -> void:
	_log("--- 大厅 ---")
	if _level and is_instance_valid(_level):
		_level.queue_free()
		await _wait_frames(3)
	var ps: PackedScene = load(LOBBY_SCENE)
	if ps == null:
		_error("无法加载大厅场景")
		return
	var lobby := ps.instantiate() as Lobby
	add_child(lobby)
	await _wait_frames(6)
	_check("大厅加载", lobby.player != null, "")
	# 角色选择
	var chars := ConfigDB.all_characters()
	if chars.size() > 0:
		var ok := GameState.select_character(chars[0].id)
		_check("角色选择", ok, "%s" % chars[0].display_name)
	# 仓库存取
	var inv := GameState.inventory
	var potion := ConfigDB.get_item(&"hp_potion_small")
	if potion:
		inv.add_item(ItemStack.new(potion, 5))
		var expect := inv.count_of(&"hp_potion_small")
		var n := WarehouseService.deposit_from_inventory(inv, inv.find_slot_of(&"hp_potion_small"), -1)
		_check("仓库存入", n == expect and inv.count_of(&"hp_potion_small") == 0,
			"存入 %d 个（期望 %d），仓库占用 %d 格" % [n, expect, WarehouseService.store.used_slots()])
		var idx := WarehouseService.find_slot(&"hp_potion_small")
		var m := WarehouseService.withdraw_to_inventory(inv, idx, 2)
		_check("仓库取出", m == 2, "取出 %d 个，背包现有 %d 个" % [m, inv.count_of(&"hp_potion_small")])
	# 装备武器跨场景保留
	if GameState.equipped_weapons[0] != &"":
		_check("武器持久化", true, "槽位 1 = %s" % GameState.equipped_weapons[0])
	else:
		_error("GameState 没有记录已装备武器（换场景会丢武器）")
	# 传送门
	var portals := 0
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Portal:
			portals += 1
	_check("大厅传送门", portals >= 1, "%d 个" % portals)
	lobby.queue_free()
	await _wait_frames(3)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _count_projectiles() -> int:
	var root := get_tree().get_first_node_in_group("projectile_root")
	if root == null:
		return 0
	var n := 0
	for c in root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			n += 1
	return n


func _count_pickups() -> int:
	var n := 0
	var seen: Dictionary = {}
	for group in ["pickup_root", "entity_root"]:
		var root := get_tree().get_first_node_in_group(group)
		if root == null:
			continue
		for c in root.get_children():
			if not is_instance_valid(c) or c.is_queued_for_deletion():
				continue
			if c is PickupBase and not seen.has(c.get_instance_id()):
				seen[c.get_instance_id()] = true
				n += 1
	return n


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	var line := "%s %s" % ["✓" if ok else "✗", label]
	if detail != "":
		line += "  —— " + detail
	_log("  " + line)
	if not ok:
		_errors.append(label)


func _warn(msg: String) -> void:
	_log("  [WARN] " + msg)


func _error(msg: String) -> void:
	_log("  [ERROR] " + msg)
	_errors.append(msg)


func _log(s: String) -> void:
	print("[SMOKE] " + s)


func _report() -> void:
	_log("=== 结果 ===")
	if _errors.is_empty():
		_log("全部通过 ✅")
	else:
		_log("失败 %d 项：" % _errors.size())
		for e in _errors:
			_log("  [FAIL] " + e)
