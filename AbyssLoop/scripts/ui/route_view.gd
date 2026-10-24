extends Control
class_name RouteView

const ABYSS_BACKDROP: Texture2D = preload("res://assets/background/abyss_pixel_backdrop.png")
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const FIELD_COLUMNS := 10
const FIELD_ROWS := 8

signal cell_clicked(cell_index: int)
signal cell_hovered(cell_index: int)
signal world_cell_clicked(cell_id: String)
signal world_cell_hovered(cell_id: String)

var route_cells: Array = []
var hero_progress: float = 0.0
var placed_tiles: Dictionary = {}
var world_tiles: Dictionary = {}
var combat_cell: int = -1
var boss_encounter: bool = false
var elite_encounter: bool = false
var route_shape_id: String = "classic_ring"
var placement_enabled: bool = false
var placement_action_allowed: bool = true
var selected_tile_id: String = ""
var hovered_cell_index: int = -1
var hovered_world_cell_id: String = ""
var feedback_text: String = ""
var feedback_kind: String = "event"
var feedback_time: float = 0.0
var reduced_motion: bool = false
var reduce_flashes: bool = true
var high_contrast: bool = false
var animation_speed: float = 1.0
var _last_static_signature: String = ""
var _placement_rules = TileSystemScript.new()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	custom_minimum_size = Vector2(620, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)

func configure_compact_layout(compact: bool) -> void:
	# The desktop layout needs a wide route canvas; phone layouts are stacked
	# vertically, so a narrower map keeps the interaction targets inside the viewport.
	custom_minimum_size = Vector2(300, 350) if compact else Vector2(620, 420)
	queue_redraw()

func configure_accessibility(use_reduced_motion: bool, use_reduce_flashes: bool, use_high_contrast: bool = false, use_animation_speed: float = 1.0) -> void:
	var next_animation_speed := clampf(use_animation_speed, 0.5, 1.5)
	if reduced_motion == use_reduced_motion and reduce_flashes == use_reduce_flashes and high_contrast == use_high_contrast and is_equal_approx(animation_speed, next_animation_speed):
		return
	reduced_motion = use_reduced_motion
	reduce_flashes = use_reduce_flashes
	high_contrast = use_high_contrast
	animation_speed = next_animation_speed
	queue_redraw()

func show_feedback(kind: String, message: String) -> void:
	feedback_kind = kind
	feedback_text = message
	feedback_time = 0.75 if reduced_motion else 1.35
	queue_redraw()

func _process(delta: float) -> void:
	if feedback_time <= 0.0:
		return
	feedback_time = maxf(0.0, feedback_time - delta * animation_speed)
	queue_redraw()

func _on_mouse_exited() -> void:
	var changed_state := false
	if hovered_cell_index != -1:
		hovered_cell_index = -1
		cell_hovered.emit(-1)
		changed_state = true
	if not hovered_world_cell_id.is_empty():
		hovered_world_cell_id = ""
		world_cell_hovered.emit("")
		changed_state = true
	if changed_state:
		queue_redraw()

