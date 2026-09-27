class_name BattleManager
extends Node

signal changed
signal action_event(message: String, side: String, kind: String, element: String, amount: int)
# Emitted before removal so the presenter can retain the exact hand card,
# including duplicate copies and discards after the played card leaves the hand.
signal hand_card_removed(side: String, card_id: String, index: int, reason: String)
signal summon_event(side: String, slot: int, kind: String, element: String, amount: int, matchup: String)
signal summon_triggered(side: String, slot: int, timing: String, effect: Dictionary)

const CARD_PATH := "res://data/cards.json"
const BATTLE_PATH := "res://data/battles.json"
const SUMMON_PATH := "res://data/summons.json"
const STATUS_NAMES := CardKeywords.NAMES
const FINISHED_PHASES := ["victory", "defeat", "draw"]
# Both sides use slots 0 / 1 / 2 for the top / middle / bottom of the battlefield.
const SUMMON_TRIGGER_ORDER := [0, 1, 2]
const RANDOM_DECK_SIZE := 25
const RANDOM_DECK_COPY_LIMIT := 3
const RANDOM_DECK_MAX_COST := 45
const RANDOM_DECK_MIN_LOW_COST := 8

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
var battle_generation := 0
# Optional UI coroutine: cast before resolving, then wait for the feedback.
# Without a presenter, rule simulations resolve immediately.
var summon_presenter: Callable

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
	var effect := CardKeywords.status_description(status_id, str(stacks), element)
	var duration := int(status.get("turns", 0))
	if duration > 0:
		effect += "\n剩余 %d 回合。" % duration
	return "%s %d 层\n%s" % [name, stacks, effect]

func start_battle(enemy_id: String, deck_id: String, seed_value: int = -1) -> void:
	battle_generation += 1
	var generation := battle_generation
	selected_enemy_id = enemy_id
	selected_deck_id = deck_id
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	var enemy_info := find_entry(enemies, enemy_id)
	var deck_info := find_entry(decks, deck_id)
	var player_deck: Array = generate_random_deck() if deck_id == "random" else deck_info["cards"]
	var enemy_deck: Array = generate_random_deck() if deck_id == "random" else enemy_info["deck"]
	player.max_hp = 80 if deck_id == "random" else 100
	enemy.max_hp = 80 if deck_id == "random" else 100
	player.setup("player", "云溪月", player_deck, rng)
	enemy.setup(enemy_id, enemy_info["name"], enemy_deck, rng)
	phase = "battle_start"
	round_number = 0
	played_cards = 0
	energy_destroyed = 0
	player_damage = 0
	battle_log.clear()
	_report("对阵 %s · 使用「%s」牌组" % [enemy.display_name, "随机牌组" if deck_id == "random" else deck_info["name"]], "system", "start")
	for i in 4:
		draw_card(player)
		draw_card(enemy)
	await _start_turn(player)
	if generation == battle_generation:
		changed.emit()

func valid_random_deck(deck: Array) -> bool:
	if deck.size() != RANDOM_DECK_SIZE: return false
	var counts := {}
	var total := 0
	var low_cost := 0
	for id in deck:
		if not cards.has(id): return false
		counts[id] = int(counts.get(id, 0)) + 1
		if counts[id] > RANDOM_DECK_COPY_LIMIT: return false
		var cost := int(cards[id]["cost"])
		total += cost
		if cost <= 1: low_cost += 1
	return total <= RANDOM_DECK_MAX_COST and low_cost >= RANDOM_DECK_MIN_LOW_COST

