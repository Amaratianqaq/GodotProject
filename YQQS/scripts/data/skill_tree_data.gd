class_name SkillTreeData
extends Resource
## 技能树定义（一棵树 = 一个 Resource）。
##
## 第一阶段只有一棵全局树 `global_tree`，放在 res://data/skills/global_tree.tres。
## 后续要加「角色专属树」，新建 Resource 并在 ConfigDB 登记即可。

@export var id: StringName = &"global_tree"
@export var display_name: String = "全局技能树"
@export_multiline var description: String = ""
## 树内所有节点
@export var nodes: Array[SkillNodeData] = []
## 面板网格尺寸（用于 UI 布局滚动区域大小）
@export var grid_size: Vector2i = Vector2i(6, 5)


func get_node_by_id(node_id: StringName) -> SkillNodeData:
	for n in nodes:
		if n.id == node_id:
			return n
	return null


func get_nodes_in_branch(branch: StringName) -> Array[SkillNodeData]:
	var out: Array[SkillNodeData] = []
	for n in nodes:
		if n.branch == branch:
			out.append(n)
	return out


func get_branches() -> Array[StringName]:
	var seen: Dictionary = {}
	var out: Array[StringName] = []
	for n in nodes:
		if not seen.has(n.branch):
			seen[n.branch] = true
			out.append(n.branch)
	return out


## 环检测：返回检测到的环路径，无环返回空数组
func find_cycles() -> Array:
	var state: Dictionary = {}
	var cycle: Array = []
	for n in nodes:
		if _visit_cycle(n.id, state, [], cycle):
			return cycle
	return []


func _visit_cycle(node_id: StringName, state: Dictionary, stack: Array, cycle: Array) -> bool:
	var st: int = int(state.get(node_id, 0))
	if st == 1:
		# 命中「访问中」的节点 = 发现环
		cycle.clear()
		cycle.append_array(stack)
		cycle.append(node_id)
		return true
	if st == 2:
		return false
	state[node_id] = 1
	stack.append(node_id)
	var nd := get_node_by_id(node_id)
	if nd:
		for pre in nd.prerequisites:
			if _visit_cycle(pre, state, stack, cycle):
				return true
	stack.pop_back()
	state[node_id] = 2
	return false


## 校验所有前置引用都存在，返回缺失的 id 列表
func find_missing_prerequisites() -> Array[StringName]:
	var ids: Dictionary = {}
	for n in nodes:
		ids[n.id] = true
	var missing: Array[StringName] = []
	for n in nodes:
		for pre in n.prerequisites:
			if not ids.has(pre):
				missing.append(pre)
	return missing
