extends SceneTree

# Builds the arena standee texture for every character from its transparent
# portrait, so the side-by-side battle layout has one art asset per fighter.
#
#   Godot --headless --path . --script res://tools/make_standees.gd
#   Godot --headless --path . --script res://tools/make_standees.gd -- --force
#
# Portraits are 1024x1536 with an alpha background; standees keep the 2:3
# framing at 320x480, matching the assets the original prototype shipped.

const PORTRAIT_DIR := "res://assets/characters"
const STANDEE_SIZE := Vector2i(320, 480)
const WEBP_QUALITY := 0.9

func _initialize() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	var characters: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/characters.json"))
	var made := 0
	var kept := 0
	var missing := 0
	for entry in characters:
		var id := str(entry["id"])
		var portrait_path := "%s/%s.webp" % [PORTRAIT_DIR, id]
		var standee_path := "%s/%s_standee.webp" % [PORTRAIT_DIR, id]
		if not FileAccess.file_exists(portrait_path):
			push_warning("No portrait for '%s' (%s); skipping" % [id, portrait_path])
			missing += 1
			continue
		if FileAccess.file_exists(standee_path) and not force:
			kept += 1
			continue
		var portrait := Image.load_from_file(portrait_path)
		if portrait == null:
			push_error("Could not read %s" % portrait_path)
			quit(1)
			return
		var standee := _build_standee(portrait)
		var err := standee.save_webp(standee_path, true, WEBP_QUALITY)
		if err != OK:
			push_error("Could not write %s (error %d)" % [standee_path, err])
			quit(1)
			return
		print("wrote %s (%dx%d from %dx%d)" % [standee_path, standee.get_width(), standee.get_height(),
			portrait.get_width(), portrait.get_height()])
		made += 1
	print("standees: %d written, %d already present, %d without portrait" % [made, kept, missing])
	quit()

func _build_standee(portrait: Image) -> Image:
	# Trim to the alpha bounding box first so a portrait with generous padding
	# still fills the standee frame the way the shipped artwork does.
	var bounds := _opaque_bounds(portrait)
	var standee := portrait
	if bounds.size.x > 0 and bounds.size.y > 0:
		standee = Image.create_empty(bounds.size.x, bounds.size.y, false, portrait.get_format())
		standee.blit_rect(portrait, bounds, Vector2i.ZERO)
	standee.resize(STANDEE_SIZE.x, STANDEE_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return standee

func _opaque_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.06:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
