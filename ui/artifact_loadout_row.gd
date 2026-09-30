class_name ArtifactLoadoutRow
extends Panel

signal equipped(slot: String, id: String)
signal remove_requested(slot: String)
signal inspect_requested(entry: Dictionary, source: Control)

var slot := ""
var entry: Dictionary = {}
var hovered := false
var art: TextureRect
var title: Label
var category: Label
var remove_button: Button
var frame: StyleBoxFlat

func configure(slot_name: String, data: Dictionary) -> void:
	slot = slot_name
	custom_minimum_size = Vector2(330, 94)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if art == null:
		frame = StyleBoxFlat.new()
		frame.bg_color = Color("#102620")
		frame.set_border_width_all(1)
		frame.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", frame)
		art = TextureRect.new()
		art.position = Vector2(3, 3)
		art.size = Vector2(324, 88)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		title = Label.new()
		title.position = Vector2(18, 27)
		title.size = Vector2(280, 38)
		title.add_theme_font_size_override("font_size", 25)
		title.add_theme_color_override("font_color", Color("#fff3dc"))
		title.add_theme_color_override("font_shadow_color", Color.BLACK)
		title.add_theme_constant_override("shadow_offset_y", 2)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(title)
		category = Label.new()
		category.position = Vector2(18, 5)
		category.size = Vector2(260, 26)
		category.add_theme_font_size_override("font_size", 16)
		category.add_theme_color_override("font_color", Color("#e4c795"))
		category.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(category)
		remove_button = Button.new()
		remove_button.text = "×"
		remove_button.position = Vector2(291, 29)
		remove_button.size = Vector2(30, 36)
		remove_button.flat = true
		remove_button.add_theme_font_size_override("font_size", 27)
		remove_button.pressed.connect(func(): remove_requested.emit(slot))
		add_child(remove_button)
	category.text = ArtifactLibrary.SLOT_NAMES[slot]
	set_entry(data)

func set_entry(data: Dictionary) -> void:
	entry = data
	var tint := BattleRules.color(str(entry.get("element", "metal"))) if not entry.is_empty() else Color("#8e866e")
	frame.border_color = Color(tint, 0.7)
	var path := "res://assets/artifacts/%s.webp" % str(entry.get("art_id", entry.get("id", "")))
	art.texture = load(path) if ResourceLoader.exists(path) else null
	art.modulate = Color(0.63, 0.66, 0.63, 0.53) if art.texture != null else Color.WHITE
	title.text = str(entry.get("name", "拖入法宝"))
	remove_button.visible = not entry.is_empty()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "artifact" and data.get("slot") == slot

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	equipped.emit(slot, str(data["id"]))

func _process(_delta: float) -> void:
	var drag_data: Variant = get_viewport().gui_get_drag_data() if get_viewport().gui_is_dragging() else null
	var over := _can_drop_data(Vector2.ZERO, drag_data) and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
	if hovered != over:
		hovered = over
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not entry.is_empty():
		inspect_requested.emit(entry, self)
		accept_event()

func _draw() -> void:
	if hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#f5d99f2e"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("#ffe8b2"), false, 3)
