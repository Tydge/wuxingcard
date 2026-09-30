extends SceneTree

var failures := 0
var ui: Control
var manager: BattleManager

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func tap(point: Vector2) -> void:
	for held in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = point; touch.pressed = held
		root.push_input(touch, true)
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = point; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = held
		root.push_input(mouse, true)
func center(control: Control) -> Vector2: return control.get_global_rect().get_center()
func get_menu() -> MainMenu:
	for child in ui.get_children():
		if child is MainMenu: return child
	return null
func prepare() -> void:
	manager.battle_generation += 1
	manager.pending_choice.clear()
	for actor in [manager.player, manager.enemy]:
		actor.setup("player" if actor == manager.player else "ember", "触屏测试", [], manager.rng)
		actor.max_hp = 80; actor.hp = 50; actor.own_turn_count = 1
		actor.draw_pile.assign(["metal_forge__2", "wood_heal__1", "water_strike__2", "earth_stele_card__2"])
		actor.summons[0] = Summon.new()
		actor.summons[0].setup(manager.summon_templates["earth_stele__2"])
		actor.summons[0].hp = 10
		for element in BattleRules.ELEMENTS: actor.energy[element] = 10
	manager._equip_loadout(manager.player, {"implement":"water_return_cup__2"})
	manager._equip_loadout(manager.enemy, {"implement":"metal_thunder_ruler__2"})
	manager.player.hand.assign(["metal_strike", "water_thought__1"])
	manager.phase = "player_action"; manager.round_number = 1
	ui.action_busy = false; ui.enemy_animating = false
	ui.pending_player_draws = 0; ui.pending_enemy_draws = 0; ui.draw_animation_active = false
	ui._clear_contemplation(); ui._clear_actors(); ui._refresh()
func portraits_unchanged(actors: Array, controls: Array, message: String) -> void:
	check(ui.actor_layer.get_children() == actors and ui.get_children() == controls, message + " preserves the scene")
	for actor: CanvasItem in actors:
		check(actor.is_visible_in_tree() and actor.modulate.a > 0, message + " keeps every portrait visible")
	check(manager.player.hp == 50 and manager.player.summons[0].hp == 10 and manager.player.artifact_ready_turn == 0, message + " spends no effect or cooldown")
