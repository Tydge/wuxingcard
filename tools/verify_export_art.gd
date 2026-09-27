extends SceneTree

func _initialize() -> void:
	var report_path := OS.get_cmdline_user_args()[0]
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var failures := 0
	var metrics := {}
	var smallest_psnr := INF
	var texture_bytes := 0
	for path: String in report["images"]:
		var original := Image.load_from_file(ProjectSettings.globalize_path("res://" + path))
		var texture: Texture2D = load("res://" + path)
		if texture == null or texture.get_size() != Vector2(original.get_size()):
			push_error("Export changed image size or lost its texture: " + path)
			failures += 1
			continue
		var settings := ConfigFile.new()
		settings.load("res://" + path + ".import")
		var imported: String = settings.get_value("remap", "path")
		var source_file := FileAccess.open(imported, FileAccess.READ)
		texture_bytes += source_file.get_length()
		if path not in report["compressed_images"]: continue
		var decoded := texture.get_image()
		original.convert(Image.FORMAT_RGBA8)
		decoded.convert(Image.FORMAT_RGBA8)
		var measure := original.compute_image_metrics(decoded, true)
		var psnr := float(measure["peak_snr"])
		metrics[path] = measure
		smallest_psnr = minf(smallest_psnr, psnr)
		if psnr < 38.0 or decoded.detect_alpha() != Image.ALPHA_NONE:
			push_error("Export compression needs review: " + path + " " + str(measure))
			failures += 1
	report["quality_metrics"] = metrics
	report["minimum_luma_psnr_db"] = smallest_psnr
	report["imported_texture_bytes"] = texture_bytes
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print("Export artwork checked: %d textures, minimum luma PSNR %.1f dB, %.1f MiB; %d failures" % [report["images"].size(), smallest_psnr, texture_bytes / 1048576.0, failures])
	quit(1 if failures > 0 else 0)
