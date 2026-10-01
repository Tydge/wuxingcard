extends SceneTree

var failures := 0
var ui: Control
var screen: EndlessScreen
var output := "res://work/endless"
var save := "user://endless_ui_test.json"

func _initialize() -> void: call_deferred("run_test")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func find_screen() -> EndlessScreen:
	for child in ui.get_children():
		if child is EndlessScreen and child.visible: return child
	return null

func find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption and child.visible: return child
		var result := find_button(child, caption)
		if result != null: return result
	return null

func press(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "input target is visible")
	if control == null: return
	var point := control.get_global_rect().get_center()
	for held in [true, false]:
		if PlatformUI.is_touch():
			var touch := InputEventScreenTouch.new()
			touch.position = point
			touch.pressed = held
			root.push_input(touch, true)
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION if PlatformUI.is_touch() else 0
		mouse.position = point
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = held
		root.push_input(mouse, true)
	await process_frame
	await process_frame

func drag_card(source: Control, destination: Control) -> void:
	var from := source.get_global_rect().get_center()
	var to := destination.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.position = from
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	for point in [from + Vector2(28, 0), to]:
		Input.warp_mouse(root.get_final_transform() * point)
		var move := InputEventMouseMotion.new()
		move.position = point
		move.relative = point - from
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(move, true)
		await process_frame
	await process_frame
	check(root.gui_is_dragging() and screen.workshop.drop_zone.hovered, "shared card dragging highlights the legal deck target")
	down.position = to
	down.pressed = false
	down.button_mask = 0
	root.push_input(down, true)
	await create_timer(0.4).timeout

func shot(name: String) -> void:
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(("touch_" if PlatformUI.is_touch() else "") + name + ".png")))

func fast_opening(stage: String) -> void:
	if stage == "first_turn": ui.action_busy = false

func win() -> void:
	ui.manager.pending_choice.clear()
	ui.manager.choice_completed.emit()
	ui.manager.enemy.hp = 0
	ui.manager._check_finish()
	await process_frame
	await press(find_button(ui, "前往休整"))
	screen = find_screen()
	check(screen != null and screen.view == "rest", "victory enters rest through the result button")
	check(ui.fx_layer.get_children().filter(func(node): return node != ui.battle_fx and node is CanvasItem and node.visible).is_empty(), "battle notices and floating effects never leak into rest")

