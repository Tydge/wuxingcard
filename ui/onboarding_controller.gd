class_name OnboardingController
extends Node

var ui: Control
var progress: OnboardingProgress
var guide: OnboardingGuide
var host: Control
var elapsed := 0.0
var sequence: Array[Dictionary] = []
var equipment_baseline := ""

func configure(surface: Control, ledger: OnboardingProgress) -> void:
	ui = surface; progress = ledger

func _ready() -> void:
	guide = OnboardingGuide.new()
	ui.add_child.call_deferred(guide)
	guide.next_requested.connect(_next)
	guide.skip_requested.connect(skip)
	guide.hide()

func guide_active() -> bool: return is_instance_valid(guide) and guide.is_inside_tree() and guide.visible

func complete(chapter: String) -> void:
	progress.finish(chapter)
	if chapter == "inventory": equipment_baseline = ""
	guide.hide()
	guide.key = ""

func skip() -> void:
	if guide_active(): complete(guide.chapter)

func _next() -> void:
	if not guide_active(): return
	var chapter := guide.chapter
	if chapter == "setup": return
	var index := progress.step(chapter) + 1
	if chapter == "inventory" and index == 2 and int(host.owned_entry.get("level",0)) == 2: index = 3
	if index >= sequence.size(): complete(chapter)
	else:
		progress.advance(chapter, index)
		if chapter == "inventory" and index == 3 and host is EndlessScreen: host._close_modal(false)
	update()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.1: return
	elapsed = 0
	update()

func update() -> void:
	if not is_instance_valid(guide) or not guide.is_inside_tree(): return
	if not progress.enabled or not ui.is_visible_in_tree(): guide.hide(); return
	host = null
	for child in ui.get_children():
		if child is Control and child.is_visible_in_tree() and not child.is_queued_for_deletion() and (child is EndlessScreen or child is MainMenu): host = child
	if host != null:
		if _details(): return
		if host is EndlessScreen:
			match host.view:
				"setup": _setup(); return
				"rest": _rest(); return
				"shop": _shop(); return
				"inventory": _inventory(); return
		guide.hide()
		return
	if ui.manager.phase == "player_action" and not ui.opening_active and not ui.action_busy and not ui.draw_animation_active and not is_instance_valid(ui.back_dialog) and not is_instance_valid(ui.information_panel):
		_battle()
	else: guide.hide()

func _rect(control: Control, local: Rect2 = Rect2()) -> Rect2:
	if local.size == Vector2.ZERO: local = Rect2(Vector2.ZERO, control.size)
	var transform := ui.get_global_transform_with_canvas().affine_inverse() * control.get_global_transform_with_canvas()
	return Rect2(transform * local.position, transform.basis_xform(local.size))

func _step(title: String, text: String, targets: Array, at: Vector2 = Vector2(575, 340), allowed: Array = [], action: bool = false, caption: String = "下一步") -> Dictionary:
	var spotlights: Array[Rect2] = []; spotlights.assign(targets)
	var input_regions: Array[Rect2] = []; input_regions.assign(allowed)
	return {"title":title,"text":text,"targets":spotlights,"at":at,"allowed":input_regions,"action":action,"caption":caption}

func _show(chapter: String, items: Array[Dictionary], forced: int = -1, key_suffix: String = "") -> void:
	if not progress.pending(chapter): guide.hide(); return
	sequence = items
	var index := mini(progress.step(chapter) if forced < 0 else forced, items.size() - 1)
	var item := items[index]
	guide.chapter = chapter
	# Godot routes Control input by sibling order, independently of z_index.
	ui.move_child(guide, ui.get_child_count() - 1)
	guide.present(chapter + "_" + str(index) + key_suffix, item.title, item.text, item.targets, item.allowed, item.at, "%s  ·  %d / %d" % ["认识卡牌" if chapter.begins_with("detail_") else "新手指引", index + 1, items.size()], item.action, item.caption)

