extends SceneTree

# Graphical QA for the horizontal arena layout.
#   Godot --path . --script res://tools/capture_layout.gd
# Captures the facing standees, the two mirrored HUDs, the round energy orbs and
# effects travelling between the two fighters. Output: work/layout_previews/.

const PLAYER_ANCHOR := Vector2(292, 452)
const ENEMY_ANCHOR := Vector2(1308, 452)

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	ui.call("_start_battle")
	print("QA: waiting for opening draw")
	await create_timer(6.4).timeout
	var output := ProjectSettings.globalize_path("res://work/layout_previews")
	DirAccess.make_dir_recursive_absolute(output)
	var fx: BattleFX = ui.get("battle_fx")
	var manager: BattleManager = ui.get("manager")

	await _shot(output.path_join("battle_start.png"))
	print("QA: battle start captured")

	ui.call("_on_hand_hover", 2)
	await create_timer(0.3).timeout
	await _shot(output.path_join("hover.png"))
	ui.call("_on_hand_exit", 2)

	# A card aimed at the opponent must cross the arena to the enemy standee.
	fx.clear_effects()
	fx.cast(manager.cards["fire_edge"], "player")
	await create_timer(0.27).timeout
	await _shot(output.path_join("cast_to_enemy.png"))

	# A card that only helps its caster must land on the player's own standee.
	fx.clear_effects()
	fx.cast(manager.cards["wood_heal"], "player")
	await create_timer(0.27).timeout
	await _shot(output.path_join("cast_to_self.png"))

	# The enemy's own attack travels the other way.
	fx.clear_effects()
	fx.cast(manager.cards["water_edge"], "enemy")
	await create_timer(0.27).timeout
	await _shot(output.path_join("cast_from_enemy.png"))

	fx.clear_effects()
	fx.impact("fire", ENEMY_ANCHOR)
	fx.status(ENEMY_ANCHOR, "fire", "burn")
	fx.energy(Vector2(1254, 136), "water", true)
	await create_timer(0.22).timeout
	await _shot(output.path_join("enemy_feedback.png"))

	fx.clear_effects()
	fx.impact("earth", PLAYER_ANCHOR, "shield")
	fx.heal(PLAYER_ANCHOR, "wood")
	ui.call("_show_floating", "-17", "player", Color("#f48177"))
	ui.call("_show_floating", "+3", "player", Color("#8dd89b"), 0.0, Vector2(16, 640))
	await create_timer(0.14).timeout
	await _shot(output.path_join("player_feedback.png"))

	# Real play-through: attack the enemy, then a self-buff, then the enemy turn.
	fx.clear_effects()
	manager.player.hand.clear()
	manager.player.hand.append("fire_edge")
	manager.player.energy["fire"] = 3
	ui.call("_refresh")
	ui.call("_play_card_from", 0, Vector2(800, 470))
	await create_timer(2.6).timeout
	await _shot(output.path_join("played_attack.png"))
	await create_timer(0.6).timeout
	if manager.played_cards < 1:
		push_error("UI did not resolve the player's attack")
		quit(1)
		return

	manager.player.hand.append("earth_bastion")
	manager.player.energy["earth"] = 3
	ui.call("_refresh")
	ui.call("_play_card_from", 0, Vector2(800, 470))
	await create_timer(2.6).timeout
	await _shot(output.path_join("played_self_buff.png"))
	await create_timer(0.6).timeout

	manager.enemy.hand.clear()
	manager.enemy.hand.append("fire_edge")
	manager.enemy.energy["fire"] = 3
	ui.call("_on_end_turn")
	await create_timer(1.6).timeout
	await _shot(output.path_join("enemy_reveal.png"))
	await create_timer(1.4).timeout
	await _shot(output.path_join("enemy_attack.png"))

	# Other opponents, to review how each standee faces the player.
	for enemy_id in ["tide", "harmony"]:
		ui.set("menu_enemy", enemy_id)
		ui.call("_start_battle")
		await create_timer(6.2).timeout
		await _shot(output.path_join("standee_%s.png" % enemy_id))

	print("Layout previews: ", output)
	quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
