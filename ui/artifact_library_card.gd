class_name ArtifactLibraryCard
extends Control

signal inspect_requested(entry: Dictionary, source: Control)
signal equip_requested(id: String)

var entry: Dictionary = {}
var front: ArtifactView
var drag_started := false
var plus: Button
var hint: Label
var equipped := false

func configure(data: Dictionary, card_size: Vector2) -> void:
	entry = data
	size = card_size + Vector2(0, 50 if PlatformUI.is_touch() else 25)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	front = ArtifactView.new()
	front.configure(data, card_size)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(front)
	hint = Label.new()
	hint.text = ArtifactLibrary.SLOT_NAMES[str(data["slot"])]
	hint.position = Vector2(3, card_size.y)
	hint.size = Vector2(card_size.x - (58 if PlatformUI.is_touch() else 45), 48 if PlatformUI.is_touch() else 25)
	hint.add_theme_font_size_override("font_size", 21 if PlatformUI.is_touch() else 15)
	hint.add_theme_color_override("font_color", Color("#b5c3bd"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	plus = Button.new()
	plus.text = "+"
	plus.position = Vector2(card_size.x - (56 if PlatformUI.is_touch() else 34), card_size.y)
	plus.size = Vector2(56, 48) if PlatformUI.is_touch() else Vector2(34, 25)
	plus.add_theme_font_size_override("font_size", 30 if PlatformUI.is_touch() else 22)
	plus.tooltip_text = "装备"
	plus.pressed.connect(func(): equip_requested.emit(str(entry["id"])))
	add_child(plus)

func set_equipped(value: bool) -> void:
	equipped = value
	plus.disabled = value
	hint.text = "已装备" if value else ArtifactLibrary.SLOT_NAMES[str(entry["slot"])]

func _get_drag_data(_at_position: Vector2) -> Variant:
	if equipped: return null
	drag_started = true
	var preview := Control.new()
	var card := ArtifactView.new()
	card.configure(entry, front.size)
	card.position = -front.size / 2.0
	card.rotation_degrees = -4.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(card)
	set_drag_preview(preview)
	return {"kind": "artifact", "id": str(entry["id"]), "slot": str(entry["slot"])}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: call_deferred("_clear_drag_flag")

func _clear_drag_flag() -> void:
	drag_started = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not drag_started:
		inspect_requested.emit(entry, front)
		accept_event()
