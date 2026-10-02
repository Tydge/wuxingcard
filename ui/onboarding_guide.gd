class_name OnboardingGuide
extends Control

signal next_requested
signal skip_requested
const DESIGN := Vector2(1600, 900)
const GOLD := Color("#ffe0a3")
var holes: Array[Rect2] = []
var highlights: Array[Rect2] = []
var panel: Panel
var heading: Label
var body: Label
var counter: Label
var next_button: Button
var skip_button: Button
var clock := 0.0
var motion_from := Vector2.ZERO
var motion_to := Vector2.ZERO
var animating_drag := false
var key := ""
var chapter := ""

func _ready() -> void:
	name = "OnboardingGuide"
	size = DESIGN
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = Panel.new()
	panel.size = Vector2(480 if PlatformUI.is_touch() else 430, 220)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0c2029f7")
	style.border_color = Color("#c6a775")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_setup_labels()
	next_button = _button("下一步", Vector2(panel.size.x - 170, 156), Vector2(146, 52))
	next_button.pressed.connect(func(): next_requested.emit())
	skip_button = _button("跳过本段", Vector2(22, 156), Vector2(150, 52))
	skip_button.add_theme_color_override("font_color", Color("#b1c0c5"))
	skip_button.pressed.connect(func(): skip_requested.emit())

func _setup_labels() -> void:
	counter = _label(Vector2(24, 12), Vector2(panel.size.x - 48, 22), 16, Color("#aec5c9"))
	heading = _label(Vector2(24, 37), Vector2(panel.size.x - 48, 35), 27, GOLD)
	body = _label(Vector2(24, 80), Vector2(panel.size.x - 48, 64), 24, Color("#f5f0e5"))

func _label(at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at; label.size = dimensions
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	return label

func _button(caption: String, at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.text = caption; button.position = at; button.size = dimensions
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", GOLD)
	for state in ["normal","hover","pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#263c42") if state == "normal" else Color("#3c5357")
		style.border_color = Color("#bca475")
		style.set_border_width_all(1); style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func(): GameAudio.play_sfx("ui_select", 0.0, 70))
	panel.add_child(button)
	return button

func present(id: String, title: String, text: String, targets: Array[Rect2], allowed: Array[Rect2], at: Vector2, index: String, action: bool = false, caption: String = "下一步") -> void:
	key = id
	heading.text = title; body.text = text; counter.text = index
	highlights = targets; holes = allowed
	panel.size.y = 164 if action else 220
	heading.size.x = panel.size.x - (184 if action else 48)
	counter.size.x = panel.size.x - (184 if action else 48)
	skip_button.position = Vector2(panel.size.x - 154, 10) if action else Vector2(22,156)
	skip_button.size.x = 132 if action else 150
	panel.position = Vector2(clampf(at.x, 18, DESIGN.x - panel.size.x - 18), clampf(at.y, 18, DESIGN.y - panel.size.y - 18))
	next_button.visible = not action
	next_button.text = caption
	animating_drag = false
	show()
	queue_redraw()

func drag_hint(from: Vector2, to: Vector2) -> void:
	motion_from = from; motion_to = to; animating_drag = true

func allows(point: Vector2) -> bool:
	for rect in holes:
		if rect.has_point(point): return true
	return false

func _has_point(point: Vector2) -> bool:
	return not allows(point)

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	# Draw the union of spotlight holes without overlapping translucent masks.
	var edges: Array[float] = [0.0, DESIGN.y]
	for rect in highlights:
		edges.append(clampf(rect.position.y, 0, DESIGN.y)); edges.append(clampf(rect.end.y, 0, DESIGN.y))
	edges.sort()
	for i in edges.size() - 1:
		var top := edges[i]; var bottom := edges[i + 1]
		if bottom <= top: continue
		var spans: Array[Vector2] = []
		for rect in highlights:
			if rect.position.y < bottom and rect.end.y > top: spans.append(Vector2(maxf(0, rect.position.x), minf(DESIGN.x, rect.end.x)))
		spans.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		var x := 0.0
		for span in spans:
			if span.x > x: draw_rect(Rect2(x, top, span.x - x, bottom - top), Color("#020c13b5"))
			x = maxf(x, span.y)
		if x < DESIGN.x: draw_rect(Rect2(x, top, DESIGN.x - x, bottom - top), Color("#020c13b5"))
	var glow := Color(GOLD, 0.65 + sin(clock * 3.0) * 0.2)
	for rect in highlights:
		draw_style_box(_outline(glow), rect.grow(5))
	if animating_drag:
		var p := fmod(clock, 2.6) / 2.6
		var tip := motion_from.lerp(motion_to, smoothstep(0.1, 0.8, p))
		draw_line(motion_from, motion_to, Color(GOLD, 0.38), 3, true)
		draw_circle(tip, 13, Color("#10232bee"))
		draw_arc(tip, 15, 0, TAU, 32, GOLD, 3, true)
		draw_line(tip + Vector2(0, 9), tip + Vector2(0, 27), GOLD, 5, true)
	else:
		if not highlights.is_empty() and is_instance_valid(panel):
			var target := highlights[0].get_center()
			var start := panel.get_rect().get_center()
			var border := Vector2(clampf(target.x, panel.position.x, panel.position.x + panel.size.x), clampf(target.y, panel.position.y, panel.position.y + panel.size.y))
			var direction := (target - start).normalized()
			var end := target - direction * minf(highlights[0].size.x, highlights[0].size.y) * 0.35
			if border.distance_to(end) > 35:
				draw_line(border, end, glow, 3, true)
				var normal := direction.orthogonal()
				draw_colored_polygon(PackedVector2Array([end, end - direction * 15 + normal * 7, end - direction * 15 - normal * 7]), GOLD)

func _outline(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT; style.border_color = color
	style.set_border_width_all(3); style.set_corner_radius_all(10)
	return style
