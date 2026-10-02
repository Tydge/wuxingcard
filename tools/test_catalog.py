"""Single registry for regression scope, input mode and quick simulation support."""
from pathlib import Path

FULL_SUITE = [f"res://tests/{name}.gd" for name in [
    "high_cost_content_test", "audio_policy_test", "high_cost_ui_test", "high_cost_touch_test",
    "smoke_test", "card_expansion_test", "deck_store_test", "artifact_test",
    "flat_damage_test", "new_card_wave_test", "card_balance_test", "summon_expansion_test",
    "summon_presentation_test", "settlement_regression_test", "artifact_ui_test",
    "qi_cycle_test", "qi_hold_ui_test", "qi_hold_touch_test", "opening_flow_test", "opening_deal_test", "energy_help_ui_test", "upgrade_test", "upgrade_ui_test",
    "endless_run_test", "endless_recovery_test", "endless_ui_test", "endless_touch_test",
]] + ["res://tools/test_card_art.gd", "res://tools/test_summon_art.gd",
      "res://tools/test_card_keywords.gd", "res://tools/test_drag.gd",
      "res://tools/test_summon_drag.gd", "res://tools/test_deck_workshop.gd",
      "res://tools/verify_touch_ui.gd", "res://tools/test_touch_interactions.gd"]

GRAPHICAL = {
    "audio_policy_test",
    "high_cost_ui_test", "high_cost_touch_test",
    "artifact_ui_test", "qi_hold_ui_test", "qi_hold_touch_test", "opening_deal_test",
    "energy_help_ui_test", "upgrade_ui_test", "endless_ui_test", "endless_touch_test",
    "test_card_keywords", "test_drag", "test_summon_drag", "test_deck_workshop",
    "verify_touch_ui", "test_touch_interactions",
}
TOUCH = {"high_cost_touch_test", "qi_hold_touch_test", "endless_touch_test", "verify_touch_ui", "test_touch_interactions"}
QUICK_SIMULATIONS = {"smoke_test", "card_expansion_test", "upgrade_test"}
BY_NAME = {Path(script).stem: script for script in FULL_SUITE}
GROUPS = {
    "audio-policy": ["audio_policy_test"],
    "core": ["flat_damage_test", "settlement_regression_test", "qi_cycle_test", "opening_flow_test"],
    "cards": ["high_cost_content_test", "card_expansion_test", "new_card_wave_test", "card_balance_test", "upgrade_test"],
    "damage": ["flat_damage_test", "settlement_regression_test"],
    "artifacts": ["high_cost_content_test", "artifact_test", "card_balance_test", "settlement_regression_test", "upgrade_test"],
    "summons": ["high_cost_content_test", "summon_expansion_test", "summon_presentation_test"],
    "decks": ["deck_store_test"],
    "endless": ["endless_run_test", "endless_recovery_test"],
    "ui-cards": ["high_cost_ui_test", "high_cost_touch_test", "test_card_keywords", "upgrade_ui_test"],
    "ui-artifacts": ["artifact_ui_test"],
    "ui-energy": ["qi_hold_ui_test", "qi_hold_touch_test", "energy_help_ui_test"],
    "ui-opening": ["opening_deal_test"],
    "ui-hand": ["high_cost_ui_test", "high_cost_touch_test", "test_drag", "test_summon_drag", "verify_touch_ui", "test_touch_interactions"],
    "ui-decks": ["test_deck_workshop"],
    "ui-endless": ["endless_ui_test", "endless_touch_test"],
    "assets": ["test_card_art", "test_summon_art"],
}
PROFILES = {
    "quick": [BY_NAME[name] for name in GROUPS["core"]],
    "rules": [script for script in FULL_SUITE if Path(script).stem not in GRAPHICAL
              and Path(script).stem not in GROUPS["assets"]],
    "ui": [script for script in FULL_SUITE if Path(script).stem in GRAPHICAL],
    "assets": [BY_NAME[name] for name in GROUPS["assets"]],
    "full": FULL_SUITE,
}


def select_tests(profile=None, groups=None, tests=None):
    """Named scopes keep daily runs small; only explicit full runs qualify for export."""
    if groups:
        names = {name for group in groups for name in GROUPS[group]}
        return "targeted", [script for script in FULL_SUITE if Path(script).stem in names]
    if tests:
        names = set()
        for value in tests:
            name = Path(value).stem
            if name not in BY_NAME:
                raise ValueError(f"Unknown registered test: {value}")
            names.add(name)
        return "targeted", [script for script in FULL_SUITE if Path(script).stem in names]
    profile = profile or "quick"
    return profile, list(PROFILES[profile])


def test_arguments(script, profile):
    name = Path(script).stem
    arguments = ["--touch-ui"] if name in TOUCH else []
    if profile != "full" and name in QUICK_SIMULATIONS:
        arguments.append("--quick")
    return arguments
