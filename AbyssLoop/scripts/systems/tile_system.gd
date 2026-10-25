extends RefCounted
class_name TileSystem

const ResourceSystemScript = preload("res://scripts/systems/resource_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const WORLD_FIELD_COLUMNS := 10
const WORLD_FIELD_ROWS := 8
const MAP_COLUMNS := 19
const MAP_ROWS := 14
const ROAD_CELL_COUNT := 34
const WORLD_FIELD_KEYS := [
    "0:0", "1:0", "2:0", "7:0", "8:0", "9:0", "0:1", "9:1",
    "0:2", "4:2", "5:2", "3:3", "4:3", "5:3", "6:3", "2:4",
    "3:4", "4:4", "5:4", "6:4", "7:4", "3:5", "4:5", "5:5",
    "6:5", "0:6", "9:6", "0:7", "1:7", "2:7", "7:7", "8:7",
    "9:7", "3:0", "4:0", "5:0", "6:0", "1:1", "2:1", "3:1",
    "4:1", "5:1", "6:1", "7:1", "8:1", "1:2", "2:2", "3:2",
    "6:2", "7:2", "8:2", "9:2", "0:3", "1:3", "2:3", "7:3",
    "8:3", "9:3", "0:4", "1:4", "8:4", "9:4", "0:5", "1:5",
    "2:5", "7:5", "8:5", "9:5", "1:6", "2:6", "3:6", "4:6",
    "5:6", "6:6", "7:6", "8:6", "3:7", "4:7", "5:7", "6:7"
]
const MAX_WORLD_TILES_PER_ROUTE_SECTOR := 2
# Common route cards should shape a build; rare high-risk cards remain discoveries,
# not one third of every late-run hand.
const TILE_DRAW_WEIGHTS := {
    "cache": 2.2,
    "hunt": 1.4,
    "ward": 2.0,
    "snare": 1.8,
    "rift": 0.35,
    "signal": 0.45,
    "archive": 0.35,
    "nursery": 0.30,
    "echo_spring": 1.15,
    "fault_line": 0.38,
    "spore_garden": 0.28,
    "crystal_hive": 0.24,
    "bone_orchard": 0.26,
    "echo_obelisk": 0.22,
    "lost_convoy": 0.28,
    "hunter_marker": 0.30
}
# Caps are applied to all synergies triggered during one route-sector visit.
# Keep the caps data-driven and shared by preview and actual expedition visits.
const WORLD_SYNERGY_LIMITS := {
    "scrap": [0, 12],
    "heal": [0, 12],
    "reward": [-0.25, 0.50],
    "spawn_bonus": [-0.35, 0.75],
    "enemy_bonus": [-0.15, 0.35]
}
# Final modifier caps are applied after route-node, local-tile, equipment/perk,
# and landscape-neighbor contributions have been accumulated for this visit.
const VISIT_MODIFIER_LIMITS := {
    "spawn_bonus": [-0.50, 1.00],
    "enemy_bonus": [-0.35, 0.75],
    "reward_bonus": [-0.50, 1.50]
}
var resource_system = ResourceSystemScript.new()
var inventory_system = InventorySystemScript.new()

static func world_cell_id(col: int, row: int) -> String:
    # Legacy IDs remain unchanged for saves created before Stage 85.
    return "%d:%d" % [col, row]

static func map_world_cell_id(col: int, row: int) -> String:
    # New IDs are explicitly namespaced so map-grid coordinates never collide
    # with legacy 10x8 field coordinates.
    return "m:%d:%d" % [col, row]

static func is_map_world_cell_id(cell_id: String) -> bool:
    var parts := cell_id.split(":")
    return parts.size() == 3 and parts[0] == "m" and parts[1].is_valid_int() and parts[2].is_valid_int() and int(parts[1]) >= 0 and int(parts[1]) < MAP_COLUMNS and int(parts[2]) >= 0 and int(parts[2]) < MAP_ROWS

static func world_cell_coordinates(cell_id: String) -> Vector2i:
    if is_map_world_cell_id(cell_id):
        var map_parts := cell_id.split(":")
        return Vector2i(int(map_parts[1]), int(map_parts[2]))
    if WORLD_FIELD_KEYS.has(cell_id):
        var legacy_parts := cell_id.split(":")
        if legacy_parts.size() == 2 and legacy_parts[0].is_valid_int() and legacy_parts[1].is_valid_int():
            return Vector2i(int(legacy_parts[0]), int(legacy_parts[1]))
    return Vector2i(-1, -1)

static func is_world_cell_valid(cell_id: String) -> bool:
    return WORLD_FIELD_KEYS.has(cell_id) or is_map_world_cell_id(cell_id)

static func world_cell_neighbors(cell_id: String) -> Array[String]:
    var result: Array[String] = []
    var coord := world_cell_coordinates(cell_id)
    if coord.x < 0 or coord.y < 0:
        return result
    var map_id := is_map_world_cell_id(cell_id)
    for pos in [Vector2i(coord.x - 1, coord.y), Vector2i(coord.x + 1, coord.y), Vector2i(coord.x, coord.y - 1), Vector2i(coord.x, coord.y + 1)]:
        var neighbor_id := map_world_cell_id(pos.x, pos.y) if map_id else world_cell_id(pos.x, pos.y)
        if is_world_cell_valid(neighbor_id) and not result.has(neighbor_id):
            result.append(neighbor_id)
    return result

static func get_road_grid_coordinates(route_shape_id: String = "classic_ring") -> Array[Vector2i]:
    var bounds := {"x": 4, "y": 3, "w": 11, "h": 8}
    match route_shape_id:
        "narrow_ring": bounds = {"x": 5, "y": 2, "w": 9, "h": 10}
        "deep_descent": bounds = {"x": 4, "y": 2, "w": 10, "h": 9}
        "fractured_loop": bounds = {"x": 3, "y": 4, "w": 13, "h": 6}
    var left := int(bounds["x"])
    var top := int(bounds["y"])
    var right := left + int(bounds["w"]) - 1
    var bottom := top + int(bounds["h"]) - 1
    var result: Array[Vector2i] = []
    for col in range(left, right + 1):
        result.append(Vector2i(col, top))
    for row in range(top + 1, bottom + 1):
        result.append(Vector2i(right, row))
    for col in range(right - 1, left - 1, -1):
        result.append(Vector2i(col, bottom))
    for row in range(bottom - 1, top, -1):
        result.append(Vector2i(left, row))
    return result

# Stage 86: legacy callers keep the original fixed rectangular contour. New runs
# pass a positive route_geometry_seed to get the deterministic procedural contour.
static func get_road_grid_coordinates_for_seed(route_shape_id: String = "classic_ring", route_geometry_seed: int = 0) -> Array[Vector2i]:
    if route_geometry_seed <= 0:
        return get_road_grid_coordinates(route_shape_id)
    return _get_procedural_road_grid_coordinates(route_shape_id, route_geometry_seed)

static func _build_rectangular_contour(left: int, top: int, horizontal_span: int, vertical_span: int) -> Array[Vector2i]:
    var right := left + horizontal_span
    var bottom := top + vertical_span
    var result: Array[Vector2i] = []
    for col in range(left, right + 1):
        result.append(Vector2i(col, top))
    for row in range(top + 1, bottom + 1):
        result.append(Vector2i(right, row))
    for col in range(right - 1, left - 1, -1):
        result.append(Vector2i(col, bottom))
    for row in range(bottom - 1, top, -1):
        result.append(Vector2i(left, row))
    return result

static func _get_procedural_road_grid_coordinates(route_shape_id: String, route_geometry_seed: int) -> Array[Vector2i]:
    # Route families preserve their recognisable footprint, but each seed chooses
    # a bounded outline deformation. The perimeter budget stays exactly 34 cells.
    var shape_mode := posmod(route_geometry_seed, 4)
    var horizontal_span := 9
    var vertical_span := 6
    match route_shape_id:
        "narrow_ring":
            match shape_mode:
                0, 1:
                    horizontal_span = 7
                    vertical_span = 8
                2:
                    horizontal_span = 7
                    vertical_span = 9
                _:
                    horizontal_span = 6
                    vertical_span = 8
        "deep_descent":
            match shape_mode:
                0, 1:
                    horizontal_span = 8
                    vertical_span = 7
                2:
                    horizontal_span = 8
                    vertical_span = 8
                _:
                    horizontal_span = 7
                    vertical_span = 7
        "fractured_loop":
            match shape_mode:
                0, 1:
                    horizontal_span = 10
                    vertical_span = 5
                2:
                    horizontal_span = 11
                    vertical_span = 5
                _:
                    horizontal_span = 9
                    vertical_span = 5
        _:
            match shape_mode:
                0, 1:
                    horizontal_span = 9
                    vertical_span = 6
                2:
                    horizontal_span = 10
                    vertical_span = 6
                _:
                    horizontal_span = 8
                    vertical_span = 6

    var bump_depths: Array[int] = []
    match shape_mode:
        0:
            bump_depths = [1, 1] # 30-cell base contour plus two shallow outward detours.
        1:
            bump_depths = [2] # One deeper outward detour adds four cells.
        2:
            bump_depths = [1] # 32-cell base contour plus one outward detour.
        _:
            bump_depths = [1, 1, 1] # 28-cell base contour plus three outward detours.

    var left := int((MAP_COLUMNS - (horizontal_span + 1)) / 2)
    var top := int((MAP_ROWS - (vertical_span + 1)) / 2)
    var base := _build_rectangular_contour(left, top, horizontal_span, vertical_span)
    var rng := RandomNumberGenerator.new()
    var shape_salt := 104729
    match route_shape_id:
        "narrow_ring": shape_salt = 130363
        "deep_descent": shape_salt = 155921
        "fractured_loop": shape_salt = 196613
    rng.seed = route_geometry_seed ^ shape_salt

    var candidates: Array[int] = []
    for edge_index in range(base.size()):
        if not _contour_edge_is_internal(base, edge_index, horizontal_span, vertical_span):
            continue
        if not _contour_bump_fits(base, edge_index, bump_depths[0]):
            continue
        candidates.append(edge_index)
    var selected_edges: Array[int] = []
    while not candidates.is_empty() and selected_edges.size() < bump_depths.size():
        var picked_position := rng.randi_range(0, candidates.size() - 1)
        var candidate_edge: int = candidates[picked_position]
        candidates.remove_at(picked_position)
        var spaced := true
        for selected_edge in selected_edges:
            var distance := absi(candidate_edge - selected_edge)
            distance = mini(distance, base.size() - distance)
            if distance < 4:
                spaced = false
                break
        if spaced:
            selected_edges.append(candidate_edge)

    if selected_edges.size() != bump_depths.size():
        return get_road_grid_coordinates(route_shape_id)

    var edge_depths: Dictionary = {}
    var skipped_midpoints: Dictionary = {}
    for bump_index in range(selected_edges.size()):
        var bump_edge := selected_edges[bump_index]
        edge_depths[bump_edge] = bump_depths[bump_index]
        skipped_midpoints[(bump_edge + 1) % base.size()] = true

    var result: Array[Vector2i] = []
    for edge_index in range(base.size()):
        if skipped_midpoints.has(edge_index):
            continue
        var point: Vector2i = base[edge_index]
        result.append(point)
        var depth := int(edge_depths.get(edge_index, 0))
        if depth <= 0:
            continue
        # Replace two straight base edges (and their middle cell) with an outward
        # detour. The two endpoints are two cells apart, so the detour does not
        # leave an accidental side-connection across the removed road segment.
        var direction := base[(edge_index + 1) % base.size()] - point
        var next_point: Vector2i = base[(edge_index + 2) % base.size()]
        var outward := Vector2i(direction.y, -direction.x)
        for step in range(1, depth + 1):
            result.append(point + outward * step)
        for segment_step in range(1, 3):
            result.append(point + direction * segment_step + outward * depth)
        for step in range(depth - 1, 0, -1):
            result.append(next_point + outward * step)

    if not is_valid_procedural_road_grid_coordinates(result):
        return get_road_grid_coordinates(route_shape_id)
    return result

static func _contour_edge_is_internal(base: Array[Vector2i], edge_index: int, horizontal_span: int, vertical_span: int) -> bool:
    var perimeter := base.size()
    var top_start := 0
    var right_start := horizontal_span
    var bottom_start := horizontal_span + vertical_span
    var left_start := horizontal_span * 2 + vertical_span
    if edge_index >= top_start and edge_index < horizontal_span:
        var top_offset := edge_index - top_start
        return top_offset >= 2 and top_offset <= horizontal_span - 3
    if edge_index >= right_start and edge_index < right_start + vertical_span:
        var right_offset := edge_index - right_start
        return right_offset >= 2 and right_offset <= vertical_span - 3
    if edge_index >= bottom_start and edge_index < bottom_start + horizontal_span:
        var bottom_offset := edge_index - bottom_start
        return bottom_offset >= 2 and bottom_offset <= horizontal_span - 3
    if edge_index >= left_start and edge_index < perimeter:
        var left_offset := edge_index - left_start
        return left_offset >= 2 and left_offset <= vertical_span - 3
    return false

static func _contour_bump_fits(base: Array[Vector2i], edge_index: int, depth: int) -> bool:
    var point: Vector2i = base[edge_index]
    var direction := base[(edge_index + 1) % base.size()] - point
    var next_point: Vector2i = base[(edge_index + 2) % base.size()]
    var outward := Vector2i(direction.y, -direction.x)
    for step in range(1, depth + 1):
        var first := point + outward * step
        var second := next_point + outward * step
        if first.x < 1 or first.x >= MAP_COLUMNS - 1 or first.y < 1 or first.y >= MAP_ROWS - 1:
            return false
        if second.x < 1 or second.x >= MAP_COLUMNS - 1 or second.y < 1 or second.y >= MAP_ROWS - 1:
            return false
    var tangent_point := point + direction + outward * depth
    if tangent_point.x < 1 or tangent_point.x >= MAP_COLUMNS - 1 or tangent_point.y < 1 or tangent_point.y >= MAP_ROWS - 1:
        return false
    return true

static func is_valid_procedural_road_grid_coordinates(cells: Array[Vector2i]) -> bool:
    if cells.size() != ROAD_CELL_COUNT:
        return false
    var occupied: Dictionary = {}
    for index in range(cells.size()):
        var cell: Vector2i = cells[index]
        if cell.x < 1 or cell.x >= MAP_COLUMNS - 1 or cell.y < 1 or cell.y >= MAP_ROWS - 1:
            return false
        var key := "%d:%d" % [cell.x, cell.y]
        if occupied.has(key):
            return false
        occupied[key] = index
        var next_cell: Vector2i = cells[(index + 1) % cells.size()]
        if absi(next_cell.x - cell.x) + absi(next_cell.y - cell.y) != 1:
            return false
    # No extra orthogonal touches/chords: every road cell has exactly two road neighbours.
    for index in range(cells.size()):
        var cell: Vector2i = cells[index]
        for other_index in range(index + 1, cells.size()):
            var other: Vector2i = cells[other_index]
            if absi(other.x - cell.x) + absi(other.y - cell.y) != 1:
                continue
            if other_index == index + 1 or (index == 0 and other_index == cells.size() - 1):
                continue
            return false
    return true

static func world_cell_is_roadside(cell_id: String, route_shape_id: String = "classic_ring") -> bool:
    return world_cell_is_roadside_for_seed(cell_id, route_shape_id, 0)

static func world_cell_is_roadside_for_seed(cell_id: String, route_shape_id: String, route_geometry_seed: int = 0) -> bool:
    if not is_map_world_cell_id(cell_id):
        return false
    var coord := world_cell_coordinates(cell_id)
    for road_coord in get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed):
        if absi(coord.x - road_coord.x) + absi(coord.y - road_coord.y) == 1:
            return true
    return false

