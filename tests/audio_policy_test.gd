extends SceneTree

const POLICY = preload("res://audio/audio_director.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func run() -> void:
	check(POLICY.should_mute_test_audio(["--script", "res://tests/artifact_ui_test.gd"], []), "direct graphical tests mute all audio by default")
	check(POLICY.should_mute_test_audio(["-s", "res://tools/test_drag.gd"], []), "legacy test scripts also default to silence")
	check(not POLICY.should_mute_test_audio([], []), "normal gameplay retains saved sound settings")
	check(POLICY.should_mute_test_audio([], ["--mute-audio"]), "manual previews can explicitly mute")
	check(not POLICY.should_mute_test_audio(["--script", "res://tests/artifact_ui_test.gd"], ["--test-audio"]), "dedicated audio tests can explicitly enable sound")
	check(POLICY.should_mute_test_audio([], ["--test-audio"], "0"), "the silent runner overrides sound flags")
	check(not POLICY.should_mute_test_audio(["--script", "res://tests/artifact_ui_test.gd"], [], "1"), "runner audio opt-in enables a dedicated check")
	var director := root.get_node("AudioDirector")
	check(not director.enabled and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "actual graphical test session disables the service and master bus")
	var saved_exists := FileAccess.file_exists(POLICY.SETTINGS_PATH)
	var saved := FileAccess.get_file_as_string(POLICY.SETTINGS_PATH) if saved_exists else ""
	GameAudio.set_context("battle")
	GameAudio.play_sfx("ui_select")
	GameAudio.play_cast("fire")
	GameAudio.play_hit("metal")
	GameAudio.set_level("Master", 0.0)
	await process_frame
	check(director.music_players.is_empty() and director.sfx_players.is_empty() and director.ui_players.is_empty(), "music, combat and UI actions create no players while muted")
	check(FileAccess.file_exists(POLICY.SETTINGS_PATH) == saved_exists and (not saved_exists or FileAccess.get_file_as_string(POLICY.SETTINGS_PATH) == saved), "silent tests never overwrite player's sound settings")
	print("Audio policy: silent tests, all sound channels, explicit opt-in and saved settings; %d failures" % failures)
	quit(1 if failures else 0)
