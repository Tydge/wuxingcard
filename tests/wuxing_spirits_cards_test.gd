extends "res://tests/ash_cleanse_cards_test.gd"

const WAVE := ["metal_mountain_sword", "metal_oath_sword_card", "water_return_tide", "water_mirror_spirit_card", "wood_spring_blessing", "wood_spring_mulberry_card", "fire_burn_pact", "fire_ash_luan_card", "earth_seek_vein", "earth_mountain_elder_card"]

func put(owner: Combatant, slot: int, id: String) -> Summon:
	var s := Summon.new(); s.setup(m.summon_templates[id]); owner.summons[slot] = s; return s

func run() -> void:
	m = BattleManager.new(); m.random_artifacts_enabled = false; root.add_child(m)
	check(m.cards.size() == 285 and m.summon_templates.size() == 96, "ten families and all thirty grades load")
	var hero := {"kind":"hero", "side":"enemy"}
	var ally := {"kind":"summon", "side":"player", "slot":0}
	for level in 3:
		var suffix := "" if level == 0 else "__%d" % level
		for previous in ["", "earth", "wood"]:
			clean(); m.player.last_card_element = previous
			var id := "metal_mountain_sword" + suffix
			m.player.energy["metal"] = 2
			var expected: Array[int] = [[12,15,18][level]]
			if previous == "earth": expected.append([12,15,18][level])
			check(m.preview_damage_segments(m.player, m.cards[id], hero) == expected and m.player.last_card_element == previous, "earth predecessor and preview isolation")
			check(cast(id, hero) and m.enemy.hp == 200 - [12,15,18][level] * (2 if previous == "earth" else 1) and m.player.last_card_element == "metal", "metal damage and immediate predecessor advance")
		clean(); put(m.player, 0, "metal_oath_sword" + suffix)
		check(cast("metal_ward") and m.player.status_stacks("strong_attack") == [4,5,6][level], "first gold spell grants grade attack only after settlement")
		cast("metal_ward"); check(m.player.status_stacks("strong_attack") == [4,5,6][level], "same summon triggers once in current turn")
		clean(); var returned := put(m.player, 0, "water_breath_wisp" + suffix); returned.hp = 1; returned.max_hp = 99
		var events: Array[String] = []
		var observer := func(_side: String, _slot: int, kind: String, _element: String, _amount: int, _note: String): events.append(kind)
		m.summon_event.connect(observer)
		check(cast("water_return_tide" + suffix, ally) and m.player.summons[0] == null and m.player.hand.size() == 1 and "destroy" not in events, "return removes without a death event")
		m.summon_event.disconnect(observer)
		var copy_id := m.player.hand[0]
		check(m.cards[copy_id]["canonical_id"] == "water_breath_wisp_card" + suffix and m.player.card_cost(m.cards[copy_id]) == 8 - [1,2,3][level], "return preserves grade with isolated discount")
		m.player.card_cost_increase = 1
		check(m.player.card_cost(m.cards[copy_id]) == 9 - [1,2,3][level] and m.cards["water_breath_wisp_card" + suffix]["cost"] == 8 and copy_id not in ContentCatalog.card_pool(m.cards), "enemy surcharge applies after reduction; printed pool remains unchanged")
		m.player.card_cost_increase = 0; await m._end_turn(m.player)
		check(m.player.hand[0] == copy_id and m.player.card_cost(m.cards[copy_id]) == 8 - [1,2,3][level], "return discount persists across turn end")
		m.player.energy["water"] = 10
		check(m.play_player_card(0, {"kind":"slot", "slot":0}) and m.player.summons[0].hp == [20,24,28][level] and m.player.summons[0].max_hp == [20,24,28][level] and copy_id not in m.player.discard_pile, "resummon uses printed HP and clears copy discount")
		clean(); var grown := creature(m.player, 0, "earth", 20); grown.hp = 4; var second := creature(m.player, 2, "water", 10)
		check(cast("wood_spring_blessing" + suffix) and grown.hp == 4 + [5,7,9][level] and grown.max_hp == 20 + [5,7,9][level] and second.hp == 10 + [5,7,9][level] and m.enemy.summons[0] == null, "wood increases current and max HP of every ally only")
		clean(); put(m.player, 0, "wood_spring_mulberry" + suffix); m.player.hp = 100
		await m._start_turn(m.player)
		check(m.player.status_stacks("regen") == [3,4,5][level] and m.player.hp == 100, "mulberry grants regeneration at turn start, not instant healing")
		await m._end_turn(m.player)
		check(m.player.hp == 100 + [3,4,5][level] and m.player.status_stacks("regen") == [2,3,4][level], "regeneration follows ordinary healing and decay")
		clean(); var fuel := creature(m.player, 0, "wood", 27); fuel.hp = 1
		m.player.energy["fire"] = 1
		var base := mini([30,35,40][level], floori(27 * float([1,1.25,1.5][level])))
		check(m.preview_damage_segments(m.player, m.cards["fire_burn_pact" + suffix], ally) == [base] and fuel.hp == 1, "sacrifice preview floors and caps maximum HP without mutation")
		check(cast("fire_burn_pact" + suffix, ally) and m.enemy.hp == 200 - base and m.player.summons[0] == null, "sacrifice destroys then deals capped grade damage")
		clean(); put(m.player, 0, "fire_ash_luan" + suffix)
		check(cast("fire_kindling", hero) and m.enemy.hp == 200 - [2,3,4][level], "first fire spell triggers one random-enemy pursuit")
		cast("fire_kindling", hero); check(m.enemy.hp == 200 - [2,3,4][level], "pursuit once per own turn")
		m.apply_summon_damage(m.enemy, m.player, 0, 100, "water")
		check(m.enemy.hp == 200 - [2,3,4][level] - [5,6,7][level], "destroyed luan fires its grade death effect once")
		clean(); put(m.player, 0, "water_mirror_spirit" + suffix); m.player.spell_elements = {"water":true}; m.interactive_choices = true
		await m._trigger_summons(m.player, "turn_end")
		check(m.pending_choice.is_empty() and m.player.hand.is_empty(), "one spell element never triggers mirror discovery")
		m.player.spell_elements["wood"] = true
		m._trigger_summons(m.player, "turn_end")
		check(m.pending_choice.get("kind") == "discover" and m.pending_choice["candidates"].size() == [2,3,4][level], "two distinct spells open restricted grade discovery")
		for id: String in m.pending_choice["candidates"]: check(m.cards[id]["element"] == "water" and m.card_target_mode(m.cards[id]) != "slot" and m.cards[id]["level"] == 0, "mirror pool contains original water spells only")
		m.choose_card(0); m.interactive_choices = false
		clean(); m.interactive_choices = true
		check(cast("earth_seek_vein" + suffix) and m.pending_choice["candidates"].size() == [2,3,3][level], "earth uses user-edited cost and discovery count")
		for id: String in m.pending_choice["candidates"]: check(m.cards[id]["element"] == "earth" and m.cards[id]["cost"] >= 3 and m.cards[id]["level"] == 0, "earth filters printed cost and element")
		var chosen: String = m.pending_choice["candidates"][0]; m.choose_card(0)
		var discounted := m.player.hand[0]
		check(m.player.card_cost(m.cards[discounted]) == m.cards[chosen]["cost"] - [1,1,2][level] and m.cards[chosen]["cost"] >= 3, "earth discount belongs to selected copy")
		await m._end_turn(m.player)
		check(m.player.hand == [chosen] and m.player.card_cost(m.cards[chosen]) == m.cards[chosen]["cost"], "earth discount ends with its owning turn")
		m.interactive_choices = false
	# Immediate means the preceding card, including summon cards, and resets each turn.
	clean(); cast("earth_strike", hero); cast("water_clear_dew"); cast("metal_mountain_sword", hero)
	check(m.enemy.hp == 200 - 10 - 12, "an intervening water card cancels earth predecessor")
	clean(); cast("earth_mountain_elder_card", {"kind":"slot", "slot":0}); cast("metal_mountain_sword", hero)
	check(m.enemy.hp == 176, "earth summon counts as previous earth card")
	await m._start_turn(m.player); check(m.player.last_card_element == "" and m.player.spell_elements.is_empty(), "turn start resets both spell history fields")
	# Protection is per summon and per opposing turn, and all segments share one target.
	clean(); var guard := put(m.enemy, 0, "earth_mountain_elder"); guard.hp = 5; put(m.enemy, 1, "earth_mountain_elder")
	m.player.hand.assign(["metal_twin_blades"]); m.player.energy["metal"] = 10
	var rng_before := m.rng.state
	var prediction := m.preview_damage_segments(m.player, m.cards["metal_twin_blades"], hero)
	check(not prediction.is_empty() and guard.hp == 5 and guard.intercept_turn == -1 and m.rng.state == rng_before, "redirect preview preserves life, charge and RNG")
	check(m.play_player_card(0, hero) and m.enemy.hp == 200 and m.enemy.summons[0] == null and m.enemy.summons[1].hp == 22, "dying first guardian loses remaining hits; no second redirect")
	cast("metal_strike", hero); check(m.enemy.hp == 200 and m.enemy.summons[1].intercept_turn == 0, "next spell can use next available guardian")
	cast("metal_strike", hero); check(m.enemy.hp == 190, "guardians are limited once in the same opposing turn")
	clean(); put(m.player, 0, "fire_ash_luan"); m.player.add_status("strong_attack", 2, 0)
	m.player.hand.assign(["fire_burn_pact"]); m.player.energy["fire"] = 1
	var segments := m.preview_damage_segments(m.player, m.cards["fire_burn_pact"], ally)
	check(segments == [7,9] and m.player.status_stacks("strong_attack") == 2, "death consumes attack before sacrifice blast, through shared preview")
	m.play_player_card(0, ally); check(m.enemy.hp == 184 and m.player.status_stacks("strong_attack") == 0, "death and sacrifice consume separate attack segments")
	clean(); put(m.player, 0, "fire_ash_luan"); creature(m.enemy, 0, "earth", 1)
	m.player.hand.assign(["earth_quake_summons"]); m.player.energy["earth"] = 5
	m.play_player_card(0, ally); check(m.player.summons[0] == null and m.enemy.summons[0] == null and m.enemy.hp == 195, "area removes all dead summons before random death aim is selected")
	clean(); put(m.player, 0, "fire_ash_luan"); m.enemy.hp = 5
	cast("fire_burn_pact", ally); check(m.phase == "victory" and m.enemy.hp == 0, "lethal death effect stops subsequent sacrifice damage")
	clean(); put(m.player, 0, "water_breath_wisp"); m.player.hand.assign(["water_return_tide", "metal_strike", "metal_strike", "metal_strike", "metal_strike", "metal_strike", "metal_strike", "metal_strike"])
	m._resolve_effect(m.player, m.enemy, {"type":"return_summon", "cost_reduction":2}, "water", ally)
	check(m.player.hand.size() == 8 and m.player.discard_pile == ["water_breath_wisp_card"], "full hand receives canonical contract into discard without retaining discount")
	clean(); m.phase = "enemy_action"; put(m.enemy, 0, "metal_oath_sword"); m.enemy.hand.assign(["metal_ward"]); m.enemy.energy["metal"] = 10
	var original_rng := m.rng.state
	check(EnemyPolicy.card_score(m, m.cards["metal_ward"], {}) > 0 and m.enemy.status_stacks("strong_attack") == 0 and m.enemy.summons[0].spell_trigger_turn == -1 and m.rng.state == original_rng, "AI evaluates new trigger in detached state")
	check(m._play_card(m.enemy, m.player, 0) and m.enemy.status_stacks("strong_attack") == 4, "enemy and player share the trigger resolver")
	for id in WAVE:
		check(not m.cards[id]["text"].contains("连诀") and not m.cards[id]["text"].contains("护阵"), "no extra combo or protection keyword")
	print("Wuxing spirits: %d assertions, %d failures" % [assertions, failures])
	m.queue_free(); quit(1 if failures else 0)
