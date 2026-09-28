class_name GameAudio
extends RefCounted

# Headless SceneTree scripts can instantiate screens before Godot registers
# autoload globals for GDScript compilation. Route through the actual root
# node so the same UI also works in those tests without special casing sound.
static func _director() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioDirector") if tree != null else null

static func set_context(context: String) -> void:
	var director := _director()
	if director != null: director.call("set_context", context)

static func play_sfx(key: String, offset_db: float = 0.0, cooldown_ms: int = 0) -> void:
	var director := _director()
	if director != null: director.call("play_sfx", key, offset_db, cooldown_ms)

static func play_cast(element: String, is_summon: bool = false) -> void:
	var director := _director()
	if director != null: director.call("play_cast", element, is_summon)

static func play_hit(element: String, blocked: bool = false, amount: int = 1) -> void:
	var director := _director()
	if director != null: director.call("play_hit", element, blocked, amount)

static func get_level(bus: String) -> float:
	var director := _director()
	return float(director.call("get_level", bus)) if director != null else 0.8

static func set_level(bus: String, value: float) -> void:
	var director := _director()
	if director != null: director.call("set_level", bus, value)
