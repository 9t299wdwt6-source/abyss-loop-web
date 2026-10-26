extends Control
class_name RouteView

const ABYSS_BACKDROP: Texture2D = preload("res://assets/background/abyss_pixel_backdrop.png")
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const FIELD_COLUMNS := 10
const FIELD_ROWS := 8
# Expedition map: square-cell grid with a 34-cell perimeter road, sized like a tactical board.
const MAP_COLUMNS := 19
const MAP_ROWS := 14
const ROAD_CELL_COUNT := 34

signal cell_clicked(cell_index: int)
signal cell_hovered(cell_index: int)
signal world_cell_clicked(cell_id: String)
signal world_cell_hovered(cell_id: String)

var route_cells: Array = []
var hero_progress: float = 0.0
var placed_tiles: Dictionary = {}
var world_tiles: Dictionary = {}
var discovered_world_cells: Dictionary = {}
var combat_cell: int = -1
var boss_encounter: bool = false
var elite_encounter: bool = false
var route_shape_id: String = "classic_ring"
var route_geometry_seed: int = 0
var placement_enabled: bool = false
var placement_action_allowed: bool = true
var selected_tile_id: String = ""
var selected_tile_display_name: String = ""
var selected_tile_zone: String = "any"
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
var _world_display_cache_shape_id: String = ""
var _world_display_cache_signature: String = ""
var _world_display_cache: Dictionary = {}

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

