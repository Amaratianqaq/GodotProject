class_name WeaponRanged
extends WeaponBase
## 默认远程武器实现（单发 / 散射 / 蓄力类）。
##
## 【框架约束】
## 第一阶段 12 把品质武器 **没有专属实现**，全部走本默认实现。
## 默认实现的数值完全由 WeaponData 驱动，所以：
##   - 「只有贴图」的武器 = 一个 WeaponData(.tres)，script_path 为空；
##   - 后续要实装专属机制（如元素伤害、连发模式），
##     新建 scripts/weapons/<weapon_id>.gd 并在 .tres 的 script_path 指向它。
## 本文件里所有 `TODO(第二阶段)` 标记即为待实装点。

## 近战/远程通用：近战由 WeaponMelee 处理，这里只管远程


func _do_fire() -> void:
	if data == null:
		return
	# TODO(第二阶段)：弓类蓄力（按住蓄力，松手发射，蓄力影响伤害与速度）
	var crit := roll_crit()
	var count := maxi(1, data.projectile_count)
	var spread := deg_to_rad(data.spread_deg)
	for i in count:
		var dir := _pellet_direction(i, count, spread)
		var info := build_damage(data.damage, crit)
		info.knockback = dir * data.knockback
		info.tags.append("bullet")
		var pdata := _projectile_data()
		spawn_projectile(dir, pdata, info)
	_play_fire_sfx()
	CombatFx.muzzle_flash(self, muzzle_world_position(), aim_direction)


func _pellet_direction(i: int, count: int, spread: float) -> Vector2:
	if count <= 1:
		return aim_direction
	# 均匀分布 + 轻微抖动，保证霰弹扇形好看
	var t := float(i) / float(count - 1) - 0.5
	var a := t * spread + randf_range(-spread * 0.06, spread * 0.06)
	if spread <= 0.0:
		a = randf_range(-0.02, 0.02)
	return aim_direction.rotated(a)


func _projectile_data() -> ProjectileData:
	# 优先用 WeaponData 里指定的投射物数据
	if data.projectile_data:
		return data.projectile_data
	# 否则按 kind 生成一个临时默认数据
	var pd := ProjectileData.new()
	pd.speed = data.bullet_speed
	pd.lifetime = data.bullet_lifetime
	pd.radius = 3.0
	pd.damage_mult = 1.0
	pd.pierce = 0
	pd.max_bounces = 0
	pd.color = _default_color()
	pd.trail_length = 4
	pd.trail_color = pd.color
	pd.rotate_to_direction = true
	match data.kind:
		GameEnums.WeaponKind.BOW:
			pd.radius = 2.5
			pd.pierce = 1
			pd.hit_vfx = &"spark"
		GameEnums.WeaponKind.STAFF:
			pd.radius = 4.0
			pd.glow = true
			pd.hit_vfx = &"spark"
		_:
			pass
	return pd


func _default_color() -> Color:
	match data.kind:
		GameEnums.WeaponKind.BOW: return Color("#c9e88a")
		GameEnums.WeaponKind.STAFF: return Color("#8fd3f2")
		GameEnums.WeaponKind.SHOTGUN: return Color("#ffd35c")
	return Color("#ffd35c")
