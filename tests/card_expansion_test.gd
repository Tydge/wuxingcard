extends SceneTree

var failures := 0
var manager: BattleManager

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func prepare() -> void:
	manager.start_battle("ember", "balanced", 141)
	for actor in [manager.player, manager.enemy]:
		actor.statuses.clear()
		actor.hp = 80
		actor.summons = [null, null, null]
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.phase = "player_action"

func cast(id: String, selection: Dictionary = {}) -> bool:
	manager.player.hand = [id, "metal_strike", "wood_strike"]
	manager.player.energy[manager.cards[id]["element"]] = int(manager.cards[id]["cost"])
	return manager.play_player_card(0, selection)

func run() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	prepare()
	check(cast("wood_to_fire") and manager.player.energy["wood"] == 0 and manager.player.energy["fire"] == 3, "wood-to-fire needs only its two-cost payment")
	prepare()
	check(cast("water_mist") and manager.enemy.status_stacks("vulnerable") == 2, "mist grants two vulnerable layers")
	prepare()
	manager.player.hp = 50
	check(cast("wood_regen") and manager.player.status_stacks("regen") == 5, "regeneration spell grants five layers")
	await manager._end_turn(manager.player)
	check(manager.player.hp == 55 and manager.player.status_stacks("regen") == 4, "five-layer regeneration heals five then decays once")
	prepare()
	manager.player.hp = 50
	manager.player.summons[0] = Summon.new()
	manager.player.summons[0].setup(manager.summon_templates["wood_seedling"])
	manager.player.summons[0].hp = 7
	check(cast("wood_heal") and manager.player.hp == 68, "life spell restores eighteen to its caster")
	check(manager.player.summons[0].hp == 7 and manager.enemy.hp == 80, "life spell does not heal summons or the opponent")
	prepare()
	check(cast("metal_rainbow_blade", {"kind":"hero"}) and manager.enemy.hp == 60, "metal spell deals twenty")
	prepare()
	manager.player.add_status("poison", 2, 0)
	check(cast("wood_spirit_vine", {"kind":"hero"}) and manager.enemy.hp == 66, "wood spell deals fourteen")
	var energy := 0
	for element in BattleRules.ELEMENTS: energy += int(manager.player.energy[element])
	check(energy == 1 and manager.player.hp == 78 and manager.player.status_stacks("poison") == 1, "one random gain triggers poison once")
	# Only one eligible attribute: capped and locked attributes must never be chosen.
	for element in BattleRules.ELEMENTS: manager.player.energy[element] = 10
	manager.player.energy["metal"] = 0
	manager.player.add_status("lock", 1, 2, "wood")
	manager.player.energy["wood"] = 0
	manager._resolve_effect(manager.player, manager.enemy, {"type":"gain_random_energy","target":"self","amount":1}, "wood")
	check(manager.player.energy["metal"] == 1 and manager.player.energy["wood"] == 0, "random energy excludes capped and locked attributes")
	prepare()
	check(cast("wood_miasma") and manager.enemy.status_stacks("poison") == 5, "poison spell grants five layers")
	prepare()
	check(cast("water_returning_tide", {"kind":"hero"}) and manager.enemy.hp == 65 and manager.player.hp == 85, "water damage and self healing both resolve")
	prepare()
	manager.enemy.summons[0] = Summon.new()
	manager.enemy.summons[0].setup(manager.summon_templates["wood_seedling"])
	check(cast("fire_scorch", {"kind":"summon","slot":0}) and manager.enemy.summons[0] == null and manager.enemy.hp == 80 and manager.enemy.status_stacks("burn") == 1, "scorch may target summon but burn always goes to enemy hero")
	prepare()
	for slot in 3:
		manager.enemy.summons[slot] = Summon.new()
		manager.enemy.summons[slot].setup(manager.summon_templates[["metal_furnace", "fire_lantern", "water_spring"][slot]])
	manager.enemy.add_status("shield", 4, 0)
	check(manager.preview_damage_segments(manager.player, manager.cards["fire_burning_field"], {"kind":"summon","slot":1}) == [10], "area spell preview uses the pointed summon resistance")
	check(cast("fire_burning_field", {"kind":"summon","slot":1}), "area spell accepts any opponent as aim")
	check(manager.enemy.hp == 64 and manager.enemy.summons[0] == null and manager.enemy.summons[1].hp == 5 and manager.enemy.summons[2] == null, "area spell independently resolves all targets, affinity and hero shield")
	check(manager.player.hp == 80 and manager.player.summons == [null,null,null], "area spell leaves own side untouched")
	prepare()
	check(cast("earth_stone_guard", {"kind":"hero"}) and manager.enemy.hp == 64 and manager.player.status_stacks("shield") == 8, "earth damage grants eight shield layers")
	prepare()
	check(cast("earth_mountain_seal", {"kind":"hero"}) and manager.enemy.hp == 45 and manager.player.hand.size() == 1 and manager.player.discard_pile.size() == 2, "mountain damage precedes one random own discard")
	prepare()
	manager.player.add_status("poison", 5, 0)
	check(cast("water_four_aspects"), "four-aspect energy spell is playable")
	for element in ["metal","wood","fire","earth"]: check(manager.player.energy[element] == 1, "four-aspect energy: " + element)
	check(manager.player.energy["water"] == 0 and manager.player.hp == 66 and manager.player.status_stacks("poison") == 1, "four separate energy events trigger 5+4+3+2 poison loss")
	prepare()
	check(cast("earth_transmute_metal") and manager.player.energy["metal"] == 3, "earth spell generates three metal energy")
	manager.start_battle("ember", "random", 140)
	manager.player.hp = 78
	for element in BattleRules.ELEMENTS: manager.enemy.energy[element] = 0
	check(cast("water_returning_tide", {"kind":"hero"}) and manager.player.hp == 80, "test-mode healing respects its eighty-point maximum")
	prepare()
	manager.enemy.hp = 1
	manager.enemy.summons[0] = Summon.new()
	manager.enemy.summons[0].setup(manager.summon_templates["metal_furnace"])
	check(cast("fire_burning_field", {"kind":"hero"}) and manager.phase == "victory" and manager.enemy.summons[0] == null, "lethal area damage still resolves the summons")
	var seen := {}
	for seed_value in 400:
		manager.start_battle("ember", "random", seed_value)
		for actor in [manager.player, manager.enemy]:
			check(actor.max_hp == 80 and actor.hp == 80, "test mode starts both heroes at 80 / 80")
			var deck: Array = actor.hand + actor.draw_pile + actor.discard_pile
			check(manager.valid_random_deck(deck), "random deck size, copy cap and cost guardrails")
			for id in deck: seen[id] = true
	check(seen.size() == manager.cards.size(), "random sampling includes every current card")
	var first := manager.player.hand + manager.player.draw_pile
	manager.start_battle("ember", "random", 399)
	check(first == manager.player.hand + manager.player.draw_pile, "seeded random deck generation is reproducible")
	var too_expensive: Array[String] = []
	for id in manager.cards:
		if int(manager.cards[id]["cost"]) < 2: continue
		for copy in 3:
			if too_expensive.size() < 25: too_expensive.append(id)
	check(not manager.valid_random_deck(too_expensive), "high-cost decks are rejected")
	for seed_value in 30:
		manager.start_battle("ember", "random", seed_value + 700)
		var steps := 0
		while manager.phase not in BattleManager.FINISHED_PHASES and steps < 1000:
			steps += 1
			if manager.phase == "player_action":
				var played := false
				for index in manager.player.hand.size():
					var card: Dictionary = manager.cards[manager.player.hand[index]]
					var selection := {"kind":"hero"}
					if manager.card_target_mode(card) == "slot": selection = {"kind":"slot","slot":manager.player.first_free_summon_slot()}
					if manager.player.can_pay(card) and manager.valid_card_target(manager.player, card, selection):
						played = manager.play_player_card(index, selection)
						break
				if not played: manager.end_player_turn()
			elif manager.phase == "enemy_action": manager.enemy_step()
			else:
				check(false, "random battle stalled: " + manager.phase)
				break
			for actor in [manager.player,manager.enemy]:
				check(actor.hp >= 0 and actor.hp <= 80, "random battle preserves eighty-point HP bounds")
		check(steps < 1000, "random battle completes: %d" % seed_value)
	print("Card expansion test: ten spells, area damage, energy events, 800 random decks and 30 complete random battles; %d failures" % failures)
	quit(1 if failures > 0 else 0)