func generate_random_deck() -> Array[String]:
	var pool: Array[String] = []
	for id in cards:
		for copy in RANDOM_DECK_COPY_LIMIT: pool.append(id)
	assert(pool.size() >= RANDOM_DECK_SIZE, "Card pool cannot fill a random deck")
	for attempt in 256:
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := pool[i]
			pool[i] = pool[j]
			pool[j] = swap
		var candidate: Array[String] = pool.slice(0, RANDOM_DECK_SIZE)
		if valid_random_deck(candidate): return candidate
	# A finite fallback avoids endless rerolls if a future pool is mostly expensive.
	# The last shuffle keeps equal-cost choices random.
	pool.sort_custom(func(a: String, b: String): return int(cards[a]["cost"]) < int(cards[b]["cost"]))
	var cheapest: Array[String] = pool.slice(0, RANDOM_DECK_SIZE)
	assert(valid_random_deck(cheapest), "Card pool cannot satisfy random deck cost constraints")
	return cheapest

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
	var generation := battle_generation
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
	await _trigger_summons(actor, "turn_start")
	if generation != battle_generation or phase in ["menu", "victory", "defeat", "draw"]:
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
	var generation := battle_generation
	var opponent := enemy if actor == player else player
	for slot in SUMMON_TRIGGER_ORDER:
		var summoned: Summon = actor.summons[slot]
		if summoned == null:
			continue
		var effects: Array = summoned.turn_start_effects if timing == "turn_start" else summoned.turn_end_effects
		for effect in effects:
			var resolved: Dictionary = effect.duplicate(true)
			if not resolved.has("target"):
				resolved["target"] = "self"
			summon_triggered.emit(_side(actor), slot, timing, resolved)
			if summon_presenter.is_valid():
				await summon_presenter.call(_side(actor), slot, summoned, resolved, "cast")
			if generation != battle_generation or phase in ["menu", "victory", "defeat", "draw"]:
				return
			if actor.summons[slot] != summoned:
				break
			_resolve_effect(actor, opponent, resolved, summoned.element)
			if summon_presenter.is_valid():
				changed.emit()
				await summon_presenter.call(_side(actor), slot, summoned, resolved, "resolved")
			if generation != battle_generation or phase in ["menu", "victory", "defeat", "draw"]:
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
	var side := str(selection.get("side", "enemy" if actor == player else "player"))
	if side not in damage_target_sides(actor, card): return false
	var owner := player if side == "player" else enemy
	if kind == "hero": return owner.hp > 0
	return kind == "summon" and slot >= 0 and slot < owner.summons.size() and owner.summons[slot] != null

func damage_target_sides(actor: Combatant, card: Dictionary) -> Array[String]:
	for effect in card["effects"]:
		if effect.get("scope", "single") == "all": return ["player", "enemy"]
	return ["enemy" if actor == player else "player"]

# A segment takes its damage snapshot before applying any hit. An area segment
# therefore shares one attack bonus even when the caster is among its targets.
func _damage_plan(actor: Combatant, opponent: Combatant, effect: Dictionary, card_element: String, selection: Dictionary) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var scope := str(effect.get("scope", "single"))
	if scope in ["all", "all_opponents"]:
		var owners: Array[Combatant] = [opponent]
		if scope == "all": owners.append(actor)
		for owner in owners:
			targets.append({"owner": owner, "kind": "hero"})
			for slot in owner.summons.size():
				if owner.summons[slot] != null: targets.append({"owner": owner, "kind": "summon", "slot": slot})
	else:
		var own_side := "player" if actor.id == "player" else "enemy"
		var owner := actor if selection.get("side", "") == own_side else opponent
		if selection.get("kind", "hero") != "summon" or (int(selection.get("slot", -1)) >= 0 and int(selection["slot"]) < owner.summons.size() and owner.summons[int(selection["slot"])] != null):
			targets.append({"owner": owner, "kind": selection.get("kind", "hero"), "slot": int(selection.get("slot", -1))})
	var amount := int(effect["amount"])
	var element := str(effect.get("element", card_element))
	for hit in targets:
		var owner: Combatant = hit["owner"]
		if hit["kind"] == "hero":
			hit["breakdown"] = BattleRules.damage_breakdown(owner, amount, element, actor)
		else:
			hit["raw"] = BattleRules.summon_damage(amount, actor, owner.summons[int(hit["slot"])].element, element)
	return targets

func _damage_snapshot(actor: Combatant) -> Combatant:
	var copy := Combatant.new()
	copy.id = actor.id
	copy.hp = actor.hp
	copy.energy = actor.energy.duplicate()
	copy.statuses = actor.statuses.duplicate(true)
	copy.summons = [null, null, null]
	for slot in actor.summons.size():
		var summoned: Summon = actor.summons[slot]
		if summoned == null: continue
		var cloned := Summon.new()
		cloned.element = summoned.element
		cloned.hp = summoned.hp
		copy.summons[slot] = cloned
	return copy

func _consume_attack_statuses(source: Combatant) -> void:
	if source == null: return
	source.decay_status("strong_attack")
	source.decay_status("weak_attack")

