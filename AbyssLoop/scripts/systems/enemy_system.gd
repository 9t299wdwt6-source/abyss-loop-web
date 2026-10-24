extends RefCounted
class_name EnemySystem

func create_enemy(loop_count: int, danger: float, rng: RandomNumberGenerator, strength_bonus: float = 0.0) -> Dictionary:
	var ids: Array = ContentRegistry.ENEMIES.keys()
	if ids.is_empty():
		push_error("ContentRegistry.ENEMIES is empty; cannot create encounter")
		return {}
	var enemy_id: String = str(ids[rng.randi_range(0, ids.size() - 1)])
	var def: Dictionary = ContentRegistry.ENEMIES[enemy_id]
	var scaling := 1.0 + maxf(0.0, float(loop_count)) * float(ContentRegistry.BALANCE.get("enemy_loop_scaling", 0.18)) + maxf(0.0, danger - 1.0) * float(ContentRegistry.BALANCE.get("enemy_danger_scaling", 0.32)) + strength_bonus
	var enemy_hp := maxi(1, int(round(float(def.hp) * scaling)))
	return {
		"id": enemy_id,
		"uid": "%s_%d" % [enemy_id, rng.randi()],
		"name": def.name,
		"role": def.role,
		"behavior_hint": str(def.get("behavior_hint", "Обычная атака")),
		"ability_text": str(def.get("ability_text", "обычная атака")),
		"is_boss": false,
		"hp": enemy_hp,
		"max_hp": enemy_hp,
		"attack": maxf(1.0, float(def.attack) * (1.0 + maxf(0.0, scaling - 1.0) * float(ContentRegistry.BALANCE.get("enemy_attack_scaling", 0.7)))),
		"defense": int(def.defense) + (1 if loop_count >= int(def.get("defense_bonus_after_loop", 999999)) else 0),
		"attack_interval": float(def.attack_interval),
		"attack_timer": 0.0,
		"attack_count": 0,
		"xp": int(def.xp) + loop_count,
		"scrap": int(def.scrap) + int(floor(float(loop_count) * 0.6)),
		"crystal": int(def.crystal),
		"danger_rating": scaling,
		"status_effects": []
	}

func create_boss(loop_count: int, danger: float, rng: RandomNumberGenerator) -> Dictionary:
	var cycle_index := maxi(1, int(floor(float(loop_count) / float(ContentRegistry.BALANCE.boss_loop_interval))))
	var boss_ids: Array = ContentRegistry.BOSSES.keys()
	if boss_ids.is_empty():
		push_error("ContentRegistry.BOSSES is empty; cannot create boss encounter")
		return {}
	var boss_id: String = str(boss_ids[posmod(cycle_index - 1, boss_ids.size())])
	var def: Dictionary = ContentRegistry.BOSSES[boss_id]
	var cycles_after_first := maxi(0, cycle_index - 1)
	var scaling := 1.0 + float(cycles_after_first) * float(ContentRegistry.BALANCE.get("boss_cycle_scaling", 0.28)) + maxf(0.0, danger - 1.0) * float(ContentRegistry.BALANCE.get("boss_danger_scaling", 0.22))
	var boss_hp := maxi(1, int(round(float(def.hp) * scaling)))
	var phase_data_value: Variant = def.get("phases", [])
	var phase_data: Array = phase_data_value.duplicate(true) if typeof(phase_data_value) == TYPE_ARRAY else []
	var initial_phase: Dictionary = phase_data[0] if not phase_data.is_empty() else {"name": "Фаза 1", "attack_multiplier": 1.0, "defense_bonus": 0, "attack_interval": float(def.attack_interval), "special_every": 3, "telegraph": "Босс готовит особую атаку."}
	var scaled_base_attack := maxf(1.0, float(def.attack) * (1.0 + maxf(0.0, scaling - 1.0) * float(ContentRegistry.BALANCE.get("boss_attack_scaling", 0.5))))
	return {
		"id": boss_id,
		"uid": "%s_%d" % [boss_id, rng.randi()],
		"name": def.name,
		"role": "boss",
		"behavior_hint": "Босс меняет тактику на порогах здоровья",
		"is_boss": true,
		"hp": boss_hp,
		"max_hp": boss_hp,
		"attack": scaled_base_attack * float(initial_phase.get("attack_multiplier", 1.0)),
		"base_attack": scaled_base_attack,
		"base_defense": int(def.defense) + cycles_after_first,
		"defense": int(def.defense) + cycles_after_first + int(initial_phase.get("defense_bonus", 0)),
		"attack_interval": float(initial_phase.get("attack_interval", def.attack_interval)),
		"attack_timer": 0.0,
		"attack_count": 0,
		"phase_index": 0,
		"phase_name": str(initial_phase.get("name", "Фаза 1")),
		"phase_telegraph": str(initial_phase.get("telegraph", "Босс готовит особую атаку.")),
		"phases": phase_data,
		"telegraph_pending": false,
		"special_every": int(initial_phase.get("special_every", 3)),
		"special_name": str(def.special_name),
		"special_effect_id": str(def.get("special_effect_id", "wound")),
		"special_effect_duration": float(def.get("special_effect_duration", 4.0)),
		"special_effect_magnitude": float(def.get("special_effect_magnitude", 0.12)),
		"special_effect_log": str(def.get("special_effect_log", "Особая атака оставляет рану: следующие удары по герою усилены на 12%.")),
		"xp": int(def.xp) + loop_count * 2,
		"scrap": int(def.scrap) + loop_count * 2,
		"crystal": int(def.crystal) + cycles_after_first,
		"danger_rating": scaling,
		"status_effects": []
	}


