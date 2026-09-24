class_name BattleManager
extends Node

signal changed
signal action_event(message: String, side: String, kind: String, element: String, amount: int)

const CARD_PATH := "res://data/cards.json"
const BATTLE_PATH := "res://data/battles.json"
const STATUS_NAMES := {"burn":"灼烧", "shield":"护盾", "vulnerable":"易伤", "regen":"再生", "lock":"封锁"}

var cards: Dictionary = {}
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
			actor.gain_energy(element, 1)
			_report("%s 获得 1 %s自然能量" % [actor.display_name, BattleRules.element_name(element)], _side(actor), "energy", element, 1)
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
	var regen := actor.status_stacks("regen")
	if regen > 0:
		var healed := mini(actor.max_hp - actor.hp, regen * 3)
		actor.hp += healed
		if healed > 0:
			_report("%s 再生，恢复 %d 生命" % [actor.display_name, healed], _side(actor), "heal", "wood", healed)
	if _check_finish():
		return
	generate_natural_energy(actor)
	draw_card(actor)
	if _check_finish():
		return
	phase = "player_action" if actor == player else "enemy_action"
	changed.emit()

func play_player_card(index: int) -> bool:
	if phase != "player_action":
		return false
	return _play_card(player, enemy, index)

func _play_card(actor: Combatant, target: Combatant, index: int) -> bool:
	if index < 0 or index >= actor.hand.size():
		return false
	var card_id := actor.hand[index]
	var card: Dictionary = cards[card_id]
	if not actor.can_pay(card):
		return false
	actor.hand.remove_at(index)
	actor.lose_energy(card["element"], int(card["cost"]))
	_report("%s 使用「%s」" % [actor.display_name, card["name"]], _side(actor), "play", card["element"], int(card["cost"]))
	for effect in card["effects"]:
		if phase == "victory" or phase == "defeat":
			break
		_resolve_effect(actor, target, effect, card["element"])
	actor.discard_pile.append(card_id)
	played_cards += 1
	_check_finish()
	changed.emit()
	return true

func _resolve_effect(actor: Combatant, opponent: Combatant, effect: Dictionary, card_element: String) -> void:
	var target: Combatant = actor if effect.get("target", "opponent") == "self" else opponent
	var amount := int(effect.get("amount", 0))
	match effect["type"]:
		"damage":
			apply_damage(actor, opponent, amount, str(effect.get("element", card_element)))
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
		"status":
			var status_id: String = effect["status"]
			var element: String = effect.get("element", "")
			target.add_status(status_id, int(effect["stacks"]), int(effect["turns"]), element)
			var detail := " · %s" % BattleRules.element_name(element) if element != "" else ""
			_report("%s 获得 %s%s ×%d" % [target.display_name, STATUS_NAMES[status_id], detail, int(effect["stacks"])], _side(target), "status_" + status_id, card_element, int(effect["stacks"]))
		"discard":
			for i in amount:
				if target.hand.is_empty():
					break
				var random_index := rng.randi_range(0, target.hand.size() - 1)
				var lost_card: String = target.hand.pop_at(random_index)
				target.discard_pile.append(lost_card)
				_report("%s 被弃掉 1 张手牌" % target.display_name, _side(target), "discard")

func apply_damage(source: Combatant, target: Combatant, base_amount: int, element: String) -> int:
	var breakdown := BattleRules.damage_breakdown(target, base_amount, element)
	var raw: int = breakdown["raw"]
	var shielded: int = breakdown["shield"]
	var dealt: int = breakdown["hp"]
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

func _end_turn(actor: Combatant) -> void:
	var burn := actor.status_stacks("burn")
	if burn > 0:
		var amount := burn * 2
		actor.hp = maxi(0, actor.hp - amount)
		_report("%s 灼烧：失去 %d 生命" % [actor.display_name, amount], _side(actor), "damage", "fire", amount)
	actor.tick_status_durations()
	_check_finish()
	changed.emit()

func end_player_turn() -> void:
	if phase != "player_action":
		return
	phase = "player_turn_end"
	_end_turn(player)
	if phase != "victory" and phase != "defeat":
		_start_turn(enemy)

func peek_enemy_card_index() -> int:
	if phase != "enemy_action":
		return -1
	return _choose_enemy_card()

func enemy_step(chosen_index: int = -2) -> bool:
	if phase != "enemy_action":
		return false
	var index := _choose_enemy_card() if chosen_index == -2 else chosen_index
	if index < 0:
		phase = "enemy_turn_end"
		_end_turn(enemy)
		if phase != "victory" and phase != "defeat":
			_start_turn(player)
		return false
	_play_card(enemy, player, index)
	return phase == "enemy_action"

func _choose_enemy_card() -> int:
	var best_index := -1
	var best_score := 3.0
	for i in enemy.hand.size():
		var card: Dictionary = cards[enemy.hand[i]]
		if not enemy.can_pay(card):
			continue
		var score := 0.0
		for effect in card["effects"]:
			match effect["type"]:
				"damage":
					var preview := BattleRules.damage_breakdown(player, int(effect["amount"]), effect["element"])
					score += float(preview["hp"]) + float(preview["shield"]) * 0.65
				"heal":
					score += mini(enemy.max_hp - enemy.hp, int(effect["amount"])) * 0.9
				"gain_energy":
					score += mini(10 - int(enemy.energy[effect["element"]]), int(effect["amount"])) * 3.5
				"lose_energy":
					score += mini(int(player.energy[effect["element"]]), int(effect["amount"])) * 6.0
				"convert_energy":
					score += 7.0
				"draw":
					score += 4.0 if not enemy.draw_pile.is_empty() else -5.0
				"discard":
					score += 8.0 if not player.hand.is_empty() else 0.0
				"status":
					match effect["status"]:
						"burn": score += 9.0 if player.status_stacks("burn") < 3 else 2.0
						"vulnerable": score += 10.0 if player.status_stacks("vulnerable") == 0 else 2.0
						"shield": score += 7.0 if enemy.status_stacks("shield") < 10 else 1.0
						"regen": score += 7.0 if enemy.hp < 75 else 1.0
						"lock": score += 9.0 if player.status_stacks("lock", effect["element"]) == 0 else 1.0
		score -= float(card["cost"]) * 0.8
		score += rng.randf_range(-3.0, 3.0)
		if score > best_score:
			best_score = score
			best_index = i
	return best_index

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
