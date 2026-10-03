extends "res://tests/discovery_ui_test.gd"

const WAVE := ["metal_mountain_sword", "metal_oath_sword_card", "water_return_tide", "water_mirror_spirit_card", "wood_spring_blessing", "wood_spring_mulberry_card", "fire_burn_pact", "fire_ash_luan_card", "earth_seek_vein", "earth_mountain_elder_card"]

func run() -> void:
	output = "res://work/wuxing_spirits_20261004"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	ui = load("res://battle/battle_scene.tscn").instantiate(); ui.endless_save_path = "user://wuxing_spirits_ui_test.json"
	root.add_child(ui); await process_frame
	clean("water_return_tide__2"); creature(ui.manager.player, 0, "water_breath_wisp__1", 1)
	ui._refresh(); await process_frame; await begin_drag()
	await send_pointer(ui._anchor("enemy"), "release")
	check(ui.manager.player.hand == ["water_return_tide__2"] and ui.manager.player.summons[0] != null, "return rejects enemy hero without payment")
	await begin_drag(); await send_pointer(ui._summon_point("player",0), "release"); await wait_idle()
	check(ui.manager.player.summons[0] == null and ui.manager.player.hand.size() == 1 and ui.manager.player.card_cost(ui.manager.cards[ui.manager.player.hand[0]]) == 5, "real return selects friendly summon and yields grade contract with discount")
	ui.manager.player.energy["water"] = 5; ui._refresh(); await process_frame
	check(ui.hand_cards[0].get_node("Cost").text == "5", "returned hand card visibly reflects copy reduction")
	await begin_drag(); await send_pointer(ui._summon_point("player",0), "release"); await wait_idle()
	check(ui.manager.player.summons[0] != null and ui.manager.player.summons[0].hp == 24 and ui.manager.player.energy["water"] == 0, "discounted contract can be dragged back into its empty slot")
	clean("fire_burn_pact__2"); creature(ui.manager.player, 0, "wood_spring_mulberry", 27)
	ui._refresh(); await process_frame; await begin_drag(); await send_pointer(ui._summon_point("player",0), "move")
	check(ui.damage_preview.visible and ui.damage_preview_label.text.contains("40") and ui.damage_preview_label.text.contains("对手"), "sacrifice preview shows capped damage to opponent")
	await shot("sacrifice_preview"); await send_pointer(ui._summon_point("player",0), "release"); await wait_idle()
	check(ui.manager.player.summons[0] == null and ui.manager.enemy.hp == 160, "real sacrifice drop resolves selected ally and opponent damage")
	clean("metal_mountain_sword"); ui.manager.player.last_card_element = "earth"; creature(ui.manager.enemy, 0, "earth_mountain_elder", 22)
	ui._refresh(); await process_frame; await begin_drag(); await send_pointer(ui._anchor("enemy"), "move")
	check(ui.damage_preview.visible and ui.damage_preview_label.text.contains("石翁") and ui.damage_preview_label.text.contains("12+10=22"), "guard preview names recipient and sums actual damage")
	await shot("intercept_preview"); await send_pointer(ui._anchor("enemy"), "release"); await wait_idle()
	check(ui.manager.enemy.hp == 200 and ui.manager.enemy.summons[0] == null, "real conditional double hit goes to guardian")
	clean("wood_spring_blessing__1"); creature(ui.manager.player,0,"wood_spring_mulberry",14); creature(ui.manager.player,2,"fire_ash_luan",8)
	ui._refresh(); await process_frame; await begin_drag(); await send_pointer(Vector2(800,450),"release"); await wait_idle()
	check(ui.manager.player.summons[0].max_hp == 21 and ui.manager.player.summons[2].max_hp == 15, "untargeted wood spell affects all friendly summons")
	clean("earth_seek_vein__2"); ui._refresh(); await process_frame; await begin_drag(); await send_pointer(Vector2(800,450),"release"); await wait_choice()
	if not is_instance_valid(ui.choice_dialog): quit(1); return
	check(ui.choice_dialog.frames.size() == 3, "edited earth discovery is three choices at top grade")
	var selected: String = ui.manager.pending_choice["candidates"][0]
	await click_control(ui.choice_dialog.frames[0].get_child(0)); await click_control(ui.choice_dialog.confirm); await wait_idle()
	var result: String = ui.manager.player.hand[0]
	check(ui.manager.cards[result]["canonical_id"] == selected and ui.hand_cards[0].get_node("Cost").text == str(int(ui.manager.cards[selected]["cost"]) - 2), "confirmed discovery displays reduced cost on selected copy")
	# End-turn discovery must finish before control reaches the opposing turn.
	clean("metal_ward"); ui.manager.player.hand.clear(); creature(ui.manager.player,0,"water_mirror_spirit__1",15)
	ui.manager.player.spell_elements = {"wood":true,"fire":true}; ui.manager.enemy.draw_pile.assign(["water_strike"])
	ui._refresh(); await process_frame
	ui._on_end_turn(); await wait_choice()
	check(ui.manager.phase == "player_turn_end" and ui.action_busy and ui.choice_dialog.frames.size() == 3, "summon discovery holds end-turn phase for confirmation")
	await click_control(ui.choice_dialog.frames[0].get_child(0)); await click_control(ui.choice_dialog.confirm)
	var deadline := Time.get_ticks_msec()+8000
	while ui.manager.phase == "player_turn_end" and Time.get_ticks_msec()<deadline: await process_frame
	check(ui.manager.phase != "player_turn_end" and ui.manager.pending_choice.is_empty(), "confirmation resumes turn transition")
	# Cancel the running opponent presenter before isolated card-face inspection.
	ui.manager.battle_generation += 1; ui.manager.phase = "menu"; ui.action_busy = false
	var surface := Control.new(); surface.theme = ui.theme; root.add_child(surface)
	for level in 3:
		for half in 2:
			for child in surface.get_children(): child.free()
			for i in 5:
				var entry: Dictionary = ui.manager.cards[ContentCatalog.variant_id(WAVE[half*5+i],level)]
				var view: Control = ui._card_front(entry,Vector2(270,378)); view.position=Vector2(30+i*310,240); surface.add_child(view); await process_frame
				var desc: RichTextLabel = view.get_node("Description")
				check(desc.get_content_height() <= desc.size.y and desc.get_content_width() <= desc.size.x+1, "new description fits: "+entry["name"])
				check(view.art_texture != null and view.art_texture.resource_path.ends_with(entry["art_id"]+".webp"), "new illustration loads: "+entry["name"])
			await shot("cards_%d_%d" % [level,half])
	surface.queue_free(); ui.queue_free(); await process_frame
	print("Wuxing spirits UI (%s): %d assertions, %d failures" % ["touch" if PlatformUI.is_touch() else "PC",assertions,failures]); quit(1 if failures else 0)