func _details() -> bool:
	var card: Control = host.inspect_card
	if not is_instance_valid(card) or not card.is_visible_in_tree(): return false
	if host is MainMenu and host.closing_inspector: return false
	if host is EndlessScreen and host.inspect_closing: return false
	var tween: Tween = host.inspect_tween
	if tween != null and tween.is_running(): guide.hide(); return true
	var entry: Dictionary = host.inspect_entry if host is MainMenu else host.preview_entry
	var type := "summon" if card is SummonCardView else "spell"
	if entry.has("slot"): type = str(entry["slot"])
	var chapter := "detail_" + type
	if not progress.pending(chapter): return false
	var factor := card.size.x / (400.0 if entry.has("slot") else 240.0)
	var at := Vector2(30, 330)
	var items: Array[Dictionary] = []
	if entry.has("slot"):
		items.append(_step("属性与类型", "%s系 · %s。" % [BattleRules.element_name(entry["element"]), ArtifactLibrary.SLOT_NAMES[type]], [_rect(card, Rect2(Vector2(18,358) * factor, Vector2(364,28) * factor))], at))
		if type == "implement":
			items.append(_step("冷却", "左上角是冷却：使用后等这些己方回合。", [_rect(card, Rect2(Vector2.ZERO,Vector2(60,60) * factor))], at))
			items.append(_step("主动法器", "战斗中点法器使用；需要目标时再选择。", [_rect(card, Rect2(Vector2(24,392) * factor,Vector2(352,157) * factor))], at, [], false, "知道了"))
		elif type == "guard":
			items.append(_step("耐久", "左上角是耐久；每次触发消耗1点。", [_rect(card, Rect2(Vector2.ZERO,Vector2(60,60) * factor))], at))
			items.append(_step("自动护身", "符合下方条件时自动触发；耐久为0失效。", [_rect(card, Rect2(Vector2(24,392) * factor,Vector2(352,157) * factor))], at, [], false, "知道了"))
		else:
			items.append(_step("灵佩", "符合下方条件时自动生效。", [_rect(card, Rect2(Vector2(24,392) * factor,Vector2(352,157) * factor))], at, [], false, "知道了"))
	else:
		items.append(_step("属性", "右上角是属性，边框颜色与它一致。", [_rect(card, Rect2(Vector2(194,3) * factor,Vector2(35,28) * factor))], at))
		items.append(_step("费用", "打出时消耗这么多点对应属性灵气。", [_rect(card, Rect2(Vector2(9,3) * factor,Vector2(37,28) * factor))], at))
		if type == "summon": items.append(_step("召唤物生命", "右下角是生命；降至0时消失。", [_rect(card,Rect2(Vector2(207,296) * factor,Vector2(54,54) * factor))], at))
		items.append(_step("效果", "这里写明打出效果。" if type == "spell" else "这里写明召唤物的触发时机与效果。", [_rect(card,Rect2(Vector2(17,243) * factor,Vector2(206,80) * factor))], at, [], false, "知道了"))
	_show(chapter, items)
	return true

func _setup() -> void:
	if not progress.pending("setup"): guide.hide(); return
	if is_instance_valid(host.modal): guide.hide(); return
	var workshop: EndlessWorkshop = host.workshop
	var count := workshop.draft.size()
	var library := Rect2(219,172,939,599)
	var rows := Rect2(1187,178,347,528)
	var allowed: Array[Rect2] = [library, rows, Rect2(60,175,140,520), Rect2(540,800,345,65)]
	var ready := count == 15
	if ready: allowed.append(_rect(workshop.play_button))
	var text := "已选15张。点「入阵」开始。" if ready else ("按住卡牌拖到右侧；也可点＋。" if PlatformUI.is_touch() else "将左侧卡牌拖到右侧。") + "\n已选 %d / 15张。" % count
	var available: DeckLibraryCard
	for card: DeckLibraryCard in workshop.card_nodes:
		if card.add_allowed: available = card; break
	var targets: Array = [_rect(workshop, library), _rect(workshop, rows)] if not ready else [_rect(workshop.play_button)]
	if not ready and available == null:
		text = "换页或切换属性，继续选牌。\n已选 %d / 15张。" % count
		targets.append(_rect(workshop.next_page_button))
	_show("setup", [_step("组成你的牌组", text, targets, Vector2(580,8), allowed, true)], 0, "_ready" if ready else "_cards")
	if not ready and available != null: guide.drag_hint(_rect(available).get_center(), _rect(workshop.drop_zone).get_center())

