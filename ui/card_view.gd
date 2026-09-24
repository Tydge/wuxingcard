class_name CardView
extends Panel

# A front always has the same 5:7 composition. Its art window is exactly 4:3.
# Every display size multiplies these measurements, including the full text.
const DESIGN_SIZE := Vector2(240, 336)
const ART_RECT := Rect2(12, 37, 216, 162)
var art_texture: Texture2D
var art_source_region := Rect2()
var art_target := Rect2()
var fallback_color := Color.TRANSPARENT

func configure(card: Dictionary, card_width: float) -> void:
	var factor := card_width / DESIGN_SIZE.x
	var card_size := DESIGN_SIZE * factor
	size = card_size
	custom_minimum_size = card_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var element: String = card["element"]
	var element_color := BattleRules.color(element)
	var border := StyleBoxFlat.new()
	border.bg_color = Color("#101e2c")
	border.border_color = element_color
	border.set_border_width_all(maxi(1, roundi(2.0 * factor)))
	border.set_corner_radius_all(maxi(4, roundi(10.0 * factor)))
	add_theme_stylebox_override("panel", border)
	art_target = Rect2(ART_RECT.position * factor, ART_RECT.size * factor)
	var art_path := _art_path(card)
	if ResourceLoader.exists(art_path):
		art_texture = load(art_path)
		art_source_region = _art_source_rect(art_texture)
	else:
		fallback_color = element_color.darkened(0.75)
	queue_redraw()
	var footer := ColorRect.new()
	footer.color = Color("#101a28f7")
	footer.position = Vector2(10, 202) * factor
	footer.size = Vector2(220, 124) * factor
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	_add_label(self, str(int(card["cost"])), Vector2(9, 3) * factor, Vector2(37, 28) * factor, maxi(8, roundi(25 * factor)), Color("#f5f1e9"))
	_add_label(self, BattleRules.element_name(element), Vector2(194, 3) * factor, Vector2(35, 28) * factor, maxi(8, roundi(24 * factor)), element_color)
	var title := _add_label(self, card["name"], Vector2(14, 204) * factor, Vector2(212, 36) * factor, maxi(8, roundi(23 * factor)), Color("#dec596"))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	var description := _add_label(self, _wrap_text(card["text"], 11), Vector2(17, 243) * factor, Vector2(206, 80) * factor, maxi(7, roundi(18 * factor)), Color("#f5f1e9"))
	description.clip_text = true
	description.autowrap_mode = TextServer.AUTOWRAP_OFF

func _ready() -> void:
	# configure() runs before the card is mounted, so at that point the card has no
	# theme and Label.get_minimum_size() is measured with Godot's built-in font
	# instead of the game font (the built-in one has much wider CJK advances).
	# Control.set_size() then clamped our designed rects, which pushed the centred
	# text sideways. The theme resolves as soon as we enter the tree, so re-assert
	# every designed rect here.
	_reapply_designed_sizes(self)

func _reapply_designed_sizes(node: Node) -> void:
	for child in node.get_children():
		if child is Label and child.has_meta("designed_size"):
			child.size = child.get_meta("designed_size")
		_reapply_designed_sizes(child)

func configure_back(card_size: Vector2) -> void:
	size = card_size
	custom_minimum_size = card_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color("#172844")
	border.border_color = Color("#a28f6e")
	border.set_border_width_all(2)
	border.set_corner_radius_all(9)
	add_theme_stylebox_override("panel", border)
	var inset := Panel.new()
	inset.position = Vector2(5, 5)
	inset.size = card_size - Vector2(10, 10)
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color("#233956")
	inner_style.border_color = Color("#73664f")
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(6)
	inset.add_theme_stylebox_override("panel", inner_style)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inset)
	_add_label(inset, "行", Vector2.ZERO, inset.size, 34, Color("#dec596"))

func _add_label(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("designed_size", dimensions)
	parent.add_child(label)
	return label

func _art_path(card: Dictionary) -> String:
	var specific := "res://assets/cards/generated/%s.webp" % card["id"]
	if ResourceLoader.exists(specific):
		return specific
	return "res://assets/cards/elements/%s.webp" % card["element"]

func _art_source_rect(source: Texture2D) -> Rect2:
	var dimensions := source.get_size()
	var target_ratio := ART_RECT.size.x / ART_RECT.size.y
	if dimensions.x / dimensions.y < target_ratio:
		var crop_h := dimensions.x / target_ratio
		return Rect2(0, (dimensions.y - crop_h) * 0.32, dimensions.x, crop_h)
	var crop_w := dimensions.y * target_ratio
	return Rect2((dimensions.x - crop_w) / 2.0, 0, crop_w, dimensions.y)

func _draw() -> void:
	if art_texture != null:
		draw_texture_rect_region(art_texture, art_target, art_source_region)
	elif art_target.size != Vector2.ZERO:
		draw_rect(art_target, fallback_color)

func _wrap_text(value: String, max_chars: int) -> String:
	var remaining := value.replace(" ", "")
	var lines: Array[String] = []
	while remaining.length() > max_chars:
		var count := max_chars
		if "，。；、".contains(remaining.substr(count, 1)):
			count += 1
		lines.append(remaining.substr(0, count))
		remaining = remaining.substr(count)
	lines.append(remaining)
	return "\n".join(lines)
