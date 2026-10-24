extends RefCounted
class_name InventorySystem

const SLOT_NAMES := {"weapon": "Оружие", "armor": "Броня", "core": "Ядро"}
const MAX_UPGRADE_LEVEL := 10

# Affixes are data-driven: their numeric fields are aggregated centrally and
# consumed by ExpeditionManager, so the UI does not implement equipment rules.
const ARCHETYPES := {
	"weapon": [
		{"id": "assault", "name": "Штурм", "description": "Дополнительный урон", "stats": {"attack": 2}},
		{"id": "precision", "name": "Точность", "description": "Повышенный шанс критического удара", "stats": {"crit": 0.035}},
		{"id": "siphon", "name": "Сифон", "description": "Восстанавливает здоровье после победы", "stats": {"kill_heal": 3}},
		{"id": "wound", "name": "Резец глубин", "description": "Шанс вызвать кровотечение при ударе", "stats": {"bleed_chance": 0.20, "bleed_damage": 2}}
	],
	"armor": [
		{"id": "bastion", "name": "Бастион", "description": "Усиленная защита и барьер в начале боя", "stats": {"defense": 1, "hp": 5, "barrier_on_encounter": 6}},
		{"id": "scavenger", "name": "Сборщик", "description": "Дополнительные материалы при посещении тайлов", "stats": {"tile_scrap": 1}},
		{"id": "field_medic", "name": "Полевой медик", "description": "Небольшое лечение после решения события", "stats": {"event_heal": 3}}
	],
	"core": [
		{"id": "tempo", "name": "Темп", "description": "Ускоренные атаки", "stats": {"speed": 0.045}},
		{"id": "resonance", "name": "Резонанс", "description": "Повышенная добыча за победу", "stats": {"reward_bonus": 0.08}},
		{"id": "pathfinder", "name": "Разведчик", "description": "Снижает шанс встречи на узлах маршрута", "stats": {"tile_spawn_bonus": -0.04}}
	]
}

const SET_DEFS := {
	"vanguard": {"name": "Авангард", "threshold": 2, "effects": {"defense": 2, "hp": 8}, "description": "2 предмета: +2 защиты и +8 здоровья."},
	"scavenger": {"name": "Снабжение", "threshold": 2, "effects": {"tile_scrap": 2}, "description": "2 предмета: +2 материала при посещении тайлов."},
	"resonance": {"name": "Резонанс", "threshold": 2, "effects": {"reward_bonus": 0.12, "crit": 0.025}, "description": "2 предмета: +12% награды и +2,5% критического шанса."}
}

# Archetype synergies are intentionally small, mutually exclusive bonuses.
# They reward a deliberate loadout without making raw item rank irrelevant.
# Named relic drops make boss victories different from ordinary random equipment.
# Each boss can drop either piece of a signature two-piece set.
const BOSS_RELIC_TABLES := {
	"warden": [
		{"id": "warden_edge", "name": "Кромка нулевого узла", "slot": "weapon", "archetype": "assault", "archetype_name": "Штурм", "archetype_description": "Реликвия Стража: агрессивный клинок, настроенный на пробой защиты.", "set_id": "vanguard", "stats": {"attack": 4, "crit": 0.04}},
		{"id": "warden_shell", "name": "Панцирь древнего узла", "slot": "armor", "archetype": "bastion", "archetype_name": "Бастион", "archetype_description": "Реликвия Стража: тяжёлая броня и барьер в начале столкновения.", "set_id": "vanguard", "stats": {"defense": 2, "hp": 12, "barrier_on_encounter": 10}}
	],
	"harvester": [
		{"id": "harvester_needle", "name": "Игла Светожора", "slot": "weapon", "archetype": "wound", "archetype_name": "Резец глубин", "archetype_description": "Реликвия Светожора: импульсный клинок, вызывающий глубокие раны.", "set_id": "resonance", "stats": {"attack": 3, "crit": 0.025, "bleed_chance": 0.18, "bleed_damage": 3}},
		{"id": "harvester_heart", "name": "Сердце импульсов", "slot": "core", "archetype": "resonance", "archetype_name": "Резонанс", "archetype_description": "Реликвия Светожора: усиливает импульс героя, добычу и восстановление после побед.", "set_id": "resonance", "stats": {"hp": 8, "speed": 0.06, "reward_bonus": 0.15, "kill_heal": 1}}
	]
}

