class_name BattleManager
extends Node

signal damage_segment_resolved(hits: Array)
signal random_hit_targeted(side: String, element: String, selection: Dictionary)
signal changed
signal action_event(message: String, side: String, kind: String, element: String, amount: int)
# Emitted before removal so the presenter can retain the exact hand card,
# including duplicate copies and discards after the played card leaves the hand.
signal hand_card_removed(side: String, card_id: String, index: int, reason: String)
signal summon_event(side: String, slot: int, kind: String, element: String, amount: int, matchup: String)
signal summon_triggered(side: String, slot: int, timing: String, effect: Dictionary)
signal choice_requested(candidates: Array, hand_full: bool)
signal choice_completed

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
var first_side := "player"
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
var opening_presenter: Callable
var interactive_choices := false
var pending_choice: Dictionary = {}
var choice_scoring := false
# Used only to recover an endless battle from its saved action journal.
var replay_choice_indices: Array[int] = []
var card_instance_serial := 0
var damage_depth := 0
var death_queue: Array[Dictionary] = []
var flushing_deaths := false

func _ready() -> void:
	load_content()

func _exit_tree() -> void:
	battle_generation += 1
	phase = "menu"
	pending_choice.clear()
	choice_completed.emit()
	summon_presenter = Callable()
	opening_presenter = Callable()

func load_content() -> void:
	cards = ContentCatalog.load_all(CARD_PATH)
	summon_templates = ContentCatalog.load_all(SUMMON_PATH)
	for card: Dictionary in cards.values(): card["text"] = EffectText.card_text(card, summon_templates)
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
	return pending_choice.is_empty() and not entry.is_empty() and actor.own_turn_count >= actor.artifact_ready_turn and phase == ("player_action" if actor == player else "enemy_action")

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
	actor.artifact_ready_turn = actor.own_turn_count + maxi(1, int(entry.get("cooldown", 3)))
	_report("%s 发动「%s」" % [actor.display_name, entry["name"]], _side(actor), "artifact", entry["element"])
	_resolve_artifact_effects(actor, entry, selection)
	_check_finish()
	changed.emit()
	return true

func _resolve_artifact_effects(actor: Combatant, entry: Dictionary, selection: Dictionary = {}) -> void:
	var opponent := enemy if actor == player else player
	_resolve_sequence(actor, opponent, entry.get("effects", []), str(entry["element"]), selection)

func _trigger_artifacts(actor: Combatant, event: String, selection: Dictionary = {}) -> void:
	if actor.hp <= 0 or phase in FINISHED_PHASES: return
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

func display_card(actor: Combatant, card: Dictionary) -> Dictionary:
	var shown := card.duplicate(true)
	shown["printed_cost"] = int(card["cost"])
	shown["cost"] = actor.card_cost(card)
	var changed_numbers := {}
	var source := actor.snapshot()
	var neutral := Combatant.new()
	neutral.setup("preview", "", [], RandomNumberGenerator.new())
	for effect: Dictionary in shown.get("effects", []):
		if effect.get("type") == "status" and effect.has("stacks_from_status"):
			var target := actor if effect.get("target") == "self" else (enemy if actor == player else player)
			effect["display_stacks"] = _effect_status_stacks(target, effect)
		if effect.get("type") != "damage": continue
		var base := _effect_damage_amount(actor, effect, str(card["id"]))
		var modified: int = BattleRules.damage_breakdown(neutral, base, str(effect.get("element", card["element"])), source)["raw"]
		if effect.has("shield_multiplier") or effect.has("hand_multiplier") or effect.has("energy_multiplier"): effect["display_amount"] = modified
		else: effect["amount"] = modified
		if modified != base:
			effect["display_color"] = "#79df8a" if modified > base else "#ff817a"
			changed_numbers[str(modified)] = effect["display_color"]
		_consume_attack_statuses(source)
	shown["rich_text"] = EffectText.card_text(shown, summon_templates)
	for effect: Dictionary in shown.get("effects", []): effect.erase("display_color")
	shown["text"] = EffectText.card_text(shown, summon_templates)
	for effect: Dictionary in card.get("effects", []):
		if effect.get("type") == "summon":
			shown["summon_hp"] = int(summon_templates[effect["summon"]]["hp"])
			shown["printed_summon_hp"] = shown["summon_hp"]
	if shown.has("summon_hp"):
		var entry := artifact_entry(actor, "pendant")
		if entry.get("trigger") == "summon":
			for effect: Dictionary in entry.get("effects", []):
				if effect.get("type") == "grow_summon": shown["summon_hp"] += int(effect["amount"])
	shown["number_colors"] = changed_numbers
	return shown

func _sync_cost_auras() -> void:
	for actor: Combatant in [player, enemy]:
		actor.card_cost_increase = 0
		var opponent: Combatant = enemy if actor == player else player
		for summoned: Summon in opponent.summons:
			if summoned != null and summoned.hp > 0: actor.card_cost_increase += summoned.enemy_cost_aura

func _on_healed(owner: Combatant, actual: int) -> void:
	if actual <= 0 or owner.hp <= 0 or phase in FINISHED_PHASES: return
	if phase.begins_with(_side(owner) + "_") and not owner.artifact_flags.get("ally_heal", false):
		owner.artifact_flags["ally_heal"] = true
		_trigger_artifacts(owner, "first_ally_heal_own_turn")
	# Snapshot the listeners before any draw/fatigue reactions. Later listeners
	# must still be alive and mounted in the same slot when their turn arrives.
	var listeners: Array[Dictionary] = []
	for actor: Combatant in [player, enemy]:
		for slot in actor.summons.size():
			var summoned: Summon = actor.summons[slot]
			if summoned != null and summoned.hp > 0 and not summoned.heal_effects.is_empty():
				listeners.append({"owner":actor, "slot":slot, "summon":summoned})
	for listener in listeners:
		if phase in FINISHED_PHASES: break
		var actor: Combatant = listener["owner"]
		var summoned: Summon = listener["summon"]
		if actor.hp <= 0 or actor.summons[int(listener["slot"])] != summoned or summoned.hp <= 0: continue
		for effect: Dictionary in summoned.heal_effects:
			if phase in FINISHED_PHASES: break
			summon_triggered.emit(_side(actor), int(listener["slot"]), "on_heal", effect)
			_resolve_effect(actor, enemy if actor == player else player, effect, summoned.element)

func summon_requires_target(card: Dictionary) -> bool:
	for effect: Dictionary in card.get("effects", []):
		if effect.get("type") != "summon": continue
		for entrance: Dictionary in summon_templates.get(effect["summon"], {}).get("on_spawn", []):
			if entrance.get("target") == "selected_opponent": return true
	return false