static func world_route_index(cell_id: String, route_size: int, route_shape_id: String = "classic_ring") -> int:
    return world_route_index_for_seed(cell_id, route_size, route_shape_id, 0)

static func world_route_index_for_seed(cell_id: String, route_size: int, route_shape_id: String, route_geometry_seed: int = 0) -> int:
    if route_size <= 0:
        return -1
    if is_map_world_cell_id(cell_id):
        var coord := world_cell_coordinates(cell_id)
        var road_cells := get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed)
        if road_cells.is_empty():
            return -1
        var nearest_slot := -1
        var nearest_distance := INF
        for slot in range(road_cells.size()):
            var road_coord: Vector2i = road_cells[slot]
            var distance := Vector2(coord).distance_squared_to(Vector2(road_coord))
            if distance < nearest_distance:
                nearest_distance = distance
                nearest_slot = slot
        if nearest_slot < 0:
            return -1
        # Use the same slot-to-route sampling as RouteView. This ties each world
        # cell to the actual contour, including non-classic route shapes.
        return posmod(roundi(float(nearest_slot) * float(route_size) / float(road_cells.size())), route_size)
    var parts := cell_id.split(":")
    if parts.size() != 2 or not WORLD_FIELD_KEYS.has(cell_id) or not parts[0].is_valid_int() or not parts[1].is_valid_int():
        return -1
    var col := int(parts[0])
    var row := int(parts[1])
    if col < 0 or col >= WORLD_FIELD_COLUMNS or row < 0 or row >= WORLD_FIELD_ROWS:
        return -1
    # Legacy angular sector assignment is intentionally retained for old saves.
    var nx := 0.029 + (float(col) + 0.5) * 0.942 / float(WORLD_FIELD_COLUMNS)
    var ny := 0.081 + (float(row) + 0.5) * 0.838 / float(WORLD_FIELD_ROWS)
    var angle := atan2(ny - 0.51, nx - 0.5)
    var route_position := fposmod(angle + PI * 0.5, TAU) / TAU
    return posmod(roundi(route_position * float(route_size)), route_size)

func _tile_placement_zone(tile: Dictionary) -> String:
    var tile_id := str(tile.get("id", ""))
    var definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
    return str(tile.get("placement_zone", definition.get("placement_zone", "any")))

