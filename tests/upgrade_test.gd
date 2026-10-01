extends SceneTree

var failures := 0
var manager: BattleManager

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func prepare() -> void:
	manager.interactive_choices = false
	manager.start_battle("ember", "balanced", 871)
	for actor in [manager.player, manager.enemy]:
		actor.max_hp = 100
		actor.hp = 60
		actor.statuses.clear()
		actor.summons = [null, null, null]
		actor.hand.clear()
		actor.discard_pile.clear()
		actor.draw_pile.assign(["metal_strike", "wood_heal", "fire_brand", "water_strike"])
		actor.artifact_flags.clear()
		manager._equip_loadout(actor, {})
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.phase = "player_action"

func cast(id: String, selection: Dictionary = {}) -> bool:
	manager.player.hand = [id]
	manager.player.energy[manager.cards[id]["element"]] = int(manager.cards[id]["cost"])
	return manager.play_player_card(0, selection)

func creature(actor: Combatant, slot: int, id: String) -> void:
	actor.summons[slot] = Summon.new()
	actor.summons[slot].setup(manager.summon_templates[id])

func run() -> void:
	manager = BattleManager.new()
	manager.random_artifacts_enabled = false
	root.add_child(manager)
	check(manager.cards.size() == 180 and manager.summon_templates.size() == 60 and manager.artifacts.size() == 45, "all 75 families contain three distinct versions")
	check(manager.cards["water_spring_card"]["text"] == "回合开始：召唤者获得1点木能量。", "spring description names the actual energy recipient")
	check(manager.cards["water_spring_card__1"]["text"] == "回合开始：召唤者获得1点木能量，恢复2点生命。", "spring upgrades share concise caster wording")
	check(manager.cards["water_spring_card__2"]["text"] == "回合开始：召唤者获得1点木能量，恢复4点生命。", "spring second upgrade uses the same format")
	check(manager.cards["water_four_aspects"]["text"] == "获得金、木、火、土能量各1点。" and manager.cards["water_four_aspects__1"]["text"] == manager.cards["water_four_aspects"]["text"], "four aspects retains its concise original wording")
	check(manager.cards["water_four_aspects__2"]["text"] == "获得金、木、火、土能量各1点，抽1张牌。", "four aspects second upgrade adds only its extra effect")
	check(manager.cards["metal_ward__1"]["text"] == "获得16层护盾、1层强防。", "parallel statuses share one verb")
	check(manager.cards["wood_shared_miasma__2"]["text"] == "双方获得6层中毒。", "symmetric statuses use both sides")
	check(manager.cards["water_drain__1"]["text"] == "对手失去3点火能量，自身获得1点水能量。", "short wording keeps opposite recipients unambiguous")
	check(manager.cards["wood_spirit_vine__2"]["text"].contains("获得1点随机能量两次"), "independent random gains remain explicitly separate")
	for pair in [["metal_furnace_card", "water"], ["wood_seedling_card", "fire"], ["water_spring_card", "wood"], ["fire_lantern_card", "earth"], ["earth_stele_card", "metal"]]:
		prepare()
		check(cast(pair[0], {"kind":"slot", "slot":0}), "summon energy source")
		await manager._trigger_summons(manager.player)
		check(manager.player.energy[pair[1]] == 1 and manager.enemy.energy[pair[1]] == 0 and manager.cards[pair[0]]["text"].contains("召唤者获得1点"), "implicit caster description agrees with settlement: " + pair[0])
	for level in 3:
		var id := "metal_thunder_ruler" + ("__%d" % level if level > 0 else "")
		for own_side in ["player", "enemy"]:
			prepare()
			var actor: Combatant = manager.player if own_side == "player" else manager.enemy
			var opponent: Combatant = manager.enemy if own_side == "player" else manager.player
			manager.phase = own_side + "_action"
			creature(opponent, 0, "earth_stele")
			var summon_hp: int = opponent.summons[0].hp
			manager._equip_loadout(actor, {"implement":id})
			check(manager.artifact_target_mode(actor) == "none" and not manager.activate_artifact(actor, {"kind":"summon", "side":"enemy" if own_side == "player" else "player", "slot":0}), "ruler cannot be redirected to a summon")
			check(manager.activate_artifact(actor) and opponent.hp == 60 - (5 if level == 0 else 7) and opponent.summons[0].hp == summon_hp and actor.hp == 60, "all ruler grades hit only the opposing hero from either side")
	for entry: Dictionary in manager.cards.values():
		prepare()
		creature(manager.player, 0, "earth_stele")
		creature(manager.enemy, 0, "earth_stele")
		var targets := manager._card_candidates(manager.player, entry)
		check(not targets.is_empty() and cast(str(entry["id"]), targets[0]), "playable definition: " + str(entry["name"]))
		check(not str(entry["text"]).is_empty(), "generated complete description: " + str(entry["name"]))
		check(entry["art_id"] == entry["base_id"] and ResourceLoader.exists("res://assets/cards/generated/%s.webp" % entry["art_id"]), "all levels reuse existing art")
	for entry: Dictionary in manager.artifacts.values():
		prepare()
		manager._equip_loadout(manager.player, {entry["slot"]:entry["id"]})
		if entry["slot"] == "implement":
			var target := {"kind":"hero", "side":"enemy"} if entry["target_mode"] == "enemy" else {"kind":"hero", "side":"player"} if entry["target_mode"] == "self_or_ally_summon" else {}
			check(manager.activate_artifact(manager.player, target), "activate: " + str(entry["name"]))
			check(manager.player.artifact_ready_turn == manager.player.own_turn_count + int(entry["cooldown"]), "displayed cooldown equals actual interval")
		check(not str(entry["description"]).is_empty(), "artifact generated text")

	prepare()
	check(cast("wood_strike__2", {"kind":"hero"}) and manager.enemy.hp == 46 and manager.enemy.status_stacks("bleed") == 4, "thorn upgrade deals fourteen and adds four bleed")
	manager.phase = "enemy_action"
	manager.enemy.hand = ["fire_gather", "metal_forge"]
	manager._play_card(manager.enemy, manager.player, 0)
	manager._play_card(manager.enemy, manager.player, 0)
	check(manager.enemy.hp == 39 and manager.enemy.status_stacks("bleed") == 2, "four bleed layers lose four then three on zero-cost cards")
	prepare()
	manager.player.hp = 2
	manager.player.add_status("bleed", 2, 0)
	check(cast("wood_heal__2") and manager.player.hp == 0 and manager.phase == "defeat", "lethal bleed prevents the thirty-point heal")

	prepare()
	manager.player.add_status("poison", 3, 0)
	manager._equip_loadout(manager.player, {"guard":"fire_ember_robe__2"})
	check(cast("wood_spirit_vine__2", {"kind":"hero"}), "double random energy spell")
	var total := 0
	for value in manager.player.energy.values(): total += int(value)
	check(total == 2 and manager.player.hp == 55 and manager.player.status_stacks("poison") == 1, "separate rolls trigger 3+2 poison")
	check(manager.enemy.hp == 34 and manager.player.artifact_durability == 4, "first-energy robe fires only once")

	prepare()
	var pile := manager.player.draw_pile.duplicate()
	var initial_deck := manager.player.initial_deck.duplicate()
	check(cast("metal_forge__2") and manager.player.energy["metal"] == 2 and manager.player.hand.size() == 1, "alchemy adds two energy and one generated card")
	check(manager.player.draw_pile == pile and manager.player.initial_deck == initial_deck and int(manager.cards[manager.player.hand[0]]["level"]) == 0, "generation preserves draw pile and original deck and gives base level")
	prepare()
	manager.player.hand.assign(["fire_brand", "fire_brand", "metal_strike", "metal_strike", "water_strike", "water_strike", "wood_heal", "wood_heal"])
	manager._resolve_effect(manager.player, manager.enemy, {"type":"generate_card", "target":"self", "amount":1, "element":"metal"}, "metal")
	check(manager.player.hand.size() == 8 and manager.player.discard_pile.size() == 1 and manager.cards[manager.player.discard_pile[0]]["element"] == "metal", "full-hand restricted generation discards a base metal card")

	prepare()
	manager.interactive_choices = true
	manager.player.draw_pile.assign(["metal_strike__1", "wood_heal__2", "metal_strike__1", "water_strike"])
	var fatigue := manager.player.fatigue_level
	check(cast("water_thought__1") and not manager.pending_choice.is_empty(), "draw then contemplate suspends after the first draw")
	check(manager.player.hand == ["metal_strike__1"] and manager.player.discard_pile.is_empty(), "selected spell is not completed before choice")
	check(not manager.play_player_card(0, {"kind":"hero"}), "choice blocks additional plays")
	check(not manager.choose_card(99) and not manager.pending_choice.is_empty(), "invalid selection does not change state")
	check(manager.choose_card(1), "choose the second physical candidate")
	check(manager.player.hand == ["metal_strike__1", "metal_strike__1"] and manager.player.draw_pile == ["wood_heal__2", "water_strike"], "selection preserves duplicate positions, grade and unselected order")
	check(manager.player.discard_pile == ["water_thought__1"] and manager.player.fatigue_level == fatigue, "completion runs once after choice")
	prepare()
	manager.player.draw_pile.clear()
	manager.player.discard_pile.assign(["metal_strike"])
	manager._resolve_effect(manager.player, manager.enemy, {"type":"contemplate", "target":"self", "amount":4}, "water")
	check(manager.player.hp == 55 and manager.player.fatigue_level == 1, "empty contemplation recycles once and loses five life")
	prepare()
	manager.enemy.energy["metal"] = 3
	manager.enemy.hp = 1
	var state := manager.rng.state
	var chosen := manager._choose_contemplation(manager.enemy, ["water_strike", "metal_rainbow_blade__2"])
	check(chosen == 1 and manager.rng.state == state, "enemy picks a playable lethal option without consuming actual RNG")

	prepare()
	manager._equip_loadout(manager.player, {"guard":"water_frost_gauze"})
	manager.player.energy["fire"] = 7
	check(manager.apply_damage(manager.enemy, manager.player, 4, "fire") == 0 and manager.player.artifact_durability == 2, "gauze still spends durability when mitigation rounds damage to zero")
	manager.player.energy["fire"] = 10
	manager.apply_damage(manager.enemy, manager.player, 4, "fire")
	check(manager.player.artifact_durability == 2, "innate immunity does not consume gauze")
	prepare()
	manager.player.hp = 12
	manager.enemy.hp = 12
	check(cast("fire_burning_field", {"kind":"hero"}) and manager.phase == "tie", "new base field deals twelve to both heroes and ties")
	prepare()
	creature(manager.enemy, 0, "earth_sand_rhino")
	check(cast("fire_all_targets", {"kind":"summon", "side":"enemy", "slot":0}) and manager.enemy.summons[0].hp == 9 and manager.player.hp == 60, "base Samadhi costs three and deals fifteen only to enemy summons")

	var store := DeckStore.new(manager.cards, "res://work/upgrade_decks.json")
	check(not store.problem(["metal_strike", "metal_strike__1", "metal_strike__2"], false).is_empty(), "family copy cap spans all grades")
	var saved := store.save_deck("upgrades", "升级存档", ["metal_strike__1", "metal_strike__2"], true, {"implement":"metal_thunder_ruler__2"})
	store.load_decks()
	check(not saved.has("error") and store.find_deck("upgrades")["cards"] == saved["cards"] and store.find_deck("upgrades")["artifacts"]["implement"] == "metal_thunder_ruler__2", "grades persist for cards and artifacts")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	# Exercise upgrades together with every artifact slot and the actual enemy AI.
	for seed_value in 12:
		manager.interactive_choices = false
		manager.start_battle("ember", "random", 3000 + seed_value)
		for actor in [manager.player, manager.enemy]:
			for zone in [actor.hand, actor.draw_pile, actor.initial_deck]:
				for i in zone.size(): zone[i] = ContentCatalog.variant_id(ContentCatalog.base_id(manager.cards[zone[i]]), seed_value % 2 + 1)
			var loadout := ArtifactLibrary.random_loadout(manager.artifacts, manager.rng)
			for slot in ArtifactLibrary.SLOTS: loadout[slot] = ContentCatalog.variant_id(str(loadout[slot]), seed_value % 2 + 1)
			manager._equip_loadout(actor, loadout)
			manager._trigger_battle_start_artifacts(actor)
		var actions := 0
		while manager.phase not in BattleManager.FINISHED_PHASES and actions < 500:
			if manager.phase == "player_action":
				preload("res://tests/simulation_player.gd").fund(manager)
				var played := false
				for i in manager.player.hand.size():
					var card: Dictionary = manager.cards[manager.player.hand[i]]
					if not manager.player.can_pay(card): continue
					var candidates := manager._card_candidates(manager.player, card)
					if candidates.is_empty(): continue
					played = manager.play_player_card(i, candidates[0])
					if played: break
				if not played: await manager.end_player_turn()
			elif manager.phase == "enemy_action": await manager.enemy_step()
			actions += 1
		check(manager.phase in BattleManager.FINISHED_PHASES and manager.pending_choice.is_empty(), "complete upgraded battle with AI and artifacts: " + str(seed_value))
	manager.queue_free()
	await process_frame
	print("Upgrade rules: all 180 cards and 45 artifacts, choices, bleeding, generation, cooldown, durability and persistence; %d failures" % failures)
	quit(1 if failures else 0)
