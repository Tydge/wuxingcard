class_name EnemyPolicy
extends RefCounted

# Score the result of the actual resolver, including conditions, self costs,
# fatigue and artifact reactions. No card or artifact IDs belong in the policy.
static func card_score(manager: BattleManager, card: Dictionary, selection: Dictionary) -> float:
	var copy := manager.simulation_copy()
	var index := manager._simulation_card(copy, copy.enemy, card)
	var played := copy._play_card(copy.enemy, copy.player, index, selection)
	var score := outcome_score(manager, copy, 1) if played else -INF
	copy.free()
	return score

static func artifact_score(manager: BattleManager, selection: Dictionary) -> float:
	var copy := manager.simulation_copy()
	var activated := copy.activate_artifact(copy.enemy, selection)
	var score := outcome_score(manager, copy, 0) if activated else -INF
	copy.free()
	return score

static func funded_card_score(manager: BattleManager, card: Dictionary, selection: Dictionary) -> float:
	var copy := manager.simulation_copy()
	var index := manager._simulation_card(copy, copy.enemy, card)
	var needed := maxi(0, int(card["cost"]) - int(copy.enemy.energy[card["element"]]))
	for i in needed:
		if not copy.convert_qi(copy.enemy, card["element"]): break
	var played := copy._play_card(copy.enemy, copy.player, index, selection) if copy.phase == "enemy_action" else false
	var score := outcome_score(manager, copy, 1) if played else -INF
	copy.free()
	return score

static func outcome_score(before: BattleManager, after: BattleManager, spent_cards: int) -> float:
	if after.enemy.hp <= 0: return -100.0 if after.player.hp <= 0 else -1000.0
	if after.player.hp <= 0: return 1000.0
	var score := float(before.player.hp - after.player.hp)
	score += float(after.enemy.qi - before.enemy.qi) * 0.8
	score += float(after.enemy.hp - before.enemy.hp) * 0.9
	score += float(before.player.hand.size() - after.player.hand.size()) * 8.0
	score += float(after.enemy.hand.size() - before.enemy.hand.size() + spent_cards) * 4.0
	for element in BattleRules.ELEMENTS:
		var gained := int(after.enemy.energy[element]) - int(before.enemy.energy[element])
		score += gained * (3.5 if gained > 0 else 0.8)
		score += (int(before.player.energy[element]) - int(after.player.energy[element])) * 4.0
	score += status_value(after.enemy, after.player) - status_value(before.enemy, before.player)
	score -= status_value(after.player, after.enemy) - status_value(before.player, before.enemy)
	for slot in 3:
		var old_ally: Summon = before.enemy.summons[slot]
		var new_ally: Summon = after.enemy.summons[slot]
		var old_target: Summon = before.player.summons[slot]
		var new_target: Summon = after.player.summons[slot]
		if old_ally == null and new_ally != null: score += summon_value(new_ally)
		elif old_ally != null:
			score += float((new_ally.hp if new_ally != null else 0) - old_ally.hp)
			if new_ally == null: score -= 9.0
		if old_target != null:
			score += float(old_target.hp - (new_target.hp if new_target != null else 0)) * 1.2
			if new_target == null: score += 9.0
	return score

static func status_value(actor: Combatant, opponent: Combatant) -> float:
	var value := actor.status_stacks("shield") * 0.65
	value += (actor.status_stacks("charge") - actor.status_stacks("weak")) * 2.5
	value += (actor.status_stacks("tenacity") - actor.status_stacks("vulnerable")) * 2.5
	value += (actor.status_stacks("strong_attack") - actor.status_stacks("weak_attack")) * 2.0
	value += (actor.status_stacks("strong_defense") - actor.status_stacks("weak_defense")) * 2.0
	for status in ["poison", "bleed"]:
		var stacks := actor.status_stacks(status)
		value -= stacks * (stacks + 1) * 0.3
	value -= actor.status_stacks("burn") * actor.hand.size() * 0.7
	value += mini(actor.max_hp - actor.hp, actor.status_stacks("regen") * 2) * 0.8
	for element in BattleRules.ELEMENTS:
		value -= actor.status_stacks("lock", element) * (2.0 + int(actor.energy[element]))
	return value

static func summon_value(summoned: Summon) -> float:
	var value := 6.0 + summoned.hp * 0.2
	for effect in summoned.turn_start_effects + summoned.turn_end_effects:
		match effect["type"]:
			"gain_energy": value += int(effect.get("amount", 1)) * 4.0
			"draw": value += 5.0
			"damage", "heal", "heal_summon": value += int(effect.get("amount", 0))
			"status": value += int(effect.get("stacks", 0)) * 2.5
	return value
