extends Node
## SkillTreeService —— 全局技能树（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 技能树是 **全局** 的：不属于任何角色，跨关卡、跨角色、跨存档保留。
## 2. 技能点来源只有两个：升级（GameState.add_xp → add_points）与调试指令。
## 3. 技能效果只能通过 StatEffect → StatBlock（apply_to）注入，
##    能力类效果只能通过 granted_tags（has_tag）查询。
##    **禁止** 在技能节点里写「解锁后调用某函数」这种硬逻辑——
##    需要硬逻辑时，在对应系统里 has_tag() 判空，保持数据驱动。
## 4. 任何修改后必须 emit EventBus.skill_tree_changed，
##    由 GameState 重算属性、由 UI 重绘整棵树。

var tree: SkillTreeData = null
## StringName -> 已投入等级
var levels: Dictionary = {}
## 可用技能点
var points: int = 0
## 累计获得过的技能点（统计用）
var total_points_earned: int = 0
## 累计花费
var total_points_spent: int = 0


func _ready() -> void:
	reload_tree()


func reload_tree() -> void:
	tree = ConfigDB.get_global_tree()
	if tree == null:
		push_warning("[SkillTreeService] 未找到 global_tree 技能树数据")
		return
	# 清理失效节点（数据改动后存档里可能残留）
	for id in levels.keys():
		if tree.get_node_by_id(id) == null:
			levels.erase(id)
		levels[id] = clampi(int(levels[id]), 0, 99)


func is_ready() -> bool:
	return tree != null


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func get_level(node_id: StringName) -> int:
	return int(levels.get(node_id, 0))


func is_unlocked(node_id: StringName) -> bool:
	return get_level(node_id) > 0


func is_maxed(node_id: StringName) -> bool:
	var nd := _node(node_id)
	if nd == null:
		return false
	return get_level(node_id) >= nd.max_level


func _node(node_id: StringName) -> SkillNodeData:
	if tree == null:
		return null
	return tree.get_node_by_id(node_id)


## 检查能否升级该节点。返回 { ok: bool, reason: String }
func can_unlock(node_id: StringName) -> Dictionary:
	var nd := _node(node_id)
	if nd == null:
		return {"ok": false, "reason": "技能不存在"}
	var cur := get_level(node_id)
	if cur >= nd.max_level:
		return {"ok": false, "reason": "已满级"}
	if GameState.player_level < nd.required_player_level:
		return {"ok": false, "reason": "需要角色等级 %d" % nd.required_player_level}
	var cost := nd.cost_to_upgrade(cur)
	if points < cost:
		return {"ok": false, "reason": "技能点不足（需要 %d）" % cost}
	# 前置检查
	for i in nd.prerequisites.size():
		var pre := nd.prerequisites[i]
		var need := 1
		if i < nd.prerequisite_levels.size():
			need = maxi(1, nd.prerequisite_levels[i])
		if get_level(pre) < need:
			var pnd := _node(pre)
			var pname := pnd.display_name if pnd else String(pre)
			return {"ok": false, "reason": "需要前置「%s」%d 级" % [pname, need]}
	return {"ok": true, "reason": ""}


## 尝试升级，成功返回 true
func unlock(node_id: StringName, silent: bool = false) -> bool:
	var res := can_unlock(node_id)
	if not res["ok"]:
		if not silent:
			EventBus.toast.emit(String(res["reason"]), Color("#d94a4a"))
		return false
	var nd := _node(node_id)
	var cur := get_level(node_id)
	var cost := nd.cost_to_upgrade(cur)
	points -= cost
	total_points_spent += cost
	levels[node_id] = cur + 1
	if not silent:
		EventBus.skill_unlocked.emit(node_id, cur + 1)
		EventBus.toast.emit("「%s」提升到 %d 级" % [nd.display_name, cur + 1], Color("#8fc75a"))
	_emit_all()
	return true


## 洗点：返还全部已花费技能点
func respec() -> void:
	var refund := 0
	for id in levels.keys():
		var nd := _node(id)
		if nd == null:
			continue
		refund += nd.cost_per_level * int(levels[id])
	levels.clear()
	points += refund
	total_points_spent = maxi(0, total_points_spent - refund)
	EventBus.toast.emit("已洗点，返还 %d 技能点" % refund, Color("#8fd3f2"))
	_emit_all()


func add_points(n: int) -> void:
	if n <= 0:
		return
	points += n
	total_points_earned += n
	EventBus.skill_points_changed.emit(points)


func set_points(n: int) -> void:
	points = maxi(0, n)
	EventBus.skill_points_changed.emit(points)


# ---------------------------------------------------------------------------
# 效果应用
# ---------------------------------------------------------------------------

## 把所有已点技能的效果注入属性块
func apply_to(block: StatBlock) -> void:
	if tree == null or block == null:
		return
	for nd in tree.nodes:
		var lv := get_level(nd.id)
		if lv <= 0:
			continue
		for e in nd.effects:
			e.apply_to(block, lv)


## 是否拥有某个能力标签
func has_tag(tag: String) -> bool:
	if tree == null:
		return false
	for nd in tree.nodes:
		if get_level(nd.id) <= 0:
			continue
		if nd.granted_tags.has(tag):
			return true
	return false


## 收集当前所有已获得的能力标签
func collect_tags() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if tree == null:
		return out
	for nd in tree.nodes:
		if get_level(nd.id) <= 0:
			continue
		for t in nd.granted_tags:
			if not out.has(t):
				out.append(t)
	return out


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var lv: Dictionary = {}
	for k in levels.keys():
		lv[String(k)] = int(levels[k])
	return {
		"levels": lv,
		"points": points,
		"total_points_earned": total_points_earned,
		"total_points_spent": total_points_spent,
	}


func from_dict(d: Dictionary) -> void:
	levels.clear()
	var raw: Dictionary = d.get("levels", {})
	for k in raw.keys():
		levels[StringName(k)] = int(raw[k])
	points = maxi(0, int(d.get("points", 0)))
	total_points_earned = int(d.get("total_points_earned", 0))
	total_points_spent = int(d.get("total_points_spent", 0))
	reload_tree()
	_emit_all()


func reset() -> void:
	levels.clear()
	points = 0
	total_points_earned = 0
	total_points_spent = 0
	_emit_all()


func _emit_all() -> void:
	EventBus.skill_points_changed.emit(points)
	EventBus.skill_tree_changed.emit()


# ---------------------------------------------------------------------------
# 调试
# ---------------------------------------------------------------------------

func debug_unlock_all() -> void:
	if tree == null:
		return
	for nd in tree.nodes:
		levels[nd.id] = nd.max_level
	_emit_all()
	print("[SkillTreeService] 已解锁全部技能（调试）")
