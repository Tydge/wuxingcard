extends SceneTree

# Run with a graphical Godot instance:
# Godot --path . --script res://tools/capture_fx.gd
# Captures representative elemental casts and an impact for visual review.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Node = current_scene
	ui.set("menu_deck", "balanced")
	ui.call("_start_battle")
	await create_timer(5.2).timeout
	var fx: BattleFX = ui.get("battle_fx")
	var manager: BattleManager = ui.get("manager")
	var output := ProjectSettings.globalize_path("res://work/fx_previews")
	DirAccess.make_dir_recursive_absolute(output)
	var examples := {"metal":"metal_edge", "wood":"wood_edge", "water":"water_edge", "fire":"fire_edge", "earth":"earth_edge"}
	for element in BattleRules.ELEMENTS:
		fx.clear_effects()
		fx.cast(manager.cards[examples[element]], "player")
		await create_timer(0.27).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s_cast.png" % element))
	fx.clear_effects()
	fx.impact("fire", Vector2(1308, 452))
	await create_timer(0.19).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("fire_impact.png"))
	fx.clear_effects()
	ui.call("_on_action_event", "护盾生效", "enemy", "status_shield", "earth", 10)
	ui.call("_on_action_event", "获得水能量", "player", "energy", "water", 1)
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("status_energy_cards.png"))
	fx.clear_effects()
	manager.draw_card(manager.player)
	ui.call("_refresh")
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("draw_feedback.png"))
	# Exercise the real UI sequence as well as standalone effect rendering.
	fx.clear_effects()
	manager.player.hand.clear()
	manager.player.hand.append("fire_edge")
	manager.player.energy["fire"] = 3
	ui.call("_refresh")
	ui.call("_play_card_from", 0, Vector2(780, 530))
	await create_timer(2.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("player_cast.png"))
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("player_card_resolved.png"))
	if manager.played_cards < 1:
		push_error("UI did not resolve the player's card")
		quit(1)
		return
	await create_timer(0.85).timeout
	ui.call("_on_end_turn")
	manager.enemy.hand.clear()
	manager.enemy.hand.append("fire_edge")
	manager.enemy.energy["fire"] = 3
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("enemy_card_reveal.png"))
	await create_timer(2.3).timeout
	if manager.played_cards < 2:
		push_error("UI did not resolve the enemy's card")
		quit(1)
		return
	await create_timer(1.1).timeout
	print("FX previews: ", output)
	quit()
