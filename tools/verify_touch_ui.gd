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
	check(ui.touch_inspecting and ui.drag_index == -1 and manager.player.hand.size() == before, "holding an unaffordable card raises its inspection without playing")
	await create_timer(0.65).timeout
	await shot("hand_hold_inspection")
	press(hand_point(0), false)
	check(not ui.touch_inspecting and manager.player.hand.size() == before, "releasing the card returns its inspection")
	await create_timer(0.23).timeout
	press(Vector2(1000, 400), true)
	press(Vector2(1000, 400), false)
	await create_timer(0.28).timeout
	check(ui.touch_hand_collapsed and ui.hand_cards[0].scale.x < 0.85, "tapping empty battlefield smoothly lowers and shrinks the hand")
	await shot("hand_lowered")
	press(Vector2(880, 840), true)
	press(Vector2(880, 840), false)
	await create_timer(0.28).timeout
	check(not ui.touch_hand_collapsed and is_equal_approx(ui.hand_cards[0].scale.x, 1.0), "tapping the lowered hand restores its normal size")
	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x + 32, hand_point(0).y - 30))
	var warning_count := 0
	for child in ui.fx_layer.get_children():
		if child is Label and child.text == "灵气不足": warning_count += 1
	for offset in [42, 58, 74]:
		slide(Vector2(hand_point(0).x + offset, hand_point(0).y - 65))
	var later_warning_count := 0
	for child in ui.fx_layer.get_children():
		if child is Label and child.text == "灵气不足": later_warning_count += 1
	check(warning_count == 1 and later_warning_count == 1, "one insufficient-energy warning per held gesture")
	slide(hand_point(2))
	slide(Vector2(hand_point(2).x + 80, hand_point(2).y - 45))
	check(ui.drag_index == 2, "after an unaffordable card, browsing to an affordable card still allows dragging")
	press(hand_point(0), false)
	check(manager.phase == "player_action", "insufficient-energy gesture leaves the turn active")
	manager.phase = "enemy_action"
	ui.action_busy = true
	ui.call("_refresh")
	await process_frame
	press(hand_point(0), true)
	check(ui.touch_inspecting and ui.touch_hand_index == 0, "enemy turn still allows holding a hand card to inspect it")
	slide(hand_point(3))
	check(ui.touch_hand_index == 3, "enemy turn still allows browsing the hand")
	ui.call("_refresh")
	await process_frame
	check(ui.touch_finger == 0 and ui.touch_inspecting and ui.touch_hand_index == 3 and not ui.hand_cards[3].visible, "enemy action refresh preserves the held card inspection")
	slide(Vector2(hand_point(3).x + 90, hand_point(3).y - 35))
	check(ui.drag_index == -1, "enemy turn inspection never drags a card into play")
	press(hand_point(3), false)
	press(Vector2(1000, 400), true)
	press(Vector2(1000, 400), false)
	check(ui.touch_hand_collapsed, "enemy turn still allows lowering the hand")
	press(Vector2(880, 840), true)
	press(Vector2(880, 840), false)
	check(not ui.touch_hand_collapsed, "enemy turn still allows restoring the hand")
	var original_hand := manager.player.hand.duplicate()
	manager.player.hand[0] = manager.player.hand[3]
	ui.call("_refresh")
	await process_frame
	press(hand_point(3), true)
	var held_preview: Control = ui.hover_preview
	manager.player.hand.append("metal_strike")
	ui.call("_refresh")
	await process_frame
	check(ui.touch_hand_index == 3 and ui.hover_preview == held_preview and ui.hand_cards.size() == 6 and not ui.hand_cards[3].visible, "drawing while holding a card preserves the enlarged card and reflows the hand")
	await shot("enemy_turn_draw_while_holding")
	manager.hand_card_removed.emit("player", manager.player.hand[0], 0, "discard")
	manager.player.hand.remove_at(0)
	ui.call("_refresh")
	await process_frame
	check(ui.touch_hand_index == 2 and ui.hover_preview == held_preview and ui.touch_hand_card_id == "water_strike", "discarding an earlier identical card keeps the held copy selected")
	manager.hand_card_removed.emit("player", manager.player.hand[2], 2, "discard")
	manager.player.hand.remove_at(2)
	ui.call("_refresh")
	await process_frame
	check(not ui.touch_inspecting and ui.touch_finger == -1, "discarding the held card closes its inspection instead of switching to another copy")
	press(hand_point(2), false)
	manager.player.hand.assign(original_hand)
	ui.call("_clear_discard_animations")
	manager.phase = "player_action"
	ui.action_busy = false
	ui.call("_refresh")
	await process_frame
	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x + 170, hand_point(0).y - 24))
	check(ui.touch_hand_index > 0 and ui.drag_index == -1, "an approximately eight-degree gesture only browses the hand")
	slide(hand_point(4))
	check(ui.touch_hand_index == 4 and ui.drag_index == -1, "horizontal hand browsing selects another card without casting")
	press(hand_point(4), false)
	await create_timer(0.23).timeout
	press(hand_point(0), true)
	var first_center := hand_point(0)
	var second_center := hand_point(1)
	var edge_x := (first_center.x + second_center.x) / 2.0
	slide(Vector2(edge_x + 8, first_center.y))
	check(ui.touch_hand_index == 0, "hovering near the card boundary keeps the current inspection")
	slide(Vector2(edge_x + 26, first_center.y))
	for offset in [8, -8, 8, -8]:
		slide(Vector2(edge_x + offset, first_center.y))
		check(ui.touch_hand_index == 1, "small finger jitter does not flicker between adjacent cards")
	press(Vector2(edge_x, first_center.y), false)
	await create_timer(0.23).timeout

	manager.player.energy.metal = 10
	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x + 140, hand_point(0).y - 27))
	check(ui.drag_index == 0, "a gesture just over ten degrees drags the original card across its neighbor")
	await create_timer(0.28).timeout
	check(ui.touch_hand_collapsed and ui.hand_cards[2].scale.x < 0.85, "dragging a card lowers the remaining hand")
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
	await create_timer(0.23).timeout
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
	manager.player.hand.assign(["metal_furnace_card"])
	manager.player.energy.metal = 10
	ui.call("_refresh")
	await process_frame
	var slot_center: Vector2 = ui.call("_summon_point", "player", 0)
	check(ui.call("_drop_selection", manager.cards["metal_furnace_card"], slot_center + Vector2(105, 0)).get("slot", -1) == 0, "summon drop accepts a finger slightly outside the painted slot")
	press(hand_point(0), true)
	slide(Vector2(hand_point(0).x + 55, hand_point(0).y - 55))
	press(slot_center + Vector2(105, 0), false)
	await create_timer(3.8).timeout
	check(manager.player.summons[0] != null and manager.player.energy.metal == 8, "wider summon landing zone still resolves exactly one summon")
	manager.phase = "victory"
	ui.call("_refresh")
	await process_frame
	press(ui.call("_summon_point", "enemy", 0), true)
	press(ui.call("_summon_point", "enemy", 0), false)
	check(not ui.touch_inspecting and manager.phase == "victory", "finished battle ignores battlefield summons")
	press(Vector2(937, 552), true)
	press(Vector2(937, 552), false)
	await process_frame
	check(manager.phase == "menu", "Return to Mountain Gate button works on touch after battle")
	manager.phase = "victory"
	ui.call("_refresh")
	await process_frame
	press(Vector2(662, 552), true)
	press(Vector2(662, 552), false)
	await create_timer(1.0).timeout
	check(manager.phase != "victory" and manager.phase != "menu", "Retry button starts another battle on touch")
	print("Touch interface checks: ", failures, " failures")
	quit(1 if failures else 0)
