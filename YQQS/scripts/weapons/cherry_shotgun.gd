class_name WeaponCherryShotgun
extends WeaponBase
## 樱花霰弹枪 —— 第一阶段唯一的「完整代码实现」武器。
##
## 原型：《元气骑士》樱花霰弹枪（橙色 · 传奇）。
## 武器定位：森林地图「射手」路线的最终武器，近距离爆发极高。
##
## ============================ 机制设计 ============================
## 1. 五瓣散射：一次扣一次弹、消耗一次能量，扇形射出 5 枚樱花瓣弹丸。
##    花瓣角分布为「中心密、边缘疏」的非等距排布，近距离能几乎全部命中，
##    远距离自然散开 —— 这就是霰弹枪「贴脸最强」的数值来源。
## 2. 花瓣弹射：每枚花瓣可弹墙 1 次，弹射后保留 75% 伤害与 88% 速度，
##    因此拐角、墙角、狭窄走廊里依然能打输出（魂系「花瓣回旋」手感）。
## 3. 后坐力：开火时把持有者向反方向推 55px/s，连续射击会被顶退，
##    逼玩家在「贴身输出」与「保持身位」之间取舍。
## 4. 命中花瓣爆散：每次命中额外炸出 4 片小花瓣粒子（纯表现）。
## 5. 技能树联动：解锁 granted_tags 里的 `cherry_mastery` 后，
##    每发多射 1 枚花瓣（6 发），并且散布收紧 20% —— 体现「全局技能树」
##    对具体武器的影响，也是标签系统的示范用法。
## =================================================================

# ---------------------------------------------------------------------------
# 可调参数（集中在这里，方便第一阶段手感调优；定稿后应下沉到 WeaponData）
# ---------------------------------------------------------------------------

## 基础花瓣数（WeaponData.projectile_count 会覆盖它）
const BASE_PELLETS := 5
## 总散布角（度）
const SPREAD_DEGREES := 34.0
## 获得「樱花精通」标签后的额外花瓣
const MASTERY_EXTRA_PELLETS := 1
## 获得「樱花精通」后的散布收紧比例
const MASTERY_SPREAD_TIGHTEN := 0.20
## 单发后坐力（像素/秒，作用在持有者身上）
const RECOIL_IMPULSE := 55.0
## 后坐力施加的冷却（避免每帧叠加）
const RECOIL_COOLDOWN := 0.12
## 每枚花瓣的击退
const PELLET_KNOCKBACK := 34.0
## 开火屏幕震动
const FIRE_SHAKE := 1.4
## 花瓣命中爆散的粒子数
const PETAL_BURST_COUNT := 4

# ---------------------------------------------------------------------------
# 内部状态
# ---------------------------------------------------------------------------

var _recoil_lock: float = 0.0
var _shot_index: int = 0
var _reload_glow: Sprite2D = null
var _last_shot_crit: bool = false
var _total_shots: int = 0
var _total_pellets: int = 0


func _on_setup_done() -> void:
	# 用 WeaponData 的配置覆盖常量（数据优先）
	if data.projectile_count <= 0:
		data.projectile_count = BASE_PELLETS
	_build_reload_glow()


func _build_reload_glow() -> void:
	if _reload_glow != null:
		return
	_reload_glow = Sprite2D.new()
	_reload_glow.name = "ReloadGlow"
	_reload_glow.texture = _make_glow_texture()
	_reload_glow.modulate = Color(1.0, 0.62, 0.85, 0.0)
	_reload_glow.z_index = 1
	add_child(_reload_glow)


static func _make_glow_texture() -> Texture2D:
	## 程序化生成一张 24x24 的樱花粉光晕，避免依赖额外美术资源
	var s := 24
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(s - 1) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.85
			if a > 0.01:
				img.set_pixel(x, y, Color(1.0, 0.72, 0.90, a))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# 主循环：后坐力冷却 + 换弹光效
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if _recoil_lock > 0.0:
		_recoil_lock = maxf(0.0, _recoil_lock - delta)
	if _reload_glow:
		var target := 0.0
		if is_reloading:
			# 换弹进度 → 光晕强度（0 → 0.75 → 0）
			var t := get_reload_ratio()
			target = sin(t * PI) * 0.75
		_reload_glow.modulate.a = lerpf(_reload_glow.modulate.a, target, 12.0 * delta)
		_reload_glow.scale = Vector2.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.012))


# ---------------------------------------------------------------------------
# 开火
# ---------------------------------------------------------------------------

func _do_fire() -> void:
	if data == null:
		return
	_shot_index += 1
	_total_shots += 1

	var crit := roll_crit()
	_last_shot_crit = crit
	var pellets := _pellet_count()
	var spread := _effective_spread()
	var pdata := _build_petal_data()

	for i in pellets:
		var dir := _petal_direction(i, pellets, spread)
		# 每枚花瓣独立构造 DamageInfo，但暴击结果整发共享
		var info := build_damage(data.damage, crit)
		info.knockback = dir * PELLET_KNOCKBACK
		info.hitstop = 0.03
		info.screen_shake = 0.0
		info.tags.append("shotgun")
		info.tags.append("petal")
		info.with_tag("cherry")
		var p := spawn_projectile(dir, pdata, info)
		if p:
			_total_pellets += 1

	_play_muzzle()
	_apply_recoil()
	_play_fire_sfx()

	EventBus.screen_shake_requested.emit(FIRE_SHAKE, 0.12)
	# 大暴击额外加重表现
	if crit:
		CombatFx.popup(self, muzzle_world_position() + Vector2(0, -10),
			"暴击!", Color("#ffd35c"))


