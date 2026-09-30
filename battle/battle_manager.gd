class_name BattleManager
extends Node

signal damage_segment_resolved(hits: Array)
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
const ARTIFACT_PATH := "res://data/artifacts.json"
const STATUS_NAMES := CardKeywords.NAMES
const FINISHED_PHASES := ["victory", "defeat", "tie"]
# Both sides use slots 0 / 1 / 2 for the top / middle / bottom of the battlefield.
const SUMMON_TRIGGER_ORDER := [0, 1, 2]
const RANDOM_DECK_SIZE := 25
const RANDOM_DECK_COPY_LIMIT := DeckStore.MAX_COPIES
const RANDOM_DECK_MAX_COST := 45
const RANDOM_DECK_MIN_LOW_COST := 8

var cards: Dictionary = {}
var summon_templates: Dictionary = {}
var artifacts: Dictionary = {}
var decks: Array = []
var enemies: Array = []
var player := Combatant.new()
var enemy := Combatant.new()
var rng := RandomNumberGenerator.new()
var phase := "menu"
var round_number := 0
var selected_enemy_id := "ember"
var selected_deck_id := "balanced"
var selected_deck_name := ""
var battle_log: Array[String] = []
var battle_seed := 0
# Tests may disable random loadouts explicitly; gameplay keeps them enabled.
var random_artifacts_enabled := true
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
	artifacts = ArtifactLibrary.load_all()
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

func _equip_loadout(actor: Combatant, raw: Variant) -> void:
	actor.artifacts = ArtifactLibrary.normalize(raw, artifacts)
	var guard: Dictionary = artifacts.get(actor.artifacts["guard"], {})
	actor.artifact_durability = int(guard.get("durability", 0))
	actor.artifact_resistances = guard.get("resistances", {}).duplicate(true)

func artifact_entry(actor: Combatant, slot: String) -> Dictionary:
	return artifacts.get(str(actor.artifacts.get(slot, "")), {})

func artifact_can_activate(actor: Combatant) -> bool:
	if actor != player and actor != enemy: return false
	var entry := artifact_entry(actor, "implement")
	return not entry.is_empty() and actor.own_turn_count >= actor.artifact_ready_turn and phase == ("player_action" if actor == player else "enemy_action")

func artifact_target_mode(actor: Combatant) -> String:
	return str(artifact_entry(actor, "implement").get("target_mode", "none"))

func artifact_effects(actor: Combatant) -> Array:
	return artifact_entry(actor, "implement").get("effects", [])

func valid_artifact_target(actor: Combatant, selection: Dictionary) -> bool:
	match artifact_target_mode(actor):
		"enemy":
			var target := enemy if actor == player else player
			if selection.get("side", _side(target)) != _side(target): return false
			if selection.get("kind", "") == "hero": return target.hp > 0
			var slot := int(selection.get("slot", -1))
			return selection.get("kind", "") == "summon" and slot >= 0 and slot < 3 and target.summons[slot] != null
		"self_or_ally_summon":
			if selection.get("side", _side(actor)) != _side(actor): return false
			if selection.get("kind", "") == "hero": return actor.hp < actor.max_hp
			var slot := int(selection.get("slot", -1))
			return selection.get("kind", "") == "summon" and slot >= 0 and slot < 3 and actor.summons[slot] != null and actor.summons[slot].hp < actor.summons[slot].max_hp
	return selection.is_empty()

func activate_artifact(actor: Combatant, selection: Dictionary = {}) -> bool:
	if not artifact_can_activate(actor) or not valid_artifact_target(actor, selection): return false
	var entry := artifact_entry(actor, "implement")
	actor.artifact_ready_turn = actor.own_turn_count + int(entry.get("cooldown", 2)) + 1
	_report("%s 发动「%s」" % [actor.display_name, entry["name"]], _side(actor), "artifact", entry["element"])
	_resolve_artifact_effects(actor, entry, selection)
	_check_finish()
	changed.emit()
	return true

