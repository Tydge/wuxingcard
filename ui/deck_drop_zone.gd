class_name DeckDropZone
extends Panel

var can_add: Callable
var add_card: Callable
var hovered := false

func _ready() -> void:
	set_process(true)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "deck_card" and can_add.call(str(data.get("id", "")))

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	add_card.call(str(data["id"]), get_global_mouse_position())

func _process(_delta: float) -> void:
	var dragging := get_viewport().gui_is_dragging()
	var valid := dragging and _can_drop_data(Vector2.ZERO, get_viewport().gui_get_drag_data())
	var over := valid and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
	if hovered != over:
		hovered = over
		queue_redraw()

func _draw() -> void:
	if hovered:
		draw_style_box(_highlight(), Rect2(Vector2.ZERO, size))

func _highlight() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#d6bd7c0e")
	style.border_color = Color("#efd29d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
