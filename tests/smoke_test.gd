extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_tests() -> void:
	var target := Combatant.new()
	for element in BattleRules.ELEMENTS:
		target.energy[element] = 0
	target.energy["fire"] = 6
	target.energy["metal"] = 4
	check(BattleRules.damage_breakdown(target, 20, "fire")["hp"] == 16, "fire damage formula")
	target.energy["fire"] = 10
	target.energy["metal"] = 0
	check(BattleRules.damage_breakdown(target, 20, "fire")["hp"] == 0, "same-element immunity")
	target.energy["metal"] = 5
	check(BattleRules.damage_breakdown(target, 20, "fire")["hp"] == 10, "counter restores damage")
	target.add_status("shield", 7, 2)
	check(BattleRules.damage_breakdown(target, 20, "fire")["hp"] == 3, "shield preview")

	var manager := BattleManager.new()
	root.add_child(manager)
	manager.start_battle("ember", "balanced", 12345)
	check(manager.player.hand.size() == 5, "opening hand plus first-turn draw")
	check(manager.enemy.hand.size() == 4, "enemy hand hidden but drawn")
	check(manager.player.draw_pile.size() == 35, "draw pile after opening")
	var before_fatigue := manager.player.hp
	manager.player.draw_pile.clear()
	manager.draw_card(manager.player)
	manager.draw_card(manager.player)
	check(manager.player.hp == before_fatigue - 3, "fatigue increases 1 then 2")
	check(manager.player.fatigue_level == 2, "fatigue level")
	test_status_rules(manager)
	test_opposite_status_rules()
	test_summon_rules(manager)
	test_new_summon_rules(manager)

	var simulations := 0
	var victories := 0
	for enemy_id in ["ember", "tide", "harmony"]:
		for deck_id in ["balanced", "flame", "tide"]:
			for seed_value in range(10):
				manager.start_battle(enemy_id, deck_id, seed_value + 100)
				var steps := 0
				while manager.phase not in ["victory", "defeat"] and steps < 1000:
					steps += 1
					if manager.phase == "player_action":
						var chosen := -1
						for i in manager.player.hand.size():
							if manager.player.can_pay(manager.cards[manager.player.hand[i]]):
								chosen = i
								break
						if chosen >= 0:
							var card: Dictionary = manager.cards[manager.player.hand[chosen]]
							var selection := {}
							match manager.card_target_mode(card):
								"damage": selection = {"kind": "hero"}
								"slot": selection = {"kind": "slot", "slot": manager.player.first_free_summon_slot()}
							manager.play_player_card(chosen, selection)
						else:
							manager.end_player_turn()
					elif manager.phase == "enemy_action":
						manager.enemy_step()
					else:
						check(false, "stalled phase: " + manager.phase)
						break
					for actor in [manager.player, manager.enemy]:
						check(actor.hp >= 0 and actor.hp <= actor.max_hp, "HP bounds")
						for element in BattleRules.ELEMENTS:
							check(int(actor.energy[element]) >= 0 and int(actor.energy[element]) <= 10, "energy bounds")
				check(steps < 1000, "battle did not finish: %s/%s/%d" % [enemy_id, deck_id, seed_value])
				if manager.phase == "victory":
					victories += 1
				simulations += 1
	print("Smoke test: %d battles, %d victories, %d failures" % [simulations, victories, failures])
	quit(1 if failures > 0 else 0)

