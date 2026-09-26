class_name BattleFX
extends Control

# All effects are drawn by Godot. New cards inherit a style from their element and
# effects; optional fx_id / fx_scale / fx_speed / fx_intensity data can override it.
var active: Array[Dictionary] = []
var serial := 0
var ring_texture: Texture2D
# Where each fighter's standee sits. The battle UI overrides these so casts can
# travel from one standee to the other.
var anchors := {"player": Vector2(292, 452), "enemy": Vector2(1308, 452)}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://assets/fx/arcane_ring.webp"):
		ring_texture = load("res://assets/fx/arcane_ring.webp")

func clear_effects() -> void:
	active.clear()
	queue_redraw()

func _add(kind: String, element: String, from: Vector2, to: Vector2, duration: float, scale: float = 1.0, intensity: float = 1.0, detail: String = "") -> void:
	serial += 1
	active.append({"kind":kind, "element":element, "from":from, "to":to, "duration":duration, "age":0.0, "scale":scale, "intensity":intensity, "detail":detail, "seed":serial})
	if active.size() > 36:
		active.remove_at(0)
	queue_redraw()

func set_anchors(player_anchor: Vector2, enemy_anchor: Vector2) -> void:
	anchors = {"player": player_anchor, "enemy": enemy_anchor}

func _anchor(side: String) -> Vector2:
	return anchors.get(side, anchors["player"])

func _opponent(side: String) -> String:
	return "enemy" if side == "player" else "player"

# A card that hits or hinders the opponent flies across the arena; a card whose
# effects all target its own side lands back on the caster's own standee.
func targets_opponent(card: Dictionary) -> bool:
	for effect in card.get("effects", []):
		if str(effect.get("type", "")) == "damage":
			return true
		if str(effect.get("target", "opponent")) == "opponent":
			return true
	return false

func cast(card: Dictionary, side: String, source: Vector2 = Vector2(-1, -1), target: Vector2 = Vector2(-1, -1)) -> float:
	var element: String = str(card.get("element", "metal"))
	var style := str(card.get("fx_id", ""))
	if style == "":
		style = _default_style(card)
	var scale := float(card.get("fx_scale", 1.0))
	var speed := maxf(0.25, float(card.get("fx_speed", 1.0)))
	var intensity := float(card.get("fx_intensity", 1.0)) + float(card.get("cost", 0)) * 0.13
	var origin := source if source.x >= 0.0 else _anchor(side)
	var destination := target
	if destination.x < 0.0:
		destination = _anchor(_opponent(side)) if targets_opponent(card) else _anchor(side)
	var duration := 0.54 / speed
	_add("cast", element, origin, destination, duration, scale, intensity, style)
	return duration

func _default_style(card: Dictionary) -> String:
	var effects: Array = card.get("effects", [])
	var first: Dictionary = effects[0] if not effects.is_empty() else {}
	match str(first.get("type", "")):
		"damage": return {"metal":"metal_slash", "wood":"wood_grow", "water":"water_wave", "fire":"fire_slash", "earth":"earth_impact"}.get(card["element"], "generic_buff")
		"summon": return "energy_gain"
		"heal": return "wood_heal"
		"draw": return "card_draw"
		"gain_energy", "convert_energy": return "energy_gain"
		"lose_energy": return "energy_loss"
		"discard": return "generic_debuff"
		"status":
			var status := str(first.get("status", ""))
			if status == "shield": return "water_shield" if card["element"] == "water" else "earth_shield"
			if status == "regen": return "wood_heal"
			if first.get("target", "opponent") == "self": return str(card["element"]) + "_buff"
			return "generic_debuff"
	return "generic_buff"

func impact(element: String, point: Vector2, detail: String = "") -> void:
	_add("impact", element, point, point, 0.72, 1.0, 1.0, detail)

func heal(point: Vector2, element: String = "wood") -> void:
	_add("heal", element, point, point, 1.05)

func energy(point: Vector2, element: String, gaining: bool) -> void:
	_add("energy_gain" if gaining else "energy_loss", element, point, point, 0.72)

func status(point: Vector2, element: String, status_id: String) -> void:
	_add("status", element, point, point, 1.1, 1.0, 1.0, status_id)

func summon_activation(point: Vector2, element: String) -> void:
	_add("summon_activation", element, point, point, 0.8)

func _process(delta: float) -> void:
	for i in range(active.size() - 1, -1, -1):
		active[i]["age"] = float(active[i]["age"]) + delta
		if float(active[i]["age"]) >= float(active[i]["duration"]):
			active.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for effect in active:
		var p := clampf(float(effect["age"]) / float(effect["duration"]), 0.0, 1.0)
		var c := _color(str(effect["element"]))
		match str(effect["kind"]):
			"cast": _draw_cast(effect, p, c)
			"impact": _draw_impact(effect, p, c)
			"heal": _draw_heal(effect, p, c)
			"energy_gain", "energy_loss": _draw_energy(effect, p, c)
			"status": _draw_status(effect, p, c)
			"summon_activation": _draw_summon_activation(effect, p, c)

