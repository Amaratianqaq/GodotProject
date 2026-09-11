class_name NodeUtils
extends RefCounted
## 节点/树操作小工具。

## 在 group 中找出离 point 最近的节点（带最大距离限制，<=0 表示不限）
static func nearest_in_group(
	tree: SceneTree, group: StringName, point: Vector2, max_dist: float = -1.0
) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in tree.get_nodes_in_group(group):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if n is Node and n.get("is_dead") == true:
			continue
		var d := (n as Node2D).global_position.distance_squared_to(point)
		if max_dist > 0.0 and d > max_dist * max_dist:
			continue
		if d < best_d:
			best_d = d
			best = n
	return best


## 找出 group 中在 radius 内的全部 Node2D
static func all_in_radius(
	tree: SceneTree, group: StringName, point: Vector2, radius: float
) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var r2 := radius * radius
	for n in tree.get_nodes_in_group(group):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if (n as Node2D).global_position.distance_squared_to(point) <= r2:
			out.append(n)
	return out


## 按名字深度查找子节点（支持 "A/B/C"）
static func find_child_path(root: Node, path: String) -> Node:
	if root == null:
		return null
	return root.get_node_or_null(NodePath(path))


## 安全地给节点加一个 group（幂等）
static func ensure_group(n: Node, group: StringName) -> void:
	if n and not n.is_in_group(group):
		n.add_to_group(group)


## 在场景树里找到第一个满足 predicate 的节点
static func find_first(root: Node, predicate: Callable) -> Node:
	if predicate.call(root):
		return root
	for c in root.get_children():
		var r := find_first(c, predicate)
		if r:
			return r
	return null


## 递归设置 CanvasItem 的 modulate（用于受击整体染色）
static func set_modulate_recursive(n: Node, c: Color) -> void:
	if n is CanvasItem:
		(n as CanvasItem).modulate = c
	for ch in n.get_children():
		set_modulate_recursive(ch, c)


## 递归设置 process_mode（用于暂停时冻结子树）
static func set_process_mode_recursive(n: Node, mode: int) -> void:
	n.process_mode = mode
	for ch in n.get_children():
		set_process_mode_recursive(ch, mode)
