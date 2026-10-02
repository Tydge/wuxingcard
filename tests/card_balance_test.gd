extends SceneTree

var failures := 0
var manager: BattleManager

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func clean() -> void:
	for actor in [manager.player, manager.enemy]:
		actor.max_hp = 100
		actor.setup("player" if actor == manager.player else "ember", "测试", [], manager.rng)
	manager.phase = "player_action"

func creature(actor: Combatant) -> void:
	actor.summons[0] = Summon.new()
	actor.summons[0].setup(manager.summon_templates["earth_stele"])

func cast(id: String, selection: Dictionary = {}) -> bool:
	manager.player.hand = [id]
	manager.player.energy[manager.cards[id]["element"]] = int(manager.cards[id]["cost"])
	return manager.play_player_card(0, selection)

func run() -> void:
	manager = BattleManager.new()
	manager.random_artifacts_enabled = false
	root.add_child(manager)
	for level in 3:
		var suffix := "" if level == 0 else "__%d" % level
		# Explicit opponent effects ignore stale selections, from either side.
		for own_side in ["player", "enemy"]:
			clean()
			var actor: Combatant = manager.player if own_side == "player" else manager.enemy
			var opponent: Combatant = manager.enemy if own_side == "player" else manager.player
			creature(opponent)
			opponent.add_status("shield", [10, 16, 25][level] + 5, 0)
			var id := "metal_thunder_break" + suffix
			actor.hand = [id]
			actor.energy["metal"] = 3
			manager.phase = own_side + "_action"
			check(manager.card_target_mode(manager.cards[id]) == "none" and manager._card_candidates(actor, manager.cards[id]) == [{}], "break card does not expose target selection")
			check(manager._play_card(actor, opponent, 0, {"kind":"summon", "side":own_side, "slot":0}), "automatic break card plays from either side")
			check(opponent.hp == 100 - [25, 30, 35][level] + 5 and opponent.summons[0].hp == 15 and actor.hp == 100, "break card removes opponent shield before damaging only opponent hero")
			check(manager.cards[id]["text"] == "对手失去%d层护盾，并对对手造成%d点金伤害。" % [[10, 16, 25][level], [25, 30, 35][level]], "break card wording identifies its fixed recipient")
		clean()
		check(cast("metal_chime_card" + suffix, {"kind":"slot", "slot":0}) and manager.player.summons[0].hp == [8, 11, 14][level] and manager.player.energy["metal"] == 0, "chime costs one and summons the revised health")
		clean()
		creature(manager.enemy)
		check(cast("water_cold_needle" + suffix, {"kind":"summon", "slot":0}) and manager.enemy.hp == 100 and manager.enemy.status_stacks("weak_defense") == [2, 3, 4][level] and manager.enemy.status_stacks("weak_attack") == 0, "needle applies weak defense to opponent even when hitting a summon")
		clean()
		check(cast("wood_regen" + suffix) and manager.player.status_stacks("regen") == [5, 6, 7][level], "regen uses revised layers")
		clean()
		manager.player.add_status("weak", 2, 0)
		manager.player.add_status("weak_attack", 4, 0)
		check(cast("fire_clear_weak" + suffix) and manager.player.status_stacks("charge") == [2, 2, 3][level] and manager.player.status_stacks("weak") == 0 and manager.player.status_stacks("weak_attack") == (0 if level == 2 else 4), "clear spell follows edited costs, charge and removals")
		clean()
		check(cast("earth_strike" + suffix, {"kind":"hero"}) and manager.enemy.hp == 100 - [10, 13, 16][level] and manager.player.status_stacks("strong_attack") == level, "earth strike grants attack after damage")
		# Only the first effective hit on the wearer's own turn, including shields.
		for own_side in ["player", "enemy"]:
			for turn in ["player_action", "enemy_action"]:
				clean()
				var owner: Combatant = manager.player if own_side == "player" else manager.enemy
				var attacker: Combatant = manager.enemy if owner == manager.player else manager.player
				manager.phase = turn
				manager._equip_loadout(owner, {"pendant":"fire_ember_ring" + suffix})
				owner.add_status("shield", 100, 0)
				for hit in 2: manager.apply_damage(attacker, owner, 5, "metal")
				var own_turn: bool = turn.begins_with(own_side)
				check(owner.hp == 100 and owner.energy["fire"] == ([1,1,2][level] if own_turn else 0) and owner.status_stacks("charge") == (1 if own_turn and level > 0 else 0), "ring triggers once only during its owner's turn, for either side")
			clean()
			var owner: Combatant = manager.player if own_side == "player" else manager.enemy
			var attacker: Combatant = manager.enemy if owner == manager.player else manager.player
			manager._equip_loadout(owner,{"pendant":"fire_ember_ring" + suffix})
			owner.draw_pile.assign(["metal_strike","water_strike"])
			await manager._start_turn(owner)
			manager.apply_damage(attacker,owner,1,"metal")
			check(owner.energy["fire"] == [1,1,2][level], "first hit triggers in the first own turn")
			await manager._start_turn(owner)
			manager.apply_damage(attacker,owner,1,"metal")
			check(owner.energy["fire"] == [2,2,4][level], "new own turn resets the ring's once-per-turn flag")
		clean()
		manager._equip_loadout(manager.player, {"pendant":"fire_ember_ring" + suffix})
		manager.player.energy["metal"] = 10
		manager.apply_damage(manager.enemy, manager.player, 5, "metal")
		check(manager.player.energy["fire"] == 0, "immune attacks do not trigger ring")
		manager._lose_life(manager.player, 3, "中毒")
		manager._lose_life(manager.player, 3, "出血")
		manager._lose_life(manager.player, 3, "疲劳")
		check(manager.player.energy["fire"] == 0, "direct life loss does not trigger damage ring")
		manager.player.hp = 1
		manager.apply_damage(manager.enemy, manager.player, 5, "earth")
		check(manager.player.energy["fire"] == 0 and manager.phase == "defeat", "lethal damage does not grant posthumous ring effects")
	clean()
	manager._equip_loadout(manager.enemy, {"pendant":"fire_ember_ring__2"})
	manager.player.hand = ["metal_twin_blades"]
	manager.player.energy["metal"] = 2
	var preview := manager.preview_damage_segments(manager.player, manager.cards["metal_twin_blades"], {"kind":"hero"})
	check(preview == [10, 10] and manager.enemy.energy["fire"] == 0, "preview simulates damage ring without changing real resources")
	manager.play_player_card(0, {"kind":"hero"})
	check(manager.enemy.hp == 80 and manager.enemy.energy["fire"] == 0 and manager.enemy.status_stacks("charge") == 0, "opponent-turn multi-hit cannot activate the ring")
	clean()
	manager.phase = "enemy_action"
	manager._equip_loadout(manager.enemy,{"pendant":"fire_ember_ring__2"})
	manager.player.energy["metal"] = 2
	var own_preview := manager.preview_damage_segments(manager.player,manager.cards["metal_twin_blades"],{"kind":"hero"})
	check(own_preview == [10,10] and manager.enemy.energy["fire"] == 0 and not manager.enemy.artifact_flags.get("own_turn_hit",false), "own-turn preview does not consume the real first-hit trigger")
	manager.apply_damage(manager.player,manager.enemy,10,"metal")
	manager.apply_damage(manager.player,manager.enemy,10,"metal")
	check(manager.enemy.energy["fire"] == 2 and manager.enemy.status_stacks("charge") == 1, "live own-turn multi-hit grants the ring only once")
	for card: Dictionary in manager.cards.values():
		check(not card["text"].contains("受到"), "damage card descriptions use active dealing-damage wording")
		for entry: Dictionary in CardKeywords.entries(card, manager.summon_templates):
			check(entry["title"] != "生牌", "generation has no explanatory popup")
			if entry["title"] == "观想N": check(entry["text"] == "查看牌堆顶至多N张，选1张入手，其余顺序不变。", "contemplation explanation is short and omits fatigue")
	print("Card balance: automatic targets, revised stats, damage ring boundaries, preview and concise keywords; %d failures" % failures)
	manager.queue_free()
	quit(1 if failures else 0)
