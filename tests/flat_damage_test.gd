extends SceneTree

var failures := 0
var manager: BattleManager
var tie_events := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func track_result(_message: String, side: String, kind: String, _element: String, _amount: int) -> void:
	if side == "system" and kind == "tie": tie_events += 1

func prepare() -> void:
	manager.start_battle("ember", "random", 918)
	# Keep the all-board damage regression with a test-only card after Samadhi Fire's retargeting.
	var all_board: Dictionary = manager.cards["fire_all_targets"].duplicate(true)
	all_board["id"] = "test_all_board"
	all_board["cost"] = 2
	all_board["effects"] = [{"type":"damage", "scope":"all", "amount":12, "element":"fire"}]
	manager.cards["test_all_board"] = all_board
	for actor in [manager.player, manager.enemy]:
		actor.hp = 80
		actor.statuses.clear()
		actor.summons = [null, null, null]
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.phase = "player_action"

func ready_card(id: String) -> Dictionary:
	manager.player.hand = [id]
	var card: Dictionary = manager.cards[id]
	manager.player.energy[card["element"]] = int(card["cost"])
	return card

func summon(actor: Combatant, slot: int, id: String, hp: int = -1) -> void:
	actor.summons[slot] = Summon.new()
	actor.summons[slot].setup(manager.summon_templates[id])
	if hp >= 0: actor.summons[slot].hp = hp

