extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	check(FileAccess.file_exists("res://data/cards.json") and FileAccess.file_exists("res://data/summons.json") and FileAccess.file_exists("res://data/artifacts.json") and FileAccess.file_exists("res://data/battles.json"), "all runtime JSON files are packaged")
	check(not ResourceLoader.exists("res://tests/smoke_test.gd") and not ResourceLoader.exists("res://tools/test_main_menu.gd"), "development tools are excluded")
	var scene: PackedScene = load("res://battle/battle_scene.tscn")
	check(scene != null, "main scene loads from exported pack")
	var ui := scene.instantiate()
	root.add_child(ui)
	await process_frame
	check(ui.theme.default_font != null, "game uses a complete portable font theme")
	var manager := BattleManager.new()
	root.add_child(manager)
	check(manager.cards.size() == 210 and manager.summon_templates.size() == 78, "current card and summon pool is included")
	var supported := GameFonts.BODY.get_supported_chars()
	for card: Dictionary in manager.cards.values():
		var art: Texture2D = load("res://assets/cards/generated/%s.webp" % card["art_id"])
		check(art != null and art.get_width() > 0, "card art loads: " + card["art_id"])
		for glyph in str(card["name"]) + str(card["text"]):
			if glyph.strip_edges() != "": check(supported.contains(glyph), "bundled font covers card glyph: " + glyph)
	for summoned: Dictionary in manager.summon_templates.values():
		var standee: Texture2D = load("res://assets/summons/standee/%s.webp" % summoned["art_id"])
		check(standee != null and standee.get_image().detect_alpha() != Image.ALPHA_NONE, "transparent summon art included: " + summoned["art_id"])
	check(manager.artifacts.size() == 90, "all artifact definitions are packaged")
	for artifact: Dictionary in manager.artifacts.values():
		var art: Texture2D = load("res://assets/artifacts/%s.webp" % artifact["art_id"])
		check(art != null and art.get_width() > 0, "artifact card art loads: " + artifact["art_id"])
		if artifact["slot"] == "implement":
			var weapon: Texture2D = load("res://assets/artifacts/%s_standee.webp" % artifact["art_id"])
			check(weapon != null and weapon.get_image().detect_alpha() != Image.ALPHA_NONE, "transparent implement standee included: " + artifact["art_id"])
	for actor_id in ["player", "ember", "tide", "harmony", "crane", "veil", "spear", "moon", "ink"]:
		check(ResourceLoader.exists("res://assets/characters/%s.webp" % actor_id) and ResourceLoader.exists("res://assets/characters/%s_standee.webp" % actor_id), "runtime portrait and full-body standee included: " + actor_id)
		check(not ResourceLoader.exists("res://assets/characters/fullbody/%s.webp" % actor_id), "unused full-body source excluded: " + actor_id)
	for element in BattleRules.ELEMENTS:
		check(ResourceLoader.exists("res://assets/cards/elements/%s.webp" % element), "shared elemental fallback included: " + element)
	for background in ["arena", "mountain_gate", "endless_camp"]:
		check(ResourceLoader.exists("res://assets/backgrounds/%s.webp" % background), "battle and home background included: " + background)
	check(ResourceLoader.exists("res://audio/audio_director.gd"), "shared desktop/Android audio director is packaged")
	for path in AudioDirector.MENU_TRACKS + AudioDirector.BATTLE_TRACKS:
		check(load(path) is AudioStream, "BGM loads: " + path)
	for path in AudioDirector.SFX.values():
		check(load(path) is AudioStream, "sound effect loads: " + path)
	check(GameFonts.SERIF.get_supported_chars().contains("克") and GameFonts.SERIF.get_supported_chars().contains("抵"), "damage font covers matchup labels")
	if OS.has_feature("windows"): check(GameFonts.body() is FontFile, "Windows body text uses the bundled CJK font")
	for seed_value in 15:
		await manager.start_battle("ember", "random", seed_value + 2100)
		for actor in [manager.player,manager.enemy]:
			check(actor.hp > 0 and actor.hp <= 80 and actor.max_hp == 80 and manager.valid_random_deck(actor.hand + actor.draw_pile), "exported battle %d %s starts with legal 25-card deck and 80 maximum HP (hp %d/%d, hand %d, pile %d)" % [seed_value, actor.id, actor.hp, actor.max_hp, actor.hand.size(), actor.draw_pile.size()])
		check(manager.player.qi == (4 if manager.first_side == "player" else 3), "exported opening uses neutral qi")
		var steps := 0
		while manager.phase not in BattleManager.FINISHED_PHASES and steps < 1000:
			steps += 1
			if manager.phase == "player_action":
				fund_player(manager)
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
	print("Export pack verified on %s: 210 card definitions and art, 78 summons, bundled Chinese fonts, 15 complete battles; %d failures" % [OS.get_name(),failures])
	quit(1 if failures > 0 else 0)

func fund_player(manager: BattleManager) -> void:
	for id in manager.player.hand:
		var card: Dictionary = manager.cards[id]
		if manager._card_candidates(manager.player, card).is_empty(): continue
		var needed := maxi(0, int(card["cost"]) - int(manager.player.energy[card["element"]]))
		if needed <= 0 or needed > manager.player.qi or not manager.can_convert_qi(manager.player, card["element"]): continue
		for unit in needed:
			if not manager.convert_qi(manager.player, card["element"]): break
		return
