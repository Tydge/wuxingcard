class_name EnergyOrb
extends Panel

func _make_custom_tooltip(for_text: String) -> Object:
	return RuleTooltip.create(for_text)
