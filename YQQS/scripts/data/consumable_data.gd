class_name ConsumableData
extends ItemData
## 消耗品数据（药水 / 卷轴 / 食物）。
##
## 【框架约束】
## 第一阶段只支持「立即生效」类消耗品（回血 / 回蓝 / 回甲），
## 使用入口统一为 Player.use_consumable(index)。
## 后续要加 Buff 类消耗品 → 在这里加 effect_id，并在 Player 里分发，
## 不要为每个药水单独写脚本。

@export_group("使用效果")
## 回复生命
@export var heal_amount: float = 0.0
## 回复能量
@export var mp_amount: float = 0.0
## 回复护甲
@export var armor_amount: float = 0.0
## 使用后是否立即丢弃（消耗品为 true）
@export var consume_on_use: bool = true
## 使用动画时长（秒）
@export var use_time: float = 0.25
## 使用音效
@export var sfx_use: String = "res://assets/audio/sfx/drink.wav"
## 特效颜色
@export var fx_color: Color = Color("#d94a4a")


func has_effect() -> bool:
	return heal_amount > 0.0 or mp_amount > 0.0 or armor_amount > 0.0


func describe_effect() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if heal_amount > 0.0:
		parts.append("回复 %d 生命" % int(heal_amount))
	if mp_amount > 0.0:
		parts.append("回复 %d 能量" % int(mp_amount))
	if armor_amount > 0.0:
		parts.append("回复 %d 护甲" % int(armor_amount))
	return " / ".join(parts)


func _init() -> void:
	item_type = GameEnums.ItemType.CONSUMABLE
	max_stack = 9
