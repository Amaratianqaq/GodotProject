class_name PickupBase
extends Area2D
## 掉落物基类（金币 / 物品 / 武器掉落）。
##
## 【框架约束 · 必读】
## 1. 掉落物 **不参与物理碰撞**：用距离判定 + 磁吸，避免和角色碰撞体打架。
##    因此碰撞层只放 PICKUP，掩码为 0。
## 2. 磁吸半径 = 玩家 PickupRange（技能树可加成），实现「拾取范围」属性。
## 3. 掉落物落地时有短暂的「不可拾取」时间与抛物线弹出，
##    防止开箱瞬间被一次性吸干、也让掉落有手感。
## 4. 子类实现 `_collect(player)` 决定拾取效果，并返回是否成功。

@export_group("拾取")
## 磁吸半径（<=0 表示使用玩家属性）
@export var magnet_radius: float = 0.0
## 进入该距离即拾取
@export var collect_distance: float = 7.0
## 落地弹出后多久才可被拾取
@export var pickup_delay: float = 0.35
## 弹出初速度
@export var pop_speed: float = 34.0

@export_group("表现")
## 上下浮动幅度（像素）
@export var bob_amplitude: float = 1.5
@export var bob_speed: float = 3.0
## 是否自动销毁（长时间没人捡）
@export var lifetime: float = 0.0

var _t: float = 0.0
var _pickup_timer: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _base_y: float = 0.0
var _player: Node2D = null
var sprite: Sprite2D = null
var _collected: bool = false


func _ready() -> void:
	collision_layer = Layers.PICKUP_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false
	NodeUtils.ensure_group(self, &"pickups")
	sprite = get_node_or_null("Sprite") as Sprite2D
	_base_y = position.y
	# 落地弹出
	if pop_speed > 0.0:
		var a := randf() * TAU
		_velocity = Vector2(cos(a), sin(a)) * pop_speed
	_pickup_timer = pickup_delay
	_on_pickup_ready()


## 子类钩子
func _on_pickup_ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	if _collected:
		return
	_t += delta
	if _pickup_timer > 0.0:
		_pickup_timer = maxf(0.0, _pickup_timer - delta)
	if lifetime > 0.0 and _t >= lifetime:
		_vanish()
		return

	# 弹出减速
	if _velocity.length_squared() > 1.0:
		_velocity = _velocity.move_toward(Vector2.ZERO, 160.0 * delta)
		global_position += _velocity * delta

	# 磁吸
	var p := _find_player()
	if p == null:
		return
	var radius := magnet_radius
	if radius <= 0.0 and GameState and GameState.stats:
		radius = GameState.get_pickup_range()
	var to_p := p.global_position - global_position
	var dist := to_p.length()
	if _pickup_timer <= 0.0 and dist <= radius:
		# 越近吸得越快
		var speed := lerpf(60.0, 260.0, 1.0 - clampf(dist / maxf(1.0, radius), 0.0, 1.0))
		global_position += to_p.normalized() * speed * delta
	if _pickup_timer <= 0.0 and dist <= collect_distance:
		if _collect(p):
			_collected = true


func _find_player() -> Node2D:
	if _player and is_instance_valid(_player) and not bool(_player.get("is_dead")):
		return _player
	var tree := get_tree()
	if tree == null:
		return null
	_player = tree.get_first_node_in_group("player") as Node2D
	return _player


## 子类实现：返回 true 表示成功拾取（掉落物会消失）
func _collect(_player_node: Node2D) -> bool:
	push_warning("[PickupBase] _collect 未实现")
	return true


func _vanish() -> void:
	_collected = true
	queue_free()


func remove_self() -> void:
	_collected = true
	queue_free()


# ---------------------------------------------------------------------------
# 表现
# ---------------------------------------------------------------------------

func _bob(delta: float, base_offset: float = 0.0) -> void:
	if sprite:
		sprite.position.y = base_offset + sin(_t * bob_speed) * bob_amplitude


func add_shadow(scale_x: float = 0.25) -> void:
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = Atlas.prop(Atlas.PROP_SHADOW)
	sh.scale = Vector2(scale_x, scale_x * 0.5)
	sh.position = Vector2(0, 1)
	sh.z_index = -1
	add_child(sh)


func spawn_pickup_text(text: String, color: Color) -> void:
	CombatFx.pickup_text(self, global_position + Vector2(0, -8), text, color)
