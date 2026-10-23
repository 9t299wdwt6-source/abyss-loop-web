extends RefCounted

## Pure presentation helpers for equipment text. This component does not mutate items,
## inventory, equipment slots, or game state.

static func format_value_list(values: Array) -> String:
	var strings: Array[String] = []
	for value in values:
		strings.append(str(value))
	return ", ".join(strings)

static func format_item_bonus(item: Dictionary) -> String:
	var bonuses: Array[String] = []
	if int(item.get("attack", 0)) > 0:
		bonuses.append("АТК +%d" % int(item.get("attack", 0)))
	if int(item.get("defense", 0)) > 0:
		bonuses.append("ЗАЩ +%d" % int(item.get("defense", 0)))
	if int(item.get("hp", 0)) > 0:
		bonuses.append("ЗДР +%d" % int(item.get("hp", 0)))
	if float(item.get("speed", 0.0)) > 0.0:
		bonuses.append("СКР +%d%%" % int(round(float(item.get("speed", 0.0)) * 100.0)))
	if float(item.get("crit", 0.0)) > 0.0:
		bonuses.append("КРИТ +%d%%" % int(round(float(item.get("crit", 0.0)) * 100.0)))
	if int(item.get("kill_heal", 0)) > 0:
		bonuses.append("лечение за победу +%d" % int(item.get("kill_heal", 0)))
	if int(item.get("tile_scrap", 0)) > 0:
		bonuses.append("материалы за тайл +%d" % int(item.get("tile_scrap", 0)))
	if int(item.get("event_heal", 0)) > 0:
		bonuses.append("лечение после события +%d" % int(item.get("event_heal", 0)))
	if float(item.get("reward_bonus", 0.0)) > 0.0:
		bonuses.append("добыча +%d%%" % int(round(float(item.get("reward_bonus", 0.0)) * 100.0)))
	if float(item.get("tile_spawn_bonus", 0.0)) < 0.0:
		bonuses.append("шанс боя %d%%" % int(round(float(item.get("tile_spawn_bonus", 0.0)) * 100.0)))
	return ", ".join(bonuses) if not bonuses.is_empty() else "без бонусов"

static func format_item_comparison(has_current_item: bool, delta: float) -> String:
	if not has_current_item:
		return "новый слот"
	var detail := "%+.1f силы" % delta
	if delta > 0.05:
		return "улучшение " + detail
	if delta < -0.05:
		return "слабее " + detail
	return "примерно равно " + detail


static func format_loadout_synergy_preview(current_stats: Dictionary, candidate_stats: Dictionary, synergy_definitions: Dictionary) -> String:
	var current_synergies: Array = current_stats.get("active_synergies", [])
	var next_synergies: Array = candidate_stats.get("active_synergies", [])
	var current_sets: Array = current_stats.get("active_sets", [])
	var next_sets: Array = candidate_stats.get("active_sets", [])
	var current_synergy_text := format_value_list(current_synergies) if not current_synergies.is_empty() else "нет"
	var next_synergy_text := format_value_list(next_synergies) if not next_synergies.is_empty() else "нет"
	var current_set_text := format_value_list(current_sets) if not current_sets.is_empty() else "нет"
	var next_set_text := format_value_list(next_sets) if not next_sets.is_empty() else "нет"
	var comparison := "Синергия до: %s → после экипировки: %s.\nНаборы до: %s → после: %s." % [current_synergy_text, next_synergy_text, current_set_text, next_set_text]
	if not next_synergies.is_empty():
		for synergy_id_value in synergy_definitions.keys():
			var synergy_id := str(synergy_id_value)
			var synergy: Dictionary = synergy_definitions[synergy_id]
			if next_synergies.has(str(synergy.get("name", synergy_id))):
				comparison += "\nЭффект: " + str(synergy.get("description", ""))
	return comparison

