class_name CardKeywords
extends RefCounted

const NAMES := {"burn":"灼伤", "poison":"中毒", "bleed":"出血", "weak":"虚弱", "vulnerable":"脆弱", "charge":"蓄力", "tenacity":"坚韧", "regen":"再生", "shield":"护盾", "lock":"封锁"}

# Card explanations use X; status icon explanations use the current stack count.
static func status_description(id: String, stacks: String = "X", element: String = "") -> String:
	var percent := "10% × X" if stacks == "X" else "%d%%" % (int(stacks) * 10)
	match id:
		"burn": return "回合结束受到手牌数 × %s 的火伤害，然后减少一层。" % stacks
		"poison": return "每获得一次能量，失去 %s 点生命，然后减少一层。" % stacks
		"bleed": return "每打出一张牌，失去 %s 点生命，然后减少一层。" % stacks
		"regen": return "回合结束恢复 %s 点生命，然后减少一层。" % stacks
		"shield": return "抵消 %s 点元素伤害；回合开始层数减半，向上取整。" % stacks
		"lock": return "不能获得%s能量或打出%s系牌。" % [BattleRules.element_name(element), BattleRules.element_name(element)]
		"charge", "weak", "tenacity", "vulnerable":
			var direction := "造成" if id in ["charge", "weak"] else "受到"
			var sign_text := "+" if id in ["charge", "vulnerable"] else "−"
			var opposite: String = NAMES[Combatant.OPPOSITE_STATUSES[id]]
			return "%s伤害 %s%s；回合结束减少一层。与%s抵消，上限10层。" % [direction, sign_text, percent, opposite]
	return ""

static func entries(card: Dictionary, summons: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var effects: Array = card.get("effects", []).duplicate(true)
	var seen: Dictionary = {}
	for effect in card.get("effects", []):
		if effect["type"] != "summon": continue
		var summon: Dictionary = summons.get(effect["summon"], {})
		var element: String = summon.get("element", card["element"])
		result.append({"title": "抵抗·" + BattleRules.element_name(element), "text": "受到%s系伤害 −50%%。" % BattleRules.element_name(element)})
		result.append({"title": "克制·" + BattleRules.element_name(BattleRules.counter_of(element)), "text": "受到%s系伤害 +50%%。" % BattleRules.element_name(BattleRules.counter_of(element))})
		effects.append_array(summon.get("turn_start", []))
		effects.append_array(summon.get("turn_end", []))
	for effect in effects:
		if effect.get("type") != "status": continue
		var id: String = effect["status"]
		var element: String = effect.get("element", "")
		var key := id + element
		if seen.has(key): continue
		seen[key] = true
		var title: String = NAMES.get(id, id)
		if element != "": title += "·" + BattleRules.element_name(element)
		result.append({"title": title + " X", "text": status_description(id, "X", element)})
	return result
