class_name DeckLibraryCard
extends Control

signal inspect_requested(card: Dictionary, source: Control)
signal add_requested(id: String)
signal drag_denied

var card: Dictionary
var factory: Callable
var front: Control
var copies_label: Label
var plus: Button
var copies := 0
var drag_started := false

func configure(data: Dictionary, card_factory: Callable, width: float) -> void:
	card = data
	factory = card_factory
	size = Vector2(width, width * 1.4)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	front = factory.call(card, size)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(front)
	copies_label = Label.new()
	copies_label.position = Vector2(0, size.y + (2 if PlatformUI.is_touch() else 9))
	copies_label.size = Vector2(width - (58 if PlatformUI.is_touch() else 32), 46 if PlatformUI.is_touch() else 26)
	copies_label.add_theme_font_size_override("font_size", 20 if PlatformUI.is_touch() else 16)
	copies_label.add_theme_color_override("font_color", Color("#c8d5bf"))
	copies_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(copies_label)
	plus = Button.new()
	plus.text = "+"
	plus.position = Vector2(width - (56 if PlatformUI.is_touch() else 28), size.y + (2 if PlatformUI.is_touch() else 9))
	plus.size = Vector2(56, 46) if PlatformUI.is_touch() else Vector2(28, 26)
	plus.add_theme_font_size_override("font_size", 30 if PlatformUI.is_touch() else 22)
	plus.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#284335")
	style.border_color = Color("#c6a971")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	plus.add_theme_stylebox_override("normal", style)
	plus.add_theme_stylebox_override("hover", style)
	plus.add_theme_stylebox_override("pressed", style)
	plus.pressed.connect(func(): add_requested.emit(card["id"]))
	add_child(plus)
	set_copies(0)

func set_copies(value: int) -> void:
	copies = value
	copies_label.text = "已入组 %d / %d" % [value, DeckStore.MAX_COPIES] if value > 0 else "召唤" if front is SummonCardView else "法术"
	plus.disabled = copies >= DeckStore.MAX_COPIES
	front.modulate = Color("#b1bcb8") if plus.disabled else Color.WHITE

func _get_drag_data(_at_position: Vector2) -> Variant:
	if copies >= DeckStore.MAX_COPIES:
		drag_denied.emit()
		return null
	drag_started = true
	var preview := Control.new()
	var view: Control = factory.call(card, size)
	view.position = -size / 2.0
	view.rotation_degrees = -4.0
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(view)
	set_drag_preview(preview)
	return {"kind": "deck_card", "id": card["id"]}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: drag_started = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not drag_started:
		inspect_requested.emit(card, front)
		accept_event()
