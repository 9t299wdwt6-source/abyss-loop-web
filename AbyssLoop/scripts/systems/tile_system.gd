extends RefCounted
class_name TileSystem

const ResourceSystemScript = preload("res://scripts/systems/resource_system.gd")
const WORLD_FIELD_COLUMNS := 10
const WORLD_FIELD_ROWS := 8
const WORLD_FIELD_KEYS := [
    "0:0", "1:0", "2:0", "7:0", "8:0", "9:0", "0:1", "9:1", "0:2", "4:2", "5:2",
    "3:3", "4:3", "5:3", "6:3", "2:4", "3:4", "4:4", "5:4", "6:4", "7:4",
    "3:5", "4:5", "5:5", "6:5", "0:6", "9:6", "0:7", "1:7", "2:7", "7:7", "8:7", "9:7"
]
const MAX_WORLD_TILES_PER_ROUTE_SECTOR := 2
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

static func world_cell_id(col: int, row: int) -> String:
    return "%d:%d" % [col, row]

static func is_world_cell_valid(cell_id: String) -> bool:
    return WORLD_FIELD_KEYS.has(cell_id)

static func world_route_index(cell_id: String, route_size: int) -> int:
    if route_size <= 0:
        return -1
    var parts := cell_id.split(":")
    if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
        return -1
    var col := int(parts[0])
    var row := int(parts[1])
    if col < 0 or col >= WORLD_FIELD_COLUMNS or row < 0 or row >= WORLD_FIELD_ROWS:
        return -1
    var nx := 0.029 + (float(col) + 0.5) * 0.942 / float(WORLD_FIELD_COLUMNS)
    var ny := 0.081 + (float(row) + 0.5) * 0.838 / float(WORLD_FIELD_ROWS)
    var angle := atan2(ny - 0.51, nx - 0.5)
    var route_position := fposmod(angle + PI * 0.5, TAU) / TAU
    return posmod(roundi(route_position * float(route_size)), route_size)

func can_place_world(route: Array, world_tiles: Dictionary, cell_id: String) -> Dictionary:
    if route.is_empty():
        return {"ok": false, "reason": "Маршрут ещё не создан."}
    if not is_world_cell_valid(cell_id):
        return {"ok": false, "reason": "Эта клетка не относится к доступному ландшафту."}
    if world_tiles.has(cell_id):
        return {"ok": false, "reason": "На этой клетке уже размещён тайл."}
    var route_index := world_route_index(cell_id, route.size())
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
    var parts := cell_id.split(":")
    if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
        return matches
    var col := int(parts[0])
    var row := int(parts[1])
    for pos in [Vector2i(col - 1, row), Vector2i(col + 1, row), Vector2i(col, row - 1), Vector2i(col, row + 1)]:
        var neighbor_key := world_cell_id(pos.x, pos.y)
        if not is_world_cell_valid(neighbor_key) or not world_tiles.has(neighbor_key):
            continue
        var neighbor_value: Variant = world_tiles[neighbor_key]
        if typeof(neighbor_value) != TYPE_DICTIONARY:
            continue
        var neighbor_id := str(neighbor_value.get("id", ""))
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
    var parts := changed_cell.split(":")
    if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
        var col := int(parts[0])
        var row := int(parts[1])
        for pos in [Vector2i(col - 1, row), Vector2i(col + 1, row), Vector2i(col, row - 1), Vector2i(col, row + 1)]:
            var neighbor_key := world_cell_id(pos.x, pos.y)
            if is_world_cell_valid(neighbor_key) and not affected_cells.has(neighbor_key):
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
    var parts := changed_cell.split(":")
    if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
        var col := int(parts[0])
        var row := int(parts[1])
        for pos in [Vector2i(col - 1, row), Vector2i(col + 1, row), Vector2i(col, row - 1), Vector2i(col, row + 1)]:
            var neighbor_key := world_cell_id(pos.x, pos.y)
            if is_world_cell_valid(neighbor_key) and not affected_cells.has(neighbor_key):
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

