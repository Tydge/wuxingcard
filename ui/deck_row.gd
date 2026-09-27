class_name DeckRow
extends Button

signal inspect_requested(card: Dictionary, source: Control)

var card: Dictionary
var copies := 1
var accent: Color
var art: Texture2D
var glow := 0.0
var title: Label
var count_label: Label
var inspect_anchor: Control

func configure(data: Dictionary, amount: int) -> void:
	card = data
	copies = amount
	accent = BattleRules.color(card["element"])
	custom_minimum_size = Vector2(306, 43)
	size = custom_minimum_size
	# A row handles clicks but must let drag/drop reach the deck parchment.
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var path := "res://assets/cards/generated/%s.webp" % card["id"]
	if ResourceLoader.exists(path): art = load(path)
	for item in [[str(int(card["cost"])), 4, 30, Color("#f9edce")], [card["name"], 42, 215, Color("#f5efdd")], [str(copies), 266, 36, Color("#efd29b")]]:
		var label := Label.new()
		label.text = item[0]
		label.position = Vector2(item[1], 0)
		label.size = Vector2(item[2], 43)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if item[1] != 42 else HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", 18 if item[1] == 42 else 20)
		label.add_theme_color_override("font_color", item[3])
		label.add_theme_color_override("font_shadow_color", Color("#020908"))
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		if item[1] == 42: title = label
		if item[1] == 266: count_label = label
	# Only an invisible origin is needed for inspection. No miniature card or
	# external summon health jewel is mounted inside a deck row.
	inspect_anchor = Control.new()
	inspect_anchor.position = Vector2(151, 2)
	inspect_anchor.size = Vector2(28, 39.2)
	inspect_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inspect_anchor)

func _process(delta: float) -> void:
	glow = move_toward(glow, 1.0 if is_hovered() else 0.0, delta * 7.0)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		inspect_requested.emit(card, inspect_anchor)
		accept_event()

func _draw() -> void:
	draw_style_box(_frame(), Rect2(Vector2.ZERO, size))
	if art != null:
		var source := art.get_size()
		var height := minf(source.y, source.x * 0.32)
		draw_texture_rect_region(art, Rect2(64, 3, 194, 37), Rect2(0, (source.y - height) / 2.0, source.x, height), Color(0.5, 0.55, 0.48, 0.48))
	draw_circle(Vector2(19, 21.5), 14, accent.darkened(0.6))
	draw_arc(Vector2(19, 21.5), 14, 0, TAU, 32, accent, 1.0, true)
	draw_line(Vector2(263, 6), Vector2(263, 37), Color(accent, 0.4), 1.0, true)

func _frame() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#10241f").lerp(accent.darkened(0.75), 0.35 + glow * 0.3)
	style.border_color = Color(accent, 0.3 + glow * 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
