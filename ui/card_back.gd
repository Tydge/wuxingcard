class_name CardBack
extends Panel

const BACK_ART := preload("res://assets/cards/card_back.webp")

func configure(card_size: Vector2, upside_down: bool = false) -> void:
	size = card_size
	custom_minimum_size = card_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var art := TextureRect.new()
	art.texture = BACK_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.size = card_size
	art.pivot_offset = card_size / 2.0
	art.rotation_degrees = 180.0 if upside_down else 0.0
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