func _resolve_artifact_effects(actor: Combatant, entry: Dictionary, selection: Dictionary = {}) -> void:
	var opponent := enemy if actor == player else player
	for effect in entry.get("effects", []):
		if phase in FINISHED_PHASES: break
		_resolve_effect(actor, opponent, effect, str(entry["element"]), selection)

func _trigger_artifacts(actor: Combatant, event: String, selection: Dictionary = {}) -> void:
	for slot in ["guard", "pendant"]:
		var entry := artifact_entry(actor, slot)
		if entry.get("trigger", "") != event: continue
		if slot == "guard" and not _use_guard(actor, str(entry["name"]), str(entry["element"])): continue
		_resolve_artifact_effects(actor, entry, selection)

func _trigger_battle_start_artifacts(actor: Combatant) -> void:
	_trigger_artifacts(actor, "battle_start")

func _gain_artifact_energy(actor: Combatant, element: String, amount: int, _name: String) -> void:
	_resolve_effect(actor, enemy if actor == player else player, {"type": "gain_energy", "target": "self", "element": element, "amount": amount}, element)

func _use_guard(actor: Combatant, name: String, element: String) -> bool:
	if actor.artifact_durability <= 0: return false
	actor.artifact_durability -= 1
	_report("%s 的%s触发 · 耐久%d" % [actor.display_name, name, actor.artifact_durability], _side(actor), "artifact", element)
	return true

func _on_card_played(actor: Combatant) -> void:
	if actor.artifact_flags.get("card", false): return
	actor.artifact_flags["card"] = true
	_trigger_artifacts(actor, "first_card_own_turn")

func _on_energy_gained(actor: Combatant) -> void:
	if not phase.begins_with("player_" if actor == player else "enemy_"): return
	if actor.artifact_flags.get("energy", false): return
	actor.artifact_flags["energy"] = true
	_trigger_artifacts(actor, "first_energy_own_turn")

func _on_health_lost(actor: Combatant, amount: int) -> void:
	if amount <= 0 or actor.hp <= 0: return
	_trigger_artifacts(actor, "health_lost")
	if not actor.artifact_flags.get("health", false) and phase.begins_with("player_" if actor == player else "enemy_"):
		actor.artifact_flags["health"] = true
		_trigger_artifacts(actor, "first_health_lost_own_turn")

func _lose_life(actor: Combatant, amount: int, reason: String, kind: String = "damage") -> int:
	var lost := mini(actor.hp, maxi(0, amount))
	actor.hp -= lost
	_report("%s %s：失去 %d 生命" % [actor.display_name, reason, lost], _side(actor), kind, "", lost)
	_on_health_lost(actor, lost)
	_check_finish()
	return lost

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

