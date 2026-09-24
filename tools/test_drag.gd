extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	ui.call("_start_battle")
	await create_timer(5.4).timeout
	var manager: BattleManager = ui.get("manager")
	var index := 2
	manager.player.hand[index] = "fire_edge"
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
	Input.warp_mouse(Vector2(980, 360))
	await process_frame
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
