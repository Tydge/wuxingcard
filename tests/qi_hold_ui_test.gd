extends SceneTree

var failures := 0
var ui: Control
var assertions := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)
func touch(point: Vector2, pressed: bool, canceled: bool = false, finger: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = ui.get_global_transform_with_canvas() * point
	event.index = finger
	event.pressed = pressed
	event.canceled = canceled
	ui._handle_touch(event)
func region(kind: String, side: String = "player") -> Dictionary:
	for entry in ui.energy_touch_regions + ui.status_touch_regions + ui.deck_touch_regions + ui.qi_touch_regions:
		if entry.get("kind", "status") == kind and entry.get("side", "player") == side: return entry
	return {}
func hold_release(entry: Dictionary, text: String) -> void:
	var point: Vector2 = entry.rect.get_center()
	var before: int = ui.manager.player.qi
	touch(point, true)
	check(not ui.touch_inspecting, "press waits for hold: " + text)
	await create_timer(0.51).timeout
	check(ui.touch_inspecting and is_instance_valid(ui.hover_preview), "hold shows explanation: " + text)
	check(ui.manager.player.qi == before, "hold never spends qi: " + text)
	touch(point, false)
	check(not ui.touch_inspecting and not is_instance_valid(ui.hover_preview), "release closes explanation: " + text)
	check(ui.manager.player.qi == before, "release after hold never converts: " + text)
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://work/qi_ui")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
func run() -> void:
	ui = load("res://battle/battle_scene.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.manager.random_artifacts_enabled = false
	await ui.manager.start_battle("ember", "random", 2)
	ui.manager.battle_generation += 1
	ui.manager.phase = "player_action"
	ui.enemy_animating = false
	ui.action_busy = false
	await create_timer(5.5).timeout
	ui.manager._equip_loadout(ui.manager.enemy, {"implement":"metal_thunder_ruler"})
	ui.manager.enemy.add_status("regen", 2, 0)
	ui.manager.player.qi = 20
	ui.manager.player.add_status("poison", 2, 0)
	ui.manager.player.add_status("lock", 1, 2, "wood")
	ui.manager.player.add_status("shield", 5, 0)
	ui._refresh()
	await process_frame
	check(ui.qi_touch_regions.size() == 2 and ui.deck_touch_regions.size() == 2, "both HUDs expose qi and deck help")
	var qi_control: Control = ui.get_node_or_null("Board/PlayerHUD/QiBadge_player")
	# Find by name independently of presentation hierarchy.
	qi_control = ui.find_child("QiBadge_player", true, false)
	check(qi_control != null and qi_control.position.x < 84 and qi_control.tooltip_text.contains("真气"), "flame and number sit left of metal with desktop tooltip")
	var enemy_qi: Control = ui.find_child("QiBadge_enemy", true, false)
	check(enemy_qi != null and enemy_qi.position.x >= 378 and enemy_qi.position.y > 82, "enemy qi sits beneath right portrait")
	await shot("qi_" + ("touch" if PlatformUI.is_touch() else "desktop"))
	var entry := region("energy")
	var point: Vector2 = entry.rect.get_center()
	var before: int = ui.manager.player.qi
	touch(point, true)
	check(ui.manager.player.qi == before, "touch down does not convert")
	touch(point, false)
	check(ui.manager.player.qi == before - 1 and ui.manager.player.energy["metal"] == 1, "short touch release converts exactly once")
	await hold_release(region("energy"), "own energy")
	await hold_release(region("energy", "enemy"), "enemy energy")
	if PlatformUI.is_touch(): await hold_release(region("status"), "status")
	await hold_release(region("deck"), "deck/fatigue")
	await hold_release(region("qi"), "stored qi")
	if PlatformUI.is_touch():
		# Native Android can update mouse hover before delivering the touch press.
		point = region("status", "enemy").rect.get_center()
		var motion := InputEventMouseMotion.new()
		motion.device = InputEvent.DEVICE_ID_EMULATION
		motion.position = ui.get_global_transform_with_canvas() * point
		root.push_input(motion, true)
		await process_frame
		check(not ui.touch_inspecting, "touch mouse hover cannot open a weapon over an enemy status")
		var native_touch := InputEventScreenTouch.new()
		native_touch.position = motion.position
		native_touch.pressed = true
		root.push_input(native_touch, true)
		await create_timer(0.51).timeout
		check(ui.touch_inspecting and ui.hover_preview.get_child(0) is Label and ui.hover_preview.get_child(0).text.contains("再生"), "enemy status with equipped weapon opens its own hold explanation")
		ui._show_artifact_preview("enemy", "implement")
		check(ui.hover_preview.get_child(0) is Label, "artifact preview cannot replace a held rule explanation")
		native_touch.pressed = false
		root.push_input(native_touch, true)
		check(not ui.touch_inspecting, "equipped enemy status closes on native release")

	point = region("energy").rect.get_center()
	before = ui.manager.player.qi
	touch(point, true)
	touch(point, false, true)
	check(ui.manager.player.qi == before, "cancelled tap does not convert")
	touch(point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = ui.get_global_transform_with_canvas() * (point + Vector2(40, 0))
	ui._handle_touch(drag)
	await create_timer(0.51).timeout
	touch(point, false)
	check(not ui.touch_inspecting and ui.manager.player.qi == before, "moving off cancels hold and conversion")
	touch(point, true)
	await create_timer(0.2).timeout
	touch(point, false)
	before = ui.manager.player.qi
	touch(point, true)
	await create_timer(0.28).timeout
	check(not ui.touch_inspecting, "old timer cannot prematurely show a new hold with same finger")
	touch(point, false)
	check(ui.manager.player.qi == before - 1, "second quick tap converts once")
	point = region("deck").rect.get_center()
	touch(point, true)
	await create_timer(0.51).timeout
	ui._request_back()
	touch(point, false)
	check(not ui.touch_inspecting and ui.touch_rule_control.is_empty(), "Back cancels held help and pending release")
	point = region("energy").rect.get_center()
	touch(point, true)
	ui._refresh()
	await create_timer(0.51).timeout
	check(ui.touch_inspecting == PlatformUI.is_touch(), "touch hold survives an ordinary battle refresh")
	touch(point, false)
	check(not ui.touch_inspecting, "release closes refreshed help")
	touch(point, true)
	ui.manager.battle_generation += 1
	ui._refresh()
	await create_timer(0.51).timeout
	touch(point, false)
	check(not ui.touch_inspecting, "new battle invalidates an old hold")
	before = ui.manager.player.qi
	ui.action_busy = true
	touch(point, true); touch(point, false)
	check(ui.manager.player.qi == before, "busy action blocks conversion")
	ui.action_busy = false
	ui.manager.phase = "enemy_action"
	check(not ui._convert_player_qi("metal"), "enemy turn blocks player conversion")
	ui.manager.phase = "player_action"
	check(not ui._convert_player_qi("wood"), "locked element rejects UI conversion")
	# Desktop signal path uses the same guard and does not run on touch platforms.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = ui.get_global_transform_with_canvas() * region("energy").rect.get_center()
	root.push_input(mouse, true)
	await process_frame
	mouse.pressed = false
	root.push_input(mouse, true)
	await process_frame
	check(ui.manager.player.qi == before - (0 if PlatformUI.is_touch() else 1), "mouse click obeys desktop/touch platform routing")
	await create_timer(1.0).timeout
	ui.queue_free()
	await process_frame
	await process_frame
	print("Qi and hold UI (%s): %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "desktop", assertions, failures])
	quit(1 if failures else 0)