func start_battle(enemy_id: String, deck_id: String, seed_value: int = -1, custom_deck: Dictionary = {}) -> void:
	if not custom_deck.is_empty() and not DeckStore.new(cards).problem(custom_deck.get("cards", [])).is_empty(): return
	battle_generation += 1
	var generation := battle_generation
	selected_enemy_id = enemy_id
	selected_deck_id = "custom:" + str(custom_deck.get("id", "")) if not custom_deck.is_empty() else deck_id
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	battle_seed = rng.seed
	var enemy_info := find_entry(enemies, enemy_id)
	var deck_info := find_entry(decks, deck_id)
	var testing := deck_id == "random" or not custom_deck.is_empty()
	var player_deck: Array = custom_deck["cards"].duplicate() if not custom_deck.is_empty() else generate_random_deck() if testing else deck_info["cards"]
	var enemy_deck: Array = generate_random_deck() if testing else enemy_info["deck"]
	selected_deck_name = str(custom_deck["name"]) if not custom_deck.is_empty() else "随机牌组" if testing else str(deck_info["name"])
	player.max_hp = 80 if testing else 100
	enemy.max_hp = 80 if testing else 100
	player.setup("player", "云溪月", player_deck, rng)
	enemy.setup(enemy_id, enemy_info["name"], enemy_deck, rng)
	var player_loadout := ArtifactLibrary.random_loadout(artifacts, rng) if custom_deck.is_empty() and testing and random_artifacts_enabled else ArtifactLibrary.normalize(custom_deck.get("artifacts", {}), artifacts)
	var enemy_loadout := ArtifactLibrary.random_loadout(artifacts, rng) if testing and random_artifacts_enabled else {"implement": "", "guard": "", "pendant": ""}
	_equip_loadout(player, player_loadout)
	_equip_loadout(enemy, enemy_loadout)
	phase = "battle_start"
	round_number = 0
	played_cards = 0
	energy_destroyed = 0
	player_damage = 0
	battle_log.clear()
	_report("对阵 %s · 使用「%s」牌组" % [enemy.display_name, selected_deck_name], "system", "start")
	for i in 4:
		draw_card(player)
		draw_card(enemy)
	_trigger_battle_start_artifacts(player)
	_trigger_battle_start_artifacts(enemy)
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
	if battle_log.size() > 2000:
		battle_log.resize(2000)
	action_event.emit(message, side, kind, element, amount)

func _side(actor: Combatant) -> String:
	return "player" if actor == player else "enemy"

func natural_weights(actor: Combatant) -> Dictionary:
	var weights := {}
	for element in BattleRules.ELEMENTS:
		weights[element] = 0
	for card_id in actor.initial_deck:
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
				_on_energy_gained(actor)
				_trigger_poison(actor)
			return element
	return ""

func draw_card(actor: Combatant) -> void:
	if actor.draw_pile.is_empty():
		actor.fatigue_level += 1
		_lose_life(actor, actor.fatigue_level, "疲劳")
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
	actor.own_turn_count += 1
	actor.artifact_flags = {"card": false, "energy": false, "health": false}
	var opposing := enemy if actor == player else player
	opposing.artifact_flags["enemy_turn_hit"] = false
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
	if generation != battle_generation or phase in ["menu", "victory", "defeat", "tie"]:
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
			if resolved["target"] == "lowest_opponent":
				resolved["selection"] = lowest_life_target(opponent)
			elif resolved["target"] == "highest_opponent":
				resolved["selection"] = highest_life_target(opponent)
			elif resolved["target"] == "summon_self":
				resolved["selection"] = {"kind": "summon", "side": _side(actor), "slot": slot}
			summon_triggered.emit(_side(actor), slot, timing, resolved)
			if summon_presenter.is_valid():
				await summon_presenter.call(_side(actor), slot, summoned, resolved, "cast")
			if generation != battle_generation or phase in ["menu", "victory", "defeat", "tie"]:
				return
			if actor.summons[slot] != summoned:
				break
			_resolve_effect(actor, opponent, resolved, summoned.element, resolved.get("selection", {}))
			if summon_presenter.is_valid():
				changed.emit()
				await summon_presenter.call(_side(actor), slot, summoned, resolved, "resolved")
			if generation != battle_generation or phase in ["menu", "victory", "defeat", "tie"]:
				return