func configure(cells: Array, progress: float, tiles: Dictionary, fighting_cell: int, allow_placement: bool, tile_id: String, is_boss: bool = false, next_route_shape_id: String = "classic_ring", landscape_tiles: Dictionary = {}, is_elite: bool = false, placement_allowed: bool = true, next_route_geometry_seed: int = 0, discovered_cells: Dictionary = {}, tile_display_name: String = "", tile_zone: String = "any") -> void:
	var next_progress := maxf(0.0, progress)
	var safe_shape := next_route_shape_id if ["classic_ring", "deep_descent", "narrow_ring", "fractured_loop"].has(next_route_shape_id) else "classic_ring"
	var safe_geometry_seed := maxi(0, next_route_geometry_seed)
	var safe_tile_zone := tile_zone if tile_zone in ["any", "road", "roadside", "landscape"] else "any"
	var safe_tile_name := tile_display_name if not tile_display_name.is_empty() else tile_id
	var static_signature := str(cells.size()) + "|" + str(tiles.keys()) + "|" + str(landscape_tiles) + "|" + str(discovered_cells.keys()) + "|" + str(fighting_cell) + "|" + str(is_boss) + "|" + str(is_elite) + "|" + str(allow_placement) + "|" + str(placement_allowed) + "|" + tile_id + "|" + safe_tile_name + "|" + safe_tile_zone + "|" + safe_shape + "|" + str(safe_geometry_seed)
	var needs_redraw := static_signature != _last_static_signature or not is_equal_approx(next_progress, hero_progress)
	route_cells = cells
	hero_progress = next_progress
	placed_tiles = tiles
	world_tiles = landscape_tiles
	discovered_world_cells = discovered_cells
	combat_cell = fighting_cell
	boss_encounter = is_boss
	elite_encounter = is_elite
	placement_enabled = allow_placement
	placement_action_allowed = placement_allowed
	selected_tile_id = tile_id if allow_placement else ""
	selected_tile_display_name = safe_tile_name if allow_placement else ""
	selected_tile_zone = safe_tile_zone
	route_shape_id = safe_shape
	route_geometry_seed = safe_geometry_seed
	_last_static_signature = static_signature
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	# Retain the abyss artwork as a textured underpainting, then build the playable
	# map from square cells. Terrain and road are no longer stretched over an ellipse.
	var texture_size := Vector2(ABYSS_BACKDROP.get_width(), ABYSS_BACKDROP.get_height())
	var backdrop_scale := maxf(size.x / texture_size.x, size.y / texture_size.y)
	var backdrop_size := texture_size * backdrop_scale
	var backdrop_position := (size - backdrop_size) * 0.5
	draw_texture_rect(ABYSS_BACKDROP, Rect2(backdrop_position, backdrop_size), false, Color(0.86, 0.92, 0.83, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.03, 0.62 if high_contrast else 0.54), true)
	if route_cells.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(30, 40), Localization.text("route.empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c6d7d7"))
		return
	var count := route_cells.size()
	var route_geometry: Dictionary = _get_route_geometry()
	var cell_points: Array = route_geometry["points"]
	_draw_map_grid(route_geometry)
	_draw_world_field(route_geometry)
	# Draw a continuous square-tile road under its node markers. The perimeter has
	# exactly 34 cells for current runs; old snapshots with fewer nodes sample the
	# same physical loop without changing their saved route indices.
	_draw_road_tiles(route_geometry)
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
		draw_rect(Rect2(marker_rect.position + Vector2(2, 3), marker_rect.size), Color(0.0, 0.0, 0.0, 0.40), true)
		draw_rect(marker_rect, Color("#101f25"), true)
		draw_rect(marker_rect.grow(-2), fill, true)
		draw_rect(Rect2(marker_rect.position + Vector2(3, 3), Vector2(maxf(2.0, marker_size * 0.20), 2.0)), Color(0.92, 0.96, 0.76, 0.52), true)
		if high_contrast:
			draw_rect(marker_rect.grow(3.0), Color("#f4f8ee"), false, 2.0)
			draw_rect(marker_rect.grow(1.0), Color("#081319"), false, 1.5)
		draw_rect(marker_rect, Color("#f1f5e9") if high_contrast else Color("#263b37"), false, 2.0)
		var symbol_id := str(placed.get("id", base_kind))
		_draw_pixel_symbol(point + Vector2(0, -marker_size * 0.18), symbol_id)
		var route_target_is_valid := false
		if placement_enabled:
			var route_probe: Dictionary = {"id": selected_tile_id, "placement_zone": selected_tile_zone}
			var route_check: Dictionary = _placement_rules.can_place(route_cells, placed_tiles, i, route_probe)
			route_target_is_valid = bool(route_check.get("ok", false)) and placement_action_allowed
			if route_target_is_valid:
				var placement_color := _placement_target_color()
				placement_color.a = 0.72
				draw_rect(marker_rect.grow(2.0), placement_color, false, 1.5)
		var outline_growth := 2.0 if count >= 30 else 4.0
		if i == hovered_cell_index:
			var hover_color := Color("#a5b2a7")
			if placement_enabled:
				hover_color = Color("#8fe3a5") if route_target_is_valid else Color("#ec8a7d")
			draw_rect(marker_rect.grow(outline_growth), Color("#f7fff3") if high_contrast else hover_color, false, 2.0)
			if placement_enabled:
				var status_text := Localization.text("tile.route.status.valid") if route_target_is_valid else Localization.text("tile.route.status.invalid")
				var status_color := Color("#173c27") if route_target_is_valid else Color("#701f26")
				var status_rect := Rect2(marker_rect.position + Vector2(1, 1), Vector2(11, 11))
				draw_rect(status_rect, Color("#f4f8ee") if high_contrast else status_color, true)
				draw_rect(status_rect, Color("#071217") if high_contrast else Color("#f4f8ee"), false, 1.0)
				draw_string(ThemeDB.fallback_font, status_rect.position + Vector2(2, 9), status_text, HORIZONTAL_ALIGNMENT_CENTER, 7.0, 9, Color("#071217") if high_contrast else Color("#f4f8ee"))
		if i == combat_cell:
			var combat_color := Color("#c2a1ed") if boss_encounter else (Color("#e7c66f") if elite_encounter else Color("#f18a64"))
			draw_rect(marker_rect.grow(outline_growth), combat_color, false, 2.0)
			var badge_size := clampf(_map_cell_size() * 0.26, 6.0, 12.0)
			var badge_position := point + Vector2(marker_half - badge_size * 0.55, -marker_half - badge_size * 0.30)
			draw_rect(Rect2(badge_position, Vector2(badge_size, badge_size)), combat_color, true)
			var badge_text := "Б" if boss_encounter else ("Э" if elite_encounter else "!")
			draw_string(ThemeDB.fallback_font, badge_position + Vector2(1, badge_size - 1), badge_text, HORIZONTAL_ALIGNMENT_CENTER, badge_size - 1, 8, Color("#172329"))
		# Route indices and tile names are secondary; show them on focus, or
		# persistently only when high-contrast accessibility is enabled.
		if i == hovered_cell_index or high_contrast:
			var label := str(placed.get("short", i + 1)) if not placed.is_empty() else str(i + 1)
			var label_width := minf(marker_size - 3.0, 24.0 if count >= 30 else 30.0)
			var label_font_size := 5 if _map_cell_size() < 18.0 else (6 if _map_cell_size() < 26.0 else (7 if count >= 30 else (8 if not placed.is_empty() else 9)))
			var label_height := clampf(_map_cell_size() * 0.34, 5.0, 10.0)
			var label_rect := Rect2(Vector2(point.x - label_width * 0.5, point.y + _map_cell_size() * 0.05), Vector2(label_width, label_height))
			draw_rect(label_rect, Color("#f4f8ee") if high_contrast else Color("#09191d", 0.86), true)
			if high_contrast:
				draw_rect(label_rect, Color("#081319"), false, 1.0)
			var label_color := Color("#10191c") if high_contrast else Color("#f5f4e6")
			draw_string(ThemeDB.fallback_font, Vector2(label_rect.position.x, label_rect.position.y + minf(label_height - 1.0, float(label_font_size))), label, HORIZONTAL_ALIGNMENT_CENTER, label_width, label_font_size, label_color)
	# Hero interpolation still follows the same route indices that drive combat.
	var hero_point: Vector2 = _get_hero_grid_position(hero_progress, route_geometry)
	var hero_scale := clampf(_map_cell_size() / 30.0, 0.62, 1.15)
	# Original block-built explorer stays custom and is scaled with grid size.
	draw_rect(Rect2(hero_point + Vector2(-8, 4) * hero_scale, Vector2(17, 4) * hero_scale), Color(0.0, 0.0, 0.0, 0.42), true)
	draw_rect(Rect2(hero_point + Vector2(-7, -5) * hero_scale, Vector2(5, 8) * hero_scale), Color("#8b6646"), true)
	draw_rect(Rect2(hero_point + Vector2(-3, -7) * hero_scale, Vector2(7, 11) * hero_scale), Color("#a6c66e"), true)
	draw_rect(Rect2(hero_point + Vector2(-4, -13) * hero_scale, Vector2(9, 7) * hero_scale), Color("#dfbd73"), true)
	draw_rect(Rect2(hero_point + Vector2(-1, -11) * hero_scale, Vector2(3, 3) * hero_scale), Color("#253e42"), true)
	draw_rect(Rect2(hero_point + Vector2(6, -10) * hero_scale, Vector2(2, 14) * hero_scale), Color("#c7b48a"), true)
	draw_rect(Rect2(hero_point + Vector2(5, -11) * hero_scale, Vector2(4, 4) * hero_scale), Color("#f4d27e"), true)
	draw_rect(Rect2(hero_point + Vector2(6, -10) * hero_scale, Vector2(2, 2) * hero_scale), Color("#fff3b0"), true)
	var header_position := Vector2(14, 24)
	var header_text := (Localization.text("route.header.compact") if size.x < 680.0 else Localization.text("route.header")) % count
	var header_color := Color("#ffffff") if high_contrast else Color("#d2d9af")
	if high_contrast:
		draw_string(ThemeDB.fallback_font, header_position + Vector2(1, 1), header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#071217"))
	draw_string(ThemeDB.fallback_font, header_position, header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, header_color)
	var selected_text := Localization.text("route.placement") % selected_tile_display_name if placement_enabled else Localization.text("route.no_tiles")
	var footer_position := Vector2(14, size.y - 14)
	var footer_color := Color("#ffffff") if high_contrast else Color("#a8bd9e")
	if high_contrast:
		draw_string(ThemeDB.fallback_font, footer_position + Vector2(1, 1), selected_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, Color("#071217"))
	draw_string(ThemeDB.fallback_font, footer_position, selected_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, footer_color)
	_draw_discovery_status_hud(route_geometry)
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

func _draw_map_grid(route_geometry: Dictionary) -> void:
	var map_rect: Rect2 = route_geometry["map_rect"]
	var cell_size: float = route_geometry["cell_size"]
	var road_lookup: Dictionary = {}
	var roadside_lookup: Dictionary = {}
	var road_cells: Array = route_geometry.get("road_cells", [])
	for road_coord_value in road_cells:
		var road_coord: Vector2i = road_coord_value
		road_lookup["%d:%d" % [road_coord.x, road_coord.y]] = true
	for road_coord_value in road_cells:
		var road_coord: Vector2i = road_coord_value
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var adjacent: Vector2i = road_coord + offset
			if adjacent.x < 0 or adjacent.x >= MAP_COLUMNS or adjacent.y < 0 or adjacent.y >= MAP_ROWS:
				continue
			var adjacent_id := "%d:%d" % [adjacent.x, adjacent.y]
			if not road_lookup.has(adjacent_id):
				roadside_lookup[adjacent_id] = true
	for row in range(MAP_ROWS):
		for col in range(MAP_COLUMNS):
			var coord := Vector2i(col, row)
			var coord_id := "%d:%d" % [col, row]
			var cell_rect := Rect2(map_rect.position + Vector2(float(col), float(row)) * cell_size, Vector2.ONE * cell_size)
			var biome_index := _visual_biome_for_cell(col, row)
			var base := _terrain_color_for_biome(biome_index)
			# Subtle deterministic value variation breaks uniform blocks without introducing noisy flicker.
			var noise_value := float(posmod(col * 7 + row * 11 + posmod(route_geometry_seed, 31), 7) - 3) / 3.0
			base = base.lerp(Color("#10191b") if noise_value < 0.0 else Color("#d7dfbf"), absf(noise_value) * 0.055)
			if roadside_lookup.has(coord_id):
				base = base.lerp(Color("#c5b98c"), 0.08)
			base.a = 0.94
			draw_rect(cell_rect, base, true)
			_draw_terrain_cell_details(cell_rect, biome_index, col, row)
			if roadside_lookup.has(coord_id):
				_draw_roadside_edge(cell_rect, coord, road_lookup, cell_size)
			var tone := 0.0 if (col + row) % 2 == 0 else 0.025
			var grid_alpha := 0.20 if placement_enabled else 0.035
			draw_rect(cell_rect, Color("#9bb59a", grid_alpha + (tone if placement_enabled else tone * 0.15)) if not high_contrast else Color("#e3f1dc", 0.36), false, 1.25 if placement_enabled else 0.8)

func _visual_biome_for_cell(col: int, row: int) -> int:
	# Cosmetic biome regions only: gameplay placement and combat continue to use tile definitions.
	# A tiny seed-driven perturbation changes region boundaries while keeping the terrain deterministic.
	var centers := [Vector2(2.5, 2.3), Vector2(15.7, 2.6), Vector2(15.8, 10.7), Vector2(2.8, 10.4)]
	var best_index := 0
	var best_score := INF
	var point := Vector2(float(col), float(row))
	var small_seed := posmod(route_geometry_seed, 97)
	for candidate_index in range(centers.size()):
		var seed_shift := Vector2(
			float(posmod(small_seed + candidate_index * 3, 5) - 2) * 0.45,
			float(posmod(small_seed * 3 + candidate_index * 7, 5) - 2) * 0.32
		)
		var center: Vector2 = centers[candidate_index] + seed_shift
		var jitter := float(posmod(col * 17 + row * 29 + candidate_index * 13 + small_seed * 7, 11)) * 0.055
		var score := point.distance_squared_to(center) + jitter
		if score < best_score:
			best_score = score
			best_index = candidate_index
	return best_index

func _terrain_color_for_biome(biome_index: int) -> Color:
	match posmod(biome_index, 4):
		0: # Sporewood — damp moss, lichen and fungal earth.
			return Color("#314b39")
		1: # Crystal flats — cooler slate and teal minerals.
			return Color("#2f4850")
		2: # Bonefield — pale mineral soil and old remains.
			return Color("#4a493b")
		_: # Echo marsh — muted blue-violet ground.
			return Color("#38384d")

func _draw_terrain_cell_details(cell_rect: Rect2, biome_index: int, col: int, row: int) -> void:
	var cell_size := cell_rect.size.x
	if cell_size < 7.0:
		return
	var mark := posmod(col * 17 + row * 31 + posmod(route_geometry_seed, 97) * 7, 16)
	var origin := cell_rect.position
	var pixel := maxf(1.0, cell_size * 0.055)
	match posmod(biome_index, 4):
		0:
			if mark % 3 == 0:
				draw_circle(origin + Vector2(cell_size * 0.28, cell_size * 0.34), maxf(1.0, cell_size * 0.045), Color("#a0bd76", 0.28))
			if mark % 7 == 2:
				draw_rect(Rect2(origin + Vector2(cell_size * 0.61, cell_size * 0.66), Vector2(pixel * 2.4, pixel)), Color("#8aab6b", 0.24), true)
		1:
			if mark % 3 == 1:
				draw_line(origin + Vector2(cell_size * 0.30, cell_size * 0.66), origin + Vector2(cell_size * 0.43, cell_size * 0.42), Color("#85c6ca", 0.38), maxf(1.0, cell_size * 0.035))
			if mark % 5 == 0:
				draw_rect(Rect2(origin + Vector2(cell_size * 0.68, cell_size * 0.26), Vector2(pixel * 1.5, pixel * 2.0)), Color("#91c9cf", 0.28), true)
		2:
			if mark % 4 == 2:
				draw_rect(Rect2(origin + Vector2(cell_size * 0.24, cell_size * 0.62), Vector2(pixel * 2.5, pixel)), Color("#d5c8a4", 0.30), true)
			if mark % 7 == 3:
				draw_line(origin + Vector2(cell_size * 0.62, cell_size * 0.30), origin + Vector2(cell_size * 0.70, cell_size * 0.42), Color("#c7bb99", 0.25), pixel)
		_:
			if mark % 3 == 2:
				draw_circle(origin + Vector2(cell_size * 0.68, cell_size * 0.34), maxf(1.0, pixel * 1.1), Color("#8983bd", 0.30))
			if mark % 5 == 2:
				draw_line(origin + Vector2(cell_size * 0.23, cell_size * 0.70), origin + Vector2(cell_size * 0.34, cell_size * 0.62), Color("#7775a7", 0.28), pixel)

func _draw_roadside_edge(cell_rect: Rect2, coord: Vector2i, road_lookup: Dictionary, cell_size: float) -> void:
	# Mark only the edge touching the road. This communicates roadside eligibility without outlining every field tile.
	var inset := maxf(1.0, cell_size * 0.07)
	var line_width := maxf(1.0, cell_size * 0.035)
	var color := Color("#d6c48c", 0.44) if not high_contrast else Color("#f4f8ee", 0.78)
	var left_id := "%d:%d" % [coord.x - 1, coord.y]
	var right_id := "%d:%d" % [coord.x + 1, coord.y]
	var up_id := "%d:%d" % [coord.x, coord.y - 1]
	var down_id := "%d:%d" % [coord.x, coord.y + 1]
	if road_lookup.has(left_id):
		draw_line(cell_rect.position + Vector2(inset, inset), cell_rect.position + Vector2(inset, cell_size - inset), color, line_width)
	if road_lookup.has(right_id):
		draw_line(cell_rect.position + Vector2(cell_size - inset, inset), cell_rect.position + Vector2(cell_size - inset, cell_size - inset), color, line_width)
	if road_lookup.has(up_id):
		draw_line(cell_rect.position + Vector2(inset, inset), cell_rect.position + Vector2(cell_size - inset, inset), color, line_width)
	if road_lookup.has(down_id):
		draw_line(cell_rect.position + Vector2(inset, cell_size - inset), cell_rect.position + Vector2(cell_size - inset, cell_size - inset), color, line_width)

func _draw_road_tiles(route_geometry: Dictionary) -> void:
	var map_rect: Rect2 = route_geometry["map_rect"]
	var cell_size: float = route_geometry["cell_size"]
	var road_cells: Array = route_geometry["road_cells"]
	for slot in range(road_cells.size()):
		var coord: Vector2i = road_cells[slot]
		var tile_rect := Rect2(map_rect.position + Vector2(coord) * cell_size, Vector2.ONE * cell_size)
		draw_rect(Rect2(tile_rect.position + Vector2(cell_size * 0.08, cell_size * 0.10), tile_rect.size), Color(0.0, 0.0, 0.0, 0.30), true)
		draw_rect(tile_rect, Color("#182629"), true)
		var stone_rect := tile_rect.grow(-maxf(1.0, cell_size * 0.055))
		var stone := Color("#796d59") if slot % 4 == 0 else (Color("#887963") if slot % 3 == 0 else Color("#726956"))
		draw_rect(stone_rect, stone, true)
		draw_rect(stone_rect.grow(-maxf(1.0, cell_size * 0.10)), Color("#9d896b", 0.92), true)
		# Pixel cracks and moss stay aligned to the square tile, not a round path.
		if slot % 3 == 1:
			draw_rect(Rect2(tile_rect.position + Vector2(cell_size * 0.24, cell_size * 0.28), Vector2(maxf(2.0, cell_size * 0.22), maxf(1.0, cell_size * 0.06))), Color("#4d5b42"), true)
		if slot % 4 == 2:
			draw_rect(Rect2(tile_rect.position + Vector2(cell_size * 0.65, cell_size * 0.67), Vector2(maxf(1.0, cell_size * 0.08), maxf(1.0, cell_size * 0.08))), Color("#b7a17b", 0.65), true)
		draw_rect(tile_rect, Color("#d0b78d", 0.62) if high_contrast else Color("#473e32"), false, 1.5 if high_contrast else 1.0)

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

func _get_map_rect() -> Rect2:
	var usable := Vector2(maxf(1.0, size.x - 28.0), maxf(1.0, size.y - 64.0))
	var cell_size := minf(usable.x / float(MAP_COLUMNS), usable.y / float(MAP_ROWS))
	var map_size := Vector2(float(MAP_COLUMNS), float(MAP_ROWS)) * cell_size
	return Rect2((size - map_size) * 0.5, map_size)

func _map_cell_size() -> float:
	var usable := Vector2(maxf(1.0, size.x - 28.0), maxf(1.0, size.y - 64.0))
	return maxf(1.0, minf(usable.x / float(MAP_COLUMNS), usable.y / float(MAP_ROWS)))

func _get_road_grid_coordinates() -> Array[Vector2i]:
	# All map systems query TileSystem's shared contour. The seed is deterministic
	# for new runs and zero for legacy snapshots that must keep their old geometry.
	var result: Array[Vector2i] = TileSystemScript.get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed)
	return result

