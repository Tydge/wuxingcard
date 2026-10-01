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
	check(menu.filtered_cards.size() == 10, "collection filters guard artifacts")
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
	check(workshop.view_mode == "artifacts" and workshop._artifact_entries().size() == 30, "deck workshop opens artifact loadout")
	var row: ArtifactLoadoutRow = workshop.artifact_rows["implement"]
	var drag_data := {"kind": "artifact", "slot": "implement", "id": "metal_thunder_ruler"}
	check(row._can_drop_data(Vector2.ZERO, drag_data), "matching artifact can be dropped into its slot")
	check(not row._can_drop_data(Vector2.ZERO, {"kind": "artifact", "slot": "guard", "id": "metal_silk_robe"}), "other artifact slots reject the drop")
	var artifact_content := workshop.content
	var page_nodes := artifact_content.get_children()
	var slot_nodes := row.get_children()
	var slot_frame := row.frame
	row._drop_data(Vector2.ZERO, drag_data)
	check(workshop.draft_loadout["implement"] == "metal_thunder_ruler" and workshop.artifact_rows["implement"] == row, "equipping updates the existing row without rebuilding the page")
	check(workshop.content == artifact_content and artifact_content.get_children() == page_nodes and row.get_children() == slot_nodes and row.frame == slot_frame, "equipping preserves the page, card controls, row children and frame")
	row.remove_button.pressed.emit()
	check(workshop.draft_loadout["implement"] == "" and row.entry.is_empty() and not row.remove_button.visible, "remove button clears only its artifact slot")
	check(workshop.content == artifact_content and artifact_content.get_children() == page_nodes and row.get_children() == slot_nodes and row.frame == slot_frame and row.modulate == Color.WHITE, "removal preserves the page and row without a flash animation")
	# Exercise the library plus button on another page, as well as drag/drop.
	workshop.page = 1
	workshop._build_artifact_editor()
	artifact_content = workshop.content
	page_nodes = artifact_content.get_children()
	var library_card: ArtifactLibraryCard
	for child in page_nodes:
		if child is ArtifactLibraryCard:
			library_card = child
			break
	var plus: Button = library_card.get_child(2)
	plus.pressed.emit()
	var updated_row: ArtifactLoadoutRow = workshop.artifact_rows[library_card.entry["slot"]]
	check(updated_row.entry["id"] == library_card.entry["id"] and workshop.page == 1 and workshop.content == artifact_content and artifact_content.get_children() == page_nodes, "plus equips on the current page without replacing any page controls")
	updated_row.remove_button.pressed.emit()
	check(workshop.page == 1 and workshop.content == artifact_content and artifact_content.get_children() == page_nodes, "removing an artifact also retains the selected page")
	menu.hide()
	compact.hide()
	enlarged.hide()
	var battle: Control = load("res://ui/battle_ui.gd").new()
	battle.size = Vector2(1600, 900)
	root.add_child(battle)
	await battle.manager.start_battle("ember", "random", 31337)
	check(battle.manager.phase == "player_action", "random battle reaches player action")
	check(battle.manager.player.artifacts["implement"] != "" and battle.manager.enemy.artifacts["guard"] != "", "both sides display random loadouts")
	check(battle.actor_layer.get_child_count() >= 4, "battlefield builds hero and implement standees")
	check(battle.artifact_layer.get_index() > battle.actor_layer.get_index() and battle.fx_layer.get_index() > battle.artifact_layer.get_index(), "equipment badges draw above characters with previews and modals above equipment")
	var enemy_guard_badge: ArtifactBadge
	for control in battle.artifact_layer.get_children():
		for child in control.get_children():
			if child is ArtifactBadge and control.position.x > 1400: enemy_guard_badge = child
	check(enemy_guard_badge != null and enemy_guard_badge.value == battle.manager.enemy.artifact_durability, "enemy durability badge displays its current value above the standee")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/balance_20261001"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://work/balance_20261001/enemy_artifact_layer.png"))
	var enemy_weapon: TextureRect
	for child in battle.actor_layer.get_children():
		if child is TextureRect and child != battle.standee_nodes["enemy"] and child.position.x > 1450.0:
			enemy_weapon = child
	check(enemy_weapon != null and enemy_weapon.flip_h, "enemy implement standee faces the player")
	battle.manager._equip_loadout(battle.manager.player, {"implement":"metal_thunder_ruler"})
	battle.manager._equip_loadout(battle.manager.enemy, {})
	battle.manager.enemy.hp = battle.manager.enemy.max_hp
	for element in BattleRules.ELEMENTS:
		battle.manager.player.energy[element] = 0
		battle.manager.enemy.energy[element] = 0
	battle.manager.player.statuses.clear()
	battle.manager.enemy.statuses.clear()
	var before_hp: int = battle.manager.enemy.hp
	check(battle._artifact_cast_target(battle.manager.player, {}) == battle.ENEMY_ANCHOR and battle._artifact_cast_target(battle.manager.enemy, {}) == battle.ENEMY_ANCHOR, "automatic artifact visual targets follow its effects")
	battle.manager._equip_loadout(battle.manager.enemy, {"implement":"metal_thunder_ruler__2"})
	check(battle._artifact_cast_target(battle.manager.enemy, {}) == battle.PLAYER_ANCHOR, "enemy ruler visual points at the player")
	battle._on_artifact_pressed()
	check(not battle.artifact_aiming and battle.manager.enemy.hp == before_hp - 5, "pressing the ruler immediately damages the opponent without opening aim mode")
	print("Artifact UI test: collection, editor, and loadout; %d failures" % failures)
	quit(1 if failures > 0 else 0)
