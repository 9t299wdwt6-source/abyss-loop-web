extends RefCounted
class_name StatusEffectSystem

const MAX_ACTIVE_EFFECTS := 8
const MAX_DELTA_SECONDS := 10.0
const MAX_TICKS_PER_UPDATE := 12

func apply_effect(target: Dictionary, effect_id: String, duration_override: float = -1.0, magnitude_override: float = -1.0, source_id: String = "") -> Dictionary:
	if target.is_empty() or not ContentRegistry.STATUS_EFFECTS.has(effect_id):
		return {"ok": false, "reason": "unknown_target_or_effect"}
	var definition: Dictionary = ContentRegistry.STATUS_EFFECTS[effect_id]
	var duration := clampf(duration_override if duration_override > 0.0 else float(definition.get("duration", 1.0)), 0.05, 600.0)
	var configured_magnitude := _configured_magnitude(definition)
	var magnitude := clampf(magnitude_override if magnitude_override >= 0.0 else configured_magnitude, 0.0, float(definition.get("max_magnitude", 1000.0)))
	var effects_value: Variant = target.get("status_effects", [])
	var effects: Array = effects_value.duplicate(true) if typeof(effects_value) == TYPE_ARRAY else []
	var existing_index := -1
	for index in range(effects.size()):
		if typeof(effects[index]) == TYPE_DICTIONARY and str(effects[index].get("id", "")) == effect_id:
			existing_index = index
			break
	var max_stacks := clampi(int(definition.get("max_stacks", 1)), 1, 10)
	var effect: Dictionary
	var disposition := "applied"
	if existing_index >= 0:
		effect = effects[existing_index].duplicate(true)
		disposition = "refreshed"
		var stack_mode := str(definition.get("stack_mode", "refresh"))
		if stack_mode == "stack":
			var old_stacks := maxi(1, int(effect.get("stacks", 1)))
			effect["stacks"] = mini(max_stacks, old_stacks + 1)
			disposition = "stacked" if int(effect["stacks"]) > old_stacks else "refreshed"
			effect["magnitude"] = maxf(float(effect.get("magnitude", magnitude)), magnitude)
		elif stack_mode == "add":
			effect["magnitude"] = minf(float(definition.get("max_magnitude", 1000.0)), float(effect.get("magnitude", 0.0)) + magnitude)
			disposition = "reinforced"
		else:
			effect["magnitude"] = maxf(float(effect.get("magnitude", magnitude)), magnitude)
		effect["duration"] = maxf(float(effect.get("duration", 0.0)), duration)
		effect["source_id"] = source_id if not source_id.is_empty() else str(effect.get("source_id", ""))
		effects[existing_index] = effect
	else:
		if effects.size() >= MAX_ACTIVE_EFFECTS:
			return {"ok": false, "reason": "effect_capacity_reached"}
		effect = {"id": effect_id, "duration": duration, "tick_accumulator": 0.0, "stacks": 1, "magnitude": magnitude, "source_id": source_id}
		effects.append(effect)
	target["status_effects"] = effects
	return {"ok": true, "id": effect_id, "name": str(definition.get("name", effect_id)), "disposition": disposition, "stacks": int(effect.get("stacks", 1)), "duration": float(effect.get("duration", duration)), "magnitude": float(effect.get("magnitude", magnitude))}

func _configured_magnitude(definition: Dictionary) -> float:
	for key in ["tick_damage", "attack_speed_penalty", "attack_penalty", "defense_penalty", "barrier_amount", "tick_heal", "damage_taken_penalty"]:
		if definition.has(key):
			return float(definition.get(key, 0.0))
	return 0.0

