class_name RngUtils
extends RefCounted
## 随机工具 —— 全项目唯一允许的随机来源。
##
## 【框架约束】
## 1. **禁止** 使用全局 randf() / randi() / randi_range()。
##    关卡生成、掉落、暴击等一切随机必须走可播种的 RandomNumberGenerator，
##    否则「同种子同地图 / 可复现 bug」无法保证。
## 2. 关卡生成使用 RunManager.map_rng（由 run seed 派生）；
##    战斗随机使用 CombatRng.default（全局，允许不可复现）。
## 3. 按权重抽取统一走 pick_weighted()。

## 权重抽取：weights 与 items 一一对应，返回被抽中的 items 元素
static func pick_weighted(rng: RandomNumberGenerator, items: Array, weights: Array):
	if items.is_empty():
		return null
	if items.size() != weights.size():
		push_error("[RngUtils] items 与 weights 长度不一致")
		return items[0]
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return items[rng.randi_range(0, items.size() - 1)]
	var roll := rng.randf() * total
	var acc := 0.0
	for i in items.size():
		acc += maxf(0.0, float(weights[i]))
		if roll <= acc:
			return items[i]
	return items[items.size() - 1]


## 指数衰减权重抽取：rank 0 的权重为 1.0，之后按 falloff 递减
static func pick_decay(rng: RandomNumberGenerator, items: Array, falloff: float = 0.5):
	var weights: Array = []
	for i in items.size():
		weights.append(pow(falloff, i))
	return pick_weighted(rng, items, weights)


## 伯努利判定
static func chance(rng: RandomNumberGenerator, p: float) -> bool:
	return rng.randf() < clampf(p, 0.0, 1.0)


## 单位圆内随机点
static func inside_unit_circle(rng: RandomNumberGenerator) -> Vector2:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf())
	return Vector2(cos(a), sin(a)) * r


## 环形随机点（min_r..max_r）
static func in_ring(rng: RandomNumberGenerator, min_r: float, max_r: float) -> Vector2:
	return inside_unit_circle(rng).normalized() * rng.randf_range(min_r, max_r)


## 高斯近似（Irwin–Hall，均值 0，范围 -1..1）
static func gaussian(rng: RandomNumberGenerator, n: int = 3) -> float:
	var s := 0.0
	for i in n:
		s += rng.randf()
	return (s / float(n)) * 2.0 - 1.0


## 角度抖动
static func spread_angle(rng: RandomNumberGenerator, base_rad: float, spread_rad: float) -> float:
	return base_rad + rng.randf_range(-spread_rad, spread_rad)


static func pick_one(rng: RandomNumberGenerator, arr: Array):
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


## 原地洗牌（Fisher–Yates）
static func shuffle(rng: RandomNumberGenerator, arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


## 取 arr 中不重复的 n 个元素
static func sample(rng: RandomNumberGenerator, arr: Array, n: int) -> Array:
	var pool := arr.duplicate()
	shuffle(rng, pool)
	return pool.slice(0, mini(n, pool.size()))
