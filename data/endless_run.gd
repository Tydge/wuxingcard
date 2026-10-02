class_name EndlessRun
extends RefCounted

# Run ownership uses copy IDs. A level belongs to one physical card/relic.
const DEFAULT_PATH := "user://endless.json"
const CARD_PRICE := 30
const ARTIFACT_PRICE := 80
const CARD_UPGRADE := [40, 70]
const ARTIFACT_UPGRADE := [60, 100]
const INITIAL_CARDS := 15
const RULES_VERSION := 5

var path: String
var cards: Dictionary
var artifacts: Dictionary
var enemies: Array
var state: Dictionary = {}
var best := 0
var error := ""
var notice := ""

func _init(card_data: Dictionary, artifact_data: Dictionary, enemy_data: Array, save_path: String = DEFAULT_PATH) -> void:
	cards = card_data
	artifacts = artifact_data
	enemies = enemy_data
	path = save_path

func load_run() -> bool:
	if not FileAccess.file_exists(path): return true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or int(raw.get("version", 0)) != 1 or not raw.get("run") is Dictionary:
		error = "进度读取失败，原存档已保留"
		return false
	best = maxi(0, int(raw.get("best", 0)))
	state = raw["run"]
	if not state.is_empty() and int(state.get("rules_version", 1)) < RULES_VERSION:
		var previous := state.duplicate(true)
		if state.get("phase", "") == "battle":
			var backup := FileAccess.open(path + ".rules-v%d" % int(state.get("rules_version", 1)), FileAccess.WRITE)
			if backup == null:
				error = "旧对局备份失败，原存档已保留"
				return false
			backup.store_string(JSON.stringify(raw))
			backup.flush()
			var backed_up := backup.get_error() == OK
			backup.close()
			if not backed_up:
				error = "旧对局备份失败，原存档已保留"
				return false
			state["battle"]["commands"] = []
			state["battle"]["choices"] = []
			notice = "规则已更新，本场从开局继续；连胜与资产已保留"
		state["rules_version"] = RULES_VERSION
		if not _commit(previous): return false
	return true

func _commit(previous: Dictionary, previous_best: int = -1) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	var okay := file != null
	if okay:
		file.store_string(JSON.stringify({"version": 1, "best": best, "run": state}))
		file.flush()
		okay = file.get_error() == OK
		file.close()
	if okay: okay = DirAccess.rename_absolute(temporary, path) == OK
	if not okay:
		state = previous
		if previous_best >= 0: best = previous_best
		error = "进度保存失败，请重试"
	else: error = ""
	return okay

func new_run(seed_value: int = -1) -> bool:
	var previous := state.duplicate(true)
	var random := RandomNumberGenerator.new()
	if seed_value < 0: random.randomize()
	else: random.seed = seed_value
	state = {"rules_version": RULES_VERSION, "phase": "setup", "seed": str(random.seed), "rng": str(random.state), "wins": 0, "gold": 0,
		"earned": 0, "spent": 0, "max_hp": 80, "hp_upgrades": 0, "next_uid": 1,
		"draft": [], "owned_cards": [], "owned_artifacts": [], "deck": [],
		"loadout": {"implement": "", "guard": "", "pendant": ""}, "shop": [],
		"refreshes": 0, "battle": {}, "last_reward": 0, "reason": "", "scout_count": 3, "opponent": {}}
	_prepare_opponent(random)
	_remember(random)
	return _commit(previous)

func _random() -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = int(state["seed"])
	random.state = int(state["rng"])
	return random

func _remember(random: RandomNumberGenerator) -> void: state["rng"] = str(random.state)
func stage() -> int: return int(state.get("wins", 0)) + 1
static func reward(round_index: int) -> int: return 100 + (round_index - 1) * 10
func enemy_hp() -> int: return 40 + int(state.get("wins", 0)) * 10
func opponent() -> Dictionary: return state.get("opponent", {})
func scouted_cards() -> Array[String]:
	var result: Array[String] = []
	var foe := opponent()
	for index in foe.get("scout_order", []).slice(0, int(state.get("scout_count", 3))):
		result.append(str(foe["cards"][int(index)]))
	return result

