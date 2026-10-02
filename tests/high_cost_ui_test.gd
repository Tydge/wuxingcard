extends SceneTree

var ui: Control
var failures := 0
var output := "res://work/expansion_20261002"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func tap(point: Vector2) -> void:
	point = ui.get_global_transform_with_canvas() * point
	for pressed in [true, false]:
		if PlatformUI.is_touch():
			var event := InputEventScreenTouch.new()
			event.position = point; event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
			root.push_input(event, true)
		await process_frame

func wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 9000
	while ui.action_busy and Time.get_ticks_msec() < deadline: await process_frame
	check(not ui.action_busy, "targeted summon action completes within its normal presentation window")

func shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(("touch_" if PlatformUI.is_touch() else "pc_") + name + ".png")))

func creature(owner: Combatant, slot: int, id: String) -> Summon:
	var summon := Summon.new(); summon.setup(ui.manager.summon_templates[id]); owner.summons[slot] = summon
	ui.manager._sync_cost_auras()
	return summon

func run() -> void:
	ui = load("res://battle/battle_scene.tscn").instantiate()
	ui.endless_save_path = "user://expansion_ui_%s.json" % ("touch" if PlatformUI.is_touch() else "pc")
	DirAccess.remove_absolute(ui.endless_save_path)
	root.add_child(ui)
	await process_frame
	for actor: Combatant in [ui.manager.player, ui.manager.enemy]:
		actor.max_hp = 80
		actor.setup("player" if actor == ui.manager.player else "ember", "测试", [], ui.manager.rng)
		actor.draw_pile.assign(["metal_strike", "water_strike", "wood_heal"])
	ui.manager.phase = "player_action"
	ui.manager.selected_enemy_id = "ember"
	ui.manager.player.hand.assign(["metal_rift_mantis_card"])
	ui.manager.player.energy["metal"] = 4
	ui._refresh()
	await process_frame
	ui._play_card_from(0, Vector2(780, 710), {"kind":"slot", "slot":0})
	await process_frame
	check(is_instance_valid(ui.summon_target_layer) and ui.action_busy and ui.manager.player.summons[0] == null and ui.manager.player.energy["metal"] == 4, "slot drop opens entrance aim before spending")
	await shot("entrance_target")
	# Native Android may re-enter cancellation while hiding the touch overlay.
	var target_layer: Control = ui.summon_target_layer
	target_layer.visibility_changed.connect(func():
		if not target_layer.visible: ui._cancel_summon_target(false))
	await tap(Vector2(800, 820))
	check(ui.pending_summon_selection.is_empty() and not ui.action_busy and ui.manager.player.hand == ["metal_rift_mantis_card"] and ui.manager.player.energy["metal"] == 4 and ui.manager.player.summons[0] == null, "real mouse/touch cancellation does not summon or spend")
	ui._confirm_summon_target({"kind":"hero", "side":"enemy"})
	check(ui.manager.player.energy["metal"] == 4, "stale confirmation cannot play a cancelled card")
	ui._play_card_from(0, Vector2(780, 710), {"kind":"slot", "slot":0})
	await process_frame
	await tap(ui._target_point("enemy", {"kind":"hero", "side":"enemy"}))
	await wait_idle()
	check(ui.manager.player.summons[0] != null and ui.manager.player.summons[0].max_hp == 18 and ui.manager.player.energy["metal"] == 0 and ui.manager.enemy.hp == 70, "real aim confirms one summon and selected entrance damage")
	await shot("new_summon")
	# Color metadata is rendered by the same factory used by the hand/inspection.
	creature(ui.manager.enemy, 0, "earth_law_lion")
	ui.manager.player.add_status("charge", 2, 0)
	ui.manager.player.hand.assign(["metal_strike", "earth_stacked_peak", "wood_dew_bloom_card"])
	ui.manager.player.add_status("shield", 25, 0)
	ui.manager._equip_loadout(ui.manager.player, {"pendant":"earth_origin_jade"})
	ui._refresh(); await process_frame
	var shown: Dictionary = ui.manager.display_card(ui.manager.player, ui.manager.cards["metal_strike"])
	var card: Control = ui._card_front(shown, Vector2(240,336)); card.position = Vector2(500,220); ui.fx_layer.add_child(card)
	check(card.get_node("Cost").get_theme_color("font_color") == Color("#ff817a"), "taxed cost has red glyphs")
	check(card.get_node("Description").text.contains("[color=#79df8a]12[/color]"), "increased attack is green inside the actual description")
	var reduced: Dictionary = ui.manager.cards["water_strike"].duplicate(true); reduced["printed_cost"] = 2; reduced["cost"] = 1
	var cheap: Control = ui._card_front(reduced, Vector2(240,336)); cheap.position = Vector2(760,220); ui.fx_layer.add_child(cheap)
	check(cheap.get_node("Cost").get_theme_color("font_color") == Color("#79df8a"), "reduced cost is green")
	var weakened: Dictionary = ui.manager.cards["metal_strike"].duplicate(true)
	ui.manager.player.remove_status("charge"); ui.manager.player.add_status("weak", 2, 0)
	var weak_display: Dictionary = ui.manager.display_card(ui.manager.player, weakened)
	check(weak_display["rich_text"].contains("[color=#ff817a]8[/color]"), "weakened attack has red markup")
	var bloom: Dictionary = ui.manager.display_card(ui.manager.player, ui.manager.cards["wood_dew_bloom_card"])
	check(bloom["summon_hp"] > bloom["printed_summon_hp"], "summon badge receives the spawn growth bonus")
	var growing: Control = ui._card_front(bloom, Vector2(240,336)); growing.position = Vector2(1020,220); ui.fx_layer.add_child(growing)
	await process_frame
	await shot("number_colors")
	card.queue_free(); cheap.queue_free(); growing.queue_free()
	# An isolated run gives stable balances/prices instead of relying on random progression.
	var run := EndlessRun.new(ui.manager.cards, ui.manager.artifacts, ui.manager.enemies, ui.endless_save_path)
	run.new_run(731)
	run.state["phase"] = "rest"; run.state["wins"] = 1; run.state["gold"] = 240; run.state["last_reward"] = 100
	run._roll_shop(run._random())
	var screen := EndlessScreen.new(); screen.configure(run, ui._card_front, ui.manager.summon_templates); screen.theme = ui.theme
	ui.hide(); root.add_child(screen)
	await create_timer(0.2).timeout
	check(not screen.content.find_children("SpiritMoney*", "", true, false).is_empty(), "rest balances and rewards use the coin row")
	await shot("coin_rest")
	screen._navigate("shop"); await create_timer(0.2).timeout
	check(screen.shop_buttons.size() == 7 and screen.shop_buttons.all(func(button): return button.icon != null and button.has_meta("currency_amount") and not button.text.contains("灵钱")), "all shop prices use an icon and numeric price")
	await shot("coin_shop")
	screen._inspect_shop(0, screen.item_views[0]); await process_frame
	check(screen.action_button.icon != null and screen.action_button.get_meta("currency_amount") == 30, "purchase modal keeps the exact price with a coin")
	await shot("coin_purchase")
	screen.queue_free(); ui.queue_free(); await process_frame
	DirAccess.remove_absolute(run.path)
	print("Expansion UI (%s): real entrance cancellation/confirmation, dynamic numeric colors and coin prices; %d failures" % ["touch" if PlatformUI.is_touch() else "PC", failures])
	quit(1 if failures else 0)
