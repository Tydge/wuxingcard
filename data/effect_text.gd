class_name EffectText
extends RefCounted

# One vocabulary and one formatter for all three levels and all display surfaces.
static func describe(effects: Array, context: String = "hero") -> String:
	var parts: Array[String] = []
	var conditional: Array[bool] = []
	var i := 0
	while i < effects.size():
		var effect: Dictionary = effects[i]
		var count := 1
		while i + count < effects.size() and effects[i + count] == effect: count += 1
		var sentence := single(effect, context).trim_suffix("。")
		if count > 1: sentence += {2:"两次", 3:"三次"}.get(count, "%d次" % count)
		# Compact parallel effects without changing their order or trigger count.
		if count == 1 and not effect.has("condition"):
			var kind := str(effect["type"])
			if kind == "gain_energy":
				var elements: Array[String] = [BattleRules.element_name(effect["element"])]
				while i + count < effects.size():
					var next: Dictionary = effects[i + count]
					if next.get("type") != kind or next.has("condition") or _target(next, context) != _target(effect, context) or next.get("amount") != effect.get("amount"): break
					var element := BattleRules.element_name(str(next["element"]))
					if element in elements: break
					elements.append(element)
					count += 1
				if count > 1: sentence = "%s获得%s能量各%d点" % [_subject(effect, context), "、".join(elements), int(effect["amount"])]
			elif kind == "status":
				var statuses: Array[String] = [_status_amount(effect)]
				while i + count < effects.size():
					var next: Dictionary = effects[i + count]
					if next.get("type") != kind or next.has("condition") or _target(next, context) != _target(effect, context): break
					statuses.append(_status_amount(next))
					count += 1
				if count > 1: sentence = _subject(effect, context) + "获得" + "、".join(statuses)
				elif i + 1 < effects.size():
					var next: Dictionary = effects[i + 1].duplicate(true)
					if _target(effect, context) == "self" and next.get("target") == "opponent":
						next["target"] = "self"
						if next == effect:
							sentence = "双方获得" + _status_amount(effect)
							count = 2
			elif kind == "remove_status":
				var names: Array[String] = [CardKeywords.NAMES.get(effect["status"], effect["status"])]
				while i + count < effects.size():
					var next: Dictionary = effects[i + count]
					if next.get("type") != kind or next.has("condition") or _target(next, context) != _target(effect, context): break
					names.append(CardKeywords.NAMES.get(next["status"], next["status"]))
					count += 1
				if count > 1: sentence = "解除" + _subject(effect, context) + "、".join(names)
		# Omit an obvious caster subject, but retain it after an enemy clause.
		var previous := parts[-1] if not parts.is_empty() else ""
		if context != "summon" and (parts.is_empty() or not (previous.contains("对手") or previous.contains("敌方") or previous.contains("所有目标") or previous.contains("双方"))):
			sentence = sentence.trim_prefix("自身").replace("，自身", "，")
		elif context == "summon" and previous.begins_with("召唤者"):
			sentence = sentence.trim_prefix("召唤者")
		if i > 0 and effects[i - 1].get("type") == "break_shield" and effect.get("type") == "damage" and effect.get("target") == "opponent" and not effect.has("condition") and not conditional[-1]:
			parts[-1] += "，并" + sentence.trim_prefix("对手")
			i += count
			continue
		if not effect.has("condition") and not parts.is_empty() and not conditional[-1]:
			var merged := false
			for subject in ["", "自身", "对手", "召唤者"]:
				var prefix: String = subject + "获得"
				if previous.begins_with(prefix) and sentence.begins_with(prefix):
					parts[-1] += "、" + sentence.trim_prefix(prefix)
					merged = true
					break
			# The summon subject may already have been omitted from this clause.
			if not merged and previous.begins_with("召唤者获得") and sentence.begins_with("获得"):
				parts[-1] += "、" + sentence.trim_prefix("获得")
				merged = true
			if merged:
				i += count
				continue
		parts.append(sentence)
		conditional.append(effect.has("condition"))
		i += count
	var text := ""
	for index in parts.size():
		if index > 0: text += "。" if conditional[index] or conditional[index - 1] else "，"
		text += parts[index]
	return text + "。" if not parts.is_empty() else ""

static func _target(effect: Dictionary, context: String) -> String:
	return str(effect.get("target", "self" if context == "summon" else "opponent"))

static func _subject(effect: Dictionary, context: String) -> String:
	return ("召唤者" if context == "summon" else "自身") if _target(effect, context) == "self" else "对手"

