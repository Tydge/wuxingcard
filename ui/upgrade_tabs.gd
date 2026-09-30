class_name UpgradeTabs
extends Control

signal selected(level: int)
var level := 0
var buttons: Array[Button] = []
var indicator: ColorRect
var motion: Tween

func configure(width: float, initial: int) -> void:
	size = Vector2(width, 56 if PlatformUI.is_touch() else 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in 3:
		var button := Button.new()
		button.text = ["原版", "精", "玄"][i]
		button.position = Vector2(i * width / 3.0, 0)
		button.size = Vector2(width / 3.0 - 6, size.y - 5)
		button.add_theme_font_size_override("font_size", 24 if PlatformUI.is_touch() else 21)
		button.pressed.connect(func(): set_level(i); selected.emit(i))
		add_child(button)
		buttons.append(button)
	indicator = ColorRect.new()
	indicator.color = Color("#e4c795")
	indicator.size = Vector2(width / 3.0 - 6, 3)
	indicator.position.y = size.y - 3
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(indicator)
	set_level(initial, false)

func set_level(value: int, animate: bool = true) -> void:
	level = value
	for i in buttons.size(): buttons[i].modulate = Color.WHITE if i == value else Color("#8eaaa5")
	if motion != null and motion.is_running(): motion.kill()
	var destination := float(value) * size.x / 3.0
	if animate:
		motion = create_tween()
		motion.tween_property(indicator, "position:x", destination, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else: indicator.position.x = destination
