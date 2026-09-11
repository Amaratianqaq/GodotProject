extends Node
## AudioManager —— 音频（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 业务代码只允许调用 play_sfx / play_bgm，禁止自己 new AudioStreamPlayer。
## 2. 音频文件缺失时 **静默跳过**（项目第一阶段没有任何音频资源，
##    后续往 res://assets/audio/ 丢文件即可自动生效）。
## 3. 音量设置持久化在 ConfigFile（user://settings.cfg），
##    与存档分离——设置属于「设备」而非「存档」。

const SETTINGS_PATH := "user://settings.cfg"
const SFX_POOL_SIZE := 12

var master_volume: float = 1.0
var sfx_volume: float = 0.9
var bgm_volume: float = 0.6

var _sfx_players: Array[AudioStreamPlayer] = []
var _bgm_player: AudioStreamPlayer = null
var _bgm_player_b: AudioStreamPlayer = null
var _bgm_crossfading: bool = false
var _current_bgm_path: String = ""
var _sfx_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	_build_players()
	load_settings()
	apply_volumes()


func _ensure_buses() -> void:
	for bus_name in ["SFX", "BGM"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _build_players() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX%d" % i
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGM_A"
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)

	_bgm_player_b = AudioStreamPlayer.new()
	_bgm_player_b.name = "BGM_B"
	_bgm_player_b.bus = "BGM"
	add_child(_bgm_player_b)


# ---------------------------------------------------------------------------
# 音效
# ---------------------------------------------------------------------------

func play_sfx(path: String, pitch_variation: float = 0.06, volume_db: float = 0.0) -> void:
	if path.is_empty():
		return
	var stream := _load_stream(path)
	if stream == null:
		return
	var p := _free_sfx_player()
	if p == null:
		return
	p.stream = stream
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	p.volume_db = volume_db
	p.play()


func play_sfx_2d(path: String, world_pos: Vector2, pitch_variation: float = 0.06) -> void:
	## 第一阶段做简化处理：按与相机的距离衰减
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		play_sfx(path, pitch_variation)
		return
	var dist := cam.global_position.distance_to(world_pos)
	var db := -80.0
	if dist < 400.0:
		db = lerpf(-6.0, -34.0, clampf(dist / 400.0, 0.0, 1.0))
	play_sfx(path, pitch_variation, db)


func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0] if not _sfx_players.is_empty() else null


func _load_stream(path: String) -> AudioStream:
	if _sfx_cache.has(path):
		return _sfx_cache[path]
	if not ResourceLoader.exists(path):
		_sfx_cache[path] = null
		return null
	var s: AudioStream = load(path)
	_sfx_cache[path] = s
	return s


# ---------------------------------------------------------------------------
# 背景音乐
# ---------------------------------------------------------------------------

func play_bgm(path: String, fade_time: float = 0.8) -> void:
	if path == _current_bgm_path and _bgm_player and _bgm_player.playing:
		return
	var stream := _load_stream(path)
	if stream == null:
		return
	_current_bgm_path = path
	if stream is AudioStreamWAV or stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	# 交叉淡入
	var from := _bgm_player
	var to := _bgm_player_b
	if _bgm_crossfading:
		from = _bgm_player_b
		to = _bgm_player
	_bgm_crossfading = not _bgm_crossfading
	to.stream = stream
	to.volume_db = -40.0
	to.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(to, "volume_db", linear_to_db(maxf(0.001, bgm_volume)), fade_time)
	if from.playing:
		tw.tween_property(from, "volume_db", -40.0, fade_time)
		tw.chain().tween_callback(from.stop)


func stop_bgm(fade_time: float = 0.5) -> void:
	_current_bgm_path = ""
	for p in [_bgm_player, _bgm_player_b]:
		if p == null or not p.playing:
			continue
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(p, "volume_db", -40.0, fade_time)
		tw.tween_callback(p.stop)


func current_bgm() -> String:
	return _current_bgm_path


# ---------------------------------------------------------------------------
# 音量
# ---------------------------------------------------------------------------

func apply_volumes() -> void:
	_set_bus_linear("Master", master_volume)
	_set_bus_linear("SFX", sfx_volume)
	_set_bus_linear("BGM", bgm_volume)


func _set_bus_linear(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_volumes()
	save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	apply_volumes()
	save_settings()


func set_bgm_volume(v: float) -> void:
	bgm_volume = clampf(v, 0.0, 1.0)
	apply_volumes()
	save_settings()


# ---------------------------------------------------------------------------
# 设置持久化
# ---------------------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = float(cfg.get_value("audio", "master", 1.0))
	sfx_volume = float(cfg.get_value("audio", "sfx", 0.9))
	bgm_volume = float(cfg.get_value("audio", "bgm", 0.6))