func lowest_life_target(owner: Combatant) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var lowest := 2147483647
	if owner.hp > 0:
		lowest = owner.hp
		candidates.append({"kind": "hero", "side": _side(owner)})
	for slot in owner.summons.size():
		var summoned: Summon = owner.summons[slot]
		if summoned == null or summoned.hp <= 0: continue
		if summoned.hp < lowest:
			lowest = summoned.hp
			candidates.clear()
		if summoned.hp == lowest:
			candidates.append({"kind": "summon", "side": _side(owner), "slot": slot})
	if candidates.is_empty(): return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func highest_life_target(owner: Combatant) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var highest := -1
	if owner.hp > 0:
		highest = owner.hp
		candidates.append({"kind": "hero", "side": _side(owner)})
	for slot in owner.summons.size():
		var summoned: Summon = owner.summons[slot]
		if summoned == null or summoned.hp <= 0: continue
		if summoned.hp > highest:
			highest = summoned.hp
			candidates.clear()
		if summoned.hp == highest:
			candidates.append({"kind": "summon", "side": _side(owner), "slot": slot})
	if candidates.is_empty(): return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _condition_met(effect: Dictionary, actor: Combatant, energy_snapshot: Dictionary = {}) -> bool:
	var condition: Dictionary = effect.get("condition", {})
	if condition.is_empty(): return true
	if condition.get("type", "") == "energy_at_least":
		var energy: Dictionary = energy_snapshot if not energy_snapshot.is_empty() else actor.energy
		return int(energy.get(condition.get("element", ""), 0)) >= int(condition.get("amount", 0))
	return false

func card_condition_met(actor: Combatant, card: Dictionary) -> bool:
	# Spell conditions see energy before payment; entrance conditions see it after.
	for effect in card["effects"]:
		if effect.get("type", "") == "summon":
			var template: Dictionary = summon_templates.get(effect.get("summon", ""), {})
			var after_payment := actor.energy.duplicate()
			after_payment[card["element"]] = int(after_payment[card["element"]]) - int(card["cost"])
			for entrance in template.get("on_spawn", []):
				if entrance.has("condition") and _condition_met(entrance, actor, after_payment): return true
		elif effect.has("condition") and _condition_met(effect, actor):
			return true
	return false

func card_target_mode(card: Dictionary) -> String:
	for effect in card["effects"]:
		if effect["type"] == "summon":
			return "slot"
		if effect["type"] == "grow_summon":
			return "ally_summon"
		if effect["type"] == "damage":
			if effect.get("scope", "") == "all_enemy_summons": return "enemy_summons"
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
	if mode in ["ally_summon", "enemy_summons"]:
		var owner: Combatant = actor if mode == "ally_summon" else enemy if actor == player else player
		return kind == "summon" and slot >= 0 and slot < owner.summons.size() and owner.summons[slot] != null and str(selection.get("side", _side(owner))) == _side(owner)
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
	if scope in ["all", "all_opponents", "all_enemy_summons"]:
		var owners: Array[Combatant] = [opponent]
		if scope == "all": owners.append(actor)
		for owner in owners:
			if scope != "all_enemy_summons": targets.append({"owner": owner, "kind": "hero"})
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
	return actor.snapshot()

# A detached copy resolves through the same card, effect and artifact code.
# It has no UI presenters or observers and owns every mutable battle value.
func simulation_copy() -> BattleManager:
	var copy := BattleManager.new()
	copy.cards = cards.duplicate()
	copy.summon_templates = summon_templates
	copy.artifacts = artifacts
	copy.player = player.snapshot()
	copy.enemy = enemy.snapshot()
	copy.phase = phase
	copy.round_number = round_number
	copy.rng.seed = rng.seed
	copy.rng.state = rng.state
	return copy

