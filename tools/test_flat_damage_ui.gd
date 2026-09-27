extends SceneTree

var failures := 0
var ui: Control
var manager: BattleManager
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

func labels(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label: result.append(node.text)
	for child in node.get_children(): result.append_array(labels(child))
	return result

func run() -> void:
	output = ProjectSettings.globalize_path("res://work/flat_damage_previews")
	DirAccess.make_dir_recursive_absolute(output)
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	ui = current_scene
	ui.call("_start_test_battle")
	await create_timer(5.8).timeout
	manager = ui.get("manager")
	for actor in [manager.player, manager.enemy]:
		actor.hp = 80
		actor.statuses.clear()
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
	manager.player.hand = ["metal_twin_blades", "metal_temper", "earth_stone_body", "fire_clear_weak", "water_tide_scroll", "fire_all_targets"]
	manager.player.energy["metal"] = 3
	manager.player.add_status("strong_attack", 3, 0)
	manager.player.add_status("strong_defense", 3, 0)
	manager.enemy.add_status("weak_attack", 2, 0)
	manager.enemy.add_status("weak_defense", 2, 0)
	ui.call("_refresh")
	ui.call("_show_hover_preview", 1)
	check(is_instance_valid(ui.get("hover_keywords")) and ui.get("hover_keywords").explanations[0]["title"] == "强攻 X", "new attack keyword appears for the buff card")
	await create_timer(0.7).timeout
	await shot("new_states_and_keyword")
	ui.call("_clear_hover_preview")
	manager.enemy.statuses.clear()
	var card: Dictionary = manager.cards["metal_twin_blades"]
	ui.call("_show_drag_hints", card)
	ui.call("_update_drag_hints", card, ui.call("_anchor", "enemy"))
	check(ui.get("damage_preview_label").text == "预计伤害 13+12=25", "drag preview displays every decreasing hit and its sum")
	var own_selection: Dictionary = ui.call("_drop_selection", card, ui.call("_anchor", "player"))
	check(own_selection.get("kind") == "invalid", "ordinary damage cannot target its own hero")
	await shot("multi_hit_preview")
	ui.call("_clear_drag_hints")
	var fx: BattleFX = ui.get("battle_fx")
	fx.clear_effects()
	ui.call("_cast_card", card, "player", ui.call("_anchor", "enemy"))
	await create_timer(0.22).timeout
	check(fx.active.size() == 2, "two-hit spell presents two successive casts")
	fx.clear_effects()
	manager.play_player_card(0, {"kind":"hero"})
	await create_timer(0.25).timeout
	check(labels(ui).has("-13") and labels(ui).has("-12"), "both damage callouts remain visible for consecutive hits")
	await shot("multi_hit_result")
	# Global damage can be released on either side and marks every affected unit.
	manager.player.statuses.clear()
	for actor in [manager.player, manager.enemy]:
		actor.hp = 80
		for element in BattleRules.ELEMENTS: actor.energy[element] = 0
		for slot in 3:
			actor.summons[slot] = Summon.new()
			actor.summons[slot].setup(manager.summon_templates["water_spring"])
	manager.player.energy["fire"] = 2
	ui.call("_refresh")
	card = manager.cards["fire_all_targets"]
	ui.call("_show_drag_hints", card)
	ui.call("_update_drag_hints", card, ui.call("_anchor", "player"))
	var hints: Array = ui.get("drag_hints")
	check(hints.size() == 8, "global spell shows both heroes and all six summons")
	for hint in hints: check(hint.highlighted, "global spell highlights every target together")
	check(ui.get("damage_preview_label").text == "预计伤害 12", "self damage preview uses fire resistance after payment")
	own_selection = ui.call("_drop_selection", card, ui.call("_anchor", "player"))
	check(own_selection == {"kind":"hero", "side":"player"}, "global spell accepts its own hero as the release point")
	await shot("global_targets")
	fx.clear_effects()
	ui.call("_cast_card", card, "player", ui.call("_anchor", "player"))
	check(fx.active.size() == 8, "global spell sends effects to every affected unit")
	fx.clear_effects()
	ui.call("_clear_drag_hints")
	manager.player.hp = 12
	manager.enemy.hp = 12
	manager.player.hand = ["fire_all_targets"]
	ui.call("_refresh")
	await ui.call("_play_card_from", 0, Vector2(800, 730), own_selection)
	check(manager.phase == "draw" and labels(ui).has("平 局"), "actual card presentation opens the draw result")
	for actor in [manager.player, manager.enemy]:
		for summoned: Summon in actor.summons: check(summoned.hp == 3, "all summon hits finish before the draw result")
	await shot("draw_result")
	manager.phase = "menu"
	ui.call("_refresh")
	await process_frame
	var menu: MainMenu
	for child in ui.get_children():
		if child is MainMenu: menu = child
	menu.mode_buttons["collection"].pressed.emit()
	menu.filter_buttons["fire"].pressed.emit()
	await process_frame
	var source: Control
	for i in menu.filtered_cards.size():
		if menu.filtered_cards[i]["id"] == "fire_clear_weak": source = menu.card_nodes[i]
	check(source != null, "new fire card appears in the collection")
	menu.call("_open_inspector", manager.cards["fire_clear_weak"], source)
	await create_timer(0.75).timeout
	check(labels(menu).has("虚弱 X") and labels(menu).has("蓄力 X"), "collection inspection explains removed and granted states")
	await shot("cleansing_collection")
	menu.call("_close_inspector")
	await create_timer(0.4).timeout
	print("Flat damage UI: status icons, delayed keywords, multi-hit preview, all-eight targeting and draw result; %d failures" % failures)
	quit(1 if failures > 0 else 0)
