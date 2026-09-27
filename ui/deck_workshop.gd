class_name DeckWorkshop
extends Control

signal back_requested
signal battle_requested(deck: Dictionary)
signal inspect_requested(card: Dictionary, source: Control)

const GOLD := Color("#e4c795")
const JADE := Color("#a9c9bb")
const INK := Color("#0a1b1c")
const CARD_WIDTH := 140.0
const PAGE_SIZE := 12

var cards: Dictionary
var summons: Dictionary
var factory: Callable
var store: DeckStore
var brush_font: Font
var content: Control
var effects: Control
var view_mode := "library"
var selected_id := ""
var edit_id := ""
var edit_name := ""
var draft: Array[String] = []
var baseline: Dictionary = {}
var selected_element := "all"
var page := 0
var filtered_cards: Array[Dictionary] = []
var card_nodes: Array[DeckLibraryCard] = []
var filter_buttons := {}
var deck_buttons := {}
var row_nodes := {}
var name_edit: LineEdit
var total_label: Label
var save_button: Button
var play_button: Button
var random_button: Button
var new_button: Button
var drop_zone: DeckDropZone
var row_scroll: ScrollContainer
var row_column: VBoxContainer
var message: Label
var message_tween: Tween
var modal: Control
var page_turn_busy := false
var page_turn_tween: Tween
var content_generation := 0

func configure(data: Dictionary, card_factory: Callable, summon_data: Dictionary, path: String = DeckStore.DEFAULT_PATH) -> void:
	cards = data
	summons = summon_data
	factory = card_factory
	store = DeckStore.new(cards, path)
	store.load_decks()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brush_font = GameFonts.title()
	effects = Control.new()
	effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(effects)
	_show_library()

func _reset(animate: bool = true) -> void:
	content_generation += 1
	page_turn_busy = false
	if page_turn_tween != null and page_turn_tween.is_running(): page_turn_tween.kill()
	page_turn_tween = null
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	move_child(effects, get_child_count() - 1)
	var veil := ColorRect.new()
	veil.color = Color("#071d20da")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(veil)
	card_nodes.clear()
	row_nodes.clear()
	if animate:
		content.modulate.a = 0.0
		content.create_tween().tween_property(content, "modulate:a", 1.0, 0.2)

