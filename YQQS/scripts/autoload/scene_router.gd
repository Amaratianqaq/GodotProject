extends Node
## SceneRouter —— 场景切换与 UI 覆盖层管理（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. **禁止** 在业务代码里直接调用 get_tree().change_scene_to_file()。
##    一切场景切换走 SceneRouter.go_to(scene_id)，以便统一处理淡入淡出、
##    暂停状态、UI 清理与 EventBus 通知。
## 2. UI 面板一律挂到 get_ui_root() 下（CanvasLayer 层 50），
##    业务场景内不要再自建顶层 CanvasLayer（HUD 除外）。
## 3. 本单例 process_mode = ALWAYS，暂停时依然能工作。

const UI_LAYER := 50
const FADE_LAYER := 100

## 全局 UI 面板登记表：panel_id → 场景路径
## 【框架约束】新增面板必须在这里登记，并通过 EventBus.ui_open_requested 打开。
const PANEL_SCENES := {
	&"inventory": "res://scenes/ui/InventoryPanel.tscn",
	&"warehouse": "res://scenes/ui/WarehousePanel.tscn",
	&"skill_tree": "res://scenes/ui/SkillTreePanel.tscn",
	&"pause": "res://scenes/ui/PauseMenu.tscn",
}

## 全屏互斥面板（打开一个会自动关掉其它）
const EXCLUSIVE_PANELS := [&"inventory", &"warehouse", &"skill_tree", &"pause"]

var current_scene_id: String = ""
var is_transitioning: bool = false
var is_paused: bool = false

var _fade_rect: ColorRect = null
var _fade_layer: CanvasLayer = null
var _ui_layer: CanvasLayer = null
var _ui_root: Control = null
## panel_id -> Node
var _open_panels: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_font()
	_build_layers()
	EventBus.ui_open_requested.connect(_on_ui_open_requested)


## 全局字体：用系统字体解决中文显示（Godot 内置字体没有 CJK 字形）。
## 【框架约束】不要在别处再设置字体；所有 UI 走 ThemeDB.fallback_font。
func _setup_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑",
		"SimHei", "黑体", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif",
	])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.allow_system_fallback = true
	ThemeDB.fallback_font = f
	ThemeDB.fallback_font_size = 12


func _on_ui_open_requested(panel_id: StringName) -> void:
	if not PANEL_SCENES.has(panel_id):
		push_warning("[SceneRouter] 未登记的 UI 面板: %s" % panel_id)
		return
	toggle_panel(panel_id, PANEL_SCENES[panel_id])


func _build_layers() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = FADE_LAYER
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	# 【注意】初始必须完全透明：否则任何「不经过 Boot 直接加载场景」的场合
	# （编辑器按 F6 运行单个场景、截图工具、自动化测试）都会被黑幕盖住。
	# 启动时由 Boot._ready() 主动调用 set_fade_black() 再淡入。
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	_ui_layer.layer = UI_LAYER
	add_child(_ui_layer)

	_ui_root = Control.new()
	_ui_root.name = "UIRoot"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func get_ui_root() -> Control:
	return _ui_root


func get_fade_layer() -> CanvasLayer:
	return _fade_layer


# ---------------------------------------------------------------------------
# 场景切换
# ---------------------------------------------------------------------------

func go_to(scene_id: String, fade_time: float = 0.22) -> void:
	if is_transitioning:
		push_warning("[SceneRouter] 正在切换场景，忽略请求: %s" % scene_id)
		return
	if not GameEnums.SCENE_PATHS.has(scene_id):
		push_error("[SceneRouter] 未登记的场景 id: %s" % scene_id)
		return
	var path: String = GameEnums.SCENE_PATHS[scene_id]
	if not ResourceLoader.exists(path):
		push_error("[SceneRouter] 场景文件不存在: %s" % path)
		return
	_transition_to_path(scene_id, path, fade_time)


