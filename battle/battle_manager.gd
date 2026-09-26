class_name BattleManager
extends Node

signal changed
signal action_event(message: String, side: String, kind: String, element: String, amount: int)
signal summon_event(side: String, slot: int, kind: String, element: String, amount: int)

const CARD_PATH := "res://data/cards.json"
const BATTLE_PATH := "res://data/battles.json"
const SUMMON_PATH := "res://data/summons.json"
const STATUS_NAMES := {"burn":"灼伤", "poison":"中毒", "bleed":"出血", "weak":"虚弱", "vulnerable":"脆弱", "charge":"蓄力", "tenacity":"坚韧", "regen":"再生", "shield":"护盾", "lock":"封锁"}

var cards: Dictionary = {}
var summon_templates: Dictionary = {}
var decks: Array = []
var enemies: Array = []
var player := Combatant.new()
var enemy := Combatant.new()
var rng := RandomNumberGenerator.new()
var phase := "menu"
var round_number := 0
var selected_enemy_id := "ember"
var selected_deck_id := "balanced"
var battle_log: Array[String] = []
var played_cards := 0
var energy_destroyed := 0
var player_damage := 0

func _ready() -> void:
	load_content()

func load_content() -> void:
	var card_file := FileAccess.open(CARD_PATH, FileAccess.READ)
	assert(card_file != null, "Missing cards.json")
	var card_list: Array = JSON.parse_string(card_file.get_as_text())
	for card in card_list:
		cards[card["id"]] = card
	var summon_file := FileAccess.open(SUMMON_PATH, FileAccess.READ)
	assert(summon_file != null, "Missing summons.json")
	var summon_list: Array = JSON.parse_string(summon_file.get_as_text())
	for summon in summon_list:
		summon_templates[summon["id"]] = summon
	var battle_file := FileAccess.open(BATTLE_PATH, FileAccess.READ)
	assert(battle_file != null, "Missing battles.json")
	var data: Dictionary = JSON.parse_string(battle_file.get_as_text())
	decks = data["decks"]
	enemies = data["enemies"]

func find_entry(entries: Array, entry_id: String) -> Dictionary:
	for entry in entries:
		if entry["id"] == entry_id:
			return entry
	return entries[0]

func status_tooltip(status: Dictionary) -> String:
	var status_id: String = status["id"]
	var stacks := int(status["stacks"])
	var element: String = status.get("element", "")
	var name: String = STATUS_NAMES.get(status_id, status_id)
	if element != "":
		name += "·" + BattleRules.element_name(element)
	var effect := ""
	match status_id:
		"burn": effect = "回合结束时受到手牌数 × %d 的火属性伤害，再减少 1 层。火伤受五行抗性、克制和护盾影响。" % stacks
		"poison": effect = "每获得一次能量，失去 %d 点生命，再减少 1 层；一次获得多点能量只触发一次。" % stacks
		"bleed": effect = "每打出一张牌，失去 %d 点生命，再减少 1 层。" % stacks
		"weak": effect = "造成的伤害降低 %d%%，回合结束时减少 1 层。" % (stacks * 10)
		"vulnerable": effect = "受到的伤害增加 %d%%，回合结束时减少 1 层。" % (stacks * 10)
		"charge": effect = "造成的伤害增加 %d%%，回合结束时减少 1 层。" % (stacks * 10)
		"tenacity": effect = "受到的伤害降低 %d%%，回合结束时减少 1 层。" % (stacks * 10)
		"regen": effect = "回合结束时恢复 %d 点生命，再减少 1 层。" % stacks
		"shield": effect = "抵消 %d 点元素伤害。每次回合开始时层数向上取整减半。" % stacks
		"lock": effect = "不能获得该属性能量，也不能打出该属性卡。"
		_: effect = "当前效果：%d 层。" % stacks
	if status_id in ["weak", "vulnerable", "charge", "tenacity"]:
		var opposite: String = STATUS_NAMES[Combatant.OPPOSITE_STATUSES[status_id]]
		effect += "与其他伤害百分比加算。与%s按层数抵消，最多 10 层。" % opposite
	var duration := int(status.get("turns", 0))
	if duration > 0:
		effect += "\n剩余 %d 回合。" % duration
	return "%s %d 层\n%s" % [name, stacks, effect]

