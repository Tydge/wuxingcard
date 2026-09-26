class_name MenuEntry
extends Button

const GOLD := Color("#d8bc81")
var mode_id := ""
var accent := Color("#c7a967")
var glow := 0.0

func configure(id: String, caption: String, subtitle: String, available: bool, font: Font) -> void:
	mode_id = id
	disabled = not available
	size = Vector2(380, 94)
	custom_minimum_size = size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	accent = Color("#e3b979") if id == "test" else Color("#8ec6b7") if id == "collection" else GOLD
	add_text(caption, Vector2(82, 10), Vector2(280, 42), 31, Color("#fff0ce") if available else Color("#c2b99f"), font)
	add_text(subtitle, Vector2(84, 53), Vector2(280, 26), 15, Color("#b3c6bb") if available else Color("#8c9890"))
	if not available:
		add_text("未开放", Vector2(283, 20), Vector2(78, 30), 14, Color("#a6a790"))
		get_child(0).size.x = 195

func add_text(value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color, font: Font = null) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	add_child(label)

func _process(delta: float) -> void:
	var target := 1.0 if not disabled and (is_hovered() or has_focus()) else 0.0
	glow = move_toward(glow, target, delta * 5.0)
	queue_redraw()

func _draw() -> void:
	var outline := PackedVector2Array([Vector2(0, 18), Vector2(18, 4), Vector2(362, 4), Vector2(379, 18), Vector2(379, 76), Vector2(362, 90), Vector2(18, 90), Vector2(0, 76)])
	var shadow := outline.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(3, 5)
	draw_colored_polygon(shadow, Color("#020a0bb3"))
	var base := Color("#142b29ef") if mode_id != "test" else Color("#543627ee")
	if disabled:
		base = Color("#122424de")
	draw_colored_polygon(outline, base.lightened(glow * 0.09))
	var edge := accent * Color(1, 1, 1, 0.36 + glow * 0.64)
	var loop := outline.duplicate()
	loop.append(outline[0])
	draw_polyline(loop, edge, 1.3 + glow, true)
	draw_line(Vector2(79, 84), Vector2(348, 84), Color(accent, 0.17 + glow * 0.3), 1.0, true)
	for x in [19.0, 360.0]:
		draw_line(Vector2(x - 8, 11), Vector2(x + 8, 11), Color(accent, 0.6), 1.2, true)
		draw_circle(Vector2(x, 11), 2.0, accent)
	var center := Vector2(43, 46)
	draw_circle(center, 27, Color(accent, 0.06 + glow * 0.12))
	draw_arc(center, 26, 0, TAU, 48, Color(accent, 0.45 + glow * 0.4), 1.2, true)
	_draw_emblem(center, Color(accent, 0.62 if disabled else 0.95))
	if has_focus() and not disabled:
		draw_arc(center, 31, -PI * 0.5, PI * 1.5, 48, accent, 1.0, true)

func _draw_emblem(c: Vector2, color: Color) -> void:
	match mode_id:
		"rogue":
			draw_polyline(PackedVector2Array([c + Vector2(-18, 12), c + Vector2(-4, -13), c + Vector2(4, 1), c + Vector2(10, -5), c + Vector2(19, 12)]), color, 2, true)
			draw_line(c + Vector2(-18, 14), c + Vector2(19, 14), color, 1, true)
		"arena":
			for sign_value in [-1.0, 1.0]:
				draw_line(c + Vector2(-14 * sign_value, 17), c + Vector2(13 * sign_value, -17), color, 3, true)
				draw_line(c + Vector2(-15 * sign_value, 2), c + Vector2(-2 * sign_value, 12), color, 2, true)
		"endless":
			for sign_value in [-1.0, 1.0]:
				draw_arc(c + Vector2(10 * sign_value, 0), 11, -PI * 0.8, PI * 0.8, 24, color, 2, true)
			draw_line(c + Vector2(-2, -8), c + Vector2(2, 8), color, 2, true)
		"test":
			draw_circle(c, 17, color)
			draw_arc(c, 17, -PI * 0.5, PI * 0.5, 32, Color("#533627"), 17, true)
			draw_circle(c + Vector2(0, -8), 8, color)
			draw_circle(c + Vector2(0, 8), 8, Color("#533627"))
			draw_circle(c + Vector2(0, -8), 2.5, Color("#533627"))
			draw_circle(c + Vector2(0, 8), 2.5, color)
		"collection":
			for i in 3:
				var rect := Rect2(c + Vector2(-17 + i * 6, -16 + i * 3), Vector2(23, 29))
				draw_rect(rect, Color("#142b29"))
				draw_rect(rect, color, false, 1.5)
			draw_circle(c + Vector2(7, 4), 4, color)