func _consume_defense_statuses(target: Combatant) -> void:
	target.decay_status("strong_defense")
	target.decay_status("weak_defense")

func _absorb_shield(target: Combatant, absorbed: int) -> void:
	for status in target.statuses:
		if status["id"] == "shield":
			status["stacks"] = maxi(0, int(status["stacks"]) - absorbed)
			break
	for i in range(target.statuses.size() - 1, -1, -1):
		if target.statuses[i]["id"] == "shield" and int(target.statuses[i]["stacks"]) == 0: target.statuses.remove_at(i)

func preview_damage_segments(actor: Combatant, card: Dictionary, selection: Dictionary) -> Array[int]:
	var segments: Array[int] = []
	if card_target_mode(card) != "damage" or not valid_card_target(actor, card, selection):
		return segments
	var source := _damage_snapshot(actor)
	var opponent := _damage_snapshot(enemy if actor == player else player)
	# Payment changes the caster's resistance when a spell also hits its own side.
	source.lose_energy(card["element"], int(card.get("cost", 0)))
	source.hp = maxi(0, source.hp - source.status_stacks("bleed"))
	if source.hp <= 0: return segments
	var own_side := _side(actor)
	var selected_owner := source if selection.get("side", "") == own_side else opponent
	for effect in card["effects"]:
		if effect["type"] != "damage":
			continue
		var plan := _damage_plan(source, opponent, effect, card["element"], selection)
		var selected_damage := 0
		for hit in plan:
			var owner: Combatant = hit["owner"]
			var dealt := 0
			if hit["kind"] == "hero":
				dealt = mini(owner.hp, int(hit["breakdown"]["hp"]))
				_absorb_shield(owner, int(hit["breakdown"]["shield"]))
				owner.hp -= dealt
				_consume_defense_statuses(owner)
			else:
				var summoned: Summon = owner.summons[int(hit["slot"])]
				dealt = mini(summoned.hp, int(hit["raw"]))
				summoned.hp -= dealt
				if summoned.hp == 0: owner.summons[int(hit["slot"])] = null
			if owner == selected_owner and hit["kind"] == selection.get("kind", "hero") and (hit["kind"] == "hero" or int(hit["slot"]) == int(selection["slot"])):
				selected_damage = dealt
		if not plan.is_empty(): _consume_attack_statuses(source)
		# Keep zero entries for later hits whose chosen summon has already died.
		segments.append(selected_damage)
		if source.hp <= 0 or opponent.hp <= 0: break
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
	hand_card_removed.emit(_side(actor), card_id, index, "play")
	actor.hand.remove_at(index)
	actor.lose_energy(card["element"], int(card["cost"]))
	_report("%s 使用「%s」" % [actor.display_name, card["name"]], _side(actor), "play", card["element"], int(card["cost"]))
	_trigger_bleed(actor)
	for effect in card["effects"]:
		if phase in FINISHED_PHASES:
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
			var plan := _damage_plan(actor, opponent, effect, card_element, selection)
			for hit in plan:
				if hit["kind"] == "hero":
					_apply_hero_damage(actor, hit["owner"], hit["breakdown"], attack_element)
				else:
					_apply_summon_hit(actor, hit["owner"], int(hit["slot"]), int(hit["raw"]), attack_element)
			if not plan.is_empty(): _consume_attack_statuses(actor)
			_check_finish()
		"summon":
			var slot := int(selection["slot"])
			var template: Dictionary = summon_templates[effect["summon"]]
			var summoned := Summon.new()
			summoned.setup(template)
			actor.summons[slot] = summoned
			_report("%s 在槽位 %d 召唤%s" % [actor.display_name, slot + 1, summoned.display_name], _side(actor), "summon", summoned.element, 1)
			summon_event.emit(_side(actor), slot, "spawn", summoned.element, 1, "")
		"heal":
			var actual := mini(amount, target.max_hp - target.hp)
			target.hp += actual
			_report("%s 恢复 %d 生命" % [target.display_name, actual], _side(target), "heal", card_element, actual)
		"draw":
			for i in amount:
				if phase in FINISHED_PHASES:
					break
				draw_card(target)
		"gain_energy":
			var gained := target.gain_energy(effect["element"], amount)
			_report("%s 获得 %d %s能量" % [target.display_name, gained, BattleRules.element_name(effect["element"])], _side(target), "energy", effect["element"], gained)
			if gained > 0:
				_trigger_poison(target)
		"gain_random_energy":
			var available: Array[String] = []
			for element in BattleRules.ELEMENTS:
				if int(target.energy[element]) < 10 and target.status_stacks("lock", element) == 0:
					available.append(element)
			if available.is_empty():
				_report("%s 没有可获得的能量" % target.display_name, _side(target), "energy")
			else:
				var element := available[rng.randi_range(0, available.size() - 1)]
				_resolve_effect(actor, opponent, {"type": "gain_energy", "target": effect.get("target", "self"), "element": element, "amount": amount}, card_element)
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
		"remove_status":
			var status_id: String = effect["status"]
			var removed := target.status_stacks(status_id)
			target.remove_status(status_id)
			_report("%s 解除%s" % [target.display_name, STATUS_NAMES.get(status_id, status_id)], _side(target), "status_remove", card_element, removed)
		"discard":
			for i in amount:
				if target.hand.is_empty():
					break
				var random_index := rng.randi_range(0, target.hand.size() - 1)
				hand_card_removed.emit(_side(target), target.hand[random_index], random_index, "discard")
				var lost_card: String = target.hand.pop_at(random_index)
				target.discard_pile.append(lost_card)
				_report("%s 被弃掉 1 张手牌" % target.display_name, _side(target), "discard")

