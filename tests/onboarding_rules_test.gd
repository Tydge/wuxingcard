extends SceneTree

var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> void:
	if not value: failures += 1; push_error(text)
func run() -> void:
	var save := "user://onboarding_rules_test.json"
	DirAccess.remove_absolute(save)
	var progress := OnboardingProgress.new(save)
	check(progress.first_battle() and progress.pending("setup"), "new profile requests onboarding and the first initiative")
	progress.advance("battle", 3); progress.finish("detail_spell"); progress.claim_battle()
	var reopened := OnboardingProgress.new(save)
	check(not reopened.first_battle() and reopened.step("battle") == 3 and not reopened.pending("detail_spell") and reopened.pending("detail_summon"), "progress resumes independently per chapter/type across launch")
	progress.finish("setup")
	check(progress.pending("shop") and progress.pending("inventory"), "skipping one chapter preserves later chapters")
	var manager := BattleManager.new(); root.add_child(manager)
	manager.random_artifacts_enabled = false
	for seed_value in 12:
		manager.start_battle("ember", "balanced", seed_value, {}, {"first_side":"player"})
		check(manager.first_side == "player" and manager.phase == "player_action" and manager.player.hand.size() == 4 and manager.enemy.hand.size() == 4, "forced first turn preserves opening hands and phase")
	var run_save := "user://onboarding_run_test.json"
	var run := EndlessRun.new(manager.cards, manager.artifacts, manager.enemies, run_save)
	run.new_run(823)
	for card in ContentCatalog.base_entries(manager.cards):
		for copy in 2:
			if run.state["draft"].size() < 15: run.change_draft(card["id"],true)
	check(run.begin_battle({"first_side":"player"}) and run.battle_options()["first_side"] == "player", "first initiative is saved with the battle journal")
	var saved := EndlessRun.new(manager.cards,manager.artifacts,manager.enemies,run_save)
	check(saved.load_run() and saved.replay_battle(manager) and manager.first_side == "player", "suspended first battle restores the same initiative")
	saved.settle("victory")
	check(saved.begin_battle() and not saved.battle_options().has("first_side"), "later battles return to the ordinary random opening")
	var sides := {}
	for seed_value in 24:
		manager.start_battle("ember","balanced",seed_value)
		sides[manager.first_side] = true
	check(sides.size() == 2, "normal battles still contain both opening orders")
	DirAccess.remove_absolute(save); DirAccess.remove_absolute(run_save)
	print("Onboarding rules: independent persistence, interrupted steps, first initiative and journal replay; %d failures" % failures)
	quit(1 if failures else 0)
