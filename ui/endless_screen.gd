class_name EndlessScreen
extends Control

signal battle_requested
signal back_requested

const GOLD := Color("#e4c795")
const JADE := Color("#a9c9bb")
const WHITE := Color("#f5f1e9")
const MUTED := Color("#9aaabc")
const RED := Color("#f48177")
const COIN = preload("res://assets/ui/spirit_coin.svg")

var run: EndlessRun
var factory: Callable
var summons: Dictionary
var content: Control
var modal: Control
var message: Label
var view := "rest"
var kind := "cards"
var element := "all"
var page := 0
var selected_uid := ""
var selected_shop := -1
var action_button: Button
var upgrade_button: Button
var next_button: Button
var shop_buttons: Array[Button] = []
var item_views: Array[Control] = []
var workshop: EndlessWorkshop
var hotspots := {}
var hp_hotspot: CampHotspot
var background: TextureRect
var inspect_card: Control
var inspect_source: Control
var inspect_origin := Vector2.ZERO
var inspect_scale := 1.0
var inspect_tween: Tween
var inspect_closing := false
var inspect_keywords: CardKeywordPopup
var inspect_tabs: UpgradeTabs
var preview_entry: Dictionary
var owned_entry: Dictionary
var inspection_kind := "cards"

func configure(progress: EndlessRun, card_factory: Callable, summon_data: Dictionary) -> void:
	run = progress
	factory = card_factory
	summons = summon_data

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background = TextureRect.new()
	background.texture = load("res://assets/backgrounds/mountain_gate.webp")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	view = "setup" if run.state.get("phase", "") == "setup" else "summary" if run.state.get("phase", "") == "ended" else "rest"
	build()

