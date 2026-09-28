class_name CardKeywordPopup
extends VBoxContainer

var explanations: Array[Dictionary] = []
var card_rect := Rect2()
var viewport_size := Vector2(1600, 900)
var placement_side := ""

func configure(entries: Array[Dictionary], rect: Rect2, bounds: Vector2) -> void:
	explanations = entries
	card_rect = rect
	viewport_size = bounds
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 10)
	var left_space := rect.position.x
	var right_space := bounds.x - rect.end.x
	placement_side = "right" if right_space >= left_space else "left"
	var width := minf(340.0 if PlatformUI.is_touch() else 280.0, maxf(left_space, right_space) - 28.0)
	custom_minimum_size.x = width
	for entry in entries:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#0a1824f5")
		style.border_color = Color("#cbb184")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 5)
		panel.add_child(column)
		for key in ["title", "text"]:
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.text = entry[key]
			label.custom_minimum_size.x = width - 28
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", (26 if key == "title" else 24) if PlatformUI.is_touch() else (20 if key == "title" else 18))
			label.add_theme_color_override("font_color", Color("#e4c795") if key == "title" else Color("#f2eee5"))
			column.add_child(label)
	call_deferred("_place")
	var reveal := create_tween()
	reveal.tween_interval(0.5)
	reveal.tween_property(self, "modulate:a", 1.0, 0.12)

func _place() -> void:
	reset_size()
	position.x = card_rect.end.x + 14 if placement_side == "right" else card_rect.position.x - size.x - 14
	position.y = clampf(card_rect.position.y, 12, maxf(12, viewport_size.y - size.y - 12))