func start_battle(enemy_id: String, deck_id: String, seed_value: int = -1) -> void:
	selected_enemy_id = enemy_id
	selected_deck_id = deck_id
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	var enemy_info := find_entry(enemies, enemy_id)
	var deck_info := find_entry(decks, deck_id)
	player.setup("player", "云溪月", deck_info["cards"], rng)
	enemy.setup(enemy_id, enemy_info["name"], enemy_info["deck"], rng)
	phase = "battle_start"
	round_number = 0
	played_cards = 0
	energy_destroyed = 0
	player_damage = 0
	battle_log.clear()
	_report("对阵 %s · 使用「%s」牌组" % [enemy.display_name, deck_info["name"]], "system", "start")
	for i in 4:
		draw_card(player)
		draw_card(enemy)
	_start_turn(player)
	changed.emit()

func _report(message: String, side: String = "system", kind: String = "info", element: String = "", amount: int = 0) -> void:
	battle_log.push_front(message)
	if battle_log.size() > 14:
		battle_log.resize(14)
	action_event.emit(message, side, kind, element, amount)

func _side(actor: Combatant) -> String:
	return "player" if actor == player else "enemy"

func natural_weights(actor: Combatant) -> Dictionary:
	var weights := {}
	for element in BattleRules.ELEMENTS:
		weights[element] = 0
	for card_id in actor.draw_pile:
		var element: String = cards[card_id]["element"]
		if int(actor.energy[element]) < 10 and actor.status_stacks("lock", element) == 0:
			weights[element] += 1
	return weights

func generate_natural_energy(actor: Combatant) -> String:
	var weights := natural_weights(actor)
	var total := 0
	for element in BattleRules.ELEMENTS:
		total += int(weights[element])
	if total == 0:
		_report("%s 本回合没有可生成的自然能量" % actor.display_name, _side(actor), "energy")
		return ""
	var roll := rng.randi_range(1, total)
	for element in BattleRules.ELEMENTS:
		roll -= int(weights[element])
		if roll <= 0:
			var gained := actor.gain_energy(element, 1)
			_report("%s 获得 1 %s自然能量" % [actor.display_name, BattleRules.element_name(element)], _side(actor), "energy", element, 1)
			if gained > 0:
				_trigger_poison(actor)
			return element
	return ""

func draw_card(actor: Combatant) -> void:
	if actor.draw_pile.is_empty():
		actor.fatigue_level += 1
		actor.hp = maxi(0, actor.hp - actor.fatigue_level)
		_report("%s 疲劳：失去 %d 生命" % [actor.display_name, actor.fatigue_level], _side(actor), "damage", "", actor.fatigue_level)
		_check_finish()
		return
	var card_id: String = actor.draw_pile.pop_front()
	if actor.hand.size() >= 8:
		actor.discard_pile.append(card_id)
		_report("%s 手牌已满，抽到的牌进入弃牌堆" % actor.display_name, _side(actor), "draw")
	else:
		actor.hand.append(card_id)
		_report("%s 抽了 1 张牌" % actor.display_name, _side(actor), "draw")

func _start_turn(actor: Combatant) -> void:
	if actor == player:
		round_number += 1
		phase = "player_turn_start"
		_report("第 %d 回合 · 你的行动" % round_number, "system", "turn")
	else:
		phase = "enemy_turn_start"
		_report("%s 的回合" % actor.display_name, "system", "turn")
	var shield_before := actor.status_stacks("shield")
	if shield_before > 0:
		actor.halve_shield()
		var shield_after := actor.status_stacks("shield")
		if shield_after < shield_before:
			_report("%s 护盾从 %d 减为 %d" % [actor.display_name, shield_before, shield_after], _side(actor), "status_shield", "", shield_before - shield_after)
	if _check_finish():
		return
	_trigger_summons(actor, "turn_start")
	if phase in ["victory", "defeat"]:
		return
	if _check_finish():
		return
	generate_natural_energy(actor)
	if _check_finish():
		return
	draw_card(actor)
	if _check_finish():
		return
	phase = "player_action" if actor == player else "enemy_action"
	changed.emit()

