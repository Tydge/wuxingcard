extends SceneTree

func _initialize() -> void:
	var failures := 0
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/summons.json"))
	for template in templates:
		var summon_id: String = template["id"]
		var standee_texture: Texture2D = load("res://assets/summons/standee/%s.webp" % summon_id)
		var card_texture: Texture2D = load("res://assets/cards/generated/%s.webp" % template["card_id"])
		if standee_texture == null or card_texture == null:
			push_error("Missing summon art: " + summon_id)
			failures += 1
			continue
		var standee := standee_texture.get_image()
		var card := card_texture.get_image()
		var size := standee.get_size()
		for corner in [Vector2i(0, 0), Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), size - Vector2i.ONE]:
			if standee.get_pixelv(corner).a > 0.1:
				push_error("Standee has an opaque corner: " + summon_id)
				failures += 1
				break
		var ratio := float(card.get_width()) / float(card.get_height())
		if absf(ratio - 4.0 / 3.0) > 0.01:
			push_error("Card art is not 4:3: " + summon_id)
			failures += 1
	print("Summon art checked: %d pairs, %d failures" % [templates.size(), failures])
	quit(1 if failures > 0 else 0)