func can_place_world(route: Array, world_tiles: Dictionary, cell_id: String, tile: Dictionary = {}, route_shape_id: String = "classic_ring", route_geometry_seed: int = 0) -> Dictionary:
    if route.is_empty():
        return {"ok": false, "reason": "Маршрут ещё не создан."}
    if not is_world_cell_valid(cell_id):
        return {"ok": false, "reason": "Эта клетка не относится к доступному ландшафту."}
    if is_map_world_cell_id(cell_id):
        var coord := world_cell_coordinates(cell_id)
        for road_coord in get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed):
            if coord == road_coord:
                return {"ok": false, "reason": "Эта клетка занята дорогой; выберите свободную клетку ландшафта."}
    if not tile.is_empty():
        var placement_zone := _tile_placement_zone(tile)
        if placement_zone not in ["any", "road", "roadside", "landscape"]:
            return {"ok": false, "reason": "У тайла не задана допустимая зона размещения."}
        if placement_zone == "road":
            return {"ok": false, "reason": "Эту карту можно разместить только на дорожном узле."}
        if placement_zone == "roadside" and not world_cell_is_roadside_for_seed(cell_id, route_shape_id, route_geometry_seed):
            return {"ok": false, "reason": "Эту карту можно разместить только в клетке, непосредственно примыкающей к дороге."}
        if placement_zone == "landscape" and is_map_world_cell_id(cell_id) and world_cell_is_roadside_for_seed(cell_id, route_shape_id, route_geometry_seed):
            return {"ok": false, "reason": "Эту постройку нужно разместить дальше от дороги, в глубине ландшафта."}
    if world_tiles.has(cell_id):
        return {"ok": false, "reason": "На этой клетке уже размещён тайл."}
    var route_index := world_route_index_for_seed(cell_id, route.size(), route_shape_id, route_geometry_seed)
    if route_index < 0:
        return {"ok": false, "reason": "Не удалось определить сектор маршрута."}
    var sector_count := 0
    for tile_value in world_tiles.values():
        if typeof(tile_value) == TYPE_DICTIONARY and int(tile_value.get("route_index", -1)) == route_index:
            sector_count += 1
    if sector_count >= MAX_WORLD_TILES_PER_ROUTE_SECTOR:
        return {"ok": false, "reason": "В этом секторе уже достаточно тайлов; выберите другой участок ландшафта."}
    return {"ok": true, "reason": "Ландшафт доступен для размещения.", "route_index": route_index}

func _get_world_synergy_matches(world_tiles: Dictionary, cell_id: String) -> Array[Dictionary]:
    var matches: Array[Dictionary] = []
    var current_value: Variant = world_tiles.get(cell_id, {})
    if typeof(current_value) != TYPE_DICTIONARY:
        return matches
    var current: Dictionary = current_value
    var current_id := str(current.get("id", ""))
    if current_id.is_empty():
        return matches
    for neighbor_key in world_cell_neighbors(cell_id):
        if not world_tiles.has(neighbor_key):
            continue
        var neighbor_value: Variant = world_tiles[neighbor_key]
        if typeof(neighbor_value) != TYPE_DICTIONARY:
            continue
        var neighbor_tile: Dictionary = neighbor_value
        if int(neighbor_tile.get("route_index", -1)) != int(current.get("route_index", -1)):
            continue
        var neighbor_id := str(neighbor_tile.get("id", ""))
        for synergy_value in ContentRegistry.TILE_SYNERGIES:
            if typeof(synergy_value) != TYPE_DICTIONARY:
                continue
            var synergy: Dictionary = synergy_value
            if str(synergy.get("trigger_tile", "")) != current_id or str(synergy.get("neighbor_tile", "")) != neighbor_id:
                continue
            var effects_value: Variant = synergy.get("effects", {})
            if typeof(effects_value) != TYPE_DICTIONARY:
                continue
            var effects: Dictionary = effects_value
            matches.append({
                "id": str(synergy.get("id", "")),
                "name": str(synergy.get("name", synergy.get("id", "Комбинация"))),
                "description": str(synergy.get("description", "Сработала комбинация тайлов.")),
                "trigger_cell": cell_id,
                "neighbor_cell": neighbor_key,
                "route_index": int(current.get("route_index", -1)),
                "effects": effects.duplicate(true)
            })
    return matches

func get_new_world_synergy_matches(before_tiles: Dictionary, after_tiles: Dictionary, changed_cell: String) -> Array[Dictionary]:
    # A placement may complete a recipe whose trigger is the existing neighbour.
    # Compare all synergies touching this cell so the preview does not depend on
    # which side of the pair was placed last.
    var affected_cells: Array[String] = [changed_cell]
    for neighbor_key in world_cell_neighbors(changed_cell):
        if not affected_cells.has(neighbor_key):
            affected_cells.append(neighbor_key)
    var existing_keys: Dictionary = {}
    for affected_cell in affected_cells:
        for match_value in _get_world_synergy_matches(before_tiles, affected_cell):
            var match_data: Dictionary = match_value
            existing_keys[_world_synergy_match_key(match_data)] = true
    var added: Array[Dictionary] = []
    var added_keys: Dictionary = {}
    for affected_cell in affected_cells:
        for match_value in _get_world_synergy_matches(after_tiles, affected_cell):
            var match_data: Dictionary = match_value
            var match_key := _world_synergy_match_key(match_data)
            if existing_keys.has(match_key) or added_keys.has(match_key):
                continue
            added_keys[match_key] = true
            added.append(match_data.duplicate(true))
    return added

func _world_synergy_match_key(match_data: Dictionary) -> String:
    return "%s|%s|%s" % [str(match_data.get("id", "")), str(match_data.get("trigger_cell", "")), str(match_data.get("neighbor_cell", ""))]

func aggregate_world_synergy_matches(matches: Array) -> Dictionary:
    var raw := {"scrap": 0, "heal": 0, "reward": 0.0, "spawn_bonus": 0.0, "enemy_bonus": 0.0}
    var names: Array[String] = []
    var messages: Array[String] = []
    for match_value in matches:
        if typeof(match_value) != TYPE_DICTIONARY:
            continue
        var match_data: Dictionary = match_value
        var effects_value: Variant = match_data.get("effects", {})
        if typeof(effects_value) != TYPE_DICTIONARY:
            continue
        var effects: Dictionary = effects_value
        raw["scrap"] = int(raw.scrap) + int(effects.get("scrap", 0))
        raw["heal"] = int(raw.heal) + int(effects.get("heal", 0))
        raw["reward"] = float(raw.reward) + float(effects.get("reward_bonus", 0.0))
        raw["spawn_bonus"] = float(raw.spawn_bonus) + float(effects.get("spawn_bonus", 0.0))
        raw["enemy_bonus"] = float(raw.enemy_bonus) + float(effects.get("enemy_bonus", 0.0))
        names.append(str(match_data.get("name", match_data.get("id", "Комбинация"))))
        messages.append(str(match_data.get("description", "Сработала комбинация тайлов.")))

    var capped := {}
    var caps_applied: Array[String] = []
    for effect_key in ["scrap", "heal", "reward", "spawn_bonus", "enemy_bonus"]:
        var limits: Array = WORLD_SYNERGY_LIMITS.get(effect_key, [])
        var raw_value: float = float(raw[effect_key])
        var final_value: float = raw_value
        if limits.size() == 2:
            final_value = clampf(raw_value, float(limits[0]), float(limits[1]))
        if not is_equal_approx(raw_value, final_value):
            caps_applied.append(effect_key)
        capped[effect_key] = int(roundi(final_value)) if effect_key in ["scrap", "heal"] else final_value
    return {
        "scrap": int(capped.get("scrap", 0)),
        "heal": int(capped.get("heal", 0)),
        "reward": float(capped.get("reward", 0.0)),
        "spawn_bonus": float(capped.get("spawn_bonus", 0.0)),
        "enemy_bonus": float(capped.get("enemy_bonus", 0.0)),
        "raw_effects": raw,
        "caps_applied": caps_applied,
        "messages": messages,
        "synergies": names
    }

func get_world_synergy_bonus(world_tiles: Dictionary, cell_id: String) -> Dictionary:
    # Single-cell calculation shares the aggregator with route-sector visits.
    return aggregate_world_synergy_matches(_get_world_synergy_matches(world_tiles, cell_id))

func get_world_synergy_bonus_for_route_index(world_tiles: Dictionary, route_index: int) -> Dictionary:
    # All landscape triggers mapped to this route sector are aggregated before caps.
    var matches: Array[Dictionary] = []
    for cell_value in world_tiles.keys():
        var cell_id := str(cell_value)
        var tile_value: Variant = world_tiles[cell_value]
        if typeof(tile_value) != TYPE_DICTIONARY:
            continue
        var tile: Dictionary = tile_value
        if int(tile.get("route_index", -1)) != route_index or str(tile.get("id", "")).is_empty():
            continue
        for match_value in _get_world_synergy_matches(world_tiles, cell_id):
            var match_data: Dictionary = match_value
            matches.append(match_data)
    return aggregate_world_synergy_matches(matches)

