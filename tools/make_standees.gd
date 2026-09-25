extends SceneTree

# Builds each arena standee from its transparent full-body artwork. The older
# portraits remain available for HUD headshots.
#
#   Godot --headless --path . --script res://tools/make_standees.gd
#   Godot --headless --path . --script res://tools/make_standees.gd -- --force
#
# Full-body sources are 1024x1536 with alpha. Fit the complete figure into a
# 320x480 transparent frame without changing its aspect ratio.

const PORTRAIT_DIR := "res://assets/characters"
const FULLBODY_DIR := "res://assets/characters/fullbody"
const STANDEE_SIZE := Vector2i(320, 480)
const PADDING := 8
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
		var source_path := "%s/%s.webp" % [FULLBODY_DIR, id]
		if not FileAccess.file_exists(source_path):
			source_path = "%s/%s.webp" % [PORTRAIT_DIR, id]
		var standee_path := "%s/%s_standee.webp" % [PORTRAIT_DIR, id]
		if not FileAccess.file_exists(source_path):
			push_warning("No artwork for '%s' (%s); skipping" % [id, source_path])
			missing += 1
			continue
		if FileAccess.file_exists(standee_path) and not force:
			kept += 1
			continue
		var source := Image.load_from_file(source_path)
		if source == null:
			push_error("Could not read %s" % source_path)
			quit(1)
			return
		var standee := _build_standee(source)
		var err := standee.save_webp(standee_path, true, WEBP_QUALITY)
		if err != OK:
			push_error("Could not write %s (error %d)" % [standee_path, err])
			quit(1)
			return
		print("wrote %s (%dx%d from %dx%d)" % [standee_path, standee.get_width(), standee.get_height(),
			source.get_width(), source.get_height()])
		made += 1
	print("standees: %d written, %d already present, %d without portrait" % [made, kept, missing])
	quit()

func _build_standee(source: Image) -> Image:
	# Trim transparent margins, then fit the entire silhouette with a small inset.
	var bounds := _opaque_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Image.create_empty(STANDEE_SIZE.x, STANDEE_SIZE.y, false, Image.FORMAT_RGBA8)
	var cropped := source.get_region(bounds)
	var available := STANDEE_SIZE - Vector2i(PADDING * 2, PADDING * 2)
	var fit := minf(float(available.x) / float(bounds.size.x), float(available.y) / float(bounds.size.y))
	var fitted_size := Vector2i(maxi(1, roundi(bounds.size.x * fit)), maxi(1, roundi(bounds.size.y * fit)))
	cropped.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_LANCZOS)
	var standee := Image.create_empty(STANDEE_SIZE.x, STANDEE_SIZE.y, false, Image.FORMAT_RGBA8)
	standee.fill(Color.TRANSPARENT)
	var target := Vector2i((STANDEE_SIZE.x - fitted_size.x) / 2, STANDEE_SIZE.y - PADDING - fitted_size.y)
	standee.blit_rect(cropped, Rect2i(Vector2i.ZERO, fitted_size), target)
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
