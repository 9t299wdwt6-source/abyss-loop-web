extends RefCounted
class_name BaseSystem

func get_upgrade_cost(building_id: String) -> Dictionary:
	if not ContentRegistry.BUILDINGS.has(building_id):
		return {}
	var def: Dictionary = ContentRegistry.BUILDINGS[building_id]
	var level := int(GameState.buildings.get(building_id, 0))
	return {
		"scrap": int(def.base_scrap) + level * int(def.scrap_step),
		"crystals": int(def.base_crystal) + level * int(def.crystal_step),
		"echo_dust": int(def.get("echo_dust_base", 0)) + level * int(def.get("echo_dust_step", 0)),
		"level": level,
		"max_level": int(def.max_level)
	}

func try_upgrade(building_id: String) -> Dictionary:
	if GameState.has_saved_expedition():
		return {"ok": false, "message": "Сначала продолжите или отмените сохранённую экспедицию. База изменяется между забегами."}
	if not ContentRegistry.BUILDINGS.has(building_id):
		return {"ok": false, "message": "Неизвестное сооружение."}
	var def: Dictionary = ContentRegistry.BUILDINGS[building_id]
	var cost := get_upgrade_cost(building_id)
	if int(cost.level) >= int(cost.max_level):
		return {"ok": false, "message": "Достигнут максимальный уровень."}
	var dust_cost := int(cost.get("echo_dust", 0))
	if GameState.scrap < int(cost.scrap) or GameState.crystals < int(cost.crystals) or GameState.echo_dust < dust_cost:
		var missing_text := "Недостаточно ресурсов: нужно %d материалов и %d редких ресурсов." % [int(cost.scrap), int(cost.crystals)]
		if dust_cost > 0:
			missing_text = "Недостаточно ресурсов: нужно %d материалов, %d редких ресурсов и %d пыли утраченных вещей." % [int(cost.scrap), int(cost.crystals), dust_cost]
		return {"ok": false, "message": missing_text}
	var old_scrap: int = GameState.scrap
	var old_crystals: int = GameState.crystals
	var old_echo_dust: int = GameState.echo_dust
	var old_building_level: int = int(GameState.buildings.get(building_id, 0))
	GameState.scrap -= int(cost.scrap)
	GameState.crystals -= int(cost.crystals)
	GameState.echo_dust -= dust_cost
	GameState.buildings[building_id] = int(cost.level) + 1
	if not GameState.save_now():
		GameState.scrap = old_scrap
		GameState.crystals = old_crystals
		GameState.echo_dust = old_echo_dust
		GameState.buildings[building_id] = old_building_level
		return {"ok": false, "message": "Не удалось сохранить улучшение. Уровень и все ресурсы восстановлены."}
	GameState.changed.emit()
	var message := "%s улучшено до уровня %d." % [def.name, int(GameState.buildings[building_id])]
	if dust_cost > 0:
		message += " Потрачено %d пыли утраченных вещей." % dust_cost
	return {"ok": true, "message": message, "building_id": building_id, "echo_dust_spent": dust_cost}

func get_research_status(research_id: String) -> Dictionary:
	if not ContentRegistry.BASE_RESEARCH.has(research_id):
		return {"known": false, "unlocked": false, "available": false, "missing": []}
	var definition: Dictionary = ContentRegistry.BASE_RESEARCH[research_id]
	var unlocked: bool = GameState.has_research(research_id)
	var missing: Array[String] = []
	var prerequisites_value: Variant = definition.get("prerequisites", [])
	if typeof(prerequisites_value) == TYPE_ARRAY:
		for prerequisite_value in prerequisites_value:
			var prerequisite := str(prerequisite_value)
			if not GameState.has_research(prerequisite):
				var prerequisite_name := str(ContentRegistry.BASE_RESEARCH.get(prerequisite, {}).get("name", prerequisite))
				missing.append(prerequisite_name)
	var can_afford: bool = GameState.scrap >= int(definition.get("scrap_cost", 0)) and GameState.crystals >= int(definition.get("crystal_cost", 0))
	return {
		"known": true,
		"unlocked": unlocked,
		"available": not unlocked and missing.is_empty() and can_afford,
		"prerequisites_met": missing.is_empty(),
		"can_afford": can_afford,
		"missing": missing,
		"scrap_cost": int(definition.get("scrap_cost", 0)),
		"crystal_cost": int(definition.get("crystal_cost", 0))
	}