func _prepare_opponent(random: RandomNumberGenerator) -> void:
	var foe := generate_enemy(random, int(state["earned"]))
	var order: Array[int] = []
	for index in foe["cards"].size(): order.append(index)
	for index in range(order.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var swap := order[index]
		order[index] = order[other]
		order[other] = swap
	foe["scout_order"] = order
	state["opponent"] = foe
func hp_price() -> int: return 60 + int(state.get("hp_upgrades", 0)) * 20
func refresh_price() -> int: return 20 + int(state.get("refreshes", 0)) * 20
func is_rest() -> bool: return state.get("phase", "") == "rest"

func change_draft(id: String, add: bool) -> bool:
	if state.get("phase", "") != "setup" or not cards.has(id) or int(cards[id]["level"]) != 0: return false
	var draft: Array = state["draft"]
	if add and (draft.size() >= INITIAL_CARDS or draft.count(id) >= DeckStore.MAX_COPIES): return false
	if not add and not draft.has(id): return false
	var previous := state.duplicate(true)
	if add: draft.append(id)
	else: draft.erase(id)
	return _commit(previous)

func _own(kind: String, id: String) -> String:
	var uid := str(state["next_uid"])
	state["next_uid"] = int(state["next_uid"]) + 1
	state["owned_" + kind].append({"uid": uid, "id": id})
	return uid

func item(kind: String, uid: String) -> Dictionary:
	for entry: Dictionary in state.get("owned_" + kind, []):
		if str(entry["uid"]) == uid: return entry
	return {}

func deck_ids() -> Array[String]:
	var ids: Array[String] = []
	for uid in state.get("deck", []):
		var entry := item("cards", str(uid))
		if not entry.is_empty(): ids.append(str(entry["id"]))
	return ids

func deck_problem() -> String:
	if deck_ids().size() != state.get("deck", []).size(): return "卡组中有失效卡牌"
	return DeckStore.new(cards).problem(deck_ids())

func loadout_ids() -> Dictionary:
	var result := {}
	for slot in ArtifactLibrary.SLOTS:
		result[slot] = str(item("artifacts", str(state["loadout"].get(slot, ""))).get("id", ""))
	return result

func toggle_card(uid: String) -> bool:
	if not is_rest(): return false
	var entry := item("cards", uid)
	if entry.is_empty(): return false
	var ids := deck_ids()
	var equipped: Array = state["deck"]
	if not equipped.has(uid) and (equipped.size() >= 30 or ContentCatalog.family_count(ids, str(entry["id"]), cards) >= DeckStore.MAX_COPIES): return false
	var previous := state.duplicate(true)
	if equipped.has(uid): equipped.erase(uid)
	else: equipped.append(uid)
	return _commit(previous)

func toggle_artifact(uid: String) -> bool:
	if not is_rest(): return false
	var entry := item("artifacts", uid)
	if entry.is_empty(): return false
	var slot: String = artifacts[entry["id"]]["slot"]
	var previous := state.duplicate(true)
	state["loadout"][slot] = "" if str(state["loadout"][slot]) == uid else uid
	return _commit(previous)

func upgrade_price(kind: String, uid: String) -> int:
	var entry := item(kind, uid)
	if entry.is_empty(): return -1
	var catalog := cards if kind == "cards" else artifacts
	var level := int(catalog[entry["id"]]["level"])
	return -1 if level >= 2 else int((CARD_UPGRADE if kind == "cards" else ARTIFACT_UPGRADE)[level])

func upgrade(kind: String, uid: String) -> bool:
	if not is_rest() or kind not in ["cards", "artifacts"]: return false
	var price := upgrade_price(kind, uid)
	if price < 0 or int(state["gold"]) < price: return false
	var previous := state.duplicate(true)
	var entry := item(kind, uid)
	var catalog := cards if kind == "cards" else artifacts
	var content: Dictionary = catalog[entry["id"]]
	entry["id"] = ContentCatalog.variant_id(ContentCatalog.base_id(content), int(content["level"]) + 1)
	state["gold"] = int(state["gold"]) - price
	state["spent"] = int(state["spent"]) + price
	return _commit(previous)

func improve_hp() -> bool:
	if not is_rest() or int(state["gold"]) < hp_price(): return false
	var previous := state.duplicate(true)
	var price := hp_price()
	state["gold"] = int(state["gold"]) - price
	state["spent"] = int(state["spent"]) + price
	state["hp_upgrades"] = int(state["hp_upgrades"]) + 1
	state["max_hp"] = int(state["max_hp"]) + 10
	return _commit(previous)

func _roll_shop(random: RandomNumberGenerator) -> void:
	state["shop"] = []
	for kind in ["cards", "artifacts"]:
		var pool := ContentCatalog.base_entries(cards if kind == "cards" else artifacts)
		for i in (5 if kind == "cards" else 2):
			var index := random.randi_range(0, pool.size() - 1)
			var entry: Dictionary = pool.pop_at(index)
			state["shop"].append({"kind": kind, "id": str(entry["id"]), "price": CARD_PRICE if kind == "cards" else ARTIFACT_PRICE, "sold": false})

func refresh_shop() -> bool:
	if not is_rest() or int(state["gold"]) < refresh_price(): return false
	var previous := state.duplicate(true)
	var price := refresh_price()
	var random := _random()
	state["gold"] = int(state["gold"]) - price
	state["spent"] = int(state["spent"]) + price
	state["refreshes"] = int(state["refreshes"]) + 1
	_roll_shop(random)
	_remember(random)
	return _commit(previous)

func buy(index: int) -> bool:
	if not is_rest() or index < 0 or index >= state["shop"].size(): return false
	var offer: Dictionary = state["shop"][index]
	if bool(offer["sold"]) or int(state["gold"]) < int(offer["price"]): return false
	var previous := state.duplicate(true)
	state["gold"] = int(state["gold"]) - int(offer["price"])
	state["spent"] = int(state["spent"]) + int(offer["price"])
	_own(str(offer["kind"]), str(offer["id"]))
	offer["sold"] = true
	return _commit(previous)

func begin_battle(options: Dictionary = {}) -> bool:
	var phase := str(state.get("phase", ""))
	if phase not in ["setup", "rest"]: return false
	if phase == "setup" and state["draft"].size() != INITIAL_CARDS: return false
	if phase == "rest" and not deck_problem().is_empty(): return false
	var previous := state.duplicate(true)
	if phase == "setup":
		for id in state["draft"]: state["deck"].append(_own("cards", str(id)))
		state["draft"] = []
	var random := _random()
	var foe := opponent().duplicate(true)
	state["battle"] = {"seed": str(random.randi()), "enemy": foe, "commands": [], "choices": []}
	if options.get("first_side", "") in ["player", "enemy"]: state["battle"]["first_side"] = options["first_side"]
	_remember(random)
	state["phase"] = "battle"
	return _commit(previous)

func battle_deck() -> Dictionary:
	return {"id": "endless", "name": "无尽 · 第%d关" % stage(), "cards": deck_ids(), "artifacts": loadout_ids()}

func battle_options() -> Dictionary:
	var foe: Dictionary = state["battle"]["enemy"]
	var options := {"player_hp": int(state["max_hp"]), "enemy_hp": enemy_hp(), "enemy_deck": foe["cards"], "enemy_artifacts": foe["artifacts"]}
	if state["battle"].has("first_side"): options["first_side"] = state["battle"]["first_side"]
	return options

func record_command(command: Dictionary) -> bool:
	if state.get("phase", "") != "battle": return false
	var previous := state.duplicate(true)
	state["battle"]["commands"].append(command.duplicate(true))
	return _commit(previous)

func record_choice(index: int) -> bool:
	if state.get("phase", "") != "battle": return false
	var previous := state.duplicate(true)
	state["battle"]["choices"].append(index)
	return _commit(previous)

func replay_battle(manager: BattleManager) -> bool:
	if state.get("phase", "") != "battle": return false
	var saved: Dictionary = state["battle"]
	manager.replay_choice_indices.assign(saved["choices"])
	manager.start_battle(str(saved["enemy"]["id"]), "random", int(saved["seed"]), battle_deck(), battle_options())
	for command: Dictionary in saved["commands"]:
		if not manager.pending_choice.is_empty() or manager.phase in BattleManager.FINISHED_PHASES: return false
		match command["kind"]:
			"card":
				if not manager.play_player_card(int(command["index"]), command["target"]): return false
			"artifact":
				if not manager.activate_artifact(manager.player, command["target"]): return false
			"qi":
				if not manager.convert_qi(manager.player, str(command.get("element", ""))): return false
			"end_turn": manager.end_player_turn()
			"enemy":
				var action := manager.peek_enemy_action()
				manager.enemy_step(int(action["index"]), action["target"], str(action.get("kind", "card")))
	return manager.phase != "menu" and manager.replay_choice_indices.is_empty()

func settle(result: String) -> bool:
	if state.get("phase", "") != "battle" or result not in BattleManager.FINISHED_PHASES: return false
	var previous := state.duplicate(true)
	var previous_best := best
	if result == "victory":
		var amount := reward(stage())
		state["wins"] = int(state["wins"]) + 1
		state["gold"] = int(state["gold"]) + amount
		state["earned"] = int(state["earned"]) + amount
		state["last_reward"] = amount
		state["phase"] = "rest"
		state["refreshes"] = 0
		var random := _random()
		_roll_shop(random)
		_prepare_opponent(random)
		_remember(random)
	else:
		state["phase"] = "ended"
		state["reason"] = result
	best = maxi(best, int(state["wins"]))
	state["battle"] = {}
	return _commit(previous, previous_best)

func generate_enemy(random: RandomNumberGenerator, budget: int) -> Dictionary:
	var pool := ContentCatalog.base_entries(cards)
	var size := random.randi_range(20, 30)
	var ids: Array[String] = []
	# Draw a broad random deck, retaining enough inexpensive cards to play.
	for i in size:
		var candidates: Array[String] = []
		for entry in pool:
			var id := str(entry["id"])
			if ids.count(id) >= 2: continue
			if i < ceili(size * 0.4) and int(entry["cost"]) > 1: continue
			candidates.append(id)
		ids.append(candidates[random.randi_range(0, candidates.size() - 1)])
	var loadout := {"implement": "", "guard": "", "pendant": ""}
	var remaining := budget
	for attempt in 250:
		var actions: Array[Dictionary] = []
		for i in ids.size():
			var entry: Dictionary = cards[ids[i]]
			var level := int(entry["level"])
			if level < 2 and remaining >= int(CARD_UPGRADE[level]):
				actions.append({"kind": "card_upgrade", "index": i, "price": CARD_UPGRADE[level]})
		for slot in ArtifactLibrary.SLOTS:
			var id := str(loadout[slot])
			if id.is_empty() and remaining >= ARTIFACT_PRICE:
				# Empty equipment slots receive priority over a sea of card upgrades.
				for weight in 12: actions.append({"kind": "artifact_buy", "slot": slot, "price": ARTIFACT_PRICE})
			elif not id.is_empty():
				var level := int(artifacts[id]["level"])
				if level < 2 and remaining >= int(ARTIFACT_UPGRADE[level]):
					for weight in 4: actions.append({"kind": "artifact_upgrade", "slot": slot, "price": ARTIFACT_UPGRADE[level]})
		# Occasional purchased replacements keep spending varied without invalidating the deck.
		if remaining >= CARD_PRICE and attempt < 3 and not actions.is_empty():
			actions.append({"kind": "card_buy", "price": CARD_PRICE})
		if actions.is_empty(): break
		var action: Dictionary = actions[random.randi_range(0, actions.size() - 1)]
		match action["kind"]:
			"card_upgrade":
				var entry: Dictionary = cards[ids[action["index"]]]
				ids[action["index"]] = ContentCatalog.variant_id(ContentCatalog.base_id(entry), int(entry["level"]) + 1)
			"artifact_buy":
				var candidates: Array[String] = []
				for entry in ContentCatalog.base_entries(artifacts):
					if entry["slot"] == action["slot"]: candidates.append(str(entry["id"]))
				loadout[action["slot"]] = candidates[random.randi_range(0, candidates.size() - 1)]
			"artifact_upgrade":
				var entry: Dictionary = artifacts[loadout[action["slot"]]]
				loadout[action["slot"]] = ContentCatalog.variant_id(ContentCatalog.base_id(entry), int(entry["level"]) + 1)
			"card_buy":
				var index := random.randi_range(0, ids.size() - 1)
				var candidates: Array[String] = []
				for entry in pool:
					if ContentCatalog.family_count(ids, str(entry["id"]), cards) < 2 and int(entry["cost"]) <= int(cards[ids[index]]["cost"]) and int(cards[ids[index]]["level"]) == 0:
						candidates.append(str(entry["id"]))
				if candidates.is_empty(): continue
				ids[index] = candidates[random.randi_range(0, candidates.size() - 1)]
		remaining -= int(action["price"])
	return {"id": str(enemies[random.randi_range(0, enemies.size() - 1)]["id"]), "cards": ids,
		"artifacts": loadout, "budget": budget, "spent": budget - remaining}
