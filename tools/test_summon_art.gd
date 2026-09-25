extends SceneTree

func _initialize() -> void:
	var failures := 0
	for summon_id in ["metal_furnace", "wood_seedling", "water_spring", "fire_lantern", "earth_stele"]:
		var standee_texture: Texture2D = load("res://assets/summons/standee/%s.webp" % summon_id)
		var card_texture: Texture2D = load("res://assets/cards/generated/%s_card.webp" % summon_id)
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
	print("Summon art checked: 5 pairs, %d failures" % failures)
	quit(1 if failures > 0 else 0)
