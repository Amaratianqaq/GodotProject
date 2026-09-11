extends SceneTree
# =============================================================================
#  verify_all_assets.gd —— **全套 35 个参考素材**的统一验收
# -----------------------------------------------------------------------------
#  运行：
#    & <godot> --headless --path <proj> --script res://tools/refart/verify_all_assets.gd
#
#  检查项（逐文件）：
#    ① 文件存在
#    ② 画布尺寸与 docs/10 契约**逐像素一致**
#    ③ 不是空图（至少有 1% 的像素非透明；格子图集另行按格检查）
#    ④ 配色全部落在 RefArt 的 32 色调色板内
#    ⑤ 不含半透明像素（像素画必须是 0 或 255 —— 半透明说明被抗锯齿糊过）
#
#  【为什么单独做这一份】前面的 verify_chars / verify_props / verify_dualgrid
#  各自只覆盖自己那批。真正要回答"35 个文件到底齐没齐、合不合格"，
#  需要一个按契约表逐条比对的**单一权威清单** —— 否则很容易漏掉某个文件，
#  而且改了契约之后没人会发现有文件过期。
# =============================================================================

const OUT_DIR := "res://assets/sprites"

## 契约表：文件名 → 期望尺寸（docs/10 §3）
const CONTRACT := {
	# 3.1 角色与敌人
	"player_ranger.png": [128, 128],
	"enemy_slime.png": [128, 128],
	"enemy_bat.png": [128, 128],
	"enemy_mushroom.png": [128, 128],
	"enemy_goblin.png": [128, 128],
	"enemy_goblin_archer.png": [128, 128],
	"enemy_goblin_guard.png": [128, 128],
	"boss_goblin_priest.png": [256, 256],
	# 3.2 地面与地形
	"tileset_forest_ground.png": [256, 256],
	"tileset_forest_wall.png": [128, 128],
	# 3.3 场景道具
	"prop_tree_pine.png": [32, 48],
	"prop_tree_dead.png": [32, 48],
	"prop_tree_broad.png": [48, 64],
	"prop_rock_small.png": [16, 16],
	"prop_rock_big.png": [32, 32],
	"prop_stump.png": [16, 16],
	"prop_bush.png": [16, 16],
	"prop_flower_a.png": [16, 16],
	"prop_flower_b.png": [16, 16],
	"prop_mushroom.png": [16, 16],
	"prop_tall_grass.png": [16, 16],
	"prop_pebble.png": [16, 16],
	"prop_fallen_log.png": [32, 16],
	"props.png": [256, 128],
	# 3.4 武器与 UI
	"weapons.png": [72, 96],
	"weapon_cherry_shotgun.png": [48, 48],
	"ui_panel.png": [64, 64],
	"ui_bar.png": [64, 32],
	"ui_bar_armor.png": [64, 16],
	"ui_frame_rarity.png": [64, 16],
	# 3.5 VFX
	"vfx_hit_spark.png": [96, 16],
	"vfx_muzzle_flash.png": [96, 16],
	"vfx_petal.png": [64, 16],
	"vfx_orb.png": [64, 16],
	"vfx_arrow.png": [48, 16],
}

var _errors: Array[String] = []
var _ok: int = 0
var _missing: Array[String] = []


func _init() -> void:
	print("=== 全套参考素材验收（契约 %d 个文件）===" % CONTRACT.size())
	print("")
	for f in CONTRACT.keys():
		_check(String(f), CONTRACT[f])
	print("")
	print("=== 结果 ===")
	if not _missing.is_empty():
		print("缺失 %d 个：" % _missing.size())
		for m in _missing:
			print("   - ", m)
	print("合格 %d / %d" % [_ok, CONTRACT.size()])
	if _errors.is_empty() and _missing.is_empty():
		print("⇒ 全套 35 个素材全部符合契约 ✅")
		quit(0)
	else:
		for e in _errors:
			print("[ERROR] ", e)
		quit(1)


func _check(f: String, size: Array) -> void:
	var path: String = OUT_DIR + "/" + f
	if not ResourceLoader.exists(path):
		_missing.append(f)
		return
	var img: Image = load(path).get_image()
	if img == null:
		_errors.append("%s 无法读取图像数据" % f)
		return
	var ww: int = size[0]
	var hh: int = size[1]
	if img.get_width() != ww or img.get_height() != hh:
		_errors.append("%s 尺寸 %dx%d，契约要求 %dx%d" % [
			f, img.get_width(), img.get_height(), ww, hh])
		return

	var filled := 0
	var semi := 0
	var off_palette := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.001:
				continue
			if c.a < 0.999:
				semi += 1
			filled += 1
			var h := c.to_html(false)
			if not RefArt.PAL.values().has("#" + h):
				off_palette[h] = true

	var ratio := float(filled) / float(ww * hh)
	if ratio < 0.01:
		_errors.append("%s 只有 %.2f%% 的像素非透明，几乎是空图" % [f, ratio * 100.0])
	if semi > 0:
		_errors.append("%s 含 %d 个半透明像素（像素画必须 0/255，半透明说明被抗锯齿糊过）" % [
			f, semi])
	if not off_palette.is_empty():
		var ks: Array = off_palette.keys()
		ks.sort()
		_errors.append("%s 用了调色板外的颜色 %d 种：%s" % [
			f, ks.size(), str(ks.slice(0, mini(6, ks.size())))])

	# 到这一步都没问题才算合格
	var bad := false
	for e in _errors:
		if e.begins_with(f + " "):
			bad = true
			break
	if not bad:
		_ok += 1
		print("  OK  %-30s %3dx%-3d  实心 %5.1f%%" % [f, ww, hh, ratio * 100.0])
