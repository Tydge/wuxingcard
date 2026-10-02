extends SceneTree

var ui: Control
var controller: OnboardingController
var failures := 0
var assertions := 0
var output := "res://work/onboarding"
var save := "user://onboarding_ui_test.json"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)
func tick() -> void:
	await process_frame; await process_frame
	controller.update()
func wait_guide(chapter: String) -> void:
	var deadline := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < deadline:
		controller.update()
		if controller.guide_active() and controller.guide.chapter == chapter: return
		await process_frame
	check(false, "guide appears after opening/drawing finishes: " + chapter)
func screen() -> EndlessScreen:
	for child in ui.get_children():
		if child is EndlessScreen and child.visible: return child
	return null
func point(control: Control) -> Vector2: return control.get_global_rect().get_center()
func tap(at: Vector2) -> void:
	Input.warp_mouse(root.get_final_transform() * at)
	for held in [true,false]:
		if PlatformUI.is_touch():
			var touch := InputEventScreenTouch.new(); touch.position = at; touch.pressed = held
			root.push_input(touch,true)
		var mouse := InputEventMouseButton.new(); mouse.position = at; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = held
		mouse.device = InputEvent.DEVICE_ID_EMULATION if PlatformUI.is_touch() else 0
		root.push_input(mouse,true)
		await process_frame
	await tick()
func next() -> void: await tap(point(controller.guide.next_button))
func shot(name: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(("touch_" if PlatformUI.is_touch() else "pc_") + name + ".png")))
	check(controller.guide.body.get_line_count() <= 2 and controller.guide.panel.get_rect().end.x <= 1600 and controller.guide.panel.get_rect().end.y <= 900, "guide copy fits two lines and remains inside the design viewport")
func drag(source: Control, destination: Control) -> void:
	var from := point(source); var to := point(destination)
	var mouse := InputEventMouseButton.new(); mouse.position = from; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.button_mask = MOUSE_BUTTON_MASK_LEFT; mouse.pressed = true
	mouse.device = InputEvent.DEVICE_ID_EMULATION if PlatformUI.is_touch() else 0
	if PlatformUI.is_touch():
		var touch := InputEventScreenTouch.new(); touch.position = from; touch.pressed = true; root.push_input(touch,true)
	root.push_input(mouse,true); await process_frame
	var previous := from
	for at in [from + Vector2(28,0), from.lerp(to,0.6), to]:
		Input.warp_mouse(root.get_final_transform() * at)
		if PlatformUI.is_touch():
			var touch := InputEventScreenDrag.new(); touch.position = at; touch.relative = at - previous; root.push_input(touch,true)
		var move := InputEventMouseMotion.new(); move.position = at; move.relative = at - previous; move.button_mask = MOUSE_BUTTON_MASK_LEFT; move.device = mouse.device
		root.push_input(move,true); previous = at; await process_frame
	check(root.gui_is_dragging(), "guide passes mouse/touch drag to the deck library")
	mouse.position = to; mouse.pressed = false; mouse.button_mask = 0
	if PlatformUI.is_touch():
		var touch := InputEventScreenTouch.new(); touch.position = to; touch.pressed = false; root.push_input(touch,true)
	root.push_input(mouse,true); await tick()

func finish_detail(chapter: String) -> void:
	await create_timer(0.9).timeout; controller.update()
	check(controller.guide_active() and controller.guide.chapter == chapter, "noncombat inspection launches the matching type introduction")
	for index in 6:
		if not controller.guide_active() or controller.guide.chapter != chapter: break
		await shot(chapter + "_" + str(controller.progress.step(chapter)))
		await next()

