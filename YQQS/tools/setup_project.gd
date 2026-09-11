extends SceneTree
## 工程初始化脚本（一次性）。
## 用代码方式写入 ProjectSettings，避免手写 project.godot 里那些易错的
## Object(InputEventKey, ...) 序列化字面量。
##
## 运行：
##   & "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" `
##       --headless --path E:\GodotProject --script res://tools/setup_project.gd
##
## 幂等：重复运行只会覆盖同样的值。

const KEY_ACTIONS := {
	# 动作名: [ [物理键码, ...], [鼠标键码, ...] ]
	"move_up":    [[87, 4194320], []],        # W / ↑
	"move_down":  [[83, 4194322], []],        # S / ↓
	"move_left":  [[65, 4194319], []],        # A / ←
	"move_right": [[68, 4194321], []],        # D / →
	"fire":       [[], [1]],                  # 鼠标左键
	"aim_lock":   [[4194325], []],            # Shift 锁定朝向
	"roll":       [[32], []],                 # 空格 翻滚
	"interact":   [[69], []],                 # E 交互
	"inventory":  [[4194306], []],            # Tab 背包
	"warehouse":  [[73], []],                 # I 仓库
	"skill_tree": [[75], []],                 # K 技能树
	"use_potion": [[81], []],                 # Q 快捷回血
	"drop_item":  [[70], []],                 # F 丢弃
	"slot_1":     [[49], []],                 # 1 武器槽 1
	"slot_2":     [[50], []],                 # 2 武器槽 2
	"reload":     [[82], []],                 # R 换弹
	"pause":      [[4194305], []],            # Esc
	"ui_confirm": [[4194309, 32], []],        # Enter / Space
	"debug_toggle": [[4194332], []],          # F3
}

const AUTOLOADS := {
	"EventBus":         "res://scripts/autoload/event_bus.gd",
	"ConfigDB":         "res://scripts/autoload/config_db.gd",
	"SaveSystem":       "res://scripts/autoload/save_system.gd",
	"GameState":        "res://scripts/autoload/game_state.gd",
	"SceneRouter":      "res://scripts/autoload/scene_router.gd",
	"AudioManager":     "res://scripts/autoload/audio_manager.gd",
	"SkillTreeService": "res://scripts/autoload/skill_tree_service.gd",
	"WarehouseService": "res://scripts/autoload/warehouse_service.gd",
	"LootService":      "res://scripts/autoload/loot_service.gd",
	"RunManager":       "res://scripts/autoload/run_manager.gd",
}

const PHYS_LAYERS := {
	"1": "world",
	"2": "obstacle",
	"3": "player",
	"4": "enemy",
	"5": "player_hitbox",
	"6": "enemy_hitbox",
	"7": "player_hurtbox",
	"8": "enemy_hurtbox",
	"9": "pickup",
	"10": "interactable",
	"11": "projectile",
	"12": "trigger",
}


func _init() -> void:
	print("[setup_project] 开始写入工程配置 ...")
	_write_input_map()
	_write_autoloads()
	_write_layer_names()
	_write_display_and_rendering()
	_write_misc()
	var err := ProjectSettings.save()
	if err != OK:
		push_error("[setup_project] ProjectSettings.save() 失败: %s" % err)
		quit(1)
		return
	print("[setup_project] 完成。project.godot 已更新。")
	quit(0)


func _write_input_map() -> void:
	for action_name in KEY_ACTIONS.keys():
		var spec: Array = KEY_ACTIONS[action_name]
		var events: Array = []
		for kc in spec[0]:
			var ev := InputEventKey.new()
			ev.physical_keycode = kc
			events.append(ev)
		for mb in spec[1]:
			var me := InputEventMouseButton.new()
			me.button_index = mb
			events.append(me)
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": 0.2,
			"events": events,
		})
	print("  · 输入映射 %d 个动作" % KEY_ACTIONS.size())


func _write_autoloads() -> void:
	for name in AUTOLOADS.keys():
		ProjectSettings.set_setting("autoload/" + name, "*" + AUTOLOADS[name])
	print("  · 自动加载 %d 个单例" % AUTOLOADS.size())


func _write_layer_names() -> void:
	for idx in PHYS_LAYERS.keys():
		ProjectSettings.set_setting(
			"layer_names/2d_physics/layer_%s" % idx, PHYS_LAYERS[idx]
		)
		# 2D 渲染层（y-sort 之外，用于灯具/遮罩等）
	ProjectSettings.set_setting("layer_names/2d_render/layer_1", "default")
	ProjectSettings.set_setting("layer_names/2d_render/layer_2", "glow")
	print("  · 物理层名 %d 层" % PHYS_LAYERS.size())


func _write_display_and_rendering() -> void:
	# 像素风：480x270 逻辑分辨率，整数倍放大到 1440x810。
	# 【为什么用 canvas_items 而不是 viewport】
	# viewport 模式会把 UI 文字也按 480x270 渲染再放大，中文会糊成一团；
	# canvas_items 模式下精灵仍按最近邻整数放大（像素完美），
	# 而字体在放大后的分辨率上渲染（文字清晰），是本项目的最优解。
	ProjectSettings.set_setting("display/window/size/viewport_width", 480)
	ProjectSettings.set_setting("display/window/size/viewport_height", 270)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1440)
	ProjectSettings.set_setting("display/window/size/window_height_override", 810)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "keep")
	ProjectSettings.set_setting("display/window/stretch/scale_mode", "integer")
	ProjectSettings.set_setting("display/window/vsync/vsync_mode", 1)
	# 物理
	ProjectSettings.set_setting("physics/2d/default_gravity", 0.0)
	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", 60)
	print("  · 显示/渲染/物理 已配置")


func _write_misc() -> void:
	ProjectSettings.set_setting("application/run/max_fps", 0)
	ProjectSettings.set_setting("application/config/name", "SoulForest")
	ProjectSettings.set_setting("application/config/version", "0.1.0")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/boot/Boot.tscn")
	# 鼠标
	ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", false)
	print("  · 应用元信息 已配置")
