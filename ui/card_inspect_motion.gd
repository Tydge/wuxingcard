class_name CardInspectMotion
extends RefCounted

# Shared focus/return motion for the collection, test workshop and journey.
static func focus(layer: Control, card: Control, origin: Vector2, origin_scale: float, destination: Vector2, shade: Control) -> Tween:
	card.position = origin
	card.scale = Vector2.ONE * origin_scale
	shade.modulate.a = 0.0
	var tween := layer.create_tween().set_parallel(true)
	tween.tween_property(card, "position", destination, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(shade, "modulate:a", 1.0, 0.3)
	return tween

static func fold(layer: Control, card: Control, origin: Vector2, origin_scale: float) -> Tween:
	var tween := layer.create_tween().set_parallel(true)
	tween.tween_property(card, "position", origin, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(card, "scale", Vector2.ONE * origin_scale, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(layer, "modulate:a", 0.0, 0.32)
	return tween
