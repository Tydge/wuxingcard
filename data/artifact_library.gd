class_name ArtifactLibrary
extends RefCounted

const PATH := "res://data/artifacts.json"
const SLOTS := ["implement", "guard", "pendant"]
const SLOT_NAMES := {"implement": "法器", "guard": "护身", "pendant": "灵佩"}

static func load_all() -> Dictionary:
	var result := ContentCatalog.load_all(PATH)
	for entry: Dictionary in result.values(): entry["description"] = EffectText.artifact_text(entry)
	return result

static func normalize(raw: Variant, known: Dictionary) -> Dictionary:
	var result := {"implement": "", "guard": "", "pendant": ""}
	if not raw is Dictionary: return result
	for slot in SLOTS:
		var id := str(raw.get(slot, ""))
		if known.has(id) and str(known[id].get("slot", "")) == slot:
			result[slot] = id
	return result

static func random_loadout(known: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result := {"implement": "", "guard": "", "pendant": ""}
	for slot in SLOTS:
		var pool: Array[String] = []
		for id in known:
			if known[id]["slot"] == slot and int(known[id].get("level", 0)) == 0: pool.append(id)
		if not pool.is_empty(): result[slot] = pool[rng.randi_range(0, pool.size() - 1)]
	return result
