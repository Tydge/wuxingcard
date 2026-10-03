class_name CardKeywords
extends RefCounted

const NAMES := {"burn":"灼伤", "poison":"中毒", "bleed":"出血", "weak":"虚弱", "vulnerable":"脆弱", "charge":"蓄力", "tenacity":"坚韧", "regen":"再生", "shield":"护盾", "lock":"封锁", "strong_attack":"强攻", "weak_attack":"弱攻", "strong_defense":"强防", "weak_defense":"弱防"}

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
		"strong_attack", "weak_attack", "strong_defense", "weak_defense":
			var direction := "造成" if id in ["strong_attack", "weak_attack"] else "受到"
			var sign_text := "+" if id in ["strong_attack", "weak_defense"] else "−"
			var opposite: String = NAMES[Combatant.OPPOSITE_STATUSES[id]]
			return "下一次%s伤害 %s%s，然后减少一层。与%s抵消。" % [direction, sign_text, stacks, opposite]
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
		effects.append_array(summon.get("on_spawn", []))
		effects.append_array(summon.get("turn_start", []))
		effects.append_array(summon.get("turn_end", []))
		effects.append_array(summon.get("after_spell", {}).get("effects", []))
		effects.append_array(summon.get("on_death", []))
		if not summon.get("on_heal", []).is_empty():
			result.append({"title":"恢复生命", "text":"双方角色与召唤物实际恢复生命才触发；满血治疗不触发，多只各自触发。"})
		if int(summon.get("enemy_cost_aura", 0)) > 0:
			result.append({"title":"费用光环", "text":"多只可叠加，0费牌也增加费用；此召唤物死亡后解除。"})
		if int(summon.get("enemy_qi_gain_reduction", 0)) > 0:
			result.append({"title":"锁息", "text":"仅减少对手回合开始时自然获得的真气，最低为0；不扣除已有真气。多只可叠加，死亡后解除。"})
	for effect in effects:
		if effect.has("hand_multiplier") and not seen.has("hand_scaling"):
			seen["hand_scaling"] = true
			var description := "按对手当前全部手牌计数，不查看或公开牌的内容；选择召唤物时仍按其持有者手牌计数。" if effect.get("hand_owner") == "opponent" else "打出本牌后计数，不含本牌；水系计数包含原、精、玄各等级水系牌。"
			result.append({"title":"手牌计数", "text":description})
		if effect.has("energy_multiplier") and not seen.has("energy_scaling"):
			seen["energy_scaling"] = true
			result.append({"title":"能量伤害", "text":"按自身当前能量计算基础伤害，向下取整；再结算强攻、抗性等修正，不消耗对应能量。"})
		if effect.get("stacks_from_status") == "strong_defense" and not seen.has("defense_copy"):
			seen["defense_copy"] = true
			result.append({"title":"铸锋", "text":"按自身当前强防层数获得强攻，不消耗强防；获得的强攻照常与弱攻抵消。"})
		if effect.get("stacks_from_status") == "poison" and not seen.has("poison"):
			seen["poison"] = true
			result.append({"title":"木生火", "text":"以对手当前中毒层数除以指定值，向下取整，施加灼伤；不会消耗中毒。"})
			result.append({"title":"中毒 X", "text":status_description("poison")})
		if effect.get("type") == "contemplate" and not seen.has("contemplate"):
			seen["contemplate"] = true
			result.append({"title":"观想N", "text":"查看牌堆顶至多N张，选1张入手，其余顺序不变。"})
		if effect.get("type") == "discover" and not seen.has("discover"):
			seen["discover"] = true
			result.append({"title":"发现N", "text":"从指定范围随机提供至多N张不同卡牌，选1张加入手牌；不消耗牌堆。未限定时从全部原级卡牌中选择。"})
		if effect.get("type") not in ["status", "remove_status", "reduce_status"]: continue
		var id: String = effect["status"]
		var element: String = effect.get("element", "")
		var key := id + element
		if seen.has(key): continue
		seen[key] = true
		var title: String = NAMES.get(id, id)
		if element != "": title += "·" + BattleRules.element_name(element)
		result.append({"title": title + " X", "text": status_description(id, "X", element)})
	return result
