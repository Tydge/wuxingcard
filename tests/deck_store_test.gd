extends SceneTree

var failures := 0
var manager: BattleManager

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func sample(amount: int) -> Array[String]:
	var ids: Array[String] = []
	for id in manager.cards:
		for copy in DeckStore.MAX_COPIES:
			if ids.size() < amount: ids.append(id)
	return ids

func counts(ids: Array) -> Dictionary:
	var result := {}
	for id in ids: result[id] = int(result.get(id, 0)) + 1
	return result

func run() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	var path := "res://work/test_decks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var store := DeckStore.new(manager.cards, path)
	store.load_decks()
	check(store.decks.is_empty(), "new profile starts without saved decks")
	check(not store.problem(sample(19)).is_empty() and store.problem(sample(20)).is_empty(), "twenty-card minimum")
	check(store.problem(sample(30)).is_empty() and not store.problem(sample(31)).is_empty(), "thirty-card maximum")
	check(store.problem(["metal_strike", "metal_strike"], false).is_empty() and not store.problem(["metal_strike", "metal_strike", "metal_strike"], false).is_empty(), "same card allows two copies and rejects a third")
	check(not store.problem(["obsolete_card"], false).is_empty(), "unknown cards cannot be saved")
	var legacy_file := FileAccess.open(path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"decks": [{"id": "legacy", "name": "旧卷", "cards": ["metal_strike", "metal_strike", "metal_strike", "obsolete_card"]}]}))
	legacy_file.close()
	store.load_decks()
	check(store.find_deck("legacy")["cards"] == ["metal_strike", "metal_strike"], "older three-copy saves retain two copies and omit retired cards")
	store.delete_deck("legacy")
	var draft := store.save_deck("", "未成卷", sample(6))
	check(not draft.has("error") and not store.problem(draft["cards"]).is_empty(), "small draft is saved but cannot start a battle")
	var saved := store.save_deck("", "青山法卷", sample(20))
	check(not saved.has("error") and store.decks.size() == 2, "second deck gets its own identity")
	var id: String = saved["id"]
	var reopened := DeckStore.new(manager.cards, path)
	reopened.load_decks()
	check(reopened.find_deck(id)["cards"] == sample(20), "saved cards persist after reopening")
	var isolated := reopened.find_deck(id)
	isolated["cards"].clear()
	check(reopened.find_deck(id)["cards"].size() == 20, "editing a draft cannot mutate the saved deck")
	saved = reopened.save_deck(id, "改名", sample(30))
	check(reopened.decks.size() == 2 and saved["name"] == "改名", "saving an existing deck updates it without duplicates")
	check(reopened.save_deck(id, "非法", sample(31)).has("error") and reopened.find_deck(id)["cards"].size() == 30, "invalid update leaves the old save intact")
	# Starting any saved legal size preserves exactly its chosen cards. Only the
	# opponent is constrained by the existing random 25-card cost guardrails.
	for size in [20, 25, 30]:
		var deck := {"id": id, "name": "测试法卷", "cards": sample(size)}
		await manager.start_battle("ember", "random", 1881, deck)
		check(counts(manager.player.hand + manager.player.draw_pile) == counts(deck["cards"]), "custom battle preserves %d selected cards" % size)
		check(manager.valid_random_deck(manager.enemy.hand + manager.enemy.draw_pile), "opponent still receives a legal random deck")
		check(manager.player.max_hp == 80 and manager.enemy.max_hp == 80 and manager.selected_deck_id == "custom:" + id, "custom mode uses eighty HP and saved deck identity")
	var old_generation := manager.battle_generation
	await manager.start_battle("ember", "random", 2, draft)
	check(manager.battle_generation == old_generation, "battle rejects incomplete drafts before changing any state")
	# Energy uses the immutable full deck, including opening cards, played cards
	# and discards; exhausted draw piles do not remove natural generation.
	await manager.start_battle("ember", "random", 4242, {"id": id, "name": "五行卷", "cards": sample(25)})
	var actor := manager.player
	for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	var weights := manager.natural_weights(actor)
	var full_counts := {}
	for element in BattleRules.ELEMENTS: full_counts[element] = 0
	for card_id in actor.initial_deck: full_counts[manager.cards[card_id]["element"]] += 1
	check(weights == full_counts, "natural weights match the full configured deck")
	actor.draw_pile.clear()
	actor.hand.clear()
	actor.discard_pile = ["fire_strike"]
	check(manager.natural_weights(actor) == weights, "drawing, playing and discarding cannot change the weights")
	for draw in 100:
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
		var gained := manager.generate_natural_energy(actor)
		check(full_counts[gained] > 0, "only configured elements are generated after fatigue")
	actor.energy["metal"] = 10
	actor.add_status("lock", 1, 2, "wood")
	var eligible := manager.natural_weights(actor)
	check(eligible["metal"] == 0 and eligible["wood"] == 0, "capped and locked attributes are still excluded")
	for element in BattleRules.ELEMENTS: actor.energy[element] = 10
	check(manager.generate_natural_energy(actor).is_empty(), "all capped attributes produce no energy")
	check(reopened.delete_deck(id), "deck deletion persists")
	store.load_decks()
	check(store.find_deck(id).is_empty() and store.decks.size() == 1, "deleted deck remains deleted after reloading")
	DirAccess.remove_absolute(path)
	print("Deck store test: drafts, persistence, copy/size limits, custom battles and fixed natural energy; %d failures" % failures)
	quit(1 if failures > 0 else 0)
