class_name CombatFx
extends RefCounted
## 战斗表现统一入口（飘字、火花、枪口火焰、死亡特效）。
##
## 【框架约束 · 必读】
## 1. 业务代码 **禁止** 自己 new Label / Sprite2D 做临时特效，
##    一律调用本文件的静态方法，便于统一数量上限与美术风格。
## 2. 特效节点必须挂在 group "fx_root" 的节点下（关卡根节点会自建 FxRoot），
##    否则会随实体一起被 queue_free 掉导致特效消失。

const MAX_FLOATING := 48
const MAX_SPARKS := 96

static var _floating_count: int = 0
static var _spark_count: int = 0


## 找到特效容器：优先 group "fx_root"，否则用当前场景根
static func fx_parent(context: Node) -> Node:
	if context == null or not is_instance_valid(context):
		return null
	var tree := context.get_tree()
	if tree == null:
		return null
	var root := tree.get_first_node_in_group("fx_root")
	if root and is_instance_valid(root):
		return root
	return tree.current_scene


# ---------------------------------------------------------------------------
# 伤害飘字
# ---------------------------------------------------------------------------

static func damage_number(
	context: Node,
	pos: Vector2,
	amount: float,
	crit: bool = false,
	color: Color = Color.WHITE
) -> void:
	if _floating_count >= MAX_FLOATING:
		return
	var parent := fx_parent(context)
	if parent == null:
		return
	var txt := str(int(round(amount)))
	var fs := 9 if crit else 7
	var col := color
	if crit:
		col = Color("#ffd35c")
		txt = txt + "!"
	_floating_count += 1
	var fl := FloatingLabel.spawn(parent, pos, txt, col, fs, crit)
	if fl:
		fl.tree_exited.connect(func() -> void: _floating_count = maxi(0, _floating_count - 1))


static func popup(context: Node, pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	if _floating_count >= MAX_FLOATING:
		return
	var parent := fx_parent(context)
	if parent == null:
		return
	_floating_count += 1
	var fl := FloatingLabel.spawn(parent, pos, text, color, 7, false)
	if fl:
		fl.tree_exited.connect(func() -> void: _floating_count = maxi(0, _floating_count - 1))


# ---------------------------------------------------------------------------
# 命中火花
# ---------------------------------------------------------------------------

static func hit_spark(context: Node, pos: Vector2, dir: Vector2 = Vector2.ZERO, scale: float = 1.0) -> void:
	if _spark_count >= MAX_SPARKS:
		return
	var parent := fx_parent(context)
	if parent == null:
		return
	var tex := Atlas.prop(Atlas.PROP_HIT_SPARK)
	if tex == null:
		return
	var rot := -1.0
	if dir != Vector2.ZERO:
		rot = dir.angle()
	_spark_count += 1
	var s := HitSpark.spawn(parent, pos, tex, 0.16, 0.8 * scale, 1.8 * scale, Color.WHITE, rot)
	if s:
		s.tree_exited.connect(func() -> void: _spark_count = maxi(0, _spark_count - 1))


static func muzzle_flash(context: Node, pos: Vector2, dir: Vector2, scale: float = 1.0) -> void:
	var parent := fx_parent(context)
	if parent == null:
		return
	var tex := Atlas.prop(Atlas.PROP_MUZZLE_FLASH)
	if tex == null:
		return
	HitSpark.spawn(parent, pos, tex, 0.09, 1.1 * scale, 0.35 * scale, Color("#ffd35c"), dir.angle())


## 死亡爆散（用金币/火花贴图拼一圈）
static func death_burst(context: Node, pos: Vector2, color: Color = Color.WHITE, count: int = 6) -> void:
	var parent := fx_parent(context)
	if parent == null:
		return
	var tex := Atlas.prop(Atlas.PROP_HIT_SPARK)
	if tex == null:
		return
	for i in count:
		var a := TAU * (float(i) / float(count)) + randf() * 0.4
		var off := Vector2(cos(a), sin(a)) * randf_range(3.0, 11.0)
		var s := HitSpark.spawn(parent, pos + off, tex, 0.34, 1.0, 0.2, color)
		if s:
			s._velocity = Vector2(cos(a), sin(a)) * randf_range(22.0, 46.0)


# ---------------------------------------------------------------------------
# 拾取提示
# ---------------------------------------------------------------------------

static func pickup_text(context: Node, pos: Vector2, text: String, color: Color) -> void:
	popup(context, pos, text, color)


# ---------------------------------------------------------------------------
# 标签漂移特效（樱花花瓣等由投射物自己处理）
# ---------------------------------------------------------------------------

static func spawn_sprite_burst(
	context: Node, pos: Vector2, tex: Texture2D, count: int, color: Color, speed: float
) -> void:
	var parent := fx_parent(context)
	if parent == null or tex == null:
		return
	for i in count:
		var a := randf() * TAU
		var s := HitSpark.spawn(parent, pos, tex, 0.5, 1.0, 0.2, color, randf() * TAU)
		if s:
			s._velocity = Vector2(cos(a), sin(a)) * speed * randf_range(0.6, 1.4)
