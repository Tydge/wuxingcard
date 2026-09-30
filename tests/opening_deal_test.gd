extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	push_error(description)

func run() -> void:
	var scene: PackedScene = load("res://battle/battle_scene.tscn")
	var ui: Node = scene.instantiate()
	root.add_child(ui)
	await process_frame
	var battle: BattleManager = ui.get("manager")
	# Both random pendants add an opening draw; test the longest deal explicitly.
	battle.artifacts = {"water_tide_pearl": battle.artifacts["water_tide_pearl"]}
	ui.call("_start_test_battle", {})
	await process_frame
	var manager: Node = ui.get("manager")
	check(manager.get("phase") == "player_action", "opening reaches the player's action phase")
	check(ui.get("draw_animation_active"), "opening cards enter the deal animation")
	check(int(ui.get("pending_player_draws")) == 6 and int(ui.get("pending_enemy_draws")) == 5, "all eleven opening draws, including pendants, are queued")
	await create_timer(6.3).timeout
	check(not ui.get("draw_animation_active") and not ui.get("action_busy"), "opening deal releases the action lock")
	var end_turn: Button
	for child in ui.get_children():
		if child is Button and child.text == "结束回合" and not child.is_queued_for_deletion():
			end_turn = child
	check(end_turn != null and not end_turn.disabled, "End Turn is enabled after the deal")
	var player: Combatant = manager.get("player")
	player.hand = ["metal_strike"]
	player.energy["metal"] = 1
	ui.call("_refresh")
	check(ui.call("_begin_hand_drag", 0, Vector2(800, 755)), "a payable card can be dragged after the deal")
	print("Opening deal: %d failures" % failures)
	quit(1 if failures > 0 else 0)
