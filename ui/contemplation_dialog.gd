class_name ContemplationDialog
extends Control

signal confirmed(index: int)
var selected := -1
var frames: Array[Panel] = []
var confirm: Button

func configure(candidates: Array, known: Dictionary, factory: Callable, full: bool) -> void:
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var shade := ColorRect.new()
	shade.size = size
	shade.color = Color("#020d16e8")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_text("观想 · 择一入手", Rect2(300, 132, 1000, 65), 42, Color("#e4c795"))
	_text("手牌已满，选中的牌将进入弃牌堆" if full else "查看牌堆顶 · 未选的牌按原顺序保留", Rect2(300, 206, 1000, 45), 23, Color("#efbd92") if full else Color("#a9c9bb"))
	var width := 260.0 if candidates.size() < 4 else 240.0
	var total := candidates.size() * (width + 30) - 30
	for i in candidates.size():
		var frame := Panel.new()
		frame.position = Vector2((1600 - total) / 2.0 + i * (width + 30) - 6, 284)
		frame.size = Vector2(width + 12, width * 1.4 + 12)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
		frames.append(frame)
		var card: Control = factory.call(known[candidates[i]], Vector2(width, width * 1.4))
		card.position = Vector2(6, 6)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: _select(i))
		frame.add_child(card)
	confirm = Button.new()
	confirm.text = "收入手牌" if not full else "确认弃置"
	confirm.position = Vector2(650, 724)
	confirm.size = Vector2(300, 65)
	confirm.add_theme_font_size_override("font_size", 27)
	confirm.disabled = true
	confirm.pressed.connect(func(): confirm.disabled = true; confirmed.emit(selected))
	add_child(confirm)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	_select(-1)

func _select(index: int) -> void:
	selected = index
	for i in frames.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#0a1824")
		style.border_color = Color("#ffe5a0") if i == index else Color("#54665f")
		style.set_border_width_all(3 if i == index else 1)
		style.set_corner_radius_all(12)
		frames[i].add_theme_stylebox_override("panel", style)
		frames[i].create_tween().tween_property(frames[i], "position:y", 272.0 if i == index else 284.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	confirm.disabled = index < 0

func _text(value: String, rect: Rect2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
