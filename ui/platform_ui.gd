class_name PlatformUI
extends RefCounted

# Platform differences belong in presentation/input, never in battle rules.
# --touch-ui lets desktop QA exercise the same touch interface as Android.
static func is_touch() -> bool:
	return OS.has_feature("android") or "--touch-ui" in OS.get_cmdline_user_args()

static func fit_design(available: Rect2, design: Vector2) -> Rect2:
	var factor := minf(available.size.x / design.x, available.size.y / design.y)
	var fitted := design * factor
	return Rect2(available.position + (available.size - fitted) / 2.0, fitted)

static func local_point(control: Control, viewport_point: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas().affine_inverse() * viewport_point