func apply_damage(source: Combatant, target: Combatant, base_amount: int, element: String) -> int:
	var breakdown := BattleRules.damage_breakdown(target, base_amount, element, source)
	var dealt := _apply_hero_damage(source, target, breakdown, element)
	_consume_attack_statuses(source)
	_check_finish()
	return dealt

func _apply_hero_damage(source: Combatant, target: Combatant, breakdown: Dictionary, element: String) -> int:
	var raw: int = breakdown["raw"]
	var shielded: int = breakdown["shield"]
	var dealt := mini(target.hp, int(breakdown["hp"]))
	_absorb_shield(target, shielded)
	_consume_defense_statuses(target)
	target.hp = maxi(0, target.hp - dealt)
	if source == player and target != player:
		player_damage += dealt
	var note := " · 护盾抵消 %d" % shielded if shielded > 0 else ""
	if raw == 0:
		note = " · 免疫"
	elif float(breakdown["multiplier"]) > 1.0:
		note += " · 克制"
	elif float(breakdown["multiplier"]) < 1.0:
		note += " · 抵抗"
	_report("%s 受到 %d 点%s伤害%s" % [target.display_name, dealt, BattleRules.element_name(element), note], _side(target), "damage", element, dealt)
	return dealt

func apply_summon_damage(source: Combatant, owner: Combatant, slot: int, base_amount: int, element: String) -> int:
	if slot < 0 or slot >= owner.summons.size() or owner.summons[slot] == null:
		return 0
	var summoned: Summon = owner.summons[slot]
	var dealt := _apply_summon_hit(source, owner, slot, BattleRules.summon_damage(base_amount, source, summoned.element, element), element)
	_consume_attack_statuses(source)
	return dealt

func _apply_summon_hit(source: Combatant, owner: Combatant, slot: int, raw: int, element: String) -> int:
	var summoned: Summon = owner.summons[slot]
	var dealt := mini(summoned.hp, raw)
	summoned.hp -= dealt
	if source == player and owner != player:
		player_damage += dealt
	var matchup := BattleRules.summon_matchup(summoned.element, element)
	var note := " · " + matchup if matchup != "" else ""
	_report("%s 受到 %d 点%s伤害%s" % [summoned.display_name, dealt, BattleRules.element_name(element), note], _side(owner), "summon_damage", element, dealt)
	summon_event.emit(_side(owner), slot, "damage", element, dealt, matchup)
	if summoned.hp <= 0:
		owner.summons[slot] = null
		_report("%s 被摧毁，槽位 %d 空出" % [summoned.display_name, slot + 1], _side(owner), "summon_destroy", element)
		summon_event.emit(_side(owner), slot, "destroy", element, 0, "")
	return dealt

