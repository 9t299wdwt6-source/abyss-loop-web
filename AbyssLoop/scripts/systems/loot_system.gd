extends RefCounted
class_name LootSystem

func roll_victory(enemy: Dictionary, loop_count: int, rng: RandomNumberGenerator, reward_bonus: float) -> Dictionary:
	var scale := 1.0 + maxf(0.0, reward_bonus)
	var scrap := int(round((int(enemy.get("scrap", 0)) + rng.randi_range(0, 2)) * scale))
	var crystals := int(enemy.get("crystal", 0))
	if rng.randf() < float(ContentRegistry.BALANCE.loot_crystal_chance) + minf(float(ContentRegistry.BALANCE.get("loot_crystal_loop_cap", 0.18)), float(loop_count) * float(ContentRegistry.BALANCE.get("loot_crystal_loop_step", 0.025))):
		crystals += 1
	return {"scrap": maxi(0, scrap), "crystals": maxi(0, crystals), "xp": int(enemy.get("xp", 0))}
