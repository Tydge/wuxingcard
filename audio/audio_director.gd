extends Node

# One audio service for desktop and Android. Only semantic actions call into it;
# rebuilding the battle UI never creates another music player or repeats a sound.
const SETTINGS_PATH := "user://audio_settings.json"
const MENU_TRACKS := [
	"res://assets/audio/music/menu_whispers_of_silk.mp3",
	"res://assets/audio/music/menu_ethereal_veil.mp3",
	"res://assets/audio/music/menu_whisper_dragon.mp3",
	"res://assets/audio/music/menu_whisper_dragon_1.mp3",
]
const BATTLE_TRACKS := [
	"res://assets/audio/music/battle_dangerous_duel.mp3",
	"res://assets/audio/music/battle_whisper_dragon_3.mp3",
]
const SFX := {
	"ui_select": "res://assets/audio/sfx/ui_select.ogg",
	"ui_confirm": "res://assets/audio/sfx/ui_confirm.ogg",
	"ui_back": "res://assets/audio/sfx/ui_back.ogg",
	"ui_error": "res://assets/audio/sfx/ui_error.ogg",
	"page_turn": "res://assets/audio/sfx/page_turn.ogg",
	"card_focus": "res://assets/audio/sfx/card_focus.ogg",
	"card_draw": "res://assets/audio/sfx/card_draw.ogg",
	"card_play": "res://assets/audio/sfx/card_play.ogg",
	"card_discard": "res://assets/audio/sfx/card_discard.ogg",
	"spell_whoosh": "res://assets/audio/sfx/spell_whoosh.ogg",
	"summon_open": "res://assets/audio/sfx/summon_open.ogg",
	"summon_death": "res://assets/audio/sfx/summon_death.ogg",
	"energy": "res://assets/audio/sfx/energy.ogg",
	"status": "res://assets/audio/sfx/status.ogg",
	"heal": "res://assets/audio/sfx/heal.ogg",
	"hit_metal": "res://assets/audio/sfx/hit_metal.ogg",
	"hit_water": "res://assets/audio/sfx/hit_water.ogg",
	"hit_wood": "res://assets/audio/sfx/hit_wood.ogg",
	"hit_fire": "res://assets/audio/sfx/hit_fire.ogg",
	"hit_earth": "res://assets/audio/sfx/hit_earth.ogg",
	"hit_shield": "res://assets/audio/sfx/hit_shield.ogg",
	"element_metal": "res://assets/audio/sfx/element_metal.wav",
	"element_water": "res://assets/audio/sfx/element_water.wav",
	"element_wood": "res://assets/audio/sfx/element_wood.wav",
	"element_fire": "res://assets/audio/sfx/element_fire.wav",
	"element_earth": "res://assets/audio/sfx/element_earth.wav",
}
const UI_KEYS := ["ui_select", "ui_confirm", "ui_back", "ui_error", "page_turn", "card_focus"]
const BASE_DB := {
	"ui_select": -13.0, "ui_confirm": -10.0, "ui_back": -12.0,
	"ui_error": -12.0, "page_turn": -11.0, "card_focus": -19.0,
	"card_draw": -10.0, "card_play": -8.0, "card_discard": -9.0,
	"spell_whoosh": -10.0, "summon_open": -10.0, "summon_death": -8.0,
	"energy": -14.0, "status": -13.0, "heal": -10.0,
	"hit_shield": -9.0,
}

var rng := RandomNumberGenerator.new()
var music_players: Array[AudioStreamPlayer] = []
var sfx_players: Array[AudioStreamPlayer] = []
var ui_players: Array[AudioStreamPlayer] = []
var streams := {}
var last_played := {}
var levels := {"Master": 0.9, "Music": 0.42, "SFX": 0.78, "UI": 0.78}
var context := ""
var bag: Array[String] = []
var previous_track := ""
var active_music := -1
var music_tween: Tween
var next_hit_tick := 0
var enabled := true

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or should_mute_test_audio(OS.get_cmdline_args(), OS.get_cmdline_user_args(), OS.get_environment("WUXING_TEST_AUDIO")):
		enabled = false
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
		return
	rng.randomize()
	_ensure_buses()
	_load_settings()
	_apply_levels()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		music_players.append(player)
	for i in 12:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	for i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = "UI"
		add_child(player)
		ui_players.append(player)

static func should_mute_test_audio(arguments: PackedStringArray, user_arguments: PackedStringArray, audio_mode: String = "") -> bool:
	# Session switches never write the player's saved audio levels.
	if "--mute-audio" in user_arguments or audio_mode == "0": return true
	if "--test-audio" in user_arguments or audio_mode == "1": return false
	for index in arguments.size() - 1:
		if arguments[index] not in ["--script", "-s"]: continue
		var path := arguments[index + 1].replace("\\", "/")
		var name := path.get_file().get_basename()
		return "/tests/" in path or path.begins_with("tests/") or name.begins_with("test_") or name.ends_with("_test") or name.begins_with("verify_")
	return false