func configure(cells: Array, progress: float, tiles: Dictionary, fighting_cell: int, allow_placement: bool, tile_id: String, is_boss: bool = false, next_route_shape_id: String = "classic_ring", landscape_tiles: Dictionary = {}, is_elite: bool = false, placement_allowed: bool = true) -> void:
	var next_progress := maxf(0.0, progress)
	var safe_shape := next_route_shape_id if ["classic_ring", "deep_descent", "narrow_ring", "fractured_loop"].has(next_route_shape_id) else "classic_ring"
	var static_signature := str(cells.size()) + "|" + str(tiles.keys()) + "|" + str(landscape_tiles) + "|" + str(fighting_cell) + "|" + str(is_boss) + "|" + str(is_elite) + "|" + str(allow_placement) + "|" + str(placement_allowed) + "|" + tile_id + "|" + safe_shape
	var needs_redraw := static_signature != _last_static_signature or not is_equal_approx(next_progress, hero_progress)
	route_cells = cells
	hero_progress = next_progress
	placed_tiles = tiles
	world_tiles = landscape_tiles
	combat_cell = fighting_cell
	boss_encounter = is_boss
	elite_encounter = is_elite
	placement_enabled = allow_placement
	placement_action_allowed = placement_allowed
	selected_tile_id = tile_id
	route_shape_id = safe_shape
	_last_static_signature = static_signature
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	# Keep the art aspect ratio and crop around the map viewport instead of stretching pixel clusters.
	var texture_size := Vector2(ABYSS_BACKDROP.get_width(), ABYSS_BACKDROP.get_height())
	var backdrop_scale := maxf(size.x / texture_size.x, size.y / texture_size.y)
	var backdrop_size := texture_size * backdrop_scale
	var backdrop_position := (size - backdrop_size) * 0.5
	draw_texture_rect(ABYSS_BACKDROP, Rect2(backdrop_position, backdrop_size), false, Color(0.86, 0.92, 0.83, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.03, 0.58 if high_contrast else 0.44), true)
	# Sparse, blocky guide lines evoke a survey map without the old technical-grid look.
	var grid_gap := 32.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.55, 0.72, 0.57, 0.045), 1.0)
		x += grid_gap
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.55, 0.72, 0.57, 0.045), 1.0)
		y += grid_gap
	if route_cells.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(30, 40), Localization.text("route.empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c6d7d7"))
		return
	var count := route_cells.size()
	# Drawing, hover and clicking must use the exact same per-profile geometry.
	# Otherwise shaped routes can be drawn in one place and select another cell.
	var route_geometry: Dictionary = _get_route_geometry()
	var center: Vector2 = route_geometry["center"]
	var radius_x: float = route_geometry["radius_x"]
	var radius_y: float = route_geometry["radius_y"]
	var cell_points: Array = route_geometry["points"]
	_draw_world_field()
	# Ambient rings.
	for ring in range(3):
		var points: PackedVector2Array = PackedVector2Array()
		for j in range(65):
			var a := TAU * float(j) / 64.0
			points.append(center + Vector2(cos(a) * (radius_x + 28.0 + ring * 13.0), sin(a) * (radius_y + 24.0 + ring * 10.0)))
		draw_polyline(points, Color(0.40, 0.62, 0.58, 0.06 + float(2 - ring) * 0.025), 1.0, true)
	# A continuous stone-and-earth trail explicitly connects every node, including
	# the last-to-first segment. This is always the battle map's closed loop.
	for i in range(count):
		var from_point: Vector2 = cell_points[i]
		var to_point: Vector2 = cell_points[(i + 1) % count]
		draw_line(from_point + Vector2(0, 4), to_point + Vector2(0, 4), Color(0.02, 0.035, 0.04, 0.62), 15.0, false)
		draw_line(from_point, to_point, Color("#493d2e"), 14.0, false)
		draw_line(from_point, to_point, Color("#b99a6d"), 9.0, false)
		draw_line(from_point, to_point, Color("#d8bd8a"), 2.0, false)
		if i % 3 == 1:
			_draw_route_chevron(from_point.lerp(to_point, 0.56), to_point - from_point)
	for i in range(count):
		var cell: Dictionary = route_cells[i]
		var point: Vector2 = cell_points[i]
		var base_kind := str(cell.get("kind", "plain"))
		var base_def: Dictionary = ContentRegistry.ROUTE_CELL_TYPES.get(base_kind, ContentRegistry.ROUTE_CELL_TYPES.plain)
		var fill: Color = Color(str(base_def.get("color", "#507e69")))
		var placed: Dictionary = placed_tiles.get(str(i), {})
		if not placed.is_empty():
			fill = Color(str(placed.get("color", "#dedede")))
		if i == 0:
			fill = Color("#d6e0a0")
		var marker_size := _route_marker_size()
		var marker_half := marker_size * 0.5
		var marker_rect := Rect2(point - Vector2(marker_half, marker_half), Vector2(marker_size, marker_size))
		draw_rect(Rect2(marker_rect.position + Vector2(3, 4), marker_rect.size), Color(0.0, 0.0, 0.0, 0.40), true)
		draw_rect(marker_rect, Color("#101f25"), true)
		draw_rect(marker_rect.grow(-3), fill, true)
		draw_rect(Rect2(marker_rect.position + Vector2(4, 4), Vector2(5, 3)), Color(0.92, 0.96, 0.76, 0.52), true)
		if high_contrast:
			draw_rect(marker_rect.grow(5.0), Color("#f4f8ee"), false, 3.0)
			draw_rect(marker_rect.grow(2.0), Color("#081319"), false, 2.0)
		draw_rect(marker_rect, Color("#f1f5e9") if high_contrast else Color("#263b37"), false, 3.0 if high_contrast else 2.0)
		var symbol_id := str(placed.get("id", base_kind))
		_draw_pixel_symbol(point + Vector2(0, -8), symbol_id)
		var outline_growth := 3.0 if count >= 18 else 6.0
		var route_target_is_valid := false
		if placement_enabled:
			var route_check: Dictionary = _placement_rules.can_place(route_cells, placed_tiles, i)
			route_target_is_valid = bool(route_check.get("ok", false)) and placement_action_allowed
		if i == hovered_cell_index:
			var hover_color := Color("#b4eb8b")
			if placement_enabled:
				hover_color = Color("#8fe3a5") if route_target_is_valid else Color("#ec8a7d")
			draw_rect(marker_rect.grow(outline_growth), Color("#f7fff3") if high_contrast else hover_color, false, 3.0 if high_contrast else (2.0 if count >= 18 else 3.0))
			if placement_enabled:
				var status_text := Localization.text("tile.route.status.valid") if route_target_is_valid else Localization.text("tile.route.status.invalid")
				var status_color := Color("#173c27") if route_target_is_valid else Color("#701f26")
				var status_rect := Rect2(marker_rect.position + Vector2(1, 1), Vector2(11, 11))
				draw_rect(status_rect, Color("#f4f8ee") if high_contrast else status_color, true)
				draw_rect(status_rect, Color("#071217") if high_contrast else Color("#f4f8ee"), false, 1.0)
				draw_string(ThemeDB.fallback_font, status_rect.position + Vector2(2, 9), status_text, HORIZONTAL_ALIGNMENT_CENTER, 7.0, 9, Color("#071217") if high_contrast else Color("#f4f8ee"))
		if i == combat_cell:
			var combat_color := Color("#c2a1ed") if boss_encounter else (Color("#e7c66f") if elite_encounter else Color("#f18a64"))
			draw_rect(marker_rect.grow(outline_growth), combat_color, false, 2.0 if not boss_encounter or count >= 18 else 4.0)
			var badge_size := 10.0 if count >= 19 else 13.0
			var badge_position := point + Vector2(marker_half - badge_size * 0.55, -marker_half - badge_size * 0.4)
			draw_rect(Rect2(badge_position, Vector2(badge_size, badge_size)), combat_color, true)
			var badge_text := "Б" if boss_encounter else ("Э" if elite_encounter else "!")
			draw_string(ThemeDB.fallback_font, badge_position + Vector2(2, badge_size - 2), badge_text, HORIZONTAL_ALIGNMENT_CENTER, badge_size - 2, 8, Color("#172329"))
		var label := str(placed.get("short", i + 1)) if not placed.is_empty() else str(i + 1)
		var label_width := minf(marker_size - 6.0, 28.0 if count >= 19 else 30.0)
		var label_font_size := 8 if count >= 19 else (9 if not placed.is_empty() else 10)
		var label_rect := Rect2(Vector2(point.x - label_width * 0.5, point.y + 1.0), Vector2(label_width, 11.0))
		draw_rect(label_rect, Color("#f4f8ee") if high_contrast else Color("#09191d", 0.84), true)
		if high_contrast:
			draw_rect(label_rect, Color("#081319"), false, 1.0)
		var label_color := Color("#10191c") if high_contrast else Color("#f5f4e6")
		draw_string(ThemeDB.fallback_font, Vector2(label_rect.position.x, point.y + 9.0), label, HORIZONTAL_ALIGNMENT_CENTER, label_width, label_font_size, label_color)
	# Hero is interpolated along the ring, so logic and presentation share one route value.
	var whole_step := int(floor(hero_progress))
	var fraction := 0.0 if reduced_motion else clampf(hero_progress - floor(hero_progress), 0.0, 1.0)
	var from_index := posmod(whole_step, count)
	var to_index := posmod(from_index + 1, count)
	var hero_point: Vector2 = cell_points[from_index].lerp(cell_points[to_index], fraction)
	# Tiny block-built explorer marker: pack, coat, hood and lantern. No licensed characters or copied silhouettes.
	draw_rect(Rect2(hero_point + Vector2(-8, 4), Vector2(17, 4)), Color(0.0, 0.0, 0.0, 0.42), true)
	draw_rect(Rect2(hero_point + Vector2(-7, -5), Vector2(5, 8)), Color("#8b6646"), true)
	draw_rect(Rect2(hero_point + Vector2(-3, -7), Vector2(7, 11)), Color("#a6c66e"), true)
	draw_rect(Rect2(hero_point + Vector2(-4, -13), Vector2(9, 7)), Color("#dfbd73"), true)
	draw_rect(Rect2(hero_point + Vector2(-1, -11), Vector2(3, 3)), Color("#253e42"), true)
	draw_rect(Rect2(hero_point + Vector2(6, -10), Vector2(2, 14)), Color("#c7b48a"), true)
	draw_rect(Rect2(hero_point + Vector2(5, -11), Vector2(4, 4)), Color("#f4d27e"), true)
	draw_rect(Rect2(hero_point + Vector2(6, -10), Vector2(2, 2)), Color("#fff3b0"), true)
	var header_position := Vector2(14, 24)
	var header_text := Localization.text("route.header") % count
	var header_color := Color("#ffffff") if high_contrast else Color("#d2d9af")
	if high_contrast:
		draw_string(ThemeDB.fallback_font, header_position + Vector2(1, 1), header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#071217"))
	draw_string(ThemeDB.fallback_font, header_position, header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, header_color)
	var selected_text := Localization.text("route.placement") % selected_tile_id if placement_enabled else Localization.text("route.no_tiles")
	var footer_position := Vector2(14, size.y - 14)
	var footer_color := Color("#ffffff") if high_contrast else Color("#a8bd9e")
	if high_contrast:
		draw_string(ThemeDB.fallback_font, footer_position + Vector2(1, 1), selected_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, Color("#071217"))
	draw_string(ThemeDB.fallback_font, footer_position, selected_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, footer_color)
	if feedback_time > 0.0 and not feedback_text.is_empty():
		var toast_width := minf(size.x - 24.0, 420.0)
		var toast_rect := Rect2(Vector2(size.x - toast_width - 12.0, 12.0), Vector2(toast_width, 34.0))
		var toast_color := Color("#314a3c")
		if not reduce_flashes:
			match feedback_kind:
				"damage": toast_color = Color("#713f40")
				"loot": toast_color = Color("#75603a")
				"boss": toast_color = Color("#5c456c")
				"objective": toast_color = Color("#386b55")
				"level": toast_color = Color("#386b55")
		var alpha := 1.0 if reduced_motion or reduce_flashes else minf(1.0, feedback_time * 1.6)
		toast_color.a = alpha
		draw_rect(toast_rect, toast_color, true)
		if high_contrast:
			draw_rect(toast_rect, Color("#f0f6ef", alpha), false, 2.0)
		draw_string(ThemeDB.fallback_font, toast_rect.position + Vector2(10, 22), feedback_text.substr(0, 48), HORIZONTAL_ALIGNMENT_LEFT, toast_width - 20.0, 12 if not high_contrast else 13, Color("#f0f5ef", alpha))

func _draw_route_chevron(raw_center: Vector2, raw_direction: Vector2) -> void:
	if raw_direction.length_squared() < 0.001:
		return
	var direction := raw_direction.normalized()
	var side := Vector2(-direction.y, direction.x)
	var center := Vector2(round(raw_center.x), round(raw_center.y))
	var back := center - direction * 5.0
	var left := Vector2(round((back + side * 3.0).x), round((back + side * 3.0).y))
	var right := Vector2(round((back - side * 3.0).x), round((back - side * 3.0).y))
	draw_line(left, center, Color("#493d2e"), 3.0, false)
	draw_line(right, center, Color("#493d2e"), 3.0, false)
	draw_line(left, center, Color("#f0d4a0"), 1.5, false)
	draw_line(right, center, Color("#f0d4a0"), 1.5, false)

func _gui_input(event: InputEvent) -> void:
	if route_cells.is_empty():
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var world_id := _find_world_cell(motion.position)
		if world_id != hovered_world_cell_id:
			hovered_world_cell_id = world_id
			world_cell_hovered.emit(hovered_world_cell_id)
			queue_redraw()
		var found_index := -1 if not world_id.is_empty() else _find_closest_cell(motion.position)
		if found_index != hovered_cell_index:
			hovered_cell_index = found_index
			cell_hovered.emit(hovered_cell_index)
			queue_redraw()
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if not touch_event.pressed or touch_event.canceled:
			return
		# Screen-touch positions are viewport-relative, unlike mouse positions in
		# _gui_input. Convert them to this RouteView's local coordinate space.
		var local_touch := make_input_local(touch_event) as InputEventScreenTouch
		if local_touch == null:
			return
		_handle_click_position(local_touch.position)
		accept_event()
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	_handle_click_position(mouse_event.position)

func _handle_click_position(local_position: Vector2) -> void:
	var world_id := _find_world_cell(local_position)
	if not world_id.is_empty():
		world_cell_clicked.emit(world_id)
		return
	var closest_index := _find_closest_cell(local_position)
	if closest_index >= 0:
		cell_clicked.emit(closest_index)

func _get_field_rect() -> Rect2:
	return Rect2(Vector2(18.0, 34.0), Vector2(maxf(1.0, size.x - 36.0), maxf(1.0, size.y - 68.0)))

func _field_cell_rect(cell_id: String) -> Rect2:
	var parts := cell_id.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Rect2()
	var col := int(parts[0])
	var row := int(parts[1])
	var field := _get_field_rect()
	var cell_size := Vector2(field.size.x / float(FIELD_COLUMNS), field.size.y / float(FIELD_ROWS))
	return Rect2(field.position + Vector2(float(col), float(row)) * cell_size, cell_size)

func _find_world_cell(position: Vector2) -> String:
	# Route hit-testing has priority over landscape placement. The world field is a
	# separate interaction layer, never a way to place a card on the visible road.
	if _find_closest_cell(position) >= 0 or _is_near_route_line(position):
		return ""
	for cell_id_value in TileSystemScript.WORLD_FIELD_KEYS:
		var cell_id := str(cell_id_value)
		if _field_cell_rect(cell_id).grow(-4.0).has_point(position):
			return cell_id
	return ""

func _is_near_route_line(position: Vector2) -> bool:
	if route_cells.size() < 2:
		return false
	var route_geometry: Dictionary = _get_route_geometry()
	var points: Array = route_geometry.get("points", [])
	if points.size() < 2:
		return false
	for index in range(points.size()):
		var from_point: Vector2 = points[index]
		var to_point: Vector2 = points[(index + 1) % points.size()]
		var nearest_point: Vector2 = Geometry2D.get_closest_point_to_segment(position, from_point, to_point)
		if nearest_point.distance_to(position) <= 9.0:
			return true
	return false

func _draw_world_field() -> void:
	for cell_id_value in TileSystemScript.WORLD_FIELD_KEYS:
		var cell_id := str(cell_id_value)
		var rect := _field_cell_rect(cell_id)
		var tile: Dictionary = world_tiles.get(cell_id, {})
		# Keep terrain markers compact. The logical field cell is larger for input,
		# but drawing a full cell could visually cover the loop on narrow profiles.
		var footprint_size := Vector2(minf(28.0, rect.size.x - 10.0), minf(22.0, rect.size.y - 10.0))
		var tile_rect := Rect2(rect.get_center() - footprint_size * 0.5, footprint_size)
		if tile.is_empty():
			var world_check: Dictionary = _placement_rules.can_place_world(route_cells, world_tiles, cell_id) if placement_enabled else {"ok": true}
			var world_target_is_valid := placement_enabled and placement_action_allowed and bool(world_check.get("ok", false))
			var base := Color("#1d332d", 0.30)
			var outline := Color("#bed59c", 0.24)
			if placement_enabled and world_target_is_valid:
				base = Color("#82b96e", 0.22)
				outline = Color("#c1e89b", 0.95)
			elif placement_enabled:
				base = Color("#c96562", 0.18)
				outline = Color("#ed9d91", 0.86)
			if cell_id == hovered_world_cell_id:
				if placement_enabled and not world_target_is_valid:
					base = Color("#c96562", 0.34)
					outline = Color("#ed9d91", 1.0)
				else:
					base = Color("#a5d98b", 0.42)
					outline = Color("#e3f4b6", 1.0)
			draw_rect(tile_rect, base, true)
			draw_rect(tile_rect, Color("#f4f8ee") if high_contrast else outline, false, 2.5 if high_contrast else (2.0 if placement_enabled else 1.0))
			if high_contrast:
				draw_rect(tile_rect.grow(2.0), Color("#081319"), false, 1.0)
			var center := tile_rect.get_center()
			if placement_enabled:
				var status_text := Localization.text("tile.route.status.valid") if world_target_is_valid else Localization.text("tile.route.status.invalid")
				var status_color := Color("#173c27") if world_target_is_valid else Color("#701f26")
				draw_rect(Rect2(center - Vector2(5, 5), Vector2(10, 10)), Color("#f4f8ee") if high_contrast else status_color, true)
				draw_string(ThemeDB.fallback_font, center + Vector2(-4, 3), status_text, HORIZONTAL_ALIGNMENT_CENTER, 8.0, 8, Color("#071217") if high_contrast else Color("#f4f8ee"))
			else:
				draw_rect(Rect2(center - Vector2(3, 1), Vector2(6, 2)), Color("#d1e5ad", 0.42 if placement_enabled else 0.14), true)
		else:
			var fill := Color(str(tile.get("color", "#788a67")))
			draw_rect(Rect2(tile_rect.position + Vector2(2, 3), tile_rect.size), Color(0.0, 0.0, 0.0, 0.38), true)
			draw_rect(tile_rect, fill, true)
			if high_contrast:
				draw_rect(tile_rect.grow(3.0), Color("#f4f8ee"), false, 2.0)
				draw_rect(tile_rect.grow(1.0), Color("#081319"), false, 1.5)
			draw_rect(tile_rect, Color("#f4f8ee") if high_contrast else Color("#172a25"), false, 2.5 if high_contrast else 2.0)
			_draw_pixel_symbol(tile_rect.get_center() + Vector2(0, -3), str(tile.get("id", "")))
			var world_label_rect := Rect2(tile_rect.position + Vector2(1.0, tile_rect.size.y - 8.0), Vector2(maxf(1.0, tile_rect.size.x - 2.0), 7.0))
			draw_rect(world_label_rect, Color("#f4f8ee") if high_contrast else Color("#071619", 0.88), true)
			if high_contrast:
				draw_rect(world_label_rect, Color("#081319"), false, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(world_label_rect.position.x, world_label_rect.end.y - 1.0), str(tile.get("short", Localization.text("route.tile.short"))), HORIZONTAL_ALIGNMENT_CENTER, world_label_rect.size.x, 6 if high_contrast else 7, Color("#10191c") if high_contrast else Color("#f5f4e6"))
			if cell_id == hovered_world_cell_id and placement_enabled:
				draw_rect(tile_rect.grow(3.0), Color("#ec8a7d"), false, 2.0)

func _get_route_geometry() -> Dictionary:
	# Single source of truth for all displayed/clickable route nodes.
	# Keep profile deformation and base ellipse in this helper only.
	var count := route_cells.size()
	var center := Vector2(size.x * 0.5, size.y * 0.51)
	var radius_x := minf(size.x * 0.385, size.y * 0.78)
	var radius_y := size.y * 0.34
	match route_shape_id:
		"narrow_ring":
			radius_x *= 0.78
			radius_y *= 0.77
		"deep_descent":
			radius_x *= 0.92
			radius_y *= 0.88
		"fractured_loop":
			radius_x *= 1.04
			radius_y *= 0.94
	var cell_points: Array[Vector2] = []
	if count > 0:
		for i in range(count):
			var angle := -PI * 0.5 + TAU * float(i) / float(count)
			var point := center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
			# Profiles modify the contour but preserve a periodic closed route.
			if route_shape_id == "deep_descent":
				point += Vector2(cos(angle * 2.0) * radius_x * 0.055, sin(angle * 2.0 + 0.4) * radius_y * 0.07)
			elif route_shape_id == "fractured_loop":
				point += Vector2(cos(angle * 3.0) * radius_x * 0.095, sin(angle * 2.0) * radius_y * 0.09)
			cell_points.append(point)
	return {"center": center, "radius_x": radius_x, "radius_y": radius_y, "points": cell_points}

func _route_marker_size() -> float:
	# Dense generated routes get smaller clickable/drawn markers so labels and hit
	# targets do not merge in the minimum supported viewport.
	return clampf(30.0 - maxf(0.0, float(route_cells.size() - 16)) * 1.2, 22.0, 30.0)

func _route_hit_radius() -> float:
	return _route_marker_size() * 0.5 + 3.0

func _find_closest_cell(position: Vector2) -> int:
	if route_cells.is_empty():
		return -1
	var geometry: Dictionary = _get_route_geometry()
	var cell_points: Array = geometry["points"]
	var closest_index := -1
	var closest_distance := INF
	for i in range(cell_points.size()):
		var point: Vector2 = cell_points[i]
		var distance_to_cell := point.distance_to(position)
		if distance_to_cell < closest_distance:
			closest_distance = distance_to_cell
			closest_index = i
	return closest_index if closest_distance <= _route_hit_radius() else -1

func _draw_pixel_symbol(center: Vector2, symbol_id: String) -> void:
	# Compact 2–3 px symbols communicate node type without relying on color alone.
	match symbol_id:
		"cache":
			draw_rect(Rect2(center + Vector2(-4, -3), Vector2(8, 6)), Color("#f0d18a"), true)
			draw_rect(Rect2(center + Vector2(-4, -4), Vector2(8, 2)), Color("#72533b"), true)
			draw_rect(Rect2(center + Vector2(-1, -2), Vector2(2, 4)), Color("#8c704b"), true)
		"hunt":
			for claw_x in [-4.0, -1.0, 2.0]:
				draw_rect(Rect2(center + Vector2(claw_x, -4), Vector2(2, 7)), Color("#f6d0a2"), true)
			draw_rect(Rect2(center + Vector2(-5, 1), Vector2(9, 2)), Color("#8c3e36"), true)
		"ward":
			draw_rect(Rect2(center + Vector2(-2, -5), Vector2(4, 10)), Color("#eff0b4"), true)
			draw_rect(Rect2(center + Vector2(-5, -2), Vector2(10, 4)), Color("#eff0b4"), true)
		"rift":
			draw_rect(Rect2(center + Vector2(-4, -5), Vector2(3, 3)), Color("#e1c5ff"), true)
			draw_rect(Rect2(center + Vector2(-1, -2), Vector2(3, 3)), Color("#e1c5ff"), true)
			draw_rect(Rect2(center + Vector2(1, 1), Vector2(3, 4)), Color("#e1c5ff"), true)
		"snare":
			for i in range(4):
				draw_rect(Rect2(center + Vector2(-5 + i * 3, -4), Vector2(1, 9)), Color("#d6f0bd"), true)
			draw_rect(Rect2(center + Vector2(-5, -1), Vector2(10, 2)), Color("#d6f0bd"), true)
		"signal":
			draw_rect(Rect2(center + Vector2(-1, -6), Vector2(3, 3)), Color("#f1e4ff"), true)
			draw_rect(Rect2(center + Vector2(-3, -3), Vector2(7, 3)), Color("#d8b4ee"), true)
			draw_rect(Rect2(center + Vector2(-2, 0), Vector2(5, 3)), Color("#9b83d5"), true)
		"event":
			draw_rect(Rect2(center + Vector2(-4, -4), Vector2(8, 8)), Color("#c0eef0"), true)
			draw_rect(Rect2(center + Vector2(-1, -1), Vector2(2, 2)), Color("#397d8a"), true)
		"danger":
			draw_rect(Rect2(center + Vector2(-4, -4), Vector2(3, 3)), Color("#ffe0bb"), true)
			draw_rect(Rect2(center + Vector2(-1, -1), Vector2(3, 3)), Color("#f3a17c"), true)
			draw_rect(Rect2(center + Vector2(2, 2), Vector2(2, 3)), Color("#9a4944"), true)
		"shrine":
			draw_rect(Rect2(center + Vector2(-4, -4), Vector2(8, 2)), Color("#e4dcff"), true)
			draw_rect(Rect2(center + Vector2(-2, -2), Vector2(4, 6)), Color("#c9b8ef"), true)
		_:
			draw_rect(Rect2(center + Vector2(-3, -2), Vector2(6, 3)), Color("#d2e6aa"), true)
			draw_rect(Rect2(center + Vector2(-1, 1), Vector2(2, 3)), Color("#4f865d"), true)

