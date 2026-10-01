extends SceneTree

var failures := 0
var manager: BattleManager
var stages: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func energy(actor: Combatant) -> int:
	var total := 0
	for amount in actor.energy.values(): total += int(amount)
	return total
func present(stage: String) -> void:
	stages.append(stage)
	var first := manager.player if manager.first_side == "player" else manager.enemy
	var second := manager.enemy if first == manager.player else manager.player
	match stage:
		"order": check(manager.player.hand.is_empty() and manager.enemy.hand.is_empty(), "order is decided before opening draws")
		"initial_draw": check(first.hand.size() == 3 and second.hand.size() == 3, "both sides draw exactly three together")
		"second_draw": check(first.hand.size() == 3 and second.hand.size() == 4, "only the second side receives the extra opening card")
		"first_turn": check(first.hand.size() == 4 and second.hand.size() == 4 and energy(first) == 0 and energy(second) == 0 and first.qi == 4 and second.qi == 3, "first turn draws and grants energy only to the first side")
	if stage != "first_turn":
		check(manager.round_number == 0 and energy(first) == 0 and energy(second) == 0 and first.qi == 3 and second.qi == 3, "opening stages grant no natural turn energy")
		check(first.own_turn_count == 0 and second.own_turn_count == 0, "opening stages do not count as turns")

func run() -> void:
	manager = BattleManager.new()
	manager.random_artifacts_enabled = false
	root.add_child(manager)
	manager.opening_presenter = present
	var orders := {}
	for seed_value in 40:
		stages.clear()
		await manager.start_battle("ember", "balanced", seed_value)
		orders[manager.first_side] = true
		check(stages == ["order", "initial_draw", "second_draw", "start_effects", "start_effects", "first_turn"], "opening stages follow the requested sequence")
		check(manager.phase == manager.first_side + "_action" and manager.round_number == 1, "round one belongs to the randomly chosen first side")
		var order := manager.first_side
		var player_hand := manager.player.hand.duplicate()
		var enemy_hand := manager.enemy.hand.duplicate()
		await manager.start_battle("ember", "balanced", seed_value)
		check(manager.first_side == order and manager.player.hand == player_hand and manager.enemy.hand == enemy_hand, "same seed reproduces order and opening cards")
		if order == "player": await manager.end_player_turn()
		else: await manager.enemy_step(-1)
		check(manager.round_number == 1 and manager.player.own_turn_count == 1 and manager.enemy.own_turn_count == 1, "second side's first turn remains in round one")
		if order == "player": await manager.enemy_step(-1)
		else: await manager.end_player_turn()
		check(manager.round_number == 2 and manager.phase == order + "_action", "next round returns to the first side")
	check(orders.size() == 2, "seed coverage includes both player-first and enemy-first games")
	manager.opening_presenter = Callable()
	manager.interactive_choices = true
	var deck: Array = manager.decks[0]["cards"].duplicate()
	var configured := {"id":"opening_flow", "name":"开局时序", "cards":deck, "artifacts":{"pendant":"water_tide_pearl__2"}}
	for seed_value in [2, 0]:
		manager.start_battle("ember", "balanced", seed_value, configured)
		await process_frame
		var player_first := manager.first_side == "player"
		check(manager.phase == "battle_start" and not manager.pending_choice.is_empty(), "opening contemplation pauses before either first turn")
		check(manager.player.hand.size() == (4 if player_first else 5) and manager.enemy.hand.size() == (4 if player_first else 3), "opening draw from pendant follows initial and second-player draws")
		check(energy(manager.player) == 0 and energy(manager.enemy) == 0 and manager.player.qi == 3 and manager.enemy.qi == 3 and manager.round_number == 0, "choice precedes turn resources for either order")
		check(not manager.play_player_card(0) and not manager.artifact_can_activate(manager.player), "opening choice prevents player actions")
		manager.choose_card(0)
		check(manager.pending_choice.is_empty() and manager.phase == manager.first_side + "_action", "choice resumes the correct first side")
		check(manager.player.hand.size() == 6 and manager.enemy.hand.size() == 4, "both orders retain the same final hand count with the upgraded pendant")
	# Restart while an old choice is pending; its continuation must never run.
	manager.start_battle("ember", "balanced", 2, configured)
	await process_frame
	await manager.start_battle("ember", "balanced", 0)
	check(manager.first_side == "enemy" and manager.phase == "enemy_action" and manager.pending_choice.is_empty(), "restart cancels the old opening choice and preserves the new order")
	check(manager.player.hand.size() == 4 and manager.enemy.hand.size() == 4, "old opening continuation adds no cards to the new game")
	manager.queue_free()
	await process_frame
	print("Opening flow: both orders, stages, resources, reproducibility, round rotation, choices and restart; %d failures" % failures)
	quit(1 if failures else 0)
