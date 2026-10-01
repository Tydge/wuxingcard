extends SceneTree

var m: BattleManager
var failures := 0
const NEW_SUMMONS := ["metal_rift_mantis", "water_breath_newt", "wood_five_banyan", "wood_dew_bloom", "fire_crimson_clam", "earth_law_lion"]

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func clean() -> void:
	for actor: Combatant in [m.player, m.enemy]:
		actor.max_hp = 500
		actor.setup("player" if actor == m.player else "enemy", "测试", [], m.rng)
		for i in 30: actor.draw_pile.append("metal_strike")
	m.phase = "player_action"
	m.pending_choice.clear()
	m.rng.seed = 42

func creature(owner: Combatant, slot: int, id: String) -> Summon:
	var s := Summon.new()
	s.setup(m.summon_templates[id])
	owner.summons[slot] = s
	m._sync_cost_auras()
	return s

func cast(id: String, selection: Dictionary = {}) -> bool:
	m.player.hand.assign([id])
	m.player.energy[m.cards[id]["element"]] = m.player.card_cost(m.cards[id])
	return m.play_player_card(0, selection)

func run() -> void:
	m = BattleManager.new()
	root.add_child(m)
	check(m.cards.size() == 210 and m.summon_templates.size() == 78 and m.artifacts.size() == 90, "all new families have three grades")
	for level in 3:
		var suffix := "" if level == 0 else "__%d" % level
		for id in NEW_SUMMONS:
			clean()
			var selection := {"kind":"slot", "slot":0}
			if id == "metal_rift_mantis": selection["entrance_target"] = {"kind":"hero", "side":"enemy"}
			check(cast(id + "_card" + suffix, selection), "new summon is playable: " + id + suffix)
			check(m.player.summons[0].max_hp == int(m.summon_templates[id + suffix]["hp"]), "grade uses its own summon template: " + id)
			if id == "water_breath_newt":
				check(m.enemy.qi == 3 - [1,1,2][level], "newt removes qi on entrance")
				await m._trigger_summons(m.player)
				check(m.enemy.hp == 500 - [5,6,7][level], "newt randomly attacks at turn start")
			if id == "fire_crimson_clam":
				var first := creature(m.enemy, 0, "earth_law_lion")
				var second := creature(m.enemy, 1, "water_breath_newt")
				await m._trigger_summons(m.player)
				check(first.hp == 28 - [5,6,7][level] and second.hp == 25 - [5,6,7][level] and m.enemy.hp == 500 and m.player.summons[0].hp == [26,30,34][level], "clam hits every opposing summon and neither hero nor allies")
			if id == "metal_rift_mantis":
				check(m.enemy.hp == 500 - [10,14,16][level], "mantis entrance uses selected hero")
				await m._trigger_summons(m.player)
				check(m.enemy.status_stacks("bleed") == [3,3,4][level], "mantis turn adds bleed")
			if id == "wood_five_banyan":
				await m._trigger_summons(m.player)
				var total := 0
				var positive := 0
				for amount in m.player.energy.values():
					total += int(amount)
					if int(amount) > 0: positive += 1
				check(total == [2,2,3][level] and positive == 1, "banyan chooses one element per trigger")
		clean()
		check(cast("water_branch_tide" + suffix, {"kind":"hero", "side":"enemy"}) and m.enemy.hp == 500 - [32,36,36][level] and m.player.energy["wood"] == [1,1,2][level], "water spell damage and wood gain")
		clean()
		creature(m.enemy, 0, "wood_seedling")
		check(cast("fire_sky_burn" + suffix, {"kind":"hero", "side":"enemy"}) and m.enemy.hp == 500 - [20,25,30][level] and m.enemy.summons[0] == null and m.player.hp == 500, "fire wave hits enemies only")
		clean()
		m.player.add_status("shield", 100, 0)
		m.player.add_status("charge", 10, 0)
		check(cast("earth_stacked_peak" + suffix, {"kind":"hero", "side":"enemy"}) and m.enemy.hp == 400 and m.player.status_stacks("shield") == 100, "shield damage caps base at fifty but final can exceed it, without spending shield")
	clean()
	var hand := ["metal_rift_mantis_card"]
	m.player.hand.assign(hand); m.player.energy["metal"] = 4
	check(not m.play_player_card(0, {"kind":"slot", "slot":0}) and m.player.hand == hand and m.player.energy["metal"] == 4 and m.player.summons[0] == null, "missing entrance target cannot spend or summon")
	var aims := m._card_candidates(m.player, m.cards[hand[0]])
	check(aims.size() == 3 and aims[0].has("entrance_target"), "AI enumerates slot and entrance target together")
	clean()
	var hits: Array = []
	m.damage_segment_resolved.connect(func(segment: Array): hits.append(segment.duplicate(true)))
	for slot in 2:
		var target := creature(m.enemy, slot, "earth_law_lion")
		target.max_hp = 200; target.hp = 200
	m.enemy.summons[0].enemy_cost_aura = 0; m.enemy.summons[1].enemy_cost_aura = 0; m._sync_cost_auras()
	check(m.card_target_mode(m.cards["metal_four_thunders"]) == "none", "random spell does not request a selected target")
	check(cast("metal_four_thunders", {"kind":"hero", "side":"enemy"}) and hits.size() == 4, "random spell resolves four independent hits")
	var distinct := {}
	for segment in hits: distinct[str(segment[0]["kind"]) + str(segment[0]["slot"])] = true
	check(distinct.size() > 1, "four hits do not lock the first random target")
	clean()
	creature(m.enemy, 0, "earth_law_lion"); creature(m.enemy, 1, "earth_law_lion__2")
	check(m.player.card_cost(m.cards["metal_forge"]) == 2 and not m.player.can_pay(m.cards["metal_forge"]), "stacked aura taxes zero-cost cards")
	m.apply_summon_damage(m.player, m.enemy, 0, 999, "water")
	check(m.player.card_cost(m.cards["metal_forge"]) == 1, "one death removes only its own aura")
	m.apply_summon_damage(m.player, m.enemy, 1, 999, "water")
	check(m.player.card_cost(m.cards["metal_forge"]) == 0, "last death restores printed costs")
	clean()
	creature(m.player, 0, "wood_dew_bloom"); creature(m.player, 1, "wood_dew_bloom__2"); creature(m.enemy, 0, "wood_dew_bloom")
	m.player.hp = 490
	m._resolve_effect(m.player, m.enemy, {"type":"heal", "target":"self", "amount":4}, "wood")
	check(m.player.hand.size() == 2 and m.enemy.hand.size() == 1, "both sides' multiple blooms each draw for one actual heal")
	m.player.hp = 500
	m._resolve_effect(m.player, m.enemy, {"type":"heal", "target":"self", "amount":4}, "wood")
	check(m.player.hand.size() == 2 and m.enemy.hand.size() == 1, "full-health healing has no draw event")
	m.enemy.summons[0].hp -= 1
	m._resolve_effect(m.enemy, m.player, {"type":"heal_summon", "amount":2}, "water", {"kind":"summon", "side":"enemy", "slot":0})
	check(m.player.hand.size() == 4 and m.enemy.hand.size() == 2, "summon healing counts once per target")
	m._resolve_effect(m.player, m.enemy, {"type":"grow_summon", "amount":2}, "earth", {"kind":"summon", "side":"player", "slot":0})
	check(m.player.hand.size() == 4, "maximum-life growth is not a healing event")
	m.player.hp = 490; m.player.add_status("regen", 1, 0)
	await m._end_turn(m.player)
	check(m.player.hand.size() == 6 and m.enemy.hand.size() == 3, "regeneration emits the same actual-heal event")
	clean()
	creature(m.enemy, 0, "earth_law_lion")
	var shown := m.display_card(m.player, m.cards["metal_strike"])
	check(shown["cost"] == 2 and shown["printed_cost"] == 1 and m.cards["metal_strike"]["cost"] == 1, "display price follows aura without mutating printed data")
	m.player.add_status("charge", 2, 0)
	shown = m.display_card(m.player, m.cards["metal_strike"])
	check(shown["text"].contains("12") and shown["number_colors"].get("12") == "#79df8a", "increased spell damage receives green markup metadata")
	await test_artifacts()
	m.queue_free(); await process_frame
	print("High-cost content: three grades, random hits, entrance transaction, healing, aura, shield cap and 15 artifacts; %d failures" % failures)
	quit(1 if failures else 0)

