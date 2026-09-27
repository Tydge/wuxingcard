class_name MainMenu
extends Control

signal test_requested(deck: Dictionary)

const ENTRY_SCRIPT := preload("res://ui/menu_entry.gd")
const ATMOSPHERE_SCRIPT := preload("res://ui/menu_atmosphere.gd")
const GOLD := Color("#e4c795")
const INK := Color("#0a1b1c")
const JADE := Color("#a9c9bb")
const CARD_WIDTH := 156.0
const PAGE_SIZE := 14
const INSPECT_WIDTH := 400.0

var cards: Dictionary
var summons: Dictionary
var inspect_keywords: CardKeywordPopup
var card_factory: Callable
var brush_font: Font
var content: Control
var atmosphere: Control
var view_mode := "home"
var selected_element := "all"
var page := 0
var filtered_cards: Array[Dictionary] = []
var card_nodes: Array[Control] = []
var filter_buttons: Dictionary = {}
var mode_buttons: Dictionary = {}
var inspector: Control
var inspect_card: Control
var inspect_source: Control
var inspect_origin := Vector2.ZERO
var inspect_tween: Tween
var closing_inspector := false
var page_label: Label
var deck_store_path := DeckStore.DEFAULT_PATH
var workshop: DeckWorkshop
var inspect_origin_scale := 1.0
var page_turn_busy := false
var page_turn_tween: Tween
var page_motion: CardPageMotion
var cached_pages := {}
var previous_page_button: Button
var next_page_button: Button

func configure(card_data: Dictionary, factory: Callable, summon_data: Dictionary = {}) -> void:
	cards = card_data
	summons = summon_data
	card_factory = factory

func _exit_tree() -> void:
	for motion: CardPageMotion in cached_pages.values(): motion.finish_loading()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brush_font = GameFonts.title()
	var background := TextureRect.new()
	var path := "res://assets/backgrounds/mountain_gate.webp"
	background.texture = load(path) if ResourceLoader.exists(path) else load("res://assets/backgrounds/arena.webp")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	# Side gradients preserve the landscape while keeping menu lettering legible.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color("#041515c9"), Color("#04151510"), Color("#04151500"), Color("#041515c9")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	atmosphere = ATMOSPHERE_SCRIPT.new()
	add_child(atmosphere)
	_show_home()
	_collection_motion("all", _collection_cards("all"))

func _reset_content() -> void:
	page_turn_busy = false
	if page_turn_tween != null and page_turn_tween.is_running(): page_turn_tween.kill()
	page_turn_tween = null
	for motion: CardPageMotion in cached_pages.values():
		if motion.get_parent() == content: motion.reparent(self)
		motion.hide()
		motion.reset_page()
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	card_nodes.clear()

func _show_home() -> void:
	view_mode = "home"
	atmosphere.set("collection", false)
	_reset_content()
	mode_buttons.clear()
	_text(content, "仙侠 · 五行卡牌", Rect2(114, 88, 320, 32), 19, JADE)
	var title := _text(content, "五行\n命盘", Rect2(104, 143, 440, 252), 103, GOLD, true)
	title.add_theme_color_override("font_shadow_color", Color("#021819"))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 5)
	_text(content, "执掌五行，演化万法。", Rect2(117, 451, 400, 40), 26, Color("#e0dec8"), true)
	_text(content, " · ".join(BattleRules.ELEMENTS.map(BattleRules.element_name)), Rect2(118, 508, 420, 32), 17, JADE)
	var featured := ["metal_chime_card", "water_conch_card", "fire_raven_card"]
	for i in featured.size():
		if not cards.has(featured[i]): continue
		var card: Control = card_factory.call(cards[featured[i]], Vector2(142, 198.8))
		content.add_child(card)
		card.position = Vector2(175 + i * 124, 618 - (20 if i == 1 else 0))
		card.pivot_offset = card.size / 2.0
		card.rotation_degrees = float(i - 1) * 11.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.modulate = Color("#d9e7dd")
	var entries := [
		["rogue", "肉鸽模式", "踏入秘境，探寻未知", false],
		["arena", "竞技模式", "以五行之术，论道争锋", false],
		["endless", "无尽模式", "长路无尽，万法归一", false],
		["test", "测试模式", "编修卡组 · 入阵试法", true],
		["collection", "卡牌一览", "五行法术 · 灵物图鉴", true]]
	for i in entries.size():
		var entry: Array = entries[i]
		var button: MenuEntry = ENTRY_SCRIPT.new()
		button.configure(entry[0], entry[1], entry[2], entry[3], brush_font)
		button.position = Vector2(1088, 178 + i * 115)
		content.add_child(button)
		mode_buttons[entry[0]] = button
		if entry[0] == "test":
			button.pressed.connect(_show_decks)
		elif entry[0] == "collection":
			button.pressed.connect(_show_collection)
		button.modulate.a = 0.0
		var entrance := button.create_tween()
		entrance.tween_interval(0.08 * i)
		entrance.tween_property(button, "modulate:a", 1.0, 0.45)
	_text(content, "五行 · 命盘", Rect2(114, 836, 350, 28), 16, Color("#a0b5a5"))