func _end_turn(actor: Combatant) -> void:
	var generation := battle_generation
	var burn := actor.status_stacks("burn")
	if burn > 0:
		var amount := actor.hand.size() * burn
		if amount > 0:
			apply_damage(null, actor, amount, "fire")
		actor.decay_status("burn")
	if phase in FINISHED_PHASES:
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
	await _trigger_summons(actor, "turn_end")
	if generation != battle_generation or phase in ["menu", "victory", "defeat", "draw"]:
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
	var generation := battle_generation
	changed.emit()
	await _end_turn(player)
	if generation == battle_generation and phase not in ["menu", "victory", "defeat", "draw"]:
		await _start_turn(enemy)

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
		var generation := battle_generation
		changed.emit()
		await _end_turn(enemy)
		if generation == battle_generation and phase not in ["menu", "victory", "defeat", "draw"]:
			await _start_turn(player)
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
	var scored_damage := false
	for effect in card["effects"]:
		match effect["type"]:
			"damage":
				if scored_damage: continue
				scored_damage = true
				if effect.get("scope", "single") in ["all_opponents", "all"]:
					var sides: Array[String] = ["player"]
					if effect.get("scope") == "all": sides.append("enemy")
					var self_lethal := false
					var opponent_lethal := false
					for side in sides:
						var owner := player if side == "player" else enemy
						var sign_value := 1.0 if owner == player else -1.0
						var hp_damage := 0
						for damage in preview_damage_segments(enemy, card, {"kind":"hero", "side":side}): hp_damage += damage
						score += sign_value * (float(hp_damage) + float(mini(owner.status_stacks("shield"), int(effect["amount"]))) * 0.65)
						if hp_damage >= owner.hp:
							if owner == enemy: self_lethal = true
							else: opponent_lethal = true
						for slot in owner.summons.size():
							var summoned: Summon = owner.summons[slot]
							if summoned == null: continue
							var dealt := 0
							for damage in preview_damage_segments(enemy, card, {"kind":"summon", "slot":slot, "side":side}): dealt += damage
							score += sign_value * (float(dealt) * 1.2 + (9.0 if dealt >= summoned.hp else 0.0))
					if self_lethal and not opponent_lethal: score -= 1000.0
				elif selection.get("kind", "hero") == "summon":
					var summoned: Summon = player.summons[int(selection["slot"])]
					var dealt := 0
					for damage in preview_damage_segments(enemy, card, selection): dealt += damage
					score += float(dealt) * 1.2 + (9.0 if dealt >= summoned.hp else 0.0)
				else:
					for damage in preview_damage_segments(enemy, card, selection): score += float(damage)
					score += float(mini(player.status_stacks("shield"), int(effect["amount"]))) * 0.65
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
			"gain_random_energy":
				var available := 0
				for element in BattleRules.ELEMENTS:
					if int(enemy.energy[element]) < 10 and enemy.status_stacks("lock", element) == 0: available += 1
				score += int(effect["amount"]) * 3.5 if available > 0 else 0.0
			"lose_energy": score += mini(int(player.energy[effect["element"]]), int(effect["amount"])) * 6.0
			"convert_energy": score += 7.0
			"draw": score += 4.0 if not enemy.draw_pile.is_empty() else -5.0
			"discard": score += 8.0 if not player.hand.is_empty() else 0.0
			"remove_status": score += float(enemy.status_stacks(effect["status"])) * 4.0
			"status":
				match effect["status"]:
					"burn": score += 9.0 if player.status_stacks("burn") < 3 else 2.0
					"vulnerable": score += 10.0 if player.status_stacks("vulnerable") == 0 else 2.0
					"charge": score += 8.0 if enemy.status_stacks("charge") < 3 else 3.0
					"tenacity": score += 8.0 if enemy.status_stacks("tenacity") < 3 else 3.0
					"strong_attack": score += 7.0 if enemy.status_stacks("strong_attack") < 4 else 3.0
					"strong_defense": score += 7.0 if enemy.status_stacks("strong_defense") < 4 else 3.0
					"weak_attack", "weak_defense": score += 6.0
					"shield": score += 7.0 if enemy.status_stacks("shield") < 10 else 1.0
					"regen": score += 7.0 if enemy.hp < 75 else 1.0
					"lock": score += 9.0 if player.status_stacks("lock", effect["element"]) == 0 else 1.0
	return score

func _check_finish() -> bool:
	if phase in FINISHED_PHASES: return true
	if enemy.hp <= 0 and player.hp <= 0:
		phase = "draw"
		_report("平局。双方同时倒下", "system", "draw")
		changed.emit()
		return true
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
