class_name GameFonts
extends RefCounted

const BODY := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const SERIF := preload("res://assets/fonts/NotoSerifCJKsc-Regular.otf")

static func body() -> Font:
	# Keep the existing Mac typography; other platforms use a bundled CJK font.
	if not OS.has_feature("macos"):
		return BODY
	return installed_or_bundled(["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"], BODY)

static func title() -> Font:
	return installed_or_bundled(["Kaiti SC", "KaiTi", "STKaiti", "Songti SC", "Noto Serif CJK SC"], SERIF)

static func damage() -> Font:
	return installed_or_bundled(["Songti SC", "STSong", "Noto Serif CJK SC"], SERIF)

static func installed_or_bundled(candidates: Array, bundled: Font) -> Font:
	# Query first so optional macOS fonts never trigger a system download.
	var installed := OS.get_system_fonts()
	for candidate in candidates:
		if installed.has(candidate):
			var font := SystemFont.new()
			font.font_names = PackedStringArray([candidate])
			font.fallbacks = [bundled]
			return font
	return bundled