func _living_targets(owner: Combatant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if owner.hp > 0: result.append({"kind":"hero", "side":_side(owner)})
	for slot in owner.summons.size():
		var summoned: Summon = owner.summons[slot]
		if summoned != null and summoned.hp > 0: result.append({"kind":"summon", "side":_side(owner), "slot":slot})
	return result

func _valid_enemy_selection(actor: Combatant, selection: Dictionary) -> bool:
	var opponent: Combatant = enemy if actor == player else player
	for candidate in _living_targets(opponent):
		if candidate["kind"] == selection.get("kind") and selection.get("side", _side(opponent)) == _side(opponent):
			if candidate["kind"] == "hero" or int(candidate["slot"]) == int(selection.get("slot", -1)): return true
	return false

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
	if not actor.artifact_flags.get("enemy_health", false) and phase.begins_with("enemy_" if actor == player else "player_"):
		actor.artifact_flags["enemy_health"] = true
		_trigger_artifacts(actor, "first_health_lost_enemy_turn")
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

func start_battle(enemy_id: String, deck_id: String, seed_value: int = -1, custom_deck: Dictionary = {}, options: Dictionary = {}) -> void:
	if not custom_deck.is_empty() and not DeckStore.new(cards).problem(custom_deck.get("cards", [])).is_empty(): return
	if options.has("enemy_deck") and not DeckStore.new(cards).problem(options["enemy_deck"]).is_empty(): return
	battle_generation += 1
	for id: String in cards.keys():
		if cards[id].get("battle_only", false): cards.erase(id)
	card_instance_serial = 0
	death_queue.clear()
	damage_depth = 0
	flushing_deaths = false
	pending_choice.clear()
	choice_completed.emit()
	var generation := battle_generation
	selected_enemy_id = enemy_id
	selected_deck_id = "custom:" + str(custom_deck.get("id", "")) if not custom_deck.is_empty() else deck_id
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	battle_seed = rng.seed
	first_side = "player" if rng.randi_range(0, 1) == 0 else "enemy"
	if options.get("first_side", "") in ["player", "enemy"]: first_side = options["first_side"]
	var enemy_info := find_entry(enemies, enemy_id)
	var deck_info := find_entry(decks, deck_id)
	var testing := deck_id == "random" or not custom_deck.is_empty()
	var player_deck: Array = custom_deck["cards"].duplicate() if not custom_deck.is_empty() else generate_random_deck() if testing else deck_info["cards"]
	var enemy_deck: Array = options["enemy_deck"].duplicate() if options.has("enemy_deck") else generate_random_deck() if testing else enemy_info["deck"]
	selected_deck_name = str(custom_deck["name"]) if not custom_deck.is_empty() else "随机牌组" if testing else str(deck_info["name"])
	player.max_hp = int(options.get("player_hp", 80 if testing else 100))
	enemy.max_hp = int(options.get("enemy_hp", 80 if testing else 100))
	player.setup("player", "云溪月", player_deck, rng)
	enemy.setup(enemy_id, enemy_info["name"], enemy_deck, rng)
	var player_loadout := ArtifactLibrary.random_loadout(artifacts, rng) if custom_deck.is_empty() and testing and random_artifacts_enabled else ArtifactLibrary.normalize(custom_deck.get("artifacts", {}), artifacts)
	var enemy_loadout: Dictionary = options["enemy_artifacts"] if options.has("enemy_artifacts") else ArtifactLibrary.random_loadout(artifacts, rng) if testing and random_artifacts_enabled else {"implement": "", "guard": "", "pendant": ""}
	_equip_loadout(player, player_loadout)
	_equip_loadout(enemy, enemy_loadout)
	phase = "opening_order"
	round_number = 0
	played_cards = 0
	energy_destroyed = 0
	player_damage = 0
	battle_log.clear()
	_report("对阵 %s · 使用「%s」牌组" % [enemy.display_name, selected_deck_name], "system", "start")
	var first := player if first_side == "player" else enemy
	var second := enemy if first == player else player
	_report("%s 先手 · %s 后手（起始多抽1张）" % [first.display_name, second.display_name], "system", "turn_order")
	await _present_opening("order")
	if not _opening_is_current(generation): return
	phase = "opening_draw"
	_report("双方各抽3张起始卡牌", "system", "opening")
	for i in 3:
		draw_card(player)
		draw_card(enemy)
	await _present_opening("initial_draw")
	if not _opening_is_current(generation): return
	_report("%s 后手补抽1张起始卡牌" % second.display_name, "system", "opening")
	draw_card(second)
	await _present_opening("second_draw")
	if not _opening_is_current(generation): return
	phase = "battle_start"
	_report("结算游戏开始时的效果（先手 → 后手）", "system", "opening")
	for actor in [first, second]:
		_trigger_battle_start_artifacts(actor)
		await wait_for_choice()
		if not _opening_is_current(generation): return
		await _present_opening("start_effects")
		if not _opening_is_current(generation): return
	await _start_turn(first)
	if not _opening_is_current(generation): return
	await _present_opening("first_turn")
	if generation == battle_generation: changed.emit()

func _opening_is_current(generation: int) -> bool:
	return generation == battle_generation and phase != "menu" and phase not in FINISHED_PHASES

func _present_opening(stage: String) -> void:
	changed.emit()
	if opening_presenter.is_valid(): await opening_presenter.call(stage)

func valid_random_deck(deck: Array) -> bool:
	if deck.size() != RANDOM_DECK_SIZE: return false
	var counts := {}
	var total := 0
	var low_cost := 0
	for id in deck:
		if not cards.has(id): return false
		var family := ContentCatalog.base_id(cards[id])
		counts[family] = int(counts.get(family, 0)) + 1
		if counts[family] > RANDOM_DECK_COPY_LIMIT: return false
		var cost := int(cards[id]["cost"])
		total += cost
		if cost <= 1: low_cost += 1
	return total <= RANDOM_DECK_MAX_COST and low_cost >= RANDOM_DECK_MIN_LOW_COST

func generate_random_deck() -> Array[String]:
	var pool: Array[String] = []
	for id in cards:
		if int(cards[id].get("level", 0)) != 0: continue
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

func can_convert_qi(actor: Combatant, element: String) -> bool:
	return (actor == player or actor == enemy) and phase == _side(actor) + "_action" and pending_choice.is_empty() and element in BattleRules.ELEMENTS and actor.qi > 0 and int(actor.energy[element]) < 10 and actor.status_stacks("lock", element) == 0

func convert_qi(actor: Combatant, element: String) -> bool:
	if not can_convert_qi(actor, element): return false
	actor.qi -= 1
	_report("%s 将1点真气转化为%s灵气" % [actor.display_name, BattleRules.element_name(element)], _side(actor), "qi_convert", element, 1)
	_resolve_effect(actor, enemy if actor == player else player, {"type":"gain_energy", "target":"self", "element":element, "amount":1}, element)
	_check_finish()
	changed.emit()
	return true

func next_fatigue_damage(actor: Combatant) -> int:
	return 5 << mini(actor.fatigue_level, 60)

func deck_tooltip(actor: Combatant) -> String:
	return "抽牌堆 %d张 · 弃牌堆 %d张\n已循环%d次\n下次循环失去%d点生命\n抽牌堆耗尽时洗回弃牌堆；手牌不参与。" % [actor.draw_pile.size(), actor.discard_pile.size(), actor.fatigue_level, next_fatigue_damage(actor)]

func _ensure_draw_pile(actor: Combatant) -> bool:
	if phase in FINISHED_PHASES: return false
	if not actor.draw_pile.is_empty(): return true
	if actor.discard_pile.is_empty():
		_report("%s 暂无可回收的弃牌，无法抽牌" % actor.display_name, _side(actor), "draw_empty")
		return false
	actor.draw_pile.assign(actor.discard_pile)
	actor.discard_pile.clear()
	for i in range(actor.draw_pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var card_id := actor.draw_pile[i]
		actor.draw_pile[i] = actor.draw_pile[j]
		actor.draw_pile[j] = card_id
	var damage := next_fatigue_damage(actor)
	actor.fatigue_level += 1
	_report("%s 牌库循环第%d次，洗回%d张弃牌" % [actor.display_name, actor.fatigue_level, actor.draw_pile.size()], _side(actor), "reshuffle")
	_lose_life(actor, damage, "循环疲劳", "fatigue_damage")
	return phase not in FINISHED_PHASES

func draw_card(actor: Combatant) -> void:
	if not _ensure_draw_pile(actor): return
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
	actor.last_card_element = ""
	actor.spell_elements.clear()
	actor.artifact_flags = {"card": false, "energy": false, "health": false}
	var opposing := enemy if actor == player else player
	opposing.artifact_flags["enemy_turn_hit"] = false
	opposing.artifact_flags["enemy_health"] = false
	round_number = maxi(player.own_turn_count, enemy.own_turn_count)
	if actor == player:
		phase = "player_turn_start"
		_report("第 %d 回合 · 你的行动" % round_number, "system", "turn")
	else:
		phase = "enemy_turn_start"
		_report("第 %d 回合 · %s 的行动" % [round_number, actor.display_name], "system", "turn")
	var shield_before := actor.status_stacks("shield")
	if shield_before > 0:
		actor.halve_shield()
		var shield_after := actor.status_stacks("shield")
		if shield_after < shield_before:
			_report("%s 护盾从 %d 减为 %d" % [actor.display_name, shield_before, shield_after], _side(actor), "shield_loss", "", shield_before - shield_after)
	if _check_finish():
		return
	await _trigger_summons(actor, "turn_start")
	if generation != battle_generation or phase in ["menu", "victory", "defeat", "tie"]:
		return
	if _check_finish():
		return
	var qi_gain := turn_start_qi_gain(actor)
	actor.qi += qi_gain
	_report("%s 获得%d点真气 · 现有%d" % [actor.display_name, qi_gain, actor.qi], _side(actor), "qi", "", qi_gain)
	if _check_finish():
		return
	draw_card(actor)
	if _check_finish():
		return
	phase = "player_action" if actor == player else "enemy_action"
	changed.emit()

func turn_start_qi_gain(actor: Combatant) -> int:
	var opponent := enemy if actor == player else player
	var reduction := 0
	for summoned: Summon in opponent.summons:
		if summoned != null and summoned.hp > 0: reduction += summoned.enemy_qi_gain_reduction
	return maxi(0, 1 - reduction)

func _trigger_summons(actor: Combatant, timing: String = "turn_start") -> void:
	var generation := battle_generation
	var opponent := enemy if actor == player else player
	for slot in SUMMON_TRIGGER_ORDER:
		var summoned: Summon = actor.summons[slot]
		if summoned == null:
			continue
		var effects: Array = summoned.turn_start_effects if timing == "turn_start" else summoned.turn_end_effects
		for effect in effects:
			if not _condition_met(effect, actor): continue
			var resolved: Dictionary = effect.duplicate(true)
			if not resolved.has("target"):
				resolved["target"] = "self"
			if resolved["target"] == "lowest_opponent":
				resolved["selection"] = lowest_life_target(opponent)
			elif resolved["target"] == "highest_opponent":
				resolved["selection"] = highest_life_target(opponent)
			elif resolved["target"] == "random_opponent":
				var candidates := _living_targets(opponent)
				if candidates.is_empty(): continue
				resolved["selection"] = candidates[rng.randi_range(0, candidates.size() - 1)]
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
			await wait_for_choice()
			if generation != battle_generation: return
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
	if condition.get("type") == "previous_card_element": return actor.last_card_element == condition.get("element")
	if condition.get("type") == "spell_elements_at_least": return actor.spell_elements.size() >= int(condition.get("amount", 2))
	if condition.is_empty(): return true
	if condition.get("type", "") == "hand_at_most": return actor.hand.size() <= int(condition.get("amount", 0))
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
			after_payment[card["element"]] = int(after_payment[card["element"]]) - actor.card_cost(card)
			for entrance in template.get("on_spawn", []):
				if entrance.has("condition") and _condition_met(entrance, actor, after_payment): return true
		elif effect.has("condition") and _condition_met(effect, actor):
			return true
	return false

func card_target_mode(card: Dictionary) -> String:
	for effect in card["effects"]:
		if effect["type"] == "summon":
			return "slot"
		if effect["type"] in ["grow_summon", "return_summon", "sacrifice_summon"]:
			return "ally_summon"
		if effect["type"] == "damage":
			if effect.get("scope", "") == "all_summons": return "all_summons"
			if effect.get("scope", "") == "all_enemy_summons": return "enemy_summons"
			if effect.get("target", "") in ["opponent", "random_opponent", "lowest_opponent", "highest_opponent"] and effect.get("scope", "single") == "single": continue
			return "damage"
	return "none"

func valid_card_target(actor: Combatant, card: Dictionary, selection: Dictionary) -> bool:
	var mode := card_target_mode(card)
	if mode == "none":
		return true
	var kind := str(selection.get("kind", ""))
	var slot := int(selection.get("slot", -1))
	if mode == "slot":
		return kind == "slot" and slot >= 0 and slot < actor.summons.size() and actor.summons[slot] == null and (not summon_requires_target(card) or _valid_enemy_selection(actor, selection.get("entrance_target", {})))
	if mode in ["ally_summon", "enemy_summons"]:
		var owner: Combatant = actor if mode == "ally_summon" else enemy if actor == player else player
		var valid := kind == "summon" and slot >= 0 and slot < owner.summons.size() and owner.summons[slot] != null and str(selection.get("side", _side(owner))) == _side(owner)
		if valid and card["effects"][0]["type"] == "return_summon": return cards.has(owner.summons[slot].card_id)
		return valid
	var side := str(selection.get("side", "enemy" if actor == player else "player"))
	if side not in damage_target_sides(actor, card): return false
	var owner := player if side == "player" else enemy
	if mode == "all_summons" and kind != "summon": return false
	if kind == "hero": return owner.hp > 0
	return kind == "summon" and slot >= 0 and slot < owner.summons.size() and owner.summons[slot] != null

func damage_target_sides(actor: Combatant, card: Dictionary) -> Array[String]:
	for effect in card["effects"]:
		if effect.get("scope", "single") in ["all", "all_summons"]: return ["player", "enemy"]
	return ["enemy" if actor == player else "player"]

# A segment takes its damage snapshot before applying any hit. An area segment
# therefore shares one attack bonus even when the caster is among its targets.
func _effect_damage_amount(actor: Combatant, effect: Dictionary, exclude_card_id: String = "") -> int:
	if effect.has("shield_multiplier"):
		return mini(int(effect.get("base_cap", 50)), floori(actor.status_stacks("shield") * float(effect["shield_multiplier"])))
	var amount := int(effect.get("amount", 0))
	if effect.has("energy_multiplier"):
		amount += floori(int(actor.energy.get(str(effect["energy_element"]), 0)) * float(effect["energy_multiplier"]))
	if effect.has("hand_multiplier"):
		var count := 0
		var excluded := false
		var owner := actor if effect.get("hand_owner", "self") == "self" else (enemy if actor == player else player)
		for id: String in owner.hand:
			# Card faces are shown before playing; settlement sees the card already removed.
			if owner == actor and not excluded and id == exclude_card_id:
				excluded = true
				continue
			if not effect.has("hand_element") or cards.get(id, {}).get("element") == effect["hand_element"]: count += 1
		amount += count * int(effect["hand_multiplier"])
	return amount

func _effect_status_stacks(target: Combatant, effect: Dictionary) -> int:
	if effect.has("stacks_from_status"):
		return floori(float(target.status_stacks(str(effect["stacks_from_status"]))) / maxi(1, int(effect.get("stacks_divisor", 1))))
	return int(effect.get("stacks", 0))

func _damage_plan(actor: Combatant, opponent: Combatant, effect: Dictionary, card_element: String, selection: Dictionary) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var scope := str(effect.get("scope", "single"))
	if scope in ["all", "all_opponents", "all_enemy_summons", "all_summons"]:
		var owners: Array[Combatant] = [opponent]
		if scope in ["all", "all_summons"]: owners.append(actor)
		for owner in owners:
			if scope not in ["all_enemy_summons", "all_summons"]: targets.append({"owner": owner, "kind": "hero"})
			for slot in owner.summons.size():
				if owner.summons[slot] != null: targets.append({"owner": owner, "kind": "summon", "slot": slot})
	else:
		var own_side := "player" if actor.id == "player" else "enemy"
		var owner := actor if selection.get("side", "") == own_side else opponent
		if selection.get("kind", "hero") != "summon" or (int(selection.get("slot", -1)) >= 0 and int(selection["slot"]) < owner.summons.size() and owner.summons[int(selection["slot"])] != null):
			targets.append({"owner": owner, "kind": selection.get("kind", "hero"), "slot": int(selection.get("slot", -1))})
	var amount := _effect_damage_amount(actor, effect)
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
	copy.first_side = first_side
	copy.choice_scoring = choice_scoring
	copy.card_instance_serial = card_instance_serial
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

func spell_damage_recipient(actor: Combatant, card: Dictionary, selection: Dictionary) -> Dictionary:
	if card_target_mode(card) != "damage" or selection.get("kind") != "hero": return selection
	var opponent := enemy if actor == player else player
	if selection.get("side", _side(opponent)) != _side(opponent): return selection
	var eligible := false
	for effect in card["effects"]:
		if effect["type"] == "damage" and not effect.has("target") and effect.get("scope", "single") == "single" and _condition_met(effect, actor): eligible = true
	if not eligible: return selection
	for slot in SUMMON_TRIGGER_ORDER:
		var guard: Summon = opponent.summons[slot]
		if guard != null and guard.intercept_spell and guard.intercept_turn != actor.own_turn_count:
			return {"kind":"summon", "side":_side(opponent), "slot":slot}
	return selection

func preview_damage_segments(actor: Combatant, card: Dictionary, selection: Dictionary) -> Array[int]:
	var segments: Array[int] = []
	var sacrifice: bool = card["effects"][0]["type"] == "sacrifice_summon"
	if (not sacrifice and card_target_mode(card) not in ["damage", "enemy_summons", "all_summons"]) or not valid_card_target(actor, card, selection): return segments
	var copy := simulation_copy()
	var source: Combatant = copy.player if actor == player else copy.enemy
	var opponent: Combatant = copy.enemy if actor == player else copy.player
	var selected_side := _side(opponent) if sacrifice else str(selection.get("side", _side(enemy if actor == player else player)))
	var recipient := spell_damage_recipient(actor, card, selection)
	var preview_kind := "hero" if sacrifice else str(recipient.get("kind", "hero"))
	copy.damage_segment_resolved.connect(func(hits: Array):
		var selected_damage := 0
		for hit in hits:
			if hit["side"] == selected_side and hit["kind"] == preview_kind and (hit["kind"] == "hero" or int(hit["slot"]) == int(recipient["slot"])):
				selected_damage += int(hit["amount"])
		segments.append(selected_damage))
	var index := _simulation_card(copy, source, card)
	copy._play_card(source, opponent, index, selection)
	copy.free()
	return segments

func play_player_card(index: int, selection: Dictionary = {}) -> bool:
	if phase != "player_action" or not pending_choice.is_empty():
		return false
	return _play_card(player, enemy, index, selection)

func _play_card(actor: Combatant, target: Combatant, index: int, selection: Dictionary = {}) -> bool:
	if index < 0 or index >= actor.hand.size():
		return false
	var card_id := actor.hand[index]
	var card: Dictionary = cards[card_id]
	if not actor.can_pay(card) or not valid_card_target(actor, card, selection):
		return false
	selection = selection.duplicate()
	if card_target_mode(card) == "damage" and selection.get("kind") == "hero" and selection.get("side", _side(target)) == _side(target):
		for slot in SUMMON_TRIGGER_ORDER:
			var guard: Summon = target.summons[slot]
			if guard == null or not guard.intercept_spell or guard.intercept_turn == actor.own_turn_count: continue
			var eligible := false
			for effect in card["effects"]:
				if effect["type"] == "damage" and not effect.has("target") and effect.get("scope", "single") == "single" and _condition_met(effect, actor): eligible = true
			if not eligible: break
			guard.intercept_turn = actor.own_turn_count
			selection["damage_redirect"] = {"kind":"summon", "side":_side(target), "slot":slot, "summon":guard}
			_report("%s 替召唤者承受此法术" % guard.display_name, _side(target), "summon_guard", guard.element)
			break
	hand_card_removed.emit(_side(actor), card_id, index, "play")
	actor.hand.remove_at(index)
	var pre_payment_energy := actor.energy.duplicate()
	var paid_cost := actor.card_cost(card)
	actor.lose_energy(card["element"], paid_cost)
	_report("%s 使用「%s」" % [actor.display_name, card["name"]], _side(actor), "play", card["element"], paid_cost)
	_trigger_bleed(actor)
	if phase not in FINISHED_PHASES:
		_on_card_played(actor)
		if paid_cost == 0: _trigger_artifacts(actor, "zero_cost_card")
	_resolve_sequence(actor, target, card["effects"], card["element"], selection, pre_payment_energy, func():
		actor.discard_pile.append(_canonical_card_id(card_id))
		actor.last_card_element = str(card["element"])
		if card_target_mode(card) != "slot":
			actor.spell_elements[card["element"]] = true
			_trigger_after_spell(actor, str(card["element"]))
		played_cards += 1
		_check_finish()
		changed.emit())
	return true

# A choice suspends only the remaining effects; payment/earlier effects cannot
# be replayed. Simulations take the same path but select without a UI.
func _resolve_sequence(actor: Combatant, opponent: Combatant, effects: Array, element: String, selection: Dictionary = {}, energy_snapshot: Dictionary = {}, complete: Callable = Callable()) -> void:
	for i in effects.size():
		if phase in FINISHED_PHASES: break
		_resolve_effect(actor, opponent, effects[i], element, selection, energy_snapshot)
		if not pending_choice.is_empty():
			pending_choice["continuation"] = {"actor":actor, "opponent":opponent, "effects":effects.slice(i + 1), "element":element, "selection":selection, "energy":energy_snapshot, "complete":complete}
			return
	if complete.is_valid(): complete.call()

func wait_for_choice() -> void:
	var generation := battle_generation
	while generation == battle_generation and not pending_choice.is_empty(): await choice_completed

func _take_choice_card(actor: Combatant, index: int) -> void:
	var id: String = actor.draw_pile[index]
	actor.draw_pile.remove_at(index)
	_receive_card(actor, id, "观想")

func _canonical_card_id(id: String) -> String:
	return str(cards.get(id, {}).get("canonical_id", id))

func _discounted_card(actor: Combatant, id: String, amount: int, this_turn: bool = false) -> String:
	if amount <= 0 or actor.hand.size() >= 8: return _canonical_card_id(id)
	card_instance_serial += 1
	var instance := "%s@%d" % [_canonical_card_id(id), card_instance_serial]
	var entry: Dictionary = cards[id].duplicate(true)
	entry["id"] = instance
	entry["canonical_id"] = _canonical_card_id(id)
	entry["battle_only"] = true
	entry["cost_reduction"] = int(entry.get("cost_reduction", 0)) + amount
	entry["discount_turn"] = actor.own_turn_count if this_turn else -1
	cards[instance] = entry
	return instance

func _receive_discovery(actor: Combatant, id: String, discount: int) -> void:
	_receive_card(actor, _discounted_card(actor, id, discount, true), "发现")

func _trigger_after_spell(actor: Combatant, element: String) -> void:
	var opponent := enemy if actor == player else player
	for slot in SUMMON_TRIGGER_ORDER:
		var summoned: Summon = actor.summons[slot]
		if summoned == null or summoned.after_spell.get("element") != element or summoned.spell_trigger_turn == actor.own_turn_count: continue
		summoned.spell_trigger_turn = actor.own_turn_count
		for effect in summoned.after_spell.get("effects", []):
			if phase in FINISHED_PHASES or actor.summons[slot] != summoned: break
			if effect.get("target") == "random_opponent":
				effect = effect.duplicate(true)
				var aims := _living_targets(opponent)
				if aims.is_empty(): continue
				effect["selection"] = aims[rng.randi_range(0, aims.size() - 1)]
			summon_triggered.emit(_side(actor), slot, "after_spell", effect)
			_resolve_effect(actor, opponent, effect, summoned.element)

func _flush_deaths() -> void:
	if damage_depth > 0 or flushing_deaths: return
	flushing_deaths = true
	# All deaths in one area segment are removed before any printed death effect.
	while not death_queue.is_empty():
		var batch := death_queue.duplicate()
		death_queue.clear()
		batch.sort_custom(func(a: Dictionary, b: Dictionary): return (0 if a["owner"] == player else 3) + int(a["slot"]) < (0 if b["owner"] == player else 3) + int(b["slot"]))
		for item in batch:
			if _check_finish():
				death_queue.clear()
				flushing_deaths = false
				return
			var owner: Combatant = item["owner"]
			var summoned: Summon = item["summon"]
			var opponent := enemy if owner == player else player
			for effect in summoned.death_effects:
				if phase in FINISHED_PHASES: break
				summon_triggered.emit(_side(owner), int(item["slot"]), "on_death", effect)
				_resolve_effect(owner, opponent, effect, summoned.element)
	flushing_deaths = false

func _receive_card(actor: Combatant, id: String, reason: String) -> void:
	if actor.hand.size() >= 8:
		actor.discard_pile.append(_canonical_card_id(id))
		_report("%s %s：手牌已满，卡牌进入弃牌堆" % [actor.display_name, reason], _side(actor), "draw")
	else:
		actor.hand.append(id)
		_report("%s %s获得1张牌" % [actor.display_name, reason], _side(actor), "draw")

func _contemplate(actor: Combatant, amount: int) -> void:
	if not _ensure_draw_pile(actor): return
	var candidates: Array = actor.draw_pile.slice(0, mini(amount, actor.draw_pile.size()))
	if candidates.is_empty(): return
	if actor == player and candidates.size() > 1 and not replay_choice_indices.is_empty():
		_take_choice_card(actor, clampi(replay_choice_indices.pop_front(), 0, candidates.size() - 1))
		return
	if actor == player and interactive_choices and candidates.size() > 1:
		pending_choice = {"generation":battle_generation, "candidates":candidates}
		call_deferred("_announce_choice")
	else:
		_take_choice_card(actor, _choose_contemplation(actor, candidates))

func _discover(actor: Combatant, amount: int, filters: Dictionary = {}, discount: int = 0) -> void:
	var pool: Array[String] = ContentCatalog.card_pool(cards, filters)
	var candidates: Array = []
	for i in mini(maxi(0, amount), pool.size()):
		candidates.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	if candidates.is_empty(): return
	if actor == player and candidates.size() > 1 and not replay_choice_indices.is_empty():
		_receive_discovery(actor, candidates[clampi(replay_choice_indices.pop_front(), 0, candidates.size() - 1)], discount)
	elif actor == player and interactive_choices and candidates.size() > 1:
		pending_choice = {"generation":battle_generation, "kind":"discover", "candidates":candidates, "discount":discount}
		call_deferred("_announce_choice")
	else:
		_receive_discovery(actor, candidates[_choose_contemplation(actor, candidates)], discount)

func _announce_choice() -> void:
	if pending_choice.is_empty() or int(pending_choice["generation"]) != battle_generation: return
	choice_requested.emit(pending_choice["candidates"], player.hand.size() >= 8)
	changed.emit()

func choose_card(index: int) -> bool:
	if pending_choice.is_empty() or int(pending_choice["generation"]) != battle_generation or phase in FINISHED_PHASES or phase == "menu": return false
	if index < 0 or index >= pending_choice["candidates"].size(): return false
	var continuation: Dictionary = pending_choice.get("continuation", {})
	var kind := str(pending_choice.get("kind", "contemplate"))
	var discount := int(pending_choice.get("discount", 0))
	var id: String = pending_choice["candidates"][index]
	pending_choice.clear()
	if kind == "discover": _receive_discovery(player, id, discount)
	else: _take_choice_card(player, index)
	if not continuation.is_empty():
		_resolve_sequence(continuation["actor"], continuation["opponent"], continuation["effects"], continuation["element"], continuation["selection"], continuation["energy"], continuation["complete"])
	choice_completed.emit()
	changed.emit()
	return true

func _choose_contemplation(actor: Combatant, candidates: Array) -> int:
	var best := 0
	var best_score := -INF
	for i in candidates.size():
		var card: Dictionary = cards[candidates[i]]
		var score := 1.0 - float(actor.card_cost(card)) * 0.15
		for effect in card["effects"]:
			match str(effect["type"]):
				"gain_energy", "gain_random_energy", "draw", "contemplate", "discover", "generate_card": score += 2.0
				"heal": score += minf(float(effect["amount"]), float(actor.max_hp - actor.hp)) * 0.25
				"summon": score += 1.0 if actor.first_free_summon_slot() >= 0 else -2.0
		if actor.can_pay(card): score += 2.0
		if actor == enemy and not choice_scoring and actor.can_pay(card):
			var copy := simulation_copy()
			copy.choice_scoring = true
			copy.phase = "enemy_action"
			for selection in copy._card_candidates(copy.enemy, card):
				if copy.valid_card_target(copy.enemy, card, selection): score = maxf(score, EnemyPolicy.card_score(copy, card, selection))
			copy.free()
		if score > best_score: best_score = score; best = i
	return best

func _card_candidates(actor: Combatant, card: Dictionary) -> Array[Dictionary]:
	var opponent := player if actor == enemy else enemy
	var candidates: Array[Dictionary] = []
	var mode := card_target_mode(card)
	if mode == "none": return [{}]
	if mode == "slot" and summon_requires_target(card):
		for slot in actor.summons.size():
			if actor.summons[slot] != null: continue
			for aim in _living_targets(opponent): candidates.append({"kind":"slot", "slot":slot, "entrance_target":aim})
		return candidates
	if mode in ["damage", "all_summons"]:
		for side in damage_target_sides(actor, card):
			var owner := player if side == "player" else enemy
			if mode == "damage": candidates.append({"kind":"hero", "side":side})
			for slot in 3:
				if owner.summons[slot] != null: candidates.append({"kind":"summon", "side":side, "slot":slot})
	else:
		var owner := actor if mode in ["slot", "ally_summon"] else opponent
		for slot in 3:
			if (mode == "slot") == (owner.summons[slot] == null): candidates.append({"kind":"slot" if mode == "slot" else "summon", "side":_side(owner), "slot":slot})
	return candidates

func _resolve_effect(actor: Combatant, opponent: Combatant, effect: Dictionary, card_element: String, selection: Dictionary = {}, pre_payment_energy: Dictionary = {}) -> void:
	if not _condition_met(effect, actor, pre_payment_energy): return
	var target: Combatant = actor if effect.get("target", "opponent") == "self" else opponent
	var amount := int(effect.get("amount", 0))
	match effect["type"]:
		"damage":
			var attack_element := str(effect.get("element", card_element))
			var resolved_selection := selection
			if selection.has("damage_redirect") and not effect.has("target") and effect.get("scope", "single") == "single":
				resolved_selection = selection["damage_redirect"]
				if opponent.summons[int(resolved_selection["slot"])] != resolved_selection["summon"]: return
			if effect.get("target", "") == "self": resolved_selection = {"kind": "hero", "side": _side(actor)}
			elif effect.get("target", "") == "opponent": resolved_selection = {"kind": "hero", "side": _side(opponent)}
			if effect.get("target", "") == "random_opponent":
				# A card's selected first hit must never pin a later random hit.
				# Only a summon presenter's preselected effect owns its exact aim.
				if effect.has("selection"): resolved_selection = effect["selection"]
				else:
					var candidates := _living_targets(opponent)
					if candidates.is_empty(): return
					resolved_selection = candidates[rng.randi_range(0, candidates.size() - 1)]
					if not _valid_enemy_selection(actor, resolved_selection): return
					random_hit_targeted.emit(_side(actor), attack_element, resolved_selection)
			var plan := _damage_plan(actor, opponent, effect, card_element, resolved_selection)
			# Consume only the attack states used by this segment, before reactions
			# can add states intended for the next attack. Area hits share the plan.
			if not plan.is_empty(): _consume_attack_statuses(actor)
			damage_depth += 1
			var hits: Array[Dictionary] = []
			for hit in plan:
				var dealt: int
				var owner: Combatant = hit["owner"]
				var life_before: int = owner.hp if hit["kind"] == "hero" else owner.summons[int(hit["slot"])].hp
				if hit["kind"] == "hero":
					dealt = _apply_hero_damage(actor, hit["owner"], hit["breakdown"], attack_element)
				else:
					dealt = _apply_summon_hit(actor, hit["owner"], int(hit["slot"]), int(hit["raw"]), attack_element)
				hits.append({"side": _side(hit["owner"]), "kind": hit["kind"], "slot": int(hit.get("slot", -1)), "amount": dealt})
				# The reward belongs to this hit, before the lethal segment ends battle.
				# A reaction killing another unit must not count as this spell's kill.
				if life_before > 0 and dealt >= life_before and actor.hp > 0:
					_resolve_sequence(actor, opponent, effect.get("on_kill", []), card_element)
			damage_segment_resolved.emit(hits)
			damage_depth -= 1
			_flush_deaths()
			_check_finish()
		"summon":
			var slot := int(selection["slot"])
			var template: Dictionary = summon_templates[effect["summon"]]
			var summoned := Summon.new()
			summoned.setup(template)
			actor.summons[slot] = summoned
			_sync_cost_auras()
			_trigger_artifacts(actor, "summon", {"kind": "summon", "side": _side(actor), "slot": slot})
			_report("%s 在槽位 %d 召唤%s" % [actor.display_name, slot + 1, summoned.display_name], _side(actor), "summon", summoned.element, 1)
			summon_event.emit(_side(actor), slot, "spawn", summoned.element, 1, "")
			for entrance in summoned.spawn_effects:
				if phase in FINISHED_PHASES: break
				if not _condition_met(entrance, actor): continue
				var resolved: Dictionary = entrance.duplicate(true)
				if resolved.get("target", "") == "lowest_opponent": resolved["selection"] = lowest_life_target(opponent)
				elif resolved.get("target", "") == "highest_opponent": resolved["selection"] = highest_life_target(opponent)
				elif resolved.get("target") == "selected_opponent": resolved["selection"] = selection.get("entrance_target", {})
				summon_triggered.emit(_side(actor), slot, "on_spawn", resolved)
				_resolve_effect(actor, opponent, resolved, summoned.element, resolved.get("selection", {}))
		"return_summon":
			var slot := int(selection.get("slot", -1))
			if slot < 0 or slot >= actor.summons.size() or actor.summons[slot] == null: return
			var summoned: Summon = actor.summons[slot]
			if not cards.has(summoned.card_id): return
			actor.summons[slot] = null
			_sync_cost_auras()
			# The summon contract has resolved as a spell; returning the spirit
			# produces its same-grade contract without a death event.
			_receive_card(actor, _discounted_card(actor, summoned.card_id, int(effect.get("cost_reduction", 0))), "收回")
			summon_event.emit(_side(actor), slot, "return", summoned.element, 0, "")
		"sacrifice_summon":
			var slot := int(selection.get("slot", -1))
			if slot < 0 or slot >= actor.summons.size() or actor.summons[slot] == null: return
			var summoned: Summon = actor.summons[slot]
			var base := mini(int(effect["base_cap"]), floori(summoned.max_hp * float(effect["multiplier"])))
			summoned.hp = 0
			actor.summons[slot] = null
			_sync_cost_auras()
			_finish_summon_death(actor, slot, summoned, card_element)
			_flush_deaths()
			if not _check_finish(): _resolve_effect(actor, opponent, {"type":"damage", "target":"opponent", "amount":base, "element":card_element}, card_element)
		"heal_selected":
			var resolved := effect.duplicate(true)
			resolved["type"] = "heal_summon" if selection.get("kind", "") == "summon" else "heal"
			resolved["target"] = "self"
			_resolve_effect(actor, opponent, resolved, card_element, selection)
		"heal":
			if target.hp <= 0: return
			var actual := maxi(0, mini(amount, target.max_hp - target.hp))
			target.hp += actual
			_report("%s 恢复 %d 生命" % [target.display_name, actual], _side(target), "heal", card_element, actual)
			_on_healed(target, actual)
		"heal_summon", "grow_summon":
			var selected_side := str(selection.get("side", _side(actor)))
			var owner := player if selected_side == "player" else enemy
			var selected_slot := int(selection.get("slot", -1))
			if selected_slot < 0 or selected_slot >= owner.summons.size() or owner.summons[selected_slot] == null: return
			var selected: Summon = owner.summons[selected_slot]
			if selected.hp <= 0: return
			if effect["type"] == "grow_summon": selected.max_hp += amount
			var healed := mini(amount, selected.max_hp - selected.hp)
			selected.hp += healed
			_report("%s %s %d 点生命" % [selected.display_name, "增加" if effect["type"] == "grow_summon" else "恢复", healed], _side(owner), "summon_heal", card_element, healed)
			summon_event.emit(_side(owner), selected_slot, "heal", card_element, healed, "")
			if effect["type"] == "heal_summon": _on_healed(owner, healed)
		"lose_qi":
			var lost := mini(target.qi, amount)
			target.qi -= lost
			_report("%s 失去%d点真气" % [target.display_name, lost], _side(target), "qi_loss", "", lost)
		"gain_qi":
			target.qi += amount
			_report("%s 获得%d点真气" % [target.display_name, amount], _side(target), "qi_gain", "", amount)
		"shield_heal":
			var shield := actor.status_stacks("shield")
			actor.remove_status("shield")
			_resolve_effect(actor, opponent, {"type":"heal", "target":"self", "amount":mini(shield, amount)}, card_element)
		"heal_lowest_ally":
			var aim := lowest_life_target(actor)
			_resolve_effect(actor, opponent, {"type":"heal_selected", "amount":amount}, card_element, aim)
		"grow_all_summons":
			for slot in actor.summons.size():
				if actor.summons[slot] != null and actor.summons[slot].hp > 0:
					_resolve_effect(actor, opponent, {"type":"grow_summon", "amount":amount}, card_element, {"kind":"summon", "side":_side(actor), "slot":slot})
		"draw":
			for i in amount:
				if phase in FINISHED_PHASES:
					break
				draw_card(target)
		"contemplate": _contemplate(target, amount)
		"discover": _discover(target, amount, effect.get("pool", {}), int(effect.get("cost_reduction", 0)))
		"generate_card":
			var pool: Array[String] = []
			for entry: Dictionary in ContentCatalog.base_entries(cards):
				if str(effect.get("element", "")) != "" and entry["element"] != effect["element"]: continue
				var recursive := false
				for part in entry["effects"]:
					if part["type"] == "generate_card": recursive = true
				if not recursive: pool.append(str(entry["id"]))
			for i in amount:
				if pool.is_empty(): break
				_receive_card(target, pool[rng.randi_range(0, pool.size() - 1)], "生牌")
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
			var stacks := _effect_status_stacks(target, effect)
			target.add_status(status_id, stacks, int(effect.get("turns", 0)), element)
			var detail := " · %s" % BattleRules.element_name(element) if element != "" else ""
			_report("%s 获得 %d 层%s%s" % [target.display_name, stacks, STATUS_NAMES.get(status_id, status_id), detail], _side(target), "status_" + status_id, card_element, stacks)
		"remove_status":
			var status_id: String = effect["status"]
			var removed := target.status_stacks(status_id)
			target.remove_status(status_id)
			_report("%s 解除%s" % [target.display_name, STATUS_NAMES.get(status_id, status_id)], _side(target), "shield_loss" if status_id == "shield" else "status_remove", card_element, removed)
		"reduce_status":
			var status_id: String = effect["status"]
			var removed := target.reduce_status(status_id, amount)
			_report("%s 降低%d层%s" % [target.display_name, removed, STATUS_NAMES.get(status_id, status_id)], _side(target), "status_remove", card_element, removed)
		"break_shield":
			var removed := mini(amount, target.status_stacks("shield"))
			if removed > 0: _absorb_shield(target, removed)
			_report("%s 失去 %d 层护盾" % [target.display_name, removed], _side(target), "shield_loss", card_element, removed)
		"discard":
			for i in amount:
				if target.hand.is_empty():
					break
				var random_index := rng.randi_range(0, target.hand.size() - 1)
				hand_card_removed.emit(_side(target), target.hand[random_index], random_index, "discard")
				var lost_card: String = target.hand.pop_at(random_index)
				target.discard_pile.append(_canonical_card_id(lost_card))
				_report("%s 被弃掉 1 张手牌" % target.display_name, _side(target), "discard")

func apply_damage(source: Combatant, target: Combatant, base_amount: int, element: String) -> int:
	var breakdown := BattleRules.damage_breakdown(target, base_amount, element, source)
	_consume_attack_statuses(source)
	var dealt := _apply_hero_damage(source, target, breakdown, element)
	_check_finish()
	return dealt

func _apply_hero_damage(source: Combatant, target: Combatant, breakdown: Dictionary, element: String) -> int:
	var raw: int = breakdown["raw"]
	var shielded: int = breakdown["shield"]
	var dealt := mini(target.hp, int(breakdown["hp"]))
	_absorb_shield(target, shielded)
	_consume_defense_statuses(target)
	target.hp = maxi(0, target.hp - dealt)
	if bool(breakdown.get("resistance_used", false)):
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
	if raw > 0 and target.hp > 0 and phase not in FINISHED_PHASES:
		_trigger_artifacts(target, "damage_received")
		if not target.artifact_flags.get("own_turn_hit", false) and phase.begins_with(_side(target) + "_"):
			target.artifact_flags["own_turn_hit"] = true
			_trigger_artifacts(target, "first_hit_own_turn")
	if raw > 0 and target.hp > 0 and not target.artifact_flags.get("enemy_turn_hit", false) and phase.begins_with("enemy_" if target == player else "player_"):
		target.artifact_flags["enemy_turn_hit"] = true
		_trigger_artifacts(target, "first_hit_enemy_turn")
	return dealt

func apply_summon_damage(source: Combatant, owner: Combatant, slot: int, base_amount: int, element: String) -> int:
	if slot < 0 or slot >= owner.summons.size() or owner.summons[slot] == null:
		return 0
	var summoned: Summon = owner.summons[slot]
	var raw := BattleRules.summon_damage(base_amount, source, summoned.element, element)
	_consume_attack_statuses(source)
	var dealt := _apply_summon_hit(source, owner, slot, raw, element)
	return dealt

func _apply_summon_hit(source: Combatant, owner: Combatant, slot: int, raw: int, element: String) -> int:
	if slot < 0 or slot >= owner.summons.size() or owner.summons[slot] == null: return 0
	var summoned: Summon = owner.summons[slot]
	if summoned.hp <= 0: return 0
	var dealt := mini(summoned.hp, raw)
	summoned.hp -= dealt
	if source == player and owner != player:
		player_damage += dealt
	var matchup := BattleRules.summon_matchup(summoned.element, element)
	var note := " · " + matchup if matchup != "" else ""
	_report("%s 受到 %d 点%s伤害%s" % [summoned.display_name, dealt, BattleRules.element_name(element), note], _side(owner), "summon_damage", element, dealt)
	summon_event.emit(_side(owner), slot, "damage", element, dealt, matchup)
	var destroyed := summoned.hp <= 0
	if destroyed:
		owner.summons[slot] = null
		_sync_cost_auras()
	if dealt > 0 and owner.hp > 0 and phase not in FINISHED_PHASES: _trigger_artifacts(owner, "ally_summon_hit")
	if destroyed: _finish_summon_death(owner, slot, summoned, element)
	return dealt

func _finish_summon_death(owner: Combatant, slot: int, summoned: Summon, element: String) -> void:
	_trigger_artifacts(owner, "ally_summon_death")
	var opponent: Combatant = enemy if owner == player else player
	if opponent.hp > 0: _trigger_artifacts(opponent, "enemy_summon_death")
	_report("%s 被摧毁，槽位 %d 空出" % [summoned.display_name, slot + 1], _side(owner), "summon_destroy", element)
	summon_event.emit(_side(owner), slot, "destroy", element, 0, "")
	if not summoned.death_effects.is_empty():
		death_queue.append({"owner":owner, "slot":slot, "summon":summoned})
		_flush_deaths()

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
			_on_healed(actor, healed)
		actor.decay_status("regen")
	actor.decay_status("weak")
	actor.decay_status("vulnerable")
	actor.decay_status("charge")
	actor.decay_status("tenacity")
	actor.tick_status_durations()
	_trigger_artifacts(actor, "turn_end")
	if phase in FINISHED_PHASES: return
	await _trigger_summons(actor, "turn_end")
	for i in actor.hand.size():
		var entry: Dictionary = cards[actor.hand[i]]
		if entry.get("battle_only", false) and int(entry.get("discount_turn", -1)) >= 0: actor.hand[i] = _canonical_card_id(actor.hand[i])
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
	if phase != "player_action" or not pending_choice.is_empty():
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
	if action_kind == "qi":
		convert_qi(enemy, str(selection.get("element", "")))
		return phase == "enemy_action"
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
		var needed := maxi(0, enemy.card_cost(card) - int(enemy.energy[card["element"]]))
		if not enemy.can_pay(card) and (needed <= 0 or needed > enemy.qi or enemy.status_stacks("lock", card["element"]) > 0): continue
		var candidates := _card_candidates(enemy, card)
		for selection in candidates:
			var score := EnemyPolicy.funded_card_score(self, card, selection) if needed > 0 else _enemy_action_score(card, selection)
			score += rng.randf_range(-3.0, 3.0)
			if score > best_score:
				best_score = score
				best_action = {"kind":"qi", "index":-1, "target":{"element":card["element"]}} if needed > 0 else {"kind":"card", "index":i, "target":selection}
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
	var report := {"version": 1, "seed": str(battle_seed), "first_side": first_side, "enemy": selected_enemy_id, "deck_name": selected_deck_name, "phase": phase, "round": round_number, "player_deck": player.initial_deck, "enemy_deck": enemy.initial_deck, "player_artifacts": player.artifacts, "enemy_artifacts": enemy.artifacts, "events": events}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(JSON.stringify(report, "  "))
	file.flush()
	return ProjectSettings.globalize_path(path) if file.get_error() == OK else ""
