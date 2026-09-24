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
