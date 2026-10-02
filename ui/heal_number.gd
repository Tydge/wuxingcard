class_name HealNumber
extends DamageNumber

func configure(amount: int, _outcome: String = "") -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	brush_font = GameFonts.damage()
	_add_text("+%d" % amount,Vector2(18,0),Vector2(208,76),62,Color("#9dffb2"),Color("#07351f"))
	_add_text("恢复",Vector2(18,72),Vector2(208,24),19,Color("#c7f8d7"),Color("#07351f"))
	queue_redraw()

func play() -> void:
	pivot_offset = size / 2.0
	scale = Vector2.ONE * 0.78
	var pop := create_tween()
	pop.tween_property(self,"scale",Vector2.ONE * 1.10,0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self,"scale",Vector2.ONE,0.16).set_trans(Tween.TRANS_SINE)
	var drift := create_tween()
	drift.tween_property(self,"position:y",position.y - 40,1.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_interval(0.70)
	fade.tween_property(self,"modulate:a",0.0,0.65).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(queue_free)

func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(7,62),Vector2(28,25),Vector2(92,17),Vector2(207,20),Vector2(232,41),Vector2(210,84),Vector2(131,95),Vector2(25,85)]),Color("#071f18ec"))
	draw_line(Vector2(29,90),Vector2(210,85),Color("#89dfaa"),2,true)
