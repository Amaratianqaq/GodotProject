extends Node
## 截图工具 —— 用真实渲染器跑一遍关卡/大厅并保存 PNG，供人工肉眼验收。
##
## 用法（**不要加 --headless**，headless 没有渲染设备拿不到帧）：
##   & godot --path E:\GodotProject res://tools/Screenshot.tscn
##   # 可选：指定场景与输出
##   & godot --path E:\GodotProject res://tools/Screenshot.tscn -- --scene=lobby --out=E:\shots\lobby.png
##
## 输出默认写到 user://（Windows 下即 %APPDATA%\Godot\app_userdata\SoulForest\），
## 并在控制台打印绝对路径。

const FOREST_SCENE := "res://scenes/levels/forest/ForestLevel.tscn"
const LOBBY_SCENE := "res://scenes/lobby/Lobby.tscn"

var _scene := "forest"
var _out := ""
var _frames := 90
var _panel := ""


func _ready() -> void:
	_parse_args()
	var path := LOBBY_SCENE if _scene == "lobby" else FOREST_SCENE
	if _scene == "forest" and RunManager:
		RunManager.start_run(20240601, 0)
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("[Screenshot] 无法加载场景: %s" % path)
		get_tree().quit(1)
		return
	add_child(ps.instantiate())
	# 等若干帧让地图生成、精灵就绪、字幕淡出
	for i in _frames:
		await get_tree().process_frame
	if _panel != "":
		# 打开一个 UI 面板再截图（用于验收背包 / 仓库 / 技能树界面）
		SceneRouter.open_panel(StringName(_panel),
			SceneRouter.PANEL_SCENES.get(StringName(_panel), ""))
		for i in 20:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture()
	get_tree().quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene = a.substr("--scene=".length())
		elif a.begins_with("--out="):
			_out = a.substr("--out=".length())
		elif a.begins_with("--panel="):
			_panel = a.substr("--panel=".length())
		elif a.begins_with("--frames="):
			_frames = maxi(10, int(a.substr("--frames=".length())))


func _capture() -> void:
	var vp := get_viewport()
	if vp == null:
		push_error("[Screenshot] 没有 viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		push_error("[Screenshot] 拿不到帧缓冲（是否用了 --headless？）")
		return
	var img := tex.get_image()
	if img == null:
		push_error("[Screenshot] 拿不到图像")
		return
	var out := _out
	if out == "":
		out = "user://shot_%s_%d.png" % [_scene, Time.get_unix_time_from_system()]
	var err := img.save_png(out)
	if err != OK:
		push_error("[Screenshot] 保存失败(%d): %s" % [err, out])
		return
	print("[Screenshot] 已保存: %s" % ProjectSettings.globalize_path(out))
	_print_stats(img)


## 因为 AI 无法看图，这里打印像素统计作为「画面不是纯黑/纯色」的客观证据。
func _print_stats(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var colors: Dictionary = {}
	var sum := 0.0
	var non_black := 0
	var step := maxi(1, w / 240)
	var samples := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			sum += lum
			if lum > 0.06:
				non_black += 1
			colors[c.to_rgba32()] = true
			samples += 1
	print("[Screenshot] 统计: %dx%d · 采样 %d 点 · 不同颜色 %d · 平均亮度 %.3f · 非黑像素占比 %.1f%%" % [
		w, h, samples, colors.size(), sum / maxf(1.0, float(samples)),
		100.0 * float(non_black) / maxf(1.0, float(samples))
	])
