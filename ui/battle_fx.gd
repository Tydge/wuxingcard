class_name BattleFX
extends Control

# Shared painted sprites add texture to the procedural five-element effects. New
# cards inherit a style from their effects; fx_id / fx_scale / fx_speed can override it.
var active: Array[Dictionary] = []
var serial := 0
var ring_texture: Texture2D
var projectile_textures: Dictionary = {}
var impact_texture: Texture2D
var healing_texture: Texture2D
var fire_impact_frames: Texture2D
var burn_mark_frames: Texture2D
var poison_mist_frames: Texture2D
# Where each fighter's standee sits. The battle UI overrides these so casts can
# travel from one standee to the other.
var anchors := {"player": Vector2(292, 452), "enemy": Vector2(1308, 452)}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://assets/fx/arcane_ring.webp"):
		ring_texture = load("res://assets/fx/arcane_ring.webp")
	for element in BattleRules.ELEMENTS:
		var projectile_path := "res://assets/fx/%s_projectile.webp" % element
		if ResourceLoader.exists(projectile_path):
			projectile_textures[element] = load(projectile_path)
	if ResourceLoader.exists("res://assets/fx/ink_impact.webp"):
		impact_texture = load("res://assets/fx/ink_impact.webp")
	if ResourceLoader.exists("res://assets/fx/healing_vines.webp"):
		healing_texture = load("res://assets/fx/healing_vines.webp")
	if ResourceLoader.exists("res://assets/fx/fire_impact_frames.webp"):
		fire_impact_frames = load("res://assets/fx/fire_impact_frames.webp")
	if ResourceLoader.exists("res://assets/fx/burn_mark_frames.webp"):
		burn_mark_frames = load("res://assets/fx/burn_mark_frames.webp")
	if ResourceLoader.exists("res://assets/fx/poison_mist_frames.webp"):
		poison_mist_frames = load("res://assets/fx/poison_mist_frames.webp")

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
	active[active.size() - 1]["summon_cast"] = bool(card.get("summon_cast", false))
	return duration

func _default_style(card: Dictionary) -> String:
	var effects: Array = card.get("effects", [])
	var first: Dictionary = effects[0] if not effects.is_empty() else {}
	match str(first.get("type", "")):
		"damage": return {"metal":"metal_slash", "wood":"wood_grow", "water":"water_wave", "fire":"fire_slash", "earth":"earth_impact"}.get(card["element"], "generic_buff")
		"summon": return "energy_gain"
		"heal", "heal_selected", "heal_summon": return "wood_heal"
		"draw": return "card_draw"
		"gain_energy", "gain_random_energy", "convert_energy": return "energy_gain"
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
	var duration := 0.56 if element == "fire" and detail != "shield" else 0.72
	_add("impact", element, point, point, duration, 1.0, 1.0, detail)

func heal(point: Vector2, element: String = "wood") -> void:
	_add("heal", element, point, point, 1.05)

func energy(point: Vector2, element: String, gaining: bool) -> void:
	_add("energy_gain" if gaining else "energy_loss", element, point, point, 0.72)

func status(point: Vector2, element: String, status_id: String) -> void:
	var duration := 0.64 if status_id == "shield" else 0.86 if status_id in ["burn", "poison"] else 1.1
	_add("status", element, point, point, duration, 1.0, 1.0, status_id)

func summon_activation(point: Vector2, element: String) -> void:
	_add("summon_activation", element, point, point, 0.48)

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
	var fade := pow(1.0 - p, 1.3)
	var radius := 25.0 + _smooth(p) * 66.0
	# A single expanding ring marks entry without repeating a busy glyph.
	draw_arc(point, radius, 0.0, TAU, 80, _tint(c, fade * 0.19), 8.0, true)
	draw_arc(point, radius, 0.0, TAU, 80, _tint(c.lightened(0.7), fade * 0.68), 2.4, true)

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