func _get_world_display_cell_map(road_cells: Array) -> Dictionary:
	# Preserve positions of old saved tiles, but expose the full modern board as
	# 232 distinct off-road cells. New IDs use m:col:row; legacy IDs remain valid.
	var legacy_occupied: Array[String] = []
	for legacy_id_value in TileSystemScript.WORLD_FIELD_KEYS:
		var legacy_id := str(legacy_id_value)
		if world_tiles.has(legacy_id):
			legacy_occupied.append(legacy_id)
	var signature_parts: Array[String] = [route_shape_id, str(route_geometry_seed)]
	signature_parts.append_array(legacy_occupied)
	var cache_signature := "|".join(signature_parts)
	if _world_display_cache_signature == cache_signature and not _world_display_cache.is_empty():
		return _world_display_cache

	var blocked: Dictionary = {}
	for road_coord_value in road_cells:
		var road_coord: Vector2i = road_coord_value
		blocked["%d:%d" % [road_coord.x, road_coord.y]] = true

	# Recreate the Stage 84 nearest-free projection in its original stable order.
	# The projection is computed for all legacy keys so their old relative positions
	# do not shift when a save contains only some of the former 80 placements.
	var used: Dictionary = {}
	var legacy_projection: Dictionary = {}
	for key_value in TileSystemScript.WORLD_FIELD_KEYS:
		var key := str(key_value)
		var parts := key.split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var col := int(parts[0])
		var row := int(parts[1])
		var preferred := Vector2(
			clampf((float(col) + 0.5) * float(MAP_COLUMNS) / float(FIELD_COLUMNS) - 0.5, 0.0, float(MAP_COLUMNS - 1)),
			clampf((float(row) + 0.5) * float(MAP_ROWS) / float(FIELD_ROWS) - 0.5, 0.0, float(MAP_ROWS - 1))
		)
		var best_coord := Vector2i(-1, -1)
		var best_cost := INF
		for candidate_row in range(MAP_ROWS):
			for candidate_col in range(MAP_COLUMNS):
				var candidate := Vector2i(candidate_col, candidate_row)
				var candidate_id := "%d:%d" % [candidate.x, candidate.y]
				if blocked.has(candidate_id) or used.has(candidate_id):
					continue
				var cost := Vector2(candidate).distance_squared_to(preferred)
				cost += float((candidate_row * MAP_COLUMNS + candidate_col) % 7) * 0.0001
				if cost < best_cost:
					best_cost = cost
					best_coord = candidate
		if best_coord.x >= 0:
			var best_id := "%d:%d" % [best_coord.x, best_coord.y]
			used[best_id] = true
			legacy_projection[key] = best_coord

	var result: Dictionary = {}
	var occupied_legacy_positions: Dictionary = {}
	for legacy_id in legacy_occupied:
		if legacy_projection.has(legacy_id):
			var legacy_coord: Vector2i = legacy_projection[legacy_id]
			var pos_id := "%d:%d" % [legacy_coord.x, legacy_coord.y]
			occupied_legacy_positions[pos_id] = true
			result[legacy_id] = legacy_coord

	for row in range(MAP_ROWS):
		for col in range(MAP_COLUMNS):
			var coord := Vector2i(col, row)
			var coord_id := "%d:%d" % [col, row]
			if blocked.has(coord_id) or occupied_legacy_positions.has(coord_id):
				continue
			result[TileSystemScript.map_world_cell_id(col, row)] = coord

	_world_display_cache_shape_id = route_shape_id
	_world_display_cache_signature = cache_signature
	_world_display_cache = result.duplicate(true)
	return _world_display_cache