func _box(fill: Color, border: Color = Color("#bd9d6566")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style

func _panel(parent: Node, rect: Rect2, fill: Color = Color("#0b211fec")) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", _box(fill))
	parent.add_child(node)
	return node

func _text(parent: Node, value: String, rect: Rect2, font_size: int = 22, color: Color = WHITE, title: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color("#061510"))
	node.add_theme_constant_override("shadow_outline_size", 5)
	if title: node.add_theme_font_override("font", GameFonts.title())
	parent.add_child(node)
	return node

func _button(parent: Node, value: String, rect: Rect2, callback: Callable) -> Button:
	var node := Button.new()
	_price_caption(node, value)
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", 23)
	node.add_theme_stylebox_override("normal", _box(Color("#15302dec")))
	node.add_theme_stylebox_override("hover", _box(Color("#26413c"), GOLD))
	node.add_theme_stylebox_override("pressed", _box(Color("#4a4933"), GOLD))
	node.add_theme_stylebox_override("disabled", _box(Color("#122321"), Color("#52605a")))
	node.add_theme_color_override("font_color", GOLD)
	node.add_theme_color_override("font_disabled_color", MUTED)
	node.pressed.connect(func(): GameAudio.play_sfx("ui_select", 0.0, 70))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func _price_caption(node: Button, value: String) -> void:
	node.text = value
	if not value.contains("灵钱"): return
	var pattern := RegEx.new()
	pattern.compile("([0-9]+)\\s*灵钱")
	var found := pattern.search(value)
	if found != null: node.set_meta("currency_amount", int(found.get_string(1)))
	node.text = value.replace("灵钱", "").strip_edges()
	node.icon = COIN
	node.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	node.add_theme_constant_override("icon_max_width", 28)
	node.tooltip_text = value

func _money(parent: Node, amount: int, rect: Rect2, font_size: int = 24, color: Color = GOLD, prefix: String = "") -> Control:
	var row := HBoxContainer.new()
	row.name = "SpiritMoney"
	row.position = rect.position
	row.size = rect.size
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.tooltip_text = "灵钱"
	row.set_meta("currency_amount", amount)
	row.add_theme_constant_override("separation", 8)
	if prefix == "": row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	if prefix != "": _text(row, prefix, Rect2(0, 0, 0, rect.size.y), font_size, color)
	var icon := TextureRect.new()
	icon.texture = COIN
	icon.custom_minimum_size = Vector2(font_size + 4, font_size + 4)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_text(row, str(amount), Rect2(0, 0, 0, rect.size.y), font_size, color)
	return row

func _navigate(destination: String) -> void:
	_close_modal(false)
	view = destination
	page = 0
	build()

func build() -> void:
	if is_instance_valid(content):
		content.hide()
		content.queue_free()
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	workshop = null
	hotspots.clear()
	item_views.clear()
	shop_buttons.clear()
	var shade := ColorRect.new()
	shade.size = Vector2(1600, 900)
	background.texture = load("res://assets/backgrounds/mountain_gate.webp" if run.state["phase"] == "setup" else "res://assets/backgrounds/endless_camp.webp")
	shade.color = Color("#051b2028") if view == "rest" else Color("#051b20b8")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(shade)
	if view == "rest":
		var atmosphere := load("res://ui/menu_atmosphere.gd").new() as Control
		content.add_child(atmosphere)
	if view in ["setup", "inventory"]:
		_build_collection()
		return
	var title: String = {"setup": "初入无尽", "rest": "云间小憩", "shop": "云游集市", "inventory": "随身仓库", "summary": "此行已尽", "scout": "下一位对手"}.get(view, "无尽")
	_text(content, title, Rect2(60, 35, 570, 70), 48, GOLD, true)
	if view != "setup" and view != "summary":
		_money(content, int(run.state["gold"]), Rect2(60, 111, 1100, 36), 24, JADE, "第%d关   ·   生命 %d/%d   ·" % [run.stage(), int(run.state["max_hp"]), int(run.state["max_hp"])])
	else:
		_text(content, "15张原版牌 · 80生命 · 无法宝" if view == "setup" else "最高连胜 %d" % run.best, Rect2(60, 111, 1100, 36), 24, JADE)
	_button(content, "返回山门" if view in ["setup", "rest", "summary"] else "返回卡组" if run.state["phase"] == "setup" else "收起摊位" if view == "shop" else "返回休整", Rect2(1340, 53, 200, 58), func():
		if view in ["setup", "rest", "summary"]: back_requested.emit()
		else: _navigate("setup" if run.state["phase"] == "setup" else "rest"))
	message = _text(content, run.error, Rect2(430, 840, 740, 38), 22, RED, false, HORIZONTAL_ALIGNMENT_CENTER)
	match view:
		"setup", "inventory": _build_collection()
		"rest": _build_rest()
		"shop": _build_shop()
		"scout": _build_scout()
		"summary": _build_summary()
	var tween := content.create_tween()
	content.modulate.a = 0.0
	tween.tween_property(content, "modulate:a", 1.0, 0.18)

func _feedback(okay: bool, success: String = "") -> void:
	if view in ["setup", "inventory"] and is_instance_valid(workshop):
		workshop._toast(success if okay else run.error if not run.error.is_empty() else "暂时无法进行")
		return
	build()
	message.text = success if okay else run.error if not run.error.is_empty() else "暂时无法进行"
	message.add_theme_color_override("font_color", JADE if okay else RED)

func _begin() -> void:
	if run.begin_battle(): battle_requested.emit()
	else: _feedback(false)

func _build_rest() -> void:
	_money(content, int(run.state["last_reward"]), Rect2(65, 168, 740, 55), 30, GOLD, "第%d关获胜   ·   +" % int(run.state["wins"]))
	_character(content, "player", Rect2(706, 285, 220, 355))
	var foe := run.opponent()
	var foe_name := ""
	for enemy: Dictionary in run.enemies:
		if enemy["id"] == foe["id"]: foe_name = str(enemy["name"])
	_character(content, str(foe["id"]), Rect2(1270, 230, 215, 330))
	hotspots["shop"] = _hotspot("逛集市", Rect2(75, 320, 320, 285), _navigate.bind("shop"))
	hotspots["inventory"] = _hotspot("整理行囊", Rect2(402, 519, 325, 230), _navigate.bind("inventory"))
	hp_hotspot = _hotspot("养息 · 生命+10", Rect2(998, 465, 260, 265), _improve_hp, "%d灵钱" % run.hp_price())
	hotspots["hp"] = hp_hotspot
	_money(content, run.hp_price(), Rect2(1000, 753, 260, 38), 23, GOLD if int(run.state["gold"]) >= run.hp_price() else MUTED)
	hotspots["scout"] = _hotspot(foe_name + " · 探看", Rect2(1255, 220, 250, 365), _navigate.bind("scout"))
	_text(content, "第%d关 · 生命%d" % [run.stage(), run.enemy_hp()], Rect2(1250, 613, 265, 38), 23, JADE, false, HORIZONTAL_ALIGNMENT_CENTER)
	next_button = _button(content, "启程  →", Rect2(1280, 750, 245, 72), _begin)
	next_button.disabled = not run.deck_problem().is_empty()
	if next_button.disabled: _text(content, run.deck_problem(), Rect2(1230, 826, 320, 35), 20, RED, false, HORIZONTAL_ALIGNMENT_CENTER)

func _hotspot(caption: String, rect: Rect2, action: Callable, detail: String = "") -> CampHotspot:
	var node := CampHotspot.new()
	node.configure(caption, rect, action, detail)
	content.add_child(node)
	return node

func _improve_hp() -> void:
	if int(run.state["gold"]) < run.hp_price():
		message.text = "灵钱不足"; return
	_feedback(run.improve_hp(), "生命 +10")
	var flash := ColorRect.new()
	flash.color = Color("#93edc449")
	flash.size = Vector2(1600, 900)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(flash)
	var motion := flash.create_tween()
	motion.tween_property(flash, "modulate:a", 0.0, 0.55)
	motion.tween_callback(flash.queue_free)

func _character(parent: Node, id: String, rect: Rect2) -> void:
	var node := TextureRect.new()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var path := "res://assets/characters/%s_standee.webp" % id
	if not ResourceLoader.exists(path): path = "res://assets/characters/%s.webp" % id
	if not ResourceLoader.exists(path): return
	node.texture = load(path)
	node.position = rect.position
	node.size = rect.size
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)