func test_artifacts() -> void:
	for level in 3:
		var suffix := "" if level == 0 else "__%d" % level
		for id in ["metal_rift_axe", "water_shift_pot", "wood_dew_branch", "fire_wild_banner", "earth_settle_seal"]:
			clean()
			m.player.hp = 450; m.player.add_status("shield", 20, 0)
			creature(m.player, 0, "wood_seedling").hp = 8
			m.enemy.add_status("shield", 30, 0)
			m._equip_loadout(m.player, {"implement":id + suffix})
			check(m.activate_artifact(m.player), "new implement activates: " + id + suffix)
			check(not m.artifact_can_activate(m.player), "new implement enters its documented cooldown")
			match id:
				"metal_rift_axe": check(m.enemy.status_stacks("shield") == 30 - [12,18,24][level] and m.enemy.status_stacks("weak_defense") == [2,3,4][level], "axe breaks shield and opens defense")
				"water_shift_pot": check(m.player.status_stacks("shield") == 0 and m.player.hp == 450 + [8,12,16][level], "pot spends all shield and caps healing")
				"wood_dew_branch": check(m.player.summons[0].hp == mini(15, 8 + [6,9,12][level]) and m.player.hp == 450 and m.player.energy["wood"] == [1,1,2][level], "dew branch heals the lowest allied target and grants wood")
				"fire_wild_banner": check(m.enemy.status_stacks("shield") == 30 - 3 * [4,5,6][level], "banner resolves all three random segments")
				"earth_settle_seal": check(m.player.status_stacks("shield") == 20 + [6,9,12][level] and m.player.summons[0].max_hp == 15 + [1,2,3][level] and m.player.summons[0].hp == 8 + [1,2,3][level], "seal raises shield and all summon life")
		clean(); m._equip_loadout(m.player, {"pendant":"metal_roaming_pendant" + suffix})
		creature(m.enemy, 0, "wood_seedling")
		m.apply_summon_damage(m.player, m.enemy, 0, 999, "water")
		check(m.enemy.status_stacks("bleed") == [1,2,3][level], "roaming pendant reacts to enemy summon death")
		clean(); m._equip_loadout(m.player, {"pendant":"earth_return_jade" + suffix})
		creature(m.player, 0, "wood_seedling")
		m.apply_summon_damage(m.enemy, m.player, 0, 999, "water")
		check(m.player.status_stacks("shield") == [3,4,5][level], "return jade reacts to allied summon death")
		clean(); m._equip_loadout(m.player, {"pendant":"wood_flower_knot" + suffix})
		m.player.hp = 490
		m._resolve_effect(m.player, m.enemy, {"type":"heal", "target":"self", "amount":1}, "wood")
		m._resolve_effect(m.player, m.enemy, {"type":"heal", "target":"self", "amount":1}, "wood")
		var total := 0
		for amount in m.player.energy.values(): total += int(amount)
		check(total == [1,1,2][level], "flower knot uses only first allied heal of own turn")
		clean(); m._equip_loadout(m.player, {"pendant":"fire_kindling_pendant" + suffix})
		check(cast("metal_forge") and m.player.status_stacks("charge") == [1,1,2][level], "kindling reacts to an actually zero-cost play")
		clean(); m._equip_loadout(m.player, {"pendant":"fire_kindling_pendant" + suffix})
		creature(m.enemy, 0, "earth_law_lion")
		check(cast("metal_forge") and m.player.status_stacks("charge") == 0, "printed zero with an active tax does not trigger kindling")
		clean(); m._equip_loadout(m.player, {"pendant":"water_return_pearl" + suffix})
		m.player.hand.assign(["metal_strike", "metal_strike"])
		await m._end_turn(m.player)
		check(m.player.hand.size() == 2 + [1,1,2][level], "return pearl checks hand count at turn end")
		for id in ["metal_tempered_robe", "water_mirror_robe", "fire_scale_robe", "earth_thick_robe", "wood_nesting_robe"]:
			clean(); m.phase = "enemy_action"; m.player.hp = 450
			m._equip_loadout(m.player, {"guard":id + suffix})
			var before := m.player.artifact_durability
			if id == "wood_nesting_robe":
				creature(m.player, 0, "wood_seedling")
				m.apply_summon_damage(m.enemy, m.player, 0, 1, "water")
			else: m.apply_damage(m.enemy, m.player, 1, "water")
			check(m.player.artifact_durability == before - 1, "new guard consumes exactly one durability: " + id)

			match id:
				"metal_tempered_robe": check(m.player.status_stacks("strong_attack") == [1,1,2][level], "tempered robe stores attack for the next damage")
				"water_mirror_robe": check(m.enemy.status_stacks("weak_attack") == [1,1,2][level], "mirror robe's new weakness survives the triggering attack")
				"fire_scale_robe": check(m.enemy.status_stacks("burn") == [1,1,2][level], "scale robe marks the opposing hero")
				"earth_thick_robe":
					check(m.player.status_stacks("tenacity") == [1,2,3][level], "thick robe gains tenacity on actual first loss")
					m.apply_damage(m.enemy, m.player, 10, "water")
					check(m.player.artifact_durability == before - 1, "thick robe cannot trigger twice during the same opposing turn")
				"wood_nesting_robe": check(m.player.hp == 450 + [2,3,4][level], "nesting robe heals the caster after a summon hit")
