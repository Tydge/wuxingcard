extends RefCounted

static func fund(manager: BattleManager) -> void:
	for id in manager.player.hand:
		var card: Dictionary = manager.cards[id]
		if manager._card_candidates(manager.player, card).is_empty(): continue
		var needed := maxi(0, int(card["cost"]) - int(manager.player.energy[card["element"]]))
		if needed <= 0 or needed > manager.player.qi or not manager.can_convert_qi(manager.player, card["element"]): continue
		for unit in needed:
			if not manager.convert_qi(manager.player, card["element"]): break
		return