func _rest() -> void:
	var items: Array[Dictionary] = []
	for entry in [["shop","集市","用灵钱购买卡牌与法宝。"],["inventory","行囊","调整牌组、升级卡牌、装备法宝。"],["hp","养息","花费灵钱，生命上限增加10。"],["scout","探看","查看下一位对手与已探知的牌。"]]:
		items.append(_step(entry[1], entry[2], [_rect(host.hotspots[entry[0]])], Vector2(550,30), [], false, "下一处"))
	items.append(_step("启程", "准备好后，点这里进入下一战。", [_rect(host.next_button)], Vector2(780,480), [], false, "开始休整"))
	_show("rest", items)

func _shop() -> void:
	if not progress.pending("shop"): guide.hide(); return
	var cards: Array[Rect2] = []
	for card in host.item_views:
		if is_instance_valid(card) and card.get_parent() == host.content: cards.append(_rect(card))
	if is_instance_valid(host.modal) and progress.step("shop") != 1: progress.advance("shop", 1)
	var items: Array[Dictionary] = [_step("集市", "点一张卡牌或法宝，查看效果与价格。", cards, Vector2(550,40), cards, true)]
	items.append(_step("购买", "支付按钮上的灵钱，将它收入行囊。", [_rect(host.action_button)] if is_instance_valid(host.action_button) else cards, Vector2(30,350), [], false, "知道了"))
	if not is_instance_valid(host.modal) and progress.step("shop") > 0: progress.advance("shop", 0)
	_show("shop", items)

func _inventory() -> void:
	if not progress.pending("inventory"): guide.hide(); return
	var workshop: EndlessWorkshop = host.workshop
	var stage := progress.step("inventory")
	var modal := is_instance_valid(host.modal)
	if modal and host.inspection_kind == "cards" and stage == 0: progress.advance("inventory", 1); stage = 1
	if stage in [1,2] and not modal: progress.advance("inventory", 0); stage = 0
	if modal and stage == 1 and int(host.preview_entry["level"]) > int(host.owned_entry["level"]): progress.advance("inventory", 2); stage = 2
	if stage == 3 and workshop.view_mode == "artifacts": progress.advance("inventory", 4); stage = 4
	if stage == 4 and workshop.view_mode != "artifacts": progress.advance("inventory",3); stage = 3
	var library := _rect(workshop, Rect2(219,172,939,599))
	var rows := _rect(workshop, Rect2(1187,178,347,528))
	var targets: Array[Rect2] = []
	for card: Control in workshop.card_nodes: targets.append(_rect(card))
	for row: Control in workshop.row_nodes.values(): targets.append(_rect(row))
	var items: Array[Dictionary] = [_step("卡牌详情", "点一张卡牌，查看可升级的效果。", [library], Vector2(590,18), targets, true)]
	var preview := Rect2(550,710,500,64)
	if modal and is_instance_valid(host.inspect_tabs): preview = _rect(host.inspect_tabs)
	var highest := modal and int(host.owned_entry.get("level",0)) == 2
	items.append(_step("预览升级", "这张牌已到最高等级。" if highest else "点下一等级，预览强化效果。", [preview], Vector2(30,330), [preview] if not highest else [], not highest))
	items.append(_step("淬炼", "点「确认淬炼」，花费灵钱升级这一张。", [_rect(host.upgrade_button)] if modal and is_instance_valid(host.upgrade_button) else [preview], Vector2(30,330), [], false, "知道了"))
	var tab := _rect(workshop, Rect2(503,63,132,58))
	items.append(_step("法宝", "点「法宝」，查看与装备随身法宝。", [tab], Vector2(670,30), [tab], true))
	items.append(_step("装备法宝", "点法宝下方＋，装备到右侧对应槽位。" if not host.run.state["owned_artifacts"].is_empty() else "购得法宝后，点＋装备到右侧对应槽位。", [library, rows], Vector2(580,18), [library,rows], false, "完成"))
	var artifact: ArtifactLibraryCard
	if stage == 4:
		var current := JSON.stringify(host.run.state["loadout"])
		if equipment_baseline.is_empty(): equipment_baseline = current
		elif equipment_baseline != current: complete("inventory"); equipment_baseline = ""; return
		for views: Array in workshop.artifact_motion.page_views:
			for candidate: ArtifactLibraryCard in views:
				if candidate.is_visible_in_tree() and not candidate.equipped: artifact = candidate; break
		if artifact != null:
			var slot := str(artifact.entry["slot"])
			items[4] = _step("装备法宝", "点＋装备，或拖到右侧标亮的槽位。", [_rect(artifact.plus),_rect(workshop.artifact_rows[slot])], Vector2(580,8),[library,rows],true)
	_show("inventory", items)
	if stage == 4 and artifact != null: guide.drag_hint(_rect(artifact.front).get_center(),_rect(workshop.artifact_rows[str(artifact.entry["slot"])]).get_center())

