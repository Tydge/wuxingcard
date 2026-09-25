extends Control

const BG := Color("#07111d")
const PANEL := Color("#101d2bdc")
const PANEL_DARK := Color("#09121fe9")
const GOLD := Color("#dec596")
const MUTED := Color("#9aaabc")
const WHITE := Color("#f5f1e9")
const RED := Color("#f48177")
const HP_FILL := Color("#d95e63")
const CARD_VIEW_SCENE := preload("res://ui/card_view.tscn")
const SUMMON_CARD_VIEW_SCENE := preload("res://ui/summon_card_view.tscn")
const CARD_BACK_SCENE := preload("res://ui/card_back.tscn")
const SUMMON_VIEW_SCENE := preload("res://ui/summon_view.tscn")
const TARGET_MARKER_SCRIPT := preload("res://ui/target_marker.gd")
const STATUS_ICON_SCRIPT := preload("res://ui/status_icon.gd")
const CARD_REVEAL_SECONDS := 1.45
const EFFECT_PAUSE_SECONDS := 0.9

# --- horizontal arena layout (1600x900 design viewport) ----------------------
# The player stands on the left and the enemy on the right, facing each other.
# Everything is point symmetric about the viewport centre: mirroring a point p
# gives VIEW_SIZE - p. The hands use the same opposing fan geometry, with
# independent offsets from their respective screen edges.
const VIEW_SIZE := Vector2(1600, 900)

const HUD_SIZE := Vector2(460, 160)
const HUD_MARGIN := 16.0
const HUD_PORTRAIT := Rect2(10, 10, 72, 72)
const HUD_NAME := Rect2(92, 8, 356, 32)
const HUD_COUNTS := Rect2(92, 40, 356, 22)
const HUD_HP := Rect2(92, 66, 356, 18)
const ORB_DIAMETER := 52.0
const ORB_STEP := 60.0
const ORB_ROW_X := 84.0
const ORB_ROW_Y := 94.0
const STATUS_ICON_SIZE := Vector2(44, 44)
const STATUS_ICON_STEP := 48.0
const STATUS_ICONS_PER_ROW := 8

const STANDEE_SIZE := Vector2(300, 450)
const STANDEE_TOP := 228.0
const STANDEE_MARGIN := 105.0
const MIRROR_ENEMY_STANDEE := true
# Where a card leaves its caster and where effects land on a standee.
const PLAYER_ANCHOR := Vector2(292, 452)
const ENEMY_ANCHOR := Vector2(1308, 452)

const HAND_CENTER_X := 880.0
const HAND_CARD_SIZE := Vector2(152, 212.8)
const HAND_MAX_SPAN := 560.0
const PLAYER_HAND_BASE_Y := 680.0
const ENEMY_HAND_BASE_Y := 710.0
const DECK_SIZE := Vector2(72, 102)
const PLAYER_DECK_POS := Vector2(1512, 764)
const ENEMY_DECK_POS := Vector2(16, 34)
const DROP_ZONE_Y := 600.0
const REVEAL_CENTER := Vector2(665, 260)
const TURN_PLATE := Rect2(640, 330, 320, 44)
const SUMMON_SIZE := Vector2(190, 190)
const SUMMON_CENTERS := [Vector2(540, 320), Vector2(700, 452), Vector2(540, 584)]
const SUMMON_TARGET_RADIUS := 82.0
const ENEMY_HERO_TARGET := Rect2(1180, 198, 345, 445)

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
var hovered_summon_side := ""
var hovered_summon_slot := -1
var drag_card: Control
var drag_hints: Array[Control] = []
var damage_preview: Panel
var damage_preview_label: Label
var turn_notice: Panel
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
	manager.summon_event.connect(_on_summon_event)
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fx_layer)
	battle_fx = BattleFX.new()
	battle_fx.set_anchors(PLAYER_ANCHOR, ENEMY_ANCHOR)
	fx_layer.add_child(battle_fx)
	_refresh()

