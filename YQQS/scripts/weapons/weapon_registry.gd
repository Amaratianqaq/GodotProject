class_name WeaponRegistry
extends RefCounted
## 武器工厂 —— 把 WeaponData 变成可用的武器节点。
##
## 【框架约束 · 必读】
## 1. 唯一创建武器的入口是 create()。禁止在别处 new WeaponXxx()。
## 2. 分发优先级：
##      ① WeaponData.script_path 指定的专属脚本（如樱花霰弹枪）
##      ② 按 kind 的默认实现（MELEE → WeaponMelee，其余 → WeaponRanged）
## 3. 专属脚本必须 `extends WeaponBase`（或其后代）并实现 `_do_fire()`。
##    在 ConfigDB 加载时会做校验，写错了会在启动时报错而不是运行中爆炸。

const DEFAULT_MELEE_SCRIPT := "res://scripts/weapons/weapon_melee.gd"
const DEFAULT_RANGED_SCRIPT := "res://scripts/weapons/weapon_ranged.gd"


## 创建武器节点（尚未加入场景树）。调用方负责 add_child 并调用 setup()。
static func create_node(data: WeaponData) -> Node2D:
	if data == null:
		push_error("[WeaponRegistry] WeaponData 为 null")
		return null
	var script := resolve_script(data)
	if script == null:
		push_error("[WeaponRegistry] 无法为武器 %s 解析实现脚本" % data.id)
		return null
	var n := Node2D.new()
	n.name = "Weapon_" + String(data.id)
	n.set_script(script)
	return n


## 一步到位：创建 + setup
static func create_and_setup(data: WeaponData, holder: Node2D, parent: Node) -> Node2D:
	var n := create_node(data)
	if n == null:
		return null
	if parent:
		parent.add_child(n)
	n.call("setup", data, holder)
	return n


## 解析要使用的脚本资源
static func resolve_script(data: WeaponData) -> Script:
	if data.script_path != "":
		if not ResourceLoader.exists(data.script_path):
			push_error("[WeaponRegistry] 武器 %s 的 script_path 不存在: %s" % [
				data.id, data.script_path
			])
		else:
			var s: Script = load(data.script_path)
			if s == null:
				push_error("[WeaponRegistry] 武器 %s 的脚本加载失败: %s" % [
					data.id, data.script_path
				])
			else:
				return s
	# 默认实现
	var path := DEFAULT_MELEE_SCRIPT if data.kind == GameEnums.WeaponKind.MELEE else DEFAULT_RANGED_SCRIPT
	return load(path)


## 校验：所有武器都能创建出节点（ConfigDB 启动时可选调用）
static func validate_all() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for w in ConfigDB.all_weapons():
		var s := resolve_script(w)
		if s == null:
			errors.append("武器 %s 无法解析实现脚本" % w.id)
			continue
		var n := Node2D.new()
		n.set_script(s)
		if not (n is WeaponBase):
			errors.append("武器 %s 的实现脚本未继承 WeaponBase" % w.id)
		n.free()
	return errors


## 该武器是否已有「专属实现」（用于 UI 上标注「待实装」）
static func has_custom_implementation(data: WeaponData) -> bool:
	return data != null and data.script_path != ""
