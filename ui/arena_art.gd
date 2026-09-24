class_name ArenaArt
extends Control

func _draw() -> void:
	var center := Vector2(780, 522)
	for radius in [290.0, 245.0, 192.0, 135.0]:
		draw_arc(center, radius, 0, TAU, 160, Color(0.61, 0.74, 0.77, 0.16), 2.0, true)
	for i in 40:
		var angle := TAU * float(i) / 40.0
		var a := center + Vector2.from_angle(angle) * 251.0
		var b := center + Vector2.from_angle(angle) * (262.0 if i % 5 == 0 else 256.0)
		draw_line(a, b, Color(0.8, 0.7, 0.48, 0.25), 2.0, true)
	for i in 5:
		var angle := -PI / 2.0 + TAU * float(i) / 5.0
		var p := center + Vector2.from_angle(angle) * 167.0
		draw_circle(p, 34.0, Color(0.03, 0.08, 0.13, 0.46))
		draw_arc(p, 34.0, 0, TAU, 48, BattleRules.color(BattleRules.ELEMENTS[i]).darkened(0.35), 2.0, true)
	for i in 5:
		var a := center + Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 5.0) * 167.0
		var b := center + Vector2.from_angle(-PI / 2.0 + TAU * float((i + 2) % 5) / 5.0) * 167.0
		draw_line(a, b, Color(0.76, 0.68, 0.48, 0.14), 2.0, true)