func clamp_visit_modifiers(modifiers: Dictionary) -> Dictionary:
    # Caps apply once to total modifiers, never once per individual tile.
    var result: Dictionary = {}
    var caps_applied: Array[String] = []
    var raw_values := {
        "spawn_bonus": float(modifiers.get("spawn_bonus", 0.0)),
        "enemy_bonus": float(modifiers.get("enemy_bonus", 0.0)),
        "reward_bonus": float(modifiers.get("reward_bonus", 0.0))
    }
    for effect_key in VISIT_MODIFIER_LIMITS.keys():
        var limits: Array = VISIT_MODIFIER_LIMITS[effect_key]
        var raw_value := float(raw_values.get(effect_key, 0.0))
        var final_value := clampf(raw_value, float(limits[0]), float(limits[1]))
        result[effect_key] = final_value
        if not is_equal_approx(raw_value, final_value):
            caps_applied.append(str(effect_key))
    result["raw_modifiers"] = raw_values
    result["caps_applied"] = caps_applied
    return result

func get_world_placement_effect_delta(before_tiles: Dictionary, after_tiles: Dictionary, changed_cell: String) -> Dictionary:
    # Only the changed cell and its orthogonal neighbours can introduce/remove a
    # recipe; however caps are calculated across every trigger in each affected sector.
    var affected_cells: Array[String] = [changed_cell]
    for neighbor_key in world_cell_neighbors(changed_cell):
        if not affected_cells.has(neighbor_key):
            affected_cells.append(neighbor_key)

    var affected_route_indices: Array[int] = []
    for affected_cell in affected_cells:
        for source_tiles in [before_tiles, after_tiles]:
            var source_value: Variant = source_tiles.get(affected_cell, {})
            if typeof(source_value) != TYPE_DICTIONARY:
                continue
            var source_tile: Dictionary = source_value
            var source_route_index := int(source_tile.get("route_index", -1))
            if source_route_index >= 0 and not affected_route_indices.has(source_route_index):
                affected_route_indices.append(source_route_index)

    affected_route_indices.sort()
    var sectors: Array[Dictionary] = []
    var totals := {"scrap": 0, "heal": 0, "reward": 0.0, "spawn_bonus": 0.0, "enemy_bonus": 0.0}
    var caps_applied: Array[String] = []
    for route_index in affected_route_indices:
        var before_bonus := get_world_synergy_bonus_for_route_index(before_tiles, route_index)
        var after_bonus := get_world_synergy_bonus_for_route_index(after_tiles, route_index)
        var delta := {
            "scrap": int(after_bonus.get("scrap", 0)) - int(before_bonus.get("scrap", 0)),
            "heal": int(after_bonus.get("heal", 0)) - int(before_bonus.get("heal", 0)),
            "reward": float(after_bonus.get("reward", 0.0)) - float(before_bonus.get("reward", 0.0)),
            "spawn_bonus": float(after_bonus.get("spawn_bonus", 0.0)) - float(before_bonus.get("spawn_bonus", 0.0)),
            "enemy_bonus": float(after_bonus.get("enemy_bonus", 0.0)) - float(before_bonus.get("enemy_bonus", 0.0))
        }
        var is_nonzero := false
        for effect_key in delta.keys():
            totals[effect_key] = totals[effect_key] + delta[effect_key]
            if not is_zero_approx(float(delta[effect_key])):
                is_nonzero = true
        for cap_key in after_bonus.get("caps_applied", []):
            if not caps_applied.has(str(cap_key)):
                caps_applied.append(str(cap_key))
        if is_nonzero:
            sectors.append({"route_index": route_index, "delta": delta, "before": before_bonus, "after": after_bonus})
    return {"sectors": sectors, "totals": totals, "caps_applied": caps_applied}

func get_world_placement_preview(route: Array, world_tiles: Dictionary, cell_id: String, tile: Dictionary, equipment: Dictionary = {}, route_shape_id: String = "classic_ring", route_geometry_seed: int = 0) -> Dictionary:
    var placement := can_place_world(route, world_tiles, cell_id, tile, route_shape_id, route_geometry_seed)
    if not bool(placement.get("ok", false)):
        return {"ok": false, "reason": str(placement.get("reason", "Размещение запрещено.")), "text": str(placement.get("reason", "Размещение запрещено."))}
    var tile_id := str(tile.get("id", ""))
    var definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
    if definition.is_empty():
        return {"ok": false, "reason": "Неизвестный тип тайла.", "text": "Неизвестный тип тайла."}
    var simulated := world_tiles.duplicate(true)
    var simulated_tile := tile.duplicate(true)
    var field_coord := world_cell_coordinates(cell_id)
    simulated_tile["route_index"] = int(placement.get("route_index", -1))
    simulated_tile["field_x"] = field_coord.x
    simulated_tile["field_y"] = field_coord.y
    simulated_tile["field_schema"] = 3 if is_map_world_cell_id(cell_id) else 2
    simulated[cell_id] = simulated_tile
    var new_matches := get_new_world_synergy_matches(world_tiles, simulated, cell_id)
    var new_secret_recipes := get_new_landscape_secret_recipes(world_tiles, simulated, cell_id)
    var baseline := _get_base_forecast(tile_id)
    var lines: Array[String] = [str(definition.get("name", tile_id)), str(definition.get("description", "")), Localization.text("tile.forecast.world_sector") % (int(placement.get("route_index", 0)) + 1), Localization.text("tile.forecast.world_baseline") % [str(baseline.get("spawn", Localization.text("tile.forecast.no_change"))), str(baseline.get("enemy", Localization.text("tile.forecast.no_change"))), str(baseline.get("reward", Localization.text("tile.forecast.no_change")))]]
    var enemy_pool_value: Variant = definition.get("enemy_pool", [])
    if typeof(enemy_pool_value) == TYPE_ARRAY and not enemy_pool_value.is_empty():
        var enemy_names: Array[String] = []
        for enemy_id_value in enemy_pool_value:
            var enemy_id := str(enemy_id_value)
            var enemy_definition: Dictionary = ContentRegistry.ENEMIES.get(enemy_id, {})
            enemy_names.append(str(enemy_definition.get("name", enemy_id)))
        lines.append("Угроза участка: %s." % ", ".join(enemy_names))
    var affinity_effects := inventory_system.get_landscape_affinity_effects(equipment, tile_id)
    var affinity_messages_value: Variant = affinity_effects.get("messages", [])
    if typeof(affinity_messages_value) == TYPE_ARRAY:
        for affinity_message in affinity_messages_value:
            lines.append(str(affinity_message))
    var affinity_parts: Array[String] = []
    for affinity_key in ["heal", "scrap", "crystals"]:
        var affinity_amount := int(affinity_effects.get(affinity_key, 0))
        if affinity_amount > 0:
            var affinity_label := {"heal": "здоровья", "scrap": "материала", "crystals": "кристалла"}.get(affinity_key, affinity_key)
            affinity_parts.append("+%d %s" % [affinity_amount, affinity_label])
    for affinity_key in ["spawn_bonus", "enemy_bonus", "reward_bonus"]:
        var affinity_amount_float := float(affinity_effects.get(affinity_key, 0.0))
        if not is_zero_approx(affinity_amount_float):
            var affinity_label := {"spawn_bonus": "п.п. к риску встречи", "enemy_bonus": "% к силе врагов", "reward_bonus": "% к награде"}.get(affinity_key, affinity_key)
            affinity_parts.append("%+d %s" % [int(round(affinity_amount_float * 100.0)), affinity_label])
    if not affinity_parts.is_empty():
        lines.append("Эффект надетой экипировки на этом ландшафте: %s." % ", ".join(affinity_parts))
    var synergy_names: Array[String] = []
    for match_data in new_matches:
        synergy_names.append(str(match_data.get("name", match_data.get("id", "Комбинация"))))
        lines.append(Localization.text("tile.forecast.world_synergy") % [str(match_data.get("name", match_data.get("id", "Комбинация"))), int(match_data.get("route_index", -1)) + 1])
        lines.append(str(match_data.get("description", "")))
    var effect_delta := get_world_placement_effect_delta(world_tiles, simulated, cell_id)
    var total_effects: Dictionary = effect_delta.get("totals", {"scrap": 0, "heal": 0, "reward": 0.0, "spawn_bonus": 0.0, "enemy_bonus": 0.0})
    for sector_value in effect_delta.get("sectors", []):
        var sector: Dictionary = sector_value
        var delta: Dictionary = sector.get("delta", {})
        var effect_lines: Array[String] = []
        if int(delta.get("scrap", 0)) != 0: effect_lines.append(Localization.text("tile.forecast.effect.scrap") % int(delta.get("scrap", 0)))
        if int(delta.get("heal", 0)) != 0: effect_lines.append(Localization.text("tile.forecast.effect.heal") % int(delta.get("heal", 0)))
        if not is_zero_approx(float(delta.get("reward", 0.0))): effect_lines.append(Localization.text("tile.forecast.effect.reward") % (float(delta.get("reward", 0.0)) * 100.0))
        if not is_zero_approx(float(delta.get("spawn_bonus", 0.0))): effect_lines.append(Localization.text("tile.forecast.effect.spawn") % (float(delta.get("spawn_bonus", 0.0)) * 100.0))
        if not is_zero_approx(float(delta.get("enemy_bonus", 0.0))): effect_lines.append(Localization.text("tile.forecast.effect.enemy") % (float(delta.get("enemy_bonus", 0.0)) * 100.0))
        if not effect_lines.is_empty():
            lines.append(Localization.text("tile.forecast.world_sector_delta") % [int(sector.get("route_index", -1)) + 1, "; ".join(effect_lines)])
    if not effect_delta.get("caps_applied", []).is_empty():
        lines.append(Localization.text("tile.forecast.world_caps_aggregate"))
    if new_matches.is_empty():
        lines.append(Localization.text("tile.forecast.world_no_new_synergy"))
    for recipe in new_secret_recipes:
        lines.append("Тайна подготовлена: «%s». Она откроется при посещении этого сектора. %s" % [str(recipe.get("title", "Тайна")), str(recipe.get("clue", ""))])
    var tactical_advice := get_tactical_counter_preview(tile_id, equipment)
    if not tactical_advice.is_empty():
        lines.append(tactical_advice)
    lines.append(Localization.text("tile.forecast.world_synergy_caps"))
    lines.append(Localization.text("tile.forecast.world_visit_caps"))
    var preview_effects := {
        "scrap": int(total_effects.get("scrap", 0)),
        "heal": int(total_effects.get("heal", 0)),
        "reward_bonus": float(total_effects.get("reward", 0.0)),
        "spawn_bonus": float(total_effects.get("spawn_bonus", 0.0)),
        "enemy_bonus": float(total_effects.get("enemy_bonus", 0.0))
    }

    return {"ok": true, "reason": "Ландшафт доступен для размещения.", "text": "\n".join(lines), "route_index": int(placement.get("route_index", -1)), "synergies": synergy_names, "new_synergy_matches": new_matches, "synergy_effects": preview_effects, "synergy_sector_deltas": effect_delta.get("sectors", []), "synergy_caps_applied": effect_delta.get("caps_applied", []), "new_secret_recipes": new_secret_recipes, "equipment_affinity": affinity_effects.duplicate(true), "forecast": baseline}