func _simulation_card(copy: BattleManager, actor: Combatant, card: Dictionary) -> int:
	var simulated: Dictionary = card.duplicate(true)
	var id := str(card.get("id", "__simulation_card"))
	simulated["id"] = id
	if not simulated.has("cost"): simulated["cost"] = 0
	if not simulated.has("name"): simulated["name"] = id
	copy.cards[id] = simulated
	var index := actor.hand.find(id)
	if index < 0:
		actor.hand.append(id)
		index = actor.hand.size() - 1
	return index

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
	if card_target_mode(card) not in ["damage", "enemy_summons"] or not valid_card_target(actor, card, selection): return segments
	var copy := simulation_copy()
	var source: Combatant = copy.player if actor == player else copy.enemy
	var opponent: Combatant = copy.enemy if actor == player else copy.player
	var selected_side := str(selection.get("side", _side(enemy if actor == player else player)))
	copy.damage_segment_resolved.connect(func(hits: Array):
		var selected_damage := 0
		for hit in hits:
			if hit["side"] == selected_side and hit["kind"] == selection.get("kind", "hero") and (hit["kind"] == "hero" or int(hit["slot"]) == int(selection["slot"])):
				selected_damage += int(hit["amount"])
		segments.append(selected_damage))
	var index := _simulation_card(copy, source, card)
	copy._play_card(source, opponent, index, selection)
	copy.free()
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
	var pre_payment_energy := actor.energy.duplicate()
	actor.lose_energy(card["element"], int(card["cost"]))
	_report("%s 使用「%s」" % [actor.display_name, card["name"]], _side(actor), "play", card["element"], int(card["cost"]))
	_trigger_bleed(actor)
	if phase not in FINISHED_PHASES: _on_card_played(actor)
	for effect in card["effects"]:
		if phase in FINISHED_PHASES:
			break
		_resolve_effect(actor, target, effect, card["element"], selection, pre_payment_energy)
	actor.discard_pile.append(card_id)
	played_cards += 1
	_check_finish()
	changed.emit()
	return true

func _resolve_effect(actor: Combatant, opponent: Combatant, effect: Dictionary, card_element: String, selection: Dictionary = {}, pre_payment_energy: Dictionary = {}) -> void:
	if not _condition_met(effect, actor, pre_payment_energy): return
	var target: Combatant = actor if effect.get("target", "opponent") == "self" else opponent
	var amount := int(effect.get("amount", 0))
	match effect["type"]:
		"damage":
			var attack_element := str(effect.get("element", card_element))
			var resolved_selection := selection
			if effect.get("target", "") == "self": resolved_selection = {"kind": "hero", "side": _side(actor)}
			var plan := _damage_plan(actor, opponent, effect, card_element, resolved_selection)
			var hits: Array[Dictionary] = []
			for hit in plan:
				var dealt: int
				if hit["kind"] == "hero":
					dealt = _apply_hero_damage(actor, hit["owner"], hit["breakdown"], attack_element)
				else:
					dealt = _apply_summon_hit(actor, hit["owner"], int(hit["slot"]), int(hit["raw"]), attack_element)
				hits.append({"side": _side(hit["owner"]), "kind": hit["kind"], "slot": int(hit.get("slot", -1)), "amount": dealt})
			damage_segment_resolved.emit(hits)
			if not plan.is_empty(): _consume_attack_statuses(actor)
			_check_finish()
		"summon":
			var slot := int(selection["slot"])
			var template: Dictionary = summon_templates[effect["summon"]]
			var summoned := Summon.new()
			summoned.setup(template)
			actor.summons[slot] = summoned
			_trigger_artifacts(actor, "summon", {"kind": "summon", "side": _side(actor), "slot": slot})
			_report("%s 在槽位 %d 召唤%s" % [actor.display_name, slot + 1, summoned.display_name], _side(actor), "summon", summoned.element, 1)
			summon_event.emit(_side(actor), slot, "spawn", summoned.element, 1, "")
			for entrance in summoned.spawn_effects:
				if phase in FINISHED_PHASES: break
				if not _condition_met(entrance, actor): continue
				var resolved: Dictionary = entrance.duplicate(true)
				if resolved.get("target", "") == "lowest_opponent": resolved["selection"] = lowest_life_target(opponent)
				elif resolved.get("target", "") == "highest_opponent": resolved["selection"] = highest_life_target(opponent)
				summon_triggered.emit(_side(actor), slot, "on_spawn", resolved)
				_resolve_effect(actor, opponent, resolved, summoned.element, resolved.get("selection", {}))
		"heal_selected":
			var resolved := effect.duplicate(true)
			resolved["type"] = "heal_summon" if selection.get("kind", "") == "summon" else "heal"
			resolved["target"] = "self"
			_resolve_effect(actor, opponent, resolved, card_element, selection)
		"heal":
			var actual := mini(amount, target.max_hp - target.hp)
			target.hp += actual
			_report("%s 恢复 %d 生命" % [target.display_name, actual], _side(target), "heal", card_element, actual)
		"heal_summon", "grow_summon":
			var selected_side := str(selection.get("side", _side(actor)))
			var owner := player if selected_side == "player" else enemy
			var selected_slot := int(selection.get("slot", -1))
			if selected_slot < 0 or selected_slot >= owner.summons.size() or owner.summons[selected_slot] == null: return
			var selected: Summon = owner.summons[selected_slot]
			if effect["type"] == "grow_summon": selected.max_hp += amount
			var healed := mini(amount, selected.max_hp - selected.hp)
			selected.hp += healed
			_report("%s %s %d 点生命" % [selected.display_name, "增加" if effect["type"] == "grow_summon" else "恢复", healed], _side(owner), "summon_heal", card_element, healed)
			summon_event.emit(_side(owner), selected_slot, "heal", card_element, healed, "")
		"draw":
			for i in amount:
				if phase in FINISHED_PHASES:
					break
				draw_card(target)
		"gain_energy":
			var gained := target.gain_energy(effect["element"], amount)
			_report("%s 获得 %d %s能量" % [target.display_name, gained, BattleRules.element_name(effect["element"])], _side(target), "energy", effect["element"], gained)
			if gained > 0:
				_on_energy_gained(target)
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
					_on_energy_gained(target)
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
		"break_shield":
			var removed := mini(amount, target.status_stacks("shield"))
			if removed > 0: _absorb_shield(target, removed)
			_report("%s 失去 %d 层护盾" % [target.display_name, removed], _side(target), "status_shield", card_element, removed)
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
	if raw > 0 and float(target.artifact_resistances.get(element, 0.0)) > 0.0:
		_trigger_artifacts(target, "element_damage")
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
	_on_health_lost(target, dealt)
	if raw > 0 and target.hp > 0 and not target.artifact_flags.get("enemy_turn_hit", false) and phase.begins_with("enemy_" if target == player else "player_"):
		target.artifact_flags["enemy_turn_hit"] = true
		_trigger_artifacts(target, "first_hit_enemy_turn")
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
	if generation != battle_generation or phase in ["menu", "victory", "defeat", "tie"]:
		return
	_check_finish()
	changed.emit()

