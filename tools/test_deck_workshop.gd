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
	await process_frame
	RenderingServer.force_draw(false)
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

func showcase_button(caption: String) -> Button:
	for child in workshop.showcase.get_children():
		if child is Button and child.text == caption: return child
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
	var ordered := ["metal", "water", "wood", "fire", "earth"]
	for index in range(1, ordered.size()):
		check(workshop.filter_buttons[ordered[index]].position.y > workshop.filter_buttons[ordered[index - 1]].position.y, "deck editor filters follow the generating cycle")
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
	check(workshop.view_mode == "artifacts" and workshop.store.decks.size() == 1 and not workshop.store.problem(workshop.draft).is_empty(), "saving a small draft opens artifact setup and still rejects combat")
	workshop.call("_save_artifacts")
	check(workshop.view_mode == "library" and workshop.play_button.disabled, "returning from artifact setup preserves the incomplete draft")
	await create_timer(0.3).timeout
	await shot("deck_library_draft")
	var saved_id: String = workshop.selected_id
	workshop.random_button.pressed.emit()
	var library_content := workshop.content
	var saved_button: Button = workshop.deck_buttons[saved_id]
	var random_showcase := workshop.showcase
	workshop.deck_buttons[saved_id].pressed.emit()
	check(workshop.view_mode == "library" and workshop.selected_id == saved_id and workshop.play_button.disabled, "saved draft selection stays in the library and updates its playable state")
	check(workshop.content == library_content and workshop.deck_buttons[saved_id] == saved_button and workshop.showcase != random_showcase, "selecting a deck replaces only the right showcase and preserves the list")
	check(showcase_button("删除").position.x > showcase_button("法宝").get_rect().end.x, "delete action sits to the right of artifacts")
	showcase_button("编修").pressed.emit()
	check(workshop.view_mode == "editor" and workshop.draft.size() == 1, "explicit edit action opens the selected deck")
	workshop.filter_buttons["wood"].pressed.emit()
	var wood_cards := ContentCatalog.base_entries(manager.cards).filter(func(entry): return entry["element"] == "wood")
	check(workshop.filtered_cards.size() == wood_cards.size() and workshop.filtered_cards.all(func(entry): return entry["element"] == "wood") and workshop.draft.size() == 1, "element filtering includes the current base card pool and preserves the deck")
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
	while not workshop.page_motion.is_prepared(1): await process_frame
	var original_content := workshop.content
	var original_scroll := workshop.row_scroll
	var original_row: DeckRow = workshop.row_nodes["earth_stele_card"]
	var outgoing: Control = workshop.page_motion.page_roots[0]
	var incoming: Control = workshop.page_motion.page_roots[1]
	var cached_card: Control = workshop.page_motion.page_views[1][0]
	workshop.call("_change_page", 1)
	workshop.call("_change_page", 1)
	var transition := workshop.page_turn_tween
	transition.pause()
	transition.custom_step(CardPageMotion.TURN_SECONDS * 0.5)
	check(workshop.page == 1 and outgoing.position.x < 0 and incoming.position.x > 0 and outgoing.modulate.a > 0 and incoming.modulate.a > 0, "editor pages cross together without blank frames or skipped pages")
	check(workshop.content == original_content and workshop.row_scroll == original_scroll and workshop.row_nodes["earth_stele_card"] == original_row and workshop.card_nodes[0] == cached_card, "editor turn retains prepared cards and the actual deck list nodes")
	await shot("deck_page_overlap")
	transition.custom_step(CardPageMotion.TURN_SECONDS)
	check(not outgoing.visible and incoming.visible and incoming.position.is_zero_approx() and incoming.modulate.a == 1 and not workshop.page_turn_busy and workshop.draft.size() == 20, "editor turn settles without an extra waiting phase")
	await process_frame
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
	check(workshop.store.decks.size() == 1 and workshop.view_mode == "artifacts", "saving edits replaces the draft and opens artifact setup")
	workshop.call("_save_artifacts")
	check(workshop.view_mode == "library" and not workshop.play_button.disabled, "completed saved deck is playable from the library")
	await create_timer(0.3).timeout
	await shot("deck_library_saved")
	# Recreate the whole menu to verify real local persistence, not just cached data.
	menu.call("_show_home")
	menu.mode_buttons["test"].pressed.emit()
	workshop = menu.workshop
	check(workshop.store.find_deck(saved_id)["cards"] == before, "reopening the library restores the saved deck")
	workshop.deck_buttons[saved_id].pressed.emit()
	showcase_button("编修").pressed.emit()
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
	check(workshop.view_mode == "artifacts", "Enter Battle opens the saved loadout before combat")
	workshop.call("_enter_with_artifacts")
	while ui.opening_active: await process_frame
	check(find_menu() == null and manager.phase == manager.first_side + "_action", "saved deck enters the existing playable battle")
	var chosen: Array = manager.player.initial_deck.duplicate()
	chosen.sort()
	final_cards.sort()
	check(chosen == final_cards and manager.player.max_hp == 80 and manager.enemy.max_hp == 80, "battle uses exact saved cards and eighty HP")
	check(manager.valid_random_deck(manager.enemy.initial_deck), "enemy remains an independent random twenty-five-card deck")
	await shot("custom_deck_battle")
	manager.battle_generation += 1
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
