extends SceneTree

var ui: Control
var failures := 0
var assertions := 0
var output := "res://work/ash_cleanse_20261002"

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)

func creature(owner: Combatant, slot: int, id: String, hp: int = 100) -> void:
	var s := Summon.new(); s.setup(ui.manager.summon_templates[id]); s.hp = hp; s.max_hp = hp
	owner.summons[slot] = s

func clean(id: String) -> void:
	ui._clear_hover_preview(); ui._clear_drag_hints()
	for actor: Combatant in [ui.manager.player, ui.manager.enemy]:
		actor.max_hp = 200; actor.setup("player" if actor == ui.manager.player else "enemy", "测试", [], ui.manager.rng)
	ui.manager.phase = "player_action"; ui.action_busy = false
	ui.manager.player.hand.assign([id]); ui.manager.player.energy[ui.manager.cards[id]["element"]] = ui.manager.cards[id]["cost"]
	ui._set_touch_hand_collapsed(false)

func send_pointer(point: Vector2, kind: String) -> void:
	var screen: Vector2 = root.get_final_transform() * (ui.get_global_transform_with_canvas() * point)
	var event: InputEvent
	if PlatformUI.is_touch():
		if kind == "move":
			var drag := InputEventScreenDrag.new(); drag.position = screen; drag.index = 0; event = drag
		else:
			var touch := InputEventScreenTouch.new(); touch.position = screen; touch.index = 0; touch.pressed = kind == "press"; event = touch
	else:
		Input.warp_mouse(screen)
		# PC gameplay reads the viewport cursor; wait for the native warp to arrive.
		var deadline := Time.get_ticks_msec() + 500
		while ui.get_local_mouse_position().distance_to(point) > 2 and Time.get_ticks_msec() < deadline: await process_frame
		if kind == "move":
			var motion := InputEventMouseMotion.new(); motion.position = screen; motion.global_position = screen; motion.button_mask = MOUSE_BUTTON_MASK_LEFT; event = motion
		else:
			var button := InputEventMouseButton.new(); button.position = screen; button.global_position = screen; button.button_index = MOUSE_BUTTON_LEFT; button.pressed = kind == "press"; button.button_mask = MOUSE_BUTTON_MASK_LEFT if button.pressed else 0; event = button
	root.push_input(event); await process_frame

func begin_drag() -> void:
	var start: Vector2 = ui._hand_card_center(0, ui.manager.player.hand.size())
	await send_pointer(start, "press")
	await send_pointer(start + Vector2(0, -85), "move")
	check(ui.drag_index == 0, "real pointer starts card drag")

func wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 9000
	while ui.action_busy and Time.get_ticks_msec() < deadline: await process_frame
	check(not ui.action_busy, "card action completes within normal animation time")

func shot(name: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(("touch_" if PlatformUI.is_touch() else "pc_") + name + ".png")))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	ui = load("res://battle/battle_scene.tscn").instantiate(); ui.endless_save_path = "user://ash_cleanse_ui_test.json"
	root.add_child(ui); await process_frame
	clean("earth_quake_summons")
	creature(ui.manager.player, 0, "earth_stele"); creature(ui.manager.enemy, 1, "water_spring")
	ui._refresh(); await process_frame
	var card: Dictionary = ui.manager.cards["earth_quake_summons"]
	check(ui._drop_selection(card, ui._anchor("enemy")).get("kind") == "invalid" and ui._drop_selection(card, ui._anchor("player")).get("kind") == "invalid", "both hero regions reject summon-only area")
	await begin_drag()
	check(ui.drag_hints.size() == 2 and ui.drag_hints.all(func(hint): return hint.get_meta("selection")["kind"] == "summon"), "drag markers cover exactly both living summons")
	await send_pointer(ui._summon_point("player", 0), "move")
	check(ui.damage_preview.visible and ui.damage_preview_label.text.contains("15"), "allied target preview includes earth resistance")
	await shot("earth_preview")
	await send_pointer(ui._summon_point("player", 0), "release"); await wait_idle()
	check(ui.manager.player.summons[0].hp == 85 and ui.manager.enemy.summons[1].hp == 55 and ui.manager.player.hp == 200 and ui.manager.enemy.hp == 200 and ui.manager.player.energy["earth"] == 0, "real area drop hits both sides without hitting heroes")
	clean("earth_quake_summons"); creature(ui.manager.enemy, 0, "water_spring")
	ui._refresh(); await process_frame; await begin_drag()
	await send_pointer(ui._anchor("enemy"), "move"); await send_pointer(ui._anchor("enemy"), "release")
	check(ui.manager.player.hand == ["earth_quake_summons"] and ui.manager.player.energy["earth"] == 5 and not ui.action_busy, "invalid hero drop cancels without spending")
	clean("fire_burn_to_earth"); creature(ui.manager.enemy, 0, "earth_stele", 15)
	ui._refresh(); await process_frame; await begin_drag()
	await send_pointer(ui._summon_point("enemy", 0), "move")
	check(ui._drop_selection(ui.manager.cards["fire_burn_to_earth"], ui._summon_point("enemy", 0)).get("kind") == "summon", "fire drop point selects the live enemy summon")
	await shot("fire_preview")
	await send_pointer(ui._summon_point("enemy", 0), "release"); await wait_idle()
	check(ui.manager.enemy.summons[0] == null and ui.manager.player.energy["earth"] == 2, "real fire drop kills selected summon and rewards energy: hand=%s fire=%d earth=%d phase=%s hp=%d" % [ui.manager.player.hand, ui.manager.player.energy["fire"], ui.manager.player.energy["earth"], ui.manager.phase, ui.manager.enemy.summons[0].hp if ui.manager.enemy.summons[0] != null else 0])
	var surface := Control.new(); surface.theme = ui.theme; root.add_child(surface)
	var ids := ["metal_rupture", "water_clear_dew", "wood_miasma_bloom", "fire_burn_to_earth", "earth_quake_summons"]
	for level in 3:
		for child in surface.get_children(): child.free()
		for i in ids.size():
			var entry: Dictionary = ui.manager.cards[ContentCatalog.variant_id(ids[i], level)]
			var view: Control = ui._card_front(entry, Vector2(270, 378)); view.position = Vector2(30 + i * 310, 240); surface.add_child(view)
			var description: RichTextLabel = view.get_node("Description")
			check(description.get_content_height() <= description.size.y and description.get_content_width() <= description.size.x + 1, "new grade description fits: " + entry["name"])
			check(view.get_node("Cost").text == str(int(entry["cost"])), "new card displays actual grade cost")
		await shot("cards_grade_%d" % level)
	surface.queue_free(); ui.queue_free(); await process_frame
	print("Ash and cleanse UI (%s): %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "PC", assertions, failures])
	quit(1 if failures else 0)