func run() -> void:
	manager = BattleManager.new()
	manager.random_artifacts_enabled = false
	root.add_child(manager)
	manager.action_event.connect(track_result)
	# The new opposite pairs cancel without inheriting the older ten-layer cap.
	var actor := Combatant.new()
	for pair in [["strong_attack", "weak_attack"], ["strong_defense", "weak_defense"]]:
		actor.statuses.clear()
		actor.add_status(pair[0], 23, 7)
		actor.add_status(pair[1], 2, 7)
		check(actor.status_stacks(pair[0]) == 21 and actor.status_stacks(pair[1]) == 0, "new pairs cancel without a ten-layer cap")
		actor.add_status(pair[1], 25, 7)
		check(actor.status_stacks(pair[0]) == 0 and actor.status_stacks(pair[1]) == 4, "excess negative layers survive cancellation")
		actor.tick_status_durations()
		check(actor.status_stacks(pair[1]) == 4, "new states have no turn duration")
		actor.add_status(pair[0], 4, 0)
		check(actor.statuses.is_empty(), "equal layers remove both states")
	actor.add_status("charge", 40, 0)
	check(actor.status_stacks("charge") == 10, "percentage states keep their ten-layer cap")

	prepare()
	manager.player.add_status("strong_attack", 3, 0)
	manager.player.add_status("charge", 2, 0)
	manager.enemy.add_status("strong_defense", 2, 0)
	manager.enemy.add_status("tenacity", 1, 0)
	manager.enemy.add_status("shield", 5, 0)
	var card := ready_card("metal_strike")
	var before := manager.player.statuses.duplicate(true)
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero"}) == [7], "fixed 10+3-2, then 110 percent, then five shield gives seven")
	check(manager.player.statuses == before and manager.enemy.status_stacks("shield") == 5, "preview never mutates live states")
	check(manager.play_player_card(0, {"kind":"hero"}) and manager.enemy.hp == 73, "actual fixed-before-percent damage agrees with preview")
	check(manager.player.status_stacks("strong_attack") == 2 and manager.enemy.status_stacks("strong_defense") == 1, "one hit consumes one attack and one defense layer")

	prepare()
	manager.player.add_status("weak_attack", 3, 0)
	manager.enemy.add_status("weak_defense", 5, 0)
	card = ready_card("metal_strike")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero"}) == [12], "negative attack and defense signs are correct")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 68 and manager.player.status_stacks("weak_attack") == 2 and manager.enemy.status_stacks("weak_defense") == 4, "negative states resolve and decay")

	prepare()
	manager.player.add_status("strong_attack", 3, 0)
	card = ready_card("metal_twin_blades")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero"}) == [13, 12], "two hits use the decreasing attack bonus")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 55 and manager.player.status_stacks("strong_attack") == 1, "two ten-damage hits deal twenty-five and consume two layers")
	prepare()
	manager.player.add_status("strong_attack", 3, 0)
	manager.enemy.add_status("strong_defense", 1, 0)
	manager.enemy.add_status("shield", 4, 0)
	card = ready_card("metal_twin_blades")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero"}) == [8, 12], "each hit updates defense and shield as well as attack")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 60 and manager.enemy.status_stacks("strong_defense") == 0 and manager.enemy.status_stacks("shield") == 0, "multi-hit actual damage consumes defense and shield correctly")
	prepare()
	manager.player.add_status("strong_attack", 3, 0)
	summon(manager.enemy, 0, "wood_seedling")
	card = ready_card("metal_twin_blades")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"summon", "slot":0}) == [15, 0], "a killed summon is not retargeted on the second hit")
	manager.play_player_card(0, {"kind":"summon", "slot":0})
	check(manager.enemy.summons[0] == null and manager.enemy.hp == 80 and manager.player.status_stacks("strong_attack") == 2, "missing second target causes no hero damage or extra consumption")

	prepare()
	manager.player.add_status("strong_attack", 3, 0)
	manager.player.add_status("strong_defense", 2, 0)
	manager.enemy.add_status("strong_defense", 1, 0)
	for owner in [manager.player, manager.enemy]:
		for slot in 3: summon(owner, slot, ["metal_furnace", "wood_seedling", "fire_lantern"][slot], 40)
	card = ready_card("test_all_board")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero", "side":"player"}) == [13], "own preview accounts for payment and its own defense")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero", "side":"enemy"}) == [14], "opponent preview uses the same simultaneous source bonus")
	manager.play_player_card(0, {"kind":"hero", "side":"player"})
	check(manager.player.hp == 67 and manager.enemy.hp == 66, "global spell hits both heroes")
	for owner in [manager.player, manager.enemy]:
		check(owner.summons[0].hp == 17 and owner.summons[1].hp == 25 and owner.summons[2].hp == 32, "all summons share the attack bonus while retaining their own affinity")
	check(manager.player.status_stacks("strong_attack") == 2 and manager.player.status_stacks("strong_defense") == 1 and manager.enemy.status_stacks("strong_defense") == 0, "eight-target segment consumes attack once and each hero defense once")

	prepare()
	manager.player.add_status("strong_attack", 3, 0)
	for slot in 3: summon(manager.enemy, slot, "water_spring", 40)
	card = ready_card("fire_burning_field")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 65 and manager.player.hp == 65 and manager.player.status_stacks("strong_attack") == 2, "global field uses one shared attack layer for both heroes")
	for summoned: Summon in manager.enemy.summons: check(summoned.hp == 25, "global field has equal simultaneous attack bonus")

	for caster_side in ["player", "enemy"]:
		prepare()
		manager.player.hp = 12
		manager.enemy.hp = 12
		for owner in [manager.player, manager.enemy]:
			for slot in 3: summon(owner, slot, "water_spring")
		var caster := manager.player if caster_side == "player" else manager.enemy
		caster.hand = ["test_all_board"]
		caster.energy["fire"] = 2
		manager.phase = caster_side + "_action"
		manager._play_card(caster, manager.enemy if caster == manager.player else manager.player, 0, {"kind":"hero"})
		check(manager.phase == "tie" and manager.player.hp == 0 and manager.enemy.hp == 0, "simultaneous lethal is a tie regardless of caster")
		for owner in [manager.player, manager.enemy]:
			for summoned: Summon in owner.summons: check(summoned.hp == 3, "all summons resolve even when both heroes die")
	check(tie_events == 2, "simultaneous lethal emits a distinct tie event for either caster")

	prepare()
	ready_card("metal_temper")
	manager.play_player_card(0)
	check(manager.player.status_stacks("strong_attack") == 3, "temper grants three strong attack")
	ready_card("earth_stone_body")
	manager.play_player_card(0)
	check(manager.player.status_stacks("strong_defense") == 3, "stone body grants three strong defense")
	await manager._end_turn(manager.player)
	check(manager.player.status_stacks("strong_attack") == 3 and manager.player.status_stacks("strong_defense") == 3, "unused fixed states survive turn end")
	prepare()
	manager.player.add_status("weak", 7, 0)
	manager.player.add_status("weak_attack", 4, 0)
	ready_card("fire_clear_weak")
	manager.play_player_card(0)
	check(manager.player.status_stacks("weak") == 0 and manager.player.status_stacks("charge") == 2 and manager.player.status_stacks("weak_attack") == 4, "remove weakness before granting charge, leaving weak attack alone")
	var keywords := CardKeywords.entries(manager.cards["fire_clear_weak"], manager.summon_templates)
	check(keywords.size() == 2 and keywords[0]["title"] == "虚弱 X" and keywords[1]["title"] == "蓄力 X", "cleansing card explains both of its state keywords")
	prepare()
	ready_card("water_tide_scroll")
	var pile_size := manager.player.draw_pile.size()
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 55 and manager.player.hand.size() == 1 and manager.player.draw_pile.size() == pile_size - 1, "water spell deals twenty-five and draws one")
	check(int(manager.cards["water_thought"]["cost"]) == 2, "Tide Thought now costs two")

	prepare()
	manager.player.add_status("strong_attack", 2, 0)
	manager.enemy.add_status("strong_defense", 30, 0)
	ready_card("metal_strike")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 80 and manager.player.status_stacks("strong_attack") == 1 and manager.enemy.status_stacks("strong_defense") == 29, "damage clamps at zero and still consumes the hit states")
	prepare()
	manager.player.add_status("strong_attack", 2, 0)
	manager.enemy.add_status("strong_defense", 1, 0)
	manager.enemy.add_status("shield", 40, 0)
	ready_card("metal_strike")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 80 and manager.enemy.status_stacks("shield") == 29 and manager.player.status_stacks("strong_attack") == 1 and manager.enemy.status_stacks("strong_defense") == 0, "shielded damage still consumes fixed states")
	prepare()
	manager.player.add_status("strong_defense", 3, 0)
	manager.player.add_status("strong_attack", 3, 0)
	manager.player.add_status("burn", 2, 0)
	manager.player.hand = ["metal_strike", "metal_strike", "metal_strike"]
	await manager._end_turn(manager.player)
	check(manager.player.hp == 77 and manager.player.status_stacks("strong_defense") == 2 and manager.player.status_stacks("strong_attack") == 3, "burn consumes only the receiving defense status")

	prepare()
	manager.player.hp = 1
	manager.player.add_status("bleed", 2, 0)
	card = ready_card("test_all_board")
	check(manager.preview_damage_segments(manager.player, card, {"kind":"hero"}).is_empty(), "lethal bleed prevents the pending spell preview")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.phase == "defeat" and manager.enemy.hp == 80, "pre-cast life loss prevents the global damage")

	print("Flat damage: four uncapped states, six cards, ordered hits, simultaneous area damage, preview and draws; %d failures" % failures)
	quit(1 if failures > 0 else 0)
