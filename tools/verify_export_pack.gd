extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	check(FileAccess.file_exists("res://data/cards.json") and FileAccess.file_exists("res://data/summons.json") and FileAccess.file_exists("res://data/battles.json"), "all runtime JSON files are packaged")
	check(not ResourceLoader.exists("res://tests/smoke_test.gd") and not ResourceLoader.exists("res://tools/test_main_menu.gd"), "development tools are excluded")
	var scene: PackedScene = load("res://battle/battle_scene.tscn")
	check(scene != null, "main scene loads from exported pack")
	var ui := scene.instantiate()
	root.add_child(ui)
	await process_frame
	check(ui.theme.default_font != null, "game uses a complete portable font theme")
	var manager := BattleManager.new()
	root.add_child(manager)
	check(manager.cards.size() == 39 and manager.summon_templates.size() == 10, "current card and summon pool is included")
	var supported := GameFonts.BODY.get_supported_chars()
	for card: Dictionary in manager.cards.values():
		var art: Texture2D = load("res://assets/cards/generated/%s.webp" % card["id"])
		check(art != null and art.get_width() > 0, "card art loads: " + card["id"])
		for glyph in str(card["name"]) + str(card["text"]):
			if glyph.strip_edges() != "": check(supported.contains(glyph), "bundled font covers card glyph: " + glyph)
	for summoned: Dictionary in manager.summon_templates.values():
		check(ResourceLoader.exists("res://assets/summons/standee/%s.webp" % summoned["id"]), "summon art included: " + summoned["id"])
	check(GameFonts.SERIF.get_supported_chars().contains("克") and GameFonts.SERIF.get_supported_chars().contains("抵"), "damage font covers matchup labels")
	if OS.has_feature("windows"): check(GameFonts.body() is FontFile, "Windows body text uses the bundled CJK font")
	for seed_value in 15:
		manager.start_battle("ember", "random", seed_value + 2100)
		for actor in [manager.player,manager.enemy]:
			check(actor.hp == 80 and actor.max_hp == 80 and manager.valid_random_deck(actor.hand + actor.draw_pile), "exported game starts with legal 25-card decks and 80 HP")
		var steps := 0
		while manager.phase not in ["victory", "defeat"] and steps < 1000:
			steps += 1
			if manager.phase == "player_action":
				var played := false
				for index in manager.player.hand.size():
					var card: Dictionary = manager.cards[manager.player.hand[index]]
					var selection := {"kind":"hero"}
					if manager.card_target_mode(card) == "slot": selection = {"kind":"slot", "slot":manager.player.first_free_summon_slot()}
					if manager.player.can_pay(card) and manager.valid_card_target(manager.player, card, selection):
						played = manager.play_player_card(index, selection)
						break
				if not played: manager.end_player_turn()
			elif manager.phase == "enemy_action": manager.enemy_step()
			else:
				check(false, "exported battle stalled: " + manager.phase)
				break
		check(steps < 1000, "exported random battle finishes")
	print("Export pack verified on %s: 39 cards and art, 10 summons, bundled Chinese fonts, 15 complete battles; %d failures" % [OS.get_name(),failures])
	quit(1 if failures > 0 else 0)