## 花瓣数：基础 + 技能树「樱花精通」加成
func _pellet_count() -> int:
	var n := maxi(1, data.projectile_count)
	if SkillTreeService and SkillTreeService.has_tag("cherry_mastery"):
		n += MASTERY_EXTRA_PELLETS
	return n


## 散布角：受技能树与「瞄准锁定」影响
func _effective_spread() -> float:
	var deg := data.spread_deg
	if deg <= 0.0:
		deg = SPREAD_DEGREES
	if SkillTreeService and SkillTreeService.has_tag("cherry_mastery"):
		deg *= (1.0 - MASTERY_SPREAD_TIGHTEN)
	return deg_to_rad(deg)


## 花瓣方向：中心密、边缘疏 + 轻微随机抖动。
## 具体做法：把 t∈[-1,1] 做 sin 压缩 → 中心两枚几乎重叠，边缘拉开。
func _petal_direction(i: int, count: int, spread_rad: float) -> Vector2:
	if count <= 1:
		return aim_direction
	var t := (float(i) / float(count - 1)) * 2.0 - 1.0     # -1 .. 1
	var shaped := sin(t * PI * 0.5) * 0.82 + t * 0.18      # 中心更密
	var jitter := randf_range(-0.035, 0.035)               # 每发略有差异，避免刻板
	# 故意让每发的整体偏置随 shot_index 左右摆动，形成「扫射感」
	var swing := sin(float(_shot_index) * 1.7) * 0.02
	return aim_direction.rotated(shaped * spread_rad * 0.5 + jitter + swing)


## 花瓣投射物参数：可弹墙一次、粉色调、带拖尾
func _build_petal_data() -> ProjectileData:
	if data.projectile_data:
		return data.projectile_data
	var pd := ProjectileData.new()
	pd.id = &"cherry_petal"
	pd.speed = data.bullet_speed
	pd.lifetime = data.bullet_lifetime
	pd.radius = 3.0
	pd.motion = &"straight"
	pd.max_bounces = 1
	pd.bounce_damping = 0.88
	pd.bounce_damage_keep = 0.75
	pd.pierce = 0
	pd.damage_mult = 1.0
	pd.destroy_on_hit = true
	pd.color = Color("#f28fc9")
	pd.trail_color = Color("#f9c8e4")
	pd.trail_length = 5
	pd.rotate_to_direction = true
	pd.hit_vfx = &"petal"
	pd.sfx_hit = "res://assets/audio/sfx/petal_hit.wav"
	return pd


# ---------------------------------------------------------------------------
# 表现
# ---------------------------------------------------------------------------

func _play_muzzle() -> void:
	var mp := muzzle_world_position()
	CombatFx.muzzle_flash(self, mp, aim_direction, 1.35)
	# 樱花花瓣从枪口炸开
	CombatFx.spawn_sprite_burst(
		self, mp, Atlas.prop(Atlas.PROP_HIT_SPARK),
		PETAL_BURST_COUNT + 2, Color("#f28fc9"), 42.0
	)
	# 枪口后坐抖动
	var tw := create_tween()
	tw.tween_property(self, "rotation", -aim_direction.angle() * 0.06, 0.04)
	tw.tween_property(self, "rotation", 0.0, 0.09)


## 后坐力：把持有者往反方向推
func _apply_recoil() -> void:
	if _recoil_lock > 0.0:
		return
	_recoil_lock = RECOIL_COOLDOWN
	if holder == null or not is_instance_valid(holder):
		return
	if holder.has_method("apply_knockback"):
		holder.apply_knockback(-aim_direction * RECOIL_IMPULSE)
		# 轻微上抛，体现 2.5D 的高度轴
		if holder.get("z_height") != null:
			var zh: float = float(holder.get("z_height"))
			if zh <= 0.0 and holder.has_method("set_z_height"):
				holder.set_z_height(1.5)


# ---------------------------------------------------------------------------
# 换弹
# ---------------------------------------------------------------------------

func _do_reload_start() -> void:
	# 换弹时抖一下，给玩家「在装填」的反馈
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.88, 1.12), 0.10)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16)
	if data.sfx_reload != "":
		AudioManager.play_sfx_2d(data.sfx_reload, global_position)


# ---------------------------------------------------------------------------
# 调试 / 信息
# ---------------------------------------------------------------------------

## 本发开火的实际参数（调试面板 / 数值核对用）
func describe_last_shot() -> String:
	return "花瓣 %d 枚 · 散布 %.1f° · 单枚伤害 %.1f · 理论满命中 %.1f" % [
		_pellet_count(),
		rad_to_deg(_effective_spread()),
		data.damage * damage_multiplier() if data else 0.0,
		(data.damage * damage_multiplier() * float(_pellet_count())) if data else 0.0,
	]


func get_stats_text() -> String:
	return "樱花霰弹枪：已开火 %d 次 / 共射出 %d 枚花瓣" % [_total_shots, _total_pellets]
