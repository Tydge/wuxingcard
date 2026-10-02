class_name CardDescription
extends RichTextLabel

var largest_font := 18
var fitting := false

func configure(value: String, area: Rect2, font_size: int, tint: Color) -> void:
	name = "Description"
	position = area.position
	size = area.size
	largest_font = font_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_active = false
	bbcode_enabled = true
	threaded = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_color_override("default_color", tint)
	text = value
	if is_node_ready(): fit_text()

func _ready() -> void:
	fit_text()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready() and not fitting: fit_text.call_deferred()

func fit_text() -> void:
	if fitting: return
	fitting = true
	# Measure the actual font after inheriting the game theme. Let the text engine
	# wrap punctuation and rich numbers once, rather than adding guessed breaks.
	var font_size := largest_font
	add_theme_font_size_override("normal_font_size", font_size)
	while font_size > 1 and get_content_height() > size.y:
		font_size -= 1
		add_theme_font_size_override("normal_font_size", font_size)
	fitting = false
