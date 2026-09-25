class_name SummonCardView
extends CardView

# Summon cards share the normal card dimensions but reserve the lower-right
# corner for the summoned unit's health.
func configure(card: Dictionary, card_width: float) -> void:
	super.configure(card, card_width)
	var factor := card_width / DESIGN_SIZE.x
	var description: Label = get_child(get_child_count() - 1)
	description.text = _wrap_text(str(card["text"]), 9)
	description.size = Vector2(165, 80) * factor
	description.set_meta("designed_size", description.size)
	description.add_theme_font_size_override("font_size", maxi(7, roundi(17 * factor)))
	var badge := Panel.new()
	badge.position = Vector2(186, 281) * factor
	badge.size = Vector2(44, 44) * factor
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("#822e38")
	badge_style.border_color = Color("#ffd0ba")
	badge_style.set_border_width_all(maxi(1, roundi(2 * factor)))
	badge_style.set_corner_radius_all(maxi(10, roundi(22 * factor)))
	badge.add_theme_stylebox_override("panel", badge_style)
	add_child(badge)
	_add_label(badge, str(int(card.get("summon_hp", 15))), Vector2.ZERO, badge.size, maxi(10, roundi(23 * factor)), Color.WHITE)
