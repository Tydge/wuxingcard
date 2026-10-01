class_name EndlessWorkshop
extends DeckWorkshop

signal scout_requested
signal changed

var run: EndlessRun
var initial := false
var artifact_motion: CardPageMotion
var artifact_page := 0
var artifact_page_label: Label
var artifact_previous: Button
var artifact_next: Button

func configure_run(progress: EndlessRun, card_factory: Callable, summon_data: Dictionary) -> void:
	run = progress
	cards = run.cards
	artifacts = run.artifacts
	factory = card_factory
	summons = summon_data
	initial = run.state["phase"] == "setup"
	_sync()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brush_font = GameFonts.title()
	effects = Control.new()
	effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(effects)
	_build_editor()

func _sync() -> void:
	draft.assign(run.state["draft"] if initial else run.deck_ids())
	draft_loadout = run.loadout_ids()

func _editor_heading() -> void:
	_text(content, "初入无尽" if initial else "行囊", Rect2(65, 48, 340, 70), 49, GOLD, true)
	if initial:
		_text(content, "15张原版牌 · 80生命 · 无法宝", Rect2(420, 73, 800, 36), 22, JADE)
	else:
		_button(content, "卡牌", Rect2(355, 63, 132, 58), func(): _build_editor()).disabled = view_mode == "editor"
		_button(content, "法宝", Rect2(503, 63, 132, 58), func(): selected_element = "all"; _build_artifact_editor()).disabled = view_mode == "artifacts"
		_text(content, "灵钱 %d" % int(run.state["gold"]), Rect2(700, 73, 400, 36), 24, GOLD)
	_button(content, "返回山门" if initial else "收起行囊", Rect2(1340, 64, 180, 58), func(): back_requested.emit())

func _editor_identity() -> void:
	_text(content, "携行牌组", Rect2(1200, 124, 320, 41), 27, GOLD, true)

func _editor_actions() -> void:
	if initial:
		_button(content, "查看对手", Rect2(1187, 805, 160, 58), func(): scout_requested.emit())
		play_button = _button(content, "入阵", Rect2(1369, 805, 165, 58), func(): battle_requested.emit({}))
	else:
		play_button = _button(content, "收起行囊", Rect2(1187, 805, 347, 58), func(): back_requested.emit())

func _maximum_cards() -> int: return EndlessRun.INITIAL_CARDS if initial else 30
func _row_has_remove() -> bool: return true
func _connect_row(row: DeckRow, _id: String) -> void:
	row.pressed.connect(func(): inspect_requested.emit(row.card, row.inspect_anchor))
	row.remove_requested.connect(_remove_card)
func _limit_hint() -> String: return "恰好15张 · 同名最多2张" if initial else "15–30张 · 同名最多2张"
func _deck_problem() -> String: return "需15张卡牌" if initial and draft.size() != EndlessRun.INITIAL_CARDS else "" if initial else run.deck_problem()

func _library_cards(element: String) -> Array[Dictionary]:
	if initial: return super._library_cards(element)
	var result: Array[Dictionary] = []
	var seen := {}
	for copy: Dictionary in run.state["owned_cards"]:
		var id := str(copy["id"])
		if seen.has(id): continue
		seen[id] = true
		if element == "all" or cards[id]["element"] == element: result.append(cards[id])
	result.sort_custom(_card_less)
	return result

func _update_editor(highlight: String = "") -> void:
	super._update_editor(highlight)
	if not initial: play_button.disabled = false

func _owned_count(id: String) -> int:
	var result := 0
	for copy: Dictionary in run.state["owned_cards"]:
		if copy["id"] == id: result += 1
	return result

func available_uid(item_kind: String, id: String, equipped: bool = false) -> String:
	var active: Array = run.state["deck"] if item_kind == "cards" else run.state["loadout"].values()
	for copy: Dictionary in run.state["owned_" + item_kind]:
		if copy["id"] == id and active.has(copy["uid"]) == equipped: return str(copy["uid"])
	return ""

