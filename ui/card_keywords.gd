class_name CardKeywords
extends RefCounted

const NAMES := {"burn":"灼伤", "poison":"中毒", "bleed":"出血", "weak":"虚弱", "vulnerable":"脆弱", "charge":"蓄力", "tenacity":"坚韧", "regen":"再生", "shield":"护盾", "lock":"封锁", "strong_attack":"强攻", "weak_attack":"弱攻", "strong_defense":"强防", "weak_defense":"弱防"}

# Card explanations use X; status icon explanations use the current stack count.
static func status_description(id: String, stacks: String = "X", element: String = "") -> String:
	var percent := "10% × X" if stacks == "X" else "%d%%" % (int(stacks) * 10)
	match id:
		"burn": return "回合结束受手牌数 × %s 火伤害，层数−1。" % stacks
		"poison": return "每次获得能量失去%s生命，层数−1。" % stacks
		"bleed": return "每次出牌失去%s生命，层数−1。" % stacks
		"regen": return "回合结束恢复%s生命，层数−1。" % stacks
		"shield": return "抵消%s元素伤害；回合开始层数减半，向上取整。" % stacks
		"lock": return "不能获得%s能量或打出%s系牌。" % [BattleRules.element_name(element), BattleRules.element_name(element)]
		"strong_attack", "weak_attack", "strong_defense", "weak_defense":
			var direction := "造成" if id in ["strong_attack", "weak_attack"] else "受到"
			var sign_text := "+" if id in ["strong_attack", "weak_defense"] else "−"
			var opposite: String = NAMES[Combatant.OPPOSITE_STATUSES[id]]
			return "每次%s伤害%s%s，层数−1；与%s抵消。" % [direction, sign_text, stacks, opposite]
		"charge", "weak", "tenacity", "vulnerable":
			var direction := "造成" if id in ["charge", "weak"] else "受到"
			var sign_text := "+" if id in ["charge", "vulnerable"] else "−"
			var opposite: String = NAMES[Combatant.OPPOSITE_STATUSES[id]]
			return "%s伤害%s%s；回合结束层数−1。与%s抵消，上限10层。" % [direction, sign_text, percent, opposite]
	return ""

static func _add_status(result: Array[Dictionary], seen: Dictionary, id: String, element: String = "") -> void:
	if not NAMES.has(id): return
	var key := id + element
	if seen.has(key): return
	seen[key] = true
	var title: String = NAMES[id]
	if element != "": title += "·" + BattleRules.element_name(element)
	result.append({"title":title + " X", "text":status_description(id, "X", element)})

static func entries(card: Dictionary, summons: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var effects: Array = card.get("effects", []).duplicate(true)
	var seen: Dictionary = {}
	for effect in card.get("effects", []):
		if effect["type"] != "summon": continue
		var summon: Dictionary = summons.get(effect["summon"], {})
		for timing in ["on_spawn", "turn_start", "turn_end", "on_heal", "on_death"]:
			effects.append_array(summon.get(timing, []))
		effects.append_array(summon.get("after_spell", {}).get("effects", []))
	# Explain named keywords, including statuses referenced by scaling/removal.
	var index := 0
	while index < effects.size():
		var effect: Dictionary = effects[index]
		index += 1
		effects.append_array(effect.get("on_kill", []))
		if effect.get("type") == "contemplate" and not seen.has("contemplate"):
			seen["contemplate"] = true
			result.append({"title":"观想N", "text":"查看牌堆顶至多N张，选1张入手，其余顺序不变。"})
		if effect.get("type") == "discover" and not seen.has("discover"):
			seen["discover"] = true
			result.append({"title":"发现N", "text":"随机提供至多N张同等级卡牌，选1张入手。"})
		if effect.get("type") in ["status", "remove_status", "reduce_status"]:
			_add_status(result, seen, str(effect["status"]), str(effect.get("element", "")))
		if effect.has("stacks_from_status"):
			_add_status(result, seen, str(effect["stacks_from_status"]))
		if effect.has("shield_multiplier") or effect.get("type") == "shield_heal":
			_add_status(result, seen, "shield")
	return result
