class_name AudioSettings
extends Control

const GOLD := Color("#dfc48e")
const INK := Color("#0b1e27")
const LABELS := {"Master": "总音量", "Music": "音乐", "SFX": "战斗音效", "UI": "界面音效"}

func _ready() -> void:
	size = Vector2(1600, 900)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color("#061016c7")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: close())
	add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(505, 205)
	panel.size = Vector2(590, 495)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(15)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_add_label(panel, "声 音", Vector2(35, 24), Vector2(520, 60), 34)
	var index := 0
	for bus in LABELS:
		var y := 112.0 + index * 74.0
		_add_label(panel, LABELS[bus], Vector2(42, y), Vector2(138, 42), 23)
		var slider := HSlider.new()
		slider.position = Vector2(183, y + 1)
		slider.size = Vector2(330, 42)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = GameAudio.get_level(bus)
		slider.value_changed.connect(func(value: float): GameAudio.set_level(bus, value))
		panel.add_child(slider)
		index += 1
	var close_button := Button.new()
	close_button.text = "返回"
	close_button.position = Vector2(212, 419)
	close_button.size = Vector2(166, 55)
	close_button.add_theme_font_override("font", GameFonts.body())
	close_button.add_theme_font_size_override("font_size", 23)
	close_button.pressed.connect(close)
	panel.add_child(close_button)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

func _add_label(parent: Control, text: String, position_value: Vector2, size_value: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_font_override("font", GameFonts.body())
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)

func close() -> void:
	GameAudio.play_sfx("ui_back")
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
