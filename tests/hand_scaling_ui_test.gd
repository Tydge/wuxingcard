extends "res://tests/ash_cleanse_ui_test.gd"

func run() -> void:
	output = "res://work/hand_scaling_20261003"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	ui = load("res://battle/battle_scene.tscn").instantiate(); ui.endless_save_path = "user://hand_scaling_ui_test.json"
	root.add_child(ui);await process_frame
	clean("water_gather_tide__2");ui.manager.player.hand.append("water_strike__1")
	ui._refresh();await process_frame;await begin_drag()
	await send_pointer(ui._anchor("enemy"), "move")
	check(ui.damage_preview.visible and ui.damage_preview_label.text.contains("16"), "real water drag previews remaining water hand")
	await shot("water_preview")
	await send_pointer(ui._anchor("enemy"), "release");await wait_idle()
	check(ui.manager.enemy.hp == 184 and ui.manager.player.hand == ["water_strike__1"], "real water drop matches sixteen-point preview")
	clean("fire_poison_flame__2");ui.manager.enemy.add_status("poison",19,0);ui._refresh();await process_frame;await begin_drag()
	await send_pointer(ui._anchor("enemy"), "release");await wait_idle()
	check(ui.manager.enemy.status_stacks("burn") == 4 and ui.manager.enemy.status_stacks("poison") == 19, "real fire drop converts wood poison to burn without consumption")
	var surface := Control.new();surface.theme = ui.theme;root.add_child(surface)
	var ids := ["metal_cleanse","water_gather_tide","wood_miasma_rain","fire_poison_flame","earth_heavy_peak"]
	for level in 3:
		for child in surface.get_children():child.free()
		for i in ids.size():
			var entry: Dictionary = ui.manager.cards[ContentCatalog.variant_id(ids[i],level)]
			var view: Control = ui._card_front(entry,Vector2(270,378));view.position=Vector2(30+i*310,240);surface.add_child(view)
			await process_frame
			var description: RichTextLabel = view.get_node("Description")
			check(description.get_content_height() <= description.size.y and description.get_content_width() <= description.size.x+1, "grade formula fits card: "+entry["name"])
			check(view.get_node("Cost").text == str(int(entry["cost"])),"card face grade cost: "+entry["name"])
		await shot("cards_grade_%d" % level)
	surface.queue_free()
	# Mount the same warehouse workshop used by the endless inventory.
	var progress := EndlessRun.new(ui.manager.cards,ui.manager.artifacts,ui.manager.enemies,"user://hand_scaling_warehouse_test.json")
	progress.new_run(901);progress.state["phase"]="rest";progress.state["deck"].clear()
	for i in ids.size():
		var id := ContentCatalog.variant_id(ids[i],i%3)
		var uid := progress._own("cards",id);progress.state["deck"].append(uid)
	var workshop := EndlessWorkshop.new();workshop.configure_run(progress,ui._card_front,ui.manager.summon_templates);root.add_child(workshop);await process_frame
	for id: String in progress.deck_ids():
		var row: DeckRow = workshop.row_nodes[id]
		check(row.art != null and row.art.resource_path.ends_with(ContentCatalog.base_id(row.card)+".webp"),"warehouse row uses shared original illustration: "+id)
		check(row.card["id"]==id and row.title.text==row.card["name"],"warehouse retains grade identity and title: "+id)
	await shot("warehouse_graded_rows")
	workshop.queue_free();ui.queue_free();await process_frame
	DirAccess.remove_absolute(progress.path)
	print("Hand scaling UI (%s): %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "PC",assertions,failures]);quit(1 if failures else 0)
