extends SceneTree

var m: BattleManager
var failures := 0
var assertions := 0
const NEW_CARDS := ["metal_rupture", "water_clear_dew", "wood_miasma_bloom", "fire_burn_to_earth", "earth_quake_summons"]

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)

func clean() -> void:
	for actor: Combatant in [m.player, m.enemy]:
		actor.max_hp = 200
		actor.setup("player" if actor == m.player else "enemy", "测试", [], m.rng)
	m.phase = "player_action"
	m.pending_choice.clear()

func creature(owner: Combatant, slot: int, element: String, hp: int = 100) -> Summon:
	var s := Summon.new()
	s.setup({"id":"fixture", "name":"灵物", "element":element, "hp":hp})
	owner.summons[slot] = s
	return s

func cast(id: String, selection: Dictionary = {}) -> bool:
	m.player.hand.assign([id])
	m.player.energy[m.cards[id]["element"]] = m.player.card_cost(m.cards[id])
	return m.play_player_card(0, selection)

func run() -> void:
	m = BattleManager.new(); m.random_artifacts_enabled = false; root.add_child(m)
	check(m.cards.size() == 285 and ContentCatalog.base_entries(m.cards).size() == 95, "95 families expand to 285 card versions")
	for level in 3:
		var suffix := "" if level == 0 else "__%d" % level
		clean()
		var bystander := creature(m.enemy, 0, "wood")
		check(m.card_target_mode(m.cards["metal_rupture" + suffix]) == "none", "metal spell needs no selected target")
		check(cast("metal_rupture" + suffix, {"kind":"summon", "slot":0, "side":"enemy"}) and m.enemy.hp == 200 - [12,14,16][level] and m.enemy.status_stacks("bleed") == [3,4,5][level] and bystander.hp == 100, "metal always hits and bleeds the opposing hero")
		clean()
		m.player.add_status("poison", 15, 0); m.player.add_status("burn", 10, 0); m.player.add_status("bleed", 3, 0)
		m.enemy.add_status("poison", 9, 0)
		check(cast("water_clear_dew" + suffix) and m.player.status_stacks("poison") == 15 - [5,6,7][level] and m.player.status_stacks("burn") == 10 - [2,3,4][level], "water removes exact grade amounts")
		check(m.player.status_stacks("bleed") == 2 and m.player.hp == 197 and m.enemy.status_stacks("poison") == 9, "cleansing preserves other states and still pays ordinary bleed loss")
		check(CardKeywords.entries(m.cards["water_clear_dew" + suffix], m.summon_templates).size() == 2, "cleansing describes both relevant status keywords")
		clean()
		m.player.add_status("poison", 2, 0); m.player.add_status("burn", 1, 0)
		check(cast("water_clear_dew" + suffix) and m.player.status_stacks("poison") == 0 and m.player.status_stacks("burn") == 0 and m.player.statuses.is_empty(), "insufficient layers clamp to zero and remove empty states")
		clean()
		m.player.hp = 100
		check(cast("wood_miasma_bloom" + suffix) and m.enemy.status_stacks("poison") == [10,12,12][level] and m.player.status_stacks("regen") == [5,6,6][level] and m.player.hp == 100, "wood poisons only opponent and grants delayed regeneration")
		check(m.cards["wood_miasma_bloom" + suffix]["cost"] == [5,5,4][level], "wood玄 costs four")
		clean()
		creature(m.enemy, 0, "earth", [15,18,20][level])
		check(cast("fire_burn_to_earth" + suffix, {"kind":"summon", "side":"enemy", "slot":0}) and m.enemy.summons[0] == null and m.player.energy["earth"] == [2,2,3][level], "exact lethal summon hit awards grade energy once")
		clean()
		creature(m.enemy, 0, "earth", 100)
		check(cast("fire_burn_to_earth" + suffix, {"kind":"summon", "side":"enemy", "slot":0}) and m.enemy.summons[0].hp == 100 - [15,18,20][level] and m.player.energy["earth"] == 0, "nonlethal hit never awards energy")
		clean()
		m.enemy.hp = [15,18,20][level]
		check(cast("fire_burn_to_earth" + suffix, {"kind":"hero", "side":"enemy"}) and m.phase == "victory" and m.player.energy["earth"] == [2,2,3][level], "hero kill awards energy before victory")
		clean()
		var allies: Array[Summon] = [creature(m.player, 0, "earth"), creature(m.player, 2, "water")]
		var opponents: Array[Summon] = [creature(m.enemy, 0, "metal"), creature(m.enemy, 1, "earth")]
		m.player.add_status("strong_attack", 3, 0)
		var base: int = [30,35,40][level]
		check(cast("earth_quake_summons" + suffix, {"kind":"summon", "side":"player", "slot":0}), "earth area may aim at an allied summon")
		check(allies[0].hp == 100 - roundi((base + 3) * 0.5) and allies[1].hp == 100 - roundi((base + 3) * 1.5) and opponents[0].hp == 100 - (base + 3) and opponents[1].hp == allies[0].hp, "all allied and enemy summons use one attack snapshot and their own affinity")
		check(m.player.hp == 200 and m.enemy.hp == 200 and m.player.status_stacks("strong_attack") == 2, "earth excludes both heroes and consumes attack state once")
	clean()
	m.player.hand.assign(["earth_quake_summons"]); m.player.energy["earth"] = 5
	check(m._card_candidates(m.player, m.cards["earth_quake_summons"]).is_empty() and not m.play_player_card(0, {"kind":"hero", "side":"enemy"}) and m.player.energy["earth"] == 5 and m.player.hand.size() == 1, "no summons means no targets and invalid aim spends nothing")
	creature(m.player, 0, "earth"); creature(m.enemy, 1, "water")
	check(m._card_candidates(m.player, m.cards["earth_quake_summons"]).size() == 2, "area candidates cover both sides and no heroes")
	var before := m.player.energy.duplicate()
	check(m.preview_damage_segments(m.player, m.cards["earth_quake_summons"], {"kind":"summon", "side":"enemy", "slot":1}) == [45] and m.enemy.summons[1].hp == 100 and m.player.energy == before, "preview uses real area settlement without changing battle")
	clean()
	creature(m.enemy, 0, "earth", 15); m.player.energy["earth"] = 9
	m.player.add_status("poison", 4, 0)
	check(cast("fire_burn_to_earth", {"kind":"summon", "side":"enemy", "slot":0}) and m.player.energy["earth"] == 10 and m.player.hp == 196 and m.player.status_stacks("poison") == 3, "kill energy respects cap and triggers poison once for actual gain")
	clean()
	creature(m.enemy, 0, "earth", 15); m.player.add_status("lock", 1, 2, "earth"); m.player.add_status("poison", 4, 0)
	check(cast("fire_burn_to_earth", {"kind":"summon", "side":"enemy", "slot":0}) and m.player.energy["earth"] == 0 and m.player.hp == 200 and m.player.status_stacks("poison") == 4, "locked kill reward gains nothing and never triggers poison")
	clean()
	m.enemy.hp = 15; m.enemy.add_status("shield", 15, 0)
	check(cast("fire_burn_to_earth", {"kind":"hero", "side":"enemy"}) and m.enemy.hp == 15 and m.player.energy["earth"] == 0, "fully shielded damage is not a kill")
	clean()
	m.player.hp = 3; m.player.add_status("bleed", 3, 0); m.player.add_status("poison", 2, 0)
	check(cast("water_clear_dew") and m.phase == "defeat" and m.player.status_stacks("poison") == 2, "lethal payment bleeding prevents subsequent cleanse")
	clean()
	m.phase = "enemy_action"; m.enemy.hand.assign(["fire_burn_to_earth"]); m.enemy.energy["fire"] = 2
	creature(m.player, 0, "earth", 15)
	var aim := {"kind":"summon", "side":"player", "slot":0}
	check(EnemyPolicy.card_score(m, m.cards["fire_burn_to_earth"], aim) > 0 and m.player.summons[0].hp == 15 and m.enemy.energy["earth"] == 0, "AI values kill reward through an isolated resolver copy")
	check(m._play_card(m.enemy, m.player, 0, aim) and m.enemy.energy["earth"] == 2, "enemy uses the identical kill reward path")
	var run_state := EndlessRun.new(m.cards, m.artifacts, m.enemies, "user://ash_cleanse_rules_test.json")
	run_state.new_run(90210)
	for id in NEW_CARDS:
		check(run_state.change_draft(id, true), "new family is available to endless starting selection: " + id)
	DirAccess.remove_absolute(run_state.path)
	print("Ash and cleanse cards: %d assertions, %d failures" % [assertions, failures])
	m.queue_free(); quit(1 if failures else 0)
