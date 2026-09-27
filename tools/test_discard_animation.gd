extends SceneTree

var failures := 0
var ui: Control
var manager: BattleManager
var expected_views := {}
var removed: Array[Dictionary] = []
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func prepare(player_hand: Array[String], enemy_hand: Array[String]) -> void:
	ui.call("_clear_discard_animations")
	manager.phase = "player_action"
	ui.set("action_busy", false)
	for actor in [manager.player, manager.enemy]:
		actor.hp = 80
		actor.statuses.clear()
		actor.discard_pile.clear()
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.player.hand = player_hand
	manager.enemy.hand = enemy_hand
	ui.call("_refresh")
	expected_views = {"player": ui.get("hand_cards").duplicate(), "enemy": ui.get("enemy_backs").duplicate()}
	removed.clear()

func on_removed(side: String, card_id: String, index: int, reason: String) -> void:
	var actor: Combatant = manager.player if side == "player" else manager.enemy
	check(actor.hand[index] == card_id, "removal event preserves identity before the hand changes")
	var original: Control = expected_views[side][index]
	expected_views[side].remove_at(index)
	removed.append({"reason": reason, "card": card_id, "origin": original.position})
	if reason == "discard":
		check(ui.get("discard_cards").back() == original, "the discarded prefab is the exact original copy, not another duplicate")
		check(original.get_parent() == ui.get("fx_layer"), "discard survives the hand and HUD refresh")
		check(original.mouse_filter == Control.MOUSE_FILTER_IGNORE, "flying discard cannot intercept input")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	output = ProjectSettings.globalize_path("res://work/discard_previews")
	DirAccess.make_dir_recursive_absolute(output)
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	ui.call("_start_test_battle")
	await create_timer(5.8).timeout
	manager = ui.get("manager")
	manager.hand_card_removed.connect(on_removed)
	# The played middle card leaves first; duplicate copies must keep their slots.
	prepare(["metal_strike", "earth_mountain_seal", "metal_strike", "fire_raven_card"], ["metal_strike"])
	manager.player.energy["earth"] = 3
	for seed_value in 100:
		manager.rng.seed = seed_value
		if manager.rng.randi_range(0, 2) == 2:
			manager.rng.seed = seed_value
			break
	ui.set("player_hidden_index", 1)
	ui.call("_refresh")
	expected_views["player"] = ui.get("hand_cards").duplicate()
	ui.set("player_hidden_index", -1)
	check(manager.play_player_card(1, {"kind": "hero"}), "mountain seal can be played")
	check(removed.size() == 2 and removed[0]["reason"] == "play" and removed[1]["card"] == "fire_raven_card", "playing a card is distinct from discarding its chosen remaining card")
	var flying: Control = ui.get("discard_cards")[0]
	var origin: Vector2 = removed[1]["origin"]
	check(flying is SummonCardView, "summon discard retains its external health badge")
	await create_timer(0.32).timeout
	check(flying.position.y < origin.y - 65 and flying.modulate.a > 0 and flying.modulate.a < 1, "player discard rises while gradually fading")
	check(flying.size.is_equal_approx(Vector2(152, 212.8)) and flying.scale == Vector2.ONE, "discard retains the normal card size")
	await shot("player_summon_discard")
	await create_timer(0.4).timeout
	check(ui.get("discard_cards").is_empty() and not is_instance_valid(flying), "completed discard frees the card")
	# An opponent discard must retain the inverted card back and move into view.
	prepare(["earth_quake"], ["metal_strike", "metal_strike", "fire_lantern_card"])
	manager.player.energy["earth"] = 2
	check(manager.play_player_card(0), "opponent-discard spell can be played")
	flying = ui.get("discard_cards")[0]
	origin = removed[1]["origin"]
	check(flying is CardBack and is_equal_approx(flying.get_child(0).rotation_degrees, 180.0), "enemy discard preserves the upside-down card back")
	await create_timer(0.32).timeout
	check(flying.position.y > origin.y + 65 and flying.modulate.a < 1, "enemy discard mirrors the lift toward the battlefield")
	await shot("enemy_discard")
	await create_timer(0.4).timeout
	# Multiple synchronous removals must animate different originals in order.
	prepare(["metal_strike", "metal_strike", "metal_strike"], ["metal_strike"])
	manager._resolve_effect(manager.player, manager.enemy, {"type": "discard", "target": "self", "amount": 5}, "earth")
	manager.changed.emit()
	check(manager.player.hand.is_empty() and manager.player.discard_pile.size() == 3 and ui.get("discard_cards").size() == 3, "multi-discard stops at an empty hand without losing animations")
	await create_timer(0.95).timeout
	check(ui.get("discard_cards").is_empty(), "all staggered discards finish")
	# Leaving a battle during the animation removes all floating cards immediately.
	prepare(["metal_strike"], ["metal_strike"])
	manager._resolve_effect(manager.player, manager.enemy, {"type": "discard", "target": "self", "amount": 1}, "earth")
	flying = ui.get("discard_cards")[0]
	manager.phase = "menu"
	ui.call("_refresh")
	check(ui.get("discard_cards").is_empty() and not flying.visible, "returning to the menu clears the in-flight discard")
	await process_frame
	await create_timer(0.7).timeout
	check(not is_instance_valid(flying), "menu cleanup frees the bound tween and prefab safely")
	print("Discard animation: exact slots, duplicates, self/opponent discard, summon prefab, fade, multi-discard and menu cleanup; %d failures" % failures)
	quit(1 if failures > 0 else 0)
