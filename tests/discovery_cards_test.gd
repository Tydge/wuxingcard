extends "res://tests/ash_cleanse_cards_test.gd"

const EXPANSION := ["metal_forge_edge", "water_breath_wisp_card", "wood_rain_slash", "fire_kindling", "earth_seek_treasure"]

func run() -> void:
	m = BattleManager.new(); m.random_artifacts_enabled = false; root.add_child(m)
	check(m.cards.size() == 285 and m.summon_templates.size() == 96, "95 card families and 32 summons have all three grades")
	for level in 3:
		var metal := ContentCatalog.variant_id(EXPANSION[0], level)
		for defense in [0, 7]:
			clean(); m.player.add_status("strong_defense", defense, 0); m.player.add_status("weak_attack", 2, 0)
			m.player.draw_pile.assign(["water_strike"])
			check(m.display_card(m.player, m.cards[metal])["effects"][0]["display_stacks"] == defense, "metal face follows defense count")
			check(cast(metal) and m.player.status_stacks("strong_attack") == maxi(0, defense - 2) and m.player.status_stacks("strong_defense") == defense, "defense copied without consumption and attack opposition applies")
			check(m.player.hand.size() == (0 if level == 0 else 1) and m.cards[metal]["cost"] == [1,1,0][level], "metal upgrades draw once with correct cost")
		var water := ContentCatalog.variant_id(EXPANSION[1], level)
		clean(); m.enemy.qi = 4
		check(cast(water, {"kind":"slot", "slot":0}) and m.player.summons[0].hp == [20,24,28][level] and m.enemy.qi == 4, "water summon HP and aura leave stored qi intact")
		await m._start_turn(m.enemy)
		check(m.enemy.qi == 4 and m.phase == "enemy_action", "opposing turn-start gain suppressed")
		m._resolve_effect(m.player, m.enemy, {"type":"gain_qi", "amount":2}, "water")
		check(m.enemy.qi == 6, "aura does not suppress card qi gains")
		m.apply_summon_damage(m.enemy, m.player, 0, 100, "earth")
		await m._start_turn(m.enemy)
		check(m.enemy.qi == 7, "destroyed summon restores natural qi")
		var wood := ContentCatalog.variant_id(EXPANSION[2], level)
		for water_energy in [2,3]:
			clean(); m.player.hp = 100; m.player.energy["water"] = water_energy
			check(cast(wood, {"kind":"hero","side":"enemy"}) and m.enemy.hp == 200 - [30,34,38][level] and m.player.hp == 100 + ([15,18,21][level] if water_energy == 3 else 0), "wood damage and water-three healing boundary")
		var fire := ContentCatalog.variant_id(EXPANSION[3], level)
		for wood_energy in [0,3,10]:
			clean(); m.player.energy["fire"] = 1; m.player.hand.assign([fire]); m.player.energy["wood"] = wood_energy; m.player.add_status("strong_attack", 2, 0)
			var amount := floori(wood_energy * float([2,2.5,3][level])) + 2
			check(m.display_card(m.player, m.cards[fire])["effects"][0]["display_amount"] == amount, "fire face floors fractional base then applies attack")
			check(m.preview_damage_segments(m.player, m.cards[fire], {"kind":"hero","side":"enemy"}) == [amount] and m.player.status_stacks("strong_attack") == 2, "fire preview uses isolated shared resolver")
			check(cast(fire, {"kind":"hero","side":"enemy"}) and m.enemy.hp == 200 - amount and m.player.energy["wood"] == wood_energy and m.player.status_stacks("strong_attack") == 1, "fire matches preview without consuming wood")
		var earth := ContentCatalog.variant_id(EXPANSION[4], level)
		clean(); m.interactive_choices = true; m.player.draw_pile.assign(["metal_strike__2"])
		m.player.hand.assign([earth]); m.player.energy["earth"] = 1
		check(m.play_player_card(0) and m.pending_choice.get("kind") == "discover" and m.pending_choice["candidates"].size() == 2 + level, "earth opens level-dependent discovery")
		var candidates: Array = m.pending_choice["candidates"].duplicate()
		var distinct := {}
		for id: String in candidates: distinct[id] = true; check(m.cards[id]["level"] == level, "discovery inherits triggering card grade")
		check(distinct.size() == candidates.size() and m.player.draw_pile == ["metal_strike__2"] and m.player.fatigue_level == 0, "discover unique candidates without using deck or fatigue")
		check(not m.choose_card(-1) and not m.choose_card(candidates.size()) and not m.play_player_card(0), "invalid choices and additional plays rejected")
		m.end_player_turn(); check(m.phase == "player_action", "pending discovery blocks end turn")
		check(m.choose_card(1) and m.player.hand == [candidates[1]] and m.player.discard_pile == [earth] and not m.choose_card(1), "exactly one generated card and one completed spell")
	clean(); m.interactive_choices = true
	var filters := {"elements":["water"], "card_types":["summon"], "min_cost":8, "max_cost":8, "levels":[2]}
	check(ContentCatalog.card_pool(m.cards, filters) == ["water_breath_wisp_card__2"], "pool supports combined element, type, cost and grade limits")
	m._discover(m.player, 4, filters, 0, 2)
	check(m.player.hand == ["water_breath_wisp_card__2"] and m.pending_choice.is_empty(), "undersized filtered pool preserves grade and auto-selects sole result")
	check(ContentCatalog.card_pool(m.cards, {"include_ids":["metal_strike","water_strike"], "exclude_ids":["metal_strike"], "effect_types":["damage"]}) == ["water_strike"], "explicit IDs, exclusions and effect types combine")
	m._discover(m.player, 4, {"elements":[]})
	check(m.player.hand.size() == 1 and m.pending_choice.is_empty(), "empty restricted pool completes without choice")
	m._discover(m.player, 99, {"include_ids":["metal_strike","water_strike"]})
	check(m.pending_choice["candidates"].size() == 2, "N is bounded by available pool size")
	m.choose_card(0)
	clean(); m.interactive_choices = true; m.player.hand.assign(["metal_strike","metal_strike","metal_strike","metal_strike","metal_strike","metal_strike","metal_strike","metal_strike"])
	m._discover(m.player, 3); var chosen: String = m.pending_choice["candidates"][2]; m.choose_card(2)
	check(m.player.hand.size() == 8 and m.player.discard_pile == [chosen] and m.player.hp == 200, "full-hand discovery discards only selected card without fatigue")
	clean(); m.interactive_choices = true
	m._resolve_sequence(m.player, m.enemy, [{"type":"discover","target":"self","amount":3}, {"type":"gain_qi","target":"self","amount":2}], "earth")
	check(m.player.qi == 3, "subsequent effects wait for choice")
	m.choose_card(0); check(m.player.qi == 5, "subsequent effects resume once")
	# A later discovery in the same spell must retain grade after the first choice.
	clean(); m.interactive_choices = true
	var scoped := {"elements":["water"], "card_types":["spell"]}
	m._resolve_sequence(m.player, m.enemy, [{"type":"discover", "target":"self", "amount":2}, {"type":"discover", "target":"self", "amount":2, "pool":scoped}], "earth", {}, {}, Callable(), 2)
	m.choose_card(0)
	check(m.pending_choice.get("kind") == "discover" and scoped == {"elements":["water"], "card_types":["spell"]}, "resumed discovery preserves filters without mutating caller")
	for id: String in m.pending_choice["candidates"]: check(m.cards[id]["level"] == 2 and m.cards[id]["element"] == "water", "resumed discovery keeps source grade and restricted scope")
	m.choose_card(0)
	for level in 3:
		clean(); m.phase = "enemy_action"
		var id := ContentCatalog.variant_id("earth_seek_treasure", level)
		m.enemy.hand.assign([id]); m.enemy.energy["earth"] = 1
		var simulation := m.simulation_copy()
		simulation._play_card(simulation.enemy, simulation.player, 0)
		check(simulation.cards[simulation.enemy.hand[0]]["level"] == level and m.enemy.hand == [id], "AI discovery keeps source grade in isolated simulation")
		simulation.free()
	clean(); m.interactive_choices = true; m.rng.seed = 4242; m.player.hand.assign(["earth_seek_treasure__2"]); m.player.energy["earth"] = 1
	m.play_player_card(0); chosen = m.pending_choice["candidates"][2]; m.choose_card(2); var state := m.rng.state
	clean(); m.rng.seed = 4242; m.replay_choice_indices.assign([2]); m.player.hand.assign(["earth_seek_treasure__2"]); m.player.energy["earth"] = 1
	check(m.play_player_card(0) and m.player.hand == [chosen] and m.rng.state == state and m.replay_choice_indices.is_empty(), "seeded replay recovers same discovered card and RNG state")
	clean(); m.interactive_choices = true; m._discover(m.player, 2); m.battle_generation += 1
	check(not m.choose_card(0) and m.player.hand.is_empty(), "stale generation choice cannot create card")
	clean(); m.interactive_choices = false
	for id: String in EXPANSION:
		clean(); m.phase = "enemy_action"; m.enemy.hand.assign([id]); m.enemy.energy[m.cards[id]["element"]] = m.cards[id]["cost"]
		m.enemy.energy["wood"] = 4 if id == "fire_kindling" else m.enemy.energy["wood"]; m.enemy.add_status("strong_defense", 7, 0)
		var selection := {"kind":"slot","slot":0} if id == "water_breath_wisp_card" else {"kind":"hero","side":"player"} if id in ["wood_rain_slash","fire_kindling"] else {}
		state = m.rng.state
		check(EnemyPolicy.card_score(m, m.cards[id], selection) > 0 and m.rng.state == state and m.player.hp == 200 and m.enemy.hand == [id], "AI scores new effect in detached copy: " + id)
		check(m._play_card(m.enemy, m.player, 0, selection) and m.pending_choice.is_empty(), "enemy settles new effect automatically: " + id)
	clean(); creature(m.player, 0, "water"); creature(m.player, 1, "water")
	for s: Summon in m.player.summons:
		if s != null: s.enemy_qi_gain_reduction = 1
	m.enemy.qi = 0; await m._start_turn(m.enemy)
	check(m.enemy.qi == 0 and m.turn_start_qi_gain(m.player) == 1, "multiple auras floor natural gain at zero and spare owner")
	# Runtime wording is exported for the manually maintained catalogue.
	DirAccess.make_dir_recursive_absolute("res://work/discovery_20261003")
	FileAccess.open("res://work/discovery_20261003/card_texts.json", FileAccess.WRITE).store_string(JSON.stringify(m.cards, "  "))
	print("Discovery cards: %d assertions, %d failures" % [assertions, failures]); m.queue_free(); quit(1 if failures else 0)