const SYNERGY_DEFS := {
	"overclock_assault": {
		"name": "Контур перегрузки",
		"description": "Штурм/Резец глубин + Темп: +1 атака, +3,5% скорости.",
		"requirements": {"weapon": ["assault", "wound"], "core": ["tempo"]},
		"effects": {"attack": 1, "speed": 0.035}
	},
	"precision_resonance": {
		"name": "Эхо охотника",
		"description": "Точность + Резонанс: +3,5% критического шанса, +5% награды.",
		"requirements": {"weapon": ["precision"], "core": ["resonance"]},
		"effects": {"crit": 0.035, "reward_bonus": 0.05}
	},
	"salvage_route": {
		"name": "Маршрут сборщика",
		"description": "Сборщик + Разведчик: +1 материал на тайле, −2 п.п. шанса встречи.",
		"requirements": {"armor": ["scavenger"], "core": ["pathfinder"]},
		"effects": {"tile_scrap": 1, "tile_spawn_bonus": -0.02}
	},
	"bastion_siphon": {
		"name": "Живучий бастион",
		"description": "Сифон + Бастион: +6 здоровья, +1 лечение после победы.",
		"requirements": {"weapon": ["siphon"], "armor": ["bastion"]},
		"effects": {"hp": 6, "kill_heal": 1}
	}
}

# Caps apply to aggregated modifiers, not to base hero statistics.
# Crit is an additive modifier; the hero's base 5% is added after this layer.
const BUILD_STAT_CAPS := {
	"speed": {"min": -0.5, "max": 1.5},
	"crit": {"min": 0.0, "max": 0.70},
	"reward_bonus": {"min": 0.0, "max": 1.5},
	"tile_spawn_bonus": {"min": -0.25, "max": 0.25},
	"bleed_chance": {"min": 0.0, "max": 0.5},
	"bleed_damage": {"min": 0, "max": 100},
	"barrier_on_encounter": {"min": 0, "max": 100},
	"kill_heal": {"min": 0, "max": 10},
	"tile_scrap": {"min": 0, "max": 5},
	"event_heal": {"min": 0, "max": 10}
}

func roll_item(rng: RandomNumberGenerator, loop_count: int, hero_level: int) -> Dictionary:
	var slots: Array = ["weapon", "armor", "core"]
	var slot: String = str(slots[rng.randi_range(0, slots.size() - 1)])
	var rarity_roll := rng.randf()
	var rarity := "Обычный"
	var multiplier := 1.0
	if rarity_roll > 0.94:
		rarity = "Эпический"
		multiplier = 1.8
	elif rarity_roll > 0.70:
		rarity = "Редкий"
		multiplier = 1.35
	var rank := 1 + int(floor(float(loop_count) / 2.0)) + int(floor(float(hero_level) / 3.0))
	var archetype_values: Array = ARCHETYPES.get(slot, [])
	var archetype: Dictionary = {"id": "standard", "name": "Стандарт", "description": "Базовые характеристики", "stats": {}}
	if not archetype_values.is_empty():
		archetype = archetype_values[rng.randi_range(0, archetype_values.size() - 1)].duplicate(true)
	var set_ids: Array = SET_DEFS.keys()
	var set_id: String = str(set_ids[rng.randi_range(0, set_ids.size() - 1)])
	var set_definition: Dictionary = SET_DEFS[set_id]
	var item := {
		"id": "%s_%d_%d" % [slot, loop_count, rng.randi()],
		"slot": slot,
		"name": "%s · %s · %s" % [SLOT_NAMES[slot], str(archetype.get("name", "Стандарт")), rarity],
		"rarity": rarity,
		"rank": rank,
		"upgrade_level": 0,
		"archetype": str(archetype.get("id", "standard")),
		"archetype_name": str(archetype.get("name", "Стандарт")),
		"archetype_description": str(archetype.get("description", "")),
		"set_id": set_id,
		"set_name": str(set_definition.get("name", set_id)),
		"attack": 0,
		"defense": 0,
		"hp": 0,
		"speed": 0.0,
		"crit": 0.0,
		"kill_heal": 0,
		"tile_scrap": 0,
		"event_heal": 0,
		"reward_bonus": 0.0,
		"tile_spawn_bonus": 0.0,
		"bleed_chance": 0.0,
		"bleed_damage": 0,
		"barrier_on_encounter": 0
	}
	match slot:
		"weapon":
			item.attack = maxi(1, int(round((1.0 + float(rank) * 0.5 + rng.randi_range(0, 1)) * multiplier)))
		"armor":
			item.defense = maxi(1, int(round((1.0 + float(rank) * 0.25) * multiplier)))
			item.hp = int(round((4.0 + float(rank) * 2.0) * multiplier))
		"core":
			item.speed = snappedf(0.04 + minf(0.13, float(rank) * 0.015), 0.01)
			item.crit = snappedf(0.025 + minf(0.07, float(rank) * 0.008), 0.005)
			item.attack = maxi(0, int(round(float(rank) * 0.3 * multiplier)))
	var archetype_stats_value: Variant = archetype.get("stats", {})
	if typeof(archetype_stats_value) == TYPE_DICTIONARY:
		for stat_key_value in archetype_stats_value.keys():
			var stat_key := str(stat_key_value)
			if item.has(stat_key):
				item[stat_key] = item.get(stat_key, 0) + archetype_stats_value[stat_key_value]
	item["power"] = item_power(item)
	return item