func test_status_rules(manager: BattleManager) -> void:
	manager.start_battle("ember", "balanced", 2468)
	var actor := manager.player
	var opponent := manager.enemy
	actor.statuses.clear()
	for element in BattleRules.ELEMENTS:
		actor.energy[element] = 0
	actor.energy["fire"] = 6
	actor.hand.clear()
	for i in 3:
		actor.hand.append("fire_strike")
	actor.hp = 100
	actor.add_status("burn", 2, 3)
	actor.add_status("shield", 1, 2)
	manager._end_turn(actor)
	check(actor.hp == 99, "burn uses hand size, fire resistance, and shield")
	check(actor.status_stacks("burn") == 1, "burn loses one stack at turn end")
	check(actor.status_stacks("shield") == 0, "shield absorbs burn damage")
	check(int(actor.statuses[0]["turns"]) == 0, "burn has no duration")

	actor.statuses.clear()
	actor.hp = 80
	actor.add_status("regen", 3, 2)
	actor.add_status("weak", 2, 2)
	actor.add_status("vulnerable", 3, 2)
	manager._end_turn(actor)
	check(actor.hp == 83 and actor.status_stacks("regen") == 2, "regen heals current stacks at turn end, then decays")
	check(actor.status_stacks("weak") == 1 and actor.status_stacks("vulnerable") == 2, "weak and vulnerable decay at turn end")
	check(manager.status_tooltip(actor.statuses[0]).contains("回合结束"), "status tooltip explains trigger")

	var source := Combatant.new()
	var target := Combatant.new()
	for element in BattleRules.ELEMENTS:
		source.energy[element] = 0
		target.energy[element] = 0
	source.add_status("weak", 2, 0)
	source.add_status("charge", 3, 0)
	target.add_status("vulnerable", 3, 0)
	target.add_status("tenacity", 1, 0)
	check(BattleRules.damage_breakdown(target, 20, "fire", source)["hp"] == 26, "damage modifiers add before rounding")
	target.energy["fire"] = 2
	target.energy["metal"] = 1
	check(BattleRules.damage_breakdown(target, 20, "fire", source)["hp"] == 24, "elemental and status percentages add together")
	check(BattleRules.summon_damage(20, source) == 22, "charge and weak add for summon targets")
	check(manager.status_tooltip(source.statuses[0]).contains("10%"), "charge tooltip shows remaining bonus after cancellation")
	check(manager.status_tooltip(target.statuses[0]).contains("20%"), "vulnerable tooltip shows remaining bonus after cancellation")
	target.add_status("tenacity", 12, 0)
	check(BattleRules.damage_breakdown(target, 20, "fire", source)["hp"] == 0, "damage multiplier never becomes negative")
	actor.statuses.clear()
	opponent.statuses.clear()
	for element in BattleRules.ELEMENTS:
		opponent.energy[element] = 0
	actor.add_status("charge", 2, 0)
	opponent.add_status("tenacity", 1, 0)
	var strike: Dictionary = manager.cards["metal_strike"]
	var preview := manager.preview_damage_segments(actor, strike, {"kind": "hero"})
	var hp_before := opponent.hp
	manager.apply_damage(actor, opponent, 10, "metal")
	check(preview == [11] and hp_before - opponent.hp == 11, "preview and actual damage share additive calculation")

	actor.statuses.clear()
	actor.hp = 100
	actor.energy["metal"] = 0
	actor.add_status("poison", 3, 0)
	manager._resolve_effect(actor, opponent, {"type":"gain_energy", "target":"self", "element":"metal", "amount":3}, "metal")
	check(actor.hp == 97 and actor.status_stacks("poison") == 2, "poison triggers once for one multi-point energy gain")
	actor.statuses.clear()
	actor.hp = 100
	actor.hand.clear()
	actor.hand.append("fire_strike")
	actor.energy["fire"] = 3
	actor.add_status("bleed", 2, 0)
	manager.phase = "player_action"
	manager.play_player_card(0, {"kind": "hero"})
	check(actor.hp == 98 and actor.status_stacks("bleed") == 1, "bleed triggers on card play")

	actor.statuses.clear()
	actor.add_status("shield", 7, 2)
	manager._start_turn(actor)
	check(actor.status_stacks("shield") == 4, "shield halves upward at turn start")
	manager._end_turn(actor)
	check(actor.status_stacks("shield") == 4, "shield has no turn limit")

func test_opposite_status_rules() -> void:
	var actor := Combatant.new()
	for pair in [["charge", "weak"], ["tenacity", "vulnerable"]]:
		actor.statuses.clear()
		actor.add_status(pair[0], 3, 0)
		actor.add_status(pair[1], 2, 0)
		check(actor.status_stacks(pair[0]) == 1 and actor.status_stacks(pair[1]) == 0, "opposite layers cancel: " + pair[0])
		actor.add_status(pair[1], 4, 0)
		check(actor.status_stacks(pair[0]) == 0 and actor.status_stacks(pair[1]) == 3, "excess opposite layers remain: " + pair[1])
		actor.add_status(pair[0], 3, 0)
		check(actor.statuses.is_empty(), "equal opposite layers remove both icons")
		actor.add_status(pair[0], 20, 0)
		actor.add_status(pair[0], 2, 0)
		check(actor.status_stacks(pair[0]) == 10, "paired status caps at ten")
		actor.add_status(pair[1], 15, 0)
		check(actor.status_stacks(pair[1]) == 5, "cancellation happens before incoming stack cap")
	actor.statuses.clear()
	for status_id in ["shield", "burn", "poison", "bleed", "regen"]:
		actor.add_status(status_id, 15, 0)
		check(actor.status_stacks(status_id) == 15, "other statuses remain uncapped: " + status_id)

