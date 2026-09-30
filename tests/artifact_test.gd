extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var manager := BattleManager.new()
	root.add_child(manager)
	check(manager.artifacts.size() == 45, "five artifacts in each of three slots")
	var ids: Array[String] = []
	for id in manager.cards:
		if int(manager.cards[id].get("level", 0)) != 0: continue
		for copy in DeckStore.MAX_COPIES:
			if ids.size() < 20: ids.append(id)
	var configured := {"id": "artifact_test", "name": "法宝测试", "cards": ids, "artifacts": {"implement": "metal_thunder_ruler", "guard": "earth_rock_armor", "pendant": "earth_origin_jade"}}
	await manager.start_battle("ember", "random", 1024, configured)
	check(manager.player.artifacts == configured["artifacts"], "saved artifact loadout enters battle")
	check(manager.enemy.artifacts.values().size() == 3 and not manager.enemy.artifacts["implement"].is_empty(), "random opponent receives artifacts")
	var actor := manager.player
	var opponent := manager.enemy
	manager._equip_loadout(opponent, {})
	for element in BattleRules.ELEMENTS:
		actor.energy[element] = 0
		opponent.energy[element] = 0
	var initial_hp := opponent.hp
	check(manager.artifact_target_mode(actor) == "none", "metal implement has no target selection")
	check(manager.activate_artifact(actor), "metal implement automatically hits enemy hero")
	check(opponent.hp == initial_hp - 5 and not manager.artifact_can_activate(actor), "metal implement deals five and enters cooldown")
	check(actor.artifact_ready_turn == actor.own_turn_count + 3, "two own turns are skipped before reuse")
	await manager._start_turn(actor)
	check(not manager.artifact_can_activate(actor), "still cooling after one own turn")
	await manager._start_turn(actor)
	check(not manager.artifact_can_activate(actor), "still cooling after two own turns")
	await manager._start_turn(actor)
	check(manager.artifact_can_activate(actor), "ready on third own turn")
	manager._equip_loadout(actor, {"implement": "fire_sun_mirror", "guard": "", "pendant": ""})
	actor.artifact_ready_turn = 0
	actor.energy["fire"] = 0
	check(manager.activate_artifact(actor) and actor.energy["fire"] == 1, "fire mirror grants one fire energy without life loss")
	manager._equip_loadout(actor, {"implement": "earth_mountain_talisman", "guard": "", "pendant": ""})
	actor.artifact_ready_turn = 0
	check(manager.activate_artifact(actor) and actor.status_stacks("shield") == 8, "earth implement grants eight shield layers")
	actor.remove_status("shield")
	manager._equip_loadout(actor, {"guard": "earth_rock_armor"})
	manager.phase = "enemy_action"
	actor.artifact_flags["enemy_turn_hit"] = false
	manager.apply_damage(opponent, actor, 3, "metal")
	check(actor.status_stacks("shield") == 5 and actor.artifact_durability == 2, "earth armor triggers on first enemy-turn hit")
	manager.apply_damage(opponent, actor, 3, "metal")
	check(actor.artifact_durability == 2, "earth armor does not retrigger in same enemy turn")
	actor.remove_status("shield")
	manager._equip_loadout(actor, {"guard": "water_frost_gauze"})
	actor.energy["fire"] = 0
	actor.energy["metal"] = 0
	check(BattleRules.damage_breakdown(actor, 10, "fire", opponent)["raw"] == 8, "frost gauze fire reduction is additive before shield")
	manager.apply_damage(opponent, actor, 10, "fire")
	check(actor.artifact_durability == 2, "frost gauze spends one durability per fire hit")
	manager._equip_loadout(opponent, {"guard": "earth_rock_armor"})
	opponent.artifact_flags["enemy_turn_hit"] = false
	manager.phase = "player_action"
	actor.energy["metal"] = 2
	var twin: Dictionary = manager.cards["metal_twin_blades"]
	var predicted := manager.preview_damage_segments(actor, twin, {"kind": "hero", "side": "enemy"})
	check(predicted == [10, 5], "damage preview includes shield gained between two hits")
	check(opponent.artifact_durability == 3, "damage preview leaves real artifact durability unchanged")
	manager._equip_loadout(actor, {"pendant": "earth_origin_jade"})
	actor.summons = [null, null, null]
	var template: Dictionary = manager.summon_templates.values()[0]
	manager._resolve_effect(actor, opponent, {"type": "summon", "summon": template["id"]}, template["element"], {"kind": "slot", "slot": 0})
	check(actor.summons[0].max_hp == int(template["hp"]) + 2 and actor.summons[0].hp == actor.summons[0].max_hp, "earth pendant increases summon current and maximum life")
	var save_path := "res://work/artifact_decks_test.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	var store := DeckStore.new(manager.cards, save_path)
	var saved := store.save_deck("", "法宝卷", ids, true, configured["artifacts"])
	var reopened := DeckStore.new(manager.cards, save_path)
	reopened.load_decks()
	check(reopened.find_deck(saved["id"])["artifacts"] == configured["artifacts"], "artifact loadout persists in deck")
	DirAccess.remove_absolute(save_path)
	print("Artifact test: rules, cooldown, durability, summons, and persistence; %d failures" % failures)
	quit(1 if failures > 0 else 0)
