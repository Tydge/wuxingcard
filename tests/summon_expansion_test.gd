extends SceneTree

var manager: BattleManager
var failures := 0
var presented: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func prepare() -> void:
	manager.summon_presenter = Callable()
	manager.start_battle("ember", "random", 760)
	for actor in [manager.player, manager.enemy]:
		actor.statuses.clear()
		actor.hp = 80
		actor.summons = [null, null, null]
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.phase = "player_turn_start"

func summon(actor: Combatant, slot: int, id: String) -> Summon:
	var creature := Summon.new()
	creature.setup(manager.summon_templates[id])
	actor.summons[slot] = creature
	return creature

func run() -> void:
	manager = BattleManager.new()
	manager.random_artifacts_enabled = false
	root.add_child(manager)
	prepare()
	check(manager.cards.size() == 240 and manager.summon_templates.size() == 78, "expanded pool has 80 cards and 26 summons")
	var expected := {"metal_falcon":[2,12], "water_koi":[3,20], "wood_frog":[1,6], "fire_fox":[2,10], "earth_badger":[2,16]}
	for id in expected:
		prepare()
		var template: Dictionary = manager.summon_templates[id]
		var card: Dictionary = manager.cards[template["card_id"]]
		check(int(card["cost"]) == expected[id][0] and int(template["hp"]) == expected[id][1], "stats: " + id)
		manager.phase = "player_action"
		manager.player.hand = [card["id"]]
		manager.player.energy[card["element"]] = int(card["cost"])
		check(manager.play_player_card(0, {"kind":"slot", "slot":1}), "summon card accepts selected free slot: " + id)
		check(manager.player.summons[1].id == id and manager.player.summons[1].hp == expected[id][1], "correct creature in selected slot: " + id)
		check(not manager.valid_card_target(manager.player, card, {"kind":"slot", "slot":1}), "occupied slot rejects summon: " + id)

	# Lowest absolute current HP; heroes participate, dead summons do not.
	prepare()
	summon(manager.player, 0, "metal_falcon")
	summon(manager.enemy, 0, "wood_frog").hp = 5
	summon(manager.enemy, 1, "water_koi").hp = 12
	summon(manager.enemy, 2, "earth_badger").hp = 0
	var target := manager.lowest_life_target(manager.enemy)
	check(target == {"kind":"summon", "side":"enemy", "slot":0}, "lowest target ignores dead creature")
	manager.enemy.hp = 3
	check(manager.lowest_life_target(manager.enemy)["kind"] == "hero", "hero is selectable when lowest")
	manager.enemy.hp = 5
	manager.enemy.summons[1].hp = 5
	var seen := {}
	for seed_value in 100:
		manager.rng.seed = seed_value
		var choice := manager.lowest_life_target(manager.enemy)
		seen[str(choice)] = true
		check(choice.get("slot", -1) != 2, "ties never choose dead creature")
	check(seen.size() == 3, "random ties can select every equally-low hero or summon")
	manager.rng.seed = 822
	var sequence: Array = []
	for i in 12: sequence.append(manager.lowest_life_target(manager.enemy))
	manager.rng.seed = 822
	for i in 12: check(sequence[i] == manager.lowest_life_target(manager.enemy), "tie selection uses reproducible battle RNG")
	manager.enemy.hp = 80
	manager.enemy.summons[0].hp = 6
	manager.enemy.summons[1].hp = 20
	manager.player.add_status("strong_attack", 2, 0)
	await manager._trigger_summons(manager.player, "turn_start")
	check(manager.enemy.summons[0] == null and manager.enemy.hp == 80, "falcon targets lowest summon, using metal-over-wood weakness plus fixed attack")
	check(manager.player.status_stacks("strong_attack") == 1, "falcon consumes one attack layer")

	# Choose once before presentation: no reroll between cast and impact.
	prepare()
	summon(manager.player, 0, "metal_falcon")
	summon(manager.enemy, 0, "metal_furnace").hp = 6
	summon(manager.enemy, 1, "wood_frog").hp = 6
	manager.summon_presenter = capture_selection
	await manager._trigger_summons(manager.player, "turn_start")
	var selected_slot := int(presented["slot"])
	check(manager.enemy.summons[selected_slot] == null if selected_slot == 1 else manager.enemy.summons[selected_slot].hp == 4, "presented target receives the hit")
	check(manager.enemy.summons[1 - selected_slot].hp == 6, "other tied target remains untouched")

	# Enemy uses the same targeting logic, mirrored side.
	prepare()
	summon(manager.enemy, 0, "metal_falcon")
	summon(manager.player, 2, "water_koi").hp = 7
	await manager._trigger_summons(manager.enemy, "turn_start")
	check(manager.player.summons[2].hp == 3 and manager.player.hp == 80, "enemy falcon strikes selected friendly summon")

	for side in ["player", "enemy"]:
		prepare()
		var owner := manager.player if side == "player" else manager.enemy
		var opponent := manager.enemy if side == "player" else manager.player
		owner.hp = 70
		summon(owner, 0, "water_koi").hp = 10
		await manager._trigger_summons(owner, "turn_start")
		check(owner.hp == 73 and opponent.hp == 77 and owner.summons[0].hp == 10, "koi heals its summoner and damages opposing hero: " + side)
		owner.hp = 79
		opponent.add_status("shield", 20, 0)
		await manager._trigger_summons(owner, "turn_start")
		check(owner.hp == 80 and opponent.hp == 77, "koi healing is independent of blocked damage and respects max HP")
		opponent.statuses.clear()
		opponent.hp = 1
		owner.hp = 70
		await manager._trigger_summons(owner, "turn_start")
		check(owner.hp == 73 and opponent.hp == 0 and manager.phase in BattleManager.FINISHED_PHASES, "lethal koi damage still includes its healing")

	prepare()
	summon(manager.player, 0, "wood_frog")
	summon(manager.player, 1, "fire_fox")
	summon(manager.player, 2, "earth_badger")
	manager.phase = "player_turn_end"
	await manager._end_turn(manager.player)
	check(manager.enemy.status_stacks("poison") == 2 and manager.enemy.status_stacks("burn") == 1, "frog and fox affect opponent hero only")
	check(manager.player.status_stacks("poison") == 0 and manager.player.status_stacks("shield") == 5, "badger grants summoner five intact shield layers")
	await manager._start_turn(manager.player)
	check(manager.player.status_stacks("shield") == 3, "new end-turn shield first halves on next own turn start, rounded up")

	prepare()
	for id in ["metal_ward", "earth_bastion"]:
		manager.player.hand = [id]
		manager.player.energy[manager.cards[id]["element"]] = 1
		manager.phase = "player_action"
		manager.player.statuses.clear()
		check(manager.play_player_card(0), "shield spell playable")
		check(manager.player.status_stacks("shield") == (12 if id == "metal_ward" else 15), "updated shield balance: " + id)
	manager.player.statuses.clear()
	summon(manager.player, 0, "wood_deer")
	manager.player.hp = 70
	await manager._trigger_summons(manager.player, "turn_end")
	check(manager.player.hp == 74 and int(manager.summon_templates["earth_tortoise"]["hp"]) == 16, "deer healing and tortoise health strengthened")
	check(manager.cards["fire_all_targets"]["name"] == "三昧火", "renamed spell keeps existing ID")
	check(summon(manager.player, 1, "metal_furnace").art_scale == 1.0 and summon(manager.player, 2, "wood_frog").art_scale == 0.82, "optional art scale defaults to one and supports small creatures")

	var pool_seen := {}
	for seed_value in 100:
		manager.start_battle("ember", "random", seed_value)
		for owner in [manager.player, manager.enemy]:
			var deck: Array = owner.hand + owner.draw_pile + owner.discard_pile
			check(manager.valid_random_deck(deck), "expanded random decks retain size, copies and cost limits")
			for id in deck: pool_seen[id] = true
	check(pool_seen.size() == 80, "all new summons participate in random deck generation")
	print("Summon expansion: targeting, ties, element damage, healing, fresh shield and random pool; %d failures" % failures)
	quit(1 if failures > 0 else 0)

func capture_selection(_side: String, _slot: int, _creature: Summon, effect: Dictionary, stage: String) -> void:
	if stage == "cast":
		presented = effect["selection"].duplicate()
		await create_timer(0.01).timeout
	else:
		check(effect["selection"] == presented, "cast and resolved selection identical")