func _can_add(id: String) -> bool:
	if not cards.has(id) or draft.size() >= _maximum_cards() or ContentCatalog.family_count(draft, id, cards) >= 2: return false
	return int(cards[id]["level"]) == 0 if initial else not available_uid("cards", id).is_empty()

func _create_library_card(card: Dictionary, index: int, sheet: Control) -> Control:
	var node: DeckLibraryCard = super._create_library_card(card, index, sheet)
	_set_availability(node)
	return node

func _set_availability(node: DeckLibraryCard) -> void:
	var id := str(node.card["id"])
	node.set_availability(draft.count(id) if not initial else ContentCatalog.family_count(draft, id, cards), -1 if initial else _owned_count(id), _can_add(id))

func _refresh_card_views() -> void:
	for motion: CardPageMotion in cached_pages.values():
		for views: Array in motion.page_views:
			for node: DeckLibraryCard in views: _set_availability(node)

func _add_card(id: String, source: Vector2 = Vector2(-1, -1)) -> void:
	if not _can_add(id): return
	var okay := run.change_draft(id, true) if initial else run.toggle_card(available_uid("cards", id))
	if not okay: _toast(run.error); return
	_sync()
	_update_editor(id)
	if source.x >= 0: _fly_into_row(id, source)
	changed.emit()

func _remove_card(id: String) -> void:
	var okay := run.change_draft(id, false) if initial else run.toggle_card(available_uid("cards", id, true))
	if not okay: _toast(run.error); return
	_sync()
	_update_editor(id)
	changed.emit()

func _artifact_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for copy: Dictionary in run.state["owned_artifacts"]:
		var id := str(copy["id"])
		if seen.has(id): continue
		seen[id] = true
		var entry: Dictionary = artifacts[id]
		if selected_element == "all" or entry["element"] == selected_element: result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["id"]) < str(b["id"]))
	return result

