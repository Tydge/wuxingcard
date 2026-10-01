extends SceneTree

const SOURCE := "/Users/wangtaizhi/.codex/generated_images/01a0f1c3-a46e-7ed3-aef2-cd54c0ce27bf/"
const FILES := {
	"moon": "exec-697cbc48-a0c8-432d-9b7c-afdf00d0a789.png",
	"crane": "exec-0f9e1252-243d-47d8-8a4a-58dfe08b92e0.png",
	"veil": "exec-0beb8bfd-e3d1-4802-afd2-fd3a1cb0889b.png",
	"spear": "exec-95e1d011-7d9f-401f-a294-f682d96fe13d.png",
	"ink": "exec-c6de314c-72bc-4c58-95dd-29ced7879d07.png"
}

func _initialize() -> void:
	for id in FILES:
		var source := Image.load_from_file(SOURCE + FILES[id])
		assert(source != null and source.get_pixel(0, 0).a == 0.0, "Expected generated transparent character")
		var fullbody := "res://assets/characters/fullbody/%s.webp" % id
		if not FileAccess.file_exists(fullbody): assert(source.save_webp(fullbody, true) == OK)
		var side := int(source.get_width() * 0.70)
		var face := source.get_region(Rect2i(int(source.get_width() * 0.28), 0, side, side))
		face.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		var portrait := "res://assets/characters/%s.webp" % id
		if not FileAccess.file_exists(portrait): assert(face.save_webp(portrait, true) == OK)
		print("Imported ", id, " · transparent fullbody + portrait")
	quit()
