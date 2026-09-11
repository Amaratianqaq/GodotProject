class_name Lobby
extends Node2D
## 玩家初始大厅 —— 角色选择 + 进入森林 + 仓库 / 技能树入口。
##
## 【框架约束 · 必读】
## 1. 大厅也使用 Player 场景（可以走动、翻滚），但不刷怪、不掉落。
## 2. 大厅必须在 _ready 里注册 entity_root / fx_root / projectile_root / pickup_root
##    四个 group，否则全局系统找不到挂载点。
## 3. 大厅是「功能聚合点」：后续新增系统（商店、铁匠、图鉴、天赋重置）
##    一律以「加一个 PanelAltar + 登记一个 UI 面板」的方式接入，
##    不要往本文件堆业务逻辑。
## 4. 进入关卡必须走 `_enter_forest()`：它会调用 RunManager.start_run()
##    生成新种子，再切场景。

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const PORTAL_SCENE := "res://scenes/world/Portal.tscn"

## 大厅地面尺寸（图块）
const FLOOR_W := 30
const FLOOR_H := 18

var entity_root: Node2D
var fx_root: Node2D
var projectile_root: Node2D
var pickup_root: Node2D
var player: Player = null

var _char_list: VBoxContainer
var _char_detail: RichTextLabel
var _top_info: RichTextLabel
var _selected_id: StringName = &"ranger"


func _ready() -> void:
	if RunManager:
		RunManager.unregister_level()
		if RunManager.run_active:
			RunManager.end_run(false)
	GameState.end_run()
	_build_world()
	_spawn_player()
	_build_ui()
	AudioManager.play_bgm("res://assets/audio/bgm/lobby.ogg")
	print("[Lobby] 大厅就绪")


# ---------------------------------------------------------------------------
# 世界
# ---------------------------------------------------------------------------

func _build_world() -> void:
	var bg := Polygon2D.new()
	bg.name = "Background"
	bg.color = Color("#0d0b1f")
	bg.z_index = -100
	bg.z_as_relative = false
	add_child(bg)
	var ts := float(Atlas.TILE_SIZE)
	bg.polygon = PackedVector2Array([
		Vector2(-4, -6) * ts, Vector2(FLOOR_W + 4, -6) * ts,
		Vector2(FLOOR_W + 4, FLOOR_H + 6) * ts, Vector2(-4, FLOOR_H + 6) * ts,
	])

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = ForestTileset.get_tileset()
	ground.z_index = -50
	ground.z_as_relative = false
	add_child(ground)
	_paint_floor(ground)

	entity_root = Node2D.new()
	entity_root.name = "EntityRoot"
	entity_root.y_sort_enabled = true
	add_child(entity_root)
	NodeUtils.ensure_group(entity_root, &"entity_root")

	pickup_root = Node2D.new()
	pickup_root.name = "Pickups"
	entity_root.add_child(pickup_root)
	NodeUtils.ensure_group(pickup_root, &"pickup_root")

	projectile_root = Node2D.new()
	projectile_root.name = "Projectiles"
	entity_root.add_child(projectile_root)
	NodeUtils.ensure_group(projectile_root, &"projectile_root")

	fx_root = Node2D.new()
	fx_root.name = "FxRoot"
	fx_root.z_index = 20
	fx_root.z_as_relative = false
	add_child(fx_root)
	NodeUtils.ensure_group(fx_root, &"fx_root")

	_build_decorations()


func _paint_floor(ground: TileMapLayer) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240601
	for y in range(-2, FLOOR_H + 2):
		for x in range(-2, FLOOR_W + 2):
			var inside := x >= 0 and y >= 0 and x < FLOOR_W and y < FLOOR_H
			var tile := Atlas.Tile.BLACK
			if inside:
				# 中央用石砖，边缘用木地板，做出「集会所」的感觉
				var is_border := x < 2 or y < 2 or x >= FLOOR_W - 2 or y >= FLOOR_H - 2
				tile = Atlas.Tile.WOOD_FLOOR if is_border else Atlas.Tile.BRICK
				if rng.randf() < 0.06:
					tile = Atlas.Tile.WOOD_FLOOR_H if is_border else Atlas.Tile.BRICK_BROKEN
			ground.set_cell(Vector2i(x, y), ForestTileset.SOURCE_ID,
				ForestTileset.tile_coords(tile))


