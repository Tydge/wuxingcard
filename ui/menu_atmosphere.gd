extends Control

var age := 0.0
var collection := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	var gold := Color("#d6b777")
	for corner in [Vector2(36, 36), Vector2(1564, 36), Vector2(36, 864), Vector2(1564, 864)]:
		var sx := 1.0 if corner.x < 800 else -1.0
		var sy := 1.0 if corner.y < 450 else -1.0
		draw_polyline(PackedVector2Array([corner + Vector2(0, 52 * sy), corner, corner + Vector2(74 * sx, 0)]), Color(gold, 0.58), 1.4, true)
		draw_polyline(PackedVector2Array([corner + Vector2(8 * sx, 34 * sy), corner + Vector2(8 * sx, 8 * sy), corner + Vector2(46 * sx, 8 * sy)]), Color(gold, 0.32), 1.0, true)
		draw_circle(corner + Vector2(8 * sx, 8 * sy), 2, gold)
	if collection:
		return
	for i in 28:
		var x := 120.0 + fmod(float(i * 137) + sin(age * 0.13 + i) * 22.0, 1360.0)
		var y := 890.0 - fmod(float(i * 71) + age * (8.0 + float(i % 4)), 850.0)
		var alpha := (sin(age * 0.9 + float(i * 3)) + 1.0) * 0.16
		draw_circle(Vector2(x, y), 1.0 + float(i % 3) * 0.5, Color(gold, alpha))
