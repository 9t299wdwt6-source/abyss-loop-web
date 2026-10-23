extends RefCounted

## Builds the debug-only diagnostic text without owning UI controls or mutating game state.
## This component is read-only: it gathers profile, expedition, and content-registry details.

func build_report(manager: Variant, screen_mode: String) -> String:
	var lines: Array[String] = []
	lines.append("ABYSS LOOP — ДИАГНОСТИКА РАЗРАБОТЧИКА")
	lines.append("Версия: %s · Godot: %s · Debug: %s" % [str(ProjectSettings.get_setting("application/config/version", "unknown")), Engine.get_version_info().get("string", "unknown"), str(OS.is_debug_build())])
	lines.append("Время отчёта: %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("")
	lines.append("ПРОФИЛЬ И СОХРАНЕНИЕ")
	lines.append("Экран: %s · Экспедиция активна: %s · Сохранённый забег: %s" % [screen_mode, str(manager != null and manager.active), str(GameState.has_saved_expedition())])
	lines.append("Материалы: %d · Редкие ресурсы: %d · Завершено экспедиций: %d" % [GameState.scrap, GameState.crystals, GameState.runs_completed])
	lines.append("История: %d/%d · Исследований: %d · Постройки: %s" % [GameState.expedition_history.size(), GameState.MAX_EXPEDITION_HISTORY, GameState.unlocked_nodes.size(), str(GameState.buildings)])
	var snapshot: Dictionary = GameState.saved_expedition if typeof(GameState.saved_expedition) == TYPE_DICTIONARY else {}
	var snapshot_text := JSON.stringify(snapshot)
	lines.append("Snapshot: версия %s · размер JSON %d байт · активен=%s" % [str(snapshot.get("snapshot_version", "—")), snapshot_text.to_utf8_buffer().size(), str(bool(snapshot.get("active", false)))])
	lines.append("")
	lines.append("ЭКСПЕДИЦИЯ")
	if manager != null and manager.active:
		var route_count: int = int(manager.route.size())
		var closed_loop_ok: bool = bool(manager.route_system.is_closed_loop(manager.route))
		lines.append("Seed: %d · Сложность: %s · Режим: %s · Модификатор: %s" % [manager.run_seed, manager.difficulty_id, manager.expedition_mode_id, manager.run_modifier_id])
		lines.append("Маршрут: %d узлов · замкнут: %s · текущий узел: %d · цикл: %d · дистанция: %.2f" % [route_count, str(closed_loop_ok), manager.current_cell() + 1, manager.loop_count, manager.distance])
		lines.append("Пауза: %s · скорость: %.1fx · опасность: %.2f · бой: %s" % [str(manager.paused), manager.speed, manager.danger, str(not manager.enemy.is_empty())])
		lines.append("Цель: %s · прогресс: %s · выполнена: %s" % [str(manager.run_objective.get("name", "—")), str(manager.run_objective.get("progress", 0)), str(manager.run_objective.get("completed", false))])
		lines.append("Контракт: %s · прогресс: %s · выполнен: %s" % [str(manager.run_contract.get("name", "—")), str(manager.run_contract.get("progress", 0)), str(manager.run_contract.get("completed", false))])
		lines.append("Добыча: %s · вырубленные противники: %s · победы над боссами: %s · элиты: %s" % [str(manager.run_ledger.get("scrap", 0)), str(manager.run_ledger.get("victories", 0)), str(manager.run_ledger.get("bosses_defeated", 0)), str(manager.run_ledger.get("elites_defeated", 0))])
		lines.append("Тайлы: рука=%d · поле=%d · размещено унаследованных=%d · событие ожидает=%s · выбор перка=%d" % [manager.tile_hand.size(), manager.world_tiles.size(), manager.placed_tiles.size(), str(not manager.pending_event.is_empty()), manager.pending_perk_count])
		lines.append("Герой: HP %s/%s · ATK %s · DEF %s · уровень %s · XP %s" % [str(manager.hero.get("hp", "?")), str(manager.hero.get("max_hp", "?")), str(manager.hero.get("attack", "?")), str(manager.hero.get("defense", "?")), str(manager.hero.get("level", "?")), str(manager.hero.get("xp", "?"))])
		lines.append("Эффекты героя: %s" % format_debug_effects(manager.hero.get("status_effects", [])))
		var encounter_lines: Array[String] = []
		for enemy_value in manager.encounter_enemies:
			if typeof(enemy_value) != TYPE_DICTIONARY:
				continue
			var enemy_data: Dictionary = enemy_value
			encounter_lines.append("%s HP %s/%s эффекты=%s" % [str(enemy_data.get("name", enemy_data.get("id", "противник"))), str(enemy_data.get("hp", "?")), str(enemy_data.get("max_hp", "?")), format_debug_effects(enemy_data.get("status_effects", []))])
		if not manager.enemy.is_empty() and encounter_lines.is_empty():
			encounter_lines.append("%s HP %s/%s эффекты=%s" % [str(manager.enemy.get("name", manager.enemy.get("id", "противник"))), str(manager.enemy.get("hp", "?")), str(manager.enemy.get("max_hp", "?")), format_debug_effects(manager.enemy.get("status_effects", []))])
		lines.append("Противники: %s" % ("; ".join(encounter_lines) if not encounter_lines.is_empty() else "нет активной встречи"))
	else:
		lines.append("Активной экспедиции нет. Чтобы увидеть seed, маршрут, эффекты и боевые данные, запустите забег.")
	lines.append("")
	lines.append("КОНТЕНТ-РЕЕСТР")
	var content_issues: Array[String] = ContentRegistry.validate_content_registry()
	lines.append("Валидатор GDScript: %s · ошибок: %d" % ["PASS" if content_issues.is_empty() else "ISSUES", content_issues.size()])
	lines.append("Тайлы: %d · синергии тайлов: %d · враги: %d · боссы: %d · статусы: %d · события: %d · перки: %d · исследования: %d" % [ContentRegistry.TILE_DEFS.size(), ContentRegistry.TILE_SYNERGIES.size(), ContentRegistry.ENEMIES.size(), ContentRegistry.BOSSES.size(), ContentRegistry.STATUS_EFFECTS.size(), ContentRegistry.EXPEDITION_EVENTS.size(), ContentRegistry.PERKS.size(), ContentRegistry.BASE_RESEARCH.size()])
	lines.append("Сложности: %d · режимы экспедиции: %d · модификаторы: %d · контракты: %d · постройки: %d" % [ContentRegistry.DIFFICULTY_PRESETS.size(), ContentRegistry.EXPEDITION_MODES.size(), ContentRegistry.RUN_MODIFIERS.size(), ContentRegistry.EXPEDITION_CONTRACTS.size(), ContentRegistry.BUILDINGS.size()])
	if not content_issues.is_empty():
		lines.append("Первые ошибки реестра:")
		for issue_index in range(mini(30, content_issues.size())):
			lines.append("  • " + content_issues[issue_index])
		if content_issues.size() > 30:
			lines.append("  … ещё %d ошибок" % (content_issues.size() - 30))
	lines.append("")
	lines.append("ЖУРНАЛ И ОБРАТНАЯ СВЯЗЬ")
	if manager != null:
		for log_index in range(mini(8, manager.event_log.size())):
			lines.append("  • " + str(manager.event_log[log_index]))
	lines.append("")
	lines.append("ПРИМЕЧАНИЕ: отчёт диагностический. Он не меняет seed, бой, контент или сохранение. Статический реестр PASS не означает успешную компиляцию/визуальную проверку в Godot.")
	return "\n".join(lines)


func format_debug_effects(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return "нет"
	var parts: Array[String] = []
	for effect_value in value:
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value
		parts.append("%s x%s %.1fс" % [str(effect.get("id", "?")), str(effect.get("stacks", 1)), float(effect.get("duration", 0.0))])
	return ", ".join(parts) if not parts.is_empty() else "нет"

