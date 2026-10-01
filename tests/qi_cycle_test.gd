extends SceneTree

var failures := 0
var manager: BattleManager
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func clean() -> void:
	manager.interactive_choices = false
	for actor in [manager.player, manager.enemy]:
		actor.max_hp = 80
		actor.setup("player" if actor == manager.player else "ember", "测试", [], manager.rng)
	manager.phase = "player_action"
	manager.pending_choice.clear()
func run() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	manager.random_artifacts_enabled = false
	await manager.start_battle("ember", "random", 2)
	check(manager.player.qi == 4 and manager.enemy.qi == 3, "opening qi is three plus one on first own turn")
	for actor in [manager.player, manager.enemy]:
		for amount in actor.energy.values(): check(int(amount) == 0, "no automatic elemental energy at opening")
	manager.player.add_status("poison", 3, 0)
	var hp := manager.player.hp
	await manager._start_turn(manager.player)
	check(manager.player.qi == 5 and manager.player.hp == hp and manager.player.status_stacks("poison") == 3, "stored qi accumulates without triggering poison")
	check(manager.convert_qi(manager.player, "metal") and manager.player.qi == 4 and manager.player.energy["metal"] == 1 and manager.player.hp == hp - 3 and manager.player.status_stacks("poison") == 2, "one conversion spends one qi and triggers one poison event")
	check(not manager.convert_qi(manager.enemy, "metal") and not manager.convert_qi(manager.player, "invalid"), "conversion requires current actor and real element")
	manager.player.energy["metal"] = 10
	manager.player.add_status("lock", 1, 2, "wood")
	check(not manager.convert_qi(manager.player, "metal") and not manager.convert_qi(manager.player, "wood") and manager.player.qi == 4, "cap and seal reject without spending")
	manager.pending_choice = {"candidates":["metal_strike"]}
	check(not manager.convert_qi(manager.player, "fire"), "pending choice blocks conversion")
	manager.pending_choice.clear()
	manager.player.qi = 0
	check(not manager.convert_qi(manager.player, "fire"), "empty qi rejects conversion")
	clean()
	manager._equip_loadout(manager.player, {"pendant":"fire_ember_ring"})
	manager.player.add_status("poison", 4, 0)
	check(manager.convert_qi(manager.player, "wood") and manager.player.hp == 76 and manager.player.qi == 2 and manager.player.energy["fire"] == 0, "conversion triggers poison without activating the damage ring")
	clean()
	manager.player.hp = 2
	manager.player.add_status("poison", 2, 0)
	check(manager.convert_qi(manager.player, "earth") and manager.phase == "defeat" and manager.player.qi == 2 and not manager.convert_qi(manager.player, "earth"), "lethal poison ends conversion actions")
	clean()
	manager.player.hand.assign(["water_strike__2"])
	manager.player.discard_pile.assign(["metal_strike__1", "wood_heal__2", "metal_strike__1"])
	manager.player.add_status("shield", 100, 0)
	for element in BattleRules.ELEMENTS: manager.player.energy[element] = 10
	manager.draw_card(manager.player)
	check(manager.player.hp == 75 and manager.player.fatigue_level == 1 and manager.player.status_stacks("shield") == 100 and manager.player.draw_pile.size() == 2 and manager.player.discard_pile.is_empty(), "cycle shuffles only discards and loses five life through shield and resistance")
	check(manager.player.hand.has("water_strike__2"), "held card never participates in shuffle")
	var collected := manager.player.hand.slice(1) + manager.player.draw_pile
	check(collected.count("metal_strike__1") == 2 and collected.count("wood_heal__2") == 1, "shuffle preserves physical copies and grades")
	manager.draw_card(manager.player)
	manager.draw_card(manager.player)
	check(manager.player.fatigue_level == 1 and manager.player.hp == 75, "one fatigue charge per cycle, not per drawn card")
	for damage in [10, 20, 40]:
		manager.player.discard_pile.assign(["metal_strike"])
		var before := manager.player.hp
		manager.draw_card(manager.player)
		check(before - manager.player.hp == damage, "doubling fatigue: " + str(damage))
	check(manager.player.hp == 5 and manager.next_fatigue_damage(manager.player) == 80, "next cycle tooltip reflects eighty after four cycles")
	var hand := manager.player.hand.duplicate()
	manager.player.discard_pile.assign(["fire_strike"])
	manager.draw_card(manager.player)
	check(manager.phase == "defeat" and manager.player.hand == hand and manager.player.draw_pile == ["fire_strike"], "lethal fatigue stops before drawing the recycled card")
	clean()
	manager.draw_card(manager.player)
	check(manager.player.hp == 80 and manager.player.fatigue_level == 0, "no discards means no cycle or fatigue")
	manager.player.hand.assign(["metal_strike", "metal_strike", "wood_heal", "wood_heal", "fire_brand", "fire_brand", "water_strike", "water_strike"])
	manager.player.discard_pile.assign(["earth_ward"])
	manager.draw_card(manager.player)
	check(manager.player.hand.size() == 8 and manager.player.discard_pile == ["earth_ward"] and manager.player.hp == 75, "full hand discards a recycled draw normally")
	clean()
	manager.interactive_choices = true
	manager.player.discard_pile.assign(["metal_strike__1", "wood_heal__2"])
	manager._resolve_effect(manager.player, manager.enemy, {"type":"contemplate", "target":"self", "amount":4}, "water")
	check(manager.player.hp == 75 and manager.player.fatigue_level == 1 and manager.pending_choice["candidates"].size() == 2, "contemplation uses recycled pile and charges once before choice")
	manager.choose_card(1)
	check(manager.player.hand.size() == 1 and manager.player.draw_pile.size() == 1, "contemplation keeps remaining recycled order")
	clean()
	manager.phase = "enemy_action"
	manager.enemy.hand.assign(["metal_strike"])
	manager.player.hp = 5
	var qi := manager.enemy.qi
	var state := manager.rng.state
	var score := EnemyPolicy.funded_card_score(manager, manager.cards["metal_strike"], {"kind":"hero"})
	check(score > 3 and manager.enemy.qi == qi and manager.enemy.energy["metal"] == 0 and manager.rng.state == state and manager.player.hp == 5, "funded AI simulation is independent and detects lethal")
	check(manager.peek_enemy_action().get("kind") == "qi", "AI selects conversion before unaffordable lethal")
	await manager.enemy_step()
	check(manager.enemy.qi == 2 and manager.enemy.energy["metal"] == 1, "AI executes qi action")
	await manager.enemy_step()
	check(manager.phase == "defeat", "AI follows conversion with the funded card")
	clean()
	manager.player.qi = 19
	var copy := manager.simulation_copy()
	check(copy.player.qi == 19, "snapshot preserves stored neutral qi")
	copy.player.qi = 0
	check(manager.player.qi == 19, "simulation cannot spend real qi")
	copy.free()
	check(manager.cards["wood_miasma"]["effects"][0]["stacks"] == 5 and manager.cards["wood_miasma__2"]["effects"][0]["stacks"] == 7 and manager.cards["wood_shared_miasma__2"]["effects"][0]["stacks"] == 6, "poison families use revised base/精/玄 values")
	manager.queue_free()
	await process_frame
	print("Qi and cycling: initial/turn resources, conversion guards, poison/artifacts, fatigue 5/10/20/40, grades, full hand, contemplation, lethal AI and snapshots; %d failures" % failures)
	quit(1 if failures else 0)
