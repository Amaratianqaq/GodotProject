class_name ProjectileData
extends Resource
## 投射物静态参数。武器的 projectile_data 字段可覆写默认行为。

@export var id: StringName = &"bullet"
@export_group("运动")
## 速度（像素/秒）。<=0 表示由生成者传入
@export var speed: float = 220.0
## 存活时间（秒）
@export var lifetime: float = 1.2
## 运动模式：straight / bounce / homing / wave / arc
@export var motion: StringName = &"straight"
## 碰撞半径
@export var radius: float = 3.0
## 最大弹射次数（motion=bounce）
@export var max_bounces: int = 0
## 弹射后速度保留比例
@export var bounce_damping: float = 1.0
## 弹射后伤害保留比例
@export var bounce_damage_keep: float = 1.0
## 追踪转向速度（弧度/秒，motion=homing）
@export var homing_turn_speed: float = 3.0
## 追踪持续时间（秒）
@export var homing_duration: float = 1.5
## 波动的振幅与频率（motion=wave）
@export var wave_amplitude: float = 6.0
@export var wave_frequency: float = 8.0
## 加速度（像素/秒²，负值为减速）
@export var acceleration: float = 0.0

@export_group("穿透与伤害")
## 可穿透的敌人数量（0 = 命中即消失）
@export var pierce: int = 0
## 命中后伤害保留比例
@export var pierce_damage_keep: float = 1.0
## 伤害倍率（× 武器基础伤害）
@export var damage_mult: float = 1.0
## 击退倍率
@export var knockback_mult: float = 1.0
## 命中目标后是否继续（false = 命中即销毁）
@export var destroy_on_hit: bool = true

@export_group("表现")
## Atlas 图集名（留空 = 用代码画圆形光点）
@export var sheet: String = ""
@export var cell: Vector2i = Vector2i.ZERO
## 代码绘制时的颜色
@export var color: Color = Color("#ffd35c")
## 拖尾长度（0 = 无拖尾）
@export var trail_length: int = 6
@export var trail_color: Color = Color("#f28fc9")
## 是否自发光（渲染层 2）
@export var glow: bool = false
## 命中特效：spark / petal / none
@export var hit_vfx: StringName = &"spark"
## 旋转跟随方向
@export var rotate_to_direction: bool = true

@export_group("音效")
@export var sfx_hit: String = ""
@export var sfx_spawn: String = ""


func duplicate_data() -> ProjectileData:
	return duplicate() as ProjectileData
