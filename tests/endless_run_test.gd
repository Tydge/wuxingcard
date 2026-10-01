extends SceneTree

const SAVE := "user://endless_rules_test.json"
var failures := 0
var manager: BattleManager
var run: EndlessRun

func _initialize() -> void: call_deferred("test")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func fill_draft() -> void:
	for entry in ContentCatalog.base_entries(manager.cards).slice(0, 10):
		for copy in 2:
			if run.state["draft"].size() < EndlessRun.INITIAL_CARDS:
				check(run.change_draft(str(entry["id"]), true), "initial selection accepts a base card up to fifteen")

func fingerprint(battle: BattleManager) -> String:
	var result := {"phase": battle.phase, "first": battle.first_side, "round": battle.round_number, "rng": str(battle.rng.state), "played": battle.played_cards, "damage": battle.player_damage, "destroyed": battle.energy_destroyed}
	for side in ["player", "enemy"]:
		var actor: Combatant = battle.get(side)
		var fields := {}
		for key in ["id", "max_hp", "hp", "qi", "energy", "draw_pile", "initial_deck", "hand", "discard_pile", "statuses", "fatigue_level", "artifacts", "artifact_resistances", "artifact_durability", "artifact_ready_turn", "own_turn_count", "artifact_flags"]:
			fields[key] = actor.get(key)
		fields["summons"] = []
		for summon: Summon in actor.summons:
			fields["summons"].append(null if summon == null else {"id":summon.id, "max_hp":summon.max_hp, "hp":summon.hp})
		result[side] = fields
	result["choice"] = battle.pending_choice.get("candidates", [])
	return JSON.stringify(result)