func _get_tile_draw_weight(tile_id: String) -> float:
    var weight := maxf(0.01, float(TILE_DRAW_WEIGHTS.get(tile_id, 1.0)))
    if tile_id in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]:
        weight *= GameState.get_rare_tile_weight_multiplier()
    return weight

func draw_tile(rng: RandomNumberGenerator, unlock_rift: bool, excluded_tile_ids: Array = []) -> Dictionary:
    var choices := ["cache", "hunt", "ward", "snare", "echo_spring"]
    if unlock_rift:
        choices.append("rift")
        choices.append("signal")
        choices.append("archive")
        choices.append("nursery")
        choices.append("fault_line")
        choices.append("spore_garden")
        choices.append("crystal_hive")
        choices.append("bone_orchard")
        choices.append("echo_obelisk")
        choices.append("lost_convoy")
        choices.append("hunter_marker")
    var available_choices: Array = []
    for choice_value in choices:
        if not excluded_tile_ids.has(str(choice_value)):
            available_choices.append(choice_value)
    if available_choices.is_empty():
        available_choices = choices.duplicate()
    var total_weight := 0.0
    for choice_value in available_choices:
        total_weight += _get_tile_draw_weight(str(choice_value))
    var roll := rng.randf() * total_weight
    var tile_id := str(available_choices.back())
    for choice_value in available_choices:
        var choice_id := str(choice_value)
        roll -= _get_tile_draw_weight(choice_id)
        if roll < 0.0:
            tile_id = choice_id
            break
    var def: Dictionary = ContentRegistry.TILE_DEFS[tile_id]
    return {"id": tile_id, "name": def.name, "short": def.short, "kind": def.kind, "color": def.color, "description": def.description, "placement_zone": str(def.get("placement_zone", "any")), "uid": str(rng.randi())}

func can_place(route: Array, placed_tiles: Dictionary, index: int, tile: Dictionary = {}) -> Dictionary:
    if index < 0 or index >= route.size():
        return {"ok": false, "reason": "Клетка находится за пределами маршрута."}
    if index == 0:
        return {"ok": false, "reason": "Стартовый узел нельзя менять."}
    if placed_tiles.has(str(index)):
        return {"ok": false, "reason": "На этой клетке уже есть тайл."}
    if not tile.is_empty():
        var placement_zone := _tile_placement_zone(tile)
        if placement_zone not in ["any", "road", "roadside", "landscape"]:
            return {"ok": false, "reason": "У тайла не задана допустимая зона размещения."}
        if placement_zone in ["landscape", "roadside"]:
            return {"ok": false, "reason": "Эту постройку можно разместить только вне дороги."}
    return {"ok": true, "reason": "Тайл можно разместить."}

func apply_tile_visit(tile: Dictionary, ledger: Dictionary, hero: Dictionary, loop_count: int) -> Dictionary:
    var result := {"messages": [], "spawn_bonus": 0.0, "enemy_bonus": 0.0, "reward_bonus": 0.0, "enemy_pool": []}
    var tile_id := str(tile.get("id", ""))
    var tile_definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
    var enemy_pool_value: Variant = tile_definition.get("enemy_pool", [])
    if typeof(enemy_pool_value) == TYPE_ARRAY:
        result["enemy_pool"] = enemy_pool_value.duplicate(true)
    match tile_id:
        "cache":
            resource_system.add(ledger, "scrap", 3 + mini(loop_count, 3))
            result.messages.append("Узел снабжения: +%d материалов." % (3 + mini(loop_count, 3)))
        "hunt":
            result.spawn_bonus = 0.60
            result.reward_bonus = 0.45
            result.messages.append("Зона охоты привлекла противника; награда за победу выше.")
        "ward":
            var old_hp := int(hero.get("hp", 0))
            hero["hp"] = mini(int(hero.get("max_hp", old_hp)), old_hp + 7)
            result.messages.append("Защитный маяк восстановил %d здоровья." % (int(hero.hp) - old_hp))
        "rift":
            result.spawn_bonus = 0.85
            result.enemy_bonus = 0.45
            result.reward_bonus = 0.8
            result.messages.append("Разлом усиливает угрозу и возможную добычу.")
        "snare":
            result.spawn_bonus = -0.12
            result.enemy_bonus = -0.10
            result.messages.append("Узел перехвата снижает вероятность столкновения и ослабляет врагов.")
        "signal":
            resource_system.add(ledger, "scrap", 2)
            result.spawn_bonus = 0.15
            result.reward_bonus = 0.30
            result.messages.append("Резонатор: +2 материала; риск и потенциальная награда повышены.")
        "archive":
            resource_system.add(ledger, "scrap", 2)
            resource_system.add(ledger, "crystals", 1)
            result.reward_bonus = 0.08
            result.messages.append("Архив старой экспедиции: +2 материала, +1 кристалл и +8% к награде за бой.")
        "nursery":
            result.spawn_bonus = 0.28
            result.enemy_bonus = 0.12
            result.reward_bonus = 0.25
            result.messages.append("Питомник бездны выводит угрозу: вероятность встречи и сила врагов выше, но награда увеличена на 25%.")
        "echo_spring":
            var spring_old_hp := int(hero.get("hp", 0))
            hero["hp"] = mini(int(hero.get("max_hp", spring_old_hp)), spring_old_hp + 6)
            result.spawn_bonus = -0.04
            result.messages.append("Источник тихого эха восстановил %d здоровья и стабилизировал узел." % (int(hero.get("hp", 0)) - spring_old_hp))
        "fault_line":
            result.spawn_bonus = 0.42
            result.enemy_bonus = 0.10
            result.reward_bonus = 0.18
            result.messages.append("Трещина живой породы раскрылась: вероятнее столкновение с эхо-огоньком, добыча выше.")
        "spore_garden":
            var garden_old_hp := int(hero.get("hp", 0))
            hero["hp"] = mini(int(hero.get("max_hp", garden_old_hp)), garden_old_hp + 3)
            result.spawn_bonus = 0.04
            result.reward_bonus = 0.04
            resource_system.add(ledger, "scrap", 1)
            result.messages.append("Споровый сад восстановил %d здоровья и дал +1 материал; его обитатели могут проснуться." % (int(hero.get("hp", 0)) - garden_old_hp))
        "crystal_hive":
            resource_system.add(ledger, "crystals", 1)
            resource_system.add(ledger, "scrap", 1)
            result.spawn_bonus = 0.12
            result.enemy_bonus = 0.06
            result.reward_bonus = 0.12
            result.messages.append("Кристальный улей дал +1 кристалл и +1 материал, но привлёк призматических клещей.")
        "bone_orchard":
            resource_system.add(ledger, "scrap", 2)
            result.spawn_bonus = 0.18
            result.enemy_bonus = 0.12
            result.reward_bonus = 0.18
            result.messages.append("Костяной сад дал +2 материала и разбудил дозорных: враги сильнее, трофеи ценнее.")
        "echo_obelisk":
            resource_system.add(ledger, "crystals", 1)
            result.spawn_bonus = 0.10
            result.reward_bonus = 0.15
            result.messages.append("Обелиск немого сигнала дал +1 кристалл и усилил редкую добычу, но позвал эхо-огоньков.")
        "lost_convoy":
            resource_system.add(ledger, "scrap", 3)
            var old_rarity_bonus := clampf(float(ledger.get("pending_item_rarity_bonus", 0.0)), 0.0, 0.18)
            var next_rarity_bonus := minf(0.18, old_rarity_bonus + 0.12)
            ledger["pending_item_rarity_bonus"] = next_rarity_bonus
            result.spawn_bonus = 0.06
            result.enemy_bonus = 0.03
            result.reward_bonus = 0.12
            result.messages.append("Обоз разобран: +3 материала. Шкала редкости будущей находки +%d п.п. (до первого успешного получения экипировки). Риск встречи немного выше." % int(round(next_rarity_bonus * 100.0)))
        "hunter_marker":
            var old_drop_bonus := clampf(float(ledger.get("pending_item_drop_bonus", 0.0)), 0.0, 0.30)
            var next_drop_bonus := minf(0.30, old_drop_bonus + 0.15)
            ledger["pending_item_drop_bonus"] = next_drop_bonus
            result.spawn_bonus = 0.18
            result.enemy_bonus = 0.05
            result.reward_bonus = 0.18
            result.messages.append("Охотничья веха пометила добычу: +%d п.п. к шансу экипировки до первой успешной находки. Встречи чаще, враги сильнее, награда выше." % int(round(next_drop_bonus * 100.0)))
    return result

