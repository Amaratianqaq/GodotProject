class_name WeaponData
extends ItemData
## 武器静态数据。
##
## 【框架约束】
## 1. 第一阶段 12 把武器「只有贴图，无代码实现」——它们的 script_path 留空，
##    由 WeaponRegistry 回退到按 kind 分发的默认实现（weapon_ranged / weapon_melee）。
##    后续要实装某把武器：新建 scripts/weapons/<id>.gd，然后把 script_path 指向它。
## 2. 樱花霰弹枪（cherry_shotgun）script_path = res://scripts/weapons/cherry_shotgun.gd，
##    是第一阶段唯一有完整独立实现的武器。
## 3. 伤害数值统一口径：
##    最终伤害 = damage × 全局伤害倍率 × 品质期望倍率(仅参考) ；暴击在结算层处理。
##    武器本身 **不** 计算暴击，只提供 crit_bonus 加成。

@export_group("武器形态")
@export var kind: GameEnums.WeaponKind = GameEnums.WeaponKind.RANGED
## 双手武器（占用两个主手位，第二阶段启用）
@export var two_handed: bool = false

@export_group("数值")
## 单发/单次挥砍基础伤害
@export var damage: float = 4.0
## 能量消耗（法杖类）
@export var energy_cost: float = 0.0
## 射击间隔（秒/发）
@export var fire_rate: float = 0.30
## 弹匣容量（0 = 无弹匣限制）
@export var magazine: int = 0
## 换弹时间（秒）
@export var reload_time: float = 1.20
## 单次射击弹丸数（霰弹 > 1）
@export var projectile_count: int = 1
## 散布角（总角度，度）
@export var spread_deg: float = 0.0
## 弹丸初速（像素/秒）
@export var bullet_speed: float = 220.0
## 弹丸存活时间（秒）
@export var bullet_lifetime: float = 1.20
## 击退力度
@export var knockback: float = 40.0
## 额外暴击率加成
@export var crit_bonus: float = 0.0

@export_group("近战形态")
## 近战扇形角度（度）
@export var melee_arc_deg: float = 90.0
## 近战攻击距离（像素）
@export var melee_range: float = 22.0
## 挥砍持续时间
@export var melee_swing_time: float = 0.18

@export_group("实现挂载")
## 自定义武器脚本路径；留空 = 使用 WeaponRegistry 的默认实现
@export_file("*.gd") var script_path: String = ""
## 自定义投射物场景；留空 = 使用按 kind 决定的默认投射物
@export_file("*.tscn") var projectile_scene: String = ""
## 自定义投射物数据（可选，覆写默认行为）
@export var projectile_data: ProjectileData = null

@export_group("表现与音效")
@export var sfx_fire: String = "res://assets/audio/sfx/shoot.wav"
@export var sfx_reload: String = "res://assets/audio/sfx/reload.wav"
@export var sfx_empty: String = "res://assets/audio/sfx/empty.wav"
## 开火时的枪口闪光偏移（相对武器原点）
@export var muzzle_offset: Vector2 = Vector2(10, 0)
## 屏幕震动强度
@export var shake_on_fire: float = 0.0
@export_multiline var flavor_text: String = ""


func get_icon() -> Texture2D:
	# 樱花霰弹枪有独立的 48x48 大图
	if String(id) == "cherry_shotgun":
		var big := Atlas.cherry_shotgun_icon()
		if big:
			return big
	return Atlas.weapon_icon(id)


## 是否为远程类武器
func is_ranged() -> bool:
	return kind != GameEnums.WeaponKind.MELEE and kind != GameEnums.WeaponKind.NONE


## 单发理论最大总伤害（霰弹 × 弹丸数）
func total_damage_per_shot() -> float:
	return damage * maxf(1.0, float(projectile_count))


## DPS 估算（不含换弹），用于 UI 对比与掉落权重
func estimated_dps() -> float:
	var shots := total_damage_per_shot()
	var cycle := maxf(0.02, fire_rate)
	if magazine > 0 and is_ranged():
		var burst := magazine * cycle
		var total_time := burst + reload_time
		return (shots * magazine) / maxf(0.01, total_time)
	return shots / cycle


func _to_string() -> String:
	return "WeaponData(%s/%s/%s dmg=%.1f dps=%.1f)" % [
		id, display_name, GameEnums.rarity_name(rarity), damage, estimated_dps()
	]
