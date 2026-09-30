extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var manager := BattleManager.new()
	root.add_child(manager)
	var menu := MainMenu.new()
	menu.configure(manager.cards, func(card: Dictionary, card_size: Vector2) -> Panel:
		var view := CardView.new()
		view.configure(card, card_size.x)
		return view, manager.summon_templates)
	root.add_child(menu)
	menu.collection_type = "artifacts"
	menu.selected_artifact_slot = "guard"
	menu._build_collection()
	check(menu.filtered_cards.size() == 5, "collection filters guard artifacts")
	var compact := ArtifactView.new()
	compact.configure(manager.artifacts["metal_silk_robe"], Vector2(156, 218))
	root.add_child(compact)
	await process_frame
	var face: Control = compact.get_child(0)
	check(face.size == ArtifactView.FACE_SIZE and is_equal_approx(face.scale.x, 156.0 / 400.0), "small artifact is a scaled full card")
	var enlarged := ArtifactView.new()
	enlarged.configure(manager.artifacts["metal_silk_robe"], ArtifactView.FACE_SIZE)
	root.add_child(enlarged)
	check((enlarged.get_child(0) as Control).scale == Vector2.ONE, "inspected artifact uses identical card layout")
	menu._show_decks()
	var workshop: DeckWorkshop = menu.workshop
	workshop._open_editor({})
	workshop._open_artifacts({})
	check(workshop.view_mode == "artifacts" and workshop._artifact_entries().size() == 15, "deck workshop opens artifact loadout")
	var row: ArtifactLoadoutRow = workshop.artifact_rows["implement"]
	var drag_data := {"kind": "artifact", "slot": "implement", "id": "metal_thunder_ruler"}
	check(row._can_drop_data(Vector2.ZERO, drag_data), "matching artifact can be dropped into its slot")
	check(not row._can_drop_data(Vector2.ZERO, {"kind": "artifact", "slot": "guard", "id": "metal_silk_robe"}), "other artifact slots reject the drop")
	row._drop_data(Vector2.ZERO, drag_data)
	check(workshop.draft_loadout["implement"] == "metal_thunder_ruler" and workshop.artifact_rows["implement"] == row, "equipping updates the existing row without rebuilding the page")
	var battle: Control = load("res://ui/battle_ui.gd").new()
	root.add_child(battle)
	await battle.manager.start_battle("ember", "random", 31337)
	check(battle.manager.phase == "player_action", "random battle reaches player action")
	check(battle.manager.player.artifacts["implement"] != "" and battle.manager.enemy.artifacts["guard"] != "", "both sides display random loadouts")
	check(battle.actor_layer.get_child_count() >= 4, "battlefield builds hero and implement standees")
	var enemy_weapon: TextureRect
	for child in battle.actor_layer.get_children():
		if child is TextureRect and child != battle.standee_nodes["enemy"] and child.position.x > 1450.0:
			enemy_weapon = child
	check(enemy_weapon != null and enemy_weapon.flip_h, "enemy implement standee faces the player")
	print("Artifact UI test: collection, editor, and loadout; %d failures" % failures)
	quit(1 if failures > 0 else 0)