func promote_encounter_to_elite(encounter: Array, loop_count: int) -> Dictionary:
	if encounter.is_empty() or typeof(encounter[0]) != TYPE_DICTIONARY:
		return {}
	var elite: Dictionary = encounter[0].duplicate(true)
	if bool(elite.get("is_boss", false)):
		return {}
	var role := str(elite.get("role", "fast"))
	var ability_value: Variant = ContentRegistry.ELITE_ROLE_ABILITIES.get(role, ContentRegistry.ELITE_ROLE_ABILITIES.get("fast", {}))
	var ability: Dictionary = ability_value.duplicate(true) if typeof(ability_value) == TYPE_DICTIONARY else {}
	var hp_multiplier := maxf(1.0, float(ContentRegistry.BALANCE.get("elite_hp_multiplier", 1.4)))
	var attack_multiplier := maxf(1.0, float(ContentRegistry.BALANCE.get("elite_attack_multiplier", 1.22)))
	var elite_hp := maxi(1, int(ceil(float(elite.get("max_hp", elite.get("hp", 1))) * hp_multiplier)))
	elite["hp"] = maxi(1, int(ceil(float(elite.get("hp", elite_hp)) * hp_multiplier)))
	elite["max_hp"] = elite_hp
	elite["attack"] = maxf(1.0, float(elite.get("attack", 1.0)) * attack_multiplier)
	elite["defense"] = maxi(0, int(elite.get("defense", 0)) + int(ContentRegistry.BALANCE.get("elite_defense_bonus", 1)))
	elite["xp"] = maxi(1, int(elite.get("xp", 1)) * 2)
	elite["scrap"] = maxi(1, int(elite.get("scrap", 1)) * 2)
	elite["crystal"] = maxi(0, int(elite.get("crystal", 0)) + 1)
	elite["is_elite"] = true
	elite["elite_ability"] = str(ability.get("name", "Элитная способность"))
	elite["elite_ability_id"] = str(ability.get("effect_id", ""))
	elite["elite_effect_duration"] = float(ability.get("duration", 3.0))
	elite["elite_effect_magnitude"] = float(ability.get("magnitude", 0.0))
	elite["elite_telegraph"] = str(ability.get("telegraph", "Противник готовит усиленную атаку."))
	elite["special_name"] = str(ability.get("name", "Усиленный удар"))
	elite["special_every"] = maxi(2, int(ContentRegistry.BALANCE.get("elite_special_every", 3)))
	elite["phase_telegraph"] = str(ability.get("telegraph", "Противник готовит усиленную атаку."))
	elite["telegraph_pending"] = false
	elite["attack_count"] = 0
	elite["danger_rating"] = float(elite.get("danger_rating", 1.0)) * attack_multiplier
	encounter[0] = elite
	return elite.duplicate(true)

# Returns a whole encounter. All members attack independently; the hero focuses
# the first living member. High-threat expeditions guarantee at least a pair.
func create_encounter(loop_count: int, danger: float, rng: RandomNumberGenerator, strength_bonus: float = 0.0, boss_encounter: bool = false, extra_group_members: int = 0) -> Array:
	if boss_encounter:
		return [create_boss(loop_count, danger + strength_bonus, rng)]
	var members: Array = []
	members.append(create_enemy(loop_count, danger, rng, strength_bonus))
	var pack_size := 1
	if loop_count >= 4:
		pack_size = 2
	elif loop_count >= 1:
		var extra_chance := clampf(0.10 + float(loop_count) * 0.075 + maxf(0.0, danger - 1.0) * 0.10, 0.10, 0.48)
		if rng.randf() < extra_chance:
			pack_size = 2
	if loop_count >= 5 and pack_size >= 2 and rng.randf() < float(ContentRegistry.BALANCE.get("three_enemy_pack_chance", 0.18)):
		pack_size = 3
	pack_size = mini(pack_size + maxi(0, extra_group_members), int(ContentRegistry.BALANCE.max_encounter_enemies))
	for index in range(1, pack_size):
		var support := create_enemy(loop_count, danger, rng, strength_bonus)
		# Stagger opening attacks so a fresh pack does not burst the hero instantly.
		support["attack_timer"] = -float(support.get("attack_interval", 1.0)) * 0.42 * float(index)
		members.append(support)
	# Put healers at the end so the player can see and respond to their support role
	# before they become the focused target; it does not alter the generated group.
	var front_line: Array = []
	var support_line: Array = []
	for member_value in members:
		var member: Dictionary = member_value
		if str(member.get("role", "")) == "support":
			support_line.append(member)
		else:
			front_line.append(member)
	return front_line + support_line
