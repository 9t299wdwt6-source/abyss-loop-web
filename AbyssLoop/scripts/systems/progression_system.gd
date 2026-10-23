extends RefCounted
class_name ProgressionSystem

func add_experience(hero: Dictionary, amount: int) -> int:
	hero["xp"] = int(hero.get("xp", 0)) + maxi(0, amount)
	var levels_gained := 0
	while int(hero.xp) >= int(hero.get("xp_next", 16)):
		hero.xp = int(hero.xp) - int(hero.xp_next)
		hero.level = int(hero.get("level", 1)) + 1
		hero.xp_next = int(ceil(float(hero.xp_next) * 1.28 + 3.0))
		levels_gained += 1
	return levels_gained

func make_perk_choices(rng: RandomNumberGenerator, hero: Dictionary = {}) -> Array:
	var available: Array[String] = []
	var perk_counts_value: Variant = hero.get("perk_counts", {})
	var perk_counts: Dictionary = perk_counts_value if typeof(perk_counts_value) == TYPE_DICTIONARY else {}
	for perk_id_value in ContentRegistry.PERKS.keys():
		var perk_id := str(perk_id_value)
		var definition: Dictionary = ContentRegistry.PERKS[perk_id]
		var stack_limit := maxi(1, int(definition.get("max_stacks", 1)))
		if int(perk_counts.get(perk_id, 0)) < stack_limit:
			available.append(perk_id)
	var result: Array = []
	var choice_count := mini(3, available.size())
	while result.size() < choice_count:
		var index := rng.randi_range(0, available.size() - 1)
		result.append(available[index])
		available.remove_at(index)
	return result

func apply_perk(hero: Dictionary, perk_id: String) -> bool:
	if not ContentRegistry.PERKS.has(perk_id):
		return false
	var perk: Dictionary = ContentRegistry.PERKS[perk_id]
	var perk_counts_value: Variant = hero.get("perk_counts", {})
	var perk_counts: Dictionary = perk_counts_value.duplicate(true) if typeof(perk_counts_value) == TYPE_DICTIONARY else {}
	if int(perk_counts.get(perk_id, 0)) >= maxi(1, int(perk.get("max_stacks", 1))):
		return false
	perk_counts[perk_id] = int(perk_counts.get(perk_id, 0)) + 1
	hero["perk_counts"] = perk_counts
	hero["attack_bonus"] = int(hero.get("attack_bonus", 0)) + int(perk.get("attack", 0))
	hero["hp_bonus"] = int(hero.get("hp_bonus", 0)) + int(perk.get("hp", 0))
	hero["defense_bonus"] = int(hero.get("defense_bonus", 0)) + int(perk.get("defense", 0))
	hero["speed_bonus"] = float(hero.get("speed_bonus", 0.0)) + float(perk.get("speed", 0.0))
	hero["crit_bonus"] = float(hero.get("crit_bonus", 0.0)) + float(perk.get("crit", 0.0))
	hero["perk_kill_heal_bonus"] = int(hero.get("perk_kill_heal_bonus", 0)) + int(perk.get("kill_heal", 0))
	hero["perk_tile_scrap_bonus"] = int(hero.get("perk_tile_scrap_bonus", 0)) + int(perk.get("tile_scrap", 0))
	hero["perk_event_heal_bonus"] = int(hero.get("perk_event_heal_bonus", 0)) + int(perk.get("event_heal", 0))
	hero["perk_reward_bonus"] = float(hero.get("perk_reward_bonus", 0.0)) + float(perk.get("reward_bonus", 0.0))
	hero["perk_tile_spawn_bonus"] = float(hero.get("perk_tile_spawn_bonus", 0.0)) + float(perk.get("tile_spawn_bonus", 0.0))
	return true

