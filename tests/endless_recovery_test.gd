extends "res://tests/endless_run_test.gd"

func recover_compare(message: String) -> BattleManager:
	var copy := BattleManager.new()
	root.add_child(copy)
	copy.interactive_choices = true
	var loaded := EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, run.path)
	check(loaded.load_run() and loaded.replay_battle(copy), message + " can replay from disk")
	check(fingerprint(copy) == fingerprint(manager), message + " preserves exact battle state")
	return copy

func test() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	manager.interactive_choices = true
	run = EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, "user://endless_recovery_test.json")
	for seed_value in [2, 0]:
		run.new_run(109)
		fill_draft()
		run.begin_battle()
		# Equipment fixture for a later run: recovery never grants this in setup.
		var pendant := run._own("artifacts", "water_tide_pearl__2")
		run.state["loadout"]["pendant"] = pendant
		var implement := run._own("artifacts", "wood_bamboo_scroll__2")
		run.state["loadout"]["implement"] = implement
		run.state["battle"]["seed"] = str(seed_value)
		run._commit(run.state.duplicate(true))
		manager.start_battle(str(run.opponent()["id"]), "random", seed_value, run.battle_deck(), run.battle_options())
		await process_frame
		check(manager.phase == "battle_start" and manager.pending_choice["candidates"].size() == 3, "opening choice suspends before the first turn")
		var copy := recover_compare("pending opening choice for either first side")
		copy.battle_generation += 1
		copy.pending_choice.clear()
		copy.choice_completed.emit()
		copy.queue_free()
		run.record_choice(1)
		manager.choose_card(1)
		copy = recover_compare("completed opening choice for either first side")
		copy.queue_free()
		if seed_value == 2:
			check(manager.phase == "player_action", "seed fixture reaches player action")
			run.record_command({"kind":"qi", "element":"metal"})
			check(manager.convert_qi(manager.player, "metal"), "recorded qi conversion resolves")
			copy = recover_compare("stored qi conversion")
			copy.queue_free()
			run.record_command({"kind":"artifact", "target":{}})
			manager.activate_artifact(manager.player)
			check(manager.pending_choice["candidates"].size() == 4, "active relic opens a four-card choice")
			copy = recover_compare("pending active-relic choice")
			copy.queue_free()
			run.record_choice(3)
			manager.choose_card(3)
			copy = recover_compare("completed active-relic choice")
			copy.queue_free()
		# Simulate quitting after a valid action was saved, before its animation/effect.
		if seed_value == 2:
			run.record_command({"kind":"end_turn"})
			var restored := BattleManager.new()
			root.add_child(restored)
			restored.interactive_choices = true
			check(run.replay_battle(restored) and restored.phase == "enemy_action", "saved action recovers even if interrupted before actual resolution")
			await manager.end_player_turn()
			check(fingerprint(restored) == fingerprint(manager), "recovered pre-animation action equals the fully resolved action")
			restored.queue_free()
		await process_frame
	# A legacy live encounter cannot replay its old automatic-energy journal.
	var assets: Array = JSON.parse_string(JSON.stringify(run.state["owned_cards"]))
	var foe: Dictionary = JSON.parse_string(JSON.stringify(run.opponent()))
	run.state.erase("rules_version")
	run.state["battle"]["commands"] = [{"kind":"card", "index":0, "target":{}}]
	run._commit(run.state.duplicate(true))
	var legacy := EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, run.path)
	check(legacy.load_run() and not legacy.notice.is_empty(), "legacy live battle migrates with an explanation")
	check(legacy.state["owned_cards"] == assets and legacy.opponent() == foe and legacy.state["battle"]["commands"].is_empty() and legacy.state["battle"]["choices"].is_empty(), "migration preserves assets and same opponent while restarting only the old battle")
	check(FileAccess.file_exists(run.path + ".pre-qi") and JSON.parse_string(FileAccess.get_file_as_string(run.path + ".pre-qi"))["run"]["battle"]["commands"].size() == 1, "legacy action journal is backed up before migration")
	var reopened := EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, run.path)
	check(reopened.load_run() and reopened.notice.is_empty() and reopened.state["rules_version"] == EndlessRun.RULES_VERSION, "migration is saved and runs only once")
	DirAccess.remove_absolute(run.path + ".pre-qi")
	DirAccess.remove_absolute(run.path)
	manager.queue_free()
	await process_frame
	print("Endless recovery: both opening orders, pending/completed choices, active relics and interruption before action resolution; %d failures" % failures)
	quit(1 if failures else 0)