func test() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	run = EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, SAVE)
	check(run.new_run(721), "create an isolated run")
	check(run.state["gold"] == 0 and run.state["max_hp"] == 80 and run.loadout_ids().values() == ["", "", ""], "initial run has eighty HP, zero money and no relics")
	check(not run.begin_battle(), "incomplete initial deck cannot enter battle")
	check(not run.change_draft("metal_forge__1", true), "upgraded cards cannot enter the initial deck")
	check(not run.toggle_artifact("1"), "setup has no relic selection")
	fill_draft()
	check(not run.change_draft("wood_heal", true), "initial deck stops at exactly fifteen")
	var preview := run.opponent().duplicate(true)
	var scouts := run.scouted_cards()
	check(scouts.size() == 3 and run.scouted_cards() == scouts, "scouting reveals the same three actual copies")
	check(run.begin_battle(), "fifteen base cards start the run")
	check(run.state["battle"]["enemy"] == preview and run.deck_ids().size() == 15, "scouted opponent is the opponent fought")
	await manager.start_battle(str(preview["id"]), "random", int(run.state["battle"]["seed"]), run.battle_deck(), run.battle_options())
	check(manager.player.hp == 80 and manager.enemy.hp == 40 and manager.enemy.initial_deck == preview["cards"], "first battle applies asymmetric HP and fixed enemy deck")
	check(manager.player.artifacts.values() == ["", "", ""] and manager.enemy.artifacts.values() == ["", "", ""], "first battle has no random free relics")
	# Journal recovery preserves both the hidden deck order and RNG state.
	manager.interactive_choices = true
	for step in 18:
		if manager.phase in BattleManager.FINISHED_PHASES: break
		if manager.phase == "player_action":
			var played := false
			for index in manager.player.hand.size():
				var card: Dictionary = manager.cards[manager.player.hand[index]]
				var needed := maxi(0, int(card["cost"]) - int(manager.player.energy[card["element"]]))
				if needed > manager.player.qi: continue
				for unit in needed:
					run.record_command({"kind":"qi", "element":card["element"]})
					manager.convert_qi(manager.player, card["element"])
				if not manager.player.can_pay(card): continue
				var targets := manager._card_candidates(manager.player, card)
				if targets.is_empty(): continue
				check(run.record_command({"kind":"card", "index":index, "target":targets[0]}), "save player action before resolution")
				manager.play_player_card(index, targets[0])
				played = true
				break
			if not played:
				run.record_command({"kind":"end_turn"})
				await manager.end_player_turn()
		elif manager.phase == "enemy_action":
			run.record_command({"kind":"enemy"})
			var action := manager.peek_enemy_action()
			await manager.enemy_step(int(action["index"]), action["target"], str(action.get("kind", "card")))
		while not manager.pending_choice.is_empty():
			run.record_choice(1)
			manager.choose_card(1)
	var copy := BattleManager.new()
	root.add_child(copy)
	copy.interactive_choices = true
	check(run.replay_battle(copy), "action journal can restore a running or just-finished battle")
	check(fingerprint(copy) == fingerprint(manager), "restore preserves complete mutable battle state and randomness")
	copy.queue_free()
	check(run.settle("victory"), "victory settles exactly once")
	check(not run.settle("victory") and run.state["gold"] == 100 and run.state["wins"] == 1, "repeated victory cannot award twice")
	check(run.enemy_hp() == 50 and int(run.opponent()["budget"]) == 100, "second opponent receives first prize regardless of player spending")
	check(run.state["shop"].size() == 7 and run.state["shop"].slice(0, 5).all(func(x): return x["kind"] == "cards") and run.state["shop"].slice(5).all(func(x): return x["kind"] == "artifacts"), "shop contains five cards and two relics")
	var deck_before := run.deck_ids().duplicate()
	var loadout_before := run.loadout_ids().duplicate()
	check(run.buy(0), "buy an offered card")
	check(run.deck_ids() == deck_before and run.loadout_ids() == loadout_before and run.state["owned_cards"].size() == 16, "purchase goes only to warehouse")
	check(not run.buy(0), "sold offers cannot be purchased twice")
	var uid := str(run.state["deck"][0])
	var sibling := str(run.state["deck"][1])
	var old_id := str(run.item("cards", sibling)["id"])
	check(run.upgrade("cards", uid), "one copy can be upgraded")
	check(run.item("cards", sibling)["id"] == old_id and run.item("cards", uid)["id"] == old_id + "__1", "upgrade never changes an identical sibling")
	check(run.toggle_card(uid) and run.toggle_card(uid), "upgraded copy retains its level when moved out and back")
	check(not run.upgrade("cards", uid), "insufficient money cannot upgrade or spend")
	var gold := int(run.state["gold"])
	var fixed_foe := run.opponent().duplicate(true)
	var fixed_scout := run.scouted_cards().duplicate()
	check(run.refresh_shop() and int(run.state["gold"]) == gold - 20 and run.refresh_price() == 40, "refresh charges once and raises its next price")
	check(run.opponent() == fixed_foe and run.scouted_cards() == fixed_scout, "refreshing shop cannot reroll opponent or scouts")
	var saved_run := EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, SAVE)
	check(saved_run.load_run() and saved_run.state == JSON.parse_string(JSON.stringify(run.state)), "inventory, levels, stock, scouts and progress survive JSON round-trip")
	check(run.begin_battle(), "continuation requires no gold")
	check(run.state["gold"] == 10, "entering next battle does not charge money")
	check(run.settle("victory") and run.state["earned"] == 210 and run.opponent()["budget"] == 210 and run.enemy_hp() == 60, "third opponent receives cumulative first and second prizes")
	check(run.buy(5), "relic purchase")
	check(run.loadout_ids() == loadout_before, "bought relic stays unequipped")
	var relic_uid := str(run.state["owned_artifacts"][0]["uid"])
	check(run.toggle_artifact(relic_uid), "owned relic equips only on player request")
	check(run.begin_battle(), "third battle begins")
	await manager.start_battle(str(run.state["battle"]["enemy"]["id"]), "random", int(run.state["battle"]["seed"]), run.battle_deck(), run.battle_options())
	check(manager.player.hp == 80 and manager.enemy.hp == 60, "third battle starts fully healed with a sixty-HP enemy")
	check(run.settle("victory"), "third prize funds further growth")
	check(run.improve_hp() and run.state["max_hp"] == 90 and run.hp_price() == 80, "HP growth charges and escalates independently")
	check(run.begin_battle(), "fourth battle begins")
	await manager.start_battle(str(run.state["battle"]["enemy"]["id"]), "random", int(run.state["battle"]["seed"]), run.battle_deck(), run.battle_options())
	check(manager.player.hp == 90 and manager.player.max_hp == 90 and manager.enemy.hp == 70, "each new battle refills grown player HP and enemy HP")
	check(run.settle("tie") and run.state["phase"] == "ended" and run.state["wins"] == 3, "tie ends the run without advancing")
	check(not run.begin_battle(), "ended runs cannot continue")
	check(run.new_run(722) and run.state["owned_cards"].is_empty() and run.state["owned_artifacts"].is_empty() and run.best == 3, "new run resets possessions but retains best record")
	# A failed write must roll back both ownership and spending.
	run.state["phase"] = "rest"
	run.state["gold"] = 100
	run.path = "user://missing-endless-directory/run.json"
	var before := run.state.duplicate(true)
	check(not run.improve_hp() and run.state == before, "failed transaction preserves gold and HP")
	# Hundreds of enemies must stay legal at every spending tier.
	var random := RandomNumberGenerator.new()
	random.seed = 109
	var seen := {}
	for budget in [0, 100, 210, 700, 2400, 10000]:
		for index in 45:
			var foe := run.generate_enemy(random, budget)
			check(DeckStore.new(manager.cards).problem(foe["cards"]).is_empty(), "enemy respects size and same-name cap")
			check(int(foe["spent"]) <= budget, "enemy never spends beyond earned budget")
			seen[foe["id"]] = true
			if budget == 0: check(foe["artifacts"].values() == ["", "", ""] and foe["cards"].all(func(id): return manager.cards[id]["level"] == 0), "zero-budget enemy has no upgrades or relics")
	check(seen.size() == manager.enemies.size(), "random enemies include every portrait")
	DirAccess.remove_absolute(SAVE)
	manager.queue_free()
	await process_frame
	print("Endless rules: economy, ownership, fixed scouting, journal recovery, HP, ties, save rollback and 270 generated enemies; %d failures" % failures)
	quit(1 if failures else 0)
