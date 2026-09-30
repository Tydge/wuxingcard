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
const DAMAGE_NUMBER_SCRIPT := preload("res://ui/damage_number.gd")
const TARGET_MARKER_SCRIPT := preload("res://ui/target_marker.gd")
const STATUS_ICON_SCRIPT := preload("res://ui/status_icon.gd")
const CARD_REVEAL_SECONDS := 1.45
const EFFECT_PAUSE_SECONDS := 0.9
const DISCARD_SECONDS := 0.62
const DISCARD_LIFT := 110.0
const SUMMON_FEEDBACK_SECONDS := 1.1
const MAIN_MENU_SCRIPT := preload("res://ui/main_menu.gd")

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
const SUMMON_DROP_RADIUS_MOUSE := 100.0
const SUMMON_DROP_RADIUS_TOUCH := 120.0
const TOUCH_DRAG_ANGLE_TANGENT := 0.17 # Just under ten degrees from horizontal.
const TOUCH_HAND_COLLAPSE_SCALE := 0.82
const TOUCH_HAND_COLLAPSE_DROP := 76.0
const ENEMY_HERO_TARGET := Rect2(1180, 198, 345, 445)

var manager: BattleManager
var artifact_layer: Control
var actor_layer: Control
var fx_layer: Control
var battle_fx: BattleFX
var standee_nodes: Dictionary = {}
var summon_views: Dictionary = {}
var selected_index := -1
var hovered_index := -1
var menu_enemy := "ember"
var menu_deck := "balanced"
var menu_custom_deck: Dictionary = {}
var enemy_animating := false
var action_busy := false
var hand_cards: Array[Control] = []
var enemy_backs: Array[Control] = []
var discard_cards: Array[Control] = []
var hover_preview: Control
var hover_keywords: CardKeywordPopup
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
var touch_finger := -1
var touch_hand_index := -1
var touch_hand_card_id := ""
var touch_origin := Vector2.ZERO
var touch_inspecting := false
var touch_block_mouse := false
var touch_drag_rejected := false
var touch_warning_shown := false
var touch_hand_collapsed := false
var touch_shade: ColorRect
var touch_returning_preview: Control
var status_touch_regions: Array[Dictionary] = []
var energy_touch_regions: Array[Dictionary] = []
var information_panel: BattleInfoPanel
var back_dialog: Control
var artifact_aiming := false
var hovered_artifact_slot := ""
var artifact_preview_button: Button
var choice_dialog: ContemplationDialog

func _ready() -> void:
	if OS.has_feature("android"):
		get_tree().auto_accept_quit = false
		Engine.max_fps = 60
		get_viewport().size_changed.connect(_fit_mobile_surface)
		_fit_mobile_surface()
	var custom_theme := Theme.new()
	custom_theme.default_font = GameFonts.body()
	custom_theme.default_font_size = 18
	theme = custom_theme
	manager = BattleManager.new()
	add_child(manager)
	manager.changed.connect(_refresh)
	manager.interactive_choices = true
	manager.choice_requested.connect(_show_contemplation)
	manager.action_event.connect(_on_action_event)
	manager.hand_card_removed.connect(_on_hand_card_removed)
	manager.summon_event.connect(_on_summon_event)
	manager.summon_triggered.connect(_on_summon_triggered)
	artifact_layer = Control.new()
	artifact_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artifact_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(artifact_layer)
	actor_layer = Control.new()
	actor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(actor_layer)
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fx_layer)
	battle_fx = BattleFX.new()
	battle_fx.set_anchors(PLAYER_ANCHOR, ENEMY_ANCHOR)
	fx_layer.add_child(battle_fx)
	manager.summon_presenter = _present_summon_effect
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
	b.pressed.connect(func(): GameAudio.play_sfx("ui_select", 0.0, 70))
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _fit_mobile_surface() -> void:
	var available := get_viewport_rect()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and safe.size.y > 0:
		var inverse := get_viewport().get_screen_transform().affine_inverse()
		available = available.intersection(Rect2(inverse * Vector2(safe.position), inverse.basis_xform(Vector2(safe.size))))
	var fitted := PlatformUI.fit_design(available, VIEW_SIZE)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = fitted.position
	size = VIEW_SIZE
	scale = Vector2.ONE * fitted.size.x / VIEW_SIZE.x

