extends "res://tests/ash_cleanse_ui_test.gd"

const EXPANSION := ["metal_forge_edge", "water_breath_wisp_card", "wood_rain_slash", "fire_kindling", "earth_seek_treasure"]

func click_control(control: Control) -> void:
	var point: Vector2 = ui.get_global_transform_with_canvas().affine_inverse() * (control.get_global_transform_with_canvas() * (control.size / 2.0))
	await send_pointer(point, "press"); await send_pointer(point, "release")

func wait_choice() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while not is_instance_valid(ui.choice_dialog) and Time.get_ticks_msec() < deadline: await process_frame
	check(is_instance_valid(ui.choice_dialog), "choice dialog appears during cast")

func run() -> void:
	output = "res://work/discovery_20261003"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	ui = load("res://battle/battle_scene.tscn").instantiate(); ui.endless_save_path = "user://discovery_ui_test.json"
	root.add_child(ui); await process_frame
	clean("fire_kindling__1"); ui.manager.player.energy["wood"] = 3; ui._refresh(); await process_frame
	await begin_drag(); await send_pointer(ui._anchor("enemy"), "move")
	check(ui.damage_preview.visible and ui.damage_preview_label.text.contains("7"), "fractional energy damage previews seven")
	await send_pointer(ui._anchor("enemy"), "release"); await wait_idle()
	check(ui.manager.enemy.hp == 193 and ui.manager.player.energy["wood"] == 3, "real fire drop matches preview without consuming wood")
	clean("wood_rain_slash__1"); ui.manager.player.hp = 100; ui.manager.player.energy["water"] = 3; ui._refresh(); await process_frame
	check(ui.manager.card_condition_met(ui.manager.player, ui.manager.cards["wood_rain_slash__1"]), "wood healing condition is active")
	await begin_drag(); await send_pointer(ui._anchor("enemy"), "release"); await wait_idle()
	check(ui.manager.enemy.hp == 166 and ui.manager.player.hp == 118, "wood drag causes damage then conditional heal")
	clean("water_breath_wisp_card__2"); ui._refresh(); await process_frame; await begin_drag()
	await send_pointer(ui._summon_point("player", 0), "release"); await wait_idle()
	check(ui.manager.player.summons[0] != null and ui.manager.player.summons[0].hp == 28 and ui.manager.turn_start_qi_gain(ui.manager.enemy) == 0, "real water summon drop applies HP and aura")
	for level in 3:
		clean(ContentCatalog.variant_id("earth_seek_treasure", level)); ui._refresh(); await process_frame; await begin_drag()
		await send_pointer(Vector2(800, 450), "release"); await wait_choice()
		if not is_instance_valid(ui.choice_dialog): break
		check(ui.choice_dialog.frames.size() == level + 2 and ui.choice_dialog.confirm.disabled and ui.action_busy, "discovery blocks cast and requires selection")
		if ui.choice_dialog.frames.size() != level + 2: quit(1); return
		var candidates: Array = ui.manager.pending_choice["candidates"].duplicate()
		var dialog: ContemplationDialog = ui.choice_dialog
		var selected_card: Control = dialog.frames[level + 1].get_child(0)
		await click_control(selected_card)
		check(dialog.selected == level + 1 and not dialog.confirm.disabled, "real pointer selects discovered candidate")
		await shot("discover_%d" % (level + 2))
		await click_control(dialog.confirm); await wait_idle()
		check(ui.manager.player.hand == [candidates[level + 1]] and ui.manager.pending_choice.is_empty() and ui.choice_dialog == null, "confirmation creates only selected card and unblocks battle")
		if not ui.manager.pending_choice.is_empty(): quit(1); return
	# This shared presenter still treats contemplation as drawing from the pile.
	clean("water_thought__1"); ui.manager.player.draw_pile.assign(["earth_strike","metal_strike__2","water_strike__1","wood_strike"])
	ui._refresh(); await process_frame; await begin_drag(); await send_pointer(Vector2(800,450), "release"); await wait_choice()
	if is_instance_valid(ui.choice_dialog):
		var dialog: ContemplationDialog = ui.choice_dialog
		await click_control(dialog.frames[1].get_child(0)); await click_control(dialog.confirm); await wait_idle()
		check(ui.manager.player.hand == ["earth_strike","water_strike__1"] and ui.manager.player.draw_pile == ["metal_strike__2","wood_strike"], "contemplation retains physical grade and unselected pile order")
	var surface := Control.new(); surface.theme = ui.theme; root.add_child(surface)
	for level in 3:
		for child in surface.get_children(): child.free()
		for i in EXPANSION.size():
			var entry: Dictionary = ui.manager.cards[ContentCatalog.variant_id(EXPANSION[i], level)]
			var view: Control = ui._card_front(entry, Vector2(270,378)); view.position = Vector2(30+i*310,240); surface.add_child(view)
			await process_frame
			var text: RichTextLabel = view.get_node("Description")
			check(text.get_content_height() <= text.size.y and text.get_content_width() <= text.size.x+1, "grade description fits: " + entry["name"])
			check(view.art_texture != null and view.art_texture.resource_path.ends_with(entry["art_id"] + ".webp"), "new grade shares its own illustration: " + entry["name"])
		await shot("new_cards_grade_%d" % level)
	surface.queue_free(); ui.queue_free(); await process_frame
	print("Discovery UI (%s): %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "PC", assertions, failures]); quit(1 if failures else 0)
