extends SceneTree

var failures := 0
var ui: Control
var menu: MainMenu
var output := "res://work/upgrade_previews"

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(name + ".png")))

func find_menu() -> MainMenu:
	for child in ui.get_children():
		if child is MainMenu: return child
	return null

func switch_level(level: int) -> void:
	menu.inspect_tabs.buttons[level].pressed.emit()
	menu.inspect_switch_tween.pause()
	menu.inspect_switch_tween.custom_step(0.1)
	check(menu.inspect_card.modulate.a > 0 and menu.inspect_card.modulate.a < 1 and menu.inspect_previous.modulate.a > 0, "grades crossfade without a blank frame")
	menu.inspect_switch_tween.custom_step(0.3)
	await create_timer(0.27).timeout
	check(menu.inspect_entry["level"] == level and menu.inspect_card.modulate.a == 1.0 and menu.inspect_card.position == menu.inspect_destination, "selected grade settles in place")

func close() -> void:
	menu._close_inspector()
	await create_timer(0.38).timeout

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	menu = find_menu()
	menu.deck_store_path = "res://work/upgrade_ui_decks.json"
	menu._show_collection()
	check(menu.filtered_cards.size() == 80, "collection groups the 240 versions into 80 families")
	menu._open_inspector(ui.manager.cards["metal_forge"], menu.card_nodes[0])
	await create_timer(0.46).timeout
	await switch_level(1)
	await shot("alchemy_jing")
	await switch_level(2)
	await shot("alchemy_xuan")
	# Interrupt a transition, then close before it completes.
	menu.inspect_tabs.buttons[0].pressed.emit()
	menu.inspect_tabs.buttons[2].pressed.emit()
	await close()
	check(menu.inspector == null, "rapid switching and closing release the modal")
	menu._open_inspector(ui.manager.cards["water_spring_card"], menu.card_nodes[0])
	await create_timer(0.46).timeout
	check(menu.inspect_entry["text"] == "回合开始：召唤者获得1点木能量。", "collection displays the corrected spring recipient")
	await shot("spring_base")
	await switch_level(2)
	check(menu.inspect_entry["text"] == "回合开始：召唤者获得1点木能量，恢复4点生命。", "spring inspector uses concise upgraded text")
	await shot("spring_xuan")
	await close()
	menu._open_inspector(ui.manager.cards["water_four_aspects"], menu.card_nodes[0])
	await create_timer(0.46).timeout
	await switch_level(2)
	check(menu.inspect_entry["text"] == "获得金、木、火、土能量各1点，抽1张牌。", "four aspects inspector groups parallel energies")
	await shot("four_aspects_xuan")
	await close()
	menu.collection_type = "artifacts"
	menu._build_collection()
	check(menu.filtered_cards.size() == 30, "artifact collection groups 90 versions into 30 families")
	menu._open_inspector(menu.artifacts["metal_thunder_ruler"], menu.card_nodes[0])
	await create_timer(0.46).timeout
	await switch_level(2)
	check(menu.inspect_card is ArtifactView and menu.inspect_entry["cooldown"] == 2, "artifact inspector changes rules and retains art")
	await shot("ruler_xuan")
	await close()

	menu._show_decks()
	var workshop := menu.workshop
	workshop._open_editor({"id":"", "name":"升级构筑", "cards":[]})
	menu._open_inspector(ui.manager.cards["metal_forge"], workshop.card_nodes[0].front)
	await create_timer(0.46).timeout
	await switch_level(1)
	menu.inspect_action.pressed.emit()
	await switch_level(2)
	menu.inspect_action.pressed.emit()
	check(workshop.draft == ["metal_forge__1", "metal_forge__2"] and not workshop._can_add("metal_forge"), "construct selected grades with family copy limit")
	await switch_level(0)
	menu.inspect_action.pressed.emit()
	check(workshop.draft == ["metal_forge", "metal_forge__2"], "full family can replace one copy's grade without changing deck size")
	workshop._remove_card("metal_forge")
	for item: Dictionary in ContentCatalog.base_entries(ui.manager.cards):
		if item["id"] == "metal_forge": continue
		for copy in 2:
			if workshop.draft.size() < 30: workshop._add_card(str(item["id"]))
	await switch_level(1)
	check(menu.inspect_action.text.begins_with("更换1张") and not menu.inspect_action.disabled, "thirty-card deck clearly offers replacement instead of adding a thirty-first card")
	menu.inspect_action.pressed.emit()
	check(workshop.draft.size() == 30 and workshop.draft.has("metal_forge__1") and not workshop.draft.has("metal_forge__2"), "full deck replaces its one existing family member")
	await close()
	workshop._open_artifacts({"id":"", "name":"升级构筑", "cards":workshop.draft})
	var source: ArtifactLibraryCard
	for child in workshop.content.get_children():
		if child is ArtifactLibraryCard: source = child; break
	menu._open_inspector(workshop.artifacts["metal_thunder_ruler"], source.front)
	await create_timer(0.46).timeout
	await switch_level(2)
	var page := workshop.content
	var row: ArtifactLoadoutRow = workshop.artifact_rows["implement"]
	menu.inspect_action.pressed.emit()
	check(workshop.draft_loadout["implement"] == "metal_thunder_ruler__2" and workshop.content == page and workshop.artifact_rows["implement"] == row, "equip upgraded artifact without rebuilding the page")
	await shot("artifact_equip_xuan")
	await close()

	menu._show_home()
	ui.manager.random_artifacts_enabled = false
	await ui.manager.start_battle("ember", "balanced", 2)
	ui.manager.player.hand.assign(["water_thought__1"])
	ui.manager.player.energy["water"] = 2
	ui.manager.player.draw_pile.assign(["metal_forge__2", "wood_heal__1", "water_strike__2", "earth_stele_card__2"])
	ui.action_busy = false
	ui._refresh()
	check(ui.manager.play_player_card(0), "upgraded contemplation spell starts")
	await process_frame
	await create_timer(0.3).timeout
	check(ui.choice_dialog != null and ui.choice_dialog.frames.size() == 3 and ui.choice_dialog.confirm.disabled, "choice presents top three actual cards and requires selection")
	ui.choice_dialog._select(1)
	await shot("contemplation")
	ui.choice_dialog.confirm.pressed.emit()
	await process_frame
	check(ui.choice_dialog == null and ui.manager.pending_choice.is_empty() and ui.manager.player.hand == ["metal_forge__2", "water_strike__2"], "confirmation resumes play and keeps selected upgrade level")
	# Opening contemplation must finish before the first turn starts.
	var deck: Array[String] = ui.manager.generate_random_deck()
	ui.manager.start_battle("ember", "random", 128, {"id":"opening_upgrade", "name":"开局观想", "cards":deck, "artifacts":{"pendant":"water_tide_pearl__2"}})
	await process_frame
	while ui.choice_dialog == null: await process_frame
	check(ui.manager.phase == "battle_start" and ui.choice_dialog != null and ui.manager.player.hand.size() == 4, "upgraded opening pendant draws first, then waits for the player's choice")
	ui.choice_dialog._select(0)
	ui.choice_dialog.confirm.pressed.emit()
	while ui.opening_active: await process_frame
	check(ui.manager.phase == "player_action" and ui.manager.player.hand.size() == 6, "opening choice resumes the first turn's normal draw")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://work/upgrade_ui_decks.json"))
	print("Upgrade UI: collection, smooth transitions, mixed-grade construction, artifact equip and contemplation; %d failures" % failures)
	quit(1 if failures else 0)
