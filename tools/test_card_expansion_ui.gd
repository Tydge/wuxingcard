extends SceneTree

var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	output = ProjectSettings.globalize_path("res://work/card_expansion_previews")
	DirAccess.make_dir_recursive_absolute(output)
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	ui.call("_start_test_battle")
	await create_timer(5.8).timeout
	var manager: BattleManager = ui.get("manager")
	check(manager.player.hp == 80 and manager.enemy.hp == 80 and manager.player.max_hp == 80 and manager.enemy.max_hp == 80, "test mode opens at eighty HP on both sides")
	for actor in [manager.player, manager.enemy]:
		actor.statuses.clear()
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	for slot in 3:
		manager.enemy.summons[slot] = Summon.new()
		manager.enemy.summons[slot].setup(manager.summon_templates[["metal_furnace", "fire_lantern", "water_spring"][slot]])
	manager.player.hand = ["fire_burning_field", "fire_scorch", "earth_stone_guard"]
	manager.player.energy["fire"] = 3
	ui.call("_refresh")
	ui.call("_show_hover_preview", 1)
	await create_timer(0.7).timeout
	check(is_instance_valid(ui.get("hover_keywords")) and ui.get("hover_keywords").explanations[0]["title"] == "灼伤 X", "new composite spell gets its burn explanation")
	await shot("scorch_keywords")
	ui.call("_clear_hover_preview")
	var card: Dictionary = manager.cards["fire_burning_field"]
	var destination: Vector2 = ui.call("_summon_point", "enemy", 1)
	var cards: Array = ui.get("hand_cards")
	var window_scale := Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	Input.warp_mouse((cards[0].position + Vector2(75, 80)) * window_scale)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	ui.call("_on_hand_input", press, 0)
	Input.warp_mouse(destination * window_scale)
	await process_frame
	ui.call("_input", InputEventMouseMotion.new())
	var hints: Array = ui.get("drag_hints")
	check(hints.size() == 4, "area spell displays four target reticles")
	for hint in hints: check(hint.highlighted, "all affected targets highlight")
	check(ui.get("damage_preview_label").text == "预计伤害 10", "pointed fire summon preview accounts for resistance")
	await shot("area_aim")
	# Verify the same presentation helper used by a real drag flies to all targets.
	var fx: BattleFX = ui.get("battle_fx")
	fx.clear_effects()
	ui.call("_cast_card", card, "player", destination)
	check(fx.active.size() == 4, "area spell casts to every occupied opponent target")
	var destinations: Array[Vector2] = []
	for effect in fx.active: destinations.append(effect["to"])
	check(destinations.has(ui.call("_anchor", "enemy")), "area spell includes enemy character FX")
	for slot in 3: check(destinations.has(ui.call("_summon_point", "enemy", slot)), "area spell includes summon FX")
	fx.clear_effects()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	ui.call("_input", release)
	await create_timer(3.9).timeout
	check(manager.enemy.hp == 60 and manager.enemy.summons[0] == null and manager.enemy.summons[1].hp == 5 and manager.enemy.summons[2] == null, "dragging area spell resolves all four targets")
	check(manager.player.hand.size() == 2 and manager.player.energy["fire"] == 0, "area spell consumes one card and three energy")
	await shot("area_result")
	print("Card expansion UI: 80 HP, composite keywords, all-target reticles, resistance preview and four-target FX; %d failures" % failures)
	quit(1 if failures > 0 else 0)
