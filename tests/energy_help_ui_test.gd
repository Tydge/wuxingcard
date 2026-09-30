extends SceneTree

var failures := 0
var ui: Control

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func collect_orbs(node: Node, results: Array[EnergyOrb]) -> void:
	if node is EnergyOrb: results.append(node)
	for child in node.get_children(): collect_orbs(child, results)

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://work/audit_ui")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))

func run() -> void:
	ui = load("res://battle/battle_scene.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	var menu: MainMenu
	for child in ui.get_children():
		if child is MainMenu: menu = child
	menu._open_rules()
	await process_frame
	check(is_instance_valid(menu.rules_panel) and menu.rules_panel.body.text.contains("金克木"), "home exposes the complete rules panel")
	menu.go_back()
	check(not is_instance_valid(menu.rules_panel), "Back closes help before leaving the menu")
	ui.manager.random_artifacts_enabled = false
	await ui.manager.start_battle("ember", "random", 901)
	for actor in [ui.manager.player, ui.manager.enemy]:
		for element in BattleRules.ELEMENTS: actor.energy[element] = 5
	await create_timer(5.4).timeout
	ui._refresh()
	await process_frame
	var orbs: Array[EnergyOrb] = []
	collect_orbs(ui, orbs)
	check(orbs.size() == 10 and ui.energy_touch_regions.size() == 10, "both combatants expose all five energy circles")
	var metal: EnergyOrb
	for orb in orbs:
		if orb.tooltip_text.begins_with("金能量 5"): metal = orb
	check(metal != null and metal.tooltip_text == "金能量 5\n金系伤害抗性+50%\n火系伤害抗性-50%", "metal tooltip matches the requested wording exactly")
	var custom_tooltip := metal._make_custom_tooltip(metal.tooltip_text)
	check(custom_tooltip.get_child(0).text == metal.tooltip_text, "desktop hover builds the readable shared tooltip")
	custom_tooltip.free()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = metal.get_global_transform_with_canvas() * (metal.size / 2.0)
	ui._handle_touch(touch)
	check(ui.touch_inspecting and is_instance_valid(ui.hover_preview), "tap on an energy circle opens its explanation")
	await shot("energy_touch")
	ui._clear_hover_preview()
	ui._open_rules()
	await process_frame
	check(ui.information_panel.body.text.contains("弃牌不洗回"), "in-battle rules explain fatigue and resource mechanics")
	await shot("rules")
	ui._request_back()
	check(not is_instance_valid(ui.information_panel), "Back closes the information modal")
	for i in 30: ui.manager._report("日志事件%d" % i)
	ui._open_journal()
	await process_frame
	check(ui.information_panel.body.text.contains("日志事件0") and ui.information_panel.body.text.contains("日志事件29"), "journal displays the complete chronological history")
	var entries: String = ui.information_panel.body.text
	check(entries.find("日志事件0") < entries.find("日志事件29"), "journal orders older events before newer ones")
	await shot("journal")
	ui._request_back()
	ui.manager.player.energy["metal"] = 2
	ui._refresh()
	await process_frame
	orbs.clear()
	collect_orbs(ui, orbs)
	var updated := false
	for orb in orbs:
		if orb.tooltip_text == "金能量 2\n金系伤害抗性+20%\n火系伤害抗性-20%": updated = true
	check(updated, "energy tooltip updates when the live energy changes")
	ui.queue_free()
	await process_frame
	await process_frame
	print("Energy and help UI: desktop/touch tooltips, dynamic values, modal Back and chronological journal; %d failures" % failures)
	quit(1 if failures > 0 else 0)