func _box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 12, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	return s

func _panel(parent: Node, rect: Rect2, color: Color = PANEL, border: Color = Color("#705f49"), radius: int = 12, border_width: int = 1) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _box(color, border, radius, border_width))
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
		add_child(art)
		move_child(art, 1)
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
	_label(self, "操作：伤害牌拖向角色或召唤物；召唤牌拖向空槽；其他牌拖到战场上方。", Vector2(290, 820), Vector2(1020, 38), 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER)

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
	_clear_drag_hints()
	battle_fx.clear_effects()
	manager.start_battle(menu_enemy, menu_deck)

func _build_battle() -> void:
	_build_standees()
	_build_summons()
	_build_enemy_hand()
	_build_combatant_hud("enemy")
	_build_combatant_hud("player")
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

# --- HUD --------------------------------------------------------------------

func _hud_origin(side: String) -> Vector2:
	if side == "player":
		return Vector2(HUD_MARGIN, VIEW_SIZE.y - HUD_MARGIN - HUD_SIZE.y)
	return Vector2(VIEW_SIZE.x - HUD_MARGIN - HUD_SIZE.x, HUD_MARGIN)

func _hud_local(side: String, local: Rect2) -> Rect2:
	if side == "player":
		return local
	return Rect2(HUD_SIZE.x - local.position.x - local.size.x, local.position.y, local.size.x, local.size.y)

func _hud_global_rect(side: String, local: Rect2) -> Rect2:
	return Rect2(_hud_origin(side) + _hud_local(side, local).position, local.size)

func _build_combatant_hud(side: String) -> void:
	var enemy_side := side == "enemy"
	var actor: Combatant = manager.enemy if enemy_side else manager.player
	var panel := _panel(self, Rect2(_hud_origin(side), HUD_SIZE), PANEL_DARK, GOLD.darkened(0.42), 14)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if enemy_side else HORIZONTAL_ALIGNMENT_LEFT
	var tag_align := HORIZONTAL_ALIGNMENT_LEFT if enemy_side else HORIZONTAL_ALIGNMENT_RIGHT

	var portrait := _hud_local(side, HUD_PORTRAIT)
	_portrait(panel, actor.id, portrait.position, portrait.size, enemy_side)

	var name_rect := _hud_local(side, HUD_NAME)
	_label(panel, actor.display_name, name_rect.position, name_rect.size, 24, WHITE, align)
	_label(panel, _side_subtitle(side), name_rect.position, name_rect.size, 16, GOLD.darkened(0.1), tag_align)

	var counts := _hud_local(side, HUD_COUNTS)
	_label(panel, "手牌 %d    牌库 %d    弃牌 %d" % [actor.hand.size(), actor.draw_pile.size(), actor.discard_pile.size()],
		counts.position, counts.size, 15, MUTED, align)

	_hp_bar(panel, _hud_local(side, HUD_HP), actor)

	# The orb row is laid out identically on both sides so 金木水火土 always read
	# left to right; only the surrounding text mirrors.
	for i in BattleRules.ELEMENTS.size():
		_energy_orb(panel, actor, side, i)
	_build_status_icons(actor, side)

func _side_subtitle(side: String) -> String:
	if side == "enemy":
		return str(manager.find_entry(manager.enemies, manager.enemy.id).get("subtitle", ""))
	return str(manager.find_entry(manager.decks, manager.selected_deck_id).get("name", ""))