func _trigger_summons(actor: Combatant, timing: String = "turn_start") -> void:
	var opponent := enemy if actor == player else player
	for slot in actor.summons.size():
		var summoned: Summon = actor.summons[slot]
		if summoned == null:
			continue
		var effects: Array = summoned.turn_start_effects if timing == "turn_start" else summoned.turn_end_effects
		for effect in effects:
			var resolved: Dictionary = effect.duplicate(true)
			if not resolved.has("target"):
				resolved["target"] = "self"
			_resolve_effect(actor, opponent, resolved, summoned.element)
			if phase in ["victory", "defeat"]:
				return

func card_target_mode(card: Dictionary) -> String:
	for effect in card["effects"]:
		if effect["type"] == "summon":
			return "slot"
		if effect["type"] == "damage":
			return "damage"
	return "none"

func valid_card_target(actor: Combatant, card: Dictionary, selection: Dictionary) -> bool:
	var mode := card_target_mode(card)
	if mode == "none":
		return true
	var kind := str(selection.get("kind", ""))
	var slot := int(selection.get("slot", -1))
	if mode == "slot":
		return kind == "slot" and slot >= 0 and slot < actor.summons.size() and actor.summons[slot] == null
	if kind == "hero":
		return true
	var opponent := enemy if actor == player else player
	return kind == "summon" and slot >= 0 and slot < opponent.summons.size() and opponent.summons[slot] != null

func preview_damage_segments(actor: Combatant, card: Dictionary, selection: Dictionary) -> Array[int]:
	var segments: Array[int] = []
	if card_target_mode(card) != "damage" or not valid_card_target(actor, card, selection):
		return segments
	var opponent := enemy if actor == player else player
	var remaining_hp := opponent.hp
	var remaining_shield := opponent.status_stacks("shield")
	if selection.get("kind", "") == "summon":
		var summoned: Summon = opponent.summons[int(selection["slot"])]
		remaining_hp = summoned.hp
	for effect in card["effects"]:
		if effect["type"] != "damage":
			continue
		var raw := 0
		if selection.get("kind", "") == "summon":
			raw = BattleRules.summon_damage(int(effect["amount"]), actor)
		else:
			raw = int(BattleRules.damage_breakdown(opponent, int(effect["amount"]), str(effect.get("element", card["element"])), actor)["raw"])
			var absorbed := mini(raw, remaining_shield)
			remaining_shield -= absorbed
			raw -= absorbed
		var dealt := mini(raw, remaining_hp)
		remaining_hp -= dealt
		segments.append(dealt)
	return segments

func play_player_card(index: int, selection: Dictionary = {}) -> bool:
	if phase != "player_action":
		return false
	return _play_card(player, enemy, index, selection)

func _play_card(actor: Combatant, target: Combatant, index: int, selection: Dictionary = {}) -> bool:
	if index < 0 or index >= actor.hand.size():
		return false
	var card_id := actor.hand[index]
	var card: Dictionary = cards[card_id]
	if not actor.can_pay(card) or not valid_card_target(actor, card, selection):
		return false
	actor.hand.remove_at(index)
	actor.lose_energy(card["element"], int(card["cost"]))
	_report("%s 使用「%s」" % [actor.display_name, card["name"]], _side(actor), "play", card["element"], int(card["cost"]))
	_trigger_bleed(actor)
	for effect in card["effects"]:
		if phase == "victory" or phase == "defeat":
			break
		_resolve_effect(actor, target, effect, card["element"], selection)
	actor.discard_pile.append(card_id)
	played_cards += 1
	_check_finish()
	changed.emit()
	return true

