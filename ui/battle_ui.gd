extends Control

const BG := Color("#07111d")
const PANEL := Color("#101d2bdc")
const PANEL_DARK := Color("#09121fe9")
const GOLD := Color("#dec596")
const MUTED := Color("#9aaabc")
const WHITE := Color("#f5f1e9")
const RED := Color("#f48177")
const CARD_VIEW_SCENE := preload("res://ui/card_view.tscn")
const CARD_REVEAL_SECONDS := 1.45
const EFFECT_PAUSE_SECONDS := 0.9

var manager: BattleManager
var fx_layer: Control
var battle_fx: BattleFX
var selected_index := -1
var hovered_index := -1
var menu_enemy := "ember"
var menu_deck := "balanced"
var enemy_animating := false
var action_busy := false
var hand_cards: Array[Control] = []
var enemy_backs: Array[Control] = []
var hover_preview: Control
var drag_card: Control
var drag_index := -1
var drag_offset := Vector2.ZERO
var pointer_down := Vector2.ZERO
var player_hidden_index := -1
var enemy_hidden_index := -1
var pending_player_draws := 0
var pending_enemy_draws := 0
var draw_generation := 0
var draw_animation_active := false

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Arial Unicode MS"])
	var custom_theme := Theme.new()
	custom_theme.default_font = font
	custom_theme.default_font_size = 18
	theme = custom_theme
	manager = BattleManager.new()
	add_child(manager)
	manager.changed.connect(_refresh)
	manager.action_event.connect(_on_action_event)
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fx_layer)
	battle_fx = BattleFX.new()
	fx_layer.add_child(battle_fx)
	_refresh()

func _box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 12, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	return s

func _panel(parent: Node, rect: Rect2, color: Color = PANEL, border: Color = Color("#705f49"), radius: int = 12) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _box(color, border, radius))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func _label(parent: Node, value: String, pos: Vector2, sz: Vector2, font_size: int = 18, color: Color = WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = value
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _button(parent: Node, value: String, rect: Rect2, action: Callable, color: Color = Color("#25384a"), accent: Color = GOLD) -> Button:
	var b := Button.new()
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.add_theme_stylebox_override("normal", _box(color, accent.darkened(0.45), 9, 1))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.14), accent, 9, 2))
	b.add_theme_stylebox_override("pressed", _box(accent.darkened(0.5), accent, 9, 2))
	b.add_theme_stylebox_override("disabled", _box(Color("#1b222a"), Color("#43505b"), 9, 1))
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.35))
	b.add_theme_font_size_override("font_size", 21)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _refresh() -> void:
	if not is_inside_tree():
		return
	_clear_hover_preview()
	for child in get_children():
		if child != manager and child != fx_layer:
			remove_child(child)
			child.queue_free()
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	move_child(background, 0)
	var texture: Texture2D = load("res://assets/backgrounds/arena.webp") if ResourceLoader.exists("res://assets/backgrounds/arena.webp") else null
	if texture != null:
		var art := TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.modulate = Color(0.85, 0.9, 1.0, 0.65)
		add_child(art)
		move_child(art, 1)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.05, 0.39)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	move_child(shade, 2)
	if manager.phase == "menu":
		_build_menu()
	else:
		_build_battle()
	move_child(fx_layer, get_child_count() - 1)

