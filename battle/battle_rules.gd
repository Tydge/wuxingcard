class_name BattleRules
extends RefCounted

const ELEMENTS := ["metal", "wood", "water", "fire", "earth"]
const NAMES := {"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}
const COLORS := {"metal":"#e6c98d", "wood":"#8dd89b", "water":"#82cafa", "fire":"#fb8b68", "earth":"#dabb82"}
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

static func damage_breakdown(target: Combatant, amount: int, element: String) -> Dictionary:
	var same: int = target.energy[element]
	var weak: int = target.energy[countered_by(element)]
	var multiplier: float = maxf(0.0, 1.0 - same * 0.1 + weak * 0.1)
	var vulnerable: int = target.status_stacks("vulnerable")
	var before_shield: int = roundi(amount * multiplier * (1.0 + vulnerable * 0.25))
	return {"base": amount, "same": same, "weak": weak, "multiplier": multiplier,
		"vulnerable": vulnerable, "raw": before_shield,
		"shield": mini(before_shield, target.status_stacks("shield")),
		"hp": maxi(0, before_shield - target.status_stacks("shield"))}