func _resolve_effect(actor: Combatant, opponent: Combatant, effect: Dictionary, card_element: String, selection: Dictionary = {}) -> void:
	var target: Combatant = actor if effect.get("target", "opponent") == "self" else opponent
	var amount := int(effect.get("amount", 0))
	match effect["type"]:
		"damage":
			var attack_element := str(effect.get("element", card_element))
			if selection.get("kind", "hero") == "summon":
				apply_summon_damage(actor, opponent, int(selection["slot"]), amount, attack_element)
			else:
				apply_damage(actor, opponent, amount, attack_element)
		"summon":
			var slot := int(selection["slot"])
			var template: Dictionary = summon_templates[effect["summon"]]
			var summoned := Summon.new()
			summoned.setup(template)
			actor.summons[slot] = summoned
			_report("%s 在槽位 %d 召唤%s" % [actor.display_name, slot + 1, summoned.display_name], _side(actor), "summon", summoned.element, 1)
			summon_event.emit(_side(actor), slot, "spawn", summoned.element, 1)
		"heal":
			var actual := mini(amount, target.max_hp - target.hp)
			target.hp += actual
			_report("%s 恢复 %d 生命" % [target.display_name, actual], _side(target), "heal", card_element, actual)
		"draw":
			for i in amount:
				if phase == "victory" or phase == "defeat":
					break
				draw_card(target)
		"gain_energy":
			var gained := target.gain_energy(effect["element"], amount)
			_report("%s 获得 %d %s能量" % [target.display_name, gained, BattleRules.element_name(effect["element"])], _side(target), "energy", effect["element"], gained)
			if gained > 0:
				_trigger_poison(target)
		"lose_energy":
			var lost := target.lose_energy(effect["element"], amount)
			if actor == player:
				energy_destroyed += lost
			_report("%s 失去 %d %s能量" % [target.display_name, lost, BattleRules.element_name(effect["element"])], _side(target), "energy_loss", effect["element"], lost)
		"convert_energy":
			var from_element: String = effect["from"]
			if int(target.energy[from_element]) >= amount:
				target.lose_energy(from_element, amount)
				var gained := target.gain_energy(effect["to"], int(effect["gain"]))
				_report("%s 将 %d %s转为 %d %s" % [target.display_name, amount, BattleRules.element_name(from_element), gained, BattleRules.element_name(effect["to"])], _side(target), "energy", effect["to"], gained)
				if gained > 0:
					_trigger_poison(target)
		"status":
			var status_id: String = effect["status"]
			var element: String = effect.get("element", "")
			target.add_status(status_id, int(effect["stacks"]), int(effect.get("turns", 0)), element)
			var detail := " · %s" % BattleRules.element_name(element) if element != "" else ""
			_report("%s 获得 %d 层%s%s" % [target.display_name, int(effect["stacks"]), STATUS_NAMES.get(status_id, status_id), detail], _side(target), "status_" + status_id, card_element, int(effect["stacks"]))
		"discard":
			for i in amount:
				if target.hand.is_empty():
					break
				var random_index := rng.randi_range(0, target.hand.size() - 1)
				var lost_card: String = target.hand.pop_at(random_index)
				target.discard_pile.append(lost_card)
				_report("%s 被弃掉 1 张手牌" % target.display_name, _side(target), "discard")

func apply_damage(source: Combatant, target: Combatant, base_amount: int, element: String) -> int:
	var breakdown := BattleRules.damage_breakdown(target, base_amount, element, source)
	var raw: int = breakdown["raw"]
	var shielded: int = breakdown["shield"]
	var dealt := mini(target.hp, int(breakdown["hp"]))
	if shielded > 0:
		for status in target.statuses:
			if status["id"] == "shield":
				status["stacks"] = maxi(0, int(status["stacks"]) - shielded)
				break
		for i in range(target.statuses.size() - 1, -1, -1):
			if target.statuses[i]["id"] == "shield" and int(target.statuses[i]["stacks"]) == 0:
				target.statuses.remove_at(i)
	target.hp = maxi(0, target.hp - dealt)
	if source == player:
		player_damage += dealt
	var note := " · 护盾抵消 %d" % shielded if shielded > 0 else ""
	if raw == 0:
		note = " · 免疫"
	elif float(breakdown["multiplier"]) > 1.0:
		note += " · 克制"
	elif float(breakdown["multiplier"]) < 1.0:
		note += " · 抵抗"
	_report("%s 受到 %d 点%s伤害%s" % [target.display_name, dealt, BattleRules.element_name(element), note], _side(target), "damage", element, dealt)
	_check_finish()
	return dealt

