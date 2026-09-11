class_name Actor
extends CharacterBody2D
## 所有可移动战斗实体的基类（玩家 / 敌人）。
##
## 【2.5D 像素表现约定 · 必读】
## 本项目是「2D 俯视 + 伪 2.5D」方案，规则固定如下：
##   1. 逻辑坐标只有 x / y 两轴（无真实 z）。y 越大越靠近镜头。
##   2. 排序：关卡的实体容器开启 y_sort_enabled，节点 position.y 决定遮挡关系。
##   3. 高度：需要「离地」（跳跃 / 翻滚 / 飞行 / 击飞）时，改 `z_height`，
##      精灵会向上偏移，同时脚下影子缩小变淡 —— 这就是 2.5D 的全部魔法。
##   4. 精灵锚点：sprite.position.y = sprite_offset_y - z_height，
##      即精灵底边对齐逻辑原点（脚），所以碰撞体永远在地面平面上。
##   5. 禁止使用 Node2D.z_index 做前后遮挡（会与 y_sort 冲突）；
##      z_index 只允许用于「始终在最上层」的特效与飘字。
##
## 【框架约束】
## 1. 子类必须实现 _ai_update(delta) 或 _player_update(delta) 来设置 `desired_velocity`，
##    本类统一处理移动、击退、闪白、死亡。
## 2. 任何实体受伤必须经过 hurtbox.receive_hit()，禁止直接调 vitals.apply_damage()
##    （除玩家自己的无敌机制外）。

@export_group("阵营与身份")
@export var faction: GameEnums.Faction = GameEnums.Faction.NEUTRAL
## 显示名（用于 UI / 调试）
@export var display_name: String = "Actor"

@export_group("移动")
@export var move_speed: float = 60.0
## 加速度（像素/秒²），越大越"硬"
@export var acceleration: float = 900.0
## 摩擦（无输入时的减速度）
@export var friction: float = 1200.0
## 被击退后的速度衰减
@export var knockback_decay: float = 420.0

@export_group("2.5D 表现")
## 精灵中心相对脚底原点的 y 偏移（32px 精灵取 -15）
@export var sprite_offset_y: float = -15.0
## 影子的 y 偏移
@export var shadow_offset_y: float = -2.0
@export var shadow_scale: float = 0.62
## 受击闪白时长
@export var hurt_flash_time: float = 0.10

@export_group("节点引用（可在场景里指定，留空则自动查找）")
@export var sprite_path: NodePath
@export var shadow_path: NodePath
@export var vitals_path: NodePath
@export var hurtbox_path: NodePath

# --- 运行时 ---
var sprite: Sprite2D = null
var shadow: Sprite2D = null
var vitals: VitalsComponent = null
var hurtbox: HurtboxComponent = null

var facing: Vector2 = Vector2.DOWN
var desired_velocity: Vector2 = Vector2.ZERO
var knockback_velocity: Vector2 = Vector2.ZERO
var z_height: float = 0.0
var is_dead: bool = false

var _flash_timer: float = 0.0
var _flash_material: ShaderMaterial = null
var _facing_locked: bool = false
var _shadow_base_scale: float = 0.62


func is_actor() -> bool:
	return true


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_resolve_nodes()
	_setup_flash_material()
	_on_actor_ready()


## 子类覆写
func _on_actor_ready() -> void:
	pass


func _resolve_nodes() -> void:
	sprite = _pick(sprite_path, "Sprite") as Sprite2D
	shadow = _pick(shadow_path, "Shadow") as Sprite2D
	vitals = _pick(vitals_path, "Vitals") as VitalsComponent
	hurtbox = _pick(hurtbox_path, "Hurtbox") as HurtboxComponent
	if hurtbox == null:
		hurtbox = find_child("Hurtbox", true, false) as HurtboxComponent
	if vitals == null:
		vitals = find_child("Vitals", true, false) as VitalsComponent
	if hurtbox and hurtbox.vitals == null:
		hurtbox.vitals = vitals
		hurtbox.owner_actor = self
	if shadow == null:
		_shadow_base_scale = shadow_scale
	else:
		_shadow_base_scale = shadow.scale.x
	# 影子贴图（如果场景没给）
	if shadow and shadow.texture == null:
		shadow.texture = Atlas.prop(Atlas.PROP_SHADOW)


