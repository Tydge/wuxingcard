extends SceneTree

# Real UI playback and captures: work/summon_fx/.
var ui: Control
var manager: BattleManager
var failures := 0
var order: Array[int] = []
var last_trigger_ms := 0
var capture_group := ""
var output := ""

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
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	ui.call("_start_battle")
	await create_timer(5.8).timeout
	manager = ui.get("manager")
	manager.summon_triggered.connect(on_trigger)
	output = ProjectSettings.globalize_path("res://work/summon_fx")
	DirAccess.make_dir_recursive_absolute(output)
	for side in ["player", "enemy"]:
		var actor := manager.player if side == "player" else manager.enemy
		var opponent := manager.enemy if side == "player" else manager.player
		for timing in ["turn_start", "turn_end"]:
			order.clear()
			last_trigger_ms = 0
			capture_group = side + "_" + timing
			actor.statuses.clear()
			actor.hand.resize(4)
			actor.hp = 70
			opponent.hp = 100
			opponent.statuses.clear()
			for element in BattleRules.ELEMENTS:
				actor.energy[element] = 1
				opponent.energy[element] = 0
			populate(actor, ["metal_furnace", "water_conch", "metal_chime"] if timing == "turn_start" else ["fire_raven", "wood_deer", "earth_tortoise"])
			manager.phase = side + "_" + timing
			ui.call("_refresh")
			var persistent_view: SummonView = ui.get("summon_views")[side + "_0"]
			await manager._trigger_summons(actor, timing)
			check(order == [0, 1, 2], "UI trigger order should be top, middle, bottom")
			check(ui.get("summon_views")[side + "_0"] == persistent_view, "trigger refresh keeps the original summon node")
			if timing == "turn_start":
				check(int(actor.energy["water"]) == 2 and actor.hand.size() == 5 and actor.status_stacks("charge") == 1, "animated start effects settled")
			else:
				check(opponent.hp == 96 and actor.hp == 73 and actor.status_stacks("tenacity") == 1, "animated end effects settled")
	# Exercise the actual end-turn button flow through the enemy's entire turn.
	manager.summon_triggered.disconnect(on_trigger)
	var turn_order: Array[String] = []
	manager.summon_triggered.connect(func(side: String, slot: int, timing: String, _effect: Dictionary): turn_order.append("%s:%d:%s" % [side, slot, timing]))
	manager.player.summons = [null, null, null]
	manager.enemy.summons = [null, null, null]
	populate(manager.player, ["metal_furnace"])
	populate(manager.enemy, ["metal_chime"])
	manager.player.summons[2] = Summon.new()
	manager.player.summons[2].setup(manager.summon_templates["earth_tortoise"])
	manager.enemy.summons[2] = Summon.new()
	manager.enemy.summons[2].setup(manager.summon_templates["fire_raven"])
	manager.enemy.hand.clear()
	manager.enemy.draw_pile = ["fire_strike"]
	for element in BattleRules.ELEMENTS:
		manager.enemy.add_status("lock", 1, 0, element)
	manager.phase = "player_action"
	ui.call("_refresh")
	var before_round := manager.round_number
	await ui.call("_on_end_turn")
	var deadline := Time.get_ticks_msec() + 15000
	while ui.get("enemy_animating") and Time.get_ticks_msec() < deadline:
		await process_frame
	check(turn_order == ["player:2:turn_end", "enemy:0:turn_start", "enemy:2:turn_end", "player:0:turn_start"], "end-turn UI completes both sides' trigger phases in order")
	check(manager.phase == "player_action" and manager.round_number == before_round + 1 and not ui.get("action_busy") and not ui.get("enemy_animating"), "control returns to the player after all animations")
	# Let the final natural draw finish before closing its scene and coroutine.
	while ui.get("draw_animation_active") and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not ui.get("draw_animation_active"), "final natural draw completes")
	print("Summon FX UI test: energy, draw, buff, damage and healing on both sides; %d failures" % failures)
	quit(1 if failures > 0 else 0)

func on_trigger(side: String, slot: int, _timing: String, effect: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if last_trigger_ms > 0:
		check(now - last_trigger_ms >= 1500, "next summon waits for the previous feedback")
	last_trigger_ms = now
	order.append(slot)
	var group := capture_group
	await create_timer(0.24).timeout
	var source: Vector2 = ui.call("_summon_point", side, slot) + Vector2(0, -14)
	var fx: BattleFX = ui.get("battle_fx")
	var matching_cast := false
	for active in fx.active:
		if active["kind"] == "cast" and active["from"].distance_to(source) < 1.0:
			matching_cast = true
			var expected_side := side if effect.get("target", "self") == "self" else ("enemy" if side == "player" else "player")
			var expected: Vector2 = ui.call("_anchor", expected_side)
			if effect["type"] == "gain_energy":
				expected = ui.call("_energy_point", expected_side, effect["element"])
			elif effect["type"] == "draw":
				expected = ui.call("_draw_pile_point", expected_side)
			check(active["to"].distance_to(expected) < 1.0, "summon effect travels to the actual target")
	check(matching_cast, "summon cast must start from its field portrait")
	var view: SummonView = ui.get("summon_views")["%s_%d" % [side, slot]]
	check(view.scale.x > 1.02, "triggering summon visibly pulses")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("%s_%d.png" % [group, slot]))
