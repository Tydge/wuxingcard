extends SceneTree

var ui: Control
var manager: BattleManager
var failures := 0
var output := ""
var cast_checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func populate(owner: Combatant, ids: Array) -> void:
	owner.summons = [null, null, null]
	for slot in ids.size():
		owner.summons[slot] = Summon.new()
		owner.summons[slot].setup(manager.summon_templates[ids[slot]])

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	ui.call("_start_battle")
	await create_timer(5.8).timeout
	manager = ui.get("manager")
	output = ProjectSettings.globalize_path("res://work/summon_expansion_ui")
	DirAccess.make_dir_recursive_absolute(output)
	for owner in [manager.player, manager.enemy]:
		owner.statuses.clear()
		owner.hp = 70
		for element in BattleRules.ELEMENTS: owner.energy[element] = 0
	populate(manager.player, ["metal_falcon", "water_koi", "wood_frog"])
	populate(manager.enemy, ["fire_fox", "earth_badger", "metal_falcon"])
	manager.player.hand = ["metal_falcon_card", "wood_frog_card", "fire_all_targets", "metal_twin_blades"]
	manager.phase = "player_action"
	ui.call("_refresh")
	await create_timer(0.2).timeout
	await shot("five_creatures")
	var views: Dictionary = ui.get("summon_views")
	for key in views:
		var view: SummonView = views[key]
		check(view.portrait.flip_h == str(key).begins_with("enemy"), "only enemy artwork is horizontally mirrored")
		check(view.hp_label.get_parent().position == Vector2(57, 160) and view.scale == Vector2.ONE, "size config preserves HP badge and target root")
		check(absf(view.portrait.scale.x / view.summon_ref.art_scale - 1.0) < 0.026, "breathing preserves creature-specific scale")
	var frog: SummonView = views["player_2"]
	var before_y := frog.portrait.position.y
	await create_timer(0.8).timeout
	check(absf(frog.portrait.position.y - before_y) > 0.2 and frog.portrait.scale.x < 0.85, "small creature floats without returning to default size")
	ui.call("_on_summon_hover", "player", 1)
	await create_timer(0.8).timeout
	check(ui.get("hover_preview") is SummonCardView, "field koi hover opens its corresponding summon card")
	await shot("koi_hover")
	ui.call("_clear_hover_preview")
	for index in [2, 3]:
		ui.call("_show_hover_preview", index)
		await create_timer(0.2).timeout
		await shot("samadhi_fire" if index == 2 else "twin_blades")
		ui.call("_clear_hover_preview")
	manager.summon_triggered.connect(check_cast)
	manager.phase = "player_turn_start"
	await manager._trigger_summons(manager.player, "turn_start")
	check(manager.enemy.summons[0].hp == 6 and manager.player.hp == 73 and manager.enemy.hp == 67, "animated falcon and koi effects settle correctly")
	populate(manager.player, ["wood_frog", "fire_fox", "earth_badger"])
	manager.phase = "player_turn_end"
	ui.call("_refresh")
	await manager._end_turn(manager.player)
	check(manager.enemy.status_stacks("poison") == 2 and manager.enemy.status_stacks("burn") == 1 and manager.player.status_stacks("shield") == 5, "all new end-turn effects animate and grant their statuses")
	manager.phase = "enemy_turn_start"
	await manager._trigger_summons(manager.enemy, "turn_start")
	check(manager.player.summons[0] == null and manager.player.hp == 73, "enemy falcon hits the lowest creature, with metal-over-wood weakness")
	check(cast_checks == 7, "all seven new trigger effects have checked animation destinations")
	await create_timer(0.8).timeout
	await shot("end_effects")
	# Finish scene-bound animation and capture callbacks before engine shutdown.
	manager.summon_triggered.disconnect(check_cast)
	manager.summon_presenter = Callable()
	current_scene.queue_free()
	ui = null
	manager = null
	await process_frame
	await process_frame
	print("Expanded summon UI: distinct art, mirror, stable scaling, hover and real cast targets; %d failures" % failures)
	quit(1 if failures > 0 else 0)

func check_cast(side: String, slot: int, _timing: String, effect: Dictionary) -> void:
	await create_timer(0.24).timeout
	var source: Vector2 = ui.call("_summon_point", side, slot) + Vector2(0, -14)
	var target_side := side if effect.get("target", "self") == "self" else ("enemy" if side == "player" else "player")
	var destination: Vector2 = ui.call("_anchor", target_side)
	var selection: Dictionary = effect.get("selection", {})
	if selection.get("kind", "") == "summon":
		destination = ui.call("_summon_point", selection["side"], selection["slot"])
	var fx: BattleFX = ui.get("battle_fx")
	var found := false
	for active in fx.active:
		if active["kind"] == "cast" and active["from"].distance_to(source) < 1.0:
			found = true
			check(active["to"].distance_to(destination) < 1.0, "spell FX travels to the selected hero or creature")
	check(found, "trigger produces visible cast FX")
	cast_checks += 1
	await shot("cast_%s_%d_%s" % [side, slot, effect["type"]])
