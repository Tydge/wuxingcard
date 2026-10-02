extends SceneTree

var ui: Control
var failures := 0
var assertions := 0
var output := "res://work/layout_20261002"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)
func shot(name: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(("touch_" if PlatformUI.is_touch() else "pc_") + name + ".png")))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	ui = load("res://battle/battle_scene.tscn").instantiate()
	ui.endless_save_path = "user://card_layout_test.json"
	DirAccess.remove_absolute(ui.endless_save_path)
	root.add_child(ui); await process_frame
	var surface := Control.new(); surface.theme = ui.theme; root.add_child(surface)
	# Every current grade at compact-list, normal and enlarged sizes. Art cannot
	# affect text measurement, so use the shared fallback to keep this check light.
	for width in [152.0,180.0,240.0,340.0,480.0]:
		for card: Dictionary in ui.manager.cards.values():
			var sample := card.duplicate(true); sample["art_id"] = "layout_font_fixture"
			var view: Control = ui._card_front(sample,Vector2(width,width * 1.4))
			surface.add_child(view)
			var description: RichTextLabel = view.get_node("Description")
			check(description.get_content_height() <= description.size.y and description.get_content_width() <= description.size.x + 1, "full description fits: " + card["id"] + " at " + str(width))
			check(description.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and description.vertical_alignment == VERTICAL_ALIGNMENT_CENTER and description.get_parsed_text() == card["text"], "complete centered text, no guessed hard breaks: " + card["id"])
			view.free()
	for entry: Dictionary in ui.manager.artifacts.values():
		var sample := entry.duplicate(true); sample["art_id"] = "layout_font_fixture"
		var view := ArtifactView.new(); view.configure(sample,Vector2(480,672)); surface.add_child(view)
		var description: RichTextLabel = view.find_child("Description",true,false)
		check(description.get_content_height() <= description.size.y and description.get_parsed_text() == entry["description"], "full artifact description fits: " + entry["id"])
		view.free()
	ui.hide()
	for index in 2:
		var id: String = ["water_strike","water_breath_newt_card"][index]
		var card: Control = ui._card_front(ui.manager.cards[id],Vector2(480,672))
		card.position = Vector2(180 + index * 700,50); surface.add_child(card)
	await shot("short_and_long_description")
	for child in surface.get_children(): child.queue_free()
	var run := EndlessRun.new(ui.manager.cards,ui.manager.artifacts,ui.manager.enemies,ui.endless_save_path)
	run.new_run(17); run.state["phase"] = "rest"; run.state["gold"] = 123456
	var camp := EndlessScreen.new(); camp.configure(run,ui._card_front,ui.manager.summon_templates); camp.theme = ui.theme
	root.add_child(camp); camp._navigate("inventory"); await process_frame; await process_frame
	for mode in ["editor","artifacts"]:
		if mode == "artifacts": camp.workshop._build_artifact_editor(); await process_frame; await process_frame
		var wallet: Control = camp.workshop.content.find_child("SpiritMoney",true,false)
		var amount: Label = wallet.get_node("Amount")
		var natural := amount.get_theme_font("font").get_string_size(amount.text,HORIZONTAL_ALIGNMENT_LEFT,-1,amount.get_theme_font_size("font_size")).x
		check(amount.text == "123456" and amount.is_visible_in_tree() and amount.size.x >= natural and amount.size.x > 0 and amount.global_position.x + amount.size.x <= wallet.global_position.x + wallet.size.x, "visible untruncated inventory balance in " + mode)
		await shot("wallet_" + mode)
	camp.queue_free(); surface.queue_free(); ui.show()
	for actor: Combatant in [ui.manager.player,ui.manager.enemy]:
		actor.max_hp = 80
		actor.setup("player" if actor == ui.manager.player else "ember","测试",[],ui.manager.rng)
		actor.draw_pile.assign(["metal_strike","water_strike"])
	ui.manager.phase = "player_action"; ui._refresh(); await process_frame
	var before: int = ui.manager.player.qi
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"gain_qi","target":"self","amount":2},"water",{})
	ui._refresh(); await create_timer(0.2).timeout
	var feedback := ui.fx_layer.get_node_or_null("QiGain_player") as Control
	var badge := ui.find_child("QiBadge_player",true,false) as QiBadge
	check(ui.manager.player.qi == before + 2 and feedback != null and feedback.get_meta("amount") == 2 and feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE and badge.gain_strength > 0 and badge.get_node("Number").scale.x > 1, "qi gain animates badge and +2 through HUD refresh without intercepting input")
	await shot("qi_gain")
	await create_timer(0.8).timeout
	check(not is_instance_valid(feedback) and badge.get_node("Number").scale == Vector2.ONE, "qi feedback fades and restores normal number size")
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"lose_qi","target":"self","amount":1},"water",{})
	var loss := ui.fx_layer.get_node_or_null("QiLoss_player") as Control
	check(ui.fx_layer.get_node_or_null("QiGain_player") == null and loss != null and loss.get_meta("amount") == -1, "qi loss shows the exact negative amount without a gain effect")
	await shot("qi_loss")
	loss.free()
	ui.manager.convert_qi(ui.manager.player,"metal")
	check(ui.fx_layer.get_node_or_null("QiLoss_player") != null, "qi conversion also displays its qi loss")
	ui.manager._resolve_effect(ui.manager.enemy,ui.manager.player,{"type":"gain_qi","target":"self","amount":1},"water",{})
	check(ui.fx_layer.get_node_or_null("QiGain_enemy") != null, "opponent qi gain uses the opponent badge")
	ui.manager.player.hp = 60
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"heal","target":"self","amount":5},"wood",{})
	var healed: HealNumber = ui.fx_layer.find_child("HealNumber*",true,false)
	check(healed != null and healed.get_meta("amount") == 5 and healed.mouse_filter == Control.MOUSE_FILTER_IGNORE and healed.get_child(0).get_theme_font_size("font_size") == 62, "actual hero healing gets a large outlined +5 at its target")
	await shot("heal_hero")
	healed.free()
	var summon := Summon.new(); summon.setup(ui.manager.summon_templates["wood_seedling"])
	summon.hp = 5; ui.manager.player.summons[0] = summon
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"heal_summon","amount":4},"wood",{"kind":"summon","side":"player","slot":0})
	check(ui.fx_layer.find_child("HealNumber*",true,false).get_meta("amount") == 4, "summon healing receives the same clear numeric callout")
	for child in ui.fx_layer.get_children():
		if child is HealNumber: child.free()
	ui.manager.player.hp = 80
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"heal","target":"self","amount":5},"wood",{})
	check(ui.fx_layer.find_child("HealNumber*",true,false) == null, "zero effective healing has no misleading +number")
	ui.battle_fx.clear_effects()
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"status","target":"self","status":"shield","stacks":20},"earth",{})
	check(ui.battle_fx.active.any(func(e): return e.kind == "status" and e.detail == "shield"), "gaining shields retains the shield animation")
	ui.battle_fx.clear_effects()
	await ui.manager._start_turn(ui.manager.player)
	check(not ui.battle_fx.active.any(func(e): return e.kind == "status" and e.detail == "shield"), "start-of-turn shield decay does not animate as a shield gain")
	ui.battle_fx.clear_effects()
	ui.manager._resolve_effect(ui.manager.enemy,ui.manager.player,{"type":"break_shield","amount":2},"metal",{})
	check(ui.battle_fx.active.is_empty(), "breaking shields has no gain or block animation")
	ui.manager.apply_damage(ui.manager.enemy,ui.manager.player,2,"water")
	check(ui.battle_fx.active.any(func(e): return e.kind == "impact" and e.detail == "shield"), "successful damage absorption retains the block animation")
	ui.battle_fx.clear_effects()
	ui.manager._resolve_effect(ui.manager.player,ui.manager.enemy,{"type":"remove_status","target":"self","status":"shield"},"water",{})
	check(ui.battle_fx.active.is_empty(), "removing shields has no shield animation")
	ui.queue_free(); await process_frame; DirAccess.remove_absolute(run.path)
	print("Card layout (%s): every grade at five sizes, full rich text, centered short/long text, inventory balances and qi feedback; %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "PC",assertions,failures])
	quit(1 if failures else 0)
