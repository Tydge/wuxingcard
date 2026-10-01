extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	ui.manager.start_battle("ember", "balanced", 2)
	await create_timer(5.4).timeout
	var manager: BattleManager = ui.get("manager")
	var index := 2
	manager.phase = "enemy_action"
	ui.action_busy = true
	ui.call("_refresh")
	ui.call("_on_hand_hover", index)
	if not is_instance_valid(ui.get("hover_preview")):
		push_error("PC hand hover should remain available during the enemy turn")
		quit(1)
		return
	ui.call("_on_hand_exit", index)
	manager.phase = "player_action"
	ui.action_busy = false
	manager.player.hand[index] = "fire_strike"
	manager.player.energy["fire"] = 10
	ui.call("_refresh")
	var before := manager.player.hand.size()
	var cards: Array = ui.get("hand_cards")
	Input.warp_mouse(cards[index].position + Vector2(75, 80))
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	ui.call("_on_hand_input", press, index)
	if ui.get("drag_index") != index:
		push_error("Hand press did not start a drag")
		quit(1)
		return
	Input.warp_mouse(Vector2(1308, 452))
	await process_frame
	var motion := InputEventMouseMotion.new()
	ui.call("_input", motion)
	var preview: Panel = ui.get("damage_preview")
	if preview == null or not preview.visible or not str(ui.get("damage_preview_label").text).begins_with("预计伤害 "):
		push_error("Damage target did not show calculated damage preview")
		quit(1)
		return
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	ui.call("_input", release)
	await create_timer(3.7).timeout
	if manager.played_cards != 1 or manager.player.hand.size() != before - 1:
		push_error("Drag release did not play one card and retain the other cards")
		quit(1)
		return
	print("Drag interaction passed")
	quit()
