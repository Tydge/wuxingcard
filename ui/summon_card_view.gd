class_name SummonCardView
extends CardView

# The health jewel hangs off the card frame, leaving the normal centred text
# area intact.
func configure(card: Dictionary, card_width: float) -> void:
	super.configure(card, card_width)
	clip_contents = false
	var factor := card_width / DESIGN_SIZE.x
	var shadow := Panel.new()
	shadow.position = Vector2(210, 302) * factor
	shadow.size = Vector2(54, 54) * factor
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color("#120b10cc")
	shadow_style.set_corner_radius_all(maxi(10, roundi(27 * factor)))
	shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(shadow)
	var badge := Panel.new()
	badge.position = Vector2(207, 296) * factor
	badge.size = Vector2(54, 54) * factor
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("#822e38")
	badge_style.border_color = Color("#ffd0ba")
	badge_style.set_border_width_all(maxi(1, roundi(3 * factor)))
	badge_style.set_corner_radius_all(maxi(10, roundi(27 * factor)))
	badge.add_theme_stylebox_override("panel", badge_style)
	add_child(badge)
	var hp := int(card.get("summon_hp", 15))
	var printed := int(card.get("printed_summon_hp", hp))
	var tint := Color("#79df8a") if hp > printed else Color("#ff817a") if hp < printed else Color.WHITE
	_add_label(badge, str(hp), Vector2.ZERO, badge.size, maxi(10, roundi(25 * factor)), tint)
