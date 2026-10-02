class_name ArtifactView
extends Control

const FACE_SIZE := Vector2(400, 560)

var entry: Dictionary = {}

func configure(data: Dictionary, view_size: Vector2, remaining: int = -1) -> void:
	entry = data
	size = view_size
	custom_minimum_size = view_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child in get_children(): child.queue_free()
	var tint := BattleRules.color(str(data.get("element", "")))
	var face := Panel.new()
	face.size = FACE_SIZE
	face.scale = Vector2(view_size.x / FACE_SIZE.x, view_size.y / FACE_SIZE.y)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color("#0b1a20")
	backing.border_color = tint
	backing.set_border_width_all(3)
	backing.set_corner_radius_all(14)
	face.add_theme_stylebox_override("panel", backing)
	var picture_path := "res://assets/artifacts/%s.webp" % data.get("art_id", data["id"])
	if ResourceLoader.exists(picture_path):
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.texture = load(picture_path)
		face.add_child(picture)
		picture.position = Vector2(10, 10)
		picture.size = Vector2(380, 290)
	var title := _label(face, str(data.get("name", "")), 38, tint)
	title.position = Vector2(18, 315)
	title.size = Vector2(364, 41)
	var slot := str(data.get("slot", ""))
	var category := _label(face, "%s · %s" % [BattleRules.element_name(str(data.get("element", ""))), ArtifactLibrary.SLOT_NAMES.get(slot, slot)], 21, Color("#b5c3bd"))
	category.position = Vector2(18, 358)
	category.size = Vector2(364, 28)
	# Match CardView's 18 pt text at 240 px width: 30 pt at this 400 px face.
	var description := CardDescription.new()
	description.configure(str(data.get("description", "")), Rect2(24,392,352,157), 30, Color("#f1e9d9"))
	face.add_child(description)
	if slot == "implement" or slot == "guard":
		var amount := int(data.get("durability" if slot == "guard" else "cooldown", 0))
		if slot == "guard" and remaining >= 0: amount = remaining
		var badge := ArtifactBadge.new()
		face.add_child(badge)
		badge.configure(slot, amount, tint, 56.0)
		badge.position = Vector2(2, 2)

func _label(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
