extends SceneTree

# Godot --path . --script res://tools/capture_new_summons.gd

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
	var output := ProjectSettings.globalize_path("res://work/new_summons")
	DirAccess.make_dir_recursive_absolute(output)
	for summon_id in ["metal_chime", "wood_deer", "water_conch", "fire_raven", "earth_tortoise"]:
		var template: Dictionary = manager.summon_templates[summon_id]
		manager.player.summons[0] = Summon.new()
		manager.player.summons[0].setup(template)
		manager.player.hand[0] = template["card_id"]
		manager.player.energy[template["element"]] = 10
		ui.call("_refresh")
		await process_frame
		var view: SummonView = ui.get("summon_views")["player_0"]
		if view.summon_ref.id != summon_id or view.get_child(0).texture == null:
			push_error("Missing field art for " + summon_id)
			quit(1)
			return
		ui.call("_on_summon_hover", "player", 0)
		await process_frame
		var preview: Control = ui.get("hover_preview")
		if not preview is SummonCardView or preview.art_texture == null:
			push_error("Missing enlarged summon card art for " + summon_id)
			quit(1)
			return
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(summon_id + ".png"))
	print("Captured 5 new summon cards and standees")
	quit()
