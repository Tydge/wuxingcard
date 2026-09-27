extends SceneTree

var ui: Control
var menu: MainMenu
var workshop: DeckWorkshop
var manager: BattleManager
var failures := 0
var output := ""
var save_path := "res://work/workshop_test_decks.json"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func screen_point(control: Control, local: Vector2) -> Vector2:
	# Input coordinates are window pixels; the designed canvas is 1600x900.
	return root.get_final_transform() * (control.get_global_transform_with_canvas() * local)

func move_mouse(point: Vector2, relative: Vector2, held: bool) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event)

func mouse_button(point: Vector2, held: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = which
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if held else 0
	event.pressed = held
	root.push_input(event)

func drag(source: Control, to: Vector2, valid: bool) -> void:
	var from := screen_point(source, Vector2(70, 70))
	move_mouse(from, Vector2.ZERO, false)
	await process_frame
	mouse_button(from, true)
	await process_frame
	move_mouse(from + Vector2(28, 0), Vector2(28, 0), true)
	await process_frame
	check(root.gui_is_dragging(), "pointer movement starts native card drag")
	move_mouse(to, to - from, true)
	await process_frame
	await process_frame
	if valid: check(workshop.drop_zone.hovered, "valid drop highlights the deck parchment")
	mouse_button(to, false)
	await create_timer(0.4).timeout
	check(not root.gui_is_dragging() and not is_instance_valid(menu.inspector), "ending a drag does not accidentally open the inspector")

func find_menu() -> MainMenu:
	for child in ui.get_children():
		if child is MainMenu: return child
	return null

func run() -> void:
	output = ProjectSettings.globalize_path("res://work/deck_previews")
	DirAccess.make_dir_recursive_absolute(output)
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	manager = ui.get("manager")
	menu = find_menu()
	menu.deck_store_path = save_path
	menu.mode_buttons["test"].pressed.emit()
	workshop = menu.workshop
	await create_timer(0.35).timeout
	check(workshop.view_mode == "library" and manager.phase == "menu", "test entry opens the deck library without starting combat")
	await shot("deck_library_random")
	workshop.new_button.pressed.emit()
	await create_timer(0.35).timeout
	check(workshop.view_mode == "editor" and workshop.card_nodes.size() == 12 and workshop.play_button.disabled, "new deck opens filtered collection and cannot play empty")
	await shot("deck_editor_empty")
	var card := workshop.card_nodes[0]
	var id: String = card.card["id"]
	var target := screen_point(workshop.drop_zone, Vector2(120, 35))
	await drag(card, target, true)
	check(workshop.draft.count(id) == 1 and workshop.row_nodes.size() == 1, "native drag adds the first card")
	await drag(card, target, true)
	check(workshop.draft.count(id) == 2 and workshop.row_nodes.size() == 1 and workshop.row_nodes[id].count_label.text == "2", "dropping onto an existing row merges its copies")
	await drag(workshop.card_nodes[1], Vector2(575, 60), false)
	check(workshop.draft.size() == 2, "dropping outside the deck leaves it unchanged")
	workshop.call("_add_card", id)
	workshop.call("_add_card", id)
	check(workshop.draft.count(id) == 2 and card.plus.disabled, "third identical copy is refused")
	# Container sorting runs at the end of the frame; target the rendered row.
	await process_frame
	await process_frame
	var row_point := screen_point(workshop.row_nodes[id], Vector2(150, 21))
	move_mouse(row_point, Vector2.ZERO, false)
	await process_frame
	mouse_button(row_point, true)
	await process_frame
	mouse_button(row_point, false)
	await process_frame
	check(workshop.draft.count(id) == 1, "clicking a deck row removes exactly one copy")
	await process_frame
	await process_frame
	mouse_button(row_point, true, MOUSE_BUTTON_RIGHT)
	await process_frame
	check(is_instance_valid(menu.inspector), "right-clicking a deck row opens inspection")
	mouse_button(row_point, false, MOUSE_BUTTON_RIGHT)
	menu.call("_close_inspector")
	await create_timer(0.4).timeout
	workshop.name_edit.text = "五行初卷"
	workshop.name_edit.text_changed.emit("五行初卷")
	workshop.save_button.pressed.emit()
	check(workshop.view_mode == "library" and workshop.store.decks.size() == 1 and workshop.play_button.disabled, "small draft is saved in the library and cannot enter combat")
	await create_timer(0.3).timeout
	await shot("deck_library_draft")
	var saved_id: String = workshop.selected_id
	workshop.deck_buttons[saved_id].pressed.emit()
	check(workshop.view_mode == "editor" and workshop.draft.size() == 1, "saved deck click reopens its editor")
	workshop.filter_buttons["wood"].pressed.emit()
	check(workshop.filtered_cards.size() == 9 and workshop.draft.size() == 1, "element filtering preserves the current deck")
	for candidate in workshop.card_nodes:
		if candidate.card["id"] == "wood_regen": card = candidate
	var point := screen_point(card, Vector2(70, 70))
	move_mouse(point, Vector2.ZERO, false)
	mouse_button(point, true)
	await process_frame
	mouse_button(point, false)
	await process_frame
	check(is_instance_valid(menu.inspector) and menu.inspect_card.scale.x < 1.0, "editor click opens progressive shared inspection")
	check(is_instance_valid(menu.inspect_keywords) and menu.inspect_keywords.modulate.a == 0, "editor inspection delays keyword explanations")
	await create_timer(0.7).timeout
	await shot("deck_card_inspection")
	menu.call("_close_inspector")
	await create_timer(0.4).timeout
	workshop.filter_buttons["all"].pressed.emit()
	workshop.call("_add_card", "earth_stele_card")
	var summon_row: DeckRow = workshop.row_nodes["earth_stele_card"]
	check(summon_row.get_child_count() == 4 and summon_row.inspect_anchor.get_child_count() == 0, "summon deck row contains only cost, name, count and invisible inspection origin without thumbnail or health jewel")
	# Populate through the same add handler used by the drop target and plus button.
	for card_id in manager.cards:
		for copy in DeckStore.MAX_COPIES:
			if workshop.draft.size() < 20 and workshop.draft.count(card_id) < DeckStore.MAX_COPIES: workshop.call("_add_card", card_id)
	check(not workshop.play_button.disabled and workshop.draft.size() == 20, "twenty-card draft becomes playable")
	await create_timer(0.35).timeout
	await shot("deck_editor_complete")
	var old_card: Control = workshop.card_nodes[0]
	var old_x := old_card.position.x
	workshop.call("_change_page", 1)
	workshop.call("_change_page", 1)
	var leaving := workshop.page_turn_tween
	leaving.pause()
	leaving.custom_step(CardPageMotion.LEAVE_SECONDS * 0.5)
	check(workshop.page == 0 and old_card.position.x < old_x and old_card.modulate.a > 0 and old_card.modulate.a < 1, "editor old page slides out and repeated paging is guarded")
	await shot("deck_page_departing")
	leaving.custom_step(CardPageMotion.LEAVE_SECONDS)
	check(workshop.page == 1 and workshop.card_nodes[0].modulate.a == 0 and workshop.card_nodes[0].position.x > old_x and workshop.draft.size() == 20, "editor new page begins offset and transparent without changing the deck")
	await create_timer(0.12).timeout
	await shot("deck_page_arriving")
	await create_timer(0.4).timeout
	workshop.call("_change_page", -1)
	await create_timer(0.6).timeout
	check(workshop.page == 0 and not workshop.page_turn_busy, "editor reverse page turn restores the first page")
	workshop.call("_change_page", 1)
	workshop.filter_buttons["water"].pressed.emit()
	await create_timer(0.6).timeout
	check(workshop.page == 0 and workshop.selected_element == "water" and workshop.draft.size() == 20, "editor filtering cancels the old page transition safely")
	workshop.filter_buttons["all"].pressed.emit()
	var before := workshop.draft.duplicate()
	workshop.call("_leave_editor")
	check(is_instance_valid(workshop.modal), "leaving modified deck offers save or discard")
	workshop.call("_dismiss_modal")
	workshop.save_button.pressed.emit()
	check(workshop.store.decks.size() == 1 and not workshop.play_button.disabled, "saving edits replaces the draft rather than adding another deck")
	await create_timer(0.3).timeout
	await shot("deck_library_saved")
	# Recreate the whole menu to verify real local persistence, not just cached data.
	menu.call("_show_home")
	menu.mode_buttons["test"].pressed.emit()
	workshop = menu.workshop
	check(workshop.store.find_deck(saved_id)["cards"] == before, "reopening the library restores the saved deck")
	workshop.deck_buttons[saved_id].pressed.emit()
	for card_id in manager.cards:
		for copy in DeckStore.MAX_COPIES:
			if workshop.draft.size() < 30 and workshop.draft.count(card_id) < DeckStore.MAX_COPIES: workshop.call("_add_card", card_id)
	workshop.call("_add_card", "metal_twin_blades")
	check(workshop.draft.size() == 30, "thirty-card maximum blocks another addition")
	await process_frame
	workshop.row_scroll.scroll_vertical = 1000
	await process_frame
	await shot("deck_editor_scrolled")
	var old_scroll := workshop.row_scroll.scroll_vertical
	workshop.call("_change_page", 1)
	await create_timer(0.6).timeout
	check(workshop.row_scroll.scroll_vertical == old_scroll and workshop.draft.size() == 30, "flipping the collection keeps the deck list scroll and contents")
	var final_cards := workshop.draft.duplicate()
	workshop.play_button.pressed.emit()
	await create_timer(5.8).timeout
	check(find_menu() == null and manager.phase == "player_action", "saved deck enters the existing playable battle")
	var chosen: Array = manager.player.hand + manager.player.draw_pile
	chosen.sort()
	final_cards.sort()
	check(chosen == final_cards and manager.player.max_hp == 80 and manager.enemy.max_hp == 80, "battle uses exact saved cards and eighty HP")
	check(manager.valid_random_deck(manager.enemy.hand + manager.enemy.draw_pile), "enemy remains an independent random twenty-five-card deck")
	await shot("custom_deck_battle")
	manager.phase = "menu"
	ui.call("_refresh")
	await process_frame
	menu = find_menu()
	menu.deck_store_path = save_path
	menu.mode_buttons["test"].pressed.emit()
	workshop = menu.workshop
	workshop.selected_id = saved_id
	workshop.call("_show_library")
	workshop.call("_ask_delete", workshop.store.find_deck(saved_id))
	check(is_instance_valid(workshop.modal), "deck deletion asks before removing the saved deck")
	workshop.call("_dismiss_modal")
	check(workshop.store.decks.size() == 1, "cancelled deletion keeps the deck")
	DirAccess.remove_absolute(save_path)
	print("Deck workshop UI: real drag/drop, duplicate rows, limits, drafts, filters, inspection, persistence and custom battle; %d failures" % failures)
	quit(1 if failures > 0 else 0)
