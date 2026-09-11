class_name CoinPickup
extends PickupBase
## 金币掉落物。4 帧旋转动画来自 props 图集的第 1 行。

## 金币面额
@export var amount: int = 1

## 大额金币用更大贴图
const BIG_THRESHOLD := 10

var _frames: Array[AtlasTexture] = []
var _frame_index: int = 0
var _frame_timer: float = 0.0


func _on_pickup_ready() -> void:
	_frames = [
		Atlas.prop(Atlas.PROP_COIN_1),
		Atlas.prop(Atlas.PROP_COIN_2),
		Atlas.prop(Atlas.PROP_COIN_3),
		Atlas.prop(Atlas.PROP_COIN_4),
	]
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	if sprite.texture == null:
		sprite.texture = _frames[0]
	add_shadow(0.22)
	if amount >= BIG_THRESHOLD:
		sprite.scale = Vector2(1.3, 1.3)
	# 大额金币颜色偏金
	if amount >= 50:
		sprite.modulate = Color("#ffd35c")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_frame_timer += delta
	if _frame_timer >= 0.12:
		_frame_timer = 0.0
		_frame_index = (_frame_index + 1) % _frames.size()
		if sprite:
			sprite.texture = _frames[_frame_index]
	_bob(delta, -1.0)


func _collect(player: Node2D) -> bool:
	if amount <= 0:
		return true
	GameState.add_gold(amount)
	EventBus.coin_picked_up.emit(amount, global_position)
	AudioManager.play_sfx("res://assets/audio/sfx/coin.wav", 0.15)
	var col := Color("#ffd35c") if amount < BIG_THRESHOLD else Color("#f2a13b")
	spawn_pickup_text("+%d" % amount, col)
	queue_free()
	return true
