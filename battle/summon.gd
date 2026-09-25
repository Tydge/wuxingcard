class_name Summon
extends RefCounted

var id := ""
var card_id := ""
var display_name := ""
var element := ""
var max_hp := 15
var hp := 15
var turn_start_effects: Array = []

func setup(data: Dictionary) -> void:
	id = str(data["id"])
	card_id = str(data.get("card_id", ""))
	display_name = str(data["name"])
	element = str(data["element"])
	max_hp = int(data.get("hp", 15))
	hp = max_hp
	turn_start_effects = data.get("turn_start", []).duplicate(true)
