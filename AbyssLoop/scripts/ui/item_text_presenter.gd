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
	if float(item.get("lifesteal", 0.0)) > 0.0:
		bonuses.append("вампиризм %d%%" % int(round(float(item.get("lifesteal", 0.0)) * 100.0)))
	if float(item.get("dodge_chance", 0.0)) > 0.0:
		bonuses.append("уклонение %d%%" % int(round(float(item.get("dodge_chance", 0.0)) * 100.0)))
	if float(item.get("special_damage_reduction", 0.0)) > 0.0:
		bonuses.append("защита от особых атак %d%%" % int(round(float(item.get("special_damage_reduction", 0.0)) * 100.0)))
	if float(item.get("elite_boss_damage_bonus", 0.0)) > 0.0:
		bonuses.append("урон элите и боссам +%d%%" % int(round(float(item.get("elite_boss_damage_bonus", 0.0)) * 100.0)))
	if float(item.get("biome_damage_bonus", 0.0)) > 0.0:
		bonuses.append("урон существам ландшафта +%d%%" % int(round(float(item.get("biome_damage_bonus", 0.0)) * 100.0)))
	if float(item.get("biome_resistance", 0.0)) > 0.0:
		bonuses.append("защита от существ ландшафта %d%%" % int(round(float(item.get("biome_resistance", 0.0)) * 100.0)))
	if float(item.get("trophy_find_bonus", 0.0)) > 0.0:
		bonuses.append("шанс трофея биома +%d п.п." % int(round(float(item.get("trophy_find_bonus", 0.0)) * 100.0)))
	if float(item.get("road_formation_bonus", 0.0)) > 0.0:
		bonuses.append("награда от формаций дороги +%d%%" % int(round(float(item.get("road_formation_bonus", 0.0)) * 100.0)))
	if float(item.get("rare_find_bonus", 0.0)) > 0.0:
		bonuses.append("шкала редкости находок +%d п.п." % int(round(float(item.get("rare_find_bonus", 0.0)) * 100.0)))
	var status_labels := {"poison": "подавить яд", "bleed": "подавить кровотечение", "wound": "подавить рану", "distortion": "подавить искажение", "weakness": "подавить ослабление"}
	for status_id in status_labels.keys():
		var status_resistance := float(item.get(status_id + "_resistance", 0.0))
		if status_resistance > 0.0:
			bonuses.append("шанс %s %d%%" % [str(status_labels[status_id]), int(round(status_resistance * 100.0))])
	for biome_tag in ["spore", "crystal", "bone", "echo"]:
		var damage_value := float(item.get(biome_tag + "_damage_bonus", 0.0))
		var resistance_value := float(item.get(biome_tag + "_resistance", 0.0))
		var trophy_value := float(item.get(biome_tag + "_trophy_bonus", 0.0))
		var biome_label: String = str({"spore": "спорам", "crystal": "кристаллам", "bone": "костяным", "echo": "эхо-сущностям"}.get(biome_tag, biome_tag))
		if damage_value > 0.0:
			bonuses.append("урон %s +%d%%" % [biome_label, int(round(damage_value * 100.0))])
		if resistance_value > 0.0:
			bonuses.append("защита от %s %d%%" % [biome_label, int(round(resistance_value * 100.0))])
		if trophy_value > 0.0:
			bonuses.append("шанс трофея биома %s +%d п.п." % [biome_label, int(round(trophy_value * 100.0))])
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
	elif float(item.get("tile_spawn_bonus", 0.0)) > 0.0:
		bonuses.append("риск встречи +%d%%" % int(round(float(item.get("tile_spawn_bonus", 0.0)) * 100.0)))
	if float(item.get("bleed_chance", 0.0)) > 0.0:
		bonuses.append("шанс кровотечения %d%%" % int(round(float(item.get("bleed_chance", 0.0)) * 100.0)))
	if int(item.get("bleed_damage", 0)) > 0:
		bonuses.append("урон кровотечения +%d" % int(item.get("bleed_damage", 0)))
	if int(item.get("barrier_on_encounter", 0)) > 0:
		bonuses.append("барьер в начале боя +%d" % int(item.get("barrier_on_encounter", 0)))
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