func _field_cell_rect(cell_id: String) -> Rect2:
	var geometry: Dictionary = _get_route_geometry()
	var display_map: Dictionary = geometry.get("world_display_cells", {})
	if not display_map.has(cell_id):
		return Rect2()
	var coord: Vector2i = display_map[cell_id]
	var map_rect: Rect2 = geometry["map_rect"]
	var cell_size: float = geometry["cell_size"]
	return Rect2(map_rect.position + Vector2(coord) * cell_size, Vector2.ONE * cell_size)

func _find_world_cell(position: Vector2) -> String:
	# Road placement has priority. A square road tile cannot accidentally be
	# interpreted as a landscape target, even when its visual bounds touch.
	if _find_closest_cell(position) >= 0 or _is_near_route_line(position):
		return ""
	var geometry: Dictionary = _get_route_geometry()
	var display_map: Dictionary = geometry.get("world_display_cells", {})
	for cell_id_value in display_map.keys():
		var cell_id := str(cell_id_value)
		if _field_cell_rect_from_geometry(cell_id, geometry).grow(-2.0).has_point(position):
			return cell_id
	return ""

func _field_cell_rect_from_geometry(cell_id: String, geometry: Dictionary) -> Rect2:
	var display_map: Dictionary = geometry.get("world_display_cells", {})
	if not display_map.has(cell_id):
		return Rect2()
	var coord: Vector2i = display_map[cell_id]
	var map_rect: Rect2 = geometry["map_rect"]
	var cell_size: float = geometry["cell_size"]
	return Rect2(map_rect.position + Vector2(coord) * cell_size, Vector2.ONE * cell_size)

