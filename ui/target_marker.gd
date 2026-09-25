class_name TargetMarker
extends Control

var tint := Color("#ffb9a0")
var highlighted := false

func configure(for_empty_slot: bool) -> void:
	size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint = Color("#e9d59e") if for_empty_slot else Color("#ffb9a0")
	queue_redraw()

func set_highlighted(value: bool) -> void:
	highlighted = value
	queue_redraw()

func _draw() -> void:
	var center := size / 2.0
	var color := Color.WHITE if highlighted else tint
	var line_width := 3.0 if highlighted else 2.0
	draw_circle(center, 19.0, Color(0.03, 0.05, 0.09, 0.48))
	draw_arc(center, 16.0, 0.0, TAU, 48, Color(0.02, 0.04, 0.07, 0.8), line_width + 2.0, true)
	draw_arc(center, 16.0, 0.0, TAU, 48, color, line_width, true)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + direction * 10.0, center + direction * 22.0, Color(0.02, 0.04, 0.07, 0.8), line_width + 2.0, true)
		draw_line(center + direction * 10.0, center + direction * 22.0, color, line_width, true)
	draw_circle(center, 2.5, color)
