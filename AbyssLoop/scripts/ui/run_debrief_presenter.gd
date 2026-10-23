extends RefCounted

## Pure post-run coaching text. Reads the finalized summary only; never mutates rewards or progression.

static func build(summary: Dictionary) -> Dictionary:
	# This is coaching only: it reads the finalized summary and never mutates rewards or progression.
	var outcome := str(summary.get("outcome", "defeat"))
	var loops := maxi(0, int(summary.get("loops", 0)))
	var victories := maxi(0, int(summary.get("victories", 0)))
	var bosses := maxi(0, int(summary.get("bosses_defeated", 0)))
	var elites := maxi(0, int(summary.get("elites_defeated", 0)))
	var events := maxi(0, int(summary.get("events_resolved", 0)))
	var lost_scrap := maxi(0, int(summary.get("lost_scrap", 0)))
	var lost_crystals := maxi(0, int(summary.get("lost_crystals", 0)))
	var earned_scrap := maxi(0, int(summary.get("earned_scrap", 0)))
	var objective_value: Variant = summary.get("objective", {})
	var objective: Dictionary = objective_value if typeof(objective_value) == TYPE_DICTIONARY else {}
	var contract_value: Variant = summary.get("contract", {})
	var contract: Dictionary = contract_value if typeof(contract_value) == TYPE_DICTIONARY else {}
	var challenge_value: Variant = summary.get("challenge", {})
	var challenge: Dictionary = challenge_value if typeof(challenge_value) == TYPE_DICTIONARY else {}
	var finding := ""
	var action := ""

	if bool(summary.get("endgame_completed", false)):
		finding = "Длинная экспедиция завершена: цель эндгейма выполнена."
		action = "Сохрани этот seed и результат в журнале. Перед новым спуском вложи сохранённую добычу в постоянное развитие или экипировку."
	elif outcome == "return":
		if bool(objective.get("completed", false)) or bool(challenge.get("completed", false)) or (bool(contract.get("completed", false)) and not bool(contract.get("failed", false))):
			finding = "Безопасное возвращение закрепило добычу и завершённую дополнительную цель."
			action = "Перед следующим забегом проверь награды цели и контракта, затем выбери один приоритет улучшения: выживаемость, урон или полезность тайлов."
		elif loops >= 5 or bosses > 0 or elites > 0:
			finding = "Сильный результат: %d циклов, %d побед над боссами и %d над элитой." % [loops, bosses, elites]
			action = "Сравни счёт с личным рекордом той же сложности. Не повышай риск автоматически: сначала используй сохранённые материалы и проверь синергию экипировки."
		else:
			finding = "Безопасный возврат сохранил добычу целиком: %d материалов получено за забег." % earned_scrap
			action = "Вложи часть ресурсов в одно постоянное улучшение или исследование. Затем попробуй продвинуться ещё на цикл, не игнорируя состояние здоровья и прогноз опасности."
	else:
		if lost_crystals > 0:
			finding = "Главная цена поражения — потеряно %d редких ресурсов и %d материалов." % [lost_crystals, lost_scrap]
			action = "При переносимой добыче безопасный возврат вне боя сохраняет больше, чем продолжение на низком здоровье. Планируй выход до следующей опасной встречи."
		elif victories == 0 or loops <= 1:
			finding = "Экспедиция оборвалась рано: %d циклов и %d побед." % [loops, victories]
			action = "Перед повторной попыткой сравни оружие и броню с доступными предметами, проверь постоянные исследования и выбери защитный тайл рядом с вероятными встречами."
		elif bosses == 0 and loops >= 3:
			finding = "Ты прошёл %d циклов, но не победил ни одного босса; обычные победы: %d." % [loops, victories]
			action = "Подготовь отдельный набор против сильной одиночной цели: устойчивость героя, надёжный урон и тайлы поддержки. Возвращайся до того, как опасность станет критической."
		else:
			finding = "Бои дали %d побед и %d побед над боссами, но забег завершился поражением." % [victories, bosses]
			action = "Изучи выбранные тайлы и последние решения событий. Перед следующим заходом усили наиболее слабую сторону экипировки и уходи на базу до критического истощения."

	if bool(contract.get("failed", false)):
		action += " Контракт не выполнен — в следующем забеге выбери задачу с более реалистичным сроком или начни без контракта."
	elif not contract.is_empty() and not bool(contract.get("completed", false)):
		action += " Контракт остался незавершённым; проверь его условие и текущий прогресс перед выбором следующего."
	if events == 0 and loops > 0 and outcome == "return":
		action += " В следующий раз обращай внимание на узлы событий: они могут изменить риск и состав добычи."
	return {"finding": finding, "action": action}

