extends SceneTree

var failures := 0
var ui: Control
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func wait_opening(seconds: float = 4.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while ui.opening_active and Time.get_ticks_msec() < deadline: await process_frame
	check(not ui.opening_active, "opening finishes within the batch-animation budget")

func run() -> void:
	ui = load("res://battle/battle_scene.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	var manager: BattleManager = ui.manager
	# Both base pendants add a draw after the initial hands are visible.
	manager.artifacts = {"water_tide_pearl":manager.artifacts["water_tide_pearl"]}
	for seed_value in [2, 0]:
		var began := Time.get_ticks_msec()
		manager.start_battle("ember", "random", seed_value)
		await create_timer(0.65).timeout
		check(manager.phase == "opening_draw" and manager.player.hand.size() == 3 and manager.enemy.hand.size() == 3, "opening base hands are a separate three-card stage")
		check(ui.draw_animation_active and ui.pending_player_draws == 3 and ui.pending_enemy_draws == 3, "both three-card hands fly simultaneously")
		check(ui.action_busy and not manager.play_player_card(0), "opening locks actions until effects and turn resources finish")
		await wait_opening()
		check(Time.get_ticks_msec() - began < 4000, "ten draws including both pendants complete in under four seconds")
		check(manager.player.hand.size() == 5 and manager.enemy.hand.size() == 5, "pendants add one each after the three-plus-one opening and first-turn draw")
		check(not ui.draw_animation_active and not ui.action_busy and ui.pending_player_draws == 0 and ui.pending_enemy_draws == 0, "all opening cards arrive before releasing the action lock")
		for view in ui.hand_cards: check(view.visible, "all player cards are visible after opening")
		for view in ui.enemy_backs: check(view.visible, "all enemy cards are visible after opening")
		if manager.first_side == "enemy":
			check(manager.phase == "enemy_action" and ui.enemy_animating and manager.round_number == 1, "enemy-first games automatically begin the enemy's action in round one")
			manager.enemy.hand.clear()
			var deadline := Time.get_ticks_msec() + 2000
			while manager.phase != "player_action" and Time.get_ticks_msec() < deadline: await process_frame
			check(manager.phase == "player_action" and manager.round_number == 1, "enemy's opening turn hands control to the player's first turn")
			while ui.draw_animation_active: await process_frame
		var end_turn: Button
		for child in ui.get_children():
			if child is Button and child.text == "结束回合" and not child.is_queued_for_deletion(): end_turn = child
		check(end_turn != null and not end_turn.disabled, "End Turn is enabled when the player gains control")
		manager.player.hand.assign(["metal_strike"])
		manager.player.energy["metal"] = 1
		ui._refresh()
		check(ui._begin_hand_drag(0, Vector2(800, 755)), "a payable card can be dragged after either opening order")
		ui._finish_hand_drag(Vector2(800, 755))
	# An upgraded pendant must show its choice after initial cards have arrived.
	manager.load_content()
	manager.random_artifacts_enabled = false
	var deck: Array = manager.decks[0]["cards"].duplicate()
	for seed_value in [2, 0]:
		manager.start_battle("ember", "balanced", seed_value, {"id":"opening_ui", "name":"开局观想", "cards":deck, "artifacts":{"pendant":"water_tide_pearl__2"}})
		var deadline := Time.get_ticks_msec() + 3000
		while ui.choice_dialog == null and Time.get_ticks_msec() < deadline: await process_frame
		check(ui.choice_dialog != null and manager.phase == "battle_start" and manager.round_number == 0, "opening choice appears before the first turn for either order")
		check(ui.pending_player_draws == 1 and ui.pending_enemy_draws == 0, "only the pendant's own extra draw is pending when the choice appears")
		for i in (3 if manager.first_side == "player" else 4): check(ui.hand_cards[i].visible, "initial player cards are already visible beneath the choice")
		ui.choice_dialog._select(0)
		ui.choice_dialog.confirm.pressed.emit()
		await wait_opening()
		check(manager.player.hand.size() == 6 and manager.pending_choice.is_empty() and not ui.action_busy, "confirming opening contemplation finishes the remaining draws and releases the lock")
	# Cancel an old flight by restarting during the three-card batch.
	manager.start_battle("ember", "balanced", 2)
	await create_timer(0.65).timeout
	await manager.start_battle("ember", "balanced", 0)
	check(manager.first_side == "enemy" and manager.phase == "enemy_action" and manager.player.hand.size() == 4 and manager.enemy.hand.size() == 4, "restart during opening animation cannot advance or mutate the new opening")
	manager.battle_generation += 1
	manager.phase = "menu"
	# Let interrupted presentation timers release their tasks while the owner
	# still exists (a card reveal can have 1.45 seconds remaining).
	await create_timer(1.7).timeout
	ui.queue_free()
	await process_frame
	await create_timer(0.8).timeout
	print("Opening deal: simultaneous batches, both orders, AI handoff, choices, locks and restart; %d failures" % failures)
	call_deferred("quit", 1 if failures else 0)
