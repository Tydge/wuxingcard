class_name OnboardingProgress
extends RefCounted

const DEFAULT_PATH := "user://onboarding.json"
var path: String
var enabled := true
var completed := {}
var steps := {}
var battle_seen := false

func _init(save_path: String = DEFAULT_PATH, active: bool = true) -> void:
	path = save_path
	enabled = active
	if not FileAccess.file_exists(path): return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw is not Dictionary or raw.get("version", 0) != 1: return
	if raw.get("completed") is Dictionary: completed = raw["completed"]
	if raw.get("steps") is Dictionary: steps = raw["steps"]
	battle_seen = bool(raw.get("battle_seen", false))

static func game() -> OnboardingProgress:
	# Existing rule/UI fixtures opt out; onboarding tests explicitly use isolated saves.
	return OnboardingProgress.new(DEFAULT_PATH, not "--script" in OS.get_cmdline_args())

func pending(chapter: String) -> bool: return enabled and not bool(completed.get(chapter, false))
func step(chapter: String) -> int: return maxi(0, int(steps.get(chapter, 0)))
func advance(chapter: String, index: int) -> void:
	steps[chapter] = index
	_save()
func finish(chapter: String) -> void:
	completed[chapter] = true
	steps.erase(chapter)
	_save()
func claim_battle() -> void:
	battle_seen = true
	_save()
func first_battle() -> bool: return enabled and not battle_seen

func _save() -> void:
	if not enabled: return
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"version":1, "completed":completed, "steps":steps, "battle_seen":battle_seen}))
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if okay: DirAccess.rename_absolute(path + ".tmp", path)