func _show_library() -> void:
	view_mode = "library"
	_reset()
	deck_buttons.clear()
	_text(content, "试炼", Rect2(66, 49, 290, 74), 50, GOLD, true)
	_text(content, "我的卡组", Rect2(225, 73, 270, 36), 21, JADE)
	_button(content, "返回山门", Rect2(1340, 64, 180, 48), func(): back_requested.emit())
	_panel(content, Rect2(65, 166, 440, 628), Color("#112c28ed"), Color("#b8955955"))
	random_button = _button(content, "随机卡组", Rect2(87, 188, 396, 74), func(): selected_id = ""; _show_library(), GOLD)
	decorate_selection(random_button, selected_id.is_empty())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(87, 280)
	scroll.size = Vector2(396, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	for entry in store.decks:
		var caption := str(entry["name"])
		var valid := store.problem(entry["cards"]).is_empty()
		var button := _button(column, "", Rect2(0, 0, 378, 78), _open_editor.bind(entry))
		button.custom_minimum_size = Vector2(378, 78)
		_text(button, caption, Rect2(18, 8, 330, 34), 23, GOLD, true)
		_text(button, "%d 张%s" % [entry["cards"].size(), "" if valid else " · 草稿"], Rect2(20, 43, 322, 23), 15, JADE)
		decorate_selection(button, selected_id == entry["id"])
		deck_buttons[entry["id"]] = button
	if store.decks.is_empty():
		_text(column, "尚无成卷", Rect2(0, 0, 378, 86), 23, Color("#a0b3a1"), true, HORIZONTAL_ALIGNMENT_CENTER)
	new_button = _button(content, "+  新建卡组", Rect2(87, 724, 396, 48), func(): _open_editor({}))
	_build_showcase()

func decorate_selection(button: Button, selected: bool) -> void:
	if selected:
		button.add_theme_stylebox_override("normal", _style(Color("#324536"), GOLD))

func _build_showcase() -> void:
	var deck := store.find_deck(selected_id)
	var random := deck.is_empty()
	_panel(content, Rect2(547, 166, 975, 628), Color("#0c262369"), Color("#b895592a"))
	_text(content, "随缘成阵" if random else str(deck["name"]), Rect2(593, 199, 880, 72), 43, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	_text(content, "五行流转 · 25 张" if random else "%d 张%s" % [deck["cards"].size(), " · 草稿" if not store.problem(deck["cards"]).is_empty() else ""], Rect2(637, 277, 796, 35), 20, JADE, false, HORIZONTAL_ALIGNMENT_CENTER)
	var featured: Array[String] = ["metal_chime_card", "wood_deer_card", "water_conch_card"]
	if not random:
		featured.clear()
		for id in _sorted_unique(deck["cards"]):
			featured.append(id)
			if featured.size() == 3: break
	for i in featured.size():
		var view: Control = factory.call(cards[featured[i]], Vector2(195, 273))
		content.add_child(view)
		view.position = Vector2(755 + i * 178, 387 - (28 if i == 1 else 0))
		view.pivot_offset = view.size / 2.0
		view.rotation_degrees = (i - 1) * 8.0
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		view.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: inspect_requested.emit(cards[featured[i]], view))
	if not random and featured.is_empty():
		_text(content, "万法，由此起笔。", Rect2(710, 420, 650, 70), 33, JADE, true, HORIZONTAL_ALIGNMENT_CENTER)
	play_button = _button(content, "入阵", Rect2(1204, 711, 266, 60), _start_selected, GOLD)
	play_button.add_theme_font_override("font", brush_font)
	play_button.add_theme_font_size_override("font_size", 30)
	play_button.disabled = not random and not store.problem(deck["cards"]).is_empty()
	if not random:
		_button(content, "编修", Rect2(595, 716, 145, 50), _open_editor.bind(deck))
		_button(content, "删除", Rect2(757, 716, 120, 50), _ask_delete.bind(deck), Color("#cd9a80"))
		if play_button.disabled:
			_text(content, store.problem(deck["cards"]), Rect2(1020, 723, 163, 35), 18, JADE, false, HORIZONTAL_ALIGNMENT_RIGHT)

func _start_selected() -> void:
	var deck := store.find_deck(selected_id)
	if not deck.is_empty() and not store.problem(deck["cards"]).is_empty(): return
	battle_requested.emit(deck)

func _open_editor(deck: Dictionary) -> void:
	edit_id = str(deck.get("id", ""))
	selected_id = edit_id
	edit_name = str(deck.get("name", "新卡组"))
	draft.assign(deck.get("cards", []))
	baseline = {"name": edit_name, "cards": draft.duplicate()}
	selected_element = "all"
	page = 0
	_build_editor()

func _build_editor(animate: bool = true) -> void:
	view_mode = "editor"
	_reset(animate)
	filter_buttons.clear()
	_text(content, "编修", Rect2(65, 48, 235, 70), 49, GOLD, true)
	_text(content, "五行藏卷", Rect2(250, 73, 290, 36), 20, JADE)
	_button(content, "返回卡组", Rect2(1340, 64, 180, 48), _leave_editor)
	_panel(content, Rect2(219, 172, 939, 597), Color("#142e29ed"), Color("#88744d"))
	var filters := ["all"] + BattleRules.ELEMENTS
	for i in filters.size():
		var element: String = filters[i]
		var tint := GOLD if element == "all" else BattleRules.color(element)
		var caption := "全部" if element == "all" else BattleRules.element_name(element) + "系"
		var button := _button(content, caption, Rect2(63, 185 + i * 85, 132, 64), _filter.bind(element), tint)
		button.add_theme_font_override("font", brush_font)
		button.add_theme_font_size_override("font_size", 25)
		if element == selected_element: button.add_theme_stylebox_override("normal", _style(Color("#385246"), tint))
		filter_buttons[element] = button
	filtered_cards.clear()
	for card in cards.values():
		if selected_element == "all" or selected_element == card["element"]: filtered_cards.append(card)
	filtered_cards.sort_custom(_card_less)
	var pages := maxi(1, ceili(float(filtered_cards.size()) / PAGE_SIZE))
	page = clampi(page, 0, pages - 1)
	for index in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, filtered_cards.size())):
		var local := index - page * PAGE_SIZE
		var view := DeckLibraryCard.new()
		view.configure(filtered_cards[index], factory, CARD_WIDTH)
		view.position = Vector2(247 + (local % 6) * 148, 211 + (local / 6) * 277)
		view.inspect_requested.connect(func(card: Dictionary, source: Control):
			if not page_turn_busy: inspect_requested.emit(card, source))
		view.add_requested.connect(_add_card)
		view.drag_denied.connect(func(): _toast("同名卡牌最多%d张" % DeckStore.MAX_COPIES))
		content.add_child(view)
		card_nodes.append(view)
	_button(content, "‹", Rect2(546, 805, 72, 48), _change_page.bind(-1)).disabled = page == 0
	_text(content, "%d / %d" % [page + 1, pages], Rect2(644, 805, 140, 48), 21, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	_button(content, "›", Rect2(810, 805, 72, 48), _change_page.bind(1)).disabled = page == pages - 1
	_text(content, "拖入卡组 · 点击查看", Rect2(228, 772, 926, 28), 15, JADE, false, HORIZONTAL_ALIGNMENT_CENTER)
	name_edit = LineEdit.new()
	name_edit.position = Vector2(1205, 124)
	name_edit.size = Vector2(314, 41)
	name_edit.text = edit_name
	name_edit.max_length = 24
	name_edit.add_theme_font_override("font", brush_font)
	name_edit.add_theme_font_size_override("font_size", 24)
	name_edit.add_theme_color_override("font_color", GOLD)
	name_edit.add_theme_stylebox_override("normal", _style(Color("#122d28c9"), Color("#c3a67060")))
	name_edit.add_theme_stylebox_override("focus", _style(INK, GOLD))
	name_edit.text_changed.connect(func(value: String): edit_name = value)
	content.add_child(name_edit)
	drop_zone = DeckDropZone.new()
	drop_zone.position = Vector2(1187, 178)
	drop_zone.size = Vector2(347, 528)
	drop_zone.add_theme_stylebox_override("panel", _style(Color("#0b211fef"), Color("#bd9d6566")))
	drop_zone.can_add = _can_add
	drop_zone.add_card = _add_card
	content.add_child(drop_zone)
	row_scroll = ScrollContainer.new()
	row_scroll.position = Vector2(14, 14)
	row_scroll.size = Vector2(319, 500)
	row_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	drop_zone.add_child(row_scroll)
	row_column = VBoxContainer.new()
	row_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_column.add_theme_constant_override("separation", 6)
	row_column.mouse_filter = Control.MOUSE_FILTER_PASS
	row_scroll.add_child(row_column)
	total_label = _text(content, "", Rect2(1195, 712, 327, 32), 21, GOLD, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(content, "20–30 张 · 同名最多 %d 张" % DeckStore.MAX_COPIES, Rect2(1196, 753, 327, 25), 15, JADE, false, HORIZONTAL_ALIGNMENT_CENTER)
	save_button = _button(content, "保存", Rect2(1187, 805, 160, 49), _save)
	play_button = _button(content, "入阵", Rect2(1369, 805, 165, 49), _save_and_play)
	_update_editor()

func _card_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["cost"]) != int(b["cost"]): return int(a["cost"]) < int(b["cost"])
	var ae := BattleRules.ELEMENTS.find(a["element"])
	var be := BattleRules.ELEMENTS.find(b["element"])
	return ae < be if ae != be else str(a["id"]) < str(b["id"])

func _sorted_unique(ids: Array) -> Array[String]:
	var unique: Array[String] = []
	for id in ids:
		if cards.has(id) and not unique.has(id): unique.append(id)
	unique.sort_custom(func(a: String, b: String): return _card_less(cards[a], cards[b]))
	return unique

func _can_add(id: String) -> bool:
	return cards.has(id) and draft.size() < DeckStore.MAX_CARDS and draft.count(id) < DeckStore.MAX_COPIES

func _add_card(id: String, source: Vector2 = Vector2(-1, -1)) -> void:
	if not _can_add(id):
		_toast("最多30张" if draft.size() >= DeckStore.MAX_CARDS else "同名卡牌最多%d张" % DeckStore.MAX_COPIES)
		return
	draft.append(id)
	_update_editor(id)
	if source.x >= 0: _fly_into_row(id, source)

func _remove_card(id: String) -> void:
	var index := draft.find(id)
	if index < 0: return
	draft.remove_at(index)
	_update_editor(id)

func _update_editor(highlight: String = "") -> void:
	for view in card_nodes: view.set_copies(draft.count(view.card["id"]))
	total_label.text = "%d / 30" % draft.size()
	play_button.disabled = not store.problem(draft).is_empty()
	var scroll := row_scroll.scroll_vertical
	for child in row_column.get_children():
		row_column.remove_child(child)
		child.queue_free()
	row_nodes.clear()
	for id in _sorted_unique(draft):
		var row := DeckRow.new()
		row.configure(cards[id], draft.count(id))
		row.pressed.connect(_remove_card.bind(id))
		row.inspect_requested.connect(func(card: Dictionary, source: Control): inspect_requested.emit(card, source))
		row_column.add_child(row)
		row_nodes[id] = row
		if id == highlight:
			row.modulate = Color("#ffeeaa")
			row.create_tween().tween_property(row, "modulate", Color.WHITE, 0.3)
	if draft.is_empty():
		_text(row_column, "拖入第一张卡牌", Rect2(0, 0, 306, 95), 22, JADE, true, HORIZONTAL_ALIGNMENT_CENTER)
	row_scroll.set_deferred("scroll_vertical", scroll)

func _fly_into_row(id: String, source: Vector2) -> void:
	var flying: Control = factory.call(cards[id], Vector2(100, 140))
	flying.position = source - global_position - flying.size / 2.0
	flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying.pivot_offset = flying.size / 2.0
	effects.add_child(flying)
	await get_tree().process_frame
	if not is_instance_valid(row_nodes.get(id)): flying.queue_free(); return
	var row: Control = row_nodes[id]
	var destination := row.global_position - global_position + row.size / 2.0 - flying.size / 2.0
	var tween := flying.create_tween().set_parallel(true)
	tween.tween_property(flying, "position", destination, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flying, "scale", Vector2.ONE * 0.3, 0.24)
	tween.tween_property(flying, "modulate:a", 0.0, 0.14).set_delay(0.1)
	tween.chain().tween_callback(flying.queue_free)
	row_scroll.ensure_control_visible(row)

func _filter(element: String) -> void:
	selected_element = element
	page = 0
	_build_editor(false)

func _change_page(amount: int) -> void:
	if page_turn_busy or view_mode != "editor" or get_viewport().gui_is_dragging(): return
	var next := clampi(page + amount, 0, maxi(0, ceili(float(filtered_cards.size()) / PAGE_SIZE) - 1))
	if next == page: return
	page_turn_busy = true
	var generation := content_generation
	var scroll := row_scroll.scroll_vertical
	page_turn_tween = CardPageMotion.leave(self, card_nodes, amount, func():
		if generation != content_generation or view_mode != "editor": return
		page_turn_tween = null
		page = next
		_build_editor(false)
		row_scroll.set_deferred("scroll_vertical", scroll)
		CardPageMotion.enter(card_nodes, amount, 6)
		page_turn_busy = true
		page_turn_tween = create_tween()
		page_turn_tween.tween_interval(CardPageMotion.SETTLE_SECONDS)
		page_turn_tween.tween_callback(func(): page_turn_busy = false))

func _save() -> void:
	var saved := store.save_deck(edit_id, edit_name, draft)
	if saved.has("error"): _toast(saved["error"]); return
	selected_id = saved["id"]
	_show_library()
	_toast("已保存")

func _save_and_play() -> void:
	if not store.problem(draft).is_empty(): _toast(store.problem(draft)); return
	var saved := store.save_deck(edit_id, edit_name, draft)
	if saved.has("error"): _toast(saved["error"]); return
	selected_id = saved["id"]
	battle_requested.emit(saved)

func _leave_editor() -> void:
	if baseline["name"] == edit_name and baseline["cards"] == draft:
		_show_library()
	else:
		_dialog("留存此卷？", [["保存", func(): _dismiss_modal(); _save()], ["舍弃", func(): _dismiss_modal(); _show_library()], ["继续编修", _dismiss_modal]])

func _ask_delete(deck: Dictionary) -> void:
	_dialog("删除「%s」？" % deck["name"], [["删除", func():
		if store.delete_deck(deck["id"]):
			selected_id = ""
			_dismiss_modal()
			_show_library()
		else: _toast("删除失败，请重试")], ["保留", _dismiss_modal]])

func _dialog(caption: String, choices: Array) -> void:
	if is_instance_valid(modal): return
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	effects.add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color("#020e13b8")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(shade)
	var panel := _panel(modal, Rect2(475, 325, 650, 233), INK, GOLD)
	_text(panel, caption, Rect2(28, 25, 594, 72), 31, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	for i in choices.size():
		var width := 560.0 / choices.size() - 12.0
		_button(panel, choices[i][0], Rect2(40 + i * (width + 12), 140, width, 48), choices[i][1])
	modal.modulate.a = 0.0
	modal.create_tween().tween_property(modal, "modulate:a", 1.0, 0.16)

func _dismiss_modal() -> void:
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	modal = null

func _toast(caption: String) -> void:
	if is_instance_valid(message): message.queue_free()
	message = _text(effects, caption, Rect2(470, 64, 660, 42), 21, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	message.modulate.a = 0.0
	message_tween = message.create_tween()
	message_tween.tween_property(message, "modulate:a", 1.0, 0.12)
	message_tween.tween_interval(1.25)
	message_tween.tween_property(message, "modulate:a", 0.0, 0.2)
	message_tween.tween_callback(message.queue_free)

func go_back() -> void:
	if is_instance_valid(modal): _dismiss_modal()
	elif view_mode == "editor": _leave_editor()
	else: back_requested.emit()

func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style

func _panel(parent: Node, rect: Rect2, fill: Color, edge: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(fill, edge))
	parent.add_child(panel)
	return panel

func _text(parent: Node, caption: String, rect: Rect2, font_size: int, tint: Color, brush: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if brush: label.add_theme_font_override("font", brush_font)
	parent.add_child(label)
	return label

func _button(parent: Node, caption: String, rect: Rect2, action: Callable, tint: Color = GOLD) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _style(INK, Color(tint, 0.45)))
	button.add_theme_stylebox_override("hover", _style(Color("#2d4d42"), tint))
	button.add_theme_stylebox_override("pressed", _style(Color("#3a6050"), tint))
	button.add_theme_stylebox_override("disabled", _style(Color("#142726"), Color("#47554b")))
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_disabled_color", Color("#69786f"))
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
