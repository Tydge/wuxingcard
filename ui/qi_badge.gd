class_name QiBadge
extends Control

func _draw() -> void:
	# A small golden flame distinguishes unallocated qi from fire-element energy.
	draw_colored_polygon(PackedVector2Array([Vector2(12,2),Vector2(13,12),Vector2(19,8),Vector2(22,20),Vector2(20,27),Vector2(12,31),Vector2(5,28),Vector2(2,21),Vector2(6,12),Vector2(8,17)]), Color("#dec596"))
	draw_colored_polygon(PackedVector2Array([Vector2(12,15),Vector2(17,23),Vector2(14,28),Vector2(9,28),Vector2(7,24)]), Color("#fff2ce"))

func _make_custom_tooltip(for_text: String) -> Object:
	return RuleTooltip.create(for_text)