func _road_formation_cycle_index(index: int, offset: int, route_size: int) -> int:
    # Route node 0 is the immutable starting landmark, not a card slot. Formations
    # follow the cyclic sequence of placeable road-card slots 1..N-1, so a pattern
    # may bridge the last slot back to slot 1 without requiring a card on the start.
    var placeable_count := route_size - 1
    if placeable_count <= 0:
        return 0
    return 1 + posmod(index - 1 + offset, placeable_count)

func get_road_formation_matches(placed_tiles: Dictionary, index: int, route_size: int, equipment: Dictionary = {}) -> Array[Dictionary]:
    var matches: Array[Dictionary] = []
    if route_size < 4 or index <= 0 or index >= route_size:
        return matches
    var center_index := _road_formation_cycle_index(index, 0, route_size)
    var previous_index := _road_formation_cycle_index(center_index, -1, route_size)
    var next_index := _road_formation_cycle_index(center_index, 1, route_size)
    var center_value: Variant = placed_tiles.get(str(center_index), {})
    var previous_value: Variant = placed_tiles.get(str(previous_index), {})
    var next_value: Variant = placed_tiles.get(str(next_index), {})
    if typeof(center_value) != TYPE_DICTIONARY or typeof(previous_value) != TYPE_DICTIONARY or typeof(next_value) != TYPE_DICTIONARY:
        return matches
    var center_tile: Dictionary = center_value
    var previous_tile: Dictionary = previous_value
    var next_tile: Dictionary = next_value
    var center_id := str(center_tile.get("id", ""))
    var previous_id := str(previous_tile.get("id", ""))
    var next_id := str(next_tile.get("id", ""))
    if center_id.is_empty() or previous_id.is_empty() or next_id.is_empty():
        return matches
    var equipment_stats: Dictionary = inventory_system.total_equipment_stats(equipment) if not equipment.is_empty() else {}
    var formation_bonus := clampf(float(equipment_stats.get("road_formation_bonus", 0.0)), 0.0, 0.25)
    for formation_value in ContentRegistry.ROAD_FORMATIONS:
        if typeof(formation_value) != TYPE_DICTIONARY:
            continue
        var formation: Dictionary = formation_value
        if str(formation.get("center_tile", "")) != center_id or str(formation.get("previous_tile", "")) != previous_id or str(formation.get("next_tile", "")) != next_id:
            continue
        var effects_value: Variant = formation.get("effects", {})
        if typeof(effects_value) != TYPE_DICTIONARY:
            continue
        var effects: Dictionary = effects_value.duplicate(true)
        # Cartographer gear only improves explicit positive combat payout; it never
        # amplifies integer healing/resource rounding or removes the formation's risk.
        var base_reward := float(effects.get("reward_bonus", 0.0))
        if base_reward > 0.0 and formation_bonus > 0.0:
            effects["reward_bonus"] = minf(0.5, base_reward * (1.0 + formation_bonus))
        matches.append({"id": str(formation.get("id", "")), "name": str(formation.get("name", "Формация дороги")), "description": str(formation.get("description", "")), "center_index": center_index, "effects": effects, "equipment_bonus": formation_bonus})
    return matches

func get_new_road_formation_matches(before_tiles: Dictionary, after_tiles: Dictionary, changed_index: int, route_size: int, equipment: Dictionary = {}) -> Array[Dictionary]:
    var added: Array[Dictionary] = []
    if route_size < 4 or changed_index <= 0 or changed_index >= route_size:
        return added
    var affected_indices: Array[int] = [
        _road_formation_cycle_index(changed_index, 0, route_size),
        _road_formation_cycle_index(changed_index, -1, route_size),
        _road_formation_cycle_index(changed_index, 1, route_size)
    ]
    var existing: Dictionary = {}
    for center_index in affected_indices:
        for match_data in get_road_formation_matches(before_tiles, center_index, route_size, equipment):
            existing[str(match_data.get("id", "")) + "|" + str(match_data.get("center_index", -1))] = true
    var seen: Dictionary = {}
    for center_index in affected_indices:
        for match_data in get_road_formation_matches(after_tiles, center_index, route_size, equipment):
            var match_key := str(match_data.get("id", "")) + "|" + str(match_data.get("center_index", -1))
            if existing.has(match_key) or seen.has(match_key):
                continue
            seen[match_key] = true
            added.append(match_data.duplicate(true))
    return added

func _get_route_pair_synergy_matches(placed_tiles: Dictionary, trigger_index: int, route_size: int) -> Array[Dictionary]:
    var matches: Array[Dictionary] = []
    if route_size <= 1 or trigger_index <= 0 or trigger_index >= route_size:
        return matches
    var trigger_value: Variant = placed_tiles.get(str(trigger_index), {})
    if typeof(trigger_value) != TYPE_DICTIONARY:
        return matches
    var trigger_tile: Dictionary = trigger_value
    var trigger_id := str(trigger_tile.get("id", ""))
    if trigger_id.is_empty():
        return matches
    var neighbor_indices: Array[int] = [posmod(trigger_index - 1, route_size), posmod(trigger_index + 1, route_size)]
    var seen_neighbors: Dictionary = {}
    for neighbor_index in neighbor_indices:
        if neighbor_index <= 0 or neighbor_index >= route_size or seen_neighbors.has(neighbor_index):
            continue
        seen_neighbors[neighbor_index] = true
        var neighbor_value: Variant = placed_tiles.get(str(neighbor_index), {})
        if typeof(neighbor_value) != TYPE_DICTIONARY:
            continue
        var neighbor_tile: Dictionary = neighbor_value
        var neighbor_id := str(neighbor_tile.get("id", ""))
        if neighbor_id.is_empty():
            continue
        for synergy_value in ContentRegistry.TILE_SYNERGIES:
            if typeof(synergy_value) != TYPE_DICTIONARY:
                continue
            var synergy: Dictionary = synergy_value
            if str(synergy.get("trigger_tile", "")) != trigger_id or str(synergy.get("neighbor_tile", "")) != neighbor_id:
                continue
            var effects_value: Variant = synergy.get("effects", {})
            if typeof(effects_value) != TYPE_DICTIONARY:
                continue
            var effects: Dictionary = effects_value
            matches.append({
                "id": str(synergy.get("id", "")),
                "name": str(synergy.get("name", synergy.get("id", "Комбинация"))),
                "description": str(synergy.get("description", "Комбинация дорожных карт.")),
                "trigger_index": trigger_index,
                "neighbor_index": neighbor_index,
                "effects": effects.duplicate(true)
            })
    return matches

func get_new_route_synergy_matches(before_tiles: Dictionary, after_tiles: Dictionary, changed_index: int, route_size: int) -> Array[Dictionary]:
    var added: Array[Dictionary] = []
    if route_size <= 1 or changed_index <= 0 or changed_index >= route_size:
        return added
    var affected_indices: Array[int] = [changed_index]
    for candidate_index in [posmod(changed_index - 1, route_size), posmod(changed_index + 1, route_size)]:
        if candidate_index > 0 and candidate_index < route_size and not affected_indices.has(candidate_index):
            affected_indices.append(candidate_index)
    var existing: Dictionary = {}
    for trigger_index in affected_indices:
        for match_data in _get_route_pair_synergy_matches(before_tiles, trigger_index, route_size):
            existing["%s|%d|%d" % [str(match_data.get("id", "")), int(match_data.get("trigger_index", -1)), int(match_data.get("neighbor_index", -1))]] = true
    var seen: Dictionary = {}
    for trigger_index in affected_indices:
        for match_data in _get_route_pair_synergy_matches(after_tiles, trigger_index, route_size):
            var match_key := "%s|%d|%d" % [str(match_data.get("id", "")), int(match_data.get("trigger_index", -1)), int(match_data.get("neighbor_index", -1))]
            if existing.has(match_key) or seen.has(match_key):
                continue
            seen[match_key] = true
            added.append(match_data.duplicate(true))
    return added