func test_summon_rules(manager: BattleManager) -> void:
	manager.start_battle("ember", "balanced", 4321)
	for summon_id in ["metal_furnace", "wood_seedling", "water_spring", "fire_lantern", "earth_stele"]:
		var template: Dictionary = manager.summon_templates[summon_id]
		check(int(template["hp"]) == 15, "%s has 15 starting HP" % summon_id)
		check(int(manager.cards[template["card_id"]]["cost"]) == 2, "%s costs 2 energy" % summon_id)
	var actor := manager.player
	var opponent := manager.enemy
	actor.hand = ["metal_furnace_card"]
	actor.energy["metal"] = 2
	check(not manager.play_player_card(0, {"kind": "slot", "slot": 3}), "summon rejects invalid slot")
	check(actor.hand.size() == 1 and actor.energy["metal"] == 2, "invalid summon does not spend resources")
	check(manager.play_player_card(0, {"kind": "slot", "slot": 0}), "summon card uses chosen empty slot")
	var summoned: Summon = actor.summons[0]
	check(summoned != null and summoned.hp == 15 and summoned.max_hp == 15, "summon starts with 15 HP")
	actor.energy["water"] = 0
	actor.add_status("poison", 2, 0)
	var hp_before := actor.hp
	manager._trigger_summons(actor)
	check(actor.energy["water"] == 1, "metal summon generates water energy at turn start")
	check(actor.hp == hp_before - 2 and actor.status_stacks("poison") == 1, "summon energy triggers poison once")
	for summon_id in ["wood_seedling", "water_spring", "fire_lantern", "earth_stele"]:
		var template: Dictionary = manager.summon_templates[summon_id]
		var produced: String = template["turn_start"][0]["element"]
		actor.summons[0] = Summon.new()
		actor.summons[0].setup(template)
		actor.energy[produced] = 0
		actor.statuses.clear()
		manager._trigger_summons(actor)
		check(actor.energy[produced] == 1, "%s produces its listed element" % summon_id)
	actor.summons[0] = null
	opponent.summons[1] = Summon.new()
	opponent.summons[1].setup(manager.summon_templates["wood_seedling"])
	for element in BattleRules.ELEMENTS:
		opponent.energy[element] = 0
	opponent.energy["fire"] = 10
	actor.hand = ["fire_edge"]
	actor.energy["fire"] = 3
	manager.phase = "player_action"
	var attack: Dictionary = manager.cards["fire_edge"]
	check(manager.preview_damage_segments(actor, attack, {"kind": "summon", "slot": 1}) == [15], "summon preview ignores fire resistance")
	check(manager.preview_damage_segments(actor, attack, {"kind": "hero"}) == [0], "hero preview still uses fire resistance")
	opponent.energy["fire"] = 0
	actor.hand = ["fire_edge"]
	check(manager.play_player_card(0, {"kind": "hero"}), "hero remains targetable while a summon is present")
	check(opponent.hp == 80 and opponent.summons[1] != null, "hero attack leaves summon untouched")
	actor.hand = ["fire_edge"]
	actor.energy["fire"] = 3
	var hero_hp := opponent.hp
	check(manager.play_player_card(0, {"kind": "summon", "slot": 1}), "damage card can target a summon")
	check(opponent.summons[1] == null and opponent.hp == hero_hp, "damage destroys summon without hitting hero")
	var multi := {"element": "fire", "effects": [
		{"type": "damage", "amount": 3, "element": "fire"},
		{"type": "damage", "amount": 2, "element": "fire"},
		{"type": "damage", "amount": 1, "element": "fire"}]}
	opponent.energy["fire"] = 0
	check(manager.preview_damage_segments(actor, multi, {"kind": "hero"}) == [3, 2, 1], "multi-hit preview lists every hit")
	opponent.add_status("shield", 2, 0)
	check(manager.preview_damage_segments(actor, multi, {"kind": "hero"}) == [1, 2, 1], "multi-hit preview consumes shield only once")
	manager.cards["test_multi"] = {"id": "test_multi", "name": "测试连击", "element": "fire", "cost": 0, "effects": multi["effects"]}
	actor.hand = ["test_multi"]
	manager.phase = "player_action"
	var before_multi := opponent.hp
	check(manager.play_player_card(0, {"kind": "hero"}), "multi-hit card can target hero")
	check(opponent.hp == before_multi - 4 and opponent.status_stacks("shield") == 0, "actual multi-hit matches shield-aware preview")
	opponent.summons[2] = Summon.new()
	opponent.summons[2].setup(manager.summon_templates["earth_stele"])
	opponent.summons[2].hp = 4
	check(manager.preview_damage_segments(actor, multi, {"kind": "summon", "slot": 2}) == [3, 1, 0], "multi-hit preview caps each hit at remaining summon HP")
	actor.hand = ["test_multi"]
	manager.phase = "player_action"
	check(manager.play_player_card(0, {"kind": "summon", "slot": 2}), "multi-hit card can target summon")
	check(opponent.summons[2] == null, "multi-hit destroys summon and frees its slot")
	manager.cards.erase("test_multi")
	for slot in actor.summons.size():
		actor.summons[slot] = Summon.new()
		actor.summons[slot].setup(manager.summon_templates["metal_furnace"])
	check(not actor.can_pay(manager.cards["metal_furnace_card"]), "full summon slots block another summon card")
	for element in BattleRules.ELEMENTS:
		actor.energy[element] = 0
	actor.energy["fire"] = 10
	opponent.hand = ["fire_edge"]
	opponent.energy["fire"] = 3
	manager.phase = "enemy_action"
	var enemy_action := manager.peek_enemy_action()
	check(enemy_action["target"].get("kind", "") == "summon", "enemy can choose player summon over resistant hero")
	var chosen_slot := int(enemy_action["target"].get("slot", -1))
	manager.enemy_step(int(enemy_action["index"]), enemy_action["target"])
	check(chosen_slot >= 0 and actor.summons[chosen_slot] == null, "enemy damage destroys a player summon")

