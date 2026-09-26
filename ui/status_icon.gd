extends Control

const ICON_SIZE := Vector2(44, 44)
const CENTER := Vector2(19, 19)

var status_id := ""
var element := ""
var stacks := 0

func configure(status: Dictionary, description: String) -> void:
	status_id = str(status["id"])
	element = str(status.get("element", ""))
	stacks = int(status["stacks"])
	size = ICON_SIZE
	custom_minimum_size = ICON_SIZE
	tooltip_text = description
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	queue_redraw()

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#09121ff5")
	style.border_color = Color("#dec596")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = for_text
	label.custom_minimum_size = Vector2(280, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#f5f1e9"))
	panel.add_child(label)
	return panel

func _draw() -> void:
	var tint := _tint()
	draw_circle(CENTER, 18.0, Color("#08111c"))
	draw_circle(CENTER, 16.0, tint.darkened(0.65))
	draw_arc(CENTER, 17.0, 0.0, TAU, 40, tint, 2.0, true)
	match status_id:
		"burn": _draw_burn(tint)
		"poison": _draw_poison(tint)
		"bleed": _draw_bleed(tint)
		"weak": _draw_weak(tint)
		"vulnerable": _draw_vulnerable(tint)
		"charge": _draw_charge(tint)
		"tenacity": _draw_tenacity(tint)
		"regen": _draw_regen(tint)
		"shield": _draw_shield(tint)
		"lock": _draw_lock(tint)
		_: draw_circle(CENTER, 6.0, tint)
	var badge := Vector2(32, 32)
	draw_circle(badge, 11.0, Color("#07111d"))
	draw_arc(badge, 10.5, 0.0, TAU, 28, Color("#dec596"), 1.5, true)
	var font := ThemeDB.fallback_font
	draw_string(font, badge + Vector2(-11, 4), str(stacks), HORIZONTAL_ALIGNMENT_CENTER, 22, 12, Color.WHITE)

func _tint() -> Color:
	match status_id:
		"burn": return Color("#ff8b5f")
		"poison": return Color("#a3d86c")
		"bleed": return Color("#ea6077")
		"weak": return Color("#a69ce0")
		"vulnerable": return Color("#e7bd74")
		"charge": return Color("#f4ad68")
		"tenacity": return Color("#8bd2c4")
		"regen": return Color("#80d9a1")
		"shield": return Color("#83c7ec")
		"lock": return BattleRules.color(element)
	return Color("#dec596")

func _draw_burn(tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(18, 7), Vector2(24, 16), Vector2(22, 26), Vector2(15, 29), Vector2(11, 23), Vector2(14, 17)]), tint)
	draw_colored_polygon(PackedVector2Array([Vector2(18, 16), Vector2(21, 23), Vector2(18, 27), Vector2(15, 23)]), Color("#ffdd95"))

func _draw_poison(tint: Color) -> void:
	draw_circle(Vector2(14, 16), 3.0, tint)
	draw_circle(Vector2(23, 14), 2.5, tint)
	draw_circle(Vector2(20, 24), 5.0, tint)
	draw_circle(Vector2(18, 22), 1.8, Color("#ecffd3"))

func _draw_bleed(tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(19, 8), Vector2(27, 22), Vector2(25, 27), Vector2(19, 30), Vector2(12, 25), Vector2(12, 21)]), tint)
	draw_line(Vector2(11, 29), Vector2(27, 10), Color("#ffd2d0"), 2.0, true)

func _draw_weak(tint: Color) -> void:
	draw_line(Vector2(19, 9), Vector2(19, 25), tint, 3.0, true)
	draw_line(Vector2(12, 19), Vector2(19, 27), tint, 3.0, true)
	draw_line(Vector2(26, 19), Vector2(19, 27), tint, 3.0, true)

func _draw_vulnerable(tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(19, 8), Vector2(28, 18), Vector2(19, 29), Vector2(10, 18)]), tint)
	draw_line(Vector2(18, 10), Vector2(21, 18), Color("#47332d"), 2.0, true)
	draw_line(Vector2(21, 18), Vector2(16, 26), Color("#47332d"), 2.0, true)

func _draw_charge(tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(19, 7), Vector2(25, 17), Vector2(21, 17), Vector2(21, 29), Vector2(17, 29), Vector2(17, 17), Vector2(13, 17)]), tint)
	draw_line(Vector2(10, 11), Vector2(13, 14), Color("#ffe6b2"), 1.8, true)
	draw_line(Vector2(28, 11), Vector2(25, 14), Color("#ffe6b2"), 1.8, true)
	draw_line(Vector2(8, 20), Vector2(12, 20), Color("#ffe6b2"), 1.8, true)
	draw_line(Vector2(30, 20), Vector2(26, 20), Color("#ffe6b2"), 1.8, true)

func _draw_tenacity(tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(9, 26), Vector2(15, 16), Vector2(19, 20), Vector2(23, 11), Vector2(30, 26)]), tint)
	draw_line(Vector2(13, 26), Vector2(25, 26), Color("#e0fff2"), 2.0, true)
	draw_line(Vector2(23, 15), Vector2(23, 23), Color("#274a4a"), 2.0, true)

func _draw_regen(tint: Color) -> void:
	draw_line(Vector2(19, 28), Vector2(19, 15), tint, 2.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(19, 19), Vector2(11, 17), Vector2(9, 11), Vector2(16, 12)]), tint)
	draw_colored_polygon(PackedVector2Array([Vector2(19, 17), Vector2(25, 10), Vector2(29, 11), Vector2(26, 18)]), tint)

func _draw_shield(tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(19, 8), Vector2(28, 12), Vector2(27, 21), Vector2(19, 30), Vector2(11, 21), Vector2(10, 12)]), tint)
	draw_colored_polygon(PackedVector2Array([Vector2(19, 12), Vector2(24, 14), Vector2(23, 21), Vector2(19, 25), Vector2(15, 21), Vector2(14, 14)]), Color("#183246"))

func _draw_lock(tint: Color) -> void:
	draw_arc(Vector2(19, 17), 6.0, PI, TAU, 20, tint, 2.5, true)
	draw_rect(Rect2(12, 17, 14, 11), tint)
	draw_circle(Vector2(19, 22), 1.8, Color("#183246"))
