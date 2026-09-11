class_name ItemData
extends Resource
## 物品静态数据基类。
##
## 【框架约束】
## 1. 所有物品（武器/消耗品/材料/金币/钥匙）都必须定义成 ItemData（或子类）的
##    .tres 资源，放在 res://data/items/ 下，**禁止**在代码里硬编码物品属性。
## 2. `id` 全局唯一，命名用 snake_case，且与文件名一致。
## 3. 图标来源二选一：
##    - 在 Atlas.SHEETS 里登记的图集 → 填 icon_sheet + icon_cell；
##    - 特殊大图（如樱花霰弹枪）→ 覆写 get_icon()。
##    绝不允许在 ItemData 里写 res:// 路径裸引用 PNG。

@export_group("标识")
## 全局唯一 ID（snake_case，与 .tres 文件名一致）
@export var id: StringName = &""
## 显示名（中文）
@export var display_name: String = "未命名物品"
## 物品说明（支持富文本 BBCode）
@export_multiline var description: String = ""

@export_group("表现")
## Atlas.SHEETS 中的图集名；留空表示由子类自己实现 get_icon()
@export var icon_sheet: String = ""
## 图集内的格子坐标
@export var icon_cell: Vector2i = Vector2i.ZERO
## 图标额外缩放（1 = 原始像素尺寸）
@export var icon_scale: float = 1.0

@export_group("分类与价值")
@export var item_type: GameEnums.ItemType = GameEnums.ItemType.MATERIAL
@export var rarity: GameEnums.Rarity = GameEnums.Rarity.COMMON
## 单格最大堆叠数（1 = 不可堆叠）
@export var max_stack: int = 1
## 出售价格（金币）
@export var sell_price: int = 5
## 额外标签，供掉落表 / 技能条件筛选
@export var tags: PackedStringArray = PackedStringArray()


## 取得图标。子类可覆写以支持非图集图标。
func get_icon() -> Texture2D:
	if icon_sheet != "":
		var t := Atlas.frame(icon_sheet, icon_cell.x, icon_cell.y)
		if t:
			return t
	# 兜底：白色占位框，避免 UI 崩
	return _placeholder_icon()


## 是否可堆叠
func is_stackable() -> bool:
	return max_stack > 1


## UI 显示用的品质色名称，如 "普通铁剑"
func qualified_name() -> String:
	return display_name


## 品质色
func get_rarity_color() -> Color:
	return GameEnums.rarity_color(rarity)


## 生成一个运行时堆叠实例
func make_stack(count: int = 1) -> ItemStack:
	var s := ItemStack.new()
	s.data = self
	s.count = count
	return s


static func _placeholder_icon() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color("#ff00ff"))
	var tex := ImageTexture.create_from_image(img)
	return tex


func _to_string() -> String:
	return "ItemData(%s/%s/%s)" % [
		id, display_name, GameEnums.rarity_name(rarity)
	]