static func format_stat_comparison(candidate: Dictionary, current: Dictionary) -> String:
	if current.is_empty():
		return "Текущий слот пуст — сравнивать не с чем."
	var rows: Array[String] = []
	var biome_names := {"spore": "споры", "crystal": "кристаллы", "bone": "кости", "echo": "эхо"}
	var status_names := {"poison": "яд", "bleed": "кровотечение", "wound": "рана", "distortion": "искажение", "weakness": "ослабление"}
	var stat_defs := [
		{"key": "attack", "name": "Атака", "mode": "int"},
		{"key": "defense", "name": "Защита", "mode": "int"},
		{"key": "hp", "name": "Здоровье", "mode": "int"},
		{"key": "speed", "name": "Скорость атаки", "mode": "pct"},
		{"key": "crit", "name": "Критический шанс", "mode": "pp"},
		{"key": "lifesteal", "name": "Вампиризм", "mode": "pp"},
		{"key": "dodge_chance", "name": "Уклонение", "mode": "pp"},
		{"key": "special_damage_reduction", "name": "Защита от особых атак", "mode": "pp"},
		{"key": "elite_boss_damage_bonus", "name": "Урон элите/боссам", "mode": "pp"},
		{"key": "reward_bonus", "name": "Награда", "mode": "pp"},
		{"key": "rare_find_bonus", "name": "Редкость находок", "mode": "pp"},
		{"key": "trophy_find_bonus", "name": "Шанс трофея", "mode": "pp"},
		{"key": "road_formation_bonus", "name": "Награда формаций", "mode": "pp"},
		{"key": "tile_spawn_bonus", "name": "Риск встречи", "mode": "pp"},
		{"key": "biome_damage_bonus", "name": "Урон существам ландшафта", "mode": "pp"},
		{"key": "biome_resistance", "name": "Защита от существ ландшафта", "mode": "pp"},
		{"key": "tile_scrap", "name": "Материалы за тайл", "mode": "int"},
		{"key": "kill_heal", "name": "Лечение за победу", "mode": "int"},
		{"key": "event_heal", "name": "Лечение после события", "mode": "int"},
		{"key": "bleed_chance", "name": "Шанс кровотечения", "mode": "pp"},
		{"key": "barrier_on_encounter", "name": "Стартовый барьер", "mode": "int"}
	]
	for biome in ["spore", "crystal", "bone", "echo"]:
		var biome_label: String = str(biome_names.get(biome, biome))
		stat_defs.append({"key": biome + "_damage_bonus", "name": "Урон: " + biome_label, "mode": "pp"})
		stat_defs.append({"key": biome + "_resistance", "name": "Сопротивление: " + biome_label, "mode": "pp"})
		stat_defs.append({"key": biome + "_trophy_bonus", "name": "Трофеи: " + biome_label, "mode": "pp"})
	for status_id in ["poison", "bleed", "wound", "distortion", "weakness"]:
		stat_defs.append({"key": status_id + "_resistance", "name": "Подавить: " + str(status_names.get(status_id, status_id)), "mode": "pp"})
	for definition_value in stat_defs:
		var definition: Dictionary = definition_value
		var stat_key := str(definition.get("key", ""))
		var before_value := float(current.get(stat_key, 0.0))
		var after_value := float(candidate.get(stat_key, 0.0))
		var delta := after_value - before_value
		if absf(delta) < 0.0005:
			continue
		var mode := str(definition.get("mode", "int"))
		var shown_delta := int(round(delta))
		var suffix := ""
		if mode == "pp":
			shown_delta = int(round(delta * 100.0))
			suffix = " п.п."
		elif mode == "pct":
			shown_delta = int(round(delta * 100.0))
			suffix = "%"
		rows.append("%s: %s%d%s" % [str(definition.get("name", stat_key)), "+" if shown_delta > 0 else "", shown_delta, suffix])
	return "\n".join(rows) if not rows.is_empty() else "Численные бонусы не меняются; решение зависит от набора, аффиксов и силы предмета."


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