func _build_artifact_editor() -> void:
	if initial: return
	view_mode = "artifacts"
	_reset()
	artifact_rows.clear()
	_editor_heading()
	_panel(content, Rect2(219, 172, 939, 597), Color("#142e29ed"), Color("#88744d"))
	_panel(content, Rect2(1187, 178, 347, 528), Color("#0b211fef"), Color("#bd9d6566"))
	_text(content, "随身法宝", Rect2(1200, 124, 320, 41), 27, GOLD, true)
	var filters := ["all"] + BattleRules.ELEMENTS
	for i in filters.size():
		var filter: String = filters[i]
		var button := _button(content, "全部" if filter == "all" else BattleRules.element_name(filter) + "系", Rect2(63, 185 + i * 85, 132, 64), func(): selected_element = filter; _build_artifact_editor(), GOLD if filter == "all" else BattleRules.color(filter))
		if filter == selected_element: button.add_theme_stylebox_override("normal", _style(Color("#385246"), GOLD if filter == "all" else BattleRules.color(filter)))
	artifact_page = 0
	artifact_motion = CardPageMotion.new()
	content.add_child(artifact_motion)
	artifact_motion.configure(_artifact_entries(), 6 if PlatformUI.is_touch() else 8, _create_artifact_card)
	artifact_motion.turn_started.connect(func(next: int, _motion: Tween): artifact_page = next; _artifact_navigation())
	artifact_motion.turn_finished.connect(func(): page_turn_busy = false)
	artifact_previous = _button(content, "‹", Rect2(546, 805, 72, 58), _artifact_turn.bind(-1))
	artifact_page_label = _text(content, "", Rect2(644, 805, 140, 58), 21, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	artifact_next = _button(content, "›", Rect2(810, 805, 72, 58), _artifact_turn.bind(1))
	_artifact_navigation()
	for i in ArtifactLibrary.SLOTS.size():
		var slot: String = ArtifactLibrary.SLOTS[i]
		var row := ArtifactLoadoutRow.new()
		row.position = Vector2(1195, 211 + i * 152)
		row.configure(slot, artifacts.get(str(draft_loadout.get(slot, "")), {}))
		row.equipped.connect(_equip_artifact)
		row.remove_requested.connect(_unequip_artifact)
		row.inspect_requested.connect(func(item: Dictionary, source: Control): inspect_requested.emit(item, source))
		content.add_child(row)
		artifact_rows[slot] = row
	_button(content, "收起行囊", Rect2(1187, 805, 347, 58), func(): back_requested.emit())
	if run.state["owned_artifacts"].is_empty(): _text(content, "尚无法宝", Rect2(350, 380, 660, 70), 32, JADE, true, HORIZONTAL_ALIGNMENT_CENTER)

func _create_artifact_card(entry: Dictionary, index: int, sheet: Control) -> Control:
	var node := ArtifactLibraryCard.new()
	node.configure(entry, Vector2(180, 252) if PlatformUI.is_touch() else Vector2(182, 254))
	node.position = Vector2(267 + (index % 3) * 300, 190 + (index / 3) * 302) if PlatformUI.is_touch() else Vector2(245 + (index % 4) * 222, 205 + (index / 4) * 279)
	node.set_equipped(draft_loadout.values().has(entry["id"]))
	node.equip_requested.connect(_equip_artifact_id)
	node.inspect_requested.connect(func(item: Dictionary, source: Control): if not page_turn_busy: inspect_requested.emit(item, source))
	sheet.add_child(node)
	return node

func _artifact_turn(direction: int) -> void:
	if page_turn_busy or get_viewport().gui_is_dragging(): return
	var next := clampi(artifact_page + direction, 0, artifact_motion.page_roots.size() - 1)
	if next == artifact_page: return
	page_turn_busy = true
	GameAudio.play_sfx("page_turn", 0.0, 100)
	artifact_motion.turn_to(next, direction)

func _artifact_navigation() -> void:
	artifact_page_label.text = "%d / %d" % [artifact_page + 1, artifact_motion.page_roots.size()]
	artifact_previous.disabled = artifact_page == 0
	artifact_next.disabled = artifact_page == artifact_motion.page_roots.size() - 1

func _equip_artifact(slot: String, id: String) -> void:
	if str(draft_loadout.get(slot, "")) == id: return
	var uid := available_uid("artifacts", id)
	if uid.is_empty() or not artifacts.has(id) or artifacts[id]["slot"] != slot: return
	if not run.toggle_artifact(uid): _toast(run.error); return
	_sync()
	_refresh_artifact_row(slot)
	_refresh_artifact_cards()
	changed.emit()

func _unequip_artifact(slot: String) -> void:
	var uid := str(run.state["loadout"].get(slot, ""))
	if uid.is_empty(): return
	if not run.toggle_artifact(uid): _toast(run.error); return
	_sync()
	_refresh_artifact_row(slot)
	_refresh_artifact_cards()
	changed.emit()

func _refresh_artifact_cards() -> void:
	if not is_instance_valid(artifact_motion): return
	for views: Array in artifact_motion.page_views:
		for node: ArtifactLibraryCard in views: node.set_equipped(draft_loadout.values().has(node.entry["id"]))

func refresh_owned() -> void:
	var previous_page := page
	var scroll := row_scroll.scroll_vertical if is_instance_valid(row_scroll) else 0
	for motion: CardPageMotion in cached_pages.values(): motion.queue_free()
	cached_pages.clear()
	_sync()
	if view_mode == "artifacts": _build_artifact_editor()
	else:
		_build_editor(false)
		row_scroll.set_deferred("scroll_vertical", scroll)
		if previous_page > 0: _change_page(mini(previous_page, page_motion.page_roots.size() - 1))

func go_back() -> void: back_requested.emit()
