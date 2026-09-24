extends SceneTree

# Graphical QA: capture the fan, hover card, played card and an enemy reveal.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	ui.call("_start_battle")
	print("QA: waiting for opening draw")
	await create_timer(5.9).timeout
	print("QA: opening draw complete")
	var output := ProjectSettings.globalize_path("res://work/interaction_previews")
	DirAccess.make_dir_recursive_absolute(output)
	await _shot(output.path_join("hand.png"))
	print("QA: hand captured")
	ui.call("_on_hand_hover", 2)
	await create_timer(0.25).timeout
	await _shot(output.path_join("hover.png"))
	ui.call("_on_hand_exit", 2)
	var manager: BattleManager = ui.get("manager")
	while manager.player.hand.size() < 8:
		manager.player.hand.append("earth_edge")
	ui.call("_refresh")
	await _shot(output.path_join("hand_full.png"))
	var before := manager.player.hand.size()
	manager.player.hand[2] = "fire_edge"
	var card: Dictionary = manager.cards[manager.player.hand[2]]
	manager.player.energy[card["element"]] = 10
	ui.call("_refresh")
	ui.call("_play_card_from", 2, Vector2(910, 500))
	await create_timer(0.7).timeout
	await _shot(output.path_join("player_reveal.png"))
	await create_timer(3.3).timeout
	await _shot(output.path_join("hand_after_play.png"))
	if manager.player.hand.size() != before - 1:
		push_error("Playing one card did not leave the remaining hand intact")
		quit(1)
		return
	manager.enemy.hand.clear()
	manager.enemy.hand.append("fire_edge")
	manager.enemy.energy["fire"] = 3
	ui.call("_on_end_turn")
	await create_timer(1.5).timeout
	await _shot(output.path_join("enemy_reveal.png"))
	print("Interaction previews: ", output)
	quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
