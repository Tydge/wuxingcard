class_name ContentCatalog
extends RefCounted

const SUFFIXES := ["", "·精", "·玄"]

static func variant_id(base: String, level: int) -> String:
	return base if level == 0 else base + "__" + str(level)

static func base_id(entry: Dictionary) -> String:
	return str(entry.get("base_id", entry.get("id", "")))

static func load_all(path: String) -> Dictionary:
	var result := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array: return result
	for raw: Dictionary in parsed:
		for level in 3:
			if level > 0 and raw.get("upgrades", []).size() < level: continue
			var entry: Dictionary = raw.duplicate(true)
			entry.erase("upgrades")
			if level > 0: entry.merge(raw["upgrades"][level - 1], true)
			entry["base_id"] = str(raw["id"])
			entry["art_id"] = str(raw["id"])
			entry["level"] = level
			entry["id"] = variant_id(str(raw["id"]), level)
			entry["name"] = str(raw["name"]) + SUFFIXES[level]
			if entry.has("card_id"): entry["card_id"] = variant_id(str(raw["card_id"]), level)
			result[entry["id"]] = entry
	return result

static func base_entries(known: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in known.values():
		if int(entry.get("level", 0)) == 0: result.append(entry)
	return result

static func family_count(ids: Array, id: String, known: Dictionary) -> int:
	var family := base_id(known.get(id, {"id": id}))
	var count := 0
	for candidate in ids:
		if base_id(known.get(candidate, {"id": candidate})) == family: count += 1
	return count