func run() -> void:
	check(PlatformUI.is_touch(), "run with -- --touch-ui")
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame; await process_frame
	ui = current_scene; manager = ui.manager
	prepare()
	await process_frame
	var actors: Array = ui.actor_layer.get_children()
	var controls: Array = ui.get_children()
	for repetition in 3:
		ui._show_artifact_preview("player", "implement")
		tap(center(ui.artifact_preview_button))
		check(ui.artifact_aiming and not is_instance_valid(ui.hover_preview), "touching the preview's Activate button enters aiming")
		tap(Vector2(810, 829))
		check(not ui.artifact_aiming and ui.artifact_target_layer == null, "bottom Cancel removes the targeting overlay")
		portraits_unchanged(actors, controls, "touch cancel")
	ui._on_artifact_pressed()
	ui._request_back()
	check(not ui.artifact_aiming and not is_instance_valid(ui.back_dialog), "Android Back cancels aiming before leaving the battle")
	portraits_unchanged(actors, controls, "Back cancel")
	ui._on_artifact_pressed()
	var cancel: Button
	for child in ui.artifact_target_layer.get_children():
		if child is Button and child.text == "取消发动": cancel = child
	cancel.pressed.emit()
	portraits_unchanged(actors, controls, "button cancel")
	ui._on_artifact_pressed()
	tap(Vector2(1000, 400))
	portraits_unchanged(actors, controls, "outside cancel")
	ui._on_artifact_pressed()
	var old_layer: Control = ui.artifact_target_layer
	old_layer.visibility_changed.connect(ui._cancel_artifact_aim)
	ui._cancel_artifact_aim()
	ui._activate_player_artifact({"kind":"hero", "side":"player"})
	check(ui.artifact_target_layer == null and not ui.artifact_aiming, "hiding the overlay tolerates reentrant cancellation")
	portraits_unchanged(actors, controls, "stale target callback after cancel")
	# A real state refresh must also leave the arena art behind all persistent actors.
	ui._refresh()
	await process_frame
	for child in ui.get_children():
		if child is TextureRect and child.texture != null:
			check(child.z_index < ui.actor_layer.z_index, "arena art has an explicit layer behind actors")
	check(ui.actor_layer.get_children() == actors, "refresh reuses every portrait")
	ui._on_artifact_pressed()
	ui._activate_player_artifact({"kind":"hero", "side":"enemy"})
	check(ui.artifact_aiming and manager.player.hp == 50 and manager.player.artifact_ready_turn == 0, "invalid or stale healing targets do not play effects or spend cooldown")
	ui._cancel_artifact_aim()
	ui._on_artifact_pressed()
	tap(ui._summon_point("player", 0))
	check(not ui.artifact_aiming and manager.player.summons[0].hp == 20 and manager.player.hp == 50 and manager.player.artifact_ready_turn == 4, "touch selects an allied summon exactly once")
	prepare()
	ui._on_artifact_pressed()
	tap(ui.PLAYER_ANCHOR)
	check(manager.player.hp == 60 and manager.player.summons[0].hp == 10, "touch selects the hero without redirecting healing")
	# Actual touch and emulated mouse events must reach grade tabs and action buttons.
	manager.phase = "menu"; ui._refresh()
	var menu := get_menu()
	menu.deck_store_path = "res://work/touch_interaction_decks.json"
	menu._show_decks(); menu.workshop._open_editor({"id":"", "name":"触屏等级", "cards":[]})
	menu._open_inspector(manager.cards["metal_forge"], menu.workshop.card_nodes[0].front)
	await create_timer(0.46).timeout
	for level in [1, 2]:
		tap(center(menu.inspect_tabs.buttons[level]))
		await create_timer(0.3).timeout
		check(menu.inspect_entry["level"] == level and is_instance_valid(menu.inspector), "touching a grade tab keeps the inspector open")
		tap(center(menu.inspect_action))
	check(menu.workshop.draft == ["metal_forge__1", "metal_forge__2"], "touch adds both selected grades without duplicate mouse actions")
	tap(center(menu.inspect_tabs.buttons[0])); tap(center(menu.inspect_tabs.buttons[2])); tap(center(menu.inspect_tabs.buttons[1]))
	await create_timer(0.3).timeout
	check(menu.inspect_entry["level"] == 1, "rapid touch grade changes settle on the final grade")
	menu.go_back()
	await create_timer(0.4).timeout
	check(menu.inspector == null, "Android Back closes the grade inspector")
	menu.workshop._open_artifacts({})
	var content := menu.workshop.content
	var row: ArtifactLoadoutRow = menu.workshop.artifact_rows["implement"]
	var source: Control
	for child in content.get_children():
		if child is ArtifactLibraryCard: source = child.front; break
	menu._open_inspector(menu.artifacts["metal_thunder_ruler"], source)
	await create_timer(0.46).timeout
	tap(center(menu.inspect_tabs.buttons[2])); await create_timer(0.3).timeout
	tap(center(menu.inspect_action))
	check(menu.workshop.draft_loadout["implement"] == "metal_thunder_ruler__2" and menu.workshop.content == content, "touch equips the selected artifact grade without rebuilding the page")
	menu.go_back(); await create_timer(0.4).timeout
	tap(center(row.remove_button))
	check(menu.workshop.draft_loadout["implement"] == "" and menu.workshop.content == content, "touch removal preserves the artifact page")
	prepare()
	manager._equip_loadout(manager.player, {})
	manager.player.hand.assign(["water_thought__1"])
	check(manager.play_player_card(0), "contemplation begins")
	await process_frame
	var dialog: ContemplationDialog = ui.choice_dialog
	check(dialog != null and dialog.confirm.disabled, "a choice requires an explicit selection")
	ui._request_back()
	tap(Vector2(1200, 830))
	check(manager.pending_choice.size() > 0 and not is_instance_valid(ui.back_dialog) and manager.phase == "player_action", "Back and background touches cannot skip a pending choice or end the turn")
	tap(center(dialog.frames[1]))
	check(dialog.selected == 1 and not dialog.confirm.disabled, "touch selects a contemplation card")
	tap(center(dialog.confirm))
	await process_frame
	check(ui.choice_dialog == null and manager.pending_choice.is_empty() and manager.player.hand == ["metal_forge__2", "water_strike__2"], "touch confirms once and preserves the chosen grade and deck order")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://work/touch_interaction_decks.json"))
	ui.queue_free(); await process_frame; await create_timer(0.6).timeout
	print("Touch interaction regression: targeting, cancel, Back, layer order, grade selection, equip and contemplation; %d failures" % failures)
	call_deferred("quit", 1 if failures else 0)