func _build_decorations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	entity_root.add_child(props)
	# 四角放一些树木与木桶做点缀
	var spots := [
		Vector2i(1, 1), Vector2i(FLOOR_W - 2, 1),
		Vector2i(1, FLOOR_H - 2), Vector2i(FLOOR_W - 2, FLOOR_H - 2),
		Vector2i(4, 1), Vector2i(FLOOR_W - 5, 1),
		Vector2i(1, 6), Vector2i(FLOOR_W - 2, 6),
		Vector2i(1, 11), Vector2i(FLOOR_W - 2, 11),
	]
	for s in spots:
		var tile := Atlas.Tile.PINE if rng.randf() < 0.5 else Atlas.Tile.BUSH
		var holder := Node2D.new()
		holder.position = Vector2(s) * float(Atlas.TILE_SIZE) + Vector2(8, 8)
		holder.y_sort_enabled = true
		props.add_child(holder)
		var sp := Sprite2D.new()
		var coords := ForestTileset.tile_coords(tile)
		sp.texture = Atlas.frame("tileset_forest", coords.x, coords.y)
		sp.scale = Vector2(1.4 if tile == Atlas.Tile.PINE else 1.0,
			1.4 if tile == Atlas.Tile.PINE else 1.0)
		sp.position = Vector2(0, -8.0 * sp.scale.y)
		holder.add_child(sp)
		# 大厅里不加碰撞，避免把玩家卡住


func _spawn_player() -> void:
	var scene: PackedScene = load(PLAYER_SCENE)
	if scene == null:
		return
	var inst := scene.instantiate()
	entity_root.add_child(inst)
	player = inst as Player
	player.global_position = Vector2(FLOOR_W * 0.5, FLOOR_H * 0.62) * float(Atlas.TILE_SIZE)
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.limit_left = int(-3.0 * Atlas.TILE_SIZE)
		cam.limit_top = int(-3.0 * Atlas.TILE_SIZE)
		cam.limit_right = int(float(FLOOR_W + 3) * Atlas.TILE_SIZE)
		cam.limit_bottom = int(float(FLOOR_H + 3) * Atlas.TILE_SIZE)
		cam.make_current()
	_add_facilities()


## 大厅设施：全部走 PanelAltar / Portal，不在这里写业务逻辑
func _add_facilities() -> void:
	var ts := float(Atlas.TILE_SIZE)

	# 1) 森林传送门（正上方）
	var portal := _make_portal(Portal.Kind.ENTER_FOREST,
		Vector2(FLOOR_W * 0.5, 2.2) * ts)
	if portal:
		portal.set_prompt_text("进入宁静森林")
		portal.activated.connect(_on_enter_forest_portal)

	# 2) 仓库（左下）
	var wh := _make_altar(&"warehouse", Atlas.UI_ICONS["warehouse"],
		Vector2(4.0, FLOOR_H - 4.0) * ts, Color("#a3713f"))
	wh.set_prompt_text("仓库")

	# 3) 技能树祭坛（右下）
	var st := _make_altar(&"skill_tree", Atlas.UI_ICONS["skilltree"],
		Vector2(FLOOR_W - 5.0, FLOOR_H - 4.0) * ts, Color("#b44ac9"))
	st.set_prompt_text("全局技能树")

	# 4) 角色选择（左上，同时也是 UI 面板的入口提示）
	var cs := _make_altar(&"character", Atlas.UI_ICONS["bag"],
		Vector2(4.0, 4.0) * ts, Color("#5c8f3a"))
	cs.set_prompt_text("角色选择")
	cs.activated.connect(func(_p: Node2D) -> void:
		EventBus.toast.emit("使用左侧面板选择角色", UIKit.COL_OK))


func _make_portal(kind: int, pos: Vector2) -> Portal:
	var scene: PackedScene = load(PORTAL_SCENE)
	if scene == null:
		return null
	var p := scene.instantiate() as Portal
	entity_root.add_child(p)
	p.global_position = pos
	p.set_kind(kind)
	return p


func _make_altar(panel_id: StringName, cell: Vector2i, pos: Vector2, color: Color) -> PanelAltar:
	var a := PanelAltar.new()
	a.panel_id = panel_id
	a.icon_prop = cell
	a.accent = color
	entity_root.add_child(a)
	a.global_position = pos
	return a


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LobbyUI"
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_character_panel(root)
	_build_top_info(root)


func _build_character_panel(parent: Control) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.wood_stylebox())
	box.position = Vector2(6, 6)
	box.size = Vector2(150, 210)
	box.custom_minimum_size = Vector2(150, 210)
	parent.add_child(box)

	var v := UIKit.vbox(4)
	box.add_child(v)
	v.add_child(UIKit.label("选择角色", UIKit.FS_NORMAL, UIKit.COL_GOLD,
		HORIZONTAL_ALIGNMENT_CENTER))

	_char_list = UIKit.vbox(3)
	v.add_child(_char_list)
	_rebuild_character_list()

	var sep := HSeparator.new()
	v.add_child(sep)

	_char_detail = UIKit.rich_label("", UIKit.FS_TINY)
	_char_detail.custom_minimum_size = Vector2(136, 96)
	v.add_child(_char_detail)

	var b_enter := UIKit.button("进入森林", UIKit.FS_NORMAL)
	b_enter.pressed.connect(_enter_forest)
	v.add_child(b_enter)

	var b_pause := UIKit.button("菜单 (Esc)", UIKit.FS_TINY)
	b_pause.pressed.connect(_open_pause_menu)
	v.add_child(b_pause)


