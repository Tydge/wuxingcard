class_name QiBadge
extends Control

var gain_started := -1000
var gain_strength := 0.0
var gaining := true

func animate_gain(started: int) -> void:
	animate_change(started,true)

func animate_change(started: int, is_gain: bool) -> void:
	gain_started = started
	gaining = is_gain
	set_process(Time.get_ticks_msec() - started < 800)
	_process(0)

func _process(_delta: float) -> void:
	var age := clampf(float(Time.get_ticks_msec() - gain_started) / 800.0, 0, 1)
	gain_strength = sin(age * PI) * (1.0 - age)
	var number := get_node_or_null("Number") as Label
	if number != null:
		number.pivot_offset = Vector2(10,17)
		number.scale = Vector2.ONE * (1.0 + gain_strength * 0.22)
		number.self_modulate = Color(1.0 + gain_strength * 0.4,1.0 + gain_strength * 0.3,1.0) if gaining else Color.WHITE.lerp(Color("#ff9d83"),gain_strength)
	queue_redraw()
	if age >= 1: set_process(false)

func _draw() -> void:
	if gain_strength > 0:
		draw_circle(Vector2(12,17), 17, Color(1.0,0.83 if gaining else 0.48,0.45,gain_strength * 0.25))
	var pulse := 1.0 + gain_strength * 0.15
	draw_set_transform(Vector2(12,17) * (1.0 - pulse),0,Vector2.ONE * pulse)
	# A small golden flame distinguishes unallocated qi from fire-element energy.
	draw_colored_polygon(PackedVector2Array([Vector2(12,2),Vector2(13,12),Vector2(19,8),Vector2(22,20),Vector2(20,27),Vector2(12,31),Vector2(5,28),Vector2(2,21),Vector2(6,12),Vector2(8,17)]), Color("#dec596"))
	draw_colored_polygon(PackedVector2Array([Vector2(12,15),Vector2(17,23),Vector2(14,28),Vector2(9,28),Vector2(7,24)]), Color("#fff2ce"))

func _make_custom_tooltip(for_text: String) -> Object:
	return RuleTooltip.create(for_text)
