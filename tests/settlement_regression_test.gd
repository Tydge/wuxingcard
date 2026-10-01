extends SceneTree

var manager: BattleManager
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func clean() -> void:
	for actor in [manager.player, manager.enemy]:
		actor.max_hp = 80
		actor.setup("player" if actor == manager.player else "ember", "测试", [], manager.rng)
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.phase = "player_action"
	manager.battle_log.clear()

func run() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	clean()
	manager._equip_loadout(manager.player, {"pendant": "fire_ember_ring"})
	manager.player.add_status("poison", 4, 0)
	manager._resolve_effect(manager.player, manager.enemy, {"type": "gain_energy", "target": "self", "element": "wood", "amount": 1}, "wood")
	check(manager.player.hp == 76 and manager.player.status_stacks("poison") == 3, "energy poison life loss does not activate the damage ring")
	check(manager.player.energy["wood"] == 1 and manager.player.energy["fire"] == 0, "ring does not gain fire from poison")
	clean()
	manager._equip_loadout(manager.player, {"guard": "wood_vine_robe", "pendant": "fire_ember_ring"})
	manager.player.hp = 40
	manager.player.draw_pile.clear()
	manager.player.discard_pile.assign(["metal_strike"])
	manager.draw_card(manager.player)
	check(manager.player.hp == 37 and manager.player.artifact_durability == 2 and manager.player.energy["fire"] == 0, "fatigue triggers life-loss healing but not the damage ring")
	manager.player.hp = 1
	manager.player.fatigue_level = 0
	manager.player.draw_pile.clear()
	manager.player.discard_pile.assign(["metal_strike"])
	manager.draw_card(manager.player)
	check(manager.player.hp == 0 and manager.phase == "defeat", "post-loss healing does not revive lethal fatigue")
	clean()
	manager._equip_loadout(manager.enemy, {"guard": "wood_vine_robe"})
	manager.enemy.hp = 12
	manager.player.hand = ["metal_twin_blades"]
	manager.player.energy["metal"] = 2
	var rng_state := manager.rng.state
	var flags := manager.enemy.artifact_flags.duplicate()
	var preview := manager.preview_damage_segments(manager.player, manager.cards["metal_twin_blades"], {"kind": "hero", "side": "enemy"})
	check(preview == [10, 4], "preview includes healing between two direct damage segments")
	check(manager.enemy.hp == 12 and manager.enemy.artifact_durability == 3 and manager.enemy.artifact_flags == flags and manager.rng.state == rng_state and manager.player.hand == ["metal_twin_blades"], "simulation leaves HP, durability, flags, hand and RNG unchanged")
	var actual: Array[int] = []
	var recorder := func(hits: Array):
		for hit in hits:
			if hit["side"] == "enemy" and hit["kind"] == "hero": actual.append(hit["amount"])
	manager.damage_segment_resolved.connect(recorder)
	manager.play_player_card(0, {"kind": "hero", "side": "enemy"})
	manager.damage_segment_resolved.disconnect(recorder)
	check(actual == preview, "live card execution equals its simulated direct segments")
	clean()
	manager.enemy.hand = ["wood_miasma"]
	manager.enemy.energy["wood"] = 1
	manager.phase = "enemy_action"
	for seed_value in 100:
		manager.rng.seed = seed_value
		check(manager.peek_enemy_action().index == 0, "poison is selected instead of passing")
	manager.enemy.hand = ["earth_mountain_seal", "metal_strike"]
	manager.enemy.energy["earth"] = 3
	manager.player.hand = ["metal_strike"]
	var with_player_hand := manager._enemy_action_score(manager.cards["earth_mountain_seal"], {"kind": "hero"})
	manager.player.hand.clear()
	check(is_equal_approx(with_player_hand, manager._enemy_action_score(manager.cards["earth_mountain_seal"], {"kind": "hero"})), "self-discard scoring does not inspect opponent's hand")
	manager.enemy.hand = ["earth_mountain_seal"]
	check(manager._enemy_action_score(manager.cards["earth_mountain_seal"], {"kind": "hero"}) > with_player_hand, "discarding a remaining own card is a genuine cost")
	clean()
	manager.phase = "enemy_action"
	manager._equip_loadout(manager.enemy, {"implement": "metal_thunder_ruler"})
	manager.player.hp = 5
	check(manager.peek_enemy_action().kind == "artifact", "the rules layer selects a lethal artifact action")
	await manager.enemy_step()
	check(manager.player.hp == 0 and manager.phase == "defeat", "headless enemy_step executes the same artifact action as the UI")
	clean()
	# Data-defined entries work without adding IDs to the resolver or AI.
	manager.artifacts["test_guard"] = {"id": "test_guard", "name": "测试法衣", "slot": "guard", "element": "wood", "durability": 2, "trigger": "health_lost", "effects": [{"type": "heal", "target": "self", "amount": 3}]}
	manager._equip_loadout(manager.player, {"guard": "test_guard"})
	manager.player.hp = 40
	manager.player.draw_pile.clear()
	manager.player.discard_pile.assign(["metal_strike"])
	manager.draw_card(manager.player)
	check(manager.player.hp == 38 and manager.player.artifact_durability == 1, "new artifact IDs use data-defined effects")
	for element in BattleRules.ELEMENTS:
		manager.player.energy[element] = 5
		var tooltip := BattleRules.energy_tooltip(manager.player, element)
		check(tooltip.contains(BattleRules.element_name(element) + "系伤害抗性+50%") and tooltip.contains(BattleRules.element_name(BattleRules.counter_of(element)) + "系伤害抗性-50%"), "all energy tooltips follow the counter cycle")
	for event in 25: manager._report("事件%d" % event)
	check(manager.battle_log.size() > 14, "journal retains events beyond the former fourteen-event limit")
	var report := manager.export_battle_report()
	check(not report.is_empty() and JSON.parse_string(FileAccess.get_file_as_string(report)).events.size() == manager.battle_log.size(), "exported battle report contains the complete journal")
	if not report.is_empty(): DirAccess.remove_absolute(report)
	print("Settlement regression: poison chains, fatigue, shared simulation, AI, artifacts, tooltips and journal; %d failures" % failures)
	quit(1 if failures > 0 else 0)
