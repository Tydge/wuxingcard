extends SceneTree

var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func inspect_popup(popup: CardKeywordPopup, side: String) -> void:
	check(popup != null and is_zero_approx(popup.modulate.a), "keyword explanation starts hidden")
	await create_timer(0.36).timeout
	check(is_zero_approx(popup.modulate.a), "keyword explanation waits half a second")
	var saw_fade := false
	var deadline := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if popup.modulate.a > 0 and popup.modulate.a < 1: saw_fade = true
		if is_equal_approx(popup.modulate.a, 1): break
	check(saw_fade, "keyword explanation quickly fades in")
	check(is_equal_approx(popup.modulate.a, 1), "keyword explanation becomes fully visible")
	check(popup.placement_side == side, "keyword explanation chooses the larger free side (%s / %s)" % [popup.placement_side, side])
	check(popup.position.x >= 0 and popup.position.x + popup.size.x <= 1600 and popup.position.y + popup.size.y <= 900, "keyword explanation stays inside the viewport")

func run() -> void:
	output = ProjectSettings.globalize_path("res://work/keyword_previews")
	DirAccess.make_dir_recursive_absolute(output)
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	var manager: BattleManager = ui.get("manager")
	var menu: MainMenu
	for child in ui.get_children():
		if child is MainMenu: menu = child
	menu.call("_show_collection")
	await process_frame
	menu.call("_open_inspector", manager.cards["metal_chime_card"], menu.card_nodes[0])
	await inspect_popup(menu.inspect_keywords, "right")
	check(menu.inspect_keywords.explanations.size() == 3, "summon card explains resistance, counter and charge")
	await shot("collection_summon")
	var closing := menu.inspect_keywords
	menu.call("_close_inspector")
	check(not closing.visible and menu.inspect_keywords == null, "collecting the card immediately hides keywords")
	await create_timer(0.4).timeout
	# Closing during the delay must cancel the pending reveal.
	menu.call("_open_inspector", manager.cards["fire_brand"], menu.card_nodes[0])
	await create_timer(0.1).timeout
	closing = menu.inspect_keywords
	menu.call("_close_inspector")
	check(not closing.visible, "closing before half a second prevents a late tooltip")
	await create_timer(0.6).timeout
	ui.call("_start_battle")
	await create_timer(5.6).timeout
	manager.player.hand[0] = "fire_brand"
	manager.player.hand[1] = "metal_ward"
	ui.call("_refresh")
	ui.call("_show_hover_preview", 0)
	var popup: CardKeywordPopup = ui.get("hover_keywords")
	await inspect_popup(popup, "right")
	check(popup.explanations[0]["title"] == "灼伤 X", "hand hover explains burn")
	await shot("hand_status")
	ui.call("_clear_hover_preview")
	check(not popup.visible and ui.get("hover_keywords") == null, "hand exit hides keywords immediately")
	# Rapid switches start a fresh delay.
	ui.call("_show_hover_preview", 0)
	await create_timer(0.1).timeout
	ui.call("_show_hover_preview", 1)
	popup = ui.get("hover_keywords")
	check(popup.explanations[0]["title"] == "护盾 X" and is_zero_approx(popup.modulate.a), "switching cards replaces keywords and resets the delay")
	ui.call("_clear_hover_preview")
	for side in ["player", "enemy"]:
		var owner := manager.player if side == "player" else manager.enemy
		owner.summons[0] = Summon.new()
		owner.summons[0].setup(manager.summon_templates["metal_chime"])
		ui.call("_refresh")
		ui.call("_on_summon_hover", side, 0)
		popup = ui.get("hover_keywords")
		await inspect_popup(popup, "right" if side == "player" else "left")
		await shot(side + "_summon")
		ui.call("_on_summon_exit", side, 0)
		check(not popup.visible, "summon exit hides keywords immediately")
	# The matchup label reaches the same animated damage number used by heroes.
	manager.apply_summon_damage(manager.player, manager.enemy, 0, 4, "fire")
	var found := false
	for child in ui.get("fx_layer").get_children():
		if child is DamageNumber:
			found = found or child.matchup == "克制"
	check(found, "summon damage number shows elemental counter")
	await shot("summon_counter")
	manager.apply_summon_damage(manager.player, manager.enemy, 0, 4, "metal")
	found = false
	for child in ui.get("fx_layer").get_children():
		if child is DamageNumber: found = found or child.matchup == "抵抗"
	check(found, "summon damage number shows elemental resistance")
	print("Card keyword UI: delayed reveal, instant removal, hand/summon/collection and matchup; %d failures" % failures)
	quit(1 if failures > 0 else 0)
