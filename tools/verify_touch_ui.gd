extends SceneTree

var ui: Control
var manager: BattleManager
var failures := 0
var output := "res://work/android-touch-previews"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func press(point: Vector2, held: bool, finger: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = held
	event.index = finger
	event.canceled = canceled
	root.push_input(event, true)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = point
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = held
	root.push_input(mouse, true)

func slide(point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.index = 0
	root.push_input(event, true)

func hand_point(index: int) -> Vector2:
	return ui.call("_hand_card_center", index, manager.player.hand.size())

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output).path_join(name + ".png"))

func run() -> void:
	check(PlatformUI.is_touch(), "run this test with -- --touch-ui")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	manager = ui.manager
	var menu: MainMenu
	for child in ui.get_children():
		if child is MainMenu: menu = child
	menu.call("_show_collection")
	await create_timer(0.4).timeout
	check(menu.card_nodes.size() == 8, "phone collection shows eight cards per page")
	menu.call("_open_inspector", menu.filtered_cards[0], menu.card_nodes[0])
	await create_timer(0.65).timeout
	check(is_equal_approx(menu.inspect_card.size.x * menu.inspect_card.scale.x, 480), "phone collection inspection is readable")
	await shot("collection_inspection")
	menu.go_back()
	await create_timer(0.35).timeout
	menu.call("_show_decks")
	var workshop := menu.workshop
	workshop.call("_open_editor", {})
	await create_timer(0.3).timeout
	check(workshop.card_nodes.size() == 6, "phone deck library uses six cards per page")
	var entry := workshop.card_nodes[0]
	entry.plus.pressed.emit()
	entry.plus.pressed.emit()
	check(workshop.draft.count(entry.card.id) == 2 and entry.plus.disabled, "tap add respects the two-copy limit")
	var row: DeckRow = workshop.row_nodes[entry.card.id]
	row.pressed.emit()
	await create_timer(0.5).timeout
	var inspect_add: Button
	for child in menu.inspector.get_children():
		if child is Button: inspect_add = child
	check(inspect_add != null and inspect_add.disabled, "inspection add honors the copy limit")
	inspect_add.pressed.emit()
	check(inspect_add.text == "已入组 2 / 2" and workshop.draft.size() == 2, "inspection add refreshes its caption without adding a third copy")
	check(is_instance_valid(menu.inspector) and workshop.draft.size() == 2, "tap carried card inspects without removing it")
	menu.go_back()
	await create_timer(0.35).timeout
	row.remove_requested.emit(entry.card.id)
	check(workshop.draft.size() == 1, "dedicated remove removes one copy")
	await shot("deck_editor")

	manager.player.setup("player", "云溪月", [], manager.rng)
	manager.enemy.setup("ember", "炽羽", [], manager.rng)
	manager.player.hand.assign(["metal_strike", "earth_bastion", "wood_strike", "water_strike", "fire_strike"])
	manager.player.energy.metal = 0
	manager.phase = "player_action"
	manager.round_number = 1
	ui.action_busy = false
	ui.call("_refresh")
	await process_frame
	var before := manager.player.hand.size()
	press(hand_point(0), true)
	press(hand_point(0), false)
	check(ui.touch_inspecting and ui.drag_index == -1 and manager.player.hand.size() == before, "unaffordable tap inspects without playing")
	press(Vector2(1400, 830), true)
	press(Vector2(1400, 830), false)
	check(not ui.touch_inspecting and manager.phase == "player_action", "outside tap dismisses inspection without clicking End Turn underneath")
	press(hand_point(0), true)
	slide(hand_point(4))
	check(ui.touch_hand_index == 4 and ui.drag_index == -1, "horizontal hand browsing selects another card without casting")
	press(hand_point(4), false)
	ui.call("_clear_hover_preview")

	manager.player.energy.metal = 10
	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x, 565))
	check(ui.drag_index == 0, "upward movement enters card targeting")
	slide(Vector2(1308, 452))
	check(ui.damage_preview.visible and ui.damage_preview.position.y < 350, "damage forecast appears above the finger")
	await shot("drag_damage_preview")
	slide(hand_point(0))
	press(hand_point(0), false)
	check(ui.drag_index == -1 and manager.player.hand.size() == before and manager.player.energy.metal == 10, "drag back cancels without spending resources")

	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x, 565))
	press(Vector2(1308, 452), false, 0, true)
	check(ui.drag_index == -1 and manager.player.hand.size() == before, "system-canceled touch does not cast")
	manager.player.add_status("charge", 2, 0)
	ui.call("_refresh")
	await process_frame
	press(ui.status_touch_regions[0].rect.get_center(), true)
	press(ui.status_touch_regions[0].rect.get_center(), false)
	check(ui.touch_inspecting, "status icon opens a touch explanation")
	ui.call("_request_back")
	check(not ui.touch_inspecting and not is_instance_valid(ui.back_dialog), "back closes the explanation first")

	var summon := Summon.new()
	summon.setup(manager.summon_templates["fire_raven"])
	manager.enemy.summons[0] = summon
	ui.call("_refresh")
	await process_frame
	press(ui.call("_summon_point", "enemy", 0), true)
	press(ui.call("_summon_point", "enemy", 0), false)
	check(ui.touch_inspecting and ui.hovered_summon_side == "enemy", "tap enemy summon opens its card")
	await create_timer(0.65).timeout
	await shot("summon_inspection")
	ui.call("_clear_hover_preview")

	manager.player.hand.clear()
	for i in 15: manager.player.hand.append("metal_strike")
	ui.call("_refresh")
	await process_frame
	for card in ui.hand_cards:
		check(card.size == ui.HAND_CARD_SIZE and card.position.y <= 704, "large hands retain card size and a bounded arc")
	press(hand_point(0), true)
	slide(hand_point(14))
	check(ui.touch_hand_index == 14, "overlapping large hand can be browsed end to end")
	press(hand_point(14), false)
	ui.call("_clear_hover_preview")
	ui.call("_request_back")
	check(is_instance_valid(ui.back_dialog), "battle back asks before leaving")
	ui.call("_request_back")
	check(not is_instance_valid(ui.back_dialog), "back again dismisses confirmation")
	var fitted := PlatformUI.fit_design(Rect2(90, 20, 2140, 1040), Vector2(1600, 900))
	check(fitted.position.x >= 90 and fitted.end.x <= 2230 and fitted.position.y >= 20 and fitted.end.y <= 1060, "safe-area fit stays within available screen")
	# The final input proves release on a valid target resolves the real battle rule.
	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x, 565))
	press(Vector2(1308, 452), false)
	await create_timer(4.3).timeout
	check(manager.player.hand.size() == 14 and manager.player.energy.metal == 9 and manager.enemy.hp < 100, "valid touch release plays exactly one card and spends its cost")
	print("Touch interface checks: ", failures, " failures")
	quit(1 if failures else 0)