func _battle() -> void:
	if not progress.pending("battle"):
		_battle_implement()
		if not guide_active(): _battle_status()
		return
	var own_hp: Rect2 = ui._hud_global_rect("player", ui.HUD_HP)
	var enemy_hp: Rect2 = ui._hud_global_rect("enemy", ui.HUD_HP)
	var energies: Array[Rect2] = []
	for entry: Dictionary in ui.energy_touch_regions:
		if entry.side == "player": energies.append(entry.rect)
	var sums: Array[Rect2] = []
	for i in 3: sums.append(ui._summon_slot_rect("player",i))
	var equipment: Array[Rect2] = [Rect2(14,191,100,214),Rect2(68,423,66,222)]
	var items: Array[Dictionary] = [
		_step("你的生命", "生命降至0时败北。", [own_hp], Vector2(60,460)),
		_step("对手", "这里查看对手的生命与灵气。", [Rect2(ui._hud_origin("enemy"),ui.HUD_SIZE)],Vector2(950,230)),
		_step("手牌", "按住查看，上拖打出。" if PlatformUI.is_touch() else "悬停查看，拖向目标出牌。", [Rect2(600,670,630,220)],Vector2(720,420)),
		_step("召唤位", "召唤牌拖到空位，最多3只。", sums, Vector2(820,330)),
		_step("牌库", "每个己方回合开始抽1张。", [Rect2(ui.PLAYER_DECK_POS,ui.DECK_SIZE)],Vector2(990,490)),
		_step("结束回合", "出牌完毕，点这里交给对手。", [Rect2(1300,800,200,66)],Vector2(1000,520)),
		_step("灵气与费用", "打出卡牌，消耗对应属性的灵气。", energies,Vector2(65,460)),
		_step("转化真气", "点任一属性圈：1真气 → 1灵气。", energies,Vector2(65,460),energies,true),
	]
	if not ui.manager.player.artifacts.values().all(func(id): return str(id).is_empty()): items.insert(4, _step("法宝", "法器主动使用；护身与灵佩自动触发。", equipment, Vector2(180,320)))
	_show("battle", items)
	if progress.step("battle") == items.size() - 1: guide.key = "battle_convert"

func _battle_implement() -> void:
	if not progress.pending("battle_implement") or ui.manager.artifact_entry(ui.manager.player,"implement").is_empty(): guide.hide(); return
	var weapon := Rect2(14,191,100,214)
	var ready: bool = ui.manager.artifact_can_activate(ui.manager.player)
	_show("battle_implement", [_step("使用法器", "点法器立绘发动；需要目标时再选择。" if ready else "点法器立绘发动；冷却结束后可使用。", [weapon],Vector2(180,215),[weapon] if ready else [],ready,"知道了")])
	if ready: guide.key = "battle_implement_use"

func _battle_status() -> void:
	if not progress.pending("battle_status"): return
	for child in ui.get_children():
		if child is Control and child.is_visible_in_tree() and child.get_script() == ui.STATUS_ICON_SCRIPT:
			_show("battle_status", [_step("状态", "按住图标查看效果，数字是层数。" if PlatformUI.is_touch() else "悬停图标查看效果，数字是层数。", [_rect(child)],Vector2(575,330),[],false,"知道了")])
			return