func _notification(what: int) -> void:
	if not enabled: return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		for player in music_players: player.stream_paused = true
		for player in sfx_players + ui_players: player.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		for player in music_players: player.stream_paused = false

func _ensure_buses() -> void:
	for name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(name) >= 0: continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH): return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null: return
	var saved = JSON.parse_string(file.get_as_text())
	if saved is not Dictionary: return
	for bus in levels:
		if saved.has(bus): levels[bus] = clampf(float(saved[bus]), 0.0, 1.0)

func _apply_levels() -> void:
	for bus in levels:
		var index := AudioServer.get_bus_index(bus)
		if index < 0: continue
		var level := float(levels[bus])
		AudioServer.set_bus_mute(index, level <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.001)))

func get_level(bus: String) -> float:
	return float(levels.get(bus, 1.0))

func set_level(bus: String, value: float) -> void:
	if not levels.has(bus): return
	levels[bus] = clampf(value, 0.0, 1.0)
	if not enabled: return
	_apply_levels()
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(levels))

func set_context(next: String) -> void:
	if not enabled or context == next: return
	context = next
	bag.clear()
	_start_next_track(1.2)

func _process(_delta: float) -> void:
	if not enabled or context.is_empty() or active_music < 0: return
	if music_tween != null and music_tween.is_running(): return
	var player := music_players[active_music]
	if not player.playing:
		_start_next_track(0.55)
	elif player.stream != null and player.stream.get_length() > 0.0 and player.stream.get_length() - player.get_playback_position() < 1.35:
		_start_next_track(1.15)

func _start_next_track(fade_seconds: float) -> void:
	if context.is_empty(): return
	var tracks: Array = MENU_TRACKS if context == "menu" else BATTLE_TRACKS
	if bag.is_empty():
		bag.assign(tracks)
		bag.shuffle()
		if bag.size() > 1 and bag[-1] == previous_track:
			var replacement := bag[0]
			bag[0] = bag[-1]
			bag[-1] = replacement
	var path: String = bag.pop_back()
	if not ResourceLoader.exists(path): return
	var old_index := active_music
	var next_index := 0 if active_music != 0 else 1
	var player := music_players[next_index]
	player.stop()
	player.stream = load(path)
	player.volume_db = -48.0
	player.play()
	active_music = next_index
	previous_track = path
	if music_tween != null and music_tween.is_running(): music_tween.kill()
	music_tween = create_tween().set_parallel(true)
	music_tween.tween_property(player, "volume_db", 0.0, fade_seconds)
	if old_index >= 0:
		var old := music_players[old_index]
		music_tween.tween_property(old, "volume_db", -48.0, fade_seconds)
		music_tween.chain().tween_callback(old.stop)

func play_sfx(key: String, offset_db: float = 0.0, cooldown_ms: int = 0) -> void:
	if not enabled or not SFX.has(key): return
	var now := Time.get_ticks_msec()
	if cooldown_ms > 0 and now - int(last_played.get(key, -100000)) < cooldown_ms: return
	last_played[key] = now
	if not streams.has(key): streams[key] = load(SFX[key])
	var pool := ui_players if key in UI_KEYS else sfx_players
	var player: AudioStreamPlayer = pool[0]
	for candidate in pool:
		if not candidate.playing:
			player = candidate
			break
	player.stop()
	player.stream = streams[key]
	player.pitch_scale = rng.randf_range(0.975, 1.025)
	player.volume_db = float(BASE_DB.get(key, -8.0)) + offset_db
	player.play()

func play_cast(element: String, is_summon: bool = false) -> void:
	play_sfx("summon_open" if is_summon else "spell_whoosh", -2.0 if is_summon else -5.0, 100)
	var accent := "element_" + element
	if SFX.has(accent): play_sfx(accent, -3.0)

func play_hit(element: String, blocked: bool = false, amount: int = 1) -> void:
	if not enabled: return
	var now := Time.get_ticks_msec()
	# Multi-hit cards are resolved in one frame. Space their audible impacts
	# alongside the staggered damage numbers instead of stacking a loud burst.
	if next_hit_tick < now: next_hit_tick = now
	if next_hit_tick - now > 420: return
	var delay := float(next_hit_tick - now) / 1000.0
	next_hit_tick += 145
	if delay > 0.001: await get_tree().create_timer(delay).timeout
	if context != "battle": return
	var key := "hit_shield" if blocked or amount <= 0 else "hit_" + element
	if not SFX.has(key): key = "hit_wood"
	play_sfx(key, -2.0 if amount >= 18 else 0.0)