func tick_effects(target: Dictionary, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target.is_empty() or delta <= 0.0 or int(target.get("hp", 1)) <= 0:
		return events
	var bounded_delta := minf(delta, MAX_DELTA_SECONDS)
	var effects_value: Variant = target.get("status_effects", [])
	if typeof(effects_value) != TYPE_ARRAY:
		target["status_effects"] = []
		return events
	var effects: Array = effects_value.duplicate(true)
	var kept: Array = []
	for effect_value in effects:
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value.duplicate(true)
		var effect_id := str(effect.get("id", ""))
		if not ContentRegistry.STATUS_EFFECTS.has(effect_id):
			continue
		var definition: Dictionary = ContentRegistry.STATUS_EFFECTS[effect_id]
		var remaining := clampf(float(effect.get("duration", 0.0)), 0.0, 600.0)
		var active_delta := minf(bounded_delta, remaining)
		var kind := str(definition.get("kind", "modifier"))
		if kind in ["damage_over_time", "healing_over_time"] and active_delta > 0.0:
			var interval := maxf(0.1, float(definition.get("tick_interval", 1.0)))
			var accumulator := clampf(float(effect.get("tick_accumulator", 0.0)), 0.0, interval)
			accumulator += active_delta
			var ticks := 0
			while accumulator + 0.00001 >= interval and ticks < MAX_TICKS_PER_UPDATE:
				accumulator -= interval
				ticks += 1
				if kind == "damage_over_time":
					var damage_magnitude := float(effect.get("magnitude", definition.get("tick_damage", 1.0)))
					var damage_stacks := maxi(1, int(effect.get("stacks", 1)))
					var damage := maxi(1, int(round(damage_magnitude * float(damage_stacks))))
					var before_hp := maxi(0, int(target.get("hp", 0)))
					var after_hp := maxi(0, before_hp - damage)
					target["hp"] = after_hp
					events.append({"type": "damage", "id": effect_id, "name": str(definition.get("name", effect_id)), "amount": before_hp - after_hp, "hp": after_hp, "stacks": int(effect.get("stacks", 1))})
					if after_hp <= 0:
						break
				else:
					var before_heal_hp := maxi(0, int(target.get("hp", 0)))
					var max_hp := maxi(before_heal_hp, int(target.get("max_hp", before_heal_hp)))
					var heal_magnitude := float(effect.get("magnitude", definition.get("tick_heal", 1.0)))
					var heal_amount := maxi(1, int(round(heal_magnitude)))
					var after_heal_hp := mini(max_hp, before_heal_hp + heal_amount)
					target["hp"] = after_heal_hp
					if after_heal_hp > before_heal_hp:
						events.append({"type": "healing", "id": effect_id, "name": str(definition.get("name", effect_id)), "amount": after_heal_hp - before_heal_hp, "hp": after_heal_hp, "stacks": int(effect.get("stacks", 1))})
				if int(target.get("hp", 0)) <= 0:
					break
			effect["tick_accumulator"] = clampf(accumulator, 0.0, interval)
		remaining = maxf(0.0, remaining - bounded_delta)
		effect["duration"] = remaining
		if remaining <= 0.00001:
			events.append({"type": "expired", "id": effect_id, "name": str(definition.get("name", effect_id))})
		else:
			kept.append(effect)
		if int(target.get("hp", 0)) <= 0:
			break
	target["status_effects"] = [] if int(target.get("hp", 1)) <= 0 else kept
	return events

func get_modifier(target: Dictionary, modifier_id: String) -> float:
	var total := 0.0
	var effects_value: Variant = target.get("status_effects", [])
	if typeof(effects_value) != TYPE_ARRAY:
		return 0.0
	for effect_value in effects_value:
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value
		var definition: Dictionary = ContentRegistry.STATUS_EFFECTS.get(str(effect.get("id", "")), {})
		if definition.is_empty() or float(effect.get("duration", 0.0)) <= 0.0 or not definition.has(modifier_id):
			continue
		var stacks_multiplier := float(effect.get("stacks", 1)) if str(definition.get("stack_mode", "")) == "stack" and modifier_id in ["attack_speed_penalty", "attack_penalty", "defense_penalty", "damage_taken_penalty"] else 1.0
		total += float(effect.get("magnitude", definition.get(modifier_id, 0.0))) * stacks_multiplier
	if modifier_id in ["attack_speed_penalty", "attack_penalty", "defense_penalty", "damage_taken_penalty"]:
		return clampf(total, 0.0, 0.65)
	return clampf(total, 0.0, 1000.0)

func apply_incoming_damage(target: Dictionary, raw_damage: int) -> Dictionary:
	var damage_before_barrier := maxi(0, raw_damage)
	if damage_before_barrier <= 0 or target.is_empty():
		return {"damage": 0, "absorbed": 0, "defeated": int(target.get("hp", 0)) <= 0}
	var vulnerability := get_modifier(target, "damage_taken_penalty")
	damage_before_barrier = maxi(1, int(ceil(float(damage_before_barrier) * (1.0 + vulnerability))))
	var effects_value: Variant = target.get("status_effects", [])
	var effects: Array = effects_value.duplicate(true) if typeof(effects_value) == TYPE_ARRAY else []
	var absorbed := 0
	for index in range(effects.size()):
		if typeof(effects[index]) != TYPE_DICTIONARY or str(effects[index].get("id", "")) != "barrier":
			continue
		var barrier: Dictionary = effects[index].duplicate(true)
		var shield := maxf(0.0, float(barrier.get("magnitude", 0.0)))
		absorbed = mini(damage_before_barrier, int(floor(shield)))
		shield -= float(absorbed)
		if shield <= 0.001:
			effects.remove_at(index)
		else:
			barrier["magnitude"] = shield
			effects[index] = barrier
		target["status_effects"] = effects
		break
	var hp_damage := maxi(0, damage_before_barrier - absorbed)
	target["hp"] = maxi(0, int(target.get("hp", 0)) - hp_damage)
	return {"damage": hp_damage, "absorbed": absorbed, "total_damage": damage_before_barrier, "defeated": int(target.get("hp", 0)) <= 0}

func normalize_legacy_entity(entity: Dictionary) -> Dictionary:
	if entity.is_empty():
		return entity
	var effects_value: Variant = entity.get("status_effects", [])
	var effects: Array = effects_value.duplicate(true) if typeof(effects_value) == TYPE_ARRAY else []
	var has_distortion := false
	for effect_value in effects:
		if typeof(effect_value) == TYPE_DICTIONARY and str(effect_value.get("id", "")) == "distortion":
			has_distortion = true
			break
	var legacy_value: Variant = entity.get("combat_debuff", {})
	if not has_distortion and typeof(legacy_value) == TYPE_DICTIONARY:
		var legacy: Dictionary = legacy_value
		var duration := clampf(float(legacy.get("time_remaining", 0.0)), 0.0, 600.0)
		var penalty := clampf(float(legacy.get("speed_penalty", 0.0)), 0.0, 0.65)
		if duration > 0.0 and penalty > 0.0:
			effects.append({"id": "distortion", "duration": duration, "tick_accumulator": 0.0, "stacks": 1, "magnitude": penalty, "source_id": "legacy_caster"})
	entity["status_effects"] = effects.slice(maxi(0, effects.size() - MAX_ACTIVE_EFFECTS), effects.size())
	entity["combat_debuff"] = {"speed_penalty": 0.0, "time_remaining": 0.0}
	return entity

func describe_active(target: Dictionary) -> Array[Dictionary]:
	var descriptions: Array[Dictionary] = []
	var effects_value: Variant = target.get("status_effects", [])
	if typeof(effects_value) != TYPE_ARRAY:
		return descriptions
	for effect_value in effects_value:
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value
		var definition: Dictionary = ContentRegistry.STATUS_EFFECTS.get(str(effect.get("id", "")), {})
		if definition.is_empty() or float(effect.get("duration", 0.0)) <= 0.0:
			continue
		descriptions.append({"id": str(effect.get("id", "")), "name": str(definition.get("name", "")), "duration": float(effect.get("duration", 0.0)), "stacks": int(effect.get("stacks", 1)), "magnitude": float(effect.get("magnitude", 0.0))})
	return descriptions
