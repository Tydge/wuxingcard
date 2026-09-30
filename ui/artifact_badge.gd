class_name ArtifactBadge
extends Control

var badge_kind := ""
var value := 0
var tint := Color.WHITE

func configure(kind: String, amount: int, color: Color, badge_size: float) -> void:
	badge_kind = kind
	value = amount
	tint = color
	size = Vector2(badge_size, badge_size)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var number := Label.new()
	number.text = str(value)
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.add_theme_font_size_override("font_size", 17 if badge_size < 45 else 26)
	number.add_theme_color_override("font_color", Color("#fff7df"))
	number.add_theme_color_override("font_shadow_color", Color("#051015"))
	number.add_theme_constant_override("shadow_offset_x", 1)
	number.add_theme_constant_override("shadow_offset_y", 2)
	add_child(number)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := size.x * 0.44
	if badge_kind == "guard":
		var shape := PackedVector2Array([
			Vector2(center.x, size.y * 0.04),
			Vector2(size.x * 0.91, size.y * 0.20),
			Vector2(size.x * 0.84, size.y * 0.67),
			Vector2(center.x, size.y * 0.96),
			Vector2(size.x * 0.16, size.y * 0.67),
			Vector2(size.x * 0.09, size.y * 0.20)
		])
		draw_colored_polygon(shape, Color("#101b22"))
		var outline := shape.duplicate()
		outline.append(shape[0])
		draw_polyline(outline, tint, 2.5, true)
	else:
		draw_circle(center, radius, Color("#101b22"))
		draw_arc(center, radius, 0, TAU, 48, tint, 2.5, true)
		draw_line(Vector2(center.x, size.y * 0.01), Vector2(center.x, size.y * 0.11), tint, 2.0, true)
		draw_line(Vector2(center.x, size.y * 0.89), Vector2(center.x, size.y * 0.99), tint, 2.0, true)
		draw_line(Vector2(size.x * 0.01, center.y), Vector2(size.x * 0.11, center.y), tint, 2.0, true)
		draw_line(Vector2(size.x * 0.89, center.y), Vector2(size.x * 0.99, center.y), tint, 2.0, true)
