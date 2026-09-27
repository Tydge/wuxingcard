extends SceneTree

func _initialize() -> void:
	var report_path := OS.get_cmdline_user_args()[0]
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var compressed: Array[String] = []
	var lossless: Array[String] = []
	for path: String in report["images"]:
		var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + path))
		if image == null:
			push_error("Cannot load export art: " + path)
			quit(1)
			return
		var settings := ConfigFile.new()
		if settings.load("res://" + path + ".import") != OK:
			push_error("Missing import settings: " + path)
			quit(1)
			return
		# Only opaque illustrations/backgrounds. Transparent artwork keeps lossless alpha.
		var eligible := path.begins_with("assets/cards/") or path.begins_with("assets/backgrounds/")
		if eligible and image.detect_alpha() == Image.ALPHA_NONE:
			settings.set_value("params", "compress/mode", 1)
			settings.set_value("params", "compress/lossy_quality", float(report["quality"]))
			compressed.append(path)
		else:
			settings.set_value("params", "compress/mode", 0)
			lossless.append(path)
		if settings.save("res://" + path + ".import") != OK:
			quit(1)
			return
	report["compressed_images"] = compressed
	report["lossless_images"] = lossless
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print("Export art: %d opaque images at quality %.2f, %d lossless images, %d unused images excluded" % [compressed.size(), report["quality"], lossless.size(), report["excluded_images"].size()])
	quit()
