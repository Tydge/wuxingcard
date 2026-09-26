extends SceneTree

var manager: BattleManager
var failures := 0
var timeline: Array[String] = []
var presenting := false
var restart_on_cast := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func populate(actor: Combatant, ids: Array) -> void:
	for slot in ids.size():
		actor.summons[slot] = Summon.new()
		actor.summons[slot].setup(manager.summon_templates[ids[slot]])

func run() -> void:
	manager = BattleManager.new()
	root.add_child(manager)
	manager.start_battle("ember", "balanced", 12345)
	manager.summon_presenter = present
	populate(manager.player, ["metal_furnace", "water_conch", "metal_chime"])
	var before_hand := manager.player.hand.size()
	var before_water := int(manager.player.energy["water"])
	await manager._start_turn(manager.player)
	check(timeline == ["player:0:cast", "player:0:resolved", "player:1:cast", "player:1:resolved", "player:2:cast", "player:2:resolved"], "start effects present top to bottom")
	check(manager.phase == "player_action" and manager.player.hand.size() == before_hand + 2, "start triggers complete before action phase and natural draw")
	check(int(manager.player.energy["water"]) >= before_water + 1 and manager.player.status_stacks("charge") == 1, "start effects resolve resources and buff")

	timeline.clear()
	populate(manager.player, ["fire_raven", "wood_deer", "earth_tortoise"])
	manager.player.hp = 70
	manager.enemy.energy["fire"] = 0
	manager.enemy.energy["metal"] = 0
	manager.phase = "player_turn_end"
	await manager._end_turn(manager.player)
	check(timeline == ["player:0:cast", "player:0:resolved", "player:1:cast", "player:1:resolved", "player:2:cast", "player:2:resolved"], "end effects present top to bottom")
	check(manager.enemy.hp == 96 and manager.player.hp == 73 and manager.player.status_stacks("tenacity") == 1, "end triggers preserve their new buff")

	timeline.clear()
	populate(manager.enemy, ["metal_furnace", "water_conch", "metal_chime"])
	await manager._start_turn(manager.enemy)
	check(timeline == ["enemy:0:cast", "enemy:0:resolved", "enemy:1:cast", "enemy:1:resolved", "enemy:2:cast", "enemy:2:resolved"], "enemy uses the same top-to-bottom order")
	check(manager.phase == "enemy_action", "enemy cannot act before its triggers settle")

	timeline.clear()
	populate(manager.player, ["fire_raven", "fire_raven", "fire_raven"])
	manager.enemy.hp = 1
	manager.phase = "player_turn_end"
	await manager._end_turn(manager.player)
	check(manager.phase == "victory" and timeline == ["player:0:cast", "player:0:resolved"], "lethal trigger stops all later summons")

	manager.start_battle("ember", "balanced", 23456)
	populate(manager.player, ["fire_raven", "wood_deer", "earth_tortoise"])
	restart_on_cast = true
	manager.phase = "player_turn_end"
	await manager._end_turn(manager.player)
	check(manager.phase == "player_action" and manager.enemy.hp == 100 and manager.player.summons[0] == null, "restarting cancels the old pending effect and turn flow")
	print("Summon presentation test: ordered triggers, deferred effects, victory and restart; %d failures" % failures)
	quit(1 if failures > 0 else 0)

func state(side: String, effect: Dictionary) -> int:
	var actor := manager.player if side == "player" else manager.enemy
	var opponent := manager.enemy if side == "player" else manager.player
	var target := actor if effect.get("target", "self") == "self" else opponent
	match effect["type"]:
		"damage", "heal": return target.hp
		"gain_energy": return int(target.energy[effect["element"]])
		"draw": return target.draw_pile.size()
		"status": return target.status_stacks(effect["status"])
	return 0

func present(side: String, slot: int, _summoned: Summon, effect: Dictionary, stage: String) -> void:
	check(not presenting, "summon animations must not overlap")
	presenting = true
	timeline.append("%s:%d:%s" % [side, slot, stage])
	var before := state(side, effect)
	check(manager.phase not in ["player_action", "enemy_action"], "turn must wait for its trigger animation")
	await create_timer(0.01).timeout
	if restart_on_cast and stage == "cast":
		restart_on_cast = false
		presenting = false
		await manager.start_battle("ember", "balanced", 34567)
		return
	check(state(side, effect) == before, "effect does not change state midway through its presentation")
	presenting = false
