extends "res://tests/ash_cleanse_cards_test.gd"

func run() -> void:
	m = BattleManager.new(); m.random_artifacts_enabled = false; root.add_child(m)
	for level in 3:
		var suffix := "" if level == 0 else "__%d" % level
		clean()
		m.player.hand.assign(["metal_cleanse" + suffix]); m.player.draw_pile.assign(["water_strike"])
		m.player.add_status("poison", 9, 0); m.player.add_status("burn", 2, 0)
		m.player.energy["metal"] = [1,1,0][level]
		check(m.play_player_card(0) and m.player.status_stacks("poison") == 0 and m.player.status_stacks("burn") == 2 and m.player.hp == 200, "cleanse removes all poison without touching burn")
		check(m.player.hand.size() == (0 if level == 0 else 1) and m.player.draw_pile.size() == (1 if level == 0 else 0), "only upgraded cleanse draws one")
		clean()
		var water := "water_gather_tide" + suffix
		m.player.hand.assign([water, water, "water_strike__2", "metal_strike"]); m.player.energy["water"] = 2
		var amount: int = 12 + 2 * [2,3,4][level]
		var shown := m.display_card(m.player, m.cards[water])
		check(shown["effects"][0]["display_amount"] == amount and shown["text"].contains("手牌中水系卡牌数"), "face excludes one played copy but counts other upgraded water cards")
		check(m.preview_damage_segments(m.player, m.cards[water], {"kind":"hero","side":"enemy"}) == [amount] and m.player.hand.size() == 4 and m.enemy.hp == 200, "water preview counts remaining hand without mutating state")
		check(m.play_player_card(0, {"kind":"hero","side":"enemy"}) and m.enemy.hp == 200 - amount and m.player.hand.size() == 3, "water actual damage equals preview after removal")
		clean()
		m.player.hand.assign([water]);m.player.energy["water"] = 2
		check(m.play_player_card(0, {"kind":"hero","side":"enemy"}) and m.enemy.hp == 188, "water alone deals base damage")
		clean()
		var own := creature(m.player, 0, "wood")
		var resistant := creature(m.enemy, 0, "wood")
		var vulnerable := creature(m.enemy, 2, "earth")
		check(cast("wood_miasma_rain" + suffix, {"kind":"summon","side":"enemy","slot":0}) and resistant.hp == 96 and vulnerable.hp == 88 and own.hp == 100, "wood hits every enemy summon with independent affinity")
		check(m.enemy.hp == 200 and m.player.hp == 200 and m.enemy.status_stacks("poison") == 3 and m.player.status_stacks("poison") == 0, "wood excludes heroes from damage and poisons only opponent")
		clean()
		var fire := "fire_poison_flame" + suffix
		var divisor: int = [5,5,4][level]
		for stacks in [0, divisor - 1, divisor, 19]:
			clean();m.enemy.add_status("poison", stacks, 0);m.enemy.add_status("burn", 1, 0)
			var expected := floori(float(stacks) / divisor)
			check(m.display_card(m.player, m.cards[fire])["effects"][0]["display_stacks"] == expected, "fire face reflects current poison floor")
			check(cast(fire) and m.enemy.status_stacks("burn") == expected + 1 and m.enemy.status_stacks("poison") == stacks, "fire adds floored burn and preserves poison at boundary")
		clean()
		var earth := "earth_heavy_peak" + suffix
		m.player.hand.assign([earth, "metal_strike", "water_strike__1", "wood_miasma_rain"]);m.player.energy["earth"] = 2
		m.enemy.hand.assign(["metal_strike", "wood_strike__2"])
		m.player.add_status("strong_attack", 2, 0)
		var damage: int = 15 + 2 * [1,2,3][level] + 2
		check(m.display_card(m.player,m.cards[earth])["effects"][0]["display_amount"] == damage and m.preview_damage_segments(m.player,m.cards[earth],{"kind":"hero","side":"enemy"}) == [damage], "earth face and simulation share count and attack bonus")
		check(m.play_player_card(0,{"kind":"hero","side":"enemy"}) and m.enemy.hp == 200 - damage and m.player.status_stacks("strong_attack") == 1 and m.enemy.hand.size() == 2, "earth scales from opponent hand and consumes attack once without discarding")
		clean();m.player.hand.assign([earth,"metal_strike"]);m.player.energy["earth"] = 2
		check(m.play_player_card(0,{"kind":"hero","side":"enemy"}) and m.enemy.hp == 185,"empty opponent hand means earth base damage regardless of own hand")
	clean()
	m.player.hand.assign(["wood_miasma_rain"]);m.player.energy["wood"] = 3
	check(not m.play_player_card(0,{"kind":"hero","side":"enemy"}) and m.player.hand.size() == 1 and m.enemy.status_stacks("poison") == 0, "summon-only wood rejects hero drop without spending or poison")
	clean();m.phase = "enemy_action";m.enemy.hand.assign(["water_gather_tide__2","water_strike__2"]);m.enemy.energy["water"] = 2
	check(EnemyPolicy.card_score(m,m.cards["water_gather_tide__2"],{"kind":"hero","side":"player"}) > 0 and m.player.hp == 200 and m.enemy.hand.size() == 2, "AI hand scaling evaluates detached state")
	check(m._play_card(m.enemy,m.player,0,{"kind":"hero","side":"player"}) and m.player.hp == 184, "enemy water uses its own remaining hand")
	clean();m.phase = "enemy_action";m.enemy.hand.assign(["fire_poison_flame__2"]);m.enemy.energy["fire"] = 1;m.player.add_status("poison", 19, 0);m.player.hand.assign(["metal_strike", "water_strike", "earth_strike"])
	check(EnemyPolicy.card_score(m,m.cards["fire_poison_flame__2"],{}) > 0 and m.player.status_stacks("burn") == 0, "AI values wood-to-fire conversion without mutation")
	check(m._play_card(m.enemy,m.player,0,{}) and m.player.status_stacks("burn") == 4 and m.player.status_stacks("poison") == 19, "enemy fire scales from opposing player poison")
	print("Hand scaling cards: %d assertions, %d failures" % [assertions, failures]); m.queue_free();quit(1 if failures else 0)
