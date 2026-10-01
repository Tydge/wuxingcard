class_name CampHotspot
extends Button

var caption: Label
var glow := 0.0
var clock := 0.0

func configure(label: String, rect: Rect2, action: Callable, detail: String = "") -> void:
	position = rect.position
	size = rect.size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = detail
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
	caption = Label.new()
	caption.text = label
	caption.position = Vector2(-30, size.y - 40)
	caption.size = Vector2(size.x + 60, 64)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font", GameFonts.title())
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", Color("#ffe4ad"))
	caption.add_theme_color_override("font_shadow_color", Color("#061510"))
	caption.add_theme_constant_override("shadow_outline_size", 9)
	add_child(caption)
	pressed.connect(func(): GameAudio.play_sfx("ui_select", 0.0, 70); action.call())

func _process(delta: float) -> void:
	clock += delta
	glow = move_toward(glow, 1.0 if is_hovered() or has_focus() else 0.0, delta * 5.0)
	caption.position.y = size.y - 40 - glow * 7
	queue_redraw()

func _draw() -> void:
	var at := Vector2(size.x / 2.0, size.y - 51)
	var tint := Color("#f5d391")
	tint.a = 0.4 + 0.15 * sin(clock * 2) + glow * 0.4
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5), at + Vector2(-5, 0)]), tint)
	if glow > 0:
		draw_line(Vector2(25, size.y + 17), Vector2(size.x - 25, size.y + 17), Color(1, 0.86, 0.6, glow * 0.8), 2, true)