func _pick(path: NodePath, fallback_name: String) -> Node:
	if path != NodePath():
		var n := get_node_or_null(path)
		if n:
			return n
	return find_child(fallback_name, true, false)


func _setup_flash_material() -> void:
	if sprite == null:
		return
	var sh: Shader = load("res://assets/vfx/sprite_flash.gdshader")
	if sh == null:
		return
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = sh
	_flash_material.set_shader_parameter("flash", 0.0)
	_flash_material.set_shader_parameter("flash_color", Color(1, 1, 1, 1))
	sprite.material = _flash_material


# ---------------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead:
		_physics_process_dead(delta)
		return
	_update_flash(delta)
	var desired := desired_velocity
	if desired.length_squared() > 0.0001:
		velocity = velocity.move_toward(desired, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	# 击退叠加
	if knockback_velocity.length_squared() > 0.01:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()
	_update_visuals()


func _physics_process_dead(delta: float) -> void:
	_update_flash(delta)
	velocity = velocity.move_toward(Vector2.ZERO, friction * 0.5 * delta)
	move_and_slide()


func _update_visuals() -> void:
	if sprite:
		sprite.position.y = sprite_offset_y - z_height
	if shadow:
		var k := clampf(1.0 - z_height / 48.0, 0.25, 1.0)
		shadow.scale = Vector2(_shadow_base_scale * k, _shadow_base_scale * k * 0.5)
		shadow.position.y = shadow_offset_y


func _update_flash(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0 and _flash_material:
			_flash_material.set_shader_parameter("flash", 0.0)


# ---------------------------------------------------------------------------
# 表现接口
# ---------------------------------------------------------------------------

func flash_white(duration: float = -1.0, color: Color = Color(1, 1, 1, 1)) -> void:
	if _flash_material == null:
		return
	var d := hurt_flash_time if duration < 0.0 else duration
	_flash_material.set_shader_parameter("flash_color", color)
	_flash_material.set_shader_parameter("flash", 1.0)
	_flash_timer = d


func set_facing(dir: Vector2) -> void:
	if _facing_locked or dir.length_squared() < 0.0001:
		return
	facing = dir.normalized()
	_update_facing_visual()


func set_facing_locked(v: bool) -> void:
	_facing_locked = v


func _update_facing_visual() -> void:
	if sprite:
		if absf(facing.x) > 0.35:
			sprite.flip_h = facing.x < 0.0


# ---------------------------------------------------------------------------
# 击退
# ---------------------------------------------------------------------------

func apply_knockback(v: Vector2) -> void:
	knockback_velocity += v


func set_z_height(v: float) -> void:
	z_height = v
	_update_visuals()


# ---------------------------------------------------------------------------
# 死亡
# ---------------------------------------------------------------------------

## 子类可覆写做自己的死亡表现（掉落、爆炸等），记得调用 super()
func die() -> void:
	if is_dead:
		return
	is_dead = true
	if hurtbox:
		hurtbox.monitorable = false
	velocity = Vector2.ZERO
	EventBus.actor_died.emit(self)


func get_hurtbox() -> HurtboxComponent:
	return hurtbox


func get_vitals() -> VitalsComponent:
	return vitals


func is_alive() -> bool:
	return not is_dead and vitals != null and not vitals.is_dead()


# ---------------------------------------------------------------------------
# 影子尺寸（按碰撞体半径自动适配）
# ---------------------------------------------------------------------------

func fit_shadow_to_radius(radius: float) -> void:
	if shadow == null:
		return
	var tex_size := 16.0
	var k := (radius * 2.6) / tex_size
	_shadow_base_scale = k
	shadow.scale = Vector2(k, k * 0.5)