func go_to_path(scene_id: String, path: String, fade_time: float = 0.22) -> void:
	if is_transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("[SceneRouter] 场景文件不存在: %s" % path)
		return
	_transition_to_path(scene_id, path, fade_time)


func _transition_to_path(scene_id: String, path: String, fade_time: float) -> void:
	is_transitioning = true
	EventBus.scene_change_started.emit(scene_id)
	close_all_panels()
	set_paused(false)

	await _fade(1.0, fade_time)

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneRouter] 切换场景失败(%d): %s" % [err, path])
		is_transitioning = false
		await _fade(0.0, fade_time)
		return

	# 等两帧，确保新场景 _ready 完毕
	await get_tree().process_frame
	await get_tree().process_frame

	current_scene_id = scene_id
	await _fade(0.0, fade_time)
	EventBus.scene_changed.emit(scene_id)
	is_transitioning = false


func reload_current() -> void:
	if current_scene_id != "":
		var id := current_scene_id
		current_scene_id = ""
		go_to(id)


func _fade(target_alpha: float, duration: float) -> void:
	if _fade_rect == null:
		return
	if duration <= 0.0:
		_fade_rect.color.a = target_alpha
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade_rect, "color:a", target_alpha, duration)
	await tween.finished


## 立即把黑幕设为全黑（用于启动时）
func set_fade_black() -> void:
	if _fade_rect:
		_fade_rect.color.a = 1.0


func fade_in(duration: float = 0.35) -> void:
	await _fade(0.0, duration)


# ---------------------------------------------------------------------------
# UI 面板管理
# ---------------------------------------------------------------------------

func open_panel(panel_id: StringName, scene_path: String) -> Node:
	if _open_panels.has(panel_id):
		return _open_panels[panel_id]
	# 全屏面板互斥：打开一个先关掉其它
	if EXCLUSIVE_PANELS.has(panel_id):
		for other in EXCLUSIVE_PANELS:
			if other != panel_id and _open_panels.has(other):
				close_panel(other)
	if not ResourceLoader.exists(scene_path):
		push_warning("[SceneRouter] 面板场景不存在: %s" % scene_path)
		return null
	var ps: PackedScene = load(scene_path)
	var inst := ps.instantiate()
	_ui_root.add_child(inst)
	if inst is Control:
		(inst as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_open_panels[panel_id] = inst
	# 全屏面板打开时暂停游戏（面板挂在 ALWAYS 的 CanvasLayer 下，不受暂停影响）
	if EXCLUSIVE_PANELS.has(panel_id):
		set_paused(true)
	EventBus.ui_panel_opened.emit(panel_id)
	return inst


func register_panel(panel_id: StringName, node: Node) -> void:
	_open_panels[panel_id] = node
	EventBus.ui_panel_opened.emit(panel_id)


func close_panel(panel_id: StringName) -> void:
	if not _open_panels.has(panel_id):
		return
	var n: Node = _open_panels[panel_id]
	_open_panels.erase(panel_id)
	if is_instance_valid(n):
		n.queue_free()
	EventBus.ui_panel_closed.emit(panel_id)
	if _open_panels.is_empty():
		set_paused(false)


func toggle_panel(panel_id: StringName, scene_path: String) -> void:
	if _open_panels.has(panel_id):
		close_panel(panel_id)
	else:
		open_panel(panel_id, scene_path)


func is_panel_open(panel_id: StringName) -> bool:
	return _open_panels.has(panel_id)


func any_panel_open() -> bool:
	return not _open_panels.is_empty()


func close_all_panels() -> void:
	for id in _open_panels.keys():
		var n: Node = _open_panels[id]
		if is_instance_valid(n):
			n.queue_free()
	_open_panels.clear()


# ---------------------------------------------------------------------------
# 暂停
# ---------------------------------------------------------------------------

func set_paused(v: bool) -> void:
	if is_paused == v:
		return
	is_paused = v
	get_tree().paused = v
	EventBus.pause_changed.emit(v)


func toggle_pause() -> void:
	set_paused(not is_paused)