func fast_opening(stage: String) -> void:
	ui.opening_active = false; ui.action_busy = false
	ui.pending_player_draws = 0; ui.pending_enemy_draws = 0; ui.draw_animation_active = false
	if stage == "order": controller.progress.claim_battle(); controller.progress.finish("setup")
	ui._refresh()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DirAccess.remove_absolute(save)
	ui = load("res://battle/battle_scene.tscn").instantiate()
	ui.endless_save_path = "user://onboarding_endless_ui.json"
	DirAccess.remove_absolute(ui.endless_save_path)
	root.add_child(ui); await process_frame; await process_frame
	controller = ui.onboarding
	controller.progress = OnboardingProgress.new(save)
	ui._open_endless(); await tick()
	var camp := screen()
	check(controller.guide_active() and controller.guide.chapter == "setup" and camp.next_button.disabled, "first setup highlights library and drop zone, entry still requires fifteen cards")
	await shot("setup")
	await drag(camp.workshop.card_nodes[0],camp.workshop.drop_zone)
	check(ui.endless.state["draft"].size() == 1 and controller.guide.body.text.contains("1 / 15"), "real first drag updates both saved draft and guide count")
	for card: DeckLibraryCard in camp.workshop.card_nodes:
		for copy in 2:
			if not card.plus.disabled and ui.endless.state["draft"].size() < 15: await tap(point(card.plus))
	if ui.endless.state["draft"].size() < 15:
		await tap(point(camp.workshop.next_page_button))
		await create_timer(0.4).timeout
		for card: DeckLibraryCard in camp.workshop.card_nodes:
			for copy in 2:
				if not card.plus.disabled and ui.endless.state["draft"].size() < 15: await tap(point(card.plus))
	check(ui.endless.state["draft"].size() == 15 and not camp.next_button.disabled and controller.guide.key.ends_with("ready"), "guide points to entry only when exactly fifteen cards are ready")
	await shot("ready")
	ui.manager.opening_presenter = fast_opening; ui.manager.summon_presenter = Callable()
	await tap(point(camp.next_button))
	check(ui.manager.first_side == "player" and ui.manager.phase == "player_action" and not controller.progress.first_battle(), "first playable battle is always player-first")
	await wait_guide("battle")
	var qi: int = ui.manager.player.qi
	await tap(ui.get_global_transform_with_canvas() * Vector2(1400,830))
	check(ui.manager.phase == "player_action" and ui.manager.player.qi == qi, "intro prevents clicking end turn underneath the spotlight")
	for index in 12:
		if controller.guide.key == "battle_convert": break
		await shot("battle_" + str(controller.progress.step("battle")))
		await next()
	if controller.guide.holes.is_empty(): quit(1); return
	var orb := controller.guide.holes[0].get_center()
	await tap(ui.get_global_transform_with_canvas() * orb)
	check(ui.manager.player.qi == qi - 1 and ui.manager.player.energy["metal"] == 1 and not controller.progress.pending("battle"), "real orb tap converts exactly once and completes the battle introduction")
	ui.manager._equip_loadout(ui.manager.player,{"implement":"metal_thunder_ruler"})
	ui._refresh(); await tick()
	check(controller.guide.key == "battle_implement_use", "first equipped implement receives its own active-use instruction")
	await shot("battle_implement")
	await tap(ui.get_global_transform_with_canvas() * Vector2(64,300))
	check(not controller.progress.pending("battle_implement") and ui.manager.player.artifact_ready_turn > ui.manager.player.own_turn_count, "actual weapon tap activates the artifact and clears only its first-use guide")
	ui.manager.battle_generation += 1; ui.action_busy = false; ui.enemy_animating = false
	ui.endless.settle("victory"); ui.manager.phase = "menu"; ui._clear_endless_presentation(); ui._refresh(); await tick(); camp = screen()
	for index in 6:
		if not controller.progress.pending("rest"): break
		await shot("rest_" + str(controller.progress.step("rest"))); await next()
	check(ui.endless.state["gold"] == 100, "rest introduction spends no money")
	ui.endless.state["shop"][0]["id"] = "metal_strike"
	await tap(point(camp.hotspots["shop"])); await tick()
	await shot("shop")
	await tap(point(camp.item_views[0])); await finish_detail("detail_spell")
	check(controller.guide.chapter == "shop" and controller.guide.heading.text == "购买", "card introduction returns to the real shop purchase control")
	await next()
	check(ui.endless.state["gold"] == 100 and not controller.progress.pending("shop"), "shop introduction does not force purchase")
	camp._close_modal(false); camp._navigate("inventory"); await tick()
	await tap(point(camp.workshop.card_nodes[0])); await create_timer(0.5).timeout; await tick()
	check(controller.guide.chapter == "inventory" and controller.progress.step("inventory") == 1, "inventory asks for a real upgrade preview")
	await tap(point(camp.inspect_tabs.buttons[1])); await create_timer(0.3).timeout; await tick()
	check(controller.progress.step("inventory") == 2 and ui.endless.state["gold"] == 100, "preview advances the guide without paying")
	await shot("upgrade_preview"); await next()
	await tap(ui.get_global_transform_with_canvas() * Vector2(565,90)); await tick()
	check(camp.workshop.view_mode == "artifacts" and controller.progress.step("inventory") == 4, "real tab tap opens artifact equipment slots")
	await shot("equipment_empty"); await next()
	check(not controller.progress.pending("inventory") and ui.endless.state["gold"] == 100, "empty artifact inventory has an explained, reachable completion")
	ui.endless._own("artifacts","metal_thunder_ruler")
	controller.progress.completed.erase("inventory"); controller.progress.advance("inventory",4)
	camp.workshop.refresh_owned(); await tick()
	var artifact: ArtifactLibraryCard = camp.workshop.artifact_motion.page_views[0][0]
	await shot("equipment_action")
	check(not controller.guide.next_button.visible, "available first equipment asks for actual operation")
	await tap(point(artifact.plus))
	check(ui.endless.loadout_ids()["implement"] == "metal_thunder_ruler" and not controller.progress.pending("inventory"), "actual plus tap equips the artifact and completes inventory guidance")
	# Noncombat details use independent chapters even after other guidance is complete.
	camp._navigate("shop")
	for entry in [["metal_furnace_card","detail_summon"],["metal_thunder_ruler","detail_implement"],["earth_thick_robe","detail_guard"]]:
		camp._close_modal(false)
		var catalog: Dictionary = ui.manager.cards if entry[1] == "detail_summon" else ui.manager.artifacts
		camp._inspect_readonly(catalog[entry[0]])
		await finish_detail(entry[1])
		check(not controller.progress.pending(entry[1]), "each detail type is remembered independently")
	var reload := OnboardingProgress.new(save)
	check(not reload.pending("inventory") and not reload.pending("detail_guard") and not reload.first_battle(), "completed tutorials persist across relaunch")
	# The same first-inspection guide also applies to the collection outside endless mode.
	ui._endless_home(); await tick()
	var collection: MainMenu
	for child in ui.get_children():
		if child is MainMenu: collection = child
	collection._show_collection(); await tick()
	controller.progress.completed.erase("detail_spell")
	await tap(point(collection.card_nodes[0]))
	await finish_detail("detail_spell")
	check(not controller.progress.pending("detail_spell"), "collection inspection uses the shared remembered tutorial")
	collection._close_inspector(); await create_timer(0.5).timeout
	controller.progress.completed.erase("detail_guard")
	collection._open_inspector(ui.manager.artifacts["earth_thick_robe"],collection.card_nodes[0])
	await create_timer(0.9).timeout; await tick()
	check(controller.guide.chapter == "detail_guard", "collection guard inspection starts independently")
	ui._request_back(); await tick()
	check(not controller.progress.pending("detail_guard") and is_instance_valid(collection.inspector), "Back skips only the current guide and preserves the open detail")
	ui.queue_free(); await process_frame
	DirAccess.remove_absolute(save); DirAccess.remove_absolute("user://onboarding_endless_ui.json")
	print("Onboarding UI (%s): real drag, fifteen cards, guided conversion, artifact tap, camp/shop/inventory/details; %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "PC",assertions,failures])
	quit(1 if failures else 0)