func _trigger_poison(actor: Combatant) -> void:
	var stacks := actor.status_stacks("poison")
	if stacks <= 0 or phase in FINISHED_PHASES: return
	# Commit consumption before emitting life-loss reactions that may gain energy.
	actor.decay_status("poison")
	_lose_life(actor, stacks, "中毒", "poison_damage")

func _trigger_bleed(actor: Combatant) -> void:
	var stacks := actor.status_stacks("bleed")
	if stacks <= 0: return
	actor.decay_status("bleed")
	_lose_life(actor, stacks, "出血")

func end_player_turn() -> void:
	if phase != "player_action":
		return
	phase = "player_turn_end"
	var generation := battle_generation
	changed.emit()
	await _end_turn(player)
	if generation == battle_generation and phase not in ["menu", "victory", "defeat", "tie"]:
		await _start_turn(enemy)

func peek_enemy_action() -> Dictionary:
	if phase != "enemy_action":
		return {"index": -1, "target": {}}
	return _choose_enemy_action()

func peek_enemy_card_index() -> int:
	return int(peek_enemy_action()["index"])

func enemy_step(chosen_index: int = -2, selection: Dictionary = {}, action_kind: String = "card") -> bool:
	if phase != "enemy_action":
		return false
	if chosen_index == -2:
		var action := _choose_enemy_action()
		chosen_index = int(action["index"])
		selection = action["target"]
		action_kind = str(action.get("kind", "card"))
	if action_kind == "artifact":
		activate_artifact(enemy, selection)
		return phase == "enemy_action"
	var index := chosen_index
	if index < 0:
		phase = "enemy_turn_end"
		var generation := battle_generation
		changed.emit()
		await _end_turn(enemy)
		if generation == battle_generation and phase not in ["menu", "victory", "defeat", "tie"]:
			await _start_turn(player)
		return false
	if selection.is_empty() and index < enemy.hand.size():
		var card: Dictionary = cards[enemy.hand[index]]
		match card_target_mode(card):
			"damage": selection = {"kind": "hero"}
			"slot": selection = {"kind": "slot", "slot": enemy.first_free_summon_slot()}
			"enemy_summons":
				for slot in player.summons.size():
					if player.summons[slot] != null:
						selection = {"kind": "summon", "side": "player", "slot": slot}
						break
			"ally_summon":
				for slot in enemy.summons.size():
					if enemy.summons[slot] != null:
						selection = {"kind": "summon", "side": "enemy", "slot": slot}
						break
	_play_card(enemy, player, index, selection)
	return phase == "enemy_action"

