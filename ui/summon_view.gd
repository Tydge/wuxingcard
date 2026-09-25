class_name SummonView
extends Panel

const VIEW_SIZE := Vector2(104, 136)

func configure(summoned: Summon) -> void:
	size = VIEW_SIZE
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	var tint := BattleRules.color(summoned.element)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#101b2bec")
	frame.border_color = tint
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", frame)
	var emblem := Panel.new()
	emblem.position = Vector2(22, 23)
	emblem.size = Vector2(60, 60)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var emblem_style := StyleBoxFlat.new()
	emblem_style.bg_color = tint.darkened(0.66)
	emblem_style.border_color = tint.lightened(0.14)
	emblem_style.set_border_width_all(2)
	emblem_style.set_corner_radius_all(30)
	emblem.add_theme_stylebox_override("panel", emblem_style)
	add_child(emblem)
	_label(summoned.glyph, Vector2(23, 28), Vector2(58, 52), 36, tint.lightened(0.28))
	_label(summoned.display_name, Vector2(4, 2), Vector2(96, 23), 15, Color("#f5f1e9"))
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(9, 104)
	bar_bg.size = Vector2(86, 20)
	bar_bg.color = Color("#38404b")
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	var fill := ColorRect.new()
	fill.position = bar_bg.position + Vector2(2, 2)
	fill.size = Vector2(82.0 * float(summoned.hp) / float(maxi(1, summoned.max_hp)), 16)
	fill.color = Color("#d95e63")
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	_label("%d/%d" % [summoned.hp, summoned.max_hp], Vector2(9, 103), Vector2(86, 22), 14, Color("#ffffff"))
	var effects: Array[String] = []
	for effect in summoned.turn_start_effects:
		if effect["type"] == "gain_energy":
			effects.append("回合开始：获得 %d %s能量" % [int(effect["amount"]), BattleRules.element_name(effect["element"])])
	tooltip_text = summoned.display_name + "\n" + "\n".join(effects)

func _label(value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