func run_test() -> void:
	if PlatformUI.is_touch(): save = "user://endless_touch_test.json"
	DirAccess.remove_absolute(save)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	ui = load("res://battle/battle_scene.tscn").instantiate()
	ui.endless_save_path = save
	root.add_child(ui)
	await process_frame
	var menu: MainMenu
	for child in ui.get_children():
		if child is MainMenu: menu = child
	check(not menu.mode_buttons["endless"].disabled, "endless mode is enabled on the title screen")
	await press(menu.mode_buttons["endless"])
	screen = find_screen()
	check(screen != null and screen.view == "setup", "title entry opens initial construction")
	check(screen.next_button.disabled and screen.workshop.card_nodes.size() == (6 if PlatformUI.is_touch() else 12), "shared workshop shows original cards and prevents incomplete entry")
	check(screen.workshop.card_nodes.all(func(node): return int(node.card["level"]) == 0), "initial setup has no relic selection")
	await shot("setup")
	await press(screen.workshop.card_nodes[0])
	await create_timer(0.45).timeout
	check(screen.modal != null and screen.inspect_tabs == null, "initial inspection has no free upgrade selection")
	await press(screen.action_button)
	check(ui.endless.state["draft"].size() == 1, "mouse or touch adds only one selected card")
	var construction := screen.workshop
	var original_content := construction.content
	await press(construction.next_page_button)
	await create_timer(0.6).timeout
	check(construction.page == 1 and construction.content == original_content, "smooth paging keeps the editor and deck list mounted")
	await press(construction.previous_page_button)
	await create_timer(0.5).timeout
	var first_id := str(construction.card_nodes[0].card["id"])
	if PlatformUI.is_touch(): await press(construction.card_nodes[0].plus)
	else: await drag_card(construction.card_nodes[0], construction.drop_zone)
	check(ui.endless.state["draft"].size() == 2 and screen.modal == null, "drag or plus adds a second copy without opening an inspector")
	await press(construction.row_nodes[first_id])
	check(screen.modal != null and ui.endless.state["draft"].size() == 2, "deck row body always inspects rather than removing a card")
	screen._close_modal()
	await create_timer(0.4).timeout
	await press(find_button(construction.row_nodes[first_id], "−"))
	check(ui.endless.state["draft"].size() == 1 and construction.content == original_content, "the separate minus removes one copy without rebuilding the editor")
	await press(find_button(screen.content, "查看对手"))
	check(screen.view == "scout" and screen.item_views.size() == 3, "scouting reveals exactly three cards, with no full deck or relic views")
	var visible: Array = ui.endless.scouted_cards().duplicate()
	await shot("scout")
	screen.go_back()
	for entry in ContentCatalog.base_entries(ui.manager.cards):
		for copy in 2:
			if ui.endless.state["draft"].size() < 15: ui.endless.change_draft(str(entry["id"]), true)
	screen.build()
	check(not screen.next_button.disabled, "exactly fifteen cards unlock entry")
	var actual_save_path: String = ui.endless.path
	ui.endless.path = "user://missing_endless_ui_folder/blocked.json"
	await press(screen.next_button)
	check(screen.view == "setup" and ui.endless.state["phase"] == "setup" and screen.workshop.draft.size() == 15 and screen.workshop.message.text == "进度保存失败，请重试", "failed start save stays in the shared workshop and reports the error without losing the draft")
	ui.endless.path = actual_save_path
	ui.manager.opening_presenter = fast_opening
	ui.manager.summon_presenter = Callable()
	await press(screen.next_button)
	check(ui.manager.player.initial_deck.size() == 15 and ui.manager.player.max_hp == 80 and ui.manager.enemy.max_hp == 40, "UI enters the promised first battle")
	check(ui.manager.player.artifacts.values() == ["", "", ""], "initial battle cannot inherit test loadouts")
	ui._endless_home()
	ui._open_endless()
	check(ui.endless.scouted_cards() == visible and ui.manager.enemy.initial_deck == ui.endless.opponent()["cards"], "returning and resuming preserve the scouted opponent")
	ui.manager.battle_generation += 1
	ui.enemy_animating = false
	await win()
	check(ui.endless.state["gold"] == 100 and ui.endless.state["wins"] == 1, "one victory awards exactly one prize")
	await shot("rest")
	await press(screen.hotspots["shop"])
	check(screen.view == "shop" and screen.shop_buttons.size() == 7, "shop presents five cards and two relics")
	await shot("shop")
	await press(screen.item_views[0])
	check(screen.modal != null and screen.action_button.text == "购买   ·   30 灵钱", "shop inspection displays the real purchase cost")
	await press(screen.action_button)
	check(ui.endless.state["owned_cards"].size() == 16 and ui.endless.state["deck"].size() == 15 and ui.endless.state["gold"] == 70, "purchase goes to warehouse once without changing the deck")
	check(screen.shop_buttons[0].disabled, "purchased offer visibly sells out")
	screen._navigate("inventory")
	await process_frame
	await shot("inventory")
	var uid := str(ui.endless.state["deck"][0])
	var owned_id := str(ui.endless.item("cards", uid)["id"])
	await press(screen.workshop.row_nodes[owned_id])
	check(screen.modal != null and screen.selected_uid == uid and ui.endless.state["deck"].size() == 15, "clicking the right deck row inspects its equipped physical copy without removing it")
	await shot("upgrade")
	await press(screen.upgrade_button)
	check(ui.endless.state["gold"] == 70 and int(screen.preview_entry["level"]) == 1, "upgrade first previews the exact next level without charging")
	await create_timer(0.28).timeout
	await shot("upgrade_preview")
	await press(screen.upgrade_button)
	check(ui.endless.state["gold"] == 30 and ui.endless.item("cards", uid)["id"].ends_with("__1"), "one paid upgrade changes one owned card once")
	screen._close_modal(false)
	ui.endless.toggle_card(uid)
	screen._navigate("rest")
	check(screen.next_button.disabled, "fourteen-card deck blocks continuation")
	ui.endless.toggle_card(uid)
	screen.build()
	check(not screen.next_button.disabled, "restoring a legal deck re-enables continuation")
	await press(screen.next_button)
	check(ui.manager.enemy.max_hp == 50 and ui.manager.player.hp == 80, "second battle resets HP and grows the enemy")
	ui.manager.battle_generation += 1
	ui.enemy_animating = false
	await win()
	screen._navigate("shop")
	await press(screen.shop_buttons[5])
	check(ui.endless.state["owned_artifacts"].size() == 1 and ui.manager.player.artifacts.values() == ["", "", ""], "purchased relic is not automatically equipped")
	screen._navigate("inventory")
	screen.kind = "artifacts"
	screen.build()
	await process_frame
	var relic: Dictionary = ui.endless.state["owned_artifacts"][0]
	screen._inspect_owned(str(relic["id"]), str(relic["uid"]))
	await create_timer(0.45).timeout
	await press(screen.action_button)
	check(ui.endless.loadout_ids().values().has(relic["id"]), "warehouse touch or mouse explicitly equips the relic")
	await shot("relics")
	screen._navigate("rest")
	screen._navigate("inventory")
	screen.workshop._build_artifact_editor()
	await press(screen.workshop.artifact_rows[str(ui.endless.artifacts[relic["id"]]["slot"])])
	check(screen.modal != null and screen.selected_uid == str(relic["uid"]) and not screen.upgrade_button.disabled, "equipped relic row opens details and paid upgrading directly")
	# Fund a second explicit upgrade action to exercise the equipped-slot path,
	# then restore the earned balance before the existing HP economy check.
	ui.endless.state["gold"] = int(ui.endless.state["gold"]) + 60
	var relic_uid := str(relic["uid"])
	var relic_original := str(relic["id"])
	await press(screen.upgrade_button)
	await create_timer(0.28).timeout
	await press(screen.upgrade_button)
	check(str(ui.endless.item("artifacts", relic_uid)["id"]) == relic_original + "__1" and ui.endless.loadout_ids().values().has(relic_original + "__1") and ui.endless.state["gold"] == 60, "paid relic upgrading from the equipped slot updates that copy and the live equipment")
	screen._close_modal(false)
	screen._navigate("rest")
	await press(screen.hp_hotspot)
	check(ui.endless.state["max_hp"] == 90 and ui.endless.state["gold"] == 0, "HP purchase spends the shown price once")
	await press(screen.next_button)
	check(ui.manager.player.hp == 90 and ui.manager.enemy.hp == 60, "third battle starts at grown full HP")
	ui.manager.battle_generation += 1
	ui.manager.pending_choice.clear()
	ui.manager.choice_completed.emit()
	ui.manager.player.hp = 0
	ui.manager.enemy.hp = 0
	ui.manager._check_finish()
	await process_frame
	check(ui.endless.state["phase"] == "ended" and ui.endless.state["wins"] == 2, "UI treats a tie as run failure")
	await press(find_button(ui, "查看结算"))
	screen = find_screen()
	check(screen.view == "summary", "tie shows the run summary")
	await shot("summary")
	await press(find_button(screen.content, "再赴无尽"))
	screen = find_screen()
	check(screen.view == "setup" and ui.endless.state["draft"].is_empty() and ui.endless.state["owned_artifacts"].is_empty(), "new run cannot carry old upgrades or equipment")
	ui._endless_home()
	await create_timer(1.8).timeout
	ui.queue_free()
	await process_frame
	DirAccess.remove_absolute(save)
	print("Endless UI: %s input, setup, fixed scouts, resume, victory, shop, warehouse, upgrades, legality, HP, relics and tie summary; %d failures" % ["touch" if PlatformUI.is_touch() else "mouse", failures])
	quit(1 if failures else 0)