func _build_menu() -> void:
	var center := _panel(self, Rect2(350, 140, 900, 650), PANEL_DARK, GOLD.darkened(0.35), 18)
	_label(center, "五 行 · 命 盘", Vector2(55, 45), Vector2(790, 80), 48, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_label(center, "储存灵气，改变防御；支付灵气，露出破绽。", Vector2(80, 130), Vector2(740, 45), 23, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label(center, "选择对手", Vector2(85, 215), Vector2(250, 34), 23, GOLD)
	var enemy_choice := OptionButton.new()
	enemy_choice.position = Vector2(85, 255)
	enemy_choice.size = Vector2(730, 50)
	for info in manager.enemies:
		enemy_choice.add_item("%s  ·  %s" % [info["name"], info["subtitle"]])
		if info["id"] == menu_enemy:
			enemy_choice.select(enemy_choice.item_count - 1)
	enemy_choice.item_selected.connect(func(index: int): menu_enemy = manager.enemies[index]["id"]; _refresh())
	center.add_child(enemy_choice)
	var enemy_info := manager.find_entry(manager.enemies, menu_enemy)
	_label(center, enemy_info["description"], Vector2(90, 312), Vector2(720, 50), 18, MUTED)
	_label(center, "选择牌组", Vector2(85, 380), Vector2(250, 34), 23, GOLD)
	var deck_choice := OptionButton.new()
	deck_choice.position = Vector2(85, 420)
	deck_choice.size = Vector2(730, 50)
	for info in manager.decks:
		deck_choice.add_item(info["name"])
		if info["id"] == menu_deck:
			deck_choice.select(deck_choice.item_count - 1)
	deck_choice.item_selected.connect(func(index: int): menu_deck = manager.decks[index]["id"]; _refresh())
	center.add_child(deck_choice)
	var deck_info := manager.find_entry(manager.decks, menu_deck)
	_label(center, deck_info["description"], Vector2(90, 475), Vector2(720, 45), 18, MUTED)
	_button(center, "进入战斗", Rect2(270, 545, 360, 64), func(): _start_battle(), Color("#704e35"), GOLD)
	_label(self, "操作：悬停查看卡牌，拖到战场打出；点击「结束回合」让对手行动。", Vector2(290, 820), Vector2(1020, 38), 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER)

func _start_battle() -> void:
	selected_index = -1
	hovered_index = -1
	player_hidden_index = -1
	enemy_hidden_index = -1
	pending_player_draws = 0
	pending_enemy_draws = 0
	draw_animation_active = false
	draw_generation += 1
	action_busy = true
	battle_fx.clear_effects()
	manager.start_battle(menu_enemy, menu_deck)

func _build_battle() -> void:
	var arena := ArenaArt.new()
	arena.position = Vector2.ZERO
	arena.size = Vector2(1600, 900)
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arena)
	_build_enemy_hud()
	_build_enemy_hand()
	_build_arena_actor()
	_build_player_hud()
	_build_decks()
	_build_hand()
	_build_end_turn()
	if not draw_animation_active and (pending_player_draws > 0 or pending_enemy_draws > 0):
		var player_count := pending_player_draws
		var enemy_count := pending_enemy_draws
		draw_animation_active = true
		call_deferred("_animate_pending_draws", player_count, enemy_count, draw_generation)
	if manager.phase == "victory" or manager.phase == "defeat":
		_build_result()

func _hp_bar(parent: Node, pos: Vector2, width: float, actor: Combatant) -> void:
	_panel(parent, Rect2(pos, Vector2(width, 18)), Color("#1b2631"), Color("#624d49"), 5)
	var fill := ColorRect.new()
	fill.position = pos + Vector2(3, 3)
	fill.size = Vector2((width - 6) * float(actor.hp) / float(actor.max_hp), 12)
	fill.color = Color("#d95e63") if actor == manager.enemy else Color("#6ec9ae")
	parent.add_child(fill)
	_label(parent, "%d / %d" % [actor.hp, actor.max_hp], pos + Vector2(0, -1), Vector2(width, 20), 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _energy_row(parent: Node, actor: Combatant, pos: Vector2, compact: bool = false) -> void:
	var chip_w := 92.0 if compact else 115.0
	for i in BattleRules.ELEMENTS.size():
		var element: String = BattleRules.ELEMENTS[i]
		var x := pos.x + float(i) * (chip_w + 6)
		var chip := _panel(parent, Rect2(x, pos.y, chip_w, 37), Color("#152435"), BattleRules.color(element).darkened(0.25), 8)
		_label(chip, BattleRules.element_name(element), Vector2(8, 1), Vector2(32, 35), 22, BattleRules.color(element), HORIZONTAL_ALIGNMENT_CENTER)
		_label(chip, str(actor.energy[element]), Vector2(40, 1), Vector2(chip_w - 47, 35), 22, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _status_line(actor: Combatant) -> String:
	if actor.statuses.is_empty():
		return "状态：无"
	var parts: Array[String] = []
	for status in actor.statuses:
		var word: String = manager.STATUS_NAMES.get(status["id"], status["id"])
		if status.get("element", "") != "":
			word += "·" + BattleRules.element_name(status["element"])
		parts.append("%s %d (%d回合)" % [word, int(status["stacks"]), int(status["turns"])])
	return "   ".join(parts)

func _build_enemy_hud() -> void:
	var p := _panel(self, Rect2(232, 16, 1128, 135), PANEL_DARK, GOLD.darkened(0.5))
	_portrait(p, manager.enemy.id, Vector2(12, 12), Vector2(112, 112), true)
	_label(p, manager.enemy.display_name, Vector2(138, 9), Vector2(280, 35), 26, WHITE)
	var info := manager.find_entry(manager.enemies, manager.enemy.id)
	_label(p, info["subtitle"], Vector2(422, 11), Vector2(245, 31), 18, MUTED)
	_hp_bar(p, Vector2(140, 49), 617, manager.enemy)
	_energy_row(p, manager.enemy, Vector2(141, 82))
	_label(p, "手牌 %d     牌库 %d     弃牌 %d" % [manager.enemy.hand.size(), manager.enemy.draw_pile.size(), manager.enemy.discard_pile.size()], Vector2(777, 37), Vector2(324, 31), 19, WHITE)
	_label(p, _status_line(manager.enemy), Vector2(777, 77), Vector2(326, 50), 16, MUTED)

func _portrait(parent: Node, actor_id: String, pos: Vector2, sz: Vector2, enemy_side: bool) -> void:
	var frame := _panel(parent, Rect2(pos, sz), Color("#182839"), GOLD.darkened(0.15), 58)
	var path := "res://assets/characters/%s.webp" % actor_id
	if ResourceLoader.exists(path):
		var image := TextureRect.new()
		image.position = Vector2(6, 6)
		image.size = sz - Vector2(12, 12)
		var atlas := AtlasTexture.new()
		atlas.atlas = load(path)
		atlas.region = Rect2(120, 0, 780, 780)
		image.texture = atlas
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(image)
	else:
		var glyph := "火" if actor_id == "ember" else "水" if actor_id == "tide" else "行" if actor_id == "harmony" else "云"
		_label(frame, glyph, Vector2.ZERO, sz, 53, RED if enemy_side else Color("#95d9da"), HORIZONTAL_ALIGNMENT_CENTER)

func _build_arena_actor() -> void:
	var actor_path := "res://assets/characters/%s_standee.webp" % manager.enemy.id
	if ResourceLoader.exists(actor_path):
		var actor := TextureRect.new()
		actor.texture = load(actor_path)
		actor.position = Vector2(632, 180)
		actor.size = Vector2(320, 480)
		actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		actor.stretch_mode = TextureRect.STRETCH_SCALE
		actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(actor)
		var tween := actor.create_tween().set_loops(3)
		tween.tween_property(actor, "position:y", 174.0, 2.0).set_trans(Tween.TRANS_SINE)
		tween.tween_property(actor, "position:y", 180.0, 2.0).set_trans(Tween.TRANS_SINE)
	else:
		var glyph := _panel(self, Rect2(690, 225, 180, 180), Color("#17304a99"), RED.darkened(0.2), 90)
		_label(glyph, BattleRules.element_name("fire" if manager.enemy.id == "ember" else "water" if manager.enemy.id == "tide" else "earth"), Vector2.ZERO, Vector2(180, 180), 96, RED, HORIZONTAL_ALIGNMENT_CENTER)
	var nameplate := _panel(self, Rect2(652, 444, 256, 40), PANEL_DARK, GOLD.darkened(0.35), 6)
	_label(nameplate, manager.enemy.display_name, Vector2.ZERO, Vector2(256, 40), 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var phase_text := "你的行动" if manager.phase == "player_action" else "敌人行动中" if manager.phase.begins_with("enemy") else "战斗结束"
	var turn_plate := _panel(self, Rect2(660, 493, 240, 45), PANEL_DARK, GOLD.darkened(0.4), 8)
	_label(turn_plate, "第 %d 回合 · %s" % [manager.round_number, phase_text], Vector2.ZERO, Vector2(240, 45), 21, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _build_player_hud() -> void:
	var p := _panel(self, Rect2(18, 696, 255, 188), PANEL_DARK, GOLD.darkened(0.42))
	_portrait(p, "player", Vector2(12, 11), Vector2(76, 76), false)
	_label(p, manager.player.display_name, Vector2(101, 11), Vector2(142, 33), 24, WHITE)
	_hp_bar(p, Vector2(99, 51), 142, manager.player)
	_label(p, "牌库 %d   弃牌 %d" % [manager.player.draw_pile.size(), manager.player.discard_pile.size()], Vector2(12, 90), Vector2(232, 28), 16, MUTED)
	_label(p, _status_line(manager.player), Vector2(12, 120), Vector2(232, 57), 16, MUTED)
	var energies := _panel(self, Rect2(275, 840, 600, 43), PANEL_DARK, GOLD.darkened(0.5), 8)
	_energy_row(energies, manager.player, Vector2(8, 3), true)

func _build_hand() -> void:
	hand_cards.clear()
	var count := manager.player.hand.size()
	if count == 0:
		return
	var card_size := _hand_card_size(count)
	for i in count:
		var card: Dictionary = manager.cards[manager.player.hand[i]]
		var view := _card_front(card, card_size)
		var target_position := _hand_card_position(i, count)
		var old_count := count - pending_player_draws
		view.position = _hand_card_position(i, old_count) if pending_player_draws > 0 and i < old_count else target_position
		view.pivot_offset = Vector2(card_size.x / 2.0, card_size.y * 0.82)
		view.rotation_degrees = _hand_angle(i, count)
		view.modulate = Color.WHITE if manager.player.can_pay(card) else Color(0.68, 0.73, 0.78)
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		view.mouse_entered.connect(_on_hand_hover.bind(i))
		view.mouse_exited.connect(_on_hand_exit.bind(i))
		view.gui_input.connect(_on_hand_input.bind(i))
		add_child(view)
		hand_cards.append(view)
		if view.position != target_position:
			view.create_tween().tween_property(view, "position", target_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i >= count - pending_player_draws or i == player_hidden_index:
			view.visible = false

func _hand_card_size(count: int) -> Vector2:
	var width := 122.0 if count >= 8 else 132.0 if count == 7 else 152.0
	return Vector2(width, width * 1.4)

func _hand_card_position(index: int, count: int) -> Vector2:
	var width := _hand_card_size(count).x
	var step := minf(width - 2.0, 960.0 / maxf(1.0, float(count - 1)))
	var offset := float(index) - float(count - 1) / 2.0
	return Vector2(800.0 + offset * step - width / 2.0, 560.0 + 6.0 * offset * offset)

func _hand_angle(index: int, count: int) -> float:
	return (float(index) - float(count - 1) / 2.0) * 3.8

func _hand_card_center(index: int, count: int) -> Vector2:
	return _hand_card_position(index, count) + Vector2(_hand_card_size(count).x / 2.0, _hand_card_size(count).y * 0.45)

func _card_front(card: Dictionary, card_size: Vector2) -> Panel:
	var view: Panel = CARD_VIEW_SCENE.instantiate()
	view.call("configure", card, card_size.x)
	return view

func _card_back(card_size: Vector2) -> Panel:
	var back: Panel = CARD_VIEW_SCENE.instantiate()
	back.call("configure_back", card_size)
	return back

func _build_enemy_hand() -> void:
	enemy_backs.clear()
	var count := manager.enemy.hand.size()
	for i in count:
		var back := _card_back(Vector2(68, 96))
		var target_position := _enemy_card_position(i, count)
		var old_count := count - pending_enemy_draws
		back.position = _enemy_card_position(i, old_count) if pending_enemy_draws > 0 and i < old_count else target_position
		back.pivot_offset = Vector2(34, 90)
		back.rotation_degrees = (float(i) - float(count - 1) / 2.0) * 4.0
		add_child(back)
		enemy_backs.append(back)
		if back.position != target_position:
			back.create_tween().tween_property(back, "position", target_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i >= count - pending_enemy_draws or i == enemy_hidden_index:
			back.visible = false

func _enemy_card_position(index: int, count: int) -> Vector2:
	return Vector2(800.0 + (float(index) - float(count - 1) / 2.0) * 57.0 - 34.0, 158.0)

func _build_decks() -> void:
	var player_deck := _card_back(Vector2(76, 108))
	player_deck.position = Vector2(1315, 636)
	add_child(player_deck)
	_label(self, str(manager.player.draw_pile.size()), Vector2(1325, 745), Vector2(55, 28), 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var enemy_deck := _card_back(Vector2(67, 92))
	enemy_deck.position = Vector2(1330, 177)
	add_child(enemy_deck)
	_label(self, str(manager.enemy.draw_pile.size()), Vector2(1336, 268), Vector2(55, 26), 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER)

func _on_hand_hover(index: int) -> void:
	if drag_index >= 0 or action_busy or index >= hand_cards.size():
		return
	hovered_index = index
	var view := hand_cards[index]
	view.position.y -= 28
	view.rotation_degrees = 0
	move_child(view, get_child_count() - 2)
	_show_hover_preview(index)

func _on_hand_exit(index: int) -> void:
	if hovered_index != index or drag_index >= 0:
		return
	hovered_index = -1
	if index < hand_cards.size() and is_instance_valid(hand_cards[index]):
		hand_cards[index].position = _hand_card_position(index, hand_cards.size())
		hand_cards[index].rotation_degrees = _hand_angle(index, hand_cards.size())
	_clear_hover_preview()

func _show_hover_preview(index: int) -> void:
	_clear_hover_preview()
	if index < 0 or index >= manager.player.hand.size():
		return
	var card: Dictionary = manager.cards[manager.player.hand[index]]
	hover_preview = _card_front(card, Vector2(270, 378))
	hover_preview.position = Vector2(clampf(_hand_card_center(index, manager.player.hand.size()).x - 135, 285, 1050), 205)
	fx_layer.add_child(hover_preview)
	hover_preview.modulate.a = 0.0
	hover_preview.create_tween().tween_property(hover_preview, "modulate:a", 1.0, 0.13)

func _clear_hover_preview() -> void:
	if is_instance_valid(hover_preview):
		hover_preview.queue_free()
	hover_preview = null

func _on_hand_input(event: InputEvent, index: int) -> void:
	if manager.phase != "player_action" or action_busy or index >= manager.player.hand.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var card: Dictionary = manager.cards[manager.player.hand[index]]
		if not manager.player.can_pay(card):
			_show_floating("灵气不足", "player", RED, 0, _hand_card_center(index, manager.player.hand.size()) + Vector2(-90, -120))
			return
		drag_index = index
		pointer_down = get_global_mouse_position()
		drag_offset = _hand_card_size(manager.player.hand.size()) / 2.0
		_clear_hover_preview()
		if index < hand_cards.size():
			hand_cards[index].visible = false
		drag_card = _card_front(card, _hand_card_size(manager.player.hand.size()))
		drag_card.position = pointer_down - drag_offset
		fx_layer.add_child(drag_card)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if drag_index < 0 or not is_instance_valid(drag_card):
		return
	if event is InputEventMouseMotion:
		var pointer := get_global_mouse_position()
		drag_card.position = pointer - drag_offset
		drag_card.rotation_degrees = 0
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var release := get_global_mouse_position()
		var index := drag_index
		drag_index = -1
		drag_card.queue_free()
		drag_card = null
		if release.y < 610 and release.y > 160 and release.x > 260 and release.x < 1320 and release.distance_to(pointer_down) > 45:
			_play_card_from(index, release)
		else:
			_refresh()
		get_viewport().set_input_as_handled()

func _play_card_from(card_index: int, source: Vector2) -> void:
	if manager.phase != "player_action" or card_index < 0 or card_index >= manager.player.hand.size() or action_busy:
		return
	var card: Dictionary = manager.cards[manager.player.hand[card_index]]
	if not manager.player.can_pay(card):
		_refresh()
		return
	action_busy = true
	player_hidden_index = card_index
	_clear_hover_preview()
	_refresh()
	await _present_card(card, "player", source)
	if manager.phase == "player_action" and card_index < manager.player.hand.size():
		await get_tree().create_timer(battle_fx.cast(card, "player", source)).timeout
		player_hidden_index = -1
		manager.play_player_card(card_index)
		await get_tree().create_timer(EFFECT_PAUSE_SECONDS).timeout
	player_hidden_index = -1
	action_busy = false
	_refresh()

func _build_end_turn() -> void:
	var end := _button(self, "结束回合", Rect2(1350, 798, 215, 72), func(): _on_end_turn(), Color("#53402d"), GOLD)
	end.disabled = manager.phase != "player_action" or action_busy

func _on_end_turn() -> void:
	if action_busy or manager.phase != "player_action":
		return
	manager.end_player_turn()
	selected_index = -1
	hovered_index = -1
	_clear_hover_preview()
	if manager.phase == "enemy_action" and not enemy_animating:
		_run_enemy_turn()

func _run_enemy_turn() -> void:
	enemy_animating = true
	await get_tree().create_timer(0.75).timeout
	while manager.phase == "enemy_action":
		var chosen_index := manager.peek_enemy_card_index()
		if chosen_index < 0:
			manager.enemy_step(-1)
			break
		var card: Dictionary = manager.cards[manager.enemy.hand[chosen_index]]
		var source := _enemy_card_position(chosen_index, manager.enemy.hand.size()) + Vector2(34, 48)
		enemy_hidden_index = chosen_index
		_refresh()
		await _present_card(card, "enemy", source)
		if manager.phase != "enemy_action":
			break
		await get_tree().create_timer(battle_fx.cast(card, "enemy", source)).timeout
		manager.enemy_step(chosen_index)
		enemy_hidden_index = -1
		await get_tree().create_timer(EFFECT_PAUSE_SECONDS).timeout
	enemy_animating = false
	enemy_hidden_index = -1
	_refresh()

func _present_card(card: Dictionary, side: String, source: Vector2) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.19)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.modulate.a = 0.0
	fx_layer.add_child(dim)
	var stage := _card_front(card, Vector2(270, 378))
	fx_layer.add_child(stage)
	stage.pivot_offset = stage.size / 2.0
	stage.position = source - stage.size / 2.0
	stage.scale = Vector2(0.32, 0.32) if side == "enemy" else Vector2(0.56, 0.56)
	var entrance := stage.create_tween().set_parallel(true)
	entrance.tween_property(stage, "position", Vector2(665, 260), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	entrance.tween_property(stage, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_property(dim, "modulate:a", 1.0, 0.4)
	await entrance.finished
	await get_tree().create_timer(CARD_REVEAL_SECONDS).timeout
	var fade := stage.create_tween().set_parallel(true)
	fade.tween_property(stage, "modulate:a", 0.0, 0.24)
	fade.tween_property(dim, "modulate:a", 0.0, 0.24)
	await fade.finished
	stage.queue_free()
	dim.queue_free()

func _animate_pending_draws(player_count: int, enemy_count: int, generation: int) -> void:
	# The model has already appended these cards. Their views stay hidden until the
	# moving card reaches the corresponding fan slot.
	for side in ["player", "enemy"]:
		var count: int = player_count if side == "player" else enemy_count
		for offset in count:
			if generation != draw_generation or manager.phase == "menu":
				return
			var views: Array[Control] = hand_cards if side == "player" else enemy_backs
			var index := views.size() - count + offset
			if index < 0 or index >= views.size() or not is_instance_valid(views[index]):
				continue
			var target := _hand_card_position(index, views.size()) + _hand_card_size(views.size()) / 2.0 if side == "player" else _enemy_card_position(index, views.size()) + Vector2(34, 48)
			var source := Vector2(1353, 690) if side == "player" else Vector2(1364, 224)
			var flying := _card_back(Vector2(88, 124))
			fx_layer.add_child(flying)
			flying.position = source - flying.size / 2.0
			flying.pivot_offset = flying.size / 2.0
			flying.scale = Vector2(0.6, 0.6)
			var tween := flying.create_tween().set_parallel(true)
			tween.tween_property(flying, "position", target - flying.size / 2.0, 0.43).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(flying, "scale", Vector2.ONE, 0.43)
			await tween.finished
			if generation != draw_generation:
				flying.queue_free()
				return
			views = hand_cards if side == "player" else enemy_backs
			if index < views.size() and is_instance_valid(views[index]):
				views[index].visible = true
				views[index].modulate.a = 0.0
				views[index].create_tween().tween_property(views[index], "modulate:a", 1.0, 0.18)
			flying.queue_free()
			await get_tree().create_timer(0.06).timeout
	pending_player_draws = maxi(0, pending_player_draws - player_count)
	pending_enemy_draws = maxi(0, pending_enemy_draws - enemy_count)
	draw_animation_active = false
	if action_busy and manager.round_number == 1 and manager.played_cards == 0:
		action_busy = false
	_refresh()

func _build_result() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := _panel(self, Rect2(480, 225, 640, 425), PANEL_DARK, GOLD, 18)
	var won := manager.phase == "victory"
	_label(box, "胜 利" if won else "败 北", Vector2(70, 36), Vector2(500, 73), 54, GOLD if won else RED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(box, "对阵 %s · %d 回合" % [manager.enemy.display_name, manager.round_number], Vector2(60, 122), Vector2(520, 40), 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label(box, "打出 %d 张牌     造成 %d 伤害     削减 %d 能量" % [manager.played_cards, manager.player_damage, manager.energy_destroyed], Vector2(40, 190), Vector2(560, 65), 19, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_button(box, "再次挑战", Rect2(70, 296, 225, 62), func(): _start_battle(), Color("#604a31"), GOLD)
	_button(box, "更换对手 / 牌组", Rect2(345, 296, 225, 62), func(): manager.phase = "menu"; _refresh(), Color("#293e51"), GOLD)

func _on_action_event(message: String, side: String, kind: String, element: String, amount: int) -> void:
	if fx_layer == null or not is_inside_tree():
		return
	if side not in ["player", "enemy"]:
		return
	var target := Vector2(800, 396) if side == "enemy" else Vector2(146, 744)
	if kind == "damage":
		battle_fx.impact(element, target, "shield" if message.contains("护盾抵消") else "")
	elif kind == "heal" and amount > 0:
		battle_fx.heal(target, element)
	elif kind in ["energy", "energy_loss", "play"] and amount > 0:
		battle_fx.energy(_energy_point(side, element), element, kind == "energy")
	elif kind.begins_with("status_"):
		battle_fx.status(target, element, kind.trim_prefix("status_"))
	elif kind in ["draw", "discard"]:
		if kind == "draw" and not message.contains("手牌已满"):
			if side == "player":
				pending_player_draws += 1
			else:
				pending_enemy_draws += 1
	if kind == "damage" and amount == 0:
		_show_floating("格挡" if message.contains("护盾抵消") else "免疫", side, Color("#bde9ff"))
		return
	if kind not in ["damage", "heal", "energy", "energy_loss"] or amount <= 0:
		return
	var float_point := Vector2(-1, -1)
	if kind in ["energy", "energy_loss"]:
		float_point = _energy_point(side, element) + Vector2(-90, -75 if side == "player" else 35)
	_show_floating(("-" if kind in ["damage", "energy_loss"] else "+") + str(amount), side, RED if kind == "damage" else BattleRules.color(element) if element != "" else GOLD, 0.0, float_point)
	if kind == "damage" and message.contains("克制"):
		_show_floating("克制", side, GOLD, 39.0)
	elif kind == "damage" and message.contains("抵抗"):
		_show_floating("抵抗", side, Color("#bde9ff"), 39.0)

func _energy_point(side: String, element: String) -> Vector2:
	var index := BattleRules.ELEMENTS.find(element)
	if index < 0:
		return Vector2(800, 690)
	return Vector2(418 + index * 121, 117) if side == "enemy" else Vector2(329 + index * 98, 864)

func _show_floating(value: String, side: String, color: Color, y_offset: float = 0.0, position_override: Vector2 = Vector2(-1, -1)) -> void:
	var floating := Label.new()
	floating.text = value
	floating.position = (position_override if position_override.x >= 0 else Vector2(792, 278) if side == "enemy" else Vector2(170, 655)) + Vector2(0, y_offset)
	floating.size = Vector2(180, 50)
	floating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floating.add_theme_font_size_override("font_size", 38 if value.is_valid_int() or value.begins_with("+") or value.begins_with("-") else 28)
	floating.add_theme_color_override("font_color", color)
	fx_layer.add_child(floating)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(floating, "position:y", floating.position.y - 72.0, 0.85)
	tween.tween_property(floating, "modulate:a", 0.0, 0.85)
	tween.chain().tween_callback(floating.queue_free)
