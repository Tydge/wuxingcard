class_name DeckStore
extends RefCounted

const DEFAULT_PATH := "user://decks.json"
const MIN_CARDS := 20
const MAX_CARDS := 30
const MAX_COPIES := 2

var path: String
var cards: Dictionary
var decks: Array[Dictionary] = []
var artifacts: Dictionary = {}

func _init(card_data: Dictionary = {}, save_path: String = DEFAULT_PATH) -> void:
	cards = card_data
	path = save_path
	artifacts = ArtifactLibrary.load_all()

func load_decks() -> void:
	decks.clear()
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("decks") is Array: return
	var seen := {}
	for entry: Variant in data["decks"]:
		if not entry is Dictionary or not entry.get("cards") is Array: continue
		var id := str(entry.get("id", ""))
		if id.is_empty() or seen.has(id): continue
		seen[id] = true
		var ids: Array[String] = []
		var copies := {}
		# Older saves omit retired cards and keep only the current copy limit.
		# The remaining deck can be completed in the editor before battle.
		for card_id: Variant in entry["cards"]:
			var known_id := str(card_id)
			var family := ContentCatalog.base_id(cards.get(known_id, {"id": known_id}))
			if cards.has(known_id) and int(copies.get(family, 0)) < MAX_COPIES:
				ids.append(known_id)
				copies[family] = int(copies.get(family, 0)) + 1
		decks.append({"id": id, "name": str(entry.get("name", "无名卡组")), "cards": ids, "artifacts": ArtifactLibrary.normalize(entry.get("artifacts", {}), artifacts)})

func problem(ids: Array, require_complete: bool = true) -> String:
	if ids.size() > MAX_CARDS: return "最多30张"
	var counts := {}
	for id in ids:
		if not cards.has(id): return "卡牌已失效"
		var family := ContentCatalog.base_id(cards[id])
		counts[family] = int(counts.get(family, 0)) + 1
		if counts[family] > MAX_COPIES: return "同名卡牌最多%d张" % MAX_COPIES
	if require_complete and ids.size() < MIN_CARDS: return "还差%d张" % (MIN_CARDS - ids.size())
	return ""

func find_deck(id: String) -> Dictionary:
	for deck in decks:
		if deck["id"] == id: return deck.duplicate(true)
	return {}

func save_deck(id: String, caption: String, ids: Array[String], allow_draft: bool = true, loadout: Dictionary = {}) -> Dictionary:
	var issue := problem(ids, not allow_draft)
	if not issue.is_empty(): return {"error": issue}
	var previous := decks.duplicate(true)
	if id.is_empty(): id = Crypto.new().generate_random_bytes(12).hex_encode()
	var name := caption.strip_edges().left(24)
	if name.is_empty(): name = "无名卡组"
	var saved := {"id": id, "name": name, "cards": ids.duplicate(), "artifacts": ArtifactLibrary.normalize(loadout, artifacts)}
	var found := false
	for i in decks.size():
		if decks[i]["id"] == id:
			decks[i] = saved
			found = true
			break
	if not found: decks.append(saved)
	if not _write():
		decks.assign(previous)
		return {"error": "保存失败，请重试"}
	return saved.duplicate(true)

func delete_deck(id: String) -> bool:
	var previous := decks.duplicate(true)
	for i in decks.size():
		if decks[i]["id"] == id:
			decks.remove_at(i)
			if _write(): return true
			decks.assign(previous)
			return false
	return false

func _write() -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"version": 2, "decks": decks}, "\t"))
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay: return false
	return DirAccess.rename_absolute(temporary, path) == OK