func _is_near_route_line(position: Vector2) -> bool:
	var geometry: Dictionary = _get_route_geometry()
	var map_rect: Rect2 = geometry["map_rect"]
	var cell_size: float = geometry["cell_size"]
	var road_cells: Array = geometry["road_cells"]
	for index in range(road_cells.size()):
		var from_coord: Vector2i = road_cells[index]
		var to_coord: Vector2i = road_cells[(index + 1) % road_cells.size()]
		var from_point := map_rect.position + (Vector2(from_coord) + Vector2(0.5, 0.5)) * cell_size
		var to_point := map_rect.position + (Vector2(to_coord) + Vector2(0.5, 0.5)) * cell_size
		var nearest_point: Vector2 = Geometry2D.get_closest_point_to_segment(position, from_point, to_point)
		if nearest_point.distance_to(position) <= cell_size * 0.46:
			return true
	return false

func _get_hero_grid_position(progress: float, geometry: Dictionary) -> Vector2:
	# For older saves whose logical route has fewer than 34 nodes, walk along the
	# intervening square road tiles instead of cutting diagonally across the board.
	var road_cells: Array = geometry["road_cells"]
	var map_rect: Rect2 = geometry["map_rect"]
	var cell_size: float = geometry["cell_size"]
	if road_cells.is_empty() or route_cells.is_empty():
		return size * 0.5
	var physical_progress := maxf(0.0, progress) * float(road_cells.size()) / float(route_cells.size())
	var whole_slot := int(floor(physical_progress))
	var fraction := 0.0 if reduced_motion else clampf(physical_progress - floor(physical_progress), 0.0, 1.0)
	var from_coord: Vector2i = road_cells[posmod(whole_slot, road_cells.size())]
	var to_coord: Vector2i = road_cells[posmod(whole_slot + 1, road_cells.size())]
	var from_point := map_rect.position + (Vector2(from_coord) + Vector2(0.5, 0.5)) * cell_size
	var to_point := map_rect.position + (Vector2(to_coord) + Vector2(0.5, 0.5)) * cell_size
	return from_point.lerp(to_point, fraction)

