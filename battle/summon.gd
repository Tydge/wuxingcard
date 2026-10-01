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
var heal_effects: Array = []
var enemy_cost_aura := 0
var printed_hp := 15
var art_flip_h := false

func setup(data: Dictionary) -> void:
	id = str(data["id"])
	art_id = str(data.get("art_id", data["id"]))
	card_id = str(data.get("card_id", ""))
	display_name = str(data["name"])
	element = str(data["element"])
	max_hp = int(data.get("hp", 15))
	printed_hp = max_hp
	art_flip_h = bool(data.get("art_flip_h", false))
	hp = max_hp
	# Battlefield art only; card framing, HP badge and target area remain stable.
	art_scale = clampf(float(data.get("art_scale", 1.0)), 0.5, 1.5)
	spawn_effects = data.get("on_spawn", []).duplicate(true)
	turn_start_effects = data.get("turn_start", []).duplicate(true)
	turn_end_effects = data.get("turn_end", []).duplicate(true)
	heal_effects = data.get("on_heal", []).duplicate(true)
	enemy_cost_aura = int(data.get("enemy_cost_aura", 0))

func snapshot() -> Summon:
	var copy := Summon.new()
	for property in ["id", "art_id", "card_id", "display_name", "element", "max_hp", "hp", "art_scale", "enemy_cost_aura", "printed_hp", "art_flip_h"]:
		copy.set(property, get(property))
	copy.spawn_effects = spawn_effects.duplicate(true)
	copy.turn_start_effects = turn_start_effects.duplicate(true)
	copy.turn_end_effects = turn_end_effects.duplicate(true)
	copy.heal_effects = heal_effects.duplicate(true)
	return copy