func _format_synergy_effects(effects: Dictionary) -> String:
    var parts: Array[String] = []
    var scrap := int(effects.get("scrap", 0))
    var heal := int(effects.get("heal", 0))
    var reward := float(effects.get("reward_bonus", 0.0))
    var spawn := float(effects.get("spawn_bonus", 0.0))
    var enemy := float(effects.get("enemy_bonus", 0.0))
    if scrap != 0:
        parts.append("%+d материала" % scrap)
    if heal != 0:
        parts.append("%+d здоровья" % heal)
    if not is_zero_approx(reward):
        parts.append("%+d%% к награде" % int(round(reward * 100.0)))
    if not is_zero_approx(spawn):
        parts.append("%+d п.п. к риску встречи" % int(round(spawn * 100.0)))
    if not is_zero_approx(enemy):
        parts.append("%+d%% к силе врагов" % int(round(enemy * 100.0)))
    return ", ".join(parts) if not parts.is_empty() else "без числового бонуса"

func _world_recipe_match_exists(world_tiles: Dictionary, first_id: String, second_id: String, changed_cell: String) -> bool:
    if not is_world_cell_valid(changed_cell):
        return false
    var current_value: Variant = world_tiles.get(changed_cell, {})
    if typeof(current_value) != TYPE_DICTIONARY:
        return false
    var current: Dictionary = current_value
    var current_id := str(current.get("id", ""))
    var route_index := int(current.get("route_index", -1))
    if current_id not in [first_id, second_id]:
        return false
    var wanted_id := second_id if current_id == first_id else first_id
    for neighbor_key in world_cell_neighbors(changed_cell):
        var neighbor_value: Variant = world_tiles.get(neighbor_key, {})
        if typeof(neighbor_value) != TYPE_DICTIONARY:
            continue
        var neighbor: Dictionary = neighbor_value
        if int(neighbor.get("route_index", -1)) != route_index:
            continue
        if str(neighbor.get("id", "")) == wanted_id:
            return true
    return false

func get_new_landscape_secret_recipes(before_tiles: Dictionary, after_tiles: Dictionary, changed_cell: String) -> Array[Dictionary]:
    var recipes: Array[Dictionary] = []
    for recipe_value in ContentRegistry.LANDSCAPE_SECRET_RECIPES:
        if typeof(recipe_value) != TYPE_DICTIONARY:
            continue
        var recipe: Dictionary = recipe_value
        var first_id := str(recipe.get("first_tile", ""))
        var second_id := str(recipe.get("second_tile", ""))
        if first_id.is_empty() or second_id.is_empty():
            continue
        if _world_recipe_match_exists(before_tiles, first_id, second_id, changed_cell):
            continue
        if _world_recipe_match_exists(after_tiles, first_id, second_id, changed_cell):
            recipes.append({"flag": str(recipe.get("flag", "")), "title": str(recipe.get("title", "Тайна")), "clue": str(recipe.get("clue", "Связь ландшафта раскрыта.")), "first_tile": first_id, "second_tile": second_id})
    return recipes

func get_synergy_bonus(placed_tiles: Dictionary, index: int, route_size: int = 0, equipment: Dictionary = {}) -> Dictionary:
    var current: Dictionary = placed_tiles.get(str(index), {})
    var current_id := str(current.get("id", ""))
    var bonus := {"reward": 0.0, "heal": 0, "scrap": 0, "spawn_bonus": 0.0, "enemy_bonus": 0.0, "messages": [], "synergies": []}
    if current_id.is_empty():
        return bonus

    var neighbor_indices: Array[int] = []
    if route_size > 1:
        neighbor_indices = [posmod(index - 1, route_size), posmod(index + 1, route_size)]
    else:
        neighbor_indices = [index - 1, index + 1]
    var matched_neighbor_keys: Array[String] = []
    for neighbor_index in neighbor_indices:
        var neighbor_key := str(neighbor_index)
        if matched_neighbor_keys.has(neighbor_key):
            continue
        matched_neighbor_keys.append(neighbor_key)
        var neighbor: Dictionary = placed_tiles.get(neighbor_key, {})
        var neighbor_id := str(neighbor.get("id", ""))
        if neighbor_id.is_empty():
            continue
        for synergy_value in ContentRegistry.TILE_SYNERGIES:
            if typeof(synergy_value) != TYPE_DICTIONARY:
                continue
            var synergy: Dictionary = synergy_value
            if str(synergy.get("trigger_tile", "")) != current_id or str(synergy.get("neighbor_tile", "")) != neighbor_id:
                continue
            var effects_value: Variant = synergy.get("effects", {})
            if typeof(effects_value) != TYPE_DICTIONARY:
                continue
            var effects: Dictionary = effects_value
            bonus["scrap"] = int(bonus.scrap) + int(effects.get("scrap", 0))
            bonus["heal"] = int(bonus.heal) + int(effects.get("heal", 0))
            bonus["reward"] = float(bonus.reward) + float(effects.get("reward_bonus", 0.0))
            bonus["spawn_bonus"] = float(bonus.spawn_bonus) + float(effects.get("spawn_bonus", 0.0))
            bonus["enemy_bonus"] = float(bonus.enemy_bonus) + float(effects.get("enemy_bonus", 0.0))
            bonus["synergies"].append(str(synergy.get("name", synergy.get("id", "Комбинация"))))
            bonus["messages"].append(str(synergy.get("description", "Сработала комбинация тайлов.")))
    for formation_match in get_road_formation_matches(placed_tiles, index, route_size, equipment):
        var formation_effects: Dictionary = formation_match.get("effects", {})
        bonus["scrap"] = int(bonus.scrap) + int(formation_effects.get("scrap", 0))
        bonus["heal"] = int(bonus.heal) + int(formation_effects.get("heal", 0))
        bonus["reward"] = float(bonus.reward) + float(formation_effects.get("reward_bonus", 0.0))
        bonus["spawn_bonus"] = float(bonus.spawn_bonus) + float(formation_effects.get("spawn_bonus", 0.0))
        bonus["enemy_bonus"] = float(bonus.enemy_bonus) + float(formation_effects.get("enemy_bonus", 0.0))
        bonus["synergies"].append(str(formation_match.get("name", "Формация дороги")))
        bonus["messages"].append("Формация «%s»: %s" % [str(formation_match.get("name", "дороги")), str(formation_match.get("description", "три дорожных тайла усилили узел."))])
    return bonus