func get_world_placement_preview(route: Array, world_tiles: Dictionary, cell_id: String, tile: Dictionary) -> Dictionary:
    var placement := can_place_world(route, world_tiles, cell_id)
    if not bool(placement.get("ok", false)):
        return {"ok": false, "reason": str(placement.get("reason", "Размещение запрещено.")), "text": str(placement.get("reason", "Размещение запрещено."))}
    var tile_id := str(tile.get("id", ""))
    var definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
    if definition.is_empty():
        return {"ok": false, "reason": "Неизвестный тип тайла.", "text": "Неизвестный тип тайла."}
    var simulated := world_tiles.duplicate(true)
    var simulated_tile := tile.duplicate(true)
    var parts := cell_id.split(":")
    simulated_tile["route_index"] = int(placement.get("route_index", -1))
    simulated_tile["field_x"] = int(parts[0])
    simulated_tile["field_y"] = int(parts[1])
    simulated[cell_id] = simulated_tile
    var new_matches := get_new_world_synergy_matches(world_tiles, simulated, cell_id)
    var baseline := _get_base_forecast(tile_id)
    var lines: Array[String] = [str(definition.get("name", tile_id)), str(definition.get("description", "")), Localization.text("tile.forecast.world_sector") % (int(placement.get("route_index", 0)) + 1), Localization.text("tile.forecast.world_baseline") % [str(baseline.get("spawn", Localization.text("tile.forecast.no_change"))), str(baseline.get("enemy", Localization.text("tile.forecast.no_change"))), str(baseline.get("reward", Localization.text("tile.forecast.no_change")))]]
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
    lines.append(Localization.text("tile.forecast.world_synergy_caps"))
    lines.append(Localization.text("tile.forecast.world_visit_caps"))
    var preview_effects := {
        "scrap": int(total_effects.get("scrap", 0)),
        "heal": int(total_effects.get("heal", 0)),
        "reward_bonus": float(total_effects.get("reward", 0.0)),
        "spawn_bonus": float(total_effects.get("spawn_bonus", 0.0)),
        "enemy_bonus": float(total_effects.get("enemy_bonus", 0.0))
    }

    return {"ok": true, "reason": "Ландшафт доступен для размещения.", "text": "\n".join(lines), "route_index": int(placement.get("route_index", -1)), "synergies": synergy_names, "new_synergy_matches": new_matches, "synergy_effects": preview_effects, "synergy_sector_deltas": effect_delta.get("sectors", []), "synergy_caps_applied": effect_delta.get("caps_applied", []), "forecast": baseline}

func draw_tile(rng: RandomNumberGenerator, unlock_rift: bool) -> Dictionary:
    var choices := ["cache", "hunt", "ward", "snare"]
    if unlock_rift:
        choices.append("rift")
        choices.append("signal")
    var tile_id: String = choices[rng.randi_range(0, choices.size() - 1)]
    var def: Dictionary = ContentRegistry.TILE_DEFS[tile_id]
    return {"id": tile_id, "name": def.name, "short": def.short, "kind": def.kind, "color": def.color, "description": def.description, "uid": str(rng.randi())}

func can_place(route: Array, placed_tiles: Dictionary, index: int) -> Dictionary:
    if index < 0 or index >= route.size():
        return {"ok": false, "reason": "Клетка находится за пределами маршрута."}
    if index == 0:
        return {"ok": false, "reason": "Стартовый узел нельзя менять."}
    if placed_tiles.has(str(index)):
        return {"ok": false, "reason": "На этой клетке уже есть тайл."}
    return {"ok": true, "reason": "Тайл можно разместить."}

func apply_tile_visit(tile: Dictionary, ledger: Dictionary, hero: Dictionary, loop_count: int) -> Dictionary:
    var result := {"messages": [], "spawn_bonus": 0.0, "enemy_bonus": 0.0, "reward_bonus": 0.0}
    var tile_id := str(tile.get("id", ""))
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
    return result

func get_synergy_bonus(placed_tiles: Dictionary, index: int, route_size: int = 0) -> Dictionary:
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
    return bonus

func get_placement_preview(route: Array, placed_tiles: Dictionary, index: int, tile: Dictionary) -> Dictionary:
    var placement: Dictionary = can_place(route, placed_tiles, index)
    var tile_id := str(tile.get("id", ""))
    var definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
    if not bool(placement.get("ok", false)):
        return {"ok": false, "reason": str(placement.get("reason", "Размещение запрещено.")), "text": str(placement.get("reason", "Размещение запрещено."))}
    if definition.is_empty():
        return {"ok": false, "reason": "Неизвестный тип тайла.", "text": "Неизвестный тип тайла."}

    var simulated: Dictionary = placed_tiles.duplicate(true)
    simulated[str(index)] = tile.duplicate(true)
    var synergy: Dictionary = get_synergy_bonus(simulated, index, route.size())
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
    return {"ok": true, "reason": "Тайл можно разместить.", "text": "\n".join(lines), "synergies": synergy.get("synergies", []).duplicate(true), "forecast": baseline}

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
    return {"spawn": Localization.text("tile.forecast.no_change"), "enemy": Localization.text("tile.forecast.no_change"), "reward": Localization.text("tile.forecast.no_change")}