func _refresh() -> void:
	if not is_inside_tree():
		return
	GameAudio.set_context("menu" if manager.phase == "menu" else "battle")
	var keep_touch_card := PlatformUI.is_touch() and touch_finger >= 0 and touch_hand_index >= 0 and touch_hand_index < manager.player.hand.size() and touch_inspecting and manager.phase != "menu" and manager.phase not in BattleManager.FINISHED_PHASES and manager.player.hand[touch_hand_index] == touch_hand_card_id
	if not keep_touch_card: _clear_hover_preview()
	status_touch_regions.clear()
	energy_touch_regions.clear()
	if not keep_touch_card:
		touch_finger = -1
		touch_hand_index = -1
	touch_drag_rejected = false
	touch_warning_shown = false
	for child in get_children():
		if child != manager and child != artifact_layer and child != actor_layer and child != fx_layer:
			if child is CanvasItem: child.hide()
			child.queue_free()
	for child in artifact_layer.get_children():
		child.queue_free()
	if manager.phase == "menu":
		_clear_discard_animations()
		hand_cards.clear()
		enemy_backs.clear()
		_clear_actors()
		_build_menu()
		move_child(fx_layer, get_child_count() - 1)
		return
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
	move_child(artifact_layer, 2 if texture != null else 1)
	move_child(actor_layer, 3 if texture != null else 2)
	_build_battle()
	if keep_touch_card:
		hand_cards[touch_hand_index].hide()
		var preview_target := _touch_preview_target(touch_hand_index)
		if is_instance_valid(hover_preview):
			hover_preview.create_tween().tween_property(hover_preview, "position", preview_target, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if is_instance_valid(hover_keywords):
			hover_keywords.card_rect = Rect2(preview_target, Vector2(340, 476))
			hover_keywords.call_deferred("_place")
	move_child(fx_layer, get_child_count() - 1)

func _build_menu() -> void:
	var screen := MAIN_MENU_SCRIPT.new()
	screen.configure(manager.cards, _card_front, manager.summon_templates)
	screen.test_requested.connect(_start_test_battle)
	add_child(screen)

func _start_test_battle(deck: Dictionary = {}) -> void:
	if not deck.is_empty() and not DeckStore.new(manager.cards).problem(deck.get("cards", [])).is_empty(): return
	var random := RandomNumberGenerator.new()
	random.randomize()
	menu_enemy = manager.enemies[random.randi_range(0, manager.enemies.size() - 1)]["id"]
	menu_deck = "random"
	menu_custom_deck = deck.duplicate(true)
	_start_battle()

func _start_battle() -> void:
	_clear_contemplation()
	touch_hand_collapsed = false
	_clear_discard_animations()
	if is_instance_valid(information_panel): information_panel.dismiss()
	_clear_actors()
	enemy_animating = false
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
	await manager.start_battle(menu_enemy, menu_deck, -1, menu_custom_deck)

func _build_battle() -> void:
	_build_standees()
	_build_summons()
	_build_enemy_hand()
	_build_combatant_hud("enemy")
	_build_combatant_hud("player")
	_build_decks()
	_build_hand()
	_build_artifacts()
	_build_end_turn()
	_button(self, "规则", Rect2(680, 25, 112, 58), _open_rules)
	_button(self, "记录", Rect2(810, 25, 112, 58), _open_journal)
	if not draw_animation_active and (pending_player_draws > 0 or pending_enemy_draws > 0):
		var player_count := pending_player_draws
		var enemy_count := pending_enemy_draws
		draw_animation_active = true
		call_deferred("_animate_pending_draws", player_count, enemy_count, draw_generation)
	if manager.phase in BattleManager.FINISHED_PHASES:
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
	var subtitle := _label(panel, _side_subtitle(side), name_rect.position + Vector2(0 if enemy_side else 150, 0), Vector2(206, name_rect.size.y), 16, GOLD.darkened(0.1), tag_align)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var counts := _hud_local(side, HUD_COUNTS)
	_label(panel, "手牌 %d    牌库 %d    弃牌 %d" % [actor.hand.size(), actor.draw_pile.size(), actor.discard_pile.size()],
		counts.position, counts.size, 15, MUTED, align)

	_hp_bar(panel, _hud_local(side, HUD_HP), actor)

	# The orb row is laid out identically on both sides so 金水木火土 always read
	# left to right; only the surrounding text mirrors.
	for i in BattleRules.ELEMENTS.size():
		_energy_orb(panel, actor, side, i)
	_build_status_icons(actor, side)

func _side_subtitle(side: String) -> String:
	if manager.selected_deck_id.begins_with("custom:"):
		return "随机牌组" if side == "enemy" else manager.selected_deck_name
	if manager.selected_deck_id == "random": return "随机牌组"
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
	# sides read 金水木火土 left to right; only the surrounding text mirrors.
	var local := Rect2(Vector2(ORB_ROW_X + float(index) * ORB_STEP, ORB_ROW_Y), Vector2(ORB_DIAMETER, ORB_DIAMETER))
	var orb := EnergyOrb.new()
	orb.position = local.position
	orb.size = local.size
	orb.add_theme_stylebox_override("panel", _box(Color("#0c1826").lerp(tint, 0.14), tint.darkened(0.1), int(ORB_DIAMETER / 2.0), 2))
	orb.tooltip_text = BattleRules.energy_tooltip(actor, element)
	orb.mouse_filter = Control.MOUSE_FILTER_STOP
	orb.mouse_default_cursor_shape = Control.CURSOR_HELP
	parent.add_child(orb)
	energy_touch_regions.append({"rect": _hud_global_rect(side, local), "text": orb.tooltip_text})
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
		if PlatformUI.is_touch():
			icon.scale = Vector2.ONE * 1.15
			icon.position.x = origin.x + (12.0 + column * 54.0 if side == "player" else HUD_SIZE.x - 12.0 - 50.6 - column * 54.0)
			status_touch_regions.append({"rect": Rect2(icon.position, STATUS_ICON_SIZE * 1.15).grow(3), "text": manager.status_tooltip(status)})
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

func _clear_actors() -> void:
	standee_nodes.clear()
	summon_views.clear()
	artifact_aiming = false
	for child in actor_layer.get_children():
		child.queue_free()
		actor_layer.remove_child(child)

func _build_standees() -> void:
	if not standee_nodes.is_empty():
		return
	standee_nodes["player"] = _standee("player", STANDEE_MARGIN, false, 2.4)
	standee_nodes["enemy"] = _standee(manager.enemy.id, VIEW_SIZE.x - STANDEE_MARGIN - STANDEE_SIZE.x, MIRROR_ENEMY_STANDEE, 2.0)
	for side in ["player", "enemy"]:
		var owner: Combatant = manager.player if side == "player" else manager.enemy
		var id := str(owner.artifacts.get("implement", ""))
		if id.is_empty(): continue
		var path := "res://assets/artifacts/%s_standee.webp" % manager.artifacts.get(id, {}).get("art_id", id)
		if not ResourceLoader.exists(path): continue
		var weapon := TextureRect.new()
		weapon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		weapon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		weapon.texture = load(path)
		weapon.flip_h = side == "enemy"
		actor_layer.add_child(weapon)
		weapon.position = Vector2(14 if side == "player" else 1486, 200)
		weapon.size = Vector2(100, 205)
		var float_tween := weapon.create_tween().set_loops()
		float_tween.tween_property(weapon, "position:y", 191.0, 2.0).set_trans(Tween.TRANS_SINE)
		float_tween.tween_property(weapon, "position:y", 200.0, 2.0).set_trans(Tween.TRANS_SINE)

func _build_artifacts() -> void:
	for side in ["player", "enemy"]:
		var owner: Combatant = manager.player if side == "player" else manager.enemy
		var implement: Dictionary = manager.artifact_entry(owner, "implement")
		if not implement.is_empty():
			var weapon_button := Button.new()
			weapon_button.flat = true
			weapon_button.position = Vector2(14 if side == "player" else 1486, 191)
			weapon_button.size = Vector2(100, 214)
			add_child(weapon_button)
			weapon_button.mouse_entered.connect(_show_artifact_preview.bind(side, "implement"))
			weapon_button.mouse_exited.connect(_hide_artifact_preview.bind(side, "implement"))
			weapon_button.pressed.connect(func():
				if side == "player": _on_artifact_pressed()
				else: _show_artifact_preview(side, "implement"))
		for i in ArtifactLibrary.SLOTS.size():
			var slot: String = ArtifactLibrary.SLOTS[i]
			var entry: Dictionary = manager.artifact_entry(owner, slot)
			var pos := Vector2(68, 423 + i * 78) if side == "player" else Vector2(1466, 423 + i * 78)
			var control := _panel(artifact_layer, Rect2(pos, Vector2(66, 66)), Color("#0d1d27dd"), BattleRules.color(str(entry.get("element", "metal"))) if not entry.is_empty() else Color("#686a66"), 33, 2)
			if not entry.is_empty():
				var icon := TextureRect.new()
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.texture = load("res://assets/artifacts/%s.webp" % entry.get("art_id", entry["id"]))
				control.add_child(icon)
				icon.position = Vector2(3, 3)
				icon.size = Vector2(60, 60)
				var circle := Shader.new()
				circle.code = "shader_type canvas_item; uniform float cooling = 0.0; void fragment() { vec4 art = texture(TEXTURE, UV); float edge = 1.0 - smoothstep(0.46, 0.5, distance(UV, vec2(0.5))); float gray = dot(art.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(mix(art.rgb, vec3(gray), cooling * 0.85) * (1.0 - cooling * 0.28), art.a * edge); }"
				var circle_material := ShaderMaterial.new()
				circle_material.shader = circle
				icon.material = circle_material
				if slot == "guard":
					var durability_badge := ArtifactBadge.new()
					control.add_child(durability_badge)
					durability_badge.configure("guard", owner.artifact_durability, BattleRules.color(str(entry["element"])), 27.0)
					durability_badge.position = Vector2(-7, -7)
				if slot == "implement" and owner.own_turn_count < owner.artifact_ready_turn:
					circle_material.set_shader_parameter("cooling", 1.0)
					var cool := _panel(control, Rect2(4, 4, 58, 58), Color("#10182087"), Color.TRANSPARENT, 29, 0)
					cool.mouse_filter = Control.MOUSE_FILTER_IGNORE
					_label(control, str(owner.artifact_ready_turn - owner.own_turn_count), Vector2.ZERO, control.size, 35, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			var trigger := Button.new()
			trigger.flat = true
			trigger.position = Vector2.ZERO
			trigger.size = control.size
			trigger.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			control.add_child(trigger)
			if not entry.is_empty():
				trigger.mouse_entered.connect(_show_artifact_preview.bind(side, slot))
				trigger.mouse_exited.connect(_hide_artifact_preview.bind(side, slot))
				trigger.pressed.connect(func():
					if PlatformUI.is_touch(): _show_artifact_preview(side, slot)
					elif side == "player" and slot == "implement": _on_artifact_pressed())
			if side == "player" and slot == "implement" and not entry.is_empty() and manager.artifact_can_activate(owner) and not action_busy:
				control.self_modulate = Color("#fff7db")
	if artifact_aiming: _build_artifact_targets()

func _show_artifact_preview(side: String, slot: String) -> void:
	if manager.phase in BattleManager.FINISHED_PHASES: return
	var owner: Combatant = manager.player if side == "player" else manager.enemy
	var entry := manager.artifact_entry(owner, slot)
	if entry.is_empty() or hovered_artifact_slot == side + slot: return
	_clear_hover_preview()
	hovered_artifact_slot = side + slot
	if PlatformUI.is_touch(): touch_inspecting = true
	hover_preview = ArtifactView.new()
	hover_preview.configure(entry, Vector2(270, 378), owner.artifact_durability if slot == "guard" else maxi(0, owner.artifact_ready_turn - owner.own_turn_count) if slot == "implement" else -1)
	hover_preview.position = Vector2(222, 450) if side == "player" else Vector2(1108, 200)
	fx_layer.add_child(hover_preview)
	hover_preview.modulate.a = 0.0
	hover_preview.create_tween().tween_property(hover_preview, "modulate:a", 1.0, 0.14)
	if PlatformUI.is_touch() and side == "player" and slot == "implement" and manager.artifact_can_activate(owner):
		artifact_preview_button = _button(fx_layer, "发动", Rect2(hover_preview.position.x + 53, hover_preview.position.y + 384, 164, 58), _on_artifact_pressed)

func _hide_artifact_preview(side: String, slot: String) -> void:
	if PlatformUI.is_touch(): return
	if hovered_artifact_slot == side + slot: _clear_hover_preview()

func _on_artifact_pressed() -> void:
	if action_busy or not manager.artifact_can_activate(manager.player): return
	_clear_hover_preview()
	if manager.artifact_target_mode(manager.player) == "none":
		_activate_player_artifact({})
	else:
		artifact_aiming = true
		_refresh()

func _build_artifact_targets() -> void:
	var mode := manager.artifact_target_mode(manager.player)
	var side := "player" if mode == "self_or_ally_summon" else "enemy"
	var owner: Combatant = manager.player if side == "player" else manager.enemy
	var choices: Array[Dictionary] = [{"kind": "hero", "side": side}]
	for slot in owner.summons.size():
		if owner.summons[slot] != null: choices.append({"kind": "summon", "side": side, "slot": slot})
	for selection in choices:
		if not manager.valid_artifact_target(manager.player, selection): continue
		var point := _target_point(side, selection)
		var marker := _button(self, "◎", Rect2(point - Vector2(31, 31), Vector2(62, 62)), _activate_player_artifact.bind(selection), Color("#233439b9"), GOLD)
		marker.add_theme_font_size_override("font_size", 32)
	_button(self, "取消发动", Rect2(735, 799, 150, 60), func(): artifact_aiming = false; _refresh())

func _activate_player_artifact(selection: Dictionary) -> void:
	if not manager.artifact_can_activate(manager.player): return
	var entry := manager.artifact_entry(manager.player, "implement")
	var target := _artifact_cast_target(manager.player, selection)
	battle_fx.cast({"element": entry["element"], "effects": manager.artifact_effects(manager.player)}, "player", Vector2(80, 500), target)
	artifact_aiming = false
	manager.activate_artifact(manager.player, selection)

func _artifact_cast_target(actor: Combatant, selection: Dictionary) -> Vector2:
	var own_side := "player" if actor == manager.player else "enemy"
	var other_side := "enemy" if own_side == "player" else "player"
	if not selection.is_empty(): return _target_point(other_side, selection)
	for effect: Dictionary in manager.artifact_effects(actor):
		if effect.get("type") == "damage" and effect.get("target") == "opponent": return _anchor(other_side)
	return _anchor(own_side)

func _show_contemplation(candidates: Array, full: bool) -> void:
	_clear_contemplation()
	_clear_hover_preview()
	var generation := manager.battle_generation
	choice_dialog = ContemplationDialog.new()
	fx_layer.add_child(choice_dialog)
	choice_dialog.configure(candidates, manager.cards, _card_front, full)
	choice_dialog.confirmed.connect(func(index: int):
		_clear_contemplation()
		if generation == manager.battle_generation: manager.choose_card(index))

func _clear_contemplation() -> void:
	if is_instance_valid(choice_dialog): choice_dialog.queue_free()
	choice_dialog = null

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
			var key := "%s_%d" % [side, slot]
			var summoned: Summon = owner.summons[slot]
			var existing: SummonView = summon_views.get(key)
			if summoned == null:
				if is_instance_valid(existing):
					existing.queue_free()
					summon_views.erase(key)
				continue
			if is_instance_valid(existing) and existing.summon_ref == summoned:
				existing.refresh_health()
				continue
			if is_instance_valid(existing):
				existing.queue_free()
			var view: SummonView = SUMMON_VIEW_SCENE.instantiate()
			view.configure(summoned, side == "enemy")
			view.position = _summon_slot_rect(side, slot).position
			view.set_meta("rest_x", view.position.x)
			view.mouse_entered.connect(_on_summon_hover.bind(side, slot))
			view.mouse_exited.connect(_on_summon_exit.bind(side, slot))
			actor_layer.add_child(view)
			view.set_health_foreground(drag_index >= 0 and PlatformUI.is_touch())
			summon_views[key] = view

func _standee(actor_id: String, x: float, mirrored: bool, bob_seconds: float) -> Control:
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
		actor_layer.add_child(actor)
		actor.set_meta("rest_x", actor.position.x)
		var tween := actor.create_tween().set_loops()
		tween.tween_property(actor, "position:y", STANDEE_TOP - 6.0, bob_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(actor, "position:y", STANDEE_TOP, bob_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return actor
	else:
		var glyph := "火" if actor_id == "ember" else "水" if actor_id == "tide" else "行" if actor_id == "harmony" else "云"
		var box := _panel(actor_layer, Rect2(x + 60.0, STANDEE_TOP + 110.0, 180, 180), Color("#17304a99"), RED.darkened(0.2), 90)
		_label(box, glyph, Vector2.ZERO, Vector2(180, 180), 96, RED if actor_id != "player" else Color("#95d9da"), HORIZONTAL_ALIGNMENT_CENTER)
		box.set_meta("rest_x", box.position.x)
		return box

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
		if PlatformUI.is_touch() and touch_hand_collapsed:
			view.position.y += TOUCH_HAND_COLLAPSE_DROP
			view.scale = Vector2.ONE * TOUCH_HAND_COLLAPSE_SCALE
		view.modulate = Color.WHITE if manager.player.can_pay(card) else Color(0.68, 0.73, 0.78)
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		view.mouse_entered.connect(_on_hand_hover.bind(i))
		view.mouse_exited.connect(_on_hand_exit.bind(i))
		view.gui_input.connect(_on_hand_input.bind(i))
		add_child(view)
		view.call("set_condition_highlight", manager.player.can_pay(card) and manager.card_condition_met(manager.player, card))
		hand_cards.append(view)
		if view.position != target_position and not touch_hand_collapsed:
			view.create_tween().tween_property(view, "position", target_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i >= count - pending_player_draws or i == player_hidden_index:
			view.visible = false

func _hand_card_position(index: int, count: int) -> Vector2:
	return _fan_card_position(index, count, PLAYER_HAND_BASE_Y - (30.0 if PlatformUI.is_touch() else 0.0))

func _fan_card_position(index: int, count: int, base_y: float) -> Vector2:
	var width := HAND_CARD_SIZE.x
	# Keep the outer cards between the player HUD and the end-turn button.
	# Additional cards overlap instead of shrinking.
	var step := minf(width - 2.0, HAND_MAX_SPAN / maxf(1.0, float(count - 1)))
	var offset := float(index) - float(count - 1) / 2.0
	var half := maxf(1.0, float(count - 1) / 2.0)
	var arc := minf(54.0, 6.0 * half * half) * pow(offset / half, 2.0)
	return Vector2(HAND_CENTER_X + offset * step - width / 2.0, base_y + arc)

func _hand_angle(index: int, count: int) -> float:
	return (float(index) - float(count - 1) / 2.0) * minf(3.8, 22.8 / maxf(1.0, float(count - 1)))

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
	if PlatformUI.is_touch() or manager.phase in BattleManager.FINISHED_PHASES or drag_index >= 0 or index >= hand_cards.size():
		return
	hovered_index = index
	GameAudio.play_sfx("card_focus", 0.0, 180)
	var view := hand_cards[index]
	view.position.y -= 28
	view.rotation_degrees = 0
	move_child(view, get_child_count() - 2)
	_show_hover_preview(index)

func _on_hand_exit(index: int) -> void:
	if PlatformUI.is_touch() or hovered_index != index or drag_index >= 0:
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
	_show_hover_keywords(card)

func _on_summon_hover(side: String, slot: int) -> void:
	if PlatformUI.is_touch(): return
	_show_summon_preview(side, slot)

func _show_summon_preview(side: String, slot: int) -> bool:
	if manager.phase in BattleManager.FINISHED_PHASES or drag_index >= 0 or action_busy or enemy_animating:
		return false
	if side not in ["player", "enemy"]: return false
	var owner: Combatant = manager.player if side == "player" else manager.enemy
	if slot < 0 or slot >= owner.summons.size(): return false
	var summoned: Summon = owner.summons[slot]
	if summoned == null or not manager.cards.has(summoned.card_id):
		return false
	_clear_hover_preview()
	hovered_summon_side = side
	hovered_summon_slot = slot
	var card: Dictionary = manager.cards[summoned.card_id]
	hover_preview = _card_front(card, Vector2(270, 378))
	var slot_rect := _summon_slot_rect(side, slot)
	var preview_x := slot_rect.end.x + 18.0 if side == "player" else slot_rect.position.x - 288.0
	hover_preview.position = Vector2(clampf(preview_x, 8.0, VIEW_SIZE.x - 278.0), clampf(slot_rect.get_center().y - 189.0, 145.0, 480.0))
	fx_layer.add_child(hover_preview)
	hover_preview.modulate.a = 0.0
	hover_preview.create_tween().tween_property(hover_preview, "modulate:a", 1.0, 0.13)
	_show_hover_keywords(card)
	return true

func _on_summon_exit(side: String, slot: int) -> void:
	if PlatformUI.is_touch(): return
	if hovered_summon_side == side and hovered_summon_slot == slot:
		_clear_hover_preview()

func _show_hover_keywords(card: Dictionary, display_rect: Rect2 = Rect2()) -> void:
	var entries := CardKeywords.entries(card, manager.summon_templates)
	if entries.is_empty(): return
	hover_keywords = CardKeywordPopup.new()
	fx_layer.add_child(hover_keywords)
	hover_keywords.configure(entries, display_rect if display_rect.size != Vector2.ZERO else Rect2(hover_preview.position, hover_preview.size), VIEW_SIZE)

func _clear_hover_preview() -> void:
	hovered_artifact_slot = ""
	if is_instance_valid(artifact_preview_button): artifact_preview_button.queue_free()
	artifact_preview_button = null
	if is_instance_valid(touch_returning_preview):
		touch_returning_preview.hide()
		touch_returning_preview.queue_free()
	touch_returning_preview = null
	touch_inspecting = false
	touch_hand_card_id = ""
	if touch_hand_index >= 0 and touch_hand_index < hand_cards.size() and is_instance_valid(hand_cards[touch_hand_index]):
		hand_cards[touch_hand_index].show()
	if is_instance_valid(touch_shade): touch_shade.queue_free()
	touch_shade = null
	if is_instance_valid(hover_keywords):
		hover_keywords.hide()
		hover_keywords.queue_free()
	hover_keywords = null
	if is_instance_valid(hover_preview):
		hover_preview.queue_free()
	hover_preview = null
	hovered_summon_side = ""
	hovered_summon_slot = -1

func _on_hand_input(event: InputEvent, index: int) -> void:
	if PlatformUI.is_touch(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_hand_drag(index, get_local_mouse_position())

func _begin_hand_drag(index: int, pointer: Vector2) -> bool:
	if manager.phase != "player_action" or action_busy or index < 0 or index >= manager.player.hand.size(): return false
	var card: Dictionary = manager.cards[manager.player.hand[index]]
	if not manager.player.can_pay(card):
		if not PlatformUI.is_touch() or not touch_warning_shown:
			var reason := "召唤位已满" if manager.card_target_mode(card) == "slot" and manager.player.first_free_summon_slot() < 0 else "灵气不足"
			GameAudio.play_sfx("ui_error", 0.0, 450)
			_show_floating(reason, "player", RED, 0, _hand_card_center(index, manager.player.hand.size()) + Vector2(-90, -120))
			touch_warning_shown = true
		return false
	drag_index = index
	pointer_down = pointer
	drag_offset = HAND_CARD_SIZE / 2.0 + (Vector2(0, 105) if PlatformUI.is_touch() else Vector2.ZERO)
	_clear_hover_preview()
	if PlatformUI.is_touch():
		_set_touch_hand_collapsed(true)
		for view in summon_views.values():
			if is_instance_valid(view): view.set_health_foreground(true)
	if index < hand_cards.size(): hand_cards[index].visible = false
	drag_card = _card_front(card, HAND_CARD_SIZE)
	drag_card.position = pointer - drag_offset
	_show_drag_hints(card)
	fx_layer.add_child(drag_card)
	return true

func _finish_hand_drag(release: Vector2) -> void:
	if drag_index < 0 or not is_instance_valid(drag_card): return
	var index := drag_index
	var card: Dictionary = manager.cards[manager.player.hand[index]]
	var selection := _drop_selection(card, release)
	drag_index = -1
	if PlatformUI.is_touch():
		_set_touch_hand_collapsed(false)
		for view in summon_views.values():
			if is_instance_valid(view): view.set_health_foreground(false)
	drag_card.queue_free()
	drag_card = null
	_clear_drag_hints()
	var moved := PlatformUI.is_touch() or release.distance_to(pointer_down) > 45
	var released_in_hand := PlatformUI.is_touch() and release.y >= 690 and release.x >= 490 and release.x <= 1260
	if moved and not released_in_hand and manager.valid_card_target(manager.player, card, selection) and selection.get("kind", "") != "invalid":
		_play_card_from(index, release, selection)
	else:
		_refresh()

func _touch_hand_at(point: Vector2, sliding: bool = false) -> int:
	var low_edge := 745.0 if touch_hand_collapsed else (610.0 if sliding else 640.0)
	if hand_cards.is_empty() or point.x < 490 or point.x > 1260 or point.y < low_edge: return -1
	var closest := -1
	var distance := INF
	for i in hand_cards.size():
		if not is_instance_valid(hand_cards[i]) or (not hand_cards[i].visible and (i != touch_hand_index or touch_finger < 0)): continue
		var center := _hand_card_center(i, hand_cards.size())
		var delta := absf(point.x - center.x)
		if delta < distance:
			closest = i
			distance = delta
	if distance >= HAND_CARD_SIZE.x: return -1
	if sliding and touch_hand_index >= 0 and closest != touch_hand_index:
		var current_x := _hand_card_center(touch_hand_index, hand_cards.size()).x
		var candidate_x := _hand_card_center(closest, hand_cards.size()).x
		var midpoint := (current_x + candidate_x) / 2.0
		var margin := minf(18.0, absf(candidate_x - current_x) * 0.2)
		if (candidate_x > current_x and point.x < midpoint + margin) or (candidate_x < current_x and point.x > midpoint - margin):
			return touch_hand_index
	return closest

func _set_touch_hand_collapsed(value: bool) -> void:
	if not PlatformUI.is_touch() or touch_hand_collapsed == value: return
	touch_hand_collapsed = value
	for i in hand_cards.size():
		var view := hand_cards[i]
		if not is_instance_valid(view): continue
		var target := _hand_card_position(i, hand_cards.size())
		if value: target.y += TOUCH_HAND_COLLAPSE_DROP
		var tween := view.create_tween().set_parallel(true)
		tween.tween_property(view, "position", target, 0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(view, "scale", Vector2.ONE * (TOUCH_HAND_COLLAPSE_SCALE if value else 1.0), 0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _show_touch_card(index: int) -> void:
	if touch_hand_index == index and touch_inspecting: return
	GameAudio.play_sfx("card_focus", 0.0, 155)
	_clear_hover_preview()
	touch_hand_index = index
	if index < 0 or index >= manager.player.hand.size(): return
	touch_hand_card_id = manager.player.hand[index]
	var card: Dictionary = manager.cards[manager.player.hand[index]]
	var center := _hand_card_center(index, manager.player.hand.size())
	var target := _touch_preview_target(index)
	hover_preview = _card_front(card, Vector2(340, 476))
	hover_preview.pivot_offset = Vector2(170, 238)
	hover_preview.position = Vector2(center.x - 170.0, center.y - 238.0)
	hover_preview.scale = Vector2.ONE * (HAND_CARD_SIZE.x / 340.0)
	fx_layer.add_child(hover_preview)
	hand_cards[index].hide()
	var tween := hover_preview.create_tween().set_parallel(true)
	tween.tween_property(hover_preview, "position", target, 0.19).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(hover_preview, "scale", Vector2.ONE, 0.19).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	touch_inspecting = true
	_show_hover_keywords(card, Rect2(target, Vector2(340, 476)))

func _touch_preview_target(index: int) -> Vector2:
	return Vector2(clampf(_hand_card_center(index, manager.player.hand.size()).x - 170.0, 380.0, 1060.0), 220.0)

func _release_touch_card() -> void:
	if touch_hand_index < 0:
		_clear_hover_preview()
		return
	var index := touch_hand_index
	var preview := hover_preview
	var source: Control = hand_cards[index] if index < hand_cards.size() else null
	var center := _hand_card_center(index, manager.player.hand.size())
	if is_instance_valid(hover_keywords):
		hover_keywords.hide()
		hover_keywords.queue_free()
	hover_keywords = null
	hover_preview = null
	touch_hand_index = -1
	touch_hand_card_id = ""
	touch_inspecting = false
	if not is_instance_valid(preview): return
	if is_instance_valid(source): source.show()
	touch_returning_preview = preview
	var tween := preview.create_tween().set_parallel(true)
	tween.tween_property(preview, "position", Vector2(center.x - 170, center.y - 238), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(preview, "scale", Vector2.ONE * (HAND_CARD_SIZE.x / 340.0), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(preview.queue_free)

func _place_touch_preview() -> void:
	# A large stationary inspection card stays clear of the finger and the hand.
	if not is_instance_valid(hover_preview): return
	var card_data: Dictionary
	if touch_hand_index >= 0:
		if touch_hand_index >= manager.player.hand.size():
			_clear_hover_preview()
			return
		card_data = manager.cards[manager.player.hand[touch_hand_index]]
	else:
		if hovered_summon_side not in ["player", "enemy"]:
			_clear_hover_preview()
			return
		var owner: Combatant = manager.player if hovered_summon_side == "player" else manager.enemy
		if hovered_summon_slot < 0 or hovered_summon_slot >= owner.summons.size() or owner.summons[hovered_summon_slot] == null:
			_clear_hover_preview()
			return
		card_data = manager.cards[owner.summons[hovered_summon_slot].card_id]
	if is_instance_valid(hover_keywords): hover_keywords.queue_free()
	hover_keywords = null
	hover_preview.queue_free()
	touch_shade = ColorRect.new()
	touch_shade.color = Color("#03101b8c")
	touch_shade.size = VIEW_SIZE
	touch_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(touch_shade)
	hover_preview = _card_front(card_data, Vector2(400, 560))
	hover_preview.position = Vector2(600, 90)
	fx_layer.add_child(hover_preview)
	hover_preview.modulate.a = 0.0
	hover_preview.create_tween().tween_property(hover_preview, "modulate:a", 1.0, 0.13)
	touch_inspecting = true
	_show_hover_keywords(card_data)

func _touch_hits_artifact(point: Vector2) -> bool:
	for side in ["player", "enemy"]:
		var owner: Combatant = manager.player if side == "player" else manager.enemy
		if not manager.artifact_entry(owner, "implement").is_empty() and Rect2(Vector2(14 if side == "player" else 1486, 191), Vector2(100, 214)).has_point(point):
			return true
		for i in ArtifactLibrary.SLOTS.size():
			var slot: String = ArtifactLibrary.SLOTS[i]
			if manager.artifact_entry(owner, slot).is_empty(): continue
			var pos := Vector2(68, 423 + i * 78) if side == "player" else Vector2(1466, 423 + i * 78)
			if Rect2(pos, Vector2(66, 66)).has_point(point): return true
	return false

func _handle_touch(event: InputEvent) -> void:
	if event is not InputEventScreenTouch and event is not InputEventScreenDrag: return
	if manager.phase in BattleManager.FINISHED_PHASES or is_instance_valid(information_panel): return
	var point := PlatformUI.local_point(self, event.position)
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_finger >= 0:
				get_viewport().set_input_as_handled()
				return
			if is_instance_valid(back_dialog): return
			if artifact_aiming:
				var mode := manager.artifact_target_mode(manager.player)
				var side := "player" if mode == "self_or_ally_summon" else "enemy"
				var owner := manager.player if side == "player" else manager.enemy
				var targets: Array[Dictionary] = [{"kind": "hero", "side": side}]
				for slot in owner.summons.size():
					if owner.summons[slot] != null: targets.append({"kind": "summon", "side": side, "slot": slot})
				for target in targets:
					if manager.valid_artifact_target(manager.player, target) and point.distance_to(_target_point(side, target)) < 80.0:
						_activate_player_artifact(target)
						get_viewport().set_input_as_handled()
						return
				artifact_aiming = false
				_refresh()
				get_viewport().set_input_as_handled()
				return
			var index := _touch_hand_at(point)
			if index >= 0:
				if touch_hand_collapsed:
					_set_touch_hand_collapsed(false)
					get_viewport().set_input_as_handled()
					return
				touch_finger = event.index
				touch_origin = point
				touch_drag_rejected = false
				touch_warning_shown = false
				_show_touch_card(index)
				get_viewport().set_input_as_handled()
				return
			# Inspection is modal until an outside tap; that tap does not play a card.
			if touch_inspecting:
				# Mouse-enter can open an artifact preview before the touch press arrives.
				# Keep it open when that same press lands on the artifact control.
				if _touch_hits_artifact(point): return
				if not Rect2(hover_preview.position, hover_preview.size).has_point(point): _clear_hover_preview()
				get_viewport().set_input_as_handled()
				return
			for entry in energy_touch_regions + status_touch_regions:
				if entry.rect.has_point(point):
					_show_touch_status(entry.text)
					get_viewport().set_input_as_handled()
					return
			for side in ["player", "enemy"]:
				var owner := manager.player if side == "player" else manager.enemy
				for slot in owner.summons.size():
					if owner.summons[slot] != null and point.distance_to(_summon_point(side, slot)) < SUMMON_TARGET_RADIUS:
						if _show_summon_preview(side, slot):
							touch_hand_index = -1
							_place_touch_preview()
						get_viewport().set_input_as_handled()
						return
			if point.x > 470 and point.x < 1270 and point.y > 180 and point.y < 640:
				_set_touch_hand_collapsed(true)
				get_viewport().set_input_as_handled()
				return
		elif event.index == touch_finger:
			touch_finger = -1
			if event.canceled:
				if drag_index >= 0: _finish_hand_drag(Vector2(880, 850))
				_clear_hover_preview()
			elif drag_index >= 0:
				_finish_hand_drag(point)
			elif touch_hand_index >= 0:
				_release_touch_card()
			get_viewport().set_input_as_handled()
	elif event.index == touch_finger:
		if drag_index >= 0:
			drag_card.position = point - drag_offset
			_update_drag_hints(manager.cards[manager.player.hand[drag_index]], point)
		elif touch_hand_index >= 0:
			var travel := point - touch_origin
			if not touch_drag_rejected and travel.y < -10.0 and travel.length() > 24.0 and -travel.y > absf(travel.x) * TOUCH_DRAG_ANGLE_TANGENT:
				if _begin_hand_drag(touch_hand_index, point):
					drag_card.position = point - drag_offset
					_update_drag_hints(manager.cards[manager.player.hand[drag_index]], point)
				else:
					touch_drag_rejected = true
			else:
				var index := _touch_hand_at(point, true)
				if index >= 0 and index != touch_hand_index:
					_show_touch_card(index)
					touch_origin = point
					touch_drag_rejected = false
		get_viewport().set_input_as_handled()

func _show_touch_status(description: String) -> void:
	_clear_hover_preview()
	touch_hand_index = -1
	hover_preview = _panel(fx_layer, Rect2(525, 315, 550, 210), PANEL_DARK, GOLD)
	_label(hover_preview, description, Vector2(24, 18), Vector2(502, 140), 30)
	_label(hover_preview, "轻点空白处收起", Vector2(24, 164), Vector2(502, 32), 22, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	touch_inspecting = true

func _drop_selection(card: Dictionary, point: Vector2) -> Dictionary:
	match manager.card_target_mode(card):
		"slot":
			var nearest := -1
			var nearest_distance := INF
			var radius := SUMMON_DROP_RADIUS_TOUCH if PlatformUI.is_touch() else SUMMON_DROP_RADIUS_MOUSE
			for slot in manager.player.summons.size():
				if manager.player.summons[slot] == null:
					var distance := point.distance_to(_summon_point("player", slot))
					if distance <= radius and distance < nearest_distance:
						nearest = slot
						nearest_distance = distance
			if nearest >= 0: return {"kind": "slot", "slot": nearest}
		"damage":
			for side in manager.damage_target_sides(manager.player, card):
				var owner := manager.player if side == "player" else manager.enemy
				for slot in owner.summons.size():
					if owner.summons[slot] != null and point.distance_to(_summon_point(side, slot)) <= SUMMON_TARGET_RADIUS:
						return {"kind": "summon", "slot": slot, "side": side}
				var hero_rect := ENEMY_HERO_TARGET
				if side == "player": hero_rect.position.x = VIEW_SIZE.x - hero_rect.end.x
				if hero_rect.has_point(point): return {"kind": "hero", "side": side}
		"ally_summon", "enemy_summons":
			var side := "player" if manager.card_target_mode(card) == "ally_summon" else "enemy"
			var owner := manager.player if side == "player" else manager.enemy
			for slot in owner.summons.size():
				if owner.summons[slot] != null and point.distance_to(_summon_point(side, slot)) <= SUMMON_TARGET_RADIUS:
					return {"kind": "summon", "slot": slot, "side": side}
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
		for side in manager.damage_target_sides(manager.player, card):
			var owner := manager.player if side == "player" else manager.enemy
			choices.append({"selection": {"kind": "hero", "side": side}, "point": _anchor(side)})
			for slot in owner.summons.size():
				if owner.summons[slot] != null:
					choices.append({"selection": {"kind": "summon", "slot": slot, "side": side}, "point": _summon_point(side, slot)})
	elif mode in ["ally_summon", "enemy_summons"]:
		var side := "player" if mode == "ally_summon" else "enemy"
		var owner := manager.player if side == "player" else manager.enemy
		for slot in owner.summons.size():
			if owner.summons[slot] != null:
				choices.append({"selection": {"kind": "summon", "slot": slot, "side": side}, "point": _summon_point(side, slot)})
	for choice in choices:
		var marker := TARGET_MARKER_SCRIPT.new()
		marker.configure(mode == "slot")
		var point: Vector2 = choice["point"]
		marker.position = point - marker.size / 2.0
		marker.set_meta("selection", choice["selection"])
		fx_layer.add_child(marker)
		drag_hints.append(marker)
	if mode == "damage":
		damage_preview = _panel(fx_layer, Rect2(Vector2.ZERO, Vector2(200, 58 if PlatformUI.is_touch() else 42)), Color("#09121ff2"), GOLD, 8)
		damage_preview.z_index = 20
		damage_preview.visible = false
		damage_preview_label = _label(damage_preview, "", Vector2(8, 0), Vector2(184, 58 if PlatformUI.is_touch() else 42), 32 if PlatformUI.is_touch() else 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER)

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
		var all_targets := false
		for effect in card["effects"]:
			if effect.get("scope", "single") in ["all_opponents", "all", "all_enemy_summons"]: all_targets = true
		hint.call("set_highlighted", selected == selection or (all_targets and manager.valid_card_target(manager.player, card, selection)))
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
	var width := clampf(44.0 + caption.length() * (22.0 if PlatformUI.is_touch() else 12.0), 180.0, 520.0)
	var height := 58.0 if PlatformUI.is_touch() else 42.0
	damage_preview.size = Vector2(width, height)
	damage_preview_label.text = caption
	damage_preview_label.size = Vector2(width - 16.0, height)
	var preview_x := pointer.x + HAND_CARD_SIZE.x / 2.0 + 20.0
	if preview_x + width > VIEW_SIZE.x - 8.0:
		preview_x = pointer.x - HAND_CARD_SIZE.x / 2.0 - width - 20.0
	damage_preview.position = Vector2(clampf(preview_x, 8.0, VIEW_SIZE.x - width - 8.0), clampf(pointer.y - (165.0 if PlatformUI.is_touch() else 21.0), 8.0, VIEW_SIZE.y - 50.0))
	damage_preview.visible = true

func _input(event: InputEvent) -> void:
	if not manager.pending_choice.is_empty(): return
	if PlatformUI.is_touch():
		# Android may synthesize mouse events after a handled touch. Consume those
		# too, so dismissing an inspection cannot also click End Turn underneath.
		if event.device == InputEvent.DEVICE_ID_EMULATION and touch_block_mouse:
			get_viewport().set_input_as_handled()
			if event is InputEventMouseButton and not event.pressed: touch_block_mouse = false
			return
		if event is InputEventScreenTouch and event.pressed: touch_block_mouse = false
		if manager.phase != "menu":
			_handle_touch(event)
			if event is InputEventScreenTouch and event.pressed and get_viewport().is_input_handled(): touch_block_mouse = true
		return
	if drag_index < 0 or not is_instance_valid(drag_card): return
	if event is InputEventMouseMotion:
		var pointer := get_local_mouse_position()
		drag_card.position = pointer - drag_offset
		drag_card.rotation_degrees = 0
		if drag_index < manager.player.hand.size(): _update_drag_hints(manager.cards[manager.player.hand[drag_index]], pointer)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_hand_drag(get_local_mouse_position())
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _request_back()

func _unhandled_input(event: InputEvent) -> void:
	if manager != null and manager.phase != "menu" and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()

func _request_back() -> void:
	if manager == null: return
	if not manager.pending_choice.is_empty(): return
	if is_instance_valid(information_panel):
		information_panel.dismiss()
		return
	if manager.phase == "menu":
		for child in get_children():
			if child is MainMenu: child.go_back()
		return
	if touch_inspecting:
		_clear_hover_preview()
		return
	if drag_index >= 0:
		touch_finger = -1
		_finish_hand_drag(Vector2(880, 850))
		return
	if is_instance_valid(back_dialog):
		back_dialog.queue_free()
		back_dialog = null
		return
	back_dialog = Control.new()
	back_dialog.size = VIEW_SIZE
	back_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	fx_layer.add_child(back_dialog)
	var shade := ColorRect.new()
	shade.size = VIEW_SIZE
	shade.color = Color("#03101bdc")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_dialog.add_child(shade)
	var panel := _panel(back_dialog, Rect2(520, 315, 560, 260), PANEL_DARK, GOLD)
	_label(panel, "返回山门？", Vector2(30, 28), Vector2(500, 65), 36, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_button(panel, "声音", Rect2(449, 14, 92, 45), _open_audio_settings)
	_button(panel, "继续对战", Rect2(38, 155, 216, 70), func(): back_dialog.queue_free(); back_dialog = null)
	_button(panel, "返回山门", Rect2(306, 155, 216, 70), func():
		back_dialog.queue_free()
		back_dialog = null
		manager.battle_generation += 1
		manager.phase = "menu"
		draw_generation += 1
		action_busy = false
		_clear_drag_hints()
		battle_fx.clear_effects()
		_refresh())

func _open_audio_settings() -> void:
	var settings := AudioSettings.new()
	fx_layer.add_child(settings)

func _target_point(side: String, selection: Dictionary) -> Vector2:
	side = str(selection.get("side", side))
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
	var generation := manager.battle_generation
	action_busy = true
	player_hidden_index = card_index
	_clear_hover_preview()
	_refresh()
	await _present_card(card, "player", source)
	if generation != manager.battle_generation: return
	if manager.phase == "player_action" and card_index < manager.player.hand.size():
		var mode := manager.card_target_mode(card)
		var destination := _target_point("player" if mode == "slot" else "enemy", selection) if mode != "none" else Vector2(-1, -1)
		await get_tree().create_timer(_cast_card(card, "player", destination)).timeout
		if generation != manager.battle_generation: return
		player_hidden_index = -1
		manager.play_player_card(card_index, selection)
		await manager.wait_for_choice()
		await get_tree().create_timer(EFFECT_PAUSE_SECONDS).timeout
	if generation != manager.battle_generation: return
	player_hidden_index = -1
	action_busy = false
	_refresh()

func _build_end_turn() -> void:
	var end := _button(self, "结束回合", Rect2(1300, 800, 200, 66), func(): _on_end_turn(), Color("#53402d"), GOLD)
	end.disabled = manager.phase != "player_action" or action_busy or not manager.pending_choice.is_empty()

func _on_end_turn() -> void:
	if action_busy or manager.phase != "player_action":
		return
	var generation := manager.battle_generation
	action_busy = true
	selected_index = -1
	hovered_index = -1
	_clear_hover_preview()
	_refresh()
	await manager.end_player_turn()
	if generation != manager.battle_generation:
		return
	action_busy = false
	_refresh()
	if manager.phase == "enemy_action" and not enemy_animating:
		_run_enemy_turn()

func _run_enemy_turn() -> void:
	var generation := manager.battle_generation
	enemy_animating = true
	await get_tree().create_timer(0.75).timeout
	if generation != manager.battle_generation:
		return
	while manager.phase == "enemy_action":
		var action := manager.peek_enemy_action()
		var chosen_index := int(action["index"])
		if action.get("kind", "") == "artifact":
			var entry := manager.artifact_entry(manager.enemy, "implement")
			var target := _artifact_cast_target(manager.enemy, action["target"])
			battle_fx.cast({"element": entry["element"], "effects": manager.artifact_effects(manager.enemy)}, "enemy", Vector2(1520, 500), target)
			await get_tree().create_timer(0.52).timeout
			if generation != manager.battle_generation: return
			await manager.enemy_step(-1, action["target"], "artifact")
			await get_tree().create_timer(0.3).timeout
			continue
		if chosen_index < 0:
			await manager.enemy_step(-1)
			break
		var selection: Dictionary = action["target"]
		var card: Dictionary = manager.cards[manager.enemy.hand[chosen_index]]
		var enemy_card_size := HAND_CARD_SIZE
		var source := _enemy_card_position(chosen_index, manager.enemy.hand.size()) + enemy_card_size / 2.0
		enemy_hidden_index = chosen_index
		_refresh()
		await _present_card(card, "enemy", source)
		if generation != manager.battle_generation:
			return
		if manager.phase != "enemy_action":
			break
		var mode := manager.card_target_mode(card)
		var destination := _target_point("enemy" if mode == "slot" else "player", selection) if mode != "none" else Vector2(-1, -1)
		await get_tree().create_timer(_cast_card(card, "enemy", destination)).timeout
		if generation != manager.battle_generation:
			return
		await manager.enemy_step(chosen_index, selection)
		enemy_hidden_index = -1
		await get_tree().create_timer(EFFECT_PAUSE_SECONDS).timeout
	if generation != manager.battle_generation:
		return
	enemy_animating = false
	enemy_hidden_index = -1
	_refresh()

func _cast_card(card: Dictionary, side: String, destination: Vector2) -> float:
	GameAudio.play_cast(str(card.get("element", "")))
	for effect in card["effects"]:
		if effect.get("scope", "single") not in ["all_opponents", "all", "all_enemy_summons"]: continue
		var actor := manager.player if side == "player" else manager.enemy
		var duration := 0.0
		for target_side in manager.damage_target_sides(actor, card):
			var owner := manager.player if target_side == "player" else manager.enemy
			if effect.get("scope", "single") != "all_enemy_summons":
				duration = battle_fx.cast(card, side, Vector2(-1, -1), _anchor(target_side))
			for slot in owner.summons.size():
				if owner.summons[slot] != null:
					duration = battle_fx.cast(card, side, Vector2(-1, -1), _summon_point(target_side, slot))
		return duration
	var duration := battle_fx.cast(card, side, Vector2(-1, -1), destination)
	var hits := 0
	for effect in card["effects"]:
		if effect["type"] == "damage": hits += 1
	var generation := manager.battle_generation
	for hit in range(1, hits):
		var next_cast := battle_fx.create_tween()
		next_cast.tween_interval(hit * 0.16)
		next_cast.tween_callback(func():
			if generation == manager.battle_generation:
				battle_fx.cast(card, side, Vector2(-1, -1), destination))
	return duration + maxi(0, hits - 1) * 0.16

func _present_card(card: Dictionary, side: String, source: Vector2) -> void:
	GameAudio.play_sfx("card_play", 0.0, 100)
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
			GameAudio.play_sfx("card_draw", -2.0, 125)
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

func _on_hand_card_removed(side: String, card_id: String, index: int, reason: String) -> void:
	var views: Array[Control] = hand_cards if side == "player" else enemy_backs
	if index < 0 or index >= views.size() or not is_instance_valid(views[index]):
		return
	if side == "player" and PlatformUI.is_touch() and touch_finger >= 0 and touch_hand_index >= 0:
		if index == touch_hand_index:
			_clear_hover_preview()
			touch_hand_index = -1
			touch_finger = -1
		elif index < touch_hand_index:
			touch_hand_index -= 1
	var card := views[index]
	# Keep the remaining view indices aligned with the model's hand before any
	# subsequent discard chooses a slot. Matching by card ID would mix up copies.
	views.remove_at(index)
	if reason != "discard":
		card.hide()
		return
	GameAudio.play_sfx("card_discard", 0.0, 90)
	if not PlatformUI.is_touch() or touch_hand_index < 0: _clear_hover_preview()
	hovered_index = -1
	# Keep the existing prefab and its exact fan transform across HUD rebuilds.
	card.reparent(fx_layer)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.show()
	card.modulate = Color.WHITE
	card.set_meta("discard_side", side)
	card.set_meta("discard_card_id", card_id)
	var delay := discard_cards.size() * 0.07
	discard_cards.append(card)
	var direction := -1.0 if side == "player" else 1.0
	var tween := card.create_tween().set_parallel(true)
	tween.tween_property(card, "position:y", card.position.y + direction * DISCARD_LIFT, DISCARD_SECONDS).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", 0.0, 0.22).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 0.0, DISCARD_SECONDS - 0.18).set_delay(delay + 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		discard_cards.erase(card)
		card.queue_free())

func _clear_discard_animations() -> void:
	for card in discard_cards:
		if is_instance_valid(card):
			card.hide()
			card.queue_free()
	discard_cards.clear()

func _build_result() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := _panel(self, Rect2(480, 225, 640, 425), PANEL_DARK, GOLD, 18)
	var won := manager.phase == "victory"
	var result_title := "平 局" if manager.phase == "tie" else ("胜 利" if won else "败 北")
	_label(box, result_title, Vector2(70, 36), Vector2(500, 73), 54, GOLD if won or manager.phase == "tie" else RED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(box, "对阵 %s · %d 回合" % [manager.enemy.display_name, manager.round_number], Vector2(60, 122), Vector2(520, 40), 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label(box, "打出 %d 张牌     造成 %d 伤害     削减 %d 能量" % [manager.played_cards, manager.player_damage, manager.energy_destroyed], Vector2(40, 190), Vector2(560, 65), 19, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_button(box, "再次挑战", Rect2(70, 296, 225, 62), func(): _start_battle(), Color("#604a31"), GOLD)
	_button(box, "返回山门", Rect2(345, 296, 225, 62), func(): manager.phase = "menu"; _refresh(), Color("#293e51"), GOLD)

func _anchor(side: String) -> Vector2:
	return ENEMY_ANCHOR if side == "enemy" else PLAYER_ANCHOR

func _play_hit_feedback(target: Control, side: String) -> void:
	if not is_instance_valid(target):
		return
	var old_tween: Tween = target.get_meta("hit_tween") if target.has_meta("hit_tween") else null
	if old_tween != null and old_tween.is_running():
		old_tween.kill()
	var rest_x := float(target.get_meta("rest_x", target.position.x))
	target.position.x = rest_x + (15.0 if side == "enemy" else -15.0)
	target.modulate = Color("#ff7770")
	var tween := target.create_tween().set_parallel(true)
	tween.tween_property(target, "position:x", rest_x, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "modulate", Color.WHITE, 0.38).set_trans(Tween.TRANS_SINE)
	target.set_meta("hit_tween", tween)

func _show_damage_number(amount: int, point: Vector2, matchup: String = "") -> void:
	# Successive hits resolve in one model action. Stagger their callouts so the
	# second number does not completely cover the first.
	var now := Time.get_ticks_msec()
	var ordinal := 0
	for child in fx_layer.get_children():
		if child is DamageNumber and child.get_meta("damage_point", Vector2(-1, -1)) == point and now - int(child.get_meta("born_tick", -1000)) < 100:
			ordinal += 1
	var number: DamageNumber = DAMAGE_NUMBER_SCRIPT.new()
	number.configure(amount, matchup)
	number.position = point - Vector2(119, 94) + Vector2(ordinal * 30, ordinal * 80)
	number.set_meta("damage_point", point)
	number.set_meta("born_tick", now)
	fx_layer.add_child(number)
	if ordinal == 0:
		number.play()
	else:
		number.modulate.a = 0.0
		var delay := number.create_tween()
		delay.tween_interval(ordinal * 0.16)
		delay.tween_callback(func(): number.modulate.a = 1.0; number.play())

func _on_summon_event(side: String, slot: int, kind: String, element: String, amount: int, matchup: String = "") -> void:
	if fx_layer == null or not is_inside_tree():
		return
	var point := _summon_point(side, slot)
	var key := "%s_%d" % [side, slot]
	match kind:
		"spawn":
			battle_fx.summon_activation(point, element)
			GameAudio.play_sfx("summon_open", -3.0, 100)
		"damage":
			battle_fx.impact(element, point)
			GameAudio.play_hit(element, false, amount)
			if amount > 0:
				_play_hit_feedback(summon_views.get(key), side)
				_show_damage_number(amount, point, matchup)
		"heal":
			battle_fx.heal(point, element)
			GameAudio.play_sfx("heal", 0.0, 120)
		"destroy":
			battle_fx.impact(element, point)
			GameAudio.play_sfx("summon_death", -2.0, 90)
			var fallen: SummonView = summon_views.get(key)
			if is_instance_valid(fallen):
				summon_views.erase(key)
				fallen.mouse_filter = Control.MOUSE_FILTER_IGNORE
				fallen.pivot_offset = fallen.size / 2.0
				var fade := fallen.create_tween().set_parallel(true)
				fade.tween_property(fallen, "self_modulate:a", 0.0, 0.4)
				fade.tween_property(fallen, "scale", Vector2(0.84, 0.84), 0.4)
				fade.chain().tween_callback(fallen.queue_free)

func _on_summon_triggered(side: String, slot: int, timing: String, effect: Dictionary) -> void:
	if timing != "on_spawn": return
	var owner := manager.player if side == "player" else manager.enemy
	if slot < 0 or slot >= owner.summons.size(): return
	var summoned: Summon = owner.summons[slot]
	if summoned != null: _present_summon_effect(side, slot, summoned, effect, "cast")

func _present_summon_effect(side: String, slot: int, summoned: Summon, effect: Dictionary, stage: String) -> void:
	var generation := manager.battle_generation
	if stage == "cast":
		_clear_hover_preview()
		_build_summons()
		var view: SummonView = summon_views.get("%s_%d" % [side, slot])
		if is_instance_valid(view):
			view.play_trigger()
		var element := str(effect.get("element", effect.get("to", summoned.element)))
		GameAudio.play_cast(element, true)
		var target_side := side if effect.get("target", "self") == "self" else ("enemy" if side == "player" else "player")
		var destination := _anchor(target_side)
		var selection: Dictionary = effect.get("selection", {})
		if selection.get("kind", "") == "summon":
			destination = _summon_point(selection.get("side", target_side), int(selection["slot"]))
		elif effect.get("target", "") == "summon_self":
			destination = _summon_point(side, slot)
		match str(effect["type"]):
			"gain_energy", "lose_energy", "convert_energy": destination = _energy_point(target_side, element)
			"draw", "discard": destination = _draw_pile_point(target_side)
		var source := _summon_point(side, slot) + Vector2(0, -14)
		var cast_data := {"element": element, "effects": [effect], "fx_scale": 0.8, "summon_cast": true}
		for key in ["fx_id", "fx_speed", "fx_scale", "fx_intensity"]:
			if effect.has(key):
				cast_data[key] = effect[key]
		await get_tree().create_timer(battle_fx.cast(cast_data, side, source, destination)).timeout
	else:
		await get_tree().create_timer(SUMMON_FEEDBACK_SECONDS).timeout
		# A draw trigger also waits for all its cards to reach the hand.
		while generation == manager.battle_generation and manager.phase != "menu" and (draw_animation_active or pending_player_draws > 0 or pending_enemy_draws > 0):
			await get_tree().process_frame

func _on_action_event(message: String, side: String, kind: String, element: String, amount: int) -> void:
	if is_instance_valid(information_panel) and information_panel.can_export and is_instance_valid(information_panel.body):
		information_panel.body.text = _journal_text()
	if fx_layer == null or not is_inside_tree():
		return
	if kind == "turn":
		_show_turn_notice("enemy" if manager.phase.begins_with("enemy") else "player")
		GameAudio.play_sfx("page_turn", -4.0, 250)
		return
	# A tie has its own event name so card draws always reach the deal queue.
	if side == "system" and kind in ["victory", "defeat", "tie"]:
		GameAudio.play_sfx("ui_confirm" if kind == "victory" else "ui_back", 2.0)
		return
	if side not in ["player", "enemy"]:
		return
	var target := _anchor(side)
	var is_damage := kind in ["damage", "poison_damage"]
	if is_damage:
		if kind == "poison_damage":
			battle_fx.status(target, "wood", "poison")
			GameAudio.play_sfx("status", -3.0, 150)
		else:
			battle_fx.impact(element, target, "shield" if message.contains("护盾抵消") else "")
			GameAudio.play_hit(element, message.contains("护盾抵消"), amount)
		if amount > 0:
			_play_hit_feedback(standee_nodes.get(side), side)
			var matchup := "克制" if message.contains("克制") else "抵抗" if message.contains("抵抗") else ""
			_show_damage_number(amount, target, matchup)
	elif kind == "heal" and amount > 0:
		battle_fx.heal(target, element)
		GameAudio.play_sfx("heal", 0.0, 120)
	elif kind in ["energy", "energy_loss", "play"] and amount > 0:
		battle_fx.energy(_energy_point(side, element), element, kind == "energy")
		if kind != "play": GameAudio.play_sfx("energy", -2.0, 170)
	elif kind.begins_with("status_"):
		battle_fx.status(target, element, kind.trim_prefix("status_"))
		GameAudio.play_sfx("status", 0.0, 145)
	elif kind in ["draw", "discard"]:
		if kind == "draw" and not message.contains("手牌已满"):
			if side == "player":
				pending_player_draws += 1
			else:
				pending_enemy_draws += 1
	if is_damage and amount == 0:
		_show_floating("格挡" if message.contains("护盾抵消") else "免疫", side, Color("#bde9ff"))
		return
	if kind not in ["damage", "poison_damage", "heal", "energy", "energy_loss"] or amount <= 0:
		return
	if is_damage:
		return
	var float_point := Vector2(-1, -1)
	if kind in ["energy", "energy_loss"]:
		# Numbers drift away from the HUD panel instead of over its own text.
		float_point = _energy_point(side, element) + Vector2(-90, 130 if side == "enemy" else -150)
	_show_floating(("-" if kind in ["damage", "energy_loss"] else "+") + str(amount), side, RED if kind == "damage" else BattleRules.color(element) if element != "" else GOLD, 0.0, float_point)

func _energy_point(side: String, element: String) -> Vector2:
	var index := BattleRules.ELEMENTS.find(element)
	if index < 0:
		return _hud_origin(side) + HUD_SIZE / 2.0
	# Both HUDs keep 金水木火土 left to right, so the row is not mirrored.
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

func _open_rules() -> void:
	_open_information("五行入门", BattleInfoPanel.RULES)

func _open_journal() -> void:
	_open_information("战斗记录", _journal_text(), true)

func _journal_text() -> String:
	var events := manager.battle_log.duplicate()
	events.reverse()
	return "对阵%s · 第%d回合\n\n%s" % [manager.enemy.display_name, manager.round_number, "\n".join(events)]

func _open_information(caption: String, text: String, exportable: bool = false) -> void:
	if is_instance_valid(information_panel): return
	_clear_hover_preview()
	information_panel = BattleInfoPanel.new()
	information_panel.configure(caption, text, exportable)
	information_panel.closed.connect(func(): information_panel = null)
	information_panel.export_requested.connect(func():
		var report := manager.export_battle_report()
		information_panel.message.text = "保存失败，请重试" if report.is_empty() else "已保存到本机战报目录")
	fx_layer.add_child(information_panel)
