class_name CardPageMotion
extends Control

signal turn_started(page: int, tween: Tween)
signal turn_finished

const TURN_SECONDS := 0.28
const SHIFT := 46.0
const PREPARE_BUDGET_USEC := 2500

var page_roots: Array[Control] = []
var page_views: Array = []
var turn_tween: Tween
var active_page := 0
var pending_page := -1
var pending_direction := 1
var entries: Array[Dictionary] = []
var page_size := 1
var builder: Callable
var art_paths: Array[String] = []
var art_resources := {}

func configure(data: Array[Dictionary], amount: int, create_view: Callable) -> void:
	entries = data.duplicate()
	page_size = amount
	builder = create_view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for index in maxi(1, ceili(float(entries.size()) / page_size)):
		var sheet := Control.new()
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sheet.hide()
		add_child(sheet)
		page_roots.append(sheet)
		page_views.append([])
	# First page is shown immediately. The others are prepared a few cards per
	# idle frame while it remains visible, rather than rebuilt during a turn.
	while not is_prepared(0): _prepare_card(0)
	page_roots[0].show()
	# Decode upcoming illustrations on loader threads. Hold completed resources
	# so configure() can reuse them without decoding a texture on the UI thread.
	for entry in entries:
		var path := "res://assets/cards/generated/%s.webp" % entry["id"]
		if not ResourceLoader.exists(path): path = "res://assets/cards/elements/%s.webp" % entry["element"]
		art_paths.append(path)
		if art_resources.has(path): continue
		if ResourceLoader.has_cached(path): art_resources[path] = load(path)
		else:
			art_resources[path] = null
			ResourceLoader.load_threaded_request(path)
	set_process(page_roots.size() > 1)

func is_prepared(index: int) -> bool:
	return page_views[index].size() == mini(page_size, entries.size() - index * page_size)

func _prepare_card(index: int) -> bool:
	var offset: int = page_views[index].size()
	if not art_paths.is_empty():
		var path := art_paths[index * page_size + offset]
		if art_resources[path] == null:
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
			if status == ResourceLoader.THREAD_LOAD_LOADED: art_resources[path] = ResourceLoader.load_threaded_get(path)
	var entry: Dictionary = entries[index * page_size + offset]
	var view: Control = builder.call(entry, offset, page_roots[index])
	page_views[index].append(view)
	return true

func _process(_delta: float) -> void:
	# Resource preparation must never compete with the visible page transition.
	if turn_tween != null and turn_tween.is_running(): return
	var preparing := pending_page if pending_page >= 0 and not is_prepared(pending_page) else -1
	if preparing < 0:
		for distance in range(1, page_roots.size()):
			for index in [active_page + distance, active_page - distance]:
				if index >= 0 and index < page_roots.size() and not is_prepared(index):
					preparing = index
					break
			if preparing >= 0: break
	if preparing >= 0:
		var began := Time.get_ticks_usec()
		for card in page_size:
			if not _prepare_card(preparing): break
			if is_prepared(preparing) or Time.get_ticks_usec() - began >= PREPARE_BUDGET_USEC: break
	elif pending_page < 0:
		set_process(false)
	if pending_page >= 0 and is_prepared(pending_page): _begin_turn()

func turn_to(index: int, direction: int) -> void:
	if pending_page >= 0 or (turn_tween != null and turn_tween.is_running()): return
	pending_page = index
	pending_direction = direction
	if is_prepared(index): _begin_turn()
	else: set_process(true)

func reset_page() -> void:
	if turn_tween != null: turn_tween.kill()
	turn_tween = null
	pending_page = -1
	active_page = 0
	for index in page_roots.size():
		page_roots[index].position = Vector2.ZERO
		page_roots[index].modulate.a = 1.0
		page_roots[index].visible = index == 0
	set_process(true)

func _begin_turn() -> void:
	var previous := active_page
	var next := pending_page
	var outgoing: Control = page_roots[previous]
	var incoming: Control = page_roots[next]
	pending_page = -1
	incoming.position.x = pending_direction * SHIFT
	incoming.modulate.a = 0.0
	incoming.show()
	turn_tween = create_tween().set_parallel(true)
	turn_tween.tween_property(outgoing, "position:x", -pending_direction * SHIFT, TURN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn_tween.tween_property(outgoing, "modulate:a", 0.0, TURN_SECONDS)
	turn_tween.tween_property(incoming, "position:x", 0.0, TURN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn_tween.tween_property(incoming, "modulate:a", 1.0, TURN_SECONDS)
	active_page = next
	turn_started.emit(next, turn_tween)
	turn_tween.chain().tween_callback(func():
		outgoing.hide()
		outgoing.position = Vector2.ZERO
		outgoing.modulate.a = 1.0
		turn_finished.emit())

func _exit_tree() -> void:
	if turn_tween != null: turn_tween.kill()

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	finish_loading()

func finish_loading() -> void:
	# Each threaded request must be consumed even if its hidden page was never
	# visited, otherwise the loader retains resources after this menu closes.
	for path: String in art_resources:
		if art_resources[path] == null:
			art_resources[path] = ResourceLoader.load_threaded_get(path)
