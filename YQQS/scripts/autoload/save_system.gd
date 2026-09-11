extends Node
## SaveSystem —— 存档（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 存档只保存「跨局持久」的数据：GameState（等级/经验/金币/背包/解锁）、
##    WarehouseService（仓库）、SkillTreeService（技能树）。
##    单局内数据（地图、敌人、掉落物）一律不入档。
## 2. 存档格式为 JSON，顶层必须带 `version`；读档时先做版本迁移（migrate）。
##    新增字段必须给默认值，禁止让旧档读不出来。
## 3. 写档采用「先写 .tmp 再改名」两段式，避免断电写坏存档。
## 4. 任何模块需要入档 → 在这里加一个 section，不要在别处自己写文件。

const SLOT_COUNT := 3

var current_slot: int = 0
var last_save_time: int = 0
var _meta_cache: Dictionary = {}


func _ready() -> void:
	_refresh_meta_cache()


func slot_path(slot: int) -> String:
	return "user://save_slot_%d.save" % slot


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SLOT_COUNT:
		out.append(get_slot_meta(i))
	return out


func get_slot_meta(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"slot": slot, "exists": false}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"slot": slot, "exists": false}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {"slot": slot, "exists": false, "corrupt": true}
	var d: Dictionary = parsed
	return {
		"slot": slot,
		"exists": true,
		"version": int(d.get("version", 0)),
		"timestamp": int(d.get("timestamp", 0)),
		"play_time": float(d.get("play_time", 0.0)),
		"summary": d.get("summary", {}),
	}


func _refresh_meta_cache() -> void:
	_meta_cache.clear()
	for i in SLOT_COUNT:
		_meta_cache[i] = get_slot_meta(i)


# ---------------------------------------------------------------------------
# 保存
# ---------------------------------------------------------------------------

func save_game(slot: int = -1) -> bool:
	var s := current_slot if slot < 0 else slot
	var data := {
		"version": GameEnums.SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"play_time": GameState.play_time,
		"summary": _build_summary(),
		"game_state": GameState.to_dict(),
		"warehouse": WarehouseService.to_dict(),
		"skill_tree": SkillTreeService.to_dict(),
	}
	var txt := JSON.stringify(data, "\t")
	var path := slot_path(s)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var reason := "无法写入存档文件（错误码 %d）" % FileAccess.get_open_error()
		push_error("[SaveSystem] " + reason)
		EventBus.save_failed.emit(reason)
		return false
	f.store_string(txt)
	f.close()
	# 两段式：删旧 → 改名
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)
	)
	if err != OK:
		var reason2 := "存档改名失败（错误码 %d）" % err
		push_error("[SaveSystem] " + reason2)
		EventBus.save_failed.emit(reason2)
		return false
	current_slot = s
	last_save_time = Time.get_ticks_msec()
	_meta_cache[s] = get_slot_meta(s)
	EventBus.game_saved.emit(s)
	print("[SaveSystem] 已保存到槽位 %d（%s）" % [s, path])
	return true


func _build_summary() -> Dictionary:
	return {
		"character": String(GameState.character_id),
		"level": GameState.player_level,
		"gold": GameState.gold,
		"best_floor": GameState.best_floor,
		"kills": GameState.total_kills,
	}


# ---------------------------------------------------------------------------
# 读取
# ---------------------------------------------------------------------------

## 载入存档。成功返回 true；存档不存在返回 false（调用方决定是否开新档）。
func load_game(slot: int = -1) -> bool:
	var s := current_slot if slot < 0 else slot
	var path := slot_path(s)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[SaveSystem] 无法打开存档: %s" % path)
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("[SaveSystem] 存档损坏，无法解析: %s" % path)
		EventBus.save_failed.emit("存档损坏")
		return false
	var d: Dictionary = parsed
	d = migrate(d)
	GameState.from_dict(d.get("game_state", {}))
	SkillTreeService.from_dict(d.get("skill_tree", {}))
	WarehouseService.from_dict(d.get("warehouse", {}))
	GameState.play_time = float(d.get("play_time", 0.0))
	current_slot = s
	EventBus.game_loaded.emit(s)
	print("[SaveSystem] 已读取槽位 %d" % s)
	return true


## 读档，若不存在则开新档
func load_or_new(slot: int = 0) -> bool:
	if load_game(slot):
		return true
	new_game(slot)
	return false


func new_game(slot: int = 0) -> void:
	current_slot = slot
	GameState.reset_new_game()
	SkillTreeService.reset()
	WarehouseService.reset()
	print("[SaveSystem] 已开始新游戏（槽位 %d）" % slot)


## 版本迁移：旧档 → 当前版本
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v == GameEnums.SAVE_VERSION:
		return d
	if v < 1:
		# v0 → v1：补齐缺失字段
		if not d.has("game_state"):
			d["game_state"] = {}
		if not d.has("warehouse"):
			d["warehouse"] = {}
		if not d.has("skill_tree"):
			d["skill_tree"] = {}
		d["version"] = 1
		v = 1
	# 未来的迁移分支追加在这里：
	# if v < 2: ...
	d["version"] = GameEnums.SAVE_VERSION
	return d


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_meta_cache[slot] = get_slot_meta(slot)


# ---------------------------------------------------------------------------
# 自动存档
# ---------------------------------------------------------------------------

const AUTOSAVE_INTERVAL := 60.0
var _autosave_accum: float = 0.0
var autosave_enabled: bool = true


func _process(delta: float) -> void:
	GameState.play_time += delta
	if not autosave_enabled:
		return
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		# 只在非关卡内自动存（关卡内数据不入档，存了没意义还会卡顿）
		if not GameState.is_in_run:
			save_game()


func has_any_save() -> bool:
	for i in SLOT_COUNT:
		if has_slot(i):
			return true
	return false
