extends RefCounted
class_name LootSystem

const EQUIPMENT_SOURCE_RARITY_BONUS := {"enemy": 0.0, "elite": 0.04, "cache": 0.02}

const BIOME_TROPHIES := {
	"spore": {"id": "spore_pollen", "name": "Пыльца спороносца", "tile_id": "spore_garden", "base_chance": 0.58},
	"crystal": {"id": "prism_fragment", "name": "Осколок призмы", "tile_id": "crystal_hive", "base_chance": 0.56},
	"bone": {"id": "bone_fragment", "name": "Фрагмент дозорного", "tile_id": "bone_orchard", "base_chance": 0.60},
	"echo": {"id": "echo_residue", "name": "Остаток эха", "tile_id": "echo_obelisk", "base_chance": 0.52}
}


func get_equipment_drop_chance(source_kind: String, combat_reward_bonus: float = 0.0, echo_charges: int = 0, pending_drop_bonus: float = 0.0) -> float:
	# This is the single probability function used by combat rewards, elites,
	# bosses, and landscape caches. Rarity is rolled only after this succeeds.
	var source := source_kind.strip_edges().to_lower()
	if source == "boss":
		return 1.0 # Boss-specific named equipment is an authored guaranteed reward.
	var is_cache := source == "cache"
	var chance: float
	if is_cache:
		chance = float(ContentRegistry.BALANCE.get("cache_item_drop_chance", 0.35))
	else:
		chance = float(ContentRegistry.BALANCE.get("loot_item_chance", 0.18))
		chance += minf(float(ContentRegistry.BALANCE.get("loot_item_bonus_cap", 0.15)), combat_reward_bonus * float(ContentRegistry.BALANCE.get("loot_item_bonus_multiplier", 0.15)))
		if source == "elite":
			chance = maxf(chance, float(ContentRegistry.BALANCE.get("elite_item_chance", 0.45)))
	var capped_echo_charges := clampi(echo_charges, 0, 4)
	chance = minf(0.85, chance + float(capped_echo_charges) * 0.05)
	if is_cache:
		chance += clampf(pending_drop_bonus, 0.0, 0.30)
		return clampf(chance, 0.0, 0.85)
	chance += clampf(pending_drop_bonus, 0.0, 0.30)
	return clampf(chance, 0.0, 0.95)

func get_source_rarity_bonus(source_kind: String) -> float:
	var source := source_kind.strip_edges().to_lower()
	return clampf(float(EQUIPMENT_SOURCE_RARITY_BONUS.get(source, 0.0)), 0.0, 0.06)

func format_rarity_distribution(distribution: Dictionary) -> String:
	var labels := PackedStringArray()
	for rarity_name in ["Обычный", "Редкий", "Эпический", "Реликтовый"]:
		labels.append("%s %.1f%%" % [rarity_name.to_lower(), clampf(float(distribution.get(rarity_name, 0.0)), 0.0, 1.0) * 100.0])
	return " · ".join(labels)

func roll_victory(enemy: Dictionary, loop_count: int, rng: RandomNumberGenerator, reward_bonus: float) -> Dictionary:
	var scale := 1.0 + maxf(0.0, reward_bonus)
	var scrap := int(round((int(enemy.get("scrap", 0)) + rng.randi_range(0, 2)) * scale))
	var crystals := int(enemy.get("crystal", 0))
	if rng.randf() < float(ContentRegistry.BALANCE.loot_crystal_chance) + minf(float(ContentRegistry.BALANCE.get("loot_crystal_loop_cap", 0.18)), float(loop_count) * float(ContentRegistry.BALANCE.get("loot_crystal_loop_step", 0.025))):
		crystals += 1
	return {"scrap": maxi(0, scrap), "crystals": maxi(0, crystals), "xp": int(enemy.get("xp", 0))}


func get_biome_trophy_chance(enemy: Dictionary, active_tile_ids: Array = [], trophy_find_bonus: float = 0.0, biome_specific_bonus: float = 0.0) -> float:
	var biome_tag := str(enemy.get("biome_tag", ""))
	if not BIOME_TROPHIES.has(biome_tag):
		return 0.0
	var definition: Dictionary = BIOME_TROPHIES[biome_tag]
	var chance := float(definition.get("base_chance", 0.5))
	var is_boss := bool(enemy.get("is_boss", false))
	var is_elite := bool(enemy.get("is_elite", false))
	if is_boss:
		# Boss signature rewards are guaranteed and are not increased by item find stats.
		chance = 1.0
		return chance
	if is_elite:
		chance = maxf(chance, 0.86)
	chance = minf(0.96, chance + clampf(trophy_find_bonus, 0.0, 0.25) + clampf(biome_specific_bonus, 0.0, 0.12))
	if active_tile_ids.has(str(definition.get("tile_id", ""))):
		chance = minf(0.96, chance + 0.22)
	return clampf(chance, 0.0, 0.96)

func roll_biome_trophy(enemy: Dictionary, rng: RandomNumberGenerator, active_tile_ids: Array = [], trophy_find_bonus: float = 0.0, biome_specific_bonus: float = 0.0) -> Dictionary:
	var biome_tag := str(enemy.get("biome_tag", ""))
	if not BIOME_TROPHIES.has(biome_tag):
		return {}
	var definition: Dictionary = BIOME_TROPHIES[biome_tag]
	var is_boss := bool(enemy.get("is_boss", false))
	var is_elite := bool(enemy.get("is_elite", false)) and not is_boss
	var chance := get_biome_trophy_chance(enemy, active_tile_ids, trophy_find_bonus, biome_specific_bonus)
	var focused := active_tile_ids.has(str(definition.get("tile_id", "")))
	if rng.randf() >= chance:
		return {}
	var amount := 3 if is_boss else (2 if is_elite else 1)
	return {
		"material_id": str(definition.get("id", "")),
		"name": str(definition.get("name", "Трофей")),
		"biome_tag": biome_tag,
		"amount": amount,
		"focused_by_landscape": focused,
		"drop_chance": chance
	}