func _choose_enemy_action() -> Dictionary:
	var best_action := {"kind": "end_turn", "index": -1, "target": {}}
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
			"enemy_summons":
				candidates = []
				for slot in player.summons.size():
					if player.summons[slot] != null: candidates.append({"kind": "summon", "side": "player", "slot": slot})
			"ally_summon":
				candidates = []
				for slot in enemy.summons.size():
					if enemy.summons[slot] != null: candidates.append({"kind": "summon", "side": "enemy", "slot": slot})
			"slot":
				candidates = []
				for slot in enemy.summons.size():
					if enemy.summons[slot] == null:
						candidates.append({"kind": "slot", "slot": slot})
		for selection in candidates:
			var score := _enemy_action_score(card, selection)
			score += rng.randf_range(-3.0, 3.0)
			if score > best_score:
				best_score = score
				best_action = {"kind": "card", "index": i, "target": selection}
	if artifact_can_activate(enemy):
		var candidates: Array[Dictionary] = [{}]
		var mode := artifact_target_mode(enemy)
		if mode != "none":
			var owner := player if mode == "enemy" else enemy
			candidates = [{"kind": "hero", "side": _side(owner)}]
			for slot in owner.summons.size():
				if owner.summons[slot] != null: candidates.append({"kind": "summon", "side": _side(owner), "slot": slot})
		for selection in candidates:
			if not valid_artifact_target(enemy, selection): continue
			var score := EnemyPolicy.artifact_score(self, selection)
			if score > best_score:
				best_score = score
				best_action = {"kind": "artifact", "index": -1, "target": selection}
	return best_action

func _enemy_action_score(card: Dictionary, selection: Dictionary) -> float:
	return EnemyPolicy.card_score(self, card, selection)

func _check_finish() -> bool:
	if phase in FINISHED_PHASES: return true
	if enemy.hp <= 0 and player.hp <= 0:
		phase = "tie"
		_report("平局。双方同时倒下", "system", "tie")
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

func export_battle_report() -> String:
	var directory := "user://battle_reports"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return ""
	var path := "%s/battle_%d_%d.json" % [directory, Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var events := battle_log.duplicate()
	events.reverse()
	var report := {"version": 1, "seed": str(battle_seed), "enemy": selected_enemy_id, "deck_name": selected_deck_name, "phase": phase, "round": round_number, "player_deck": player.initial_deck, "enemy_deck": enemy.initial_deck, "player_artifacts": player.artifacts, "enemy_artifacts": enemy.artifacts, "events": events}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(JSON.stringify(report, "  "))
	file.flush()
	return ProjectSettings.globalize_path(path) if file.get_error() == OK else ""