func _draw_world_field(route_geometry: Dictionary) -> void:
	var map_rect: Rect2 = route_geometry["map_rect"]
	var cell_size: float = route_geometry["cell_size"]
	var display_map: Dictionary = route_geometry.get("world_display_cells", {})
	for cell_id_value in display_map.keys():
		var cell_id := str(cell_id_value)
		var coord: Vector2i = display_map[cell_id]
		var cell_rect := Rect2(map_rect.position + Vector2(coord) * cell_size, Vector2.ONE * cell_size)
		var inset := maxf(2.0, cell_size * 0.08)
		var tile_rect := cell_rect.grow(-inset)
		var tile: Dictionary = world_tiles.get(cell_id, {})
		if tile.is_empty():
			var map_cell_id := TileSystemScript.map_world_cell_id(coord.x, coord.y)
			var is_discovered := discovered_world_cells.has(map_cell_id)
			var placement_probe: Dictionary = {"id": selected_tile_id, "placement_zone": selected_tile_zone} if not selected_tile_id.is_empty() else {}
			var world_check: Dictionary = _placement_rules.can_place_world(route_cells, world_tiles, cell_id, placement_probe, route_shape_id, route_geometry_seed) if placement_enabled else {"ok": true}
			var world_target_is_valid := placement_enabled and placement_action_allowed and bool(world_check.get("ok", false))
			var base := Color("#253c32", 0.30)
			var outline := Color("#b6d2a0", 0.18)
			if placement_enabled and world_target_is_valid:
				var target_color := _placement_target_color()
				base = Color(target_color.r, target_color.g, target_color.b, 0.22)
				outline = Color(target_color.r, target_color.g, target_color.b, 0.78)
			elif placement_enabled:
				# Ineligible cells remain quiet; the hovered cell carries the explicit rejection.
				base = Color("#253c32", 0.22)
				outline = Color("#82938a", 0.28)
			if not is_discovered:
				if placement_enabled:
					# Preserve readable valid/invalid preview while strongly muting the unknown biome.
					base = base.lerp(Color("#101b20"), 0.58)
					outline = Color("#b3c6b6", 0.72) if not high_contrast else Color("#f4f8ee", 0.92)
				else:
					# The fog is nearly opaque so hidden terrain details cannot leak through.
					base = Color("#09161b", 0.98)
					outline = Color("#71847e", 0.92) if not high_contrast else Color("#f4f8ee", 0.96)
			if cell_id == hovered_world_cell_id:
				if placement_enabled and not world_target_is_valid:
					base = Color("#c96562", 0.42)
					outline = Color("#ed9d91", 1.0)
				elif placement_enabled:
					var hover_color := _placement_target_color()
					base = Color(hover_color.r, hover_color.g, hover_color.b, 0.46)
					outline = Color(hover_color.r, hover_color.g, hover_color.b, 1.0)
				else:
					base = base.lerp(Color("#b9c8b4"), 0.08)
					outline = Color("#aebeb3", 0.70)
			draw_rect(tile_rect, base, true)
			if not is_discovered:
				_draw_unknown_cell_fog(tile_rect, coord, cell_size, cell_id == hovered_world_cell_id)
			var outline_width := 1.0
			if placement_enabled and world_target_is_valid:
				outline_width = 1.35
			if cell_id == hovered_world_cell_id:
				outline_width = 2.0
			draw_rect(tile_rect, Color("#f4f8ee") if high_contrast else outline, false, outline_width)
			var center := tile_rect.get_center()
			if cell_id == hovered_world_cell_id and placement_enabled:
				_draw_placement_preview_corners(tile_rect.grow(-1.0), Color("#f4f8ee") if high_contrast else outline)
			if placement_enabled and cell_id == hovered_world_cell_id:
				var status_text := Localization.text("tile.route.status.valid") if world_target_is_valid else Localization.text("tile.route.status.invalid")
				var status_color := Color("#173c27") if world_target_is_valid else Color("#701f26")
				var status_size := clampf(cell_size * 0.48, 8.0, 12.0)
				var status_rect := Rect2(center - Vector2.ONE * status_size * 0.5, Vector2.ONE * status_size)
				draw_rect(status_rect, Color("#f4f8ee") if high_contrast else status_color, true)
				draw_rect(status_rect, Color("#071217") if high_contrast else Color("#f4f8ee", 0.94), false, 1.0)
				var compact_status := ("+" if world_target_is_valid else "X") if cell_size < 20.0 else status_text
				var status_font_size := 7 if cell_size < 20.0 else (8 if cell_size < 28.0 else 9)
				draw_string(ThemeDB.fallback_font, center + Vector2(-status_size * 0.45, status_font_size * 0.34), compact_status, HORIZONTAL_ALIGNMENT_CENTER, status_size * 0.9, status_font_size, Color("#071217") if high_contrast else Color("#f4f8ee"))
		else:
			var fill := Color(str(tile.get("color", "#788a67")))
			draw_rect(Rect2(tile_rect.position + Vector2(2, 3), tile_rect.size), Color(0.0, 0.0, 0.0, 0.38), true)
			draw_rect(tile_rect, fill, true)
			if high_contrast:
				draw_rect(tile_rect.grow(2.0), Color("#f4f8ee"), false, 2.0)
				draw_rect(tile_rect.grow(1.0), Color("#081319"), false, 1.5)
			else:
				draw_rect(tile_rect, Color("#172a25"), false, 2.0)
			_draw_pixel_symbol(tile_rect.get_center() + Vector2(0, -cell_size * 0.10), str(tile.get("id", "")))
			# Keep landscape labels available on focus and in high-contrast mode only.
			if cell_id == hovered_world_cell_id or high_contrast:
				var label_height := clampf(cell_size * 0.22, 6.0, 10.0)
				var world_label_rect := Rect2(tile_rect.position + Vector2(1.0, tile_rect.size.y - label_height), Vector2(maxf(1.0, tile_rect.size.x - 2.0), label_height))
				draw_rect(world_label_rect, Color("#f4f8ee") if high_contrast else Color("#071619", 0.88), true)
				draw_string(ThemeDB.fallback_font, Vector2(world_label_rect.position.x, world_label_rect.end.y - 1.0), str(tile.get("short", Localization.text("route.tile.short"))), HORIZONTAL_ALIGNMENT_CENTER, world_label_rect.size.x, 6 if cell_size < 24.0 else 7, Color("#10191c") if high_contrast else Color("#f5f4e6"))
			if cell_id == hovered_world_cell_id and placement_enabled:
				draw_rect(tile_rect.grow(2.0), Color("#ec8a7d") if not world_target_is_valid else _placement_target_color(), false, 2.0)