func roll_boss_item(enemy: Dictionary, rng: RandomNumberGenerator, loop_count: int, hero_level: int) -> Dictionary:
	var boss_id := str(enemy.get("id", ""))
	var templates_value: Variant = BOSS_RELIC_TABLES.get(boss_id, [])
	if typeof(templates_value) != TYPE_ARRAY:
		return {}
	var templates: Array = templates_value
	if templates.is_empty():
		return {}
	var template_value: Variant = templates[rng.randi_range(0, templates.size() - 1)]
	if typeof(template_value) != TYPE_DICTIONARY:
		return {}
	var template: Dictionary = template_value
	var slot := str(template.get("slot", ""))
	if not SLOT_NAMES.has(slot):
		return {}
	var set_id := str(template.get("set_id", ""))
	var set_definition: Dictionary = SET_DEFS.get(set_id, {})
	var rank := 1 + int(floor(float(maxi(0, loop_count)) / 2.0)) + int(floor(float(maxi(1, hero_level)) / 3.0))
	var item := {
		"id": "boss_%s_%d_%d" % [str(template.get("id", boss_id)), loop_count, rng.randi()],
		"unique_id": str(template.get("id", boss_id)), "slot": slot,
		"name": str(template.get("name", "Реликвия бездны")), "rarity": "Боссовая",
		"rank": rank, "upgrade_level": 0,
		"archetype": str(template.get("archetype", "standard")),
		"archetype_name": str(template.get("archetype_name", "Реликвия")),
		"archetype_description": str(template.get("archetype_description", "Именная экипировка босса.")),
		"set_id": set_id, "set_name": str(set_definition.get("name", set_id)),
		"is_boss_relic": true, "source_enemy_id": boss_id,
		"source_enemy_name": str(enemy.get("name", boss_id)),
		"attack": 0, "defense": 0, "hp": 0, "speed": 0.0, "crit": 0.0,
		"kill_heal": 0, "tile_scrap": 0, "event_heal": 0, "reward_bonus": 0.0,
		"tile_spawn_bonus": 0.0, "bleed_chance": 0.0, "bleed_damage": 0,
		"barrier_on_encounter": 0
	}
	var template_stats_value: Variant = template.get("stats", {})
	if typeof(template_stats_value) == TYPE_DICTIONARY:
		var template_stats: Dictionary = template_stats_value
		for stat_key_value in template_stats.keys():
			var stat_key := str(stat_key_value)
			if item.has(stat_key):
				item[stat_key] = template_stats[stat_key_value]
	# Signature items gain rank with the expedition while keeping a bounded profile.
	var rank_bonus := mini(5, maxi(0, rank - 2))
	if int(item.get("attack", 0)) > 0:
		item["attack"] = int(item.get("attack", 0)) + rank_bonus
	if int(item.get("defense", 0)) > 0:
		item["defense"] = int(item.get("defense", 0)) + floori(float(rank_bonus) / 2.0)
	if int(item.get("hp", 0)) > 0:
		item["hp"] = int(item.get("hp", 0)) + rank_bonus * 2
	if float(item.get("speed", 0.0)) > 0.0:
		item["speed"] = minf(0.20, float(item.get("speed", 0.0)) + minf(0.04, float(rank_bonus) * 0.005))
	if float(item.get("crit", 0.0)) > 0.0:
		item["crit"] = minf(0.20, float(item.get("crit", 0.0)) + minf(0.035, float(rank_bonus) * 0.005))
	if int(item.get("kill_heal", 0)) > 0:
		item["kill_heal"] = int(item.get("kill_heal", 0)) + floori(float(rank_bonus) / 2.0)
	if int(item.get("bleed_damage", 0)) > 0:
		item["bleed_damage"] = int(item.get("bleed_damage", 0)) + floori(float(rank_bonus) / 3.0)
	if float(item.get("bleed_chance", 0.0)) > 0.0:
		item["bleed_chance"] = minf(0.5, float(item.get("bleed_chance", 0.0)) + float(rank_bonus) * 0.01)
	if int(item.get("barrier_on_encounter", 0)) > 0:
		item["barrier_on_encounter"] = int(item.get("barrier_on_encounter", 0)) + rank_bonus * 2
	if float(item.get("reward_bonus", 0.0)) > 0.0:
		item["reward_bonus"] = minf(1.5, float(item.get("reward_bonus", 0.0)) + minf(0.08, float(rank_bonus) * 0.01))
	item["power"] = item_power(item)
	return item