func test_new_summon_rules(manager: BattleManager) -> void:
	manager.start_battle("ember", "balanced", 5678)
	var actor := manager.player
	var opponent := manager.enemy
	var expected := {
		"metal_chime": ["metal", 2, 12],
		"wood_deer": ["wood", 2, 13],
		"water_conch": ["water", 2, 10],
		"fire_raven": ["fire", 2, 11],
		"earth_tortoise": ["earth", 2, 15],
	}
	for summon_id in expected:
		var template: Dictionary = manager.summon_templates[summon_id]
		var card: Dictionary = manager.cards[template["card_id"]]
		check(template["element"] == expected[summon_id][0] and int(card["cost"]) == expected[summon_id][1] and int(template["hp"]) == expected[summon_id][2], "new summon stats: " + summon_id)
		check(card["effects"][0]["summon"] == summon_id and manager.card_target_mode(card) == "slot", "new summon card target: " + summon_id)
		check(manager.find_entry(manager.decks, "balanced")["cards"].has(template["card_id"]), "new summon appears in balanced deck: " + summon_id)
	for slot in actor.summons.size():
		actor.summons[slot] = null
	actor.summons[0] = Summon.new()
	actor.summons[0].setup(manager.summon_templates["metal_chime"])
	manager._trigger_summons(actor, "turn_start")
	check(actor.status_stacks("charge") == 1, "metal chime adds one charge layer")
	actor.summons[0].setup(manager.summon_templates["wood_deer"])
	actor.hp = 80
	manager._trigger_summons(actor, "turn_end")
	check(actor.hp == 83, "wood deer heals at turn end")
	actor.summons[0].setup(manager.summon_templates["water_conch"])
	var hand_before := actor.hand.size()
	var pile_before := actor.draw_pile.size()
	manager._trigger_summons(actor, "turn_start")
	check(actor.hand.size() == hand_before + 1 and actor.draw_pile.size() == pile_before - 1, "water conch draws a card at turn start")
	actor.summons[0].setup(manager.summon_templates["fire_raven"])
	opponent.energy["fire"] = 0
	opponent.energy["metal"] = 0
	opponent.statuses.clear()
	var hp_before := opponent.hp
	manager._trigger_summons(actor, "turn_end")
	check(opponent.hp == hp_before - 4, "fire raven deals ordinary fire damage")
	actor.summons[0].setup(manager.summon_templates["earth_tortoise"])
	manager._end_turn(actor)
	check(actor.status_stacks("tenacity") == 1, "earth tortoise's end-turn tenacity does not decay immediately")
	check(opponent.status_stacks("weak") == 0, "earth tortoise does not debuff opponent")
	actor.summons[0] = null
	manager._end_turn(actor)
	check(actor.status_stacks("tenacity") == 0, "tenacity decays on following turn end")
	actor.summons[0] = Summon.new()
	actor.summons[0].setup(manager.summon_templates["fire_raven"])
	opponent.hp = 3
	manager.phase = "player_turn_end"
	manager._end_turn(actor)
	check(manager.phase == "victory" and opponent.hp == 0, "lethal summon effect ends battle before next turn")
