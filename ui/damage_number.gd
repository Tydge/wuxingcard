class_name DamageNumber
extends Control

# A short ink-and-cinnabar hit callout. The heavy outline keeps the number
# readable over both the light sky and the dark arena floor.
const SIZE := Vector2(238, 96)
var brush_font: SystemFont
var matchup := ""

func configure(amount: int, outcome: String = "") -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	matchup = outcome if outcome in ["克制", "抵抗"] else ""
	brush_font = SystemFont.new()
	brush_font.font_names = PackedStringArray(["Songti SC", "STSong", "Noto Serif CJK SC", "serif"])
	if matchup != "":
		_add_text(matchup, Vector2(12, 12), Vector2(80, 72), 31, Color("#bde9ff") if matchup == "抵抗" else Color("#ffcd72"), Color("#371019"))
		_add_text("-%d" % amount, Vector2(88, 2), Vector2(138, 82), 62, Color("#fff1cf"), Color("#5b1720"))
	else:
		_add_text("-%d" % amount, Vector2(18, 2), Vector2(208, 82), 62, Color("#fff1cf"), Color("#5b1720"))
	queue_redraw()

func play() -> void:
	pivot_offset = size / 2.0
	scale = Vector2(0.72, 0.72)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2(1.14, 1.14), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var drift := create_tween()
	drift.tween_property(self, "position:y", position.y - 64.0, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_interval(0.32)
	fade.tween_property(self, "modulate:a", 0.0, 0.63)
	fade.tween_callback(queue_free)

func _add_text(value: String, at: Vector2, dimensions: Vector2, font_size: int, fill: Color, outline: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", brush_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", fill)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", 7)
	add_child(label)

func _draw() -> void:
	var ink := PackedVector2Array([Vector2(7, 64), Vector2(28, 33), Vector2(91, 24), Vector2(197, 17), Vector2(232, 37), Vector2(210, 65), Vector2(135, 75), Vector2(28, 82)])
	draw_colored_polygon(ink, Color("#160c12d9"))
	draw_line(Vector2(27, 79), Vector2(211, 70), Color("#da9e59c0"), 2.0, true)
