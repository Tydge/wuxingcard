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
	await create_timer(5.5).timeout
	var manager: BattleManager = ui.get("manager")
	manager.player.hand[0] = "metal_furnace_card"
	manager.player.energy["metal"] = 3
	ui.call("_refresh")
	var slot_rect: Rect2 = ui.call("_summon_slot_rect", "player", 0)
	await _drag(ui, 0, slot_rect.get_center())
	await create_timer(3.9).timeout
	if manager.player.summons[0] == null or manager.player.summons[0].hp != 10:
		push_error("Summon drag did not place a 10-HP summon in the selected slot")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://work/summon_previews")
	DirAccess.make_dir_recursive_absolute(output)
	await _shot(output.path_join("player_summon.png"))
	manager.enemy.summons[1] = Summon.new()
	manager.enemy.summons[1].setup(manager.summon_templates["wood_seedling"])
	manager.player.hand[0] = "fire_edge"
	manager.player.energy["fire"] = 3
	ui.call("_refresh")
	var before := manager.player.hand.size()
	await _drag(ui, 0, Vector2(800, 400))
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
	if manager.enemy.summons[1] != null or manager.enemy.hp != hero_hp:
		push_error("Selected summon did not take damage independently from its owner")
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