func _show_decks() -> void:
	view_mode = "decks"
	atmosphere.set("collection", true)
	_reset_content()
	workshop = DeckWorkshop.new()
	workshop.configure(cards, card_factory, summons, deck_store_path)
	workshop.back_requested.connect(_show_home)
	workshop.battle_requested.connect(func(deck: Dictionary): test_requested.emit(deck))
	workshop.inspect_requested.connect(_open_inspector)
	content.add_child(workshop)

func _show_collection() -> void:
	view_mode = "collection"
	atmosphere.set("collection", true)
	selected_element = "all"
	page = 0
	_build_collection()

func _build_collection() -> void:
	_reset_content()
	filter_buttons.clear()
	var veil := ColorRect.new()
	veil.color = Color("#061c20ed")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(veil)
	_text(content, "藏经阁", Rect2(65, 50, 270, 70), 49, GOLD, true)
	_text(content, "卡牌一览", Rect2(310, 71, 220, 40), 20, JADE)
	_button(content, "返回山门", Rect2(1340, 65, 180, 48), _show_home)
	_panel(content, Rect2(244, 171, 1290, 599), Color("#152e2af2"), Color("#88744d"))
	filtered_cards = _collection_cards(selected_element)
	var page_count := maxi(1, ceili(float(filtered_cards.size()) / PAGE_SIZE))
	page = clampi(page, 0, page_count - 1)
	var heading := "五行全卷" if selected_element == "all" else BattleRules.element_name(selected_element) + "系卷宗"
	_text(content, "%s · %d 张" % [heading, filtered_cards.size()], Rect2(1030, 116, 496, 34), 18, JADE, false, HORIZONTAL_ALIGNMENT_RIGHT)
	var filters := ["all"] + BattleRules.ELEMENTS
	for i in filters.size():
		var element: String = filters[i]
		var count := cards.size() if element == "all" else _element_count(element)
		var name := "全部" if element == "all" else BattleRules.element_name(element) + "系"
		var tint := GOLD if element == "all" else BattleRules.color(element)
		var button := _button(content, "%s   %d" % [name, count], Rect2(62, 185 + i * 85, 154, 64), _filter.bind(element), tint)
		button.add_theme_font_override("font", brush_font)
		button.add_theme_font_size_override("font_size", 25)
		button.add_theme_stylebox_override("normal", _style(Color("#385246") if element == selected_element else INK, tint if element == selected_element else Color(tint, 0.25)))
		filter_buttons[element] = button
	page_motion = _collection_motion(selected_element, filtered_cards)
	page_motion.reparent(content)
	page_motion.show()
	card_nodes.assign(page_motion.page_views[0])
	previous_page_button = _button(content, "上一页", Rect2(650, 806, 120, 48), _change_page.bind(-1))
	page_label = _text(content, "", Rect2(795, 806, 140, 48), 21, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	next_page_button = _button(content, "下一页", Rect2(960, 806, 120, 48), _change_page.bind(1))
	_update_page_navigation()
	_text(content, "点击卡牌，展开卷宗", Rect2(1170, 810, 355, 40), 16, JADE, false, HORIZONTAL_ALIGNMENT_RIGHT)

func _element_count(element: String) -> int:
	var count := 0
	for card in cards.values():
		if card["element"] == element: count += 1
	return count

func _filter(element: String) -> void:
	selected_element = element
	page = 0
	_build_collection()

func _collection_cards(element: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in cards.values():
		if element == "all" or card["element"] == element: result.append(card)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		var ai := BattleRules.ELEMENTS.find(a["element"])
		var bi := BattleRules.ELEMENTS.find(b["element"])
		if ai != bi: return ai < bi
		if int(a["cost"]) != int(b["cost"]): return int(a["cost"]) < int(b["cost"])
		return str(a["id"]) < str(b["id"]))
	return result

func _collection_motion(element: String, data: Array[Dictionary]) -> CardPageMotion:
	if cached_pages.has(element): return cached_pages[element]
	var motion := CardPageMotion.new()
	add_child(motion)
	motion.hide()
	motion.turn_started.connect(func(next: int, tween: Tween):
		page = next
		card_nodes.assign(motion.page_views[next])
		page_turn_tween = tween
		_update_page_navigation())
	motion.turn_finished.connect(func(): page_turn_busy = false; page_turn_tween = null)
	motion.configure(data, PAGE_SIZE, _create_collection_card)
	cached_pages[element] = motion
	return motion

func _create_collection_card(card: Dictionary, index: int, sheet: Control) -> Control:
	var pos := Vector2(283 + (index % 7) * 177, 209 + (index / 7) * 276)
	var slot := _panel(sheet, Rect2(pos - Vector2(10, 10), Vector2(176, 263)), Color("#091a193d"), Color("#b79a5b22"))
	var view: Control = card_factory.call(card, Vector2(CARD_WIDTH, CARD_WIDTH * 1.4))
	sheet.add_child(view)
	view.position = pos
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	view.gui_input.connect(_card_input.bind(card, view))
	var kind := "召唤" if view is SummonCardView else "法术"
	_text(slot, "%s · %d费" % [kind, int(card["cost"])], Rect2(0, 239, 176, 22), 14, Color("#a6b7a2"), false, HORIZONTAL_ALIGNMENT_CENTER)
	return view

func _update_page_navigation() -> void:
	var count := page_motion.page_roots.size()
	page_label.text = "%d / %d" % [page + 1, count]
	previous_page_button.disabled = page == 0
	next_page_button.disabled = page == count - 1

func _change_page(direction: int) -> void:
	if page_turn_busy or is_instance_valid(inspector): return
	var next := clampi(page + direction, 0, page_motion.page_roots.size() - 1)
	if next == page: return
	page_turn_busy = true
	page_motion.turn_to(next, direction)

func _card_input(event: InputEvent, card: Dictionary, source: Control) -> void:
	if page_turn_busy: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_inspector(card, source)

func _open_inspector(card: Dictionary, source: Control) -> void:
	if is_instance_valid(inspector): return
	inspect_source = source
	inspect_origin = source.global_position - global_position
	inspect_origin_scale = source.size.x * source.get_global_transform().get_scale().x / (INSPECT_WIDTH * get_global_transform().get_scale().x)
	closing_inspector = false
	inspector = Control.new()
	inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(inspector)
	inspector.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: _close_inspector())
	var shade := ColorRect.new()
	shade.color = Color("#010e12dc")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector.add_child(shade)
	shade.modulate.a = 0.0
	inspect_card = card_factory.call(card, Vector2(INSPECT_WIDTH, INSPECT_WIDTH * 1.4))
	inspector.add_child(inspect_card)
	inspect_card.mouse_filter = Control.MOUSE_FILTER_STOP
	inspect_card.position = inspect_origin
	inspect_card.scale = Vector2.ONE * inspect_origin_scale
	source.visible = false
	var hint := _text(inspector, "点击空白处收起 · Esc 返回", Rect2(500, 775, 600, 40), 18, JADE, false, HORIZONTAL_ALIGNMENT_CENTER)
	hint.modulate.a = 0.0
	var entries := CardKeywords.entries(card, summons)
	if not entries.is_empty():
		inspect_keywords = CardKeywordPopup.new()
		inspector.add_child(inspect_keywords)
		inspect_keywords.configure(entries, Rect2(600, 133, INSPECT_WIDTH, INSPECT_WIDTH * 1.4), size)
	inspect_tween = inspector.create_tween().set_parallel(true)
	inspect_tween.tween_property(inspect_card, "position", Vector2(600, 133), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	inspect_tween.tween_property(inspect_card, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	inspect_tween.tween_property(shade, "modulate:a", 1.0, 0.3)
	inspect_tween.tween_property(hint, "modulate:a", 1.0, 0.4)

func _close_inspector() -> void:
	if not is_instance_valid(inspector) or closing_inspector: return
	closing_inspector = true
	if is_instance_valid(inspect_keywords):
		inspect_keywords.hide()
		inspect_keywords.queue_free()
	inspect_keywords = null
	if inspect_tween != null and inspect_tween.is_running(): inspect_tween.kill()
	inspect_tween = inspector.create_tween().set_parallel(true)
	inspect_tween.tween_property(inspect_card, "position", inspect_origin, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	inspect_tween.tween_property(inspect_card, "scale", Vector2.ONE * inspect_origin_scale, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	inspect_tween.tween_property(inspector.get_child(0), "modulate:a", 0.0, 0.32)
	inspect_tween.tween_property(inspector.get_child(2), "modulate:a", 0.0, 0.2)
	inspect_tween.chain().tween_callback(func():
		if is_instance_valid(inspect_source): inspect_source.visible = true
		inspector.queue_free()
		inspector = null
		inspect_card = null)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(inspector): _close_inspector()
		elif view_mode == "collection": _show_home()
		elif view_mode == "decks" and is_instance_valid(workshop): workshop.go_back()
		get_viewport().set_input_as_handled()
	elif view_mode == "collection" and not is_instance_valid(inspector):
		if event.is_action_pressed("ui_right"): _change_page(1)
		elif event.is_action_pressed("ui_left"): _change_page(-1)
	elif view_mode == "decks" and is_instance_valid(workshop) and not is_instance_valid(inspector) and not is_instance_valid(workshop.modal):
		if event.is_action_pressed("ui_right"): workshop.call("_change_page", 1)
		elif event.is_action_pressed("ui_left"): workshop.call("_change_page", -1)

func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style

func _panel(parent: Node, rect: Rect2, fill: Color, edge: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style(fill, edge))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _text(parent: Node, value: String, rect: Rect2, font_size: int, tint: Color, brush: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
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