func _placement_target_color() -> Color:
	match selected_tile_zone:
		"roadside":
			return Color("#b4a56f") # restrained amber: cells directly beside the road
		"landscape":
			return Color("#79aa97") # muted teal: deeper landscape cells
		"road":
			return Color("#98b97d")
		_:
			return Color("#8eb883")

func _draw_discovery_status_hud(route_geometry: Dictionary) -> void:
	# A compact map status is kept outside the tile board so that it never covers
	# road/landscape hit targets, including phone-sized layouts.
	var road_lookup: Dictionary = {}
	var road_cells: Array = route_geometry.get("road_cells", [])
	for road_value in road_cells:
		var road_coord: Vector2i = road_value
		road_lookup["%d:%d" % [road_coord.x, road_coord.y]] = true
	var discovered_count := 0
	for key_value in discovered_world_cells.keys():
		var cell_id := str(key_value)
		if not bool(discovered_world_cells[key_value]) or not TileSystemScript.is_map_world_cell_id(cell_id):
			continue
		var coord: Vector2i = TileSystemScript.world_cell_coordinates(cell_id)
		if not road_lookup.has("%d:%d" % [coord.x, coord.y]):
			discovered_count += 1
	var total_world_cells := maxi(0, MAP_COLUMNS * MAP_ROWS - road_cells.size())
	var label := Localization.text("route.discovery.count") % [mini(discovered_count, total_world_cells), total_world_cells]
	var pill_width := minf(148.0, maxf(112.0, size.x - 24.0))
	var pill_rect := Rect2(Vector2(size.x - pill_width - 12.0, 9.0), Vector2(pill_width, 18.0))
	draw_rect(pill_rect, Color("#071419", 0.96), true)
	draw_rect(pill_rect, Color("#f4f8ee", 0.95) if high_contrast else Color("#9eafa1", 0.92), false, 1.0)
	var font_size := 8 if size.x < 480.0 else 9
	var text_color := Color("#071217") if high_contrast else Color("#e4eddd")
	draw_string(ThemeDB.fallback_font, Vector2(pill_rect.position.x + 4.0, pill_rect.position.y + 10.5), label, HORIZONTAL_ALIGNMENT_CENTER, pill_width - 8.0, font_size, text_color)

func _draw_unknown_cell_fog(tile_rect: Rect2, coord: Vector2i, cell_size: float, emphasized: bool) -> void:
	# Opaque fog hides biome texture; deterministic sparse marks keep the unknown
	# state perceptible at tiny sizes without making every cell visually noisy.
	var color := Color("#82958e", 0.28) if not high_contrast else Color("#eef7eb", 0.62)
	var origin := tile_rect.position
	var mark := posmod(coord.x * 13 + coord.y * 17 + posmod(route_geometry_seed, 97), 5)
	var pixel := maxf(1.0, cell_size * 0.055)
	if mark % 2 == 0:
		draw_line(origin + Vector2(cell_size * 0.22, cell_size * 0.24), origin + Vector2(cell_size * 0.39, cell_size * 0.41), color, pixel, true)
	if mark % 3 == 1:
		draw_rect(Rect2(origin + Vector2(cell_size * 0.62, cell_size * 0.65), Vector2(pixel * 1.8, pixel)), color, true)
	if not placement_enabled and cell_size >= 13.0:
		var font_size := 6 if cell_size < 16.0 else (7 if cell_size < 24.0 else 10)
		var glyph_color := Color("#eef7eb") if high_contrast else Color("#a3b6ac")
		if emphasized:
			glyph_color = Color("#ffffff") if high_contrast else Color("#d5e5da")
		var center := tile_rect.get_center()
		draw_string(ThemeDB.fallback_font, center + Vector2(-3.0, font_size * 0.36), "?", HORIZONTAL_ALIGNMENT_CENTER, 7.0, font_size, glyph_color)
	elif placement_enabled and cell_size >= 20.0:
		draw_string(ThemeDB.fallback_font, origin + Vector2(2.0, 8.0), "?", HORIZONTAL_ALIGNMENT_LEFT, 7.0, 7, Color("#c8d6ce", 0.88))