static func _status_amount(effect: Dictionary) -> String:
	var name: String = CardKeywords.NAMES.get(effect["status"], effect["status"])
	if effect.get("status") == "lock": name += "·" + BattleRules.element_name(str(effect.get("element", "")))
	return "%d层%s" % [int(effect["stacks"]), name]

static func single(effect: Dictionary, context: String) -> String:
	var amount := int(effect.get("amount", 0))
	var target := _target(effect, context)
	var own := "召唤者" if context == "summon" else "自身"
	var who := own if target == "self" else "对手"
	var element := BattleRules.element_name(str(effect.get("element", "")))
	var text := ""
	match str(effect["type"]):
		"damage":
			match str(effect.get("scope", "single")):
				"all": text = "场上所有目标受到%d点%s伤害。" % [amount, element]
				"all_opponents": text = "对手及其所有召唤物受到%d点%s伤害。" % [amount, element]
				"all_enemy_summons": text = "敌方所有召唤物受到%d点%s伤害。" % [amount, element]
				_:
					match target:
						"lowest_opponent": text = "生命值最低的敌方目标受到%d点%s伤害。" % [amount, element]
						"highest_opponent": text = "生命值最高的敌方目标受到%d点%s伤害。" % [amount, element]
						"random_opponent": text = "随机1个敌方目标受到%d点%s伤害。" % [amount, element]
						"self": text = "%s受到%d点%s伤害。" % [own, amount, element]
						_:
							text = "对手受到%d点%s伤害。" % [amount, element] if context in ["summon", "artifact"] or effect.get("target") == "opponent" else "造成%d点%s伤害。" % [amount, element]
		"status": text = who + "获得" + _status_amount(effect) + "。"
		"remove_status": text = "解除%s%s。" % [who, CardKeywords.NAMES.get(effect["status"], effect["status"])]
		"heal": text = "%s恢复%d点生命。" % [who, amount]
		"heal_summon": text = "此召唤物恢复%d点生命。" % amount
		"heal_selected": text = "为自身或我方召唤物恢复%d点生命。" % amount
		"grow_summon": text = "%s增加%d点生命。" % ["该召唤物" if context == "artifact" else "我方目标召唤物", amount]
		"gain_energy": text = "%s获得%d点%s能量。" % [who, amount, element]
		"gain_random_energy": text = "%s获得%d点随机能量。" % [who, amount]
		"lose_energy": text = "%s失去%d点%s能量。" % [who, amount, element]
		"draw": text = "%s抽%d张牌。" % [who, amount]
		"contemplate": text = "%s观想%d。" % [who, amount]
		"generate_card": text = "%s随机获得%d张%s牌。" % [who, amount, element + "系" if element != "" else ""]
		"discard": text = "%s随机弃%d张手牌。" % [who, amount]
		"break_shield": text = "%s失去%d层护盾。" % [who, amount]
	if effect.has("condition"):
		var condition: Dictionary = effect["condition"]
		if condition.get("type", "") == "energy_at_least":
			text = "%s能量≥%d时，%s" % [BattleRules.element_name(condition["element"]), int(condition["amount"]), text]
	return text

static func card_text(card: Dictionary, summons: Dictionary) -> String:
	for effect in card.get("effects", []):
		if effect["type"] != "summon": continue
		var template: Dictionary = summons.get(effect["summon"], {})
		var parts: Array[String] = []
		for timing in ["on_spawn", "turn_start", "turn_end"]:
			if template.get(timing, []).is_empty(): continue
			var label: String = {"on_spawn":"出场", "turn_start":"回合开始", "turn_end":"回合结束"}[timing]
			var effects: Array = template[timing].duplicate(true)
			# Entrance effects use the normal resolver default; turn effects default to the caster.
			if timing == "on_spawn":
				for entrance: Dictionary in effects:
					if not entrance.has("target"): entrance["target"] = "opponent"
			parts.append(label + "：" + describe(effects, "summon"))
		return "".join(parts)
	return describe(card.get("effects", []))

static func artifact_text(entry: Dictionary) -> String:
	var trigger := str(entry.get("trigger", ""))
	var prefix: String = {"first_card_own_turn":"每个己方回合首次打出牌时，", "health_lost":"每次失去生命后，", "damage_received":"受到伤害时，", "first_energy_own_turn":"每个己方回合首次获得能量时，", "first_hit_enemy_turn":"每个敌方回合首次受到伤害后，", "battle_start":"开局：", "first_health_lost_own_turn":"每个己方回合首次失去生命时，", "summon":"每次召唤时，"}.get(trigger, "")
	if trigger == "element_damage":
		return "受到火伤害时，该次伤害-%d%%。" % roundi(float(entry.get("resistances", {}).get("fire", 0.0)) * 100)
	return prefix + describe(entry.get("effects", []), "artifact")
