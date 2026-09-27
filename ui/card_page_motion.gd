class_name CardPageMotion
extends RefCounted

const LEAVE_SECONDS := 0.14
const ENTER_SECONDS := 0.28
const SETTLE_SECONDS := 0.38

static func leave(owner: Node, views: Array, direction: int, next_page: Callable) -> Tween:
	var tween := owner.create_tween().set_parallel(true)
	if views.is_empty(): tween.tween_interval(LEAVE_SECONDS)
	for view: Control in views:
		view.pivot_offset = view.size / 2.0
		tween.tween_property(view, "position:x", view.position.x - direction * 38.0, LEAVE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(view, "modulate:a", 0.0, LEAVE_SECONDS)
		tween.tween_property(view, "scale", Vector2.ONE * 0.96, LEAVE_SECONDS)
	tween.chain().tween_callback(next_page)
	return tween

static func enter(views: Array, direction: int, columns: int) -> void:
	for i in views.size():
		var view: Control = views[i]
		var destination := view.position
		view.pivot_offset = view.size / 2.0
		view.position.x += direction * 46.0
		view.scale = Vector2.ONE * 0.96
		view.modulate.a = 0.0
		var delay := float(i % columns) * 0.012
		var tween := view.create_tween().set_parallel(true)
		tween.tween_property(view, "position", destination, ENTER_SECONDS).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(view, "scale", Vector2.ONE, ENTER_SECONDS).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(view, "modulate:a", 1.0, ENTER_SECONDS - 0.04).set_delay(delay)