func get_research_branch_status(branch_id: String) -> Dictionary:
	if not ContentRegistry.RESEARCH_BRANCHES.has(branch_id):
		return {"known": false, "branch_id": branch_id, "message": "Неизвестная ветка развития."}
	var branch: Dictionary = ContentRegistry.RESEARCH_BRANCHES[branch_id]
	var nodes_value: Variant = branch.get("nodes", [])
	var nodes: Array = nodes_value if typeof(nodes_value) == TYPE_ARRAY else []
	var unlocked_count := 0
	var next_nodes: Array[Dictionary] = []
	var blocked_nodes: Array[Dictionary] = []
	for node_value in nodes:
		var research_id := str(node_value)
		var definition: Dictionary = ContentRegistry.BASE_RESEARCH.get(research_id, {})
		var status := get_research_status(research_id)
		if bool(status.get("unlocked", false)):
			unlocked_count += 1
			continue
		var node_summary := {
			"id": research_id,
			"name": str(definition.get("name", research_id)),
			"effect_text": str(definition.get("effect_text", "—")),
			"scrap_cost": int(definition.get("scrap_cost", 0)),
			"crystal_cost": int(definition.get("crystal_cost", 0)),
			"missing": status.get("missing", []).duplicate(),
			"available": bool(status.get("available", false)),
			"prerequisites_met": bool(status.get("prerequisites_met", false))
		}
		if bool(status.get("prerequisites_met", false)):
			next_nodes.append(node_summary)
		else:
			blocked_nodes.append(node_summary)
	var entry_id := str(branch.get("entry_node", ""))
	var entry_status := get_research_status(entry_id)
	var next_preview: Dictionary = next_nodes[0] if not next_nodes.is_empty() else {}
	return {
		"known": true,
		"branch_id": branch_id,
		"name": str(branch.get("name", branch_id)),
		"summary": str(branch.get("summary", "")),
		"style": str(branch.get("style", "")),
		"total_nodes": nodes.size(),
		"unlocked_nodes": unlocked_count,
		"complete": unlocked_count >= nodes.size(),
		"entry_node": entry_id,
		"entry_available": bool(entry_status.get("available", false)),
		"next_nodes": next_nodes,
		"blocked_nodes": blocked_nodes,
		"next_preview": next_preview,
		"blocked_count": blocked_nodes.size()
	}

func try_research(research_id: String) -> Dictionary:
	if GameState.has_saved_expedition():
		return {"ok": false, "message": "Сначала продолжите или отмените сохранённую экспедицию. Исследования доступны между забегами."}
	if not ContentRegistry.BASE_RESEARCH.has(research_id):
		return {"ok": false, "message": "Неизвестное исследование."}
	var definition: Dictionary = ContentRegistry.BASE_RESEARCH[research_id]
	var status := get_research_status(research_id)
	if bool(status.get("unlocked", false)):
		return {"ok": false, "message": "Это исследование уже завершено."}
	if not bool(status.get("prerequisites_met", false)):
		return {"ok": false, "message": "Сначала завершите исследования: %s." % ", ".join(status.get("missing", []))}
	var scrap_cost := int(definition.get("scrap_cost", 0))
	var crystal_cost := int(definition.get("crystal_cost", 0))
	if GameState.scrap < scrap_cost or GameState.crystals < crystal_cost:
		return {"ok": false, "message": "Недостаточно ресурсов для исследования."}
	var old_scrap: int = int(GameState.scrap)
	var old_crystals: int = int(GameState.crystals)
	var old_unlocked_nodes: Array = GameState.unlocked_nodes.duplicate(true)
	var old_investments: Dictionary = GameState.research_investments.duplicate(true)
	GameState.scrap -= scrap_cost
	GameState.crystals -= crystal_cost
	GameState.unlocked_nodes.append(research_id)
	GameState.research_investments[research_id] = {"scrap": scrap_cost, "crystals": crystal_cost}
	if not GameState.save_now():
		GameState.scrap = old_scrap
		GameState.crystals = old_crystals
		GameState.unlocked_nodes = old_unlocked_nodes
		GameState.research_investments = old_investments
		return {"ok": false, "message": "Не удалось сохранить исследование. Ресурсы и прогресс восстановлены без изменений."}
	GameState.changed.emit()
	return {"ok": true, "message": "Исследование завершено: %s." % str(definition.get("name", research_id)), "research_id": research_id}

func get_research_reset_preview() -> Dictionary:
	return GameState.get_research_reset_preview()

func try_reset_research_tree() -> Dictionary:
	return GameState.reset_research_tree()