func item_power(item: Dictionary) -> float:
	var score := float(item.get("attack", 0)) * 2.0
	score += float(item.get("defense", 0)) * 2.5
	score += float(item.get("hp", 0)) * 0.12
	score += float(item.get("speed", 0.0)) * 18.0
	score += float(item.get("crit", 0.0)) * 15.0
	score += float(item.get("kill_heal", 0)) * 1.4
	score += float(item.get("tile_scrap", 0)) * 1.2
	score += float(item.get("event_heal", 0)) * 0.9
	score += float(item.get("reward_bonus", 0.0)) * 18.0
	score += absf(float(item.get("tile_spawn_bonus", 0.0))) * 8.0
	score += clampf(float(item.get("bleed_chance", 0.0)), 0.0, 0.5) * 12.0
	score += float(item.get("bleed_damage", 0)) * 1.4
	score += float(item.get("barrier_on_encounter", 0)) * 1.0
	return score

func get_upgrade_cost(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var upgrade_level := maxi(0, int(item.get("upgrade_level", 0)))
	if upgrade_level >= MAX_UPGRADE_LEVEL:
		return {"available": false, "scrap": 0, "crystals": 0, "upgrade_level": upgrade_level, "max_level": MAX_UPGRADE_LEVEL}
	var rarity := str(item.get("rarity", "Обычный"))
	var rarity_multiplier := 1.0
	var rarity_crystals := 0
	match rarity:
		"Редкий":
			rarity_multiplier = 1.25
			rarity_crystals = 1
		"Элитная":
			rarity_multiplier = 1.45
			rarity_crystals = 1
		"Эпический":
			rarity_multiplier = 1.6
			rarity_crystals = 2
		"Боссовая":
			rarity_multiplier = 2.0
			rarity_crystals = 3
	var power_tier := maxi(1, int(item.get("rank", 1))) + upgrade_level
	var scrap_cost := int(ceil(float(18 + power_tier * 7 + upgrade_level * 10) * rarity_multiplier))
	var crystal_cost := 1 + floori(float(power_tier) / 3.0) + rarity_crystals
	return {"available": true, "scrap": scrap_cost, "crystals": crystal_cost, "upgrade_level": upgrade_level, "next_level": upgrade_level + 1, "max_level": MAX_UPGRADE_LEVEL}

func preview_upgrade_item(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var cost := get_upgrade_cost(item)
	if not bool(cost.get("available", false)):
		return {}
	var upgraded := item.duplicate(true)
	var next_level := int(cost.get("next_level", 1))
	var primary_step := 1 + floori(float(next_level - 1) / 3.0)
	match str(item.get("slot", "")):
		"weapon":
			upgraded["attack"] = int(upgraded.get("attack", 0)) + primary_step
		"armor":
			upgraded["defense"] = int(upgraded.get("defense", 0)) + primary_step
			upgraded["hp"] = int(upgraded.get("hp", 0)) + 2 + next_level
		"core":
			upgraded["speed"] = snappedf(minf(1.5, float(upgraded.get("speed", 0.0)) + 0.01), 0.005)
			upgraded["crit"] = snappedf(minf(0.75, float(upgraded.get("crit", 0.0)) + 0.005), 0.005)
			if next_level % 3 == 0:
				upgraded["attack"] = int(upgraded.get("attack", 0)) + 1
		_:
			return {}
	upgraded["upgrade_level"] = next_level
	upgraded["power"] = item_power(upgraded)
	return upgraded

func get_salvage_reward(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var rarity := str(item.get("rarity", "Обычный"))
	var rarity_scrap := 0
	var crystals := 0
	match rarity:
		"Редкий":
			rarity_scrap = 4
			crystals = 1
		"Элитная":
			rarity_scrap = 7
			crystals = 1
		"Эпический":
			rarity_scrap = 10
			crystals = 2
		"Боссовая":
			rarity_scrap = 14
			crystals = 3
	var rank := maxi(1, int(item.get("rank", 1)))
	var upgrade_level := clampi(int(item.get("upgrade_level", 0)), 0, MAX_UPGRADE_LEVEL)
	return {"scrap": 8 + rank * 5 + upgrade_level * 7 + rarity_scrap, "crystals": crystals + floori(float(upgrade_level) / 3.0)}

func should_equip(candidate: Dictionary, current: Dictionary) -> bool:
	if current.is_empty():
		return true
	return item_power(candidate) > item_power(current)

func total_equipment_stats(equipment: Dictionary) -> Dictionary:
	var stats := _empty_stat_block()
	var set_counts: Dictionary = {}
	for slot_value in ["weapon", "armor", "core"]:
		var item_value: Variant = equipment.get(str(slot_value), {})
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		for stat_key in _numeric_stat_keys():
			stats[stat_key] = stats.get(stat_key, 0) + item.get(stat_key, 0)
		var set_id := str(item.get("set_id", ""))
		if not set_id.is_empty() and SET_DEFS.has(set_id):
			set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1
	for set_id_value in SET_DEFS.keys():
		var set_id := str(set_id_value)
		if int(set_counts.get(set_id, 0)) < int(SET_DEFS[set_id].get("threshold", 2)):
			continue
		var definition: Dictionary = SET_DEFS[set_id]
		stats["active_sets"].append(str(definition.get("name", set_id)))
		var effects_value: Variant = definition.get("effects", {})
		if typeof(effects_value) != TYPE_DICTIONARY:
			continue
		var effects: Dictionary = effects_value
		for effect_key_value in effects.keys():
			var effect_key := str(effect_key_value)
			if stats.has(effect_key):
				stats[effect_key] = stats.get(effect_key, 0) + effects[effect_key_value]
	# At most one archetype synergy can be active at a time, keeping bonus stacking legible.
	for synergy_id_value in SYNERGY_DEFS.keys():
		var synergy_id := str(synergy_id_value)
		var synergy: Dictionary = SYNERGY_DEFS[synergy_id]
		if not _synergy_requirements_match(equipment, synergy.get("requirements", {})):
			continue
		stats["active_synergies"].append(str(synergy.get("name", synergy_id)))
		var effects_value: Variant = synergy.get("effects", {})
		if typeof(effects_value) == TYPE_DICTIONARY:
			var effects: Dictionary = effects_value
			for effect_key_value in effects.keys():
				var effect_key := str(effect_key_value)
				if stats.has(effect_key):
					stats[effect_key] = stats.get(effect_key, 0) + effects[effect_key_value]
		break
	_apply_build_stat_caps(stats)
	stats["power"] = 0.0
	for slot_value in ["weapon", "armor", "core"]:
		var item_value: Variant = equipment.get(str(slot_value), {})
		if typeof(item_value) == TYPE_DICTIONARY:
			stats["power"] = float(stats.get("power", 0.0)) + item_power(item_value)
	return stats

func total_perk_stats(perk_counts: Dictionary) -> Dictionary:
	var stats := _empty_stat_block()
	for perk_id_value in ContentRegistry.PERKS.keys():
		var perk_id := str(perk_id_value)
		var perk: Dictionary = ContentRegistry.PERKS[perk_id]
		var rank := clampi(int(perk_counts.get(perk_id, 0)), 0, maxi(1, int(perk.get("max_stacks", 1))))
		if rank <= 0:
			continue
		for stat_key in _numeric_stat_keys():
			if perk.has(stat_key):
				stats[stat_key] = stats.get(stat_key, 0) + perk[stat_key] * rank
	_apply_build_stat_caps(stats)
	return stats

func calculate_loadout_stats(equipment: Dictionary, perk_counts: Dictionary = {}) -> Dictionary:
	# This is the shared source for derived equipment/set/synergy/perk numbers.
	var equipment_stats := total_equipment_stats(equipment)
	var perk_stats := total_perk_stats(perk_counts)
	var combined := _empty_stat_block()
	for stat_key in _numeric_stat_keys():
		combined[stat_key] = equipment_stats.get(stat_key, 0) + perk_stats.get(stat_key, 0)
	combined["active_sets"] = equipment_stats.get("active_sets", []).duplicate(true)
	combined["active_synergies"] = equipment_stats.get("active_synergies", []).duplicate(true)
	combined["power"] = equipment_stats.get("power", 0.0)
	_apply_build_stat_caps(combined)
	return {"equipment": equipment_stats, "perks": perk_stats, "combined": combined}

func _synergy_requirements_match(equipment: Dictionary, requirements_value: Variant) -> bool:
	if typeof(requirements_value) != TYPE_DICTIONARY:
		return false
	var requirements: Dictionary = requirements_value
	if requirements.is_empty():
		return false
	for slot_value in requirements.keys():
		var slot := str(slot_value)
		var item_value: Variant = equipment.get(slot, {})
		if typeof(item_value) != TYPE_DICTIONARY or item_value.is_empty():
			return false
		var accepted_value: Variant = requirements[slot_value]
		if typeof(accepted_value) != TYPE_ARRAY:
			return false
		var accepted: Array = accepted_value
		if not accepted.has(str(item_value.get("archetype", ""))):
			return false
	return true

func _empty_stat_block() -> Dictionary:
	return {
		"attack": 0, "defense": 0, "hp": 0, "speed": 0.0, "crit": 0.0,
		"kill_heal": 0, "tile_scrap": 0, "event_heal": 0,
		"reward_bonus": 0.0, "tile_spawn_bonus": 0.0, "bleed_chance": 0.0,
		"bleed_damage": 0, "barrier_on_encounter": 0, "active_sets": [], "active_synergies": [], "power": 0.0
	}

func _numeric_stat_keys() -> Array[String]:
	return ["attack", "defense", "hp", "speed", "crit", "kill_heal", "tile_scrap", "event_heal", "reward_bonus", "tile_spawn_bonus", "bleed_chance", "bleed_damage", "barrier_on_encounter"]

func _apply_build_stat_caps(stats: Dictionary) -> void:
	for key_value in BUILD_STAT_CAPS.keys():
		var key := str(key_value)
		var cap: Dictionary = BUILD_STAT_CAPS[key]
		if not stats.has(key):
			continue
		if key in ["bleed_damage", "barrier_on_encounter", "kill_heal", "tile_scrap", "event_heal"]:
			stats[key] = clampi(int(stats[key]), int(cap["min"]), int(cap["max"]))
		else:
			stats[key] = clampf(float(stats[key]), float(cap["min"]), float(cap["max"]))

func set_summary(equipment: Dictionary) -> Array[String]:
	var counts: Dictionary = {}
	for item_value in equipment.values():
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var set_id := str(item_value.get("set_id", ""))
		if SET_DEFS.has(set_id):
			counts[set_id] = int(counts.get(set_id, 0)) + 1
	var result: Array[String] = []
	for set_id_value in SET_DEFS.keys():
		var set_id := str(set_id_value)
		var definition: Dictionary = SET_DEFS[set_id]
		var count := int(counts.get(set_id, 0))
		var threshold := int(definition.get("threshold", 2))
		var active_prefix := "✓ АКТИВЕН · " if count >= threshold else ""
		result.append("%s%s: %d/%d — %s" % [active_prefix, str(definition.get("name", set_id)), count, threshold, str(definition.get("description", ""))])
	return result