func _card(parent: Node, entry: Dictionary, at: Vector2, width: float, callback: Callable = Callable()) -> Control:
	var node: Control
	if entry.has("slot"):
		node = ArtifactView.new()
		node.configure(entry, Vector2(width, width * 1.4))
	else: node = factory.call(entry, Vector2(width, width * 1.4))
	node.position = at
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(node)
	if callback.is_valid():
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		node.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				callback.call(node)
				node.accept_event())
	item_views.append(node)
	return node

func _build_shop() -> void:
	_text(content, "卡牌", Rect2(64, 227, 1030, 40), 28, GOLD, true)
	_text(content, "法宝", Rect2(1120, 227, 420, 40), 28, GOLD, true)
	for index in run.state["shop"].size():
		var offer: Dictionary = run.state["shop"][index]
		var entry: Dictionary = (run.cards if offer["kind"] == "cards" else run.artifacts)[offer["id"]]
		var x: float = 65.0 + index * 210.0
		var node := _card(content, entry, Vector2(x, 300), 180, func(source: Control): _inspect_shop(index, source))
		if bool(offer["sold"]): node.modulate = Color("#777d77")
		var buy_button := _button(content, "已售罄" if bool(offer["sold"]) else "%d 灵钱" % int(offer["price"]), Rect2(x, 575, 180, 64), _purchase.bind(index))
		buy_button.disabled = bool(offer["sold"]) or int(run.state["gold"]) < int(offer["price"])
		shop_buttons.append(buy_button)
	var refresh := _button(content, "换一批   ·   %d 灵钱" % run.refresh_price(), Rect2(607, 733, 386, 65), func(): _feedback(run.refresh_shop()))
	refresh.disabled = int(run.state["gold"]) < run.refresh_price()