func _draw_summon_activation(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	var glow := sin(PI * p)
	var radius := 34.0 + p * 32.0
	_draw_ai_ring(point, radius * 1.25, p * 0.8, _tint(c.lightened(0.3), glow * 0.65))
	_glow(point, radius, c, glow * 0.6)
	draw_arc(point, radius, 0.0, TAU, 48, _tint(c.lightened(0.3), glow * 0.85), 2.5, true)
	for i in 6:
		var mote := point + Vector2.from_angle(TAU * float(i) / 6.0 + p * 0.9) * radius
		draw_circle(mote, 3.0, _tint(c.lightened(0.5), glow))

func _color(element: String) -> Color:
	return BattleRules.color(element) if element in BattleRules.ELEMENTS else Color("#dec596")

func _tint(base: Color, alpha: float) -> Color:
	return Color(base.r, base.g, base.b, clampf(alpha, 0.0, 1.0))

func _glow(point: Vector2, radius: float, color: Color, strength: float) -> void:
	for i in range(4, 0, -1):
		draw_circle(point, radius * float(i) / 2.0, _tint(color, strength * 0.055))
		draw_circle(point, maxf(2.0, radius * 0.22), _tint(color.lightened(0.65), strength * 0.62))

func _draw_ai_ring(point: Vector2, radius: float, angle: float, color: Color) -> void:
	if ring_texture == null:
		return
	draw_set_transform(point, angle, Vector2.ONE)
	draw_texture_rect(ring_texture, Rect2(-radius, -radius, radius * 2.0, radius * 2.0), false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_cast(e: Dictionary, p: float, c: Color) -> void:
	var origin: Vector2 = e["from"]
	var destination: Vector2 = e["to"]
	var scale: float = e["scale"]
	var intensity: float = e["intensity"]
	var style: String = e["detail"]
	var same_place := origin.distance_to(destination) < 3.0
	var head := origin.lerp(destination, _smooth(p))
	var visibility := sin(PI * p)
	if same_place:
		_draw_impact(e, p, c)
		return
	var direction := (destination - origin).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var tail := origin.lerp(head, 0.40)
	# A broad colored trail keeps the motion readable against the painted arena.
	draw_line(tail, head, _tint(c, visibility * 0.16), 30.0 * scale, true)
	draw_line(tail, head, _tint(c, visibility * 0.42), 12.0 * scale, true)
	draw_line(tail, head, _tint(c.lightened(0.7), visibility * 0.86), 3.5 * scale, true)
	_glow(head, 40.0 * scale, c, visibility * intensity)
	if style.begins_with("metal"):
		for i in 3:
			var offset := perpendicular * (float(i) - 1.0) * 13.0 * scale
			draw_line(tail + offset, head + offset + direction * 35.0, _tint(c.lightened(0.5), visibility * (0.9 - float(i) * 0.13)), (8.0 - float(i)) * scale, true)
	elif style.begins_with("water"):
		for i in 7:
			var q := clampf(p - float(i) * 0.035, 0.0, 1.0)
			var point := origin.lerp(destination, _smooth(q)) + perpendicular * sin(float(i) * 1.3 + p * 9.0) * 11.0
			draw_arc(point, (13.0 + float(i) * 4.0) * scale, -PI * 0.7, PI * 0.8, 20, _tint(c.lightened(0.2), visibility * 0.77), 3.5, true)
	elif style.begins_with("wood"):
		var previous := tail
		for i in 8:
			var q := float(i) / 7.0
			var point := tail.lerp(head, q) + perpendicular * sin(q * TAU * 1.6 + p * 5.0) * 12.0
			draw_line(previous, point, _tint(c, visibility * 0.92), 6.0 * scale, true)
			if i % 2 == 0:
				draw_circle(point + perpendicular * 8.0, 4.5 * scale, _tint(c.lightened(0.3), visibility * 0.7))
			previous = point
	elif style.begins_with("earth"):
		for i in 6:
			var q := clampf(p - float(i) * 0.055, 0.0, 1.0)
			var point := origin.lerp(destination, _smooth(q)) + perpendicular * sin(float(i) * 2.8) * 23.0
			_draw_shard(point, direction.rotated(float(i) * 0.8), (14.0 + float(i % 3) * 7.0) * scale, _tint(c, visibility * 0.85))
	else:
		for i in 9:
			var q := clampf(p - float(i) * 0.025, 0.0, 1.0)
			var point := origin.lerp(destination, _smooth(q)) + perpendicular * sin(float(i) * 2.1 + p * 8.0) * (7.0 + float(i % 4) * 5.0)
			var size := (19.0 - float(i) * 0.9) * scale
			_draw_shard(point, direction.rotated(sin(float(i) * 2.0) * 0.6), size, _tint(c.lightened(0.25), visibility * 0.82))

func _draw_impact(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	var scale: float = e["scale"]
	var fade := 1.0 - p
	var radius := (16.0 + p * 95.0) * scale
	_draw_ai_ring(point, (75.0 + p * 100.0) * scale, p * 0.75 + float(e["seed"]) * 0.2, _tint(c.lightened(0.15), fade * 0.6))
	draw_circle(point, 80.0 * scale * (0.55 + p * 0.45), _tint(c, fade * 0.12))
	_glow(point, 63.0 * scale * (1.0 - p * 0.4), c, fade)
	draw_arc(point, radius, 0.0, TAU, 72, _tint(c.lightened(0.35), fade * 0.95), maxf(1.0, (8.0 - p * 4.0) * scale), true)
	var element: String = e["element"]
	for i in 12:
		var angle := TAU * float(i) / 12.0 + float(e["seed"]) * 0.17
		var direction := Vector2.from_angle(angle)
		var start := point + direction * (17.0 + p * 34.0) * scale
		var finish := point + direction * (39.0 + p * (66.0 + float(i % 3) * 13.0)) * scale
		if element == "earth":
			_draw_shard(finish, direction, 12.0 * fade * scale, _tint(c, fade * 0.8))
		elif element == "wood":
			draw_line(start, finish, _tint(c, fade * 0.75), 3.0 * scale, true)
			draw_circle(finish, 3.0 + 3.0 * fade, _tint(c.lightened(0.45), fade))
		elif element == "water":
			draw_arc(finish, 6.0 + p * 8.0, angle, angle + PI, 10, _tint(c, fade * 0.7), 2.0, true)
		else:
			draw_line(start, finish, _tint(c.lightened(0.4), fade * 0.8), (3.0 if element == "metal" else 5.0) * scale, true)
	if str(e["detail"]) == "shield":
		draw_arc(point, radius * 0.75, 0.0, TAU, 64, _tint(Color("#b5eaff"), fade * 0.85), 5.0, true)

func _draw_heal(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	var fade := sin(PI * p)
	draw_arc(point, 34.0 + p * 70.0, 0.0, TAU, 60, _tint(c, fade * 0.7), 3.0, true)
	for i in 12:
		var angle := TAU * float(i) / 12.0 + p * 2.0
		var leaf := point + Vector2.from_angle(angle) * (25.0 + p * 70.0) + Vector2(0, -p * 36.0)
		_draw_shard(leaf, Vector2.from_angle(angle + PI * 0.5), 8.0 * fade, _tint(c.lightened(0.35), fade * 0.8))

func _draw_energy(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	var gain: bool = e["kind"] == "energy_gain"
	var fade := 1.0 - p
	var radius := (12.0 + p * 39.0) if gain else (48.0 - p * 36.0)
	_glow(point, 20.0 + 20.0 * sin(PI * p), c, fade)
	draw_arc(point, radius, 0.0, TAU, 48, _tint(c.lightened(0.4), fade * 0.9), 3.0, true)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + p * 3.0
		var spark := point + Vector2.from_angle(angle) * (radius + 9.0)
		draw_circle(spark, 2.5 + 2.0 * fade, _tint(c, fade * 0.85))

func _draw_status(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	var status_id: String = e["detail"]
	var fade := 1.0 - p
	var r := 40.0 + p * 84.0
	if status_id == "shield":
		_draw_ai_ring(point, r * 1.3, -p * 0.7, _tint(Color("#bcecff"), fade * 0.55))
		for i in 3:
			draw_arc(point, r + float(i) * 9.0, -PI * 0.9, PI * 0.1, 38, _tint(Color("#bcecff"), fade * (0.9 - float(i) * 0.2)), 4.0, true)
	elif status_id == "regen":
		_draw_heal(e, p, BattleRules.color("wood"))
	elif status_id == "burn":
		for i in 9:
			var x := float(i - 4) * 17.0
			var tip := point + Vector2(x, -22.0 - p * (40.0 + float(i % 3) * 13.0))
			_draw_shard(tip, Vector2(0, -1), 14.0 * fade, _tint(BattleRules.color("fire"), fade))
	elif status_id == "lock":
		_draw_ai_ring(point, r * 1.25, p * 0.6, _tint(c, fade * 0.52))
		draw_arc(point, r, 0.0, TAU, 60, _tint(c, fade), 5.0, true)
		draw_line(point + Vector2(-r * 0.7, r * 0.7), point + Vector2(r * 0.7, -r * 0.7), _tint(c, fade), 6.0, true)
	else:
		draw_arc(point, r, 0.0, TAU, 60, _tint(c, fade * 0.9), 4.0, true)
		for i in 5:
			var angle := TAU * float(i) / 5.0 + PI * 0.25
			_draw_shard(point + Vector2.from_angle(angle) * r, Vector2.from_angle(angle), 12.0 * fade, _tint(c, fade))

func _draw_shard(point: Vector2, direction: Vector2, size: float, color: Color) -> void:
	# Subpixel shards collapse at canvas coordinates and cannot be triangulated.
	if size < 0.5 or color.a < 0.01:
		return
	var side := Vector2(-direction.y, direction.x)
	var polygon := PackedVector2Array([point + direction * size, point + side * size * 0.36, point - direction * size * 0.65, point - side * size * 0.25])
	draw_colored_polygon(polygon, color)

func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
