extends SceneTree

func _initialize() -> void:
	var failures := 0
	var cards: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))
	var unique: Dictionary = {}
	var ordinary := 0
	for card in cards:
		var view := CardView.new()
		var path := view._art_path(card)
		view.free()
		var expected := "res://assets/cards/generated/%s.webp" % card["id"]
		if path != expected or not ResourceLoader.exists(expected):
			push_error("Card still uses shared art or is missing art: " + str(card["id"]))
			failures += 1
			continue
		var texture: Texture2D = load(path)
		var ratio := float(texture.get_width()) / float(texture.get_height())
		if absf(ratio - 4.0 / 3.0) > 0.01 or mini(texture.get_width(), texture.get_height()) < 512:
			push_error("Card art needs a sufficiently large 4:3 image: " + str(card["id"]))
			failures += 1
		var is_summon := false
		for effect in card["effects"]:
			if effect["type"] == "summon": is_summon = true
		if is_summon: continue
		ordinary += 1
		var digest := FileAccess.get_sha256(path)
		if unique.has(digest):
			push_error("Ordinary cards share an illustration: %s / %s" % [unique[digest], card["id"]])
			failures += 1
		unique[digest] = card["id"]
	print("Card art checked: %d cards, %d independent ordinary illustrations, %d failures" % [cards.size(), ordinary, failures])
	quit(1 if failures > 0 else 0)
