extends RefCounted
class_name CombatSystem

const StatusEffectSystemScript = preload("res://scripts/systems/status_effect_system.gd")
var status_effect_system = StatusEffectSystemScript.new()

func perform_attack(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if attacker.is_empty() or defender.is_empty() or int(defender.get("hp", 0)) <= 0:
		return {"damage": 0, "raw_damage": 0, "absorbed": 0, "critical": false, "defeated": int(defender.get("hp", 0)) <= 0}
	var attack_penalty := status_effect_system.get_modifier(attacker, "attack_penalty")
	var attack_value := float(attacker.get("attack", 1.0)) * (1.0 - attack_penalty)
	var defense_penalty := status_effect_system.get_modifier(defender, "defense_penalty")
	var defense_value := maxf(0.0, float(defender.get("defense", 0.0)) - defense_penalty)
	var damage := maxf(1.0, attack_value - defense_value * 0.48)
	var critical_chance := clampf(float(attacker.get("crit", 0.05)), 0.0, 0.75)
	var critical := rng.randf() < critical_chance
	if critical:
		damage *= float(ContentRegistry.BALANCE.critical_multiplier)
	# Small variance prevents identical fights without making outcomes unreadable.
	damage *= rng.randf_range(0.9, 1.1)
	var final_damage := maxi(1, int(round(damage)))
	var damage_result: Dictionary = status_effect_system.apply_incoming_damage(defender, final_damage)
	return {"damage": int(damage_result.get("damage", 0)), "raw_damage": final_damage, "absorbed": int(damage_result.get("absorbed", 0)), "total_damage": int(damage_result.get("total_damage", final_damage)), "critical": critical, "defeated": bool(damage_result.get("defeated", int(defender.get("hp", 0)) <= 0))}

func enemy_can_be_defeated(enemy: Dictionary) -> bool:
	return int(enemy.get("hp", 0)) <= 0