func _hp_bar(parent: Node, rect: Rect2, actor: Combatant) -> void:
	_panel(parent, rect, Color("#1b2631"), Color("#624d49"), 6)
	var inner := rect.grow(-3.0)
	var ratio := clampf(float(actor.hp) / float(maxi(1, actor.max_hp)), 0.0, 1.0)
	var fill := ColorRect.new()
	fill.position = inner.position
	fill.size = Vector2(inner.size.x * ratio, inner.size.y)
	fill.color = HP_FILL
	parent.add_child(fill)
	_label(parent, "%d / %d" % [actor.hp, actor.max_hp], rect.position, rect.size, 14, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _energy_orb(parent: Node, actor: Combatant, side: String, index: int) -> void:
	var element: String = BattleRules.ELEMENTS[index]
	var tint := BattleRules.color(element)
	# The orb row is centred in the panel and deliberately not mirrored, so both
	# sides read 金木水火土 left to right; only the surrounding text mirrors.
	var local := Rect2(Vector2(ORB_ROW_X + float(index) * ORB_STEP, ORB_ROW_Y), Vector2(ORB_DIAMETER, ORB_DIAMETER))
	var orb := _panel(parent, local, Color("#0c1826").lerp(tint, 0.14), tint.darkened(0.1), int(ORB_DIAMETER / 2.0), 2)
	_label(orb, BattleRules.element_name(element), Vector2(0, 2), Vector2(ORB_DIAMETER, 18), 14, tint, HORIZONTAL_ALIGNMENT_CENTER)
	_label(orb, str(actor.energy[element]), Vector2(0, 17), Vector2(ORB_DIAMETER, 30), 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _build_status_icons(actor: Combatant, side: String) -> void:
	for i in actor.statuses.size():
		var status: Dictionary = actor.statuses[i]
		var icon: Control = STATUS_ICON_SCRIPT.new()
		icon.call("configure", status, manager.status_tooltip(status))
		var row := int(i / STATUS_ICONS_PER_ROW)
		var column := i % STATUS_ICONS_PER_ROW
		var origin := _hud_origin(side)
		if side == "player":
			icon.position = origin + Vector2(12.0 + column * STATUS_ICON_STEP, -8.0 - STATUS_ICON_SIZE.y - row * STATUS_ICON_STEP)
		else:
			icon.position = origin + Vector2(HUD_SIZE.x - 12.0 - STATUS_ICON_SIZE.x - column * STATUS_ICON_STEP, HUD_SIZE.y + 8.0 + row * STATUS_ICON_STEP)
		add_child(icon)

func _portrait(parent: Node, actor_id: String, pos: Vector2, sz: Vector2, enemy_side: bool) -> void:
	var frame := _panel(parent, Rect2(pos, sz), Color("#182839"), GOLD.darkened(0.15), 12)
	var path := "res://assets/characters/%s.webp" % actor_id
	if ResourceLoader.exists(path):
		var image := TextureRect.new()
		image.position = Vector2(4, 4)
		image.size = sz - Vector2(8, 8)
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
		_label(frame, glyph, Vector2.ZERO, sz, 40, RED if enemy_side else Color("#95d9da"), HORIZONTAL_ALIGNMENT_CENTER)

# --- arena actors -----------------------------------------------------------

func _build_standees() -> void:
	_standee("player", STANDEE_MARGIN, false, 2.4)
	_standee(manager.enemy.id, VIEW_SIZE.x - STANDEE_MARGIN - STANDEE_SIZE.x, MIRROR_ENEMY_STANDEE, 2.0)

func _summon_slot_rect(side: String, slot: int) -> Rect2:
	var center: Vector2 = SUMMON_CENTERS[slot]
	if side == "enemy":
		center.x = VIEW_SIZE.x - center.x
	return Rect2(center - SUMMON_SIZE / 2.0, SUMMON_SIZE)

func _summon_point(side: String, slot: int) -> Vector2:
	return _summon_slot_rect(side, slot).get_center()

func _build_summons() -> void:
	for side in ["player", "enemy"]:
		var owner: Combatant = manager.player if side == "player" else manager.enemy
		for slot in owner.summons.size():
			var summoned: Summon = owner.summons[slot]
			if summoned == null:
				continue
			var view: Panel = SUMMON_VIEW_SCENE.instantiate()
			view.call("configure", summoned)
			view.position = _summon_slot_rect(side, slot).position
			view.mouse_entered.connect(_on_summon_hover.bind(side, slot))
			view.mouse_exited.connect(_on_summon_exit.bind(side, slot))
			add_child(view)

func _standee(actor_id: String, x: float, mirrored: bool, bob_seconds: float) -> void:
	var path := "res://assets/characters/%s_standee.webp" % actor_id
	if not ResourceLoader.exists(path):
		path = "res://assets/characters/%s.webp" % actor_id
	if ResourceLoader.exists(path):
		var actor := TextureRect.new()
		actor.texture = load(path)
		actor.size = STANDEE_SIZE
		# Mirroring happens around the right edge so the fighter keeps its slot.
		actor.position = Vector2(x + (STANDEE_SIZE.x if mirrored else 0.0), STANDEE_TOP)
		actor.scale = Vector2(-1.0 if mirrored else 1.0, 1.0)
		actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		actor.stretch_mode = TextureRect.STRETCH_SCALE
		actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(actor)
		var tween := actor.create_tween().set_loops()
		tween.tween_property(actor, "position:y", STANDEE_TOP - 6.0, bob_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(actor, "position:y", STANDEE_TOP, bob_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		var glyph := "火" if actor_id == "ember" else "水" if actor_id == "tide" else "行" if actor_id == "harmony" else "云"
		var box := _panel(self, Rect2(x + 60.0, STANDEE_TOP + 110.0, 180, 180), Color("#17304a99"), RED.darkened(0.2), 90)
		_label(box, glyph, Vector2.ZERO, Vector2(180, 180), 96, RED if actor_id != "player" else Color("#95d9da"), HORIZONTAL_ALIGNMENT_CENTER)

func _show_turn_notice(side: String) -> void:
	if is_instance_valid(turn_notice):
		turn_notice.queue_free()
	var caption := "第 %d 回合 · %s" % [manager.round_number, "你的行动" if side == "player" else "敌人行动"]
	turn_notice = _panel(fx_layer, TURN_PLATE, PANEL_DARK, GOLD.darkened(0.4), 8)
	_label(turn_notice, caption, Vector2.ZERO, TURN_PLATE.size, 21, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	turn_notice.modulate.a = 0.0
	var tween := turn_notice.create_tween()
	tween.tween_property(turn_notice, "modulate:a", 1.0, 0.18)
	tween.tween_interval(1.2)
	tween.tween_property(turn_notice, "modulate:a", 0.0, 0.42)
	tween.tween_callback(turn_notice.queue_free)

# --- cards ------------------------------------------------------------------

func _build_hand() -> void:
	hand_cards.clear()
	var count := manager.player.hand.size()
	if count == 0:
		return
	var card_size := HAND_CARD_SIZE
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

func _hand_card_position(index: int, count: int) -> Vector2:
	return _fan_card_position(index, count, PLAYER_HAND_BASE_Y)

func _fan_card_position(index: int, count: int, base_y: float) -> Vector2:
	var width := HAND_CARD_SIZE.x
	# Keep the outer cards between the player HUD and the end-turn button.
	# Additional cards overlap instead of shrinking.
	var step := minf(width - 2.0, HAND_MAX_SPAN / maxf(1.0, float(count - 1)))
	var offset := float(index) - float(count - 1) / 2.0
	return Vector2(HAND_CENTER_X + offset * step - width / 2.0, base_y + 6.0 * offset * offset)

func _hand_angle(index: int, count: int) -> float:
	return (float(index) - float(count - 1) / 2.0) * 3.8

func _hand_card_center(index: int, count: int) -> Vector2:
	return _hand_card_position(index, count) + Vector2(HAND_CARD_SIZE.x / 2.0, HAND_CARD_SIZE.y * 0.45)

func _card_front(card: Dictionary, card_size: Vector2) -> Panel:
	for effect in card["effects"]:
		if effect["type"] == "summon":
			var summon_data: Dictionary = manager.summon_templates[effect["summon"]]
			var summon_card: Panel = SUMMON_CARD_VIEW_SCENE.instantiate()
			var display_card := card.duplicate()
			display_card["summon_hp"] = int(summon_data["hp"])
			summon_card.call("configure", display_card, card_size.x)
			return summon_card
	var view: Panel = CARD_VIEW_SCENE.instantiate()
	view.call("configure", card, card_size.x)
	return view

func _card_back(card_size: Vector2, upside_down: bool = false) -> Panel:
	var back: Panel = CARD_BACK_SCENE.instantiate()
	back.call("configure", card_size, upside_down)
	return back

func _build_enemy_hand() -> void:
	enemy_backs.clear()
	var count := manager.enemy.hand.size()
	var card_size := HAND_CARD_SIZE
	for i in count:
		var back := _card_back(card_size, true)
		var target_position := _enemy_card_position(i, count)
		var old_count := count - pending_enemy_draws
		back.position = _enemy_card_position(i, old_count) if pending_enemy_draws > 0 and i < old_count else target_position
		back.pivot_offset = Vector2(card_size.x / 2.0, card_size.y * 0.18)
		back.rotation_degrees = -_hand_angle(i, count)
		add_child(back)
		enemy_backs.append(back)
		if back.position != target_position:
			back.create_tween().tween_property(back, "position", target_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i >= count - pending_enemy_draws or i == enemy_hidden_index:
			back.visible = false

func _enemy_card_position(index: int, count: int) -> Vector2:
	var card_size := HAND_CARD_SIZE
	var opposite_position := _fan_card_position(count - 1 - index, count, ENEMY_HAND_BASE_Y)
	return VIEW_SIZE - opposite_position - card_size

func _build_decks() -> void:
	var player_deck := _card_back(DECK_SIZE)
	player_deck.position = PLAYER_DECK_POS
	add_child(player_deck)
	_label(self, str(manager.player.draw_pile.size()), PLAYER_DECK_POS + Vector2(0, -26), Vector2(DECK_SIZE.x, 24), 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var enemy_deck := _card_back(DECK_SIZE, true)
	enemy_deck.position = ENEMY_DECK_POS
	add_child(enemy_deck)
	_label(self, str(manager.enemy.draw_pile.size()), ENEMY_DECK_POS + Vector2(0, DECK_SIZE.y + 2), Vector2(DECK_SIZE.x, 24), 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER)

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
	hover_preview.position = Vector2(clampf(_hand_card_center(index, manager.player.hand.size()).x - 135.0, 430.0, 1030.0), 265.0)
	fx_layer.add_child(hover_preview)
	hover_preview.modulate.a = 0.0
	hover_preview.create_tween().tween_property(hover_preview, "modulate:a", 1.0, 0.13)

func _on_summon_hover(side: String, slot: int) -> void:
	if drag_index >= 0 or action_busy:
		return
	var owner: Combatant = manager.player if side == "player" else manager.enemy
	var summoned: Summon = owner.summons[slot]
	if summoned == null or not manager.cards.has(summoned.card_id):
		return
	_clear_hover_preview()
	hovered_summon_side = side
	hovered_summon_slot = slot
	hover_preview = _card_front(manager.cards[summoned.card_id], Vector2(270, 378))
	var slot_rect := _summon_slot_rect(side, slot)
	var preview_x := slot_rect.end.x + 18.0 if side == "player" else slot_rect.position.x - 288.0
	hover_preview.position = Vector2(clampf(preview_x, 8.0, VIEW_SIZE.x - 278.0), clampf(slot_rect.get_center().y - 189.0, 145.0, 480.0))
	fx_layer.add_child(hover_preview)
	hover_preview.modulate.a = 0.0
	hover_preview.create_tween().tween_property(hover_preview, "modulate:a", 1.0, 0.13)

func _on_summon_exit(side: String, slot: int) -> void:
	if hovered_summon_side == side and hovered_summon_slot == slot:
		_clear_hover_preview()

func _clear_hover_preview() -> void:
	if is_instance_valid(hover_preview):
		hover_preview.queue_free()
	hover_preview = null
	hovered_summon_side = ""
	hovered_summon_slot = -1

func _on_hand_input(event: InputEvent, index: int) -> void:
	if manager.phase != "player_action" or action_busy or index >= manager.player.hand.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var card: Dictionary = manager.cards[manager.player.hand[index]]
		if not manager.player.can_pay(card):
			var reason := "召唤位已满" if manager.card_target_mode(card) == "slot" and manager.player.first_free_summon_slot() < 0 else "灵气不足"
			_show_floating(reason, "player", RED, 0, _hand_card_center(index, manager.player.hand.size()) + Vector2(-90, -120))
			return
		drag_index = index
		pointer_down = get_global_mouse_position()
		drag_offset = HAND_CARD_SIZE / 2.0
		_clear_hover_preview()
		if index < hand_cards.size():
			hand_cards[index].visible = false
		drag_card = _card_front(card, HAND_CARD_SIZE)
		drag_card.position = pointer_down - drag_offset
		_show_drag_hints(card)
		fx_layer.add_child(drag_card)
		get_viewport().set_input_as_handled()

func _drop_selection(card: Dictionary, point: Vector2) -> Dictionary:
	match manager.card_target_mode(card):
		"slot":
			for slot in manager.player.summons.size():
				if manager.player.summons[slot] == null and point.distance_to(_summon_point("player", slot)) <= SUMMON_TARGET_RADIUS:
					return {"kind": "slot", "slot": slot}
		"damage":
			for slot in manager.enemy.summons.size():
				if manager.enemy.summons[slot] != null and point.distance_to(_summon_point("enemy", slot)) <= SUMMON_TARGET_RADIUS:
					return {"kind": "summon", "slot": slot}
			if ENEMY_HERO_TARGET.has_point(point):
				return {"kind": "hero"}
		"none":
			if point.y < DROP_ZONE_Y:
				return {}
	return {"kind": "invalid"}

func _show_drag_hints(card: Dictionary) -> void:
	_clear_drag_hints()
	var mode := manager.card_target_mode(card)
	var choices: Array[Dictionary] = []
	if mode == "slot":
		for slot in manager.player.summons.size():
			if manager.player.summons[slot] == null:
				choices.append({"selection": {"kind": "slot", "slot": slot}, "point": _summon_point("player", slot)})
	elif mode == "damage":
		choices.append({"selection": {"kind": "hero"}, "point": _anchor("enemy")})
		for slot in manager.enemy.summons.size():
			var summoned: Summon = manager.enemy.summons[slot]
			if summoned != null:
				choices.append({"selection": {"kind": "summon", "slot": slot}, "point": _summon_point("enemy", slot)})
	for choice in choices:
		var marker := TARGET_MARKER_SCRIPT.new()
		marker.configure(mode == "slot")
		var point: Vector2 = choice["point"]
		marker.position = point - marker.size / 2.0
		marker.set_meta("selection", choice["selection"])
		fx_layer.add_child(marker)
		drag_hints.append(marker)
	if mode == "damage":
		damage_preview = _panel(fx_layer, Rect2(Vector2.ZERO, Vector2(200, 42)), Color("#09121ff2"), GOLD, 8)
		damage_preview.z_index = 20
		damage_preview.visible = false
		damage_preview_label = _label(damage_preview, "", Vector2(8, 0), Vector2(184, 42), 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _clear_drag_hints() -> void:
	for hint in drag_hints:
		if is_instance_valid(hint):
			hint.queue_free()
	drag_hints.clear()
	if is_instance_valid(damage_preview):
		damage_preview.queue_free()
	damage_preview = null
	damage_preview_label = null

func _update_drag_hints(card: Dictionary, pointer: Vector2) -> void:
	var selection := _drop_selection(card, pointer)
	for hint in drag_hints:
		var selected: Dictionary = hint.get_meta("selection")
		hint.call("set_highlighted", selected == selection)
	if not is_instance_valid(damage_preview):
		return
	var segments := manager.preview_damage_segments(manager.player, card, selection)
	if segments.is_empty():
		damage_preview.visible = false
		return
	var parts: Array[String] = []
	var total := 0
	for damage in segments:
		parts.append(str(damage))
		total += damage
	var value := parts[0] if parts.size() == 1 else "%s=%d" % ["+".join(parts), total]
	var caption := "预计伤害 " + value
	var width := clampf(44.0 + caption.length() * 12.0, 180.0, 520.0)
	damage_preview.size = Vector2(width, 42)
	damage_preview_label.text = caption
	damage_preview_label.size = Vector2(width - 16.0, 42)
	var preview_x := pointer.x + HAND_CARD_SIZE.x / 2.0 + 20.0
	if preview_x + width > VIEW_SIZE.x - 8.0:
		preview_x = pointer.x - HAND_CARD_SIZE.x / 2.0 - width - 20.0
	damage_preview.position = Vector2(clampf(preview_x, 8.0, VIEW_SIZE.x - width - 8.0), clampf(pointer.y - 21.0, 8.0, VIEW_SIZE.y - 50.0))
	damage_preview.visible = true

func _input(event: InputEvent) -> void:
	if drag_index < 0 or not is_instance_valid(drag_card):
		return
	if event is InputEventMouseMotion:
		var pointer := get_global_mouse_position()
		drag_card.position = pointer - drag_offset
		drag_card.rotation_degrees = 0
		if drag_index < manager.player.hand.size():
			_update_drag_hints(manager.cards[manager.player.hand[drag_index]], pointer)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var release := get_global_mouse_position()
		var index := drag_index
		var card: Dictionary = manager.cards[manager.player.hand[index]]
		var selection := _drop_selection(card, release)
		drag_index = -1
		drag_card.queue_free()
		drag_card = null
		_clear_drag_hints()
		if release.distance_to(pointer_down) > 45 and manager.valid_card_target(manager.player, card, selection) and selection.get("kind", "") != "invalid":
			_play_card_from(index, release, selection)
		else:
			_refresh()
		get_viewport().set_input_as_handled()

func _target_point(side: String, selection: Dictionary) -> Vector2:
	if selection.get("kind", "") in ["slot", "summon"]:
		return _summon_point(side, int(selection["slot"]))
	return _anchor(side)

func _play_card_from(card_index: int, source: Vector2, selection: Dictionary = {}) -> void:
	if manager.phase != "player_action" or card_index < 0 or card_index >= manager.player.hand.size() or action_busy:
		return
	var card: Dictionary = manager.cards[manager.player.hand[card_index]]
	if not manager.player.can_pay(card) or not manager.valid_card_target(manager.player, card, selection):
		_refresh()
		return
	action_busy = true
	player_hidden_index = card_index
	_clear_hover_preview()
	_refresh()
	await _present_card(card, "player", source)
	if manager.phase == "player_action" and card_index < manager.player.hand.size():
		var mode := manager.card_target_mode(card)
		var destination := _target_point("player" if mode == "slot" else "enemy", selection) if mode != "none" else Vector2(-1, -1)
		await get_tree().create_timer(battle_fx.cast(card, "player", Vector2(-1, -1), destination)).timeout
		player_hidden_index = -1
		manager.play_player_card(card_index, selection)
		await get_tree().create_timer(EFFECT_PAUSE_SECONDS).timeout
	player_hidden_index = -1
	action_busy = false
	_refresh()

func _build_end_turn() -> void:
	var end := _button(self, "结束回合", Rect2(1300, 800, 200, 66), func(): _on_end_turn(), Color("#53402d"), GOLD)
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
		var action := manager.peek_enemy_action()
		var chosen_index := int(action["index"])
		if chosen_index < 0:
			manager.enemy_step(-1)
			break
		var selection: Dictionary = action["target"]
		var card: Dictionary = manager.cards[manager.enemy.hand[chosen_index]]
		var enemy_card_size := HAND_CARD_SIZE
		var source := _enemy_card_position(chosen_index, manager.enemy.hand.size()) + enemy_card_size / 2.0
		enemy_hidden_index = chosen_index
		_refresh()
		await _present_card(card, "enemy", source)
		if manager.phase != "enemy_action":
			break
		var mode := manager.card_target_mode(card)
		var destination := _target_point("enemy" if mode == "slot" else "player", selection) if mode != "none" else Vector2(-1, -1)
		await get_tree().create_timer(battle_fx.cast(card, "enemy", Vector2(-1, -1), destination)).timeout
		manager.enemy_step(chosen_index, selection)
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
	entrance.tween_property(stage, "position", REVEAL_CENTER, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
			var hand_size := HAND_CARD_SIZE
			var target := _hand_card_position(index, views.size()) + hand_size / 2.0 if side == "player" else _enemy_card_position(index, views.size()) + hand_size / 2.0
			var source := _draw_pile_point(side)
			var flying := _card_back(hand_size, side == "enemy")
			fx_layer.add_child(flying)
			flying.position = source - flying.size / 2.0
			flying.pivot_offset = flying.size / 2.0
			flying.scale = Vector2.ONE * (DECK_SIZE.x / hand_size.x)
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

func _draw_pile_point(side: String) -> Vector2:
	var origin := PLAYER_DECK_POS if side == "player" else ENEMY_DECK_POS
	return origin + DECK_SIZE / 2.0

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

func _anchor(side: String) -> Vector2:
	return ENEMY_ANCHOR if side == "enemy" else PLAYER_ANCHOR

func _on_summon_event(side: String, slot: int, kind: String, element: String, amount: int) -> void:
	if fx_layer == null or not is_inside_tree():
		return
	var point := _summon_point(side, slot)
	match kind:
		"spawn": battle_fx.energy(point, element, true)
		"damage":
			battle_fx.impact(element, point)
			_show_floating("-%d" % amount, side, RED, 0.0, point + Vector2(-90, -45))
		"destroy": battle_fx.impact(element, point)

func _on_action_event(message: String, side: String, kind: String, element: String, amount: int) -> void:
	if fx_layer == null or not is_inside_tree():
		return
	if kind == "turn":
		_show_turn_notice("enemy" if manager.phase.begins_with("enemy") else "player")
		return
	if side not in ["player", "enemy"]:
		return
	var target := _anchor(side)
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
		# Numbers drift away from the HUD panel instead of over its own text.
		float_point = _energy_point(side, element) + Vector2(-90, 130 if side == "enemy" else -150)
	_show_floating(("-" if kind in ["damage", "energy_loss"] else "+") + str(amount), side, RED if kind == "damage" else BattleRules.color(element) if element != "" else GOLD, 0.0, float_point)
	if kind == "damage" and message.contains("克制"):
		_show_floating("克制", side, GOLD, 39.0)
	elif kind == "damage" and message.contains("抵抗"):
		_show_floating("抵抗", side, Color("#bde9ff"), 39.0)

func _energy_point(side: String, element: String) -> Vector2:
	var index := BattleRules.ELEMENTS.find(element)
	if index < 0:
		return _hud_origin(side) + HUD_SIZE / 2.0
	# Both HUDs keep 金木水火土 left to right, so the row is not mirrored.
	var local := Vector2(ORB_ROW_X + ORB_DIAMETER / 2.0 + float(index) * ORB_STEP, ORB_ROW_Y + ORB_DIAMETER / 2.0)
	return _hud_origin(side) + local

func _show_floating(value: String, side: String, color: Color, y_offset: float = 0.0, position_override: Vector2 = Vector2(-1, -1)) -> void:
	var floating := Label.new()
	floating.text = value
	floating.position = (position_override if position_override.x >= 0 else _anchor(side) + Vector2(-90, -25)) + Vector2(0, y_offset)
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
