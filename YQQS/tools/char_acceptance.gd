extends Node
## 角色/敌人图集**游戏内**验收：真跑起来，确认贴图能被正确取到并显示。
##
## 【为什么不能只看 PNG 结构】图集尺寸对了，不代表运行时代码取到的帧是对的 ——
## 双网格地表那次就吃过"图集 16/16 正确、但图层取错槽位"的亏。
## 这里直接把 Enemy / Player 实例化出来，逐个动画名取帧，量它们的实际尺寸与内容。

const ENEMY_SCENE := "res://scenes/enemies/Enemy.tscn"
const LEVEL_SCENE := "res://scenes/levels/forest/ForestLevel.tscn"

var _errors: Array[String] = []
var _logs: Array[String] = []


func _ready() -> void:
	print("[角色验收] === 开始 ===")
	_run()


func _run() -> void:
	# ① Atlas 层：每个敌人表、每个动画名，逐帧取出来量尺寸
	_check_atlas_frames()
	# ② 场景层：真的生成一个关卡，看敌精灵有没有贴图
	var lvl: Node = load(LEVEL_SCENE).instantiate()
	add_child(lvl)
	for i in 4:
		await get_tree().process_frame
	await _check_live_enemies()
	_finish()


func _finish() -> void:
	print("")
	print("[角色验收] === 结果 ===")
	for l in _logs:
		print("[角色验收]   OK  ", l)
	if _errors.is_empty():
		print("[角色验收] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for e in _errors:
			print("[角色验收]   [ERROR] ", e)
		get_tree().quit(1)


func _check_atlas_frames() -> void:
	var anims: Array = Atlas.ENEMY_ANIMS.keys()
	var checked := 0
	for key in Atlas.ENEMY_SHEETS.keys():
		var sheet: String = Atlas.ENEMY_SHEETS[key]
		var meta: Dictionary = Atlas.SHEETS.get(sheet, {})
		var cell: int = int(meta.get("cell", 0))
		var cols: int = int(meta.get("cols", 0))
		var frame_count: int = cols * int(meta.get("rows", 0))
		if cell <= 0 or cols <= 0:
			_errors.append("%s 的图集元数据缺失" % sheet)
			continue
		for anim in anims:
			var seq: Array = Atlas.ENEMY_ANIMS[anim]
			for step in seq.size():
				var tex: AtlasTexture = Atlas.enemy_frame(key, String(anim), step)
				if tex == null:
					_errors.append("%s / %s 第 %d 步取不到帧" % [key, anim, step])
					continue
				var r: Rect2 = tex.region
				if r.size != Vector2(cell, cell):
					_errors.append("%s / %s 帧尺寸 %s，期望 %dx%d" % [
						key, anim, str(r.size), cell, cell])
				# 帧号必须落在图集范围内
				var idx: int = int(seq[step]) if false else int(seq[step % seq.size()])
				if idx < 0 or idx >= frame_count:
					_errors.append("%s / %s 帧号 %d 超出图集范围 0..%d" % [
						key, anim, idx, frame_count - 1])
				checked += 1
	_logs.append("敌人图集：%d 个表 x %d 个动画，共校验 %d 帧，尺寸与帧号全部合法" % [
		Atlas.ENEMY_SHEETS.size(), anims.size(), checked])

	# 玩家 16 格逐格取
	var pmeta: Dictionary = Atlas.SHEETS["player_ranger"]
	var pcell: int = int(pmeta["cell"])
	var bad := 0
	for row in int(pmeta["rows"]):
		for col in int(pmeta["cols"]):
			var t := Atlas.frame("player_ranger", col, row)
			if t == null or t.region.size != Vector2(pcell, pcell):
				bad += 1
	if bad > 0:
		_errors.append("player_ranger 有 %d 格取帧异常" % bad)
	else:
		_logs.append("player_ranger：16 格取帧全部为 %dx%d" % [pcell, pcell])


func _check_live_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		_errors.append("关卡里没有敌人，无法验证实战取帧")
		return
	var with_tex := 0
	var sizes := {}
	for e in enemies:
		var sp = e.get("sprite")
		if sp == null or sp.texture == null:
			continue
		with_tex += 1
		var sz: Vector2 = sp.texture.get_size()
		sizes[sz] = int(sizes.get(sz, 0)) + 1
	if with_tex == 0:
		_errors.append("所有敌人精灵都没有贴图")
		return
	_logs.append("关卡内 %d 个敌人有贴图，尺寸分布 %s" % [with_tex, str(sizes)])
	# 玩家
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_errors.append("没有玩家节点")
		return
	var psp = players[0].get("sprite")
	if psp == null or psp.texture == null:
		_errors.append("玩家精灵没有贴图")
	else:
		_logs.append("玩家贴图尺寸 %s" % str(psp.texture.get_size()))
