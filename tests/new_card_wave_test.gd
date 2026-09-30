extends SceneTree

var failures := 0
var manager: BattleManager

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, description: String) -> void:
    if not ok:
        failures += 1
        push_error(description)

func prepare() -> void:
    manager.start_battle("ember", "random", 2409)
    for actor in [manager.player, manager.enemy]:
        actor.hp = 80
        actor.statuses.clear()
        actor.summons = [null, null, null]
        for element in BattleRules.ELEMENTS: actor.energy[element] = 0
    manager.phase = "player_action"

func summon(actor: Combatant, slot: int, id: String, hp: int = -1) -> void:
    var unit := Summon.new()
    unit.setup(manager.summon_templates[id])
    if hp >= 0: unit.hp = hp
    actor.summons[slot] = unit

func cast(id: String, energy: int, selection: Dictionary = {}) -> bool:
    manager.player.hand = [id]
    manager.player.energy[manager.cards[id]["element"]] = energy
    return manager.play_player_card(0, selection)

func run() -> void:
    manager = BattleManager.new()
    manager.random_artifacts_enabled = false
    root.add_child(manager)
    check(manager.cards.size() == 180 and manager.summon_templates.size() == 60, "new pool contains 60 cards and 20 summons")

    prepare()
    summon(manager.player, 0, "earth_stele")
    summon(manager.enemy, 0, "earth_stele")
    summon(manager.enemy, 1, "earth_tortoise")
    var area: Dictionary = manager.cards["fire_all_targets"]
    check(manager.card_target_mode(area) == "enemy_summons" and not manager.valid_card_target(manager.player, area, {"kind":"hero", "side":"enemy"}), "Samadhi Fire only aims at enemy summons")
    check(cast("fire_all_targets", 3, {"kind":"summon", "side":"enemy", "slot":0}), "Samadhi Fire casts onto an enemy summon")
    check(manager.enemy.hp == 80 and manager.player.hp == 80 and manager.player.summons[0].hp == 15, "Samadhi Fire leaves both heroes and allied summons alone")
    check(manager.enemy.summons[0] == null and manager.enemy.summons[1].hp == 1, "Samadhi Fire hits every enemy summon")

    prepare()
    check(cast("wood_spirit_vine", 2, {"kind":"hero"}) and manager.enemy.hp == 66, "vine now deals 14")
    prepare()
    check(cast("water_tide_scroll", 3, {"kind":"hero"}) and manager.enemy.hp == 55, "tide scroll now deals 25")

    prepare()
    var marten: Dictionary = manager.cards["metal_thunder_marten_card"]
    manager.player.energy["metal"] = 4
    check(not manager.card_condition_met(manager.player, marten), "summon entrance threshold uses post-cost energy")
    check(cast("metal_thunder_marten_card", 4, {"kind":"slot", "slot":0}) and manager.enemy.hp == 80, "four metal leaves two and skips entrance damage")
    prepare()
    manager.player.energy["metal"] = 5
    check(manager.card_condition_met(manager.player, marten), "summon condition highlights at five pre-cost metal")
    check(cast("metal_thunder_marten_card", 5, {"kind":"slot", "slot":0}) and manager.enemy.hp == 72, "five metal leaves three and entrance deals eight")
    await manager._trigger_summons(manager.player)
    check(manager.enemy.hp == 69, "thunder marten deals three at turn start")

    prepare()
    manager.enemy.add_status("shield", 15, 0)
    var break_card: Dictionary = manager.cards["metal_thunder_break"]
    manager.player.energy["metal"] = 3
    check(manager.preview_damage_segments(manager.player, break_card, {"kind":"hero"}) == [20], "preview accounts for breaking ten shield before damage")
    check(cast("metal_thunder_break", 3, {"kind":"hero"}) and manager.enemy.status_stacks("shield") == 0 and manager.enemy.hp == 60, "shield break resolves before metal strike")

    prepare()
    check(cast("water_frost_moth_card", 3, {"kind":"slot", "slot":0}), "frost moth enters")
    await manager._trigger_summons(manager.player, "turn_end")
    check(manager.enemy.status_stacks("weak") == 2, "frost moth adds two weak at turn end")
    prepare()
    check(cast("water_cold_needle", 1, {"kind":"hero"}) and manager.enemy.hp == 73 and manager.enemy.status_stacks("weak_attack") == 2, "cold needle hits once and adds two weak attack")

    prepare()
    check(cast("wood_thorn_flower_card", 3, {"kind":"slot", "slot":0}), "plant spirit enters")
    manager.player.summons[0].hp = 8
    await manager._trigger_summons(manager.player)
    check(manager.enemy.hp == 76 and manager.player.summons[0].hp == 12, "plant spirit attacks then restores its own health")
    prepare()
    check(cast("wood_shared_miasma", 0) and manager.player.status_stacks("poison") == 4 and manager.enemy.status_stacks("poison") == 4, "zero-cost miasma poisons both heroes")

    prepare()
    var sun: Dictionary = manager.cards["fire_sun_awakening"]
    manager.player.energy["fire"] = 4
    check(not manager.card_condition_met(manager.player, sun), "fire spell condition is not met at four before payment")
    var before := manager.player.draw_pile.size()
    check(cast("fire_sun_awakening", 4, {"kind":"hero"}) and manager.enemy.hp == 52 and manager.player.draw_pile.size() == before, "four fire deals 28 without drawing")
    prepare()
    manager.player.energy["fire"] = 5
    check(manager.card_condition_met(manager.player, sun), "fire spell condition highlights at five before payment")
    before = manager.player.draw_pile.size()
    check(cast("fire_sun_awakening", 5, {"kind":"hero"}) and manager.player.energy["fire"] == 2 and manager.player.draw_pile.size() == before - 1, "five fire draws despite dropping to two after payment")

    prepare()
    check(cast("fire_ember_lizard_card", 1, {"kind":"slot", "slot":0}) and manager.player.hp == 75, "ember lizard entrance damages its summoner")
    summon(manager.enemy, 0, "earth_stele", 3)
    await manager._trigger_summons(manager.player, "turn_end")
    check(manager.enemy.summons[0] == null and manager.enemy.hp == 80, "ember lizard aims at lowest-life enemy target")

    prepare()
    summon(manager.player, 0, "earth_stele", 6)
    summon(manager.enemy, 0, "earth_stele")
    var grow: Dictionary = manager.cards["earth_nourishing_soil"]
    check(manager.card_target_mode(grow) == "ally_summon" and not manager.valid_card_target(manager.player, grow, {"kind":"summon", "side":"enemy", "slot":0}), "growth spell targets allied summon only")
    before = manager.player.draw_pile.size()
    check(cast("earth_nourishing_soil", 1, {"kind":"summon", "side":"player", "slot":0}), "growth spell casts onto allied summon")
    check(manager.player.summons[0].max_hp == 20 and manager.player.summons[0].hp == 11 and manager.player.draw_pile.size() == before - 1, "growth adds five max and current health then draws")

    prepare()
    check(cast("earth_sand_rhino_card", 3, {"kind":"slot", "slot":0}), "sand rhino enters")
    manager.enemy.hp = 40
    summon(manager.enemy, 0, "earth_stele", 50)
    await manager._trigger_summons(manager.player)
    check(manager.enemy.hp == 40 and manager.enemy.summons[0].hp < 50, "sand rhino hits highest-life enemy target")
    manager.enemy.hp = 10
    manager.enemy.summons[0].hp = 10
    var hero_seen := false
    var summon_seen := false
    for i in 30:
        var chosen := manager.highest_life_target(manager.enemy)
        hero_seen = hero_seen or chosen.get("kind") == "hero"
        summon_seen = summon_seen or chosen.get("kind") == "summon"
    check(hero_seen and summon_seen, "tied highest-life targets are chosen randomly")

    print("New card wave: 10 cards, summon timing, conditional glow predicates, target modes and damage preview; %d failures" % failures)
    quit(1 if failures else 0)
