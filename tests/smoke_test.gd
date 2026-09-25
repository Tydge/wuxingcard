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
	check(manager.player.draw_pile.size() == 25, "draw pile after opening")
	var before_fatigue := manager.player.hp
	manager.player.draw_pile.clear()
	manager.draw_card(manager.player)
	manager.draw_card(manager.player)
	check(manager.player.hp == before_fatigue - 3, "fatigue increases 1 then 2")
	check(manager.player.fatigue_level == 2, "fatigue level")
	test_status_rules(manager)

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
							manager.play_player_card(chosen)
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
	target.add_status("vulnerable", 3, 0)
	check(BattleRules.damage_breakdown(target, 20, "fire", source)["hp"] == 21, "weak and vulnerable change damage by 10% per stack")

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
	manager.play_player_card(0)
	check(actor.hp == 98 and actor.status_stacks("bleed") == 1, "bleed triggers on card play")

	actor.statuses.clear()
	actor.add_status("shield", 7, 2)
	manager._start_turn(actor)
	check(actor.status_stacks("shield") == 4, "shield halves upward at turn start")
	manager._end_turn(actor)
	check(actor.status_stacks("shield") == 4, "shield has no turn limit")
