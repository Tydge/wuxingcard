class_name SummonView
extends Panel

const VIEW_SIZE := Vector2(190, 190)

func configure(summoned: Summon) -> void:
	size = VIEW_SIZE
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var portrait := TextureRect.new()
	portrait.position = Vector2(2, 0)
	portrait.size = Vector2(186, 162)
	portrait.texture = load("res://assets/summons/standee/%s.webp" % summoned.id)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	portrait.pivot_offset = portrait.size / 2.0
	var float_seconds := 1.65 + float(abs(hash(summoned.id)) % 5) * 0.13
	var float_tween := portrait.create_tween().set_loops()
	float_tween.tween_property(portrait, "position:y", -6.0, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(portrait, "position:y", 2.0, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var breath_tween := portrait.create_tween().set_loops()
	breath_tween.tween_property(portrait, "scale", Vector2(1.025, 1.025), float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath_tween.tween_property(portrait, "scale", Vector2.ONE, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var hp_badge := Panel.new()
	hp_badge.position = Vector2(57, 160)
	hp_badge.size = Vector2(76, 26)
	hp_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("#4b202b")
	badge_style.border_color = BattleRules.color(summoned.element)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(13)
	hp_badge.add_theme_stylebox_override("panel", badge_style)
	add_child(hp_badge)
	_label(hp_badge, "%d / %d" % [summoned.hp, summoned.max_hp], Vector2.ZERO, hp_badge.size, 15, Color.WHITE)

func _label(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
