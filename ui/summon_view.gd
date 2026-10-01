class_name SummonView
extends Panel

const VIEW_SIZE := Vector2(190, 190)
var summon_ref: Summon
var portrait: TextureRect
var hp_label: Label
var hp_badge: Panel
var trigger_tween: Tween

func configure(summoned: Summon, mirrored: bool = false) -> void:
	summon_ref = summoned
	size = VIEW_SIZE
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	portrait = TextureRect.new()
	portrait.position = Vector2(2, 0)
	portrait.size = Vector2(186, 162)
	portrait.texture = load("res://assets/summons/standee/%s.webp" % summoned.art_id)
	# Only mirror the artwork, preserving readable health and stable animation scale.
	portrait.flip_h = mirrored != summoned.art_flip_h
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	portrait.pivot_offset = Vector2(portrait.size.x / 2.0, portrait.size.y)
	var art_size := Vector2.ONE * summoned.art_scale
	portrait.scale = art_size
	var float_seconds := 1.65 + float(abs(hash(summoned.id)) % 5) * 0.13
	var float_tween := portrait.create_tween().set_loops()
	float_tween.tween_property(portrait, "position:y", -6.0, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(portrait, "position:y", 2.0, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var breath_tween := portrait.create_tween().set_loops()
	breath_tween.tween_property(portrait, "scale", art_size * 1.025, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath_tween.tween_property(portrait, "scale", art_size, float_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	hp_badge = Panel.new()
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
	hp_label = _label(hp_badge, "%d / %d" % [summoned.hp, summoned.max_hp], Vector2.ZERO, hp_badge.size, 15, Color.WHITE)
	refresh_health()

func set_health_foreground(value: bool) -> void:
	if is_instance_valid(hp_badge):
		hp_badge.z_as_relative = false
		hp_badge.z_index = 2 if value else 0

func refresh_health() -> void:
	if is_instance_valid(hp_label):
		hp_label.text = "%d / %d" % [summon_ref.hp, summon_ref.max_hp]
		hp_label.add_theme_color_override("font_color", Color("#ff817a") if summon_ref.hp < summon_ref.max_hp else Color("#79df8a") if summon_ref.max_hp > summon_ref.printed_hp else Color.WHITE)

func play_trigger() -> void:
	if trigger_tween != null and trigger_tween.is_running():
		trigger_tween.kill()
	pivot_offset = Vector2(95, 81)
	# Pulse the persistent view; the portrait's breathing animation keeps running.
	trigger_tween = create_tween()
	trigger_tween.tween_property(self, "scale", Vector2(1.075, 1.075), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	trigger_tween.tween_property(self, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _label(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
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
	return label
