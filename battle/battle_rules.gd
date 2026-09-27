class_name BattleRules
extends RefCounted

const ELEMENTS := ["metal", "water", "wood", "fire", "earth"]
const NAMES := {"metal":"金", "water":"水", "wood":"木", "fire":"火", "earth":"土"}
const COLORS := {"metal":"#ffe16a", "water":"#82cafa", "wood":"#8dd89b", "fire":"#fb8b68", "earth":"#bb9068"}
const COUNTERED := {"metal":"wood", "wood":"earth", "earth":"water", "water":"fire", "fire":"metal"}

static func element_name(element: String) -> String:
	return NAMES.get(element, element)

static func color(element: String) -> Color:
	return Color.html(COLORS.get(element, "#ffffff"))

static func countered_by(attack_element: String) -> String:
	return COUNTERED[attack_element]

static func counter_of(element: String) -> String:
	for key in COUNTERED:
		if COUNTERED[key] == element:
			return key
	return ""

static func attack_adjustment(source: Combatant) -> int:
	return source.status_stacks("strong_attack") - source.status_stacks("weak_attack") if source != null else 0

static func defense_adjustment(target: Combatant) -> int:
	return target.status_stacks("weak_defense") - target.status_stacks("strong_defense")

static func damage_breakdown(target: Combatant, amount: int, element: String, source: Combatant = null) -> Dictionary:
	var same: int = target.energy[element]
	var weak: int = target.energy[countered_by(element)]
	var multiplier: float = maxf(0.0, 1.0 - same * 0.1 + weak * 0.1)
	var vulnerable: int = target.status_stacks("vulnerable")
	var tenacity: int = target.status_stacks("tenacity")
	var weak_stacks := source.status_stacks("weak") if source != null else 0
	var charge: int = source.status_stacks("charge") if source != null else 0
	var total_multiplier := maxf(0.0, 1.0 + (weak - same + vulnerable - tenacity + charge - weak_stacks) * 0.1)
	var fixed_amount := maxi(0, amount + attack_adjustment(source) + defense_adjustment(target))
	var before_shield: int = roundi(fixed_amount * total_multiplier)
	return {"base": amount, "same": same, "weak": weak, "multiplier": multiplier,
		"vulnerable": vulnerable, "tenacity": tenacity, "charge": charge,
		"weak_stacks": weak_stacks, "fixed": fixed_amount, "total_multiplier": total_multiplier, "raw": before_shield,
		"shield": mini(before_shield, target.status_stacks("shield")),
		"hp": maxi(0, before_shield - target.status_stacks("shield"))}

static func summon_matchup(target_element: String, attack_element: String) -> String:
	if target_element == attack_element: return "抵抗"
	if COUNTERED.get(attack_element, "") == target_element: return "克制"
	return ""

static func summon_damage(amount: int, source: Combatant = null, target_element: String = "", attack_element: String = "") -> int:
	var weak_stacks := source.status_stacks("weak") if source != null else 0
	var charge := source.status_stacks("charge") if source != null else 0
	var matchup := summon_matchup(target_element, attack_element) if target_element != "" else ""
	var elemental := -0.5 if matchup == "抵抗" else 0.5 if matchup == "克制" else 0.0
	return roundi(maxi(0, amount + attack_adjustment(source)) * maxf(0.0, 1.0 + elemental + (charge - weak_stacks) * 0.1))
