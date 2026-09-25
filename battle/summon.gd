class_name Summon
extends RefCounted

var id := ""
var display_name := ""
var element := ""
var glyph := ""
var max_hp := 10
var hp := 10
var turn_start_effects: Array = []

func setup(data: Dictionary) -> void:
	id = str(data["id"])
	display_name = str(data["name"])
	element = str(data["element"])
	glyph = str(data.get("glyph", BattleRules.element_name(element)))
	max_hp = int(data.get("hp", 10))
	hp = max_hp
	turn_start_effects = data.get("turn_start", []).duplicate(true)