func _draw_painted_sprite(texture: Texture2D, point: Vector2, dimensions: Vector2, angle: float, color: Color) -> void:
	if texture == null or color.a <= 0.01:
		return
	draw_set_transform(point, angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-dimensions * 0.5, dimensions), false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_frame(atlas: Texture2D, point: Vector2, dimensions: Vector2, progress: float, color: Color, crossfade: bool = false) -> void:
	if atlas == null:
		return
	# Eight cels, laid out in reading order as four columns and two rows.
	var frame_position := clampf(progress, 0.0, 1.0) * (7.0 if crossfade else 8.0)
	var frame := mini(7, int(frame_position))
	var blend := _smooth(frame_position - float(frame)) if crossfade else 0.0
	_draw_frame_cell(atlas, point, dimensions, frame, _tint(color, color.a * (1.0 - blend)))
	if blend > 0.0 and frame < 7:
		_draw_frame_cell(atlas, point, dimensions, frame + 1, _tint(color, color.a * blend))

func _draw_frame_cell(atlas: Texture2D, point: Vector2, dimensions: Vector2, frame: int, color: Color) -> void:
	var source := Rect2(Vector2(float(frame % 4) * 256.0, float(int(frame / 4)) * 256.0), Vector2(256, 256))
	draw_set_transform(point, 0.0, Vector2.ONE)
	draw_texture_rect_region(atlas, Rect2(-dimensions * 0.5, dimensions), source, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_cast(e: Dictionary, p: float, c: Color) -> void:
	var origin: Vector2 = e["from"]
	var destination: Vector2 = e["to"]
	var scale: float = e["scale"]
	var intensity: float = e["intensity"]
	var style: String = e["detail"]
	var same_place := origin.distance_to(destination) < 3.0
	var flight := clampf((p - 0.11) / 0.81, 0.0, 1.0)
	var head := origin.lerp(destination, _smooth(flight))
	var visibility := sin(PI * clampf((p - 0.07) / 0.93, 0.0, 1.0))
	if same_place:
		if style.contains("heal"):
			_draw_heal(e, p, c)
		elif style.contains("shield"):
			_draw_shield(e, p, c)
		elif style in ["energy_gain", "energy_loss", "card_draw", "generic_buff"] or style.ends_with("_buff"):
			if not bool(e.get("summon_cast", false)):
				_draw_summon_activation(e, p, c)
		else:
			_draw_impact(e, p, c)
		return
	if p < 0.23 and not bool(e.get("summon_cast", false)):
		var windup := sin(PI * p / 0.23)
		_draw_ai_ring(origin, (30.0 + p * 82.0) * scale, -p * 1.4,
			_tint(c.lightened(0.3), windup * 0.55))
		_glow(origin, 32.0 * scale, c, windup * 0.7)
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
			var q := clampf(flight - float(i) * 0.035, 0.0, 1.0)
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
			var q := clampf(flight - float(i) * 0.055, 0.0, 1.0)
			var point := origin.lerp(destination, _smooth(q)) + perpendicular * sin(float(i) * 2.8) * 23.0
			_draw_shard(point, direction.rotated(float(i) * 0.8), (14.0 + float(i % 3) * 7.0) * scale, _tint(c, visibility * 0.85))
	else:
		for i in 9:
			var q := clampf(flight - float(i) * 0.025, 0.0, 1.0)
			var point := origin.lerp(destination, _smooth(q)) + perpendicular * sin(float(i) * 2.1 + p * 8.0) * (7.0 + float(i % 4) * 5.0)
			var size := (19.0 - float(i) * 0.9) * scale
			_draw_shard(point, direction.rotated(sin(float(i) * 2.0) * 0.6), size, _tint(c.lightened(0.25), visibility * 0.82))
	# Element-specific painted heads overlay the geometric motion trails. The
	# texture aspect ratio is preserved so each motif stays crisp on mobile.
	var projectile: Texture2D = projectile_textures.get(str(e["element"]))
	if projectile != null:
		var width := 208.0 * scale
		var aspect := float(projectile.get_height()) / float(projectile.get_width())
		_draw_painted_sprite(projectile, head - direction * 72.0 * scale,
			Vector2(width, width * aspect), direction.angle(),
			_tint(Color.WHITE, visibility))

func _draw_impact(e: Dictionary, p: float, c: Color) -> void:
	if str(e["detail"]) == "shield":
		_draw_shield(e, p, c)
		return
	if str(e["element"]) == "fire" and fire_impact_frames != null:
		_draw_frame(fire_impact_frames, e["to"], Vector2(260, 260) * float(e["scale"]), p, Color.WHITE)
		return
	var point: Vector2 = e["to"]
	var scale: float = e["scale"]
	var fade := 1.0 - p
	var radius := (16.0 + p * 95.0) * scale
	var painted_fade := pow(1.0 - p, 1.6)
	draw_circle(point, 80.0 * scale * (0.55 + p * 0.45), _tint(c, fade * 0.12))
	_glow(point, 63.0 * scale * (1.0 - p * 0.4), c, fade)
	draw_arc(point, radius, 0.0, TAU, 72, _tint(c.lightened(0.35), fade * 0.55), maxf(1.0, (6.0 - p * 3.0) * scale), true)
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
	_draw_painted_sprite(impact_texture, point,
		Vector2.ONE * (190.0 + p * 170.0) * scale,
		float(e["seed"]) * 0.43 + p * 0.4,
		_tint(c.lightened(0.12), painted_fade * 0.95))
func _draw_heal(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	var fade := sin(PI * p)
	draw_arc(point, 34.0 + p * 70.0, 0.0, TAU, 60, _tint(c, fade * 0.7), 3.0, true)
	for i in 12:
		var angle := TAU * float(i) / 12.0 + p * 2.0
		var leaf := point + Vector2.from_angle(angle) * (25.0 + p * 70.0) + Vector2(0, -p * 36.0)
		_draw_shard(leaf, Vector2.from_angle(angle + PI * 0.5), 8.0 * fade, _tint(c.lightened(0.35), fade * 0.8))
	_draw_painted_sprite(healing_texture, point + Vector2(0, -30.0 - p * 26.0),
		Vector2(148.0 + p * 44.0, 246.0 + p * 72.0), 0.0,
		_tint(Color.WHITE, fade * 0.84))

func _draw_shield(e: Dictionary, p: float, c: Color) -> void:
	var point: Vector2 = e["to"]
	# A single full-height arc stands just ahead of the fighter. It follows the
	# fighter's facing direction and fades cleanly instead of bursting into sprites.
	var facing := 1.0 if point.x < size.x * 0.5 else -1.0
	var visibility := sin(PI * p)
	var curve := PackedVector2Array()
	for i in 49:
		var vertical := float(i) / 48.0 * 2.0 - 1.0
		var bulge := 57.0 * (1.0 - vertical * vertical)
		var outward := 8.0 * sin(PI * p)
		curve.append(point + Vector2(facing * (118.0 + bulge + outward), vertical * 236.0))
	var light := c.lightened(0.55)
	draw_polyline(curve, _tint(c, visibility * 0.13), 19.0, true)
	draw_polyline(curve, _tint(light, visibility * 0.42), 7.0, true)
	draw_polyline(curve, _tint(Color.WHITE, visibility * 0.63), 2.2, true)

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
		_draw_shield(e, p, c)
	elif status_id == "regen":
		_draw_heal(e, p, BattleRules.color("wood"))
	elif status_id == "burn":
		if burn_mark_frames != null:
			_draw_frame(burn_mark_frames, point, Vector2(220, 220), p, Color(1, 1, 1, 0.88), true)
		else:
			_draw_burn_status(point, p)
	elif status_id == "poison":
		if poison_mist_frames != null:
			_draw_frame(poison_mist_frames, point, Vector2(232, 232), p, Color.WHITE, true)
		else:
			_draw_poison_status(point, p)
	elif status_id == "lock":
		_draw_ai_ring(point, r * 1.25, p * 0.6, _tint(c, fade * 0.52))
		draw_arc(point, r, 0.0, TAU, 60, _tint(c, fade), 5.0, true)
		draw_line(point + Vector2(-r * 0.7, r * 0.7), point + Vector2(r * 0.7, -r * 0.7), _tint(c, fade), 6.0, true)
	else:
		draw_arc(point, r, 0.0, TAU, 60, _tint(c, fade * 0.9), 4.0, true)
		for i in 5:
			var angle := TAU * float(i) / 5.0 + PI * 0.25
			_draw_shard(point + Vector2.from_angle(angle) * r, Vector2.from_angle(angle), 12.0 * fade, _tint(c, fade))

func _draw_burn_status(point: Vector2, p: float) -> void:
	var fade := minf(1.0, p * 5.0) * pow(1.0 - p, 0.7)
	var rise := _smooth(p)
	var ember := Color("#fa713d")
	var core := Color("#ffe1a0")
	draw_arc(point + Vector2(0, 43), 37.0 + rise * 9.0, 0.0, TAU, 56, _tint(ember, fade * 0.38), 2.5, true)
	for side in [-1.0, 1.0]:
		var line := PackedVector2Array()
		for step in 9:
			var t := float(step) / 8.0
			var drift := sin(t * PI * 1.7 + p * 2.0 + side) * 12.0 * t
			line.append(point + Vector2(side * (26.0 - t * 13.0) + drift, 51.0 - t * (85.0 + rise * 45.0)))
		draw_polyline(line, _tint(ember, fade * 0.21), 13.0, true)
		draw_polyline(line, _tint(core, fade * 0.77), 2.6, true)
	for i in 3:
		var mote := point + Vector2(float(i - 1) * 30.0 + sin(p * 5.0 + float(i)) * 7.0, 24.0 - rise * (85.0 + float(i % 2) * 26.0))
		draw_circle(mote, 2.5 + float(i % 2), _tint(core, fade * 0.85))

func _draw_poison_status(point: Vector2, p: float) -> void:
	var fade := minf(1.0, p * 5.0) * pow(1.0 - p, 0.7)
	var rise := _smooth(p)
	var venom := Color("#5fae79")
	var glint := Color("#c3f0a2")
	draw_circle(point + Vector2(0, 8), 36.0 + rise * 10.0, _tint(venom, fade * 0.08))
	for side in [-1.0, 1.0]:
		var curl := PackedVector2Array()
		for step in 10:
			var t := float(step) / 9.0
			var sway := sin(t * PI * 1.5 + p * 2.2) * 16.0
			curl.append(point + Vector2(side * (32.0 - t * 16.0) + sway, 43.0 - t * (62.0 + rise * 55.0)))
		draw_polyline(curl, _tint(venom, fade * 0.21), 15.0, true)
		draw_polyline(curl, _tint(glint, fade * 0.63), 2.3, true)
	for i in 3:
		var bubble := point + Vector2(float(i - 1) * 26.0 + sin(p * 3.0 + float(i)) * 7.0, 30.0 - rise * (84.0 + float(i % 2) * 24.0))
		var bubble_radius := 5.0 + float(i % 2) * 2.0
		draw_circle(bubble, bubble_radius, _tint(venom, fade * 0.24))
		draw_arc(bubble, bubble_radius, 0.0, TAU, 24, _tint(glint, fade * 0.84), 1.8, true)

func _draw_shard(point: Vector2, direction: Vector2, size: float, color: Color) -> void:
	# Subpixel shards collapse at canvas coordinates and cannot be triangulated.
	if size < 0.5 or color.a < 0.01:
		return
	var side := Vector2(-direction.y, direction.x)
	var polygon := PackedVector2Array([point + direction * size, point + side * size * 0.36, point - direction * size * 0.65, point - side * size * 0.25])
	draw_colored_polygon(polygon, color)

func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