func apply_summon_damage(source: Combatant, owner: Combatant, slot: int, base_amount: int, element: String) -> int:
	if slot < 0 or slot >= owner.summons.size() or owner.summons[slot] == null:
		return 0
	var summoned: Summon = owner.summons[slot]
	var dealt := mini(summoned.hp, BattleRules.summon_damage(base_amount, source))
	summoned.hp -= dealt
	if source == player:
		player_damage += dealt
	_report("%s 受到 %d 点%s伤害" % [summoned.display_name, dealt, BattleRules.element_name(element)], _side(owner), "summon_damage", element, dealt)
	summon_event.emit(_side(owner), slot, "damage", element, dealt)
	if summoned.hp <= 0:
		owner.summons[slot] = null
		_report("%s 被摧毁，槽位 %d 空出" % [summoned.display_name, slot + 1], _side(owner), "summon_destroy", element)
		summon_event.emit(_side(owner), slot, "destroy", element, 0)
	return dealt

func _end_turn(actor: Combatant) -> void:
	var burn := actor.status_stacks("burn")
	if burn > 0:
		var amount := actor.hand.size() * burn
		if amount > 0:
			apply_damage(null, actor, amount, "fire")
		actor.decay_status("burn")
	if phase in ["victory", "defeat"]:
		changed.emit()
		return
	var regen := actor.status_stacks("regen")
	if regen > 0:
		var healed := mini(actor.max_hp - actor.hp, regen)
		actor.hp += healed
		if healed > 0:
			_report("%s 再生，恢复 %d 生命" % [actor.display_name, healed], _side(actor), "heal", "wood", healed)
		actor.decay_status("regen")
	actor.decay_status("weak")
	actor.decay_status("vulnerable")
	actor.decay_status("charge")
	actor.decay_status("tenacity")
	actor.tick_status_durations()
	_trigger_summons(actor, "turn_end")
	if phase in ["victory", "defeat"]:
		return
	_check_finish()
	changed.emit()

func _trigger_poison(actor: Combatant) -> void:
	var stacks := actor.status_stacks("poison")
	if stacks <= 0:
		return
	actor.hp = maxi(0, actor.hp - stacks)
	actor.decay_status("poison")
	_report("%s 中毒：失去 %d 生命" % [actor.display_name, stacks], _side(actor), "damage", "", stacks)
	_check_finish()

func _trigger_bleed(actor: Combatant) -> void:
	var stacks := actor.status_stacks("bleed")
	if stacks <= 0:
		return
	actor.hp = maxi(0, actor.hp - stacks)
	actor.decay_status("bleed")
	_report("%s 出血：失去 %d 生命" % [actor.display_name, stacks], _side(actor), "damage", "", stacks)
	_check_finish()

func end_player_turn() -> void:
	if phase != "player_action":
		return
	phase = "player_turn_end"
	_end_turn(player)
	if phase != "victory" and phase != "defeat":
		_start_turn(enemy)

func peek_enemy_action() -> Dictionary:
	if phase != "enemy_action":
		return {"index": -1, "target": {}}
	return _choose_enemy_action()

func peek_enemy_card_index() -> int:
	return int(peek_enemy_action()["index"])

func enemy_step(chosen_index: int = -2, selection: Dictionary = {}) -> bool:
	if phase != "enemy_action":
		return false
	if chosen_index == -2:
		var action := _choose_enemy_action()
		chosen_index = int(action["index"])
		selection = action["target"]
	var index := chosen_index
	if index < 0:
		phase = "enemy_turn_end"
		_end_turn(enemy)
		if phase != "victory" and phase != "defeat":
			_start_turn(player)
		return false
	if selection.is_empty() and index < enemy.hand.size():
		var card: Dictionary = cards[enemy.hand[index]]
		match card_target_mode(card):
			"damage": selection = {"kind": "hero"}
			"slot": selection = {"kind": "slot", "slot": enemy.first_free_summon_slot()}
	_play_card(enemy, player, index, selection)
	return phase == "enemy_action"

