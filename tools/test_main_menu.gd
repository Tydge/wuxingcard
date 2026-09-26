extends SceneTree

var ui: Control
var menu: MainMenu
var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func find_menu() -> MainMenu:
	for child in ui.get_children():
		if child is MainMenu: return child
	return null

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	menu = find_menu()
	check(menu != null and menu.view_mode == "home", "game opens at the mountain gate")
	output = ProjectSettings.globalize_path("res://work/menu_previews")
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(1.0).timeout
	await shot("home")
	for mode in ["rogue", "arena", "endless"]:
		check(menu.mode_buttons[mode].disabled, "unfinished mode cannot be selected")
	check(not menu.mode_buttons["test"].disabled and not menu.mode_buttons["collection"].disabled, "test and collection are available")
	menu.mode_buttons["collection"].pressed.emit()
	await process_frame
	check(menu.filtered_cards.size() == 40 and menu.card_nodes.size() == 14, "collection contains every card with pagination")
	await shot("collection")
	var seen: Array[String] = []
	for page in 3:
		for card in menu.filtered_cards.slice(page * 14, mini((page + 1) * 14, 40)):
			seen.append(card["id"])
		for card in menu.card_nodes:
			check(card.position.x >= 244 and card.position.x + card.size.x <= 1534 and card.position.y + card.size.y < 770, "card layout stays within the collection frame")
		if page < 2: menu.call("_change_page", 1)
	check(seen.size() == 40 and menu.card_nodes.size() == 12, "last page includes the remaining cards")
	for element in BattleRules.ELEMENTS:
		var expected := 0
		for card in menu.cards.values():
			if card["element"] == element: expected += 1
		menu.filter_buttons[element].pressed.emit()
		await process_frame
		check(menu.filtered_cards.size() == expected and menu.card_nodes.size() == expected and menu.page == 0, "each element filter displays every matching card")
		for card in menu.filtered_cards:
			check(card["element"] == element, "filter excludes other elements")
	menu.filter_buttons["metal"].pressed.emit()
	await process_frame
	await shot("metal_collection")
	var source: Control
	for i in menu.card_nodes.size():
		if menu.card_nodes[i] is SummonCardView:
			source = menu.card_nodes[i]
			break
	check(source != null, "collection uses the summon card prefab with its health badge")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	source.gui_input.emit(click)
	check(menu.inspect_card.scale.x < 0.4 and menu.inspect_tween.is_running(), "inspection begins at the original card's size")
	await create_timer(0.12).timeout
	await process_frame
	check(menu.inspect_card.scale.x > 0.4 and menu.inspect_card.scale.x < 1.0 and not source.visible, "card enlarges progressively from its grid location (scale %.3f)" % menu.inspect_card.scale.x)
	await shot("inspection_opening")
	await create_timer(0.4).timeout
	check(menu.inspect_card is SummonCardView and menu.inspect_card.scale.is_equal_approx(Vector2.ONE), "inspection shows a full-sized summon card")
	await shot("inspection")
	menu.inspector.gui_input.emit(click)
	await create_timer(0.12).timeout
	check(menu.inspect_card.scale.x < 1.0 and menu.inspect_card.scale.x > 0.4, "card shrinks smoothly back toward its slot")
	await create_timer(0.3).timeout
	check(menu.inspector == null and source.visible, "clicking beside the card restores its grid view")
	# Closing while an opening tween runs must not leave duplicate cards behind.
	source.gui_input.emit(click)
	await create_timer(0.05).timeout
	menu.call("_close_inspector")
	await create_timer(0.4).timeout
	check(menu.inspector == null and source.visible, "rapid open and close is safe")
	menu.call("_show_home")
	menu.mode_buttons["test"].pressed.emit()
	await create_timer(5.8).timeout
	var manager: BattleManager = ui.get("manager")
	check(find_menu() == null and manager.phase == "player_action" and manager.player.hand.size() == 5, "test mode directly starts a playable battle")
	check(manager.selected_enemy_id in ["ember", "tide", "harmony"] and manager.selected_deck_id in ["balanced", "flame", "tide"], "test mode chooses a valid random matchup")
	manager.phase = "menu"
	ui.call("_refresh")
	await process_frame
	check(find_menu() != null and find_menu().view_mode == "home", "returning from battle opens the new main screen")
	print("Main menu UI test: modes, all 40 cards, element filters, animated inspection and random battle; %d failures" % failures)
	quit(1 if failures > 0 else 0)