func _draw_placement_preview_corners(rect: Rect2, color: Color) -> void:
	# Preview targets use corner brackets; a committed tile is a solid filled square.
	var length := minf(6.0, minf(rect.size.x, rect.size.y) * 0.28)
	if length < 2.0:
		return
	var p := rect.position
	var e := rect.end
	draw_line(p, p + Vector2(length, 0), color, 2.0, true)
	draw_line(p, p + Vector2(0, length), color, 2.0, true)
	draw_line(Vector2(e.x, p.y), Vector2(e.x - length, p.y), color, 2.0, true)
	draw_line(Vector2(e.x, p.y), Vector2(e.x, p.y + length), color, 2.0, true)
	draw_line(Vector2(p.x, e.y), Vector2(p.x + length, e.y), color, 2.0, true)
	draw_line(Vector2(p.x, e.y), Vector2(p.x, e.y - length), color, 2.0, true)
	draw_line(e, e - Vector2(length, 0), color, 2.0, true)
	draw_line(e, e - Vector2(0, length), color, 2.0, true)

func _get_route_geometry() -> Dictionary:
	# The map uses a discrete square-cell perimeter. Drawing, hover, clicking and
	# landscape placement all consume this same geometry object.
	var road_cells := _get_road_grid_coordinates()
	var cell_size := _map_cell_size()
	var map_rect := _get_map_rect()
	var points: Array[Vector2] = []
	var slot_indices: Array[int] = []
	var count := route_cells.size()
	if count > 0:
		for i in range(count):
			var slot := posmod(roundi(float(i) * float(road_cells.size()) / float(count)), road_cells.size())
			var coord: Vector2i = road_cells[slot]
			points.append(map_rect.position + (Vector2(coord) + Vector2(0.5, 0.5)) * cell_size)
			slot_indices.append(slot)
	var min_x := map_rect.end.x
	var max_x := map_rect.position.x
	var min_y := map_rect.end.y
	var max_y := map_rect.position.y
	for point in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var center := (Vector2(min_x, min_y) + Vector2(max_x, max_y)) * 0.5
	var display_map := _get_world_display_cell_map(road_cells)
	return {"center": center, "radius_x": (max_x - min_x) * 0.5, "radius_y": (max_y - min_y) * 0.5, "points": points, "road_cells": road_cells, "slot_indices": slot_indices, "map_rect": map_rect, "cell_size": cell_size, "world_display_cells": display_map}

func _route_marker_size() -> float:
	# Keep the placement/encounter badge inset in its square road cell.
	return clampf(_map_cell_size() * 0.74, 12.0, 34.0)

func _route_hit_radius() -> float:
	return clampf(_map_cell_size() * 0.38, 5.0, 18.0)

func _find_closest_cell(position: Vector2) -> int:
	if route_cells.is_empty():
		return -1
	var geometry: Dictionary = _get_route_geometry()
	var map_rect: Rect2 = geometry["map_rect"]
	var cell_size: float = geometry["cell_size"]
	# Any click inside a square road tile selects the logical route node mapped to
	# that tile. This is the whole-tile hitbox, not only a circular marker center.
	if map_rect.has_point(position):
		var col := clampi(int(floor((position.x - map_rect.position.x) / cell_size)), 0, MAP_COLUMNS - 1)
		var row := clampi(int(floor((position.y - map_rect.position.y) / cell_size)), 0, MAP_ROWS - 1)
		var coord := Vector2i(col, row)
		var road_cells: Array = geometry["road_cells"]
		var slot := road_cells.find(coord)
		if slot >= 0:
			var slot_indices: Array = geometry["slot_indices"]
			var best_index := -1
			var best_gap := 999999
			for route_index in range(slot_indices.size()):
				var gap := absi(int(slot_indices[route_index]) - slot)
				gap = mini(gap, road_cells.size() - gap)
				if gap < best_gap:
					best_gap = gap
					best_index = route_index
			return best_index
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
		"echo_spring":
			draw_rect(Rect2(center + Vector2(-3, -5), Vector2(6, 10)), Color("#d9fff0"), true)
			draw_rect(Rect2(center + Vector2(-5, -1), Vector2(10, 3)), Color("#438e89"), true)
		"fault_line":
			draw_rect(Rect2(center + Vector2(-4, -5), Vector2(3, 4)), Color("#ffd3e8"), true)
			draw_rect(Rect2(center + Vector2(-1, -1), Vector2(3, 4)), Color("#ffd3e8"), true)
			draw_rect(Rect2(center + Vector2(2, 2), Vector2(3, 3)), Color("#7c3b65"), true)
		"spore_garden":
			for spore_x in [-4.0, 0.0, 4.0]:
				draw_rect(Rect2(center + Vector2(spore_x - 1.0, -4.0), Vector2(3, 4)), Color("#dcf6a3"), true)
				draw_rect(Rect2(center + Vector2(spore_x, 0), Vector2(2, 5)), Color("#507b48"), true)
		"crystal_hive":
			draw_rect(Rect2(center + Vector2(-5, -2), Vector2(4, 6)), Color("#d6f3ff"), true)
			draw_rect(Rect2(center + Vector2(-1, -6), Vector2(4, 10)), Color("#91d7ef"), true)
			draw_rect(Rect2(center + Vector2(3, -1), Vector2(3, 5)), Color("#d6f3ff"), true)
		"bone_orchard":
			draw_rect(Rect2(center + Vector2(-1, -5), Vector2(3, 10)), Color("#f7e7c9"), true)
			draw_rect(Rect2(center + Vector2(-4, -4), Vector2(8, 3)), Color("#f7e7c9"), true)
			draw_rect(Rect2(center + Vector2(-4, 2), Vector2(8, 3)), Color("#a89a80"), true)
		"echo_obelisk":
			draw_rect(Rect2(center + Vector2(-3, -5), Vector2(6, 10)), Color("#eaddff"), true)
			draw_rect(Rect2(center + Vector2(-1, -7), Vector2(2, 2)), Color("#ac8bd7"), true)
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

