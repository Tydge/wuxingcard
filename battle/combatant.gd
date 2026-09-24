class_name Combatant
extends RefCounted

var id := ""
var display_name := ""
var max_hp := 100
var hp := 100
var energy: Dictionary = {}
var draw_pile: Array[String] = []
var hand: Array[String] = []
var discard_pile: Array[String] = []
var statuses: Array[Dictionary] = []
var fatigue_level := 0

func setup(new_id: String, new_name: String, deck: Array, random: RandomNumberGenerator) -> void:
	id = new_id
	display_name = new_name
	hp = max_hp
	fatigue_level = 0
	energy.clear()
	for element in BattleRules.ELEMENTS:
		energy[element] = 1
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	statuses.clear()
	for card_id in deck:
		draw_pile.append(str(card_id))
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var temp := draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = temp

func status_stacks(status_id: String, element: String = "") -> int:
	var total := 0
	for status in statuses:
		if status["id"] == status_id and (element == "" or status.get("element", "") == element):
			total += int(status["stacks"])
	return total

func add_status(status_id: String, stacks: int, turns: int, element: String = "") -> void:
	if stacks <= 0:
		return
	for status in statuses:
		if status["id"] == status_id and status.get("element", "") == element:
			status["stacks"] = int(status["stacks"]) + stacks
			status["turns"] = maxi(int(status["turns"]), turns)
			return
	statuses.append({"id": status_id, "stacks": stacks, "turns": turns, "element": element})

func remove_status(status_id: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i]["id"] == status_id:
			statuses.remove_at(i)

func tick_status_durations() -> void:
	for i in range(statuses.size() - 1, -1, -1):
		statuses[i]["turns"] = int(statuses[i]["turns"]) - 1
		if int(statuses[i]["turns"]) <= 0 or int(statuses[i]["stacks"]) <= 0:
			statuses.remove_at(i)

func can_pay(card: Dictionary) -> bool:
	var element: String = card["element"]
	if int(energy[element]) < int(card["cost"]) or status_stacks("lock", element) > 0:
		return false
	for effect in card["effects"]:
		if effect["type"] == "convert_energy" and effect.get("target", "self") == "self":
			var from_element: String = effect["from"]
			var paid_from := int(card["cost"]) if from_element == element else 0
			if int(energy[from_element]) - paid_from < int(effect["amount"]):
				return false
	return true

func gain_energy(element: String, amount: int) -> int:
	if status_stacks("lock", element) > 0:
		return 0
	var before: int = energy[element]
	energy[element] = clampi(before + amount, 0, 10)
	return int(energy[element]) - before

func lose_energy(element: String, amount: int) -> int:
	var before: int = energy[element]
	energy[element] = maxi(0, before - amount)
	return before - int(energy[element])
