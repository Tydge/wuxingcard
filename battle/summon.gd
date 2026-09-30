class_name Summon
extends RefCounted

var id := ""
var art_id := ""
var card_id := ""
var display_name := ""
var element := ""
var max_hp := 15
var hp := 15
var art_scale := 1.0
var spawn_effects: Array = []
var turn_start_effects: Array = []
var turn_end_effects: Array = []

func setup(data: Dictionary) -> void:
	id = str(data["id"])
	art_id = str(data.get("art_id", data["id"]))
	card_id = str(data.get("card_id", ""))
	display_name = str(data["name"])
	element = str(data["element"])
	max_hp = int(data.get("hp", 15))
	hp = max_hp
	# Battlefield art only; card framing, HP badge and target area remain stable.
	art_scale = clampf(float(data.get("art_scale", 1.0)), 0.5, 1.5)
	spawn_effects = data.get("on_spawn", []).duplicate(true)
	turn_start_effects = data.get("turn_start", []).duplicate(true)
	turn_end_effects = data.get("turn_end", []).duplicate(true)

func snapshot() -> Summon:
	var copy := Summon.new()
	for property in ["id", "art_id", "card_id", "display_name", "element", "max_hp", "hp", "art_scale"]:
		copy.set(property, get(property))
	copy.spawn_effects = spawn_effects.duplicate(true)
	copy.turn_start_effects = turn_start_effects.duplicate(true)
	copy.turn_end_effects = turn_end_effects.duplicate(true)
	return copy