func _open_pause_menu() -> void:
	if SceneRouter.is_panel_open(&"pause"):
		return
	SceneRouter.open_panel(&"pause", SceneRouter.PANEL_SCENES[&"pause"])


func _rebuild_character_list() -> void:
	for c in _char_list.get_children():
		c.queue_free()
	var chars := ConfigDB.all_characters()
	if chars.is_empty():
		_char_list.add_child(UIKit.label("（没有角色数据）", UIKit.FS_TINY, UIKit.COL_DANGER))
		return
	for cd in chars:
		var unlocked := GameState.is_character_unlocked(cd.id)
		var b := UIKit.button(
			"%s  Lv.%d%s" % [cd.display_name, GameState.player_level, "" if unlocked else " 🔒"],
			UIKit.FS_SMALL
		)
		b.custom_minimum_size = Vector2(132, 22)
		if not unlocked:
			b.disabled = true
			b.tooltip_text = cd.unlock_hint
		b.pressed.connect(_on_character_pressed.bind(cd.id))
		if cd.id == GameState.character_id:
			b.add_theme_color_override("font_color", UIKit.COL_GOLD)
		_char_list.add_child(b)
	if _selected_id == &"":
		_selected_id = GameState.character_id
	_show_character_detail(_selected_id)


func _build_top_info(root: Control) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.panel_stylebox(
		Color(0.08, 0.07, 0.14, 0.9), UIKit.COL_BORDER, 2))
	box.position = Vector2(480 - 6 - 210, 6)
	box.size = Vector2(210, 56)
	box.custom_minimum_size = Vector2(210, 56)
	root.add_child(box)
	_top_info = UIKit.rich_label("", UIKit.FS_TINY)
	_top_info.custom_minimum_size = Vector2(198, 50)
	box.add_child(_top_info)
	_refresh_top_info()
	EventBus.gold_changed.connect(func(_g: int) -> void: _refresh_top_info())
	EventBus.skill_points_changed.connect(func(_p: int) -> void: _refresh_top_info())
	EventBus.player_level_changed.connect(
		func(_l: int, _x: int, _n: int) -> void: _refresh_top_info())


func _refresh_top_info() -> void:
	if _top_info == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Soul Forest[/b] · 第一阶段：宁静森林")
	lines.append("金币 [color=#ffd35c]%d[/color]    技能点 [color=#8fc75a]%d[/color]" % [
		GameState.gold, SkillTreeService.points
	])
	lines.append("击杀 %d    最高层 %d    存档槽 %d" % [
		GameState.total_kills, GameState.best_floor + 1, SaveSystem.current_slot
	])
	lines.append("[color=#9a94a8]WASD 移动 · 鼠标瞄准 · 左键攻击 · 空格翻滚 · Q 喝药[/color]")
	_top_info.text = "\n".join(lines)


func _on_character_pressed(id: StringName) -> void:
	_selected_id = id
	if GameState.select_character(id):
		# 换角色后重开一个玩家实例（属性会重新计算）
		_respawn_player()
	_rebuild_character_list()


func _respawn_player() -> void:
	if player and is_instance_valid(player):
		var pos := player.global_position
		player.queue_free()
		var scene: PackedScene = load(PLAYER_SCENE)
		var inst := scene.instantiate()
		entity_root.add_child(inst)
		player = inst as Player
		player.global_position = pos
		var cam := player.get_node_or_null("Camera2D") as Camera2D
		if cam:
			cam.make_current()


func _show_character_detail(id: StringName) -> void:
	var cd := ConfigDB.get_character(id)
	if cd == null or _char_detail == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#%s][b]%s[/b][/color]" % [
		cd.accent_color.to_html(false), cd.display_name
	])
	lines.append("生命 %d  护甲 %d  能量 %d" % [
		int(cd.max_hp), int(cd.max_armor), int(cd.max_mp)
	])
	lines.append("移速 %.0f  暴击 %.0f%%  暴伤 %.0fx" % [
		cd.move_speed, cd.crit_chance * 100.0, cd.crit_mult
	])
	lines.append("[color=#ffd35c]技能：%s[/color]" % cd.skill_name)
	lines.append(cd.skill_description)
	if GameState.is_character_unlocked(id):
		lines.append("[color=#8fc75a]已解锁[/color]")
	else:
		lines.append("[color=#d94a4a]未解锁：%s[/color]" % cd.unlock_hint)
	_char_detail.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# 进入森林
# ---------------------------------------------------------------------------

func _on_enter_forest_portal(_pl: Node2D) -> void:
	_enter_forest()


func _enter_forest() -> void:
	if GameState.character_data == null:
		EventBus.toast.emit("请先选择角色", UIKit.COL_DANGER)
		return
	var run_seed_value := int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	if RunManager:
		RunManager.start_run(run_seed_value, 0)
	EventBus.toast.emit("进入宁静森林…", UIKit.COL_OK)
	SceneRouter.go_to(GameEnums.SCENE_FOREST, 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not SceneRouter.any_panel_open():
		_open_pause_menu()
		get_viewport().set_input_as_handled()