func get_placement_preview(route: Array, placed_tiles: Dictionary, index: int, tile: Dictionary, equipment: Dictionary = {}) -> Dictionary:
    var placement: Dictionary = can_place(route, placed_tiles, index, tile)
    var tile_id := str(tile.get("id", ""))
    var definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
    if not bool(placement.get("ok", false)):
        return {"ok": false, "reason": str(placement.get("reason", "Размещение запрещено.")), "text": str(placement.get("reason", "Размещение запрещено."))}
    if definition.is_empty():
        return {"ok": false, "reason": "Неизвестный тип тайла.", "text": "Неизвестный тип тайла."}

    var simulated: Dictionary = placed_tiles.duplicate(true)
    simulated[str(index)] = tile.duplicate(true)
    var synergy: Dictionary = get_synergy_bonus(simulated, index, route.size(), equipment)
    var newly_completed_formations := get_new_road_formation_matches(placed_tiles, simulated, index, route.size(), equipment)
    var newly_activated_route_synergies := get_new_route_synergy_matches(placed_tiles, simulated, index, route.size())
    var baseline := _get_base_forecast(tile_id)
    var lines: Array[String] = [str(definition.get("name", tile_id)), str(definition.get("description", "")), Localization.text("tile.forecast.route_baseline") % [str(baseline.get("spawn", Localization.text("tile.forecast.no_change"))), str(baseline.get("enemy", Localization.text("tile.forecast.no_change"))), str(baseline.get("reward", Localization.text("tile.forecast.no_change")))]]
    var effect_summary: Array[String] = []
    var forecast_spawn := float(synergy.get("spawn_bonus", 0.0))
    var forecast_enemy := float(synergy.get("enemy_bonus", 0.0))
    var forecast_reward := float(synergy.get("reward", 0.0))
    var forecast_scrap := int(synergy.get("scrap", 0))
    var forecast_heal := int(synergy.get("heal", 0))
    if not is_zero_approx(forecast_spawn):
        effect_summary.append(Localization.text("tile.forecast.delta.spawn") % ["+" if forecast_spawn > 0.0 else "−", absf(forecast_spawn) * 100.0])
    if not is_zero_approx(forecast_enemy):
        effect_summary.append(Localization.text("tile.forecast.delta.enemy") % ["+" if forecast_enemy > 0.0 else "−", absf(forecast_enemy) * 100.0])
    if not is_zero_approx(forecast_reward):
        effect_summary.append(Localization.text("tile.forecast.delta.reward") % ["+" if forecast_reward > 0.0 else "−", absf(forecast_reward) * 100.0])
    if forecast_scrap != 0:
        effect_summary.append(Localization.text("tile.forecast.delta.scrap") % forecast_scrap)
    if forecast_heal > 0:
        effect_summary.append(Localization.text("tile.forecast.delta.heal") % forecast_heal)
    if not effect_summary.is_empty():
        lines.append(Localization.text("tile.forecast.neighbor_bonus") % "; ".join(effect_summary))
    var synergy_messages: Variant = synergy.get("messages", [])
    var has_synergy_messages := false
    if typeof(synergy_messages) == TYPE_ARRAY:
        has_synergy_messages = not synergy_messages.is_empty()
        for message in synergy_messages:
            lines.append(Localization.text("tile.forecast.combo") % str(message))
    if not has_synergy_messages:
        lines.append(Localization.text("tile.forecast.no_synergy"))
    var preview_synergies: Array = synergy.get("synergies", []).duplicate(true)
    var newly_created_effects := {"scrap": 0, "heal": 0, "reward_bonus": 0.0, "spawn_bonus": 0.0, "enemy_bonus": 0.0}
    for route_synergy in newly_activated_route_synergies:
        var trigger_index := int(route_synergy.get("trigger_index", -1))
        var neighbor_index := int(route_synergy.get("neighbor_index", -1))
        var route_synergy_name := str(route_synergy.get("name", "Комбинация"))
        var route_synergy_effects: Dictionary = route_synergy.get("effects", {})
        if trigger_index != index:
            lines.append("Новая связка «%s» сработает при посещении узла %d (соседний узел %d): %s. %s" % [route_synergy_name, trigger_index + 1, neighbor_index + 1, _format_synergy_effects(route_synergy_effects), str(route_synergy.get("description", ""))])
        if not preview_synergies.has(route_synergy_name):
            preview_synergies.append(route_synergy_name)
        newly_created_effects["scrap"] = int(newly_created_effects.scrap) + int(route_synergy_effects.get("scrap", 0))
        newly_created_effects["heal"] = int(newly_created_effects.heal) + int(route_synergy_effects.get("heal", 0))
        for effect_key in ["reward_bonus", "spawn_bonus", "enemy_bonus"]:
            newly_created_effects[effect_key] = float(newly_created_effects.get(effect_key, 0.0)) + float(route_synergy_effects.get(effect_key, 0.0))
    for formation_delta in newly_completed_formations:
        var formation_delta_effects: Dictionary = formation_delta.get("effects", {})
        newly_created_effects["scrap"] = int(newly_created_effects.scrap) + int(formation_delta_effects.get("scrap", 0))
        newly_created_effects["heal"] = int(newly_created_effects.heal) + int(formation_delta_effects.get("heal", 0))
        for effect_key in ["reward_bonus", "spawn_bonus", "enemy_bonus"]:
            newly_created_effects[effect_key] = float(newly_created_effects.get(effect_key, 0.0)) + float(formation_delta_effects.get(effect_key, 0.0))
    var has_created_effects := false
    for effect_value in newly_created_effects.values():
        if not is_zero_approx(float(effect_value)):
            has_created_effects = true
            break
    if has_created_effects:
        lines.append("Суммарный эффект новых связок на затронутых узлах (до общих лимитов узла): %s." % _format_synergy_effects(newly_created_effects))
    var route_slot := route[index] if index >= 0 and index < route.size() else {}
    if typeof(route_slot) == TYPE_DICTIONARY:
        var route_kind := str(route_slot.get("kind", "plain"))
        var route_kind_name := str(ContentRegistry.ROUTE_CELL_TYPES.get(route_kind, {}).get("name", route_kind))
        lines.append("Тип дорожного узла: %s. Карта повлияет на сам узел и указанные выше соседние связки." % route_kind_name)
    for formation_match in newly_completed_formations:
        var formation_name := str(formation_match.get("name", "Формация дороги"))
        if not preview_synergies.has(formation_name):
            preview_synergies.append(formation_name)
        var formation_effects: Dictionary = formation_match.get("effects", {})
        var formation_index := int(formation_match.get("center_index", -1))
        var formation_parts: Array[String] = []
        if int(formation_effects.get("scrap", 0)) > 0:
            formation_parts.append("+%d материала" % int(formation_effects.get("scrap", 0)))
        if int(formation_effects.get("heal", 0)) > 0:
            formation_parts.append("+%d здоровья" % int(formation_effects.get("heal", 0)))
        if float(formation_effects.get("reward_bonus", 0.0)) != 0.0:
            formation_parts.append("%+d%% к боевой награде" % int(round(float(formation_effects.get("reward_bonus", 0.0)) * 100.0)))
        if float(formation_effects.get("spawn_bonus", 0.0)) != 0.0:
            formation_parts.append("%+d п.п. к риску встречи" % int(round(float(formation_effects.get("spawn_bonus", 0.0)) * 100.0)))
        if float(formation_effects.get("enemy_bonus", 0.0)) != 0.0:
            formation_parts.append("%+d%% к силе врагов" % int(round(float(formation_effects.get("enemy_bonus", 0.0)) * 100.0)))
        lines.append("Новая формация «%s» с центром в узле %d: %s. %s" % [formation_name, formation_index + 1, ", ".join(formation_parts), str(formation_match.get("description", ""))])
    match tile_id:
        "lost_convoy":
            lines.append("ДОБЫЧА: +3 материала; подготовка будущей экипировки — +12 п.п. к шкале редкости, накопление ограничено +18 п.п.")
        "hunter_marker":
            lines.append("ДОБЫЧА: +15 п.п. к шансу найти экипировку за каждое посещение, накопление ограничено +30 п.п.; бонус сгорает после первой успешной находки.")
    var tactical_advice := get_tactical_counter_preview(tile_id, equipment)
    if not tactical_advice.is_empty():
        lines.append(tactical_advice)
    return {"ok": true, "reason": "Тайл можно разместить.", "text": "\n".join(lines), "synergies": preview_synergies, "forecast": baseline, "new_route_synergy_matches": newly_activated_route_synergies.duplicate(true), "new_synergy_effects": newly_created_effects.duplicate(true), "new_road_formations": newly_completed_formations.duplicate(true)}

func get_tactical_counter_preview(tile_id: String, equipment: Dictionary = {}) -> String:
    # Preview a biome's signature status/telegraph using the same stat aggregation as live combat.
    var threat_profiles := {
        "spore_garden": {"enemy": "Споровик-бубенчик", "status": "poison", "label": "яд", "counter": "Фильтр спор"},
        "nursery": {"enemy": "выводок спор", "status": "poison", "label": "яд", "counter": "Фильтр спор"},
        "crystal_hive": {"enemy": "Призматический клещ", "status": "bleed", "label": "кровотечение элиты", "counter": "Заземлитель улья"},
        "bone_orchard": {"enemy": "Костяной дозорный", "status": "wound", "label": "рана тяжёлого удара", "counter": "Костяная прослойка"},
        "echo_obelisk": {"enemy": "Эхо-огонёк", "status": "distortion", "label": "искажение", "counter": "Глушитель фантома"},
        "fault_line": {"enemy": "Эхо-огонёк", "status": "distortion", "label": "искажение", "counter": "Глушитель фантома"},
        "signal": {"enemy": "резонансные элиты", "status": "weakness", "label": "ослабление", "counter": "Чистый тон"}
    }
    if not threat_profiles.has(tile_id):
        return ""
    var profile: Dictionary = threat_profiles[tile_id]
    var status_id := str(profile.get("status", ""))
    var stats: Dictionary = inventory_system.total_equipment_stats(equipment)
    var resistance := clampf(float(stats.get(status_id + "_resistance", 0.0)), 0.0, 0.25)
    var line := "Контр-стратегия против %s: %s." % [str(profile.get("enemy", "угрозы")), str(profile.get("label", "особого эффекта"))]
    if resistance > 0.0:
        line += " Текущая экипировка: %d%% шанс подавить эффект." % int(round(resistance * 100.0))
    else:
        line += " В сборке пока нет профильной защиты; подходящий модификатор: «%s»." % str(profile.get("counter", "контр-модификатор"))
    return line

func _get_base_forecast(tile_id: String) -> Dictionary:
    match tile_id:
        "cache":
            return {"spawn": Localization.text("tile.forecast.no_change"), "enemy": Localization.text("tile.forecast.no_change"), "reward": Localization.text("tile.forecast.no_change")}
        "hunt":
            return {"spawn": "+60 п.п.", "enemy": Localization.text("tile.forecast.no_change"), "reward": "+45%"}
        "ward":
            return {"spawn": Localization.text("tile.forecast.no_change"), "enemy": Localization.text("tile.forecast.no_change"), "reward": Localization.text("tile.forecast.no_change"), "heal": 7}
        "rift":
            return {"spawn": "+85 п.п.", "enemy": "+45%", "reward": "+80%"}
        "snare":
            return {"spawn": "−12 п.п.", "enemy": "−10%", "reward": Localization.text("tile.forecast.no_change")}
        "signal":
            return {"spawn": "+15 п.п.", "enemy": Localization.text("tile.forecast.no_change"), "reward": "+30%"}
        "archive":
            return {"spawn": Localization.text("tile.forecast.no_change"), "enemy": Localization.text("tile.forecast.no_change"), "reward": "+8%", "scrap": 2, "crystals": 1}
        "nursery":
            return {"spawn": "+28 п.п.", "enemy": "+12%", "reward": "+25%"}
        "lost_convoy":
            return {"spawn": "+6 п.п.", "enemy": "+3%", "reward": "+12%", "scrap": 3, "rarity_bonus": "+12 п.п. до находки"}
        "hunter_marker":
            return {"spawn": "+18 п.п.", "enemy": "+5%", "reward": "+18%", "item_chance_bonus": "+15 п.п. до находки"}
    return {"spawn": Localization.text("tile.forecast.no_change"), "enemy": Localization.text("tile.forecast.no_change"), "reward": Localization.text("tile.forecast.no_change")}