func _purchase(index: int) -> void:
	_close_modal(false)
	_feedback(run.buy(index), "已收入仓库")

func _build_scout() -> void:
	var foe := run.opponent()
	var caption := ""
	for enemy: Dictionary in run.enemies:
		if enemy["id"] == foe["id"]: caption = str(enemy["name"])
	_character(content, str(foe["id"]), Rect2(65, 227, 430, 580))
	_text(content, caption, Rect2(72, 176, 460, 60), 39, GOLD, true)
	_text(content, "生命 %d   ·   卡组 %d张" % [run.enemy_hp(), foe["cards"].size()], Rect2(590, 209, 900, 45), 28, GOLD)
	var visible_cards := run.scouted_cards()
	_text(content, "已探知 %d张" % visible_cards.size(), Rect2(590, 270, 900, 40), 23, JADE)
	# Paginate the revealed subset too; future scouting can reveal more than three.
	var pages := maxi(1, ceili(visible_cards.size() / 3.0))
	page = clampi(page, 0, pages - 1)
	for index in range(page * 3, mini(visible_cards.size(), page * 3 + 3)):
		var entry: Dictionary = run.cards[visible_cards[index]]
		_card(content, entry, Vector2(595 + (index % 3) * 280, 350), 240, func(source: Control): _inspect_readonly(entry, source))
	_text(content, "其余 %d张尚未探知" % maxi(0, foe["cards"].size() - visible_cards.size()), Rect2(590, 732, 900, 38), 24, MUTED)
	if pages > 1:
		_button(content, "‹", Rect2(820, 795, 80, 55), _turn_page.bind(-1, pages))
		_text(content, "%d / %d" % [page + 1, pages], Rect2(910, 795, 145, 55), 23, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
		_button(content, "›", Rect2(1065, 795, 80, 55), _turn_page.bind(1, pages))

func _build_summary() -> void:
	_panel(content, Rect2(460, 235, 680, 540))
	_text(content, "止步第%d关" % run.stage(), Rect2(495, 277, 610, 80), 48, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	_text(content, "双方倒下，此行止步" if run.state["reason"] == "tie" else "胜败皆历练，再赴长路", Rect2(495, 380, 610, 45), 27, JADE, true, HORIZONTAL_ALIGNMENT_CENTER)
	var earnings := _money(content, int(run.state["earned"]), Rect2(495, 465, 610, 50), 27, WHITE, "连胜 %d关   ·   获得" % int(run.state["wins"]))
	earnings.set("alignment", BoxContainer.ALIGNMENT_CENTER)
	_text(content, "最高连胜 %d" % run.best, Rect2(495, 535, 610, 40), 23, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	_button(content, "再赴无尽", Rect2(620, 647, 360, 72), func():
		if run.new_run(): _navigate("setup")
		else: _feedback(false))

func _build_collection() -> void:
	workshop = EndlessWorkshop.new()
	workshop.configure_run(run, factory, summons)
	workshop.back_requested.connect(func():
		if view == "setup": back_requested.emit()
		else: _navigate("rest"))
	workshop.battle_requested.connect(func(_deck: Dictionary): _begin())
	workshop.scout_requested.connect(_navigate.bind("scout"))
	workshop.inspect_requested.connect(_workshop_inspect)
	content.add_child(workshop)
	if view == "inventory" and kind == "artifacts": workshop._build_artifact_editor()
	next_button = workshop.play_button

func _workshop_inspect(entry: Dictionary, source: Control) -> void:
	inspection_kind = "artifacts" if entry.has("slot") else "cards"
	if view == "setup": _inspect_owned(str(entry["id"]), "", source); return
	var equipped_origin := source is ArtifactLoadoutRow or source.get_parent() is DeckRow
	var uid := workshop.available_uid(inspection_kind, str(entry["id"]), equipped_origin)
	if uid.is_empty(): uid = workshop.available_uid(inspection_kind, str(entry["id"]), not equipped_origin)
	_inspect_owned(str(entry["id"]), uid, source)

func _turn_page(direction: int, pages: int) -> void:
	page = clampi(page + direction, 0, pages - 1)
	GameAudio.play_sfx("page_turn", 0.0, 100)
	build()

func _equipped(uid: String) -> bool:
	return run.state["deck"].has(uid) if inspection_kind == "cards" else run.state["loadout"].values().has(uid)

func _can_toggle(id: String, uid: String) -> bool:
	if view == "setup": return workshop._can_add(id)
	if inspection_kind == "artifacts" or _equipped(uid): return true
	return run.state["deck"].size() < 30 and ContentCatalog.family_count(run.deck_ids(), id, run.cards) < 2

func _new_modal() -> Control:
	_close_modal(false)
	modal = Control.new()
	modal.size = Vector2(1600, 900)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	var shade := ColorRect.new()
	shade.size = modal.size
	shade.color = Color("#010e12dc")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(shade)
	modal.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: _close_modal())
	_button(modal, "收起", Rect2(1320, 46, 200, 60), _close_modal)
	return modal

func _close_modal(animate: bool = true) -> void:
	if not is_instance_valid(modal): return
	if inspect_closing and animate: return
	if inspect_tween != null: inspect_tween.kill()
	if animate and is_instance_valid(inspect_card):
		inspect_closing = true
		if is_instance_valid(inspect_keywords): inspect_keywords.hide()
		inspect_tween = CardInspectMotion.fold(modal, inspect_card, inspect_origin, inspect_scale)
		inspect_tween.chain().tween_callback(func(): _close_modal(false))
		return
	if is_instance_valid(inspect_source): inspect_source.show()
	modal.hide()
	modal.queue_free()
	modal = null
	inspect_card = null
	inspect_keywords = null
	inspect_source = null
	inspect_closing = false

func _inspect_readonly(entry: Dictionary, source: Control = null) -> void:
	var layer := _new_modal()
	GameAudio.play_sfx("card_focus", 0.0, 150)
	preview_entry = entry
	inspect_source = source
	var width := 480.0 if PlatformUI.is_touch() else 400.0
	var destination := Vector2((1600 - width) / 2.0, 40 if PlatformUI.is_touch() else 120)
	inspect_card = _card(layer, entry, destination, width)
	inspect_origin = destination + Vector2(0, 20)
	inspect_scale = 0.9
	if is_instance_valid(source):
		inspect_origin = get_global_transform().affine_inverse() * source.global_position
		inspect_scale = source.size.x * source.get_global_transform().get_scale().x / (width * get_global_transform().get_scale().x)
		source.hide()
	inspect_tween = CardInspectMotion.focus(layer, inspect_card, inspect_origin, inspect_scale, destination, layer.get_child(0))
	_inspect_keywords(entry, destination, width)

func _inspect_keywords(entry: Dictionary, at: Vector2, width: float) -> void:
	if is_instance_valid(inspect_keywords): inspect_keywords.queue_free()
	inspect_keywords = null
	var entries := CardKeywords.entries(entry, summons)
	if not entries.is_empty():
		inspect_keywords = CardKeywordPopup.new()
		modal.add_child(inspect_keywords)
		inspect_keywords.configure(entries, Rect2(at, Vector2(width, width * 1.4)), size)

func _inspect_shop(index: int, source: Control = null) -> void:
	selected_shop = index
	var offer: Dictionary = run.state["shop"][index]
	var entry: Dictionary = (run.cards if offer["kind"] == "cards" else run.artifacts)[offer["id"]]
	_inspect_readonly(entry, source)
	action_button = _button(modal, "已售罄" if bool(offer["sold"]) else "购买   ·   %d 灵钱" % int(offer["price"]), Rect2(575, 794, 450, 70), _purchase.bind(index))
	action_button.disabled = bool(offer["sold"]) or int(run.state["gold"]) < int(offer["price"])

func _inspect_owned(id: String, uid: String, source: Control = null) -> void:
	selected_uid = uid
	inspection_kind = "cards" if run.cards.has(id) else "artifacts"
	var catalog := run.cards if inspection_kind == "cards" else run.artifacts
	owned_entry = catalog[id]
	_inspect_readonly(owned_entry, source)
	var equipped := false if view == "setup" else _equipped(uid)
	var caption := "入组" if inspection_kind == "cards" else "装备"
	if equipped: caption = "移出卡组" if inspection_kind == "cards" else "卸下"
	action_button = _button(modal, caption, Rect2(485, 794, 300, 64), func():
		var okay := run.change_draft(id, true) if view == "setup" else run.toggle_card(uid) if inspection_kind == "cards" else run.toggle_artifact(uid)
		_close_modal(false)
		if not okay: workshop._toast(run.error); return
		workshop._sync()
		if workshop.view_mode == "editor": workshop._update_editor(id)
		else:
			for slot: String in ArtifactLibrary.SLOTS: workshop._refresh_artifact_row(slot)
			workshop._refresh_artifact_cards())
	action_button.disabled = not _can_toggle(id, uid)
	if view == "setup":
		action_button.position.x = 600
		return
	var level := int(owned_entry["level"])
	inspect_tabs = UpgradeTabs.new()
	modal.add_child(inspect_tabs)
	inspect_tabs.configure(inspect_card.size.x, level)
	inspect_tabs.position = Vector2((1600 - inspect_card.size.x) / 2.0, 720 if PlatformUI.is_touch() else 700)
	for i in 3: inspect_tabs.buttons[i].disabled = i < level or i > level + 1
	inspect_tabs.selected.connect(_preview_level)
	var price := run.upgrade_price(inspection_kind, uid)
	upgrade_button = _button(modal, "已至玄境" if price < 0 else "淬炼1张 · %d灵钱" % price if inspection_kind == "cards" else "淬炼法宝 · %d灵钱" % price, Rect2(815, 794, 300, 64), func():
		if int(preview_entry["level"]) == level:
			inspect_tabs.set_level(level + 1)
			_preview_level(level + 1)
			return
		var okay := run.upgrade(inspection_kind, uid)
		_close_modal(false)
		if not okay: workshop._toast(run.error); return
		workshop.refresh_owned()
		workshop._toast("淬炼完成")
		_inspect_owned(str(run.item(inspection_kind, uid)["id"]), uid))
	upgrade_button.disabled = price < 0 or int(run.state["gold"]) < price

func _preview_level(level: int) -> void:
	if inspect_closing or int(preview_entry["level"]) == level: return
	if inspect_tween != null: inspect_tween.kill()
	var catalog := run.cards if inspection_kind == "cards" else run.artifacts
	var next_id := ContentCatalog.variant_id(ContentCatalog.base_id(owned_entry), level)
	preview_entry = catalog[next_id]
	var at := Vector2((1600 - inspect_card.size.x) / 2.0, 40 if PlatformUI.is_touch() else 120)
	var width := inspect_card.size.x
	inspect_card.hide()
	inspect_card.queue_free()
	inspect_card = _card(modal, preview_entry, at + Vector2(24, 0), width)
	inspect_card.modulate.a = 0.0
	modal.get_child(0).modulate.a = 1.0
	inspect_tween = modal.create_tween().set_parallel(true)
	inspect_tween.tween_property(inspect_card, "position", at, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	inspect_tween.tween_property(inspect_card, "modulate:a", 1.0, 0.24)
	_inspect_keywords(preview_entry, at, width)
	var price := run.upgrade_price(inspection_kind, selected_uid)
	_price_caption(upgrade_button, "淬炼1张 · %d灵钱" % price if level == int(owned_entry["level"]) else "确认淬炼为%s · %d灵钱" % [["原版", "精", "玄"][level], price])

func go_back() -> void:
	if is_instance_valid(modal): _close_modal()
	elif view not in ["setup", "rest", "summary"]: _navigate("setup" if run.state["phase"] == "setup" else "rest")
	else: back_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
