extends SceneTree

# Graphical interaction check for summon placement and selected damage targets.
# Godot --path . --script res://tools/test_summon_drag.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	var ui: Control = current_scene
	ui.call("_start_battle")
	await create_timer(0.2).timeout
	if not is_instance_valid(ui.get("turn_notice")):
		push_error("Turn announcement did not appear")
		quit(1)
		return
	await create_timer(5.5).timeout
	if is_instance_valid(ui.get("turn_notice")):
		push_error("Turn announcement did not fade away")
		quit(1)
		return
	var manager: BattleManager = ui.get("manager")
	manager.player.hand[0] = "metal_furnace_card"
	manager.player.energy["metal"] = 2
	ui.call("_refresh")
	var summon_card: Control = ui.get("hand_cards")[0]
	if not summon_card is SummonCardView:
		push_error("Summon hand card did not use its dedicated prefab")
		quit(1)
		return
	var health_badge: Control = summon_card.get_child(summon_card.get_child_count() - 1)
	if summon_card.clip_contents or health_badge.position.x + health_badge.size.x <= summon_card.size.x:
		push_error("Summon health badge is not hanging outside the card frame")
		quit(1)
		return
	var description: Label
	for child in summon_card.get_children():
		if child is Label and child.text.contains("回合开始"):
			description = child
			break
	if description == null or absf(description.position.x + description.size.x / 2.0 - summon_card.size.x / 2.0) > 1.0:
		push_error("Summon description is not centred in the card")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://work/summon_previews")
	DirAccess.make_dir_recursive_absolute(output)
	await _shot(output.path_join("summon_card_in_hand.png"))
	var slot_rect: Rect2 = ui.call("_summon_slot_rect", "player", 0)
	await _drag(ui, 0, slot_rect.get_center())
	await create_timer(3.9).timeout
	if manager.player.summons[0] == null or manager.player.summons[0].hp != 15:
		push_error("Summon drag did not place a 15-HP summon in the selected slot")
		quit(1)
		return
	var field_view: SummonView
	var actor_layer: Control = ui.get("actor_layer")
	for child in actor_layer.get_children():
		if child is SummonView:
			field_view = child
			break
	if field_view == null:
		push_error("Summon battlefield view was not created")
		quit(1)
		return
	var portrait: TextureRect = field_view.get_child(0)
	var initial_y := portrait.position.y
	await create_timer(0.45).timeout
	if absf(portrait.position.y - initial_y) < 0.5:
		push_error("Summon portrait did not float")
		quit(1)
		return
	var player_standee: Control = ui.get("standee_nodes")["player"]
	ui.call("_refresh")
	await process_frame
	if ui.get("standee_nodes")["player"] != player_standee or ui.get("summon_views")["player_0"] != field_view:
		push_error("Refreshing the hand recreated the battlefield actors")
		quit(1)
		return
	ui.call("_on_action_event", "测试受击", "player", "damage", "fire", 7)
	await create_timer(0.12).timeout
	var plain_number := _latest_damage_number(ui.get("fx_layer"))
	if player_standee.modulate == Color.WHITE or plain_number == null or plain_number.matchup != "" or plain_number.get_child_count() != 1:
		push_error("Hero hit feedback or damage number did not appear")
		quit(1)
		return
	await _shot(output.path_join("hero_hit.png"))
	await create_timer(1.0).timeout
	ui.call("_on_action_event", "测试受击 · 克制", "player", "damage", "fire", 8)
	await create_timer(0.12).timeout
	var strong_number := _latest_damage_number(ui.get("fx_layer"))
	if strong_number == null or strong_number.matchup != "克制" or strong_number.get_child_count() != 2:
		push_error("Element advantage was not placed inside the damage number")
		quit(1)
		return
	await _shot(output.path_join("advantage_hit.png"))
	await create_timer(1.0).timeout
	ui.call("_on_action_event", "测试受击 · 抵抗", "player", "damage", "water", 4)
	await create_timer(0.12).timeout
	var resisted_number := _latest_damage_number(ui.get("fx_layer"))
	if resisted_number == null or resisted_number.matchup != "抵抗" or resisted_number.get_child_count() != 2:
		push_error("Element resistance was not placed inside the damage number")
		quit(1)
		return
	await _shot(output.path_join("resisted_hit.png"))
	await create_timer(1.0).timeout
	ui.call("_on_summon_event", "player", 0, "damage", "metal", 5)
	await create_timer(0.12).timeout
	if field_view.modulate == Color.WHITE:
		push_error("Summon hit feedback did not appear")
		quit(1)
		return
	await _shot(output.path_join("summon_hit.png"))
	await _shot(output.path_join("player_summon.png"))
	ui.call("_on_summon_hover", "player", 0)
	await process_frame
	var enlarged: Control = ui.get("hover_preview")
	if not enlarged is SummonCardView:
		push_error("Hovering a battlefield summon did not show its enlarged card")
		quit(1)
		return
	await _shot(output.path_join("summon_hover.png"))
	ui.call("_on_summon_exit", "player", 0)
	manager.enemy.summons[1] = Summon.new()
	manager.enemy.summons[1].setup(manager.summon_templates["wood_seedling"])
	manager.player.hand[0] = "fire_strike"
	manager.player.energy["fire"] = 3
	ui.call("_refresh")
	await _shot(output.path_join("both_summons.png"))
	var before := manager.player.hand.size()
	await _drag(ui, 0, Vector2(800, 250))
	await process_frame
	if manager.player.hand.size() != before:
		push_error("Damage card played without a selected target")
		quit(1)
		return
	var enemy_rect: Rect2 = ui.call("_summon_slot_rect", "enemy", 1)
	var hero_hp := manager.enemy.hp
	var preview := await _drag(ui, 0, enemy_rect.get_center(), true)
	if preview != "预计伤害 10":
		push_error("Expected summon damage preview 10, got: " + preview)
		quit(1)
		return
	await create_timer(3.9).timeout
	if manager.enemy.summons[1] == null or manager.enemy.summons[1].hp != 5 or manager.enemy.hp != hero_hp:
		push_error("Selected summon did not take damage independently from its owner")
		quit(1)
		return
	manager.player.hand[0] = "fire_strike"
	manager.player.energy["fire"] = 1
	ui.call("_refresh")
	var finishing_preview := await _drag(ui, 0, enemy_rect.get_center(), true)
	if finishing_preview != "预计伤害 5":
		push_error("Finishing preview must show the summon's remaining five HP")
		quit(1)
		return
	await create_timer(3.9).timeout
	if manager.enemy.summons[1] != null or manager.enemy.hp != hero_hp:
		push_error("Second basic spell did not destroy only the selected summon")
		quit(1)
		return
	await _shot(output.path_join("after_attack.png"))
	var multi_card: Dictionary = manager.cards["fire_strike"].duplicate(true)
	multi_card["id"] = "test_multi"
	multi_card["name"] = "测试连击"
	multi_card["cost"] = 0
	multi_card["effects"] = [
		{"type": "damage", "element": "fire", "amount": 3},
		{"type": "damage", "element": "fire", "amount": 2},
		{"type": "damage", "element": "fire", "amount": 1}]
	manager.cards["test_multi"] = multi_card
	manager.player.hand[0] = "test_multi"
	for element in BattleRules.ELEMENTS:
		manager.enemy.energy[element] = 0
	ui.call("_refresh")
	var multi_before := manager.enemy.hp
	var multi_preview := await _drag(ui, 0, Vector2(1308, 450), true, "multi_damage_preview.png")
	if multi_preview != "预计伤害 3+2+1=6":
		push_error("Expected segmented multi-hit preview, got: " + multi_preview)
		quit(1)
		return
	await create_timer(3.9).timeout
	if manager.enemy.hp != multi_before - 6:
		push_error("Multi-hit result did not match the preview")
		quit(1)
		return
	print("Summon drag and damage targeting passed")
	quit()

func _drag(ui: Control, index: int, destination: Vector2, read_preview: bool = false, preview_file: String = "damage_preview.png") -> String:
	var cards: Array = ui.get("hand_cards")
	var window_scale := Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	Input.warp_mouse((cards[index].position + Vector2(75, 80)) * window_scale)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	ui.call("_on_hand_input", press, index)
	Input.warp_mouse(destination * window_scale)
	await process_frame
	var motion := InputEventMouseMotion.new()
	ui.call("_input", motion)
	var preview := ""
	if read_preview:
		var label: Label = ui.get("damage_preview_label")
		preview = label.text if label != null else ""
		await _shot(ProjectSettings.globalize_path("res://work/summon_previews/" + preview_file))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	ui.call("_input", release)
	return preview

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _latest_damage_number(layer: Control) -> DamageNumber:
	for index in range(layer.get_child_count() - 1, -1, -1):
		var child := layer.get_child(index)
		if child is DamageNumber:
			return child
	return null