func _choose_enemy_action() -> Dictionary:
	var best_action := {"index": -1, "target": {}}
	var best_score := 3.0
	for i in enemy.hand.size():
		var card: Dictionary = cards[enemy.hand[i]]
		if not enemy.can_pay(card):
			continue
		var candidates: Array[Dictionary] = [{}]
		match card_target_mode(card):
			"damage":
				candidates = [{"kind": "hero"}]
				for slot in player.summons.size():
					if player.summons[slot] != null:
						candidates.append({"kind": "summon", "slot": slot})
			"slot":
				candidates = []
				for slot in enemy.summons.size():
					if enemy.summons[slot] == null:
						candidates.append({"kind": "slot", "slot": slot})
		for selection in candidates:
			var score := _enemy_action_score(card, selection)
			score -= float(card["cost"]) * 0.8
			score += rng.randf_range(-3.0, 3.0)
			if score > best_score:
				best_score = score
				best_action = {"index": i, "target": selection}
	return best_action

func _enemy_action_score(card: Dictionary, selection: Dictionary) -> float:
	var score := 0.0
	for effect in card["effects"]:
		match effect["type"]:
			"damage":
				if selection.get("kind", "hero") == "summon":
					var summoned: Summon = player.summons[int(selection["slot"])]
					var dealt := mini(summoned.hp, BattleRules.summon_damage(int(effect["amount"]), enemy))
					score += float(dealt) * 1.2 + (9.0 if dealt >= summoned.hp else 0.0)
				else:
					var preview := BattleRules.damage_breakdown(player, int(effect["amount"]), effect["element"], enemy)
					score += float(preview["hp"]) + float(preview["shield"]) * 0.65
			"summon":
				var template: Dictionary = summon_templates[effect["summon"]]
				score += 6.0
				for turn_effect in template.get("turn_start", []) + template.get("turn_end", []):
					match turn_effect["type"]:
						"gain_energy":
							var produced := str(turn_effect["element"])
							score += 5.0 if int(enemy.energy[produced]) < 8 else 0.0
						"draw": score += 5.0 if enemy.hand.size() < 7 else 1.0
						"heal": score += 4.0 if enemy.hp < enemy.max_hp - 6 else 2.0
						"damage": score += 5.0
						"status": score += 4.0
			"heal": score += mini(enemy.max_hp - enemy.hp, int(effect["amount"])) * 0.9
			"gain_energy": score += mini(10 - int(enemy.energy[effect["element"]]), int(effect["amount"])) * 3.5
			"lose_energy": score += mini(int(player.energy[effect["element"]]), int(effect["amount"])) * 6.0
			"convert_energy": score += 7.0
			"draw": score += 4.0 if not enemy.draw_pile.is_empty() else -5.0
			"discard": score += 8.0 if not player.hand.is_empty() else 0.0
			"status":
				match effect["status"]:
					"burn": score += 9.0 if player.status_stacks("burn") < 3 else 2.0
					"vulnerable": score += 10.0 if player.status_stacks("vulnerable") == 0 else 2.0
					"charge": score += 8.0 if enemy.status_stacks("charge") < 3 else 3.0
					"tenacity": score += 8.0 if enemy.status_stacks("tenacity") < 3 else 3.0
					"shield": score += 7.0 if enemy.status_stacks("shield") < 10 else 1.0
					"regen": score += 7.0 if enemy.hp < 75 else 1.0
					"lock": score += 9.0 if player.status_stacks("lock", effect["element"]) == 0 else 1.0
	return score

func _check_finish() -> bool:
	if enemy.hp <= 0:
		phase = "victory"
		_report("胜利！%s 已被击败" % enemy.display_name, "system", "victory")
		changed.emit()
		return true
	if player.hp <= 0:
		phase = "defeat"
		_report("败北。五行失衡，请再试一次", "system", "defeat")
		changed.emit()
		return true
	return false
