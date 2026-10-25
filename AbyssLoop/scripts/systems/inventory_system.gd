extends RefCounted
class_name InventorySystem

const SLOT_NAMES := {
	"weapon": "Оружие", "helmet": "Шлем", "armor": "Броня",
	"shield": "Щит", "amulet": "Амулет", "core": "Ядро бездны"
}
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "helmet", "armor", "shield", "amulet", "core"]
const BACKPACK_CAPACITY := 12
const MAX_UPGRADE_LEVEL := 10

# Affixes are data-driven: their numeric fields are aggregated centrally and
# consumed by ExpeditionManager, so the UI does not implement equipment rules.
const ARCHETYPES := {
	"weapon": [
		{"id": "assault", "name": "Штурм", "description": "Дополнительный урон", "stats": {"attack": 2}},
		{"id": "precision", "name": "Точность", "description": "Повышенный шанс критического удара", "stats": {"crit": 0.035}},
		{"id": "siphon", "name": "Сифон", "description": "Восстанавливает здоровье после победы", "stats": {"kill_heal": 3}},
		{"id": "wound", "name": "Резец глубин", "description": "Шанс вызвать кровотечение при ударе", "stats": {"bleed_chance": 0.20, "bleed_damage": 2}},
		{"id": "leech", "name": "Живой клинок", "description": "Возвращает часть нанесённого урона в здоровье героя", "stats": {"lifesteal": 0.08, "attack": 1}}
	],
	"armor": [
		{"id": "bastion", "name": "Бастион", "description": "Усиленная защита и барьер в начале боя", "stats": {"defense": 1, "hp": 5, "barrier_on_encounter": 6}},
		{"id": "scavenger", "name": "Сборщик", "description": "Дополнительные материалы при посещении тайлов", "stats": {"tile_scrap": 1}},
		{"id": "field_medic", "name": "Полевой медик", "description": "Небольшое лечение после решения события", "stats": {"event_heal": 3}},
		{"id": "phaseweave", "name": "Фазовая ткань", "description": "Шанс уклониться от атаки, не получив урон или негативный эффект", "stats": {"dodge_chance": 0.07, "hp": 3}}
	],
	"helmet": [
		{"id": "observer", "name": "Наблюдатель", "description": "Считывает телеграфы: снижает урон особых атак элиты и боссов", "stats": {"crit": 0.025, "dodge_chance": 0.015, "special_damage_reduction": 0.07}},
		{"id": "echo_hood", "name": "Глушитель эха", "description": "Снижает риск опасных встреч на ландшафте", "stats": {"tile_spawn_bonus": -0.035, "hp": 3}},
		{"id": "deep_sight", "name": "Глубинное зрение", "description": "Находит слабые места элиты и боссов", "stats": {"crit": 0.04, "reward_bonus": 0.025, "elite_boss_damage_bonus": 0.06}}
	],
	"shield": [
		{"id": "bulwark", "name": "Оплот", "description": "Щит гасит первые импульсы и особые атаки врага", "stats": {"defense": 1, "hp": 6, "barrier_on_encounter": 4, "special_damage_reduction": 0.03}},
		{"id": "reflector", "name": "Призматический отражатель", "description": "Рассеивает усиленный телеграфированный удар", "stats": {"defense": 1, "dodge_chance": 0.025, "special_damage_reduction": 0.08}},
		{"id": "rootguard", "name": "Корневой заслон", "description": "Защита помогает восстановиться после схватки", "stats": {"defense": 2, "kill_heal": 1}}
	],
	"amulet": [
		{"id": "wayfinder", "name": "Нить проводника", "description": "Находит безопасные развилки и запасы", "stats": {"tile_scrap": 1, "tile_spawn_bonus": -0.02}},
		{"id": "pulse_charm", "name": "Талисман импульса", "description": "Резонирует с героем и ускоряет атаки", "stats": {"speed": 0.035, "lifesteal": 0.02}},
		{"id": "event_reader", "name": "Слухач событий", "description": "Читает повадки элиты и извлекает больше трофеев", "stats": {"event_heal": 3, "reward_bonus": 0.035, "elite_boss_damage_bonus": 0.04}},
		{"id": "route_scribe", "name": "Чертёжник дороги", "description": "Увеличивает на 10% полезную боевую награду от трёхузловых формаций дороги", "stats": {"road_formation_bonus": 0.10}},
		{"id": "relic_scout", "name": "Собиратель реликвий", "description": "Повышает шкалу редкости найденной экипировки на 5 п.п., но немного чаще привлекает встречи", "stats": {"rare_find_bonus": 0.05, "tile_spawn_bonus": 0.02}}
	],
	"core": [
		{"id": "tempo", "name": "Темп", "description": "Ускоренные атаки", "stats": {"speed": 0.045}},
		{"id": "resonance", "name": "Резонанс", "description": "Повышенная добыча за победу", "stats": {"reward_bonus": 0.08}},
		{"id": "pathfinder", "name": "Разведчик", "description": "Снижает шанс встречи на узлах маршрута", "stats": {"tile_spawn_bonus": -0.04}},
		{"id": "reflex", "name": "Рефлекс бездны", "description": "Уклонение и небольшое восстановление от атак", "stats": {"dodge_chance": 0.045, "lifesteal": 0.025}}
	]
}

const SET_DEFS := {
	"vanguard": {"name": "Авангард", "threshold": 2, "effects": {"defense": 2, "hp": 8}, "description": "2 предмета: +2 защиты и +8 здоровья."},
	"scavenger": {"name": "Снабжение", "threshold": 2, "effects": {"tile_scrap": 2}, "description": "2 предмета: +2 материала при посещении тайлов."},
	"resonance": {"name": "Резонанс", "threshold": 2, "effects": {"reward_bonus": 0.12, "crit": 0.025}, "description": "2 предмета: +12% награды и +2,5% критического шанса."},
	"phasebound": {"name": "Фазоход", "threshold": 2, "effects": {"dodge_chance": 0.04, "lifesteal": 0.03}, "description": "2 предмета: +4% уклонения и +3% вампиризма."},
	"abyss_tracker": {"name": "Следопыт Бездны", "threshold": 2, "effects": {"biome_damage_bonus": 0.05, "biome_resistance": 0.025, "reward_bonus": 0.03}, "description": "2 предмета: +5% урона и 2,5% защиты против существ ландшафта, +3% добычи."}
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
		{"id": "harvester_heart", "name": "Сердце импульсов", "slot": "core", "archetype": "resonance", "archetype_name": "Резонанс", "archetype_description": "Реликвия Светожора: усиливает импульс героя, добычу и восстановление после побед.", "set_id": "resonance", "stats": {"hp": 8, "speed": 0.06, "reward_bonus": 0.15, "kill_heal": 1, "lifesteal": 0.04}}
	],
	"matriarch": [
		{"id": "matriarch_scythe", "name": "Серп мшистой королевы", "slot": "weapon", "archetype": "siphon", "archetype_name": "Сифон", "archetype_description": "Реликвия Матриарха: высасывает силы у противников и улучшает снабжение.", "set_id": "scavenger", "stats": {"attack": 3, "kill_heal": 2, "tile_scrap": 1, "bleed_chance": 0.10}},
		{"id": "matriarch_mantle", "name": "Плащ корневой кладки", "slot": "armor", "archetype": "scavenger", "archetype_name": "Сборщик", "archetype_description": "Реликвия Матриарха: броня из корней помогает собирать материалы и восстанавливаться после событий.", "set_id": "scavenger", "stats": {"defense": 2, "hp": 10, "tile_scrap": 1, "event_heal": 4}}
	],
	"bellkeeper": [
		{"id": "bell_tuning_fork", "name": "Калибратор последнего звона", "slot": "weapon", "archetype": "precision", "archetype_name": "Точность", "archetype_description": "Реликвия Глашатая: концентрирует импульс в критический точный удар.", "set_id": "resonance", "stats": {"attack": 4, "crit": 0.055, "reward_bonus": 0.06}},
		{"id": "bell_veil", "name": "Вуаль немого резонанса", "slot": "core", "archetype": "pathfinder", "archetype_name": "Разведчик", "archetype_description": "Реликвия Глашатая: гасит часть сигнала встречи и ускоряет атаки.", "set_id": "resonance", "stats": {"speed": 0.07, "crit": 0.035, "tile_spawn_bonus": -0.04, "reward_bonus": 0.08, "dodge_chance": 0.055}}
	],
}

# Secret discoveries award named relics instead of generic random drops.
# Each choice leads to a different equipment profile and encourages a real build decision.
const SECRET_RELIC_TEMPLATES := {
	"echo_chart_core": {"name": "Компас за закрытой картой", "slot": "core", "archetype": "pathfinder", "archetype_name": "Разведчик", "archetype_description": "Тайная реликвия Архива: предсказывает безопасные участки и усиливает добычу.", "set_id": "resonance", "stats": {"hp": 8, "speed": 0.05, "reward_bonus": 0.10, "tile_spawn_bonus": -0.02, "dodge_chance": 0.04}},
	"riftwalker_edge": {"name": "Клинок незамкнутого разлома", "slot": "weapon", "landscape_affinity": "fault_line", "affinity_name": "Трещина живой породы", "affinity_effect": {"reward_bonus": 0.08, "enemy_bonus": -0.04}, "archetype": "wound", "archetype_name": "Резец глубин", "archetype_description": "Тайная реликвия Разлома: оружие для точных ударов и кровоточащих ран.", "set_id": "vanguard", "stats": {"attack": 4, "crit": 0.04, "bleed_chance": 0.12, "bleed_damage": 2}},
	"brood_shell": {"name": "Панцирь тихого выводка", "slot": "armor", "archetype": "bastion", "archetype_name": "Бастион", "archetype_description": "Тайная реликвия Питомника: переживает первые атаки, приносит материалы и лечит после побед.", "set_id": "scavenger", "stats": {"defense": 2, "hp": 14, "kill_heal": 2, "tile_scrap": 1, "barrier_on_encounter": 5, "lifesteal": 0.03}},
	"snare_hunter_core": {"name": "Ядро приманивающего импульса", "slot": "core", "archetype": "resonance", "archetype_name": "Резонанс", "archetype_description": "Тайная реликвия Сети: увеличивает награду и слегка повышает шанс новой встречи.", "set_id": "resonance", "stats": {"speed": 0.07, "crit": 0.03, "reward_bonus": 0.18, "tile_spawn_bonus": 0.06}},
	"prism_heart": {"name": "Сердце призматического улья", "slot": "core", "landscape_affinity": "crystal_hive", "affinity_name": "Кристальный улей", "affinity_effect": {"crystals": 1, "enemy_bonus": -0.06, "reward_bonus": 0.08}, "archetype": "reflex", "archetype_name": "Рефлекс бездны", "archetype_description": "Тайная реликвия улья и обелиска: превращает часть урона в здоровье и позволяет уклоняться от импульсов.", "set_id": "phasebound", "stats": {"hp": 6, "speed": 0.03, "reward_bonus": 0.08, "dodge_chance": 0.06, "lifesteal": 0.04}},
	"echo_veil": {"name": "Вуаль немого импульса", "slot": "armor", "landscape_affinity": "echo_obelisk", "affinity_name": "Обелиск немого сигнала", "affinity_effect": {"spawn_bonus": -0.09, "reward_bonus": 0.05}, "archetype": "phaseweave", "archetype_name": "Фазовая ткань", "archetype_description": "Тайная реликвия, глушащая часть сигнала встреч ценой более опасной добычи.", "set_id": "phasebound", "stats": {"defense": 1, "hp": 8, "dodge_chance": 0.045, "tile_spawn_bonus": -0.04, "reward_bonus": 0.12}},
	"rootwatch_mantle": {"name": "Мантия корневого хранителя", "slot": "armor", "landscape_affinity": "spore_garden", "affinity_name": "Сад спороносных колокольчиков", "affinity_effect": {"heal": 3, "enemy_bonus": -0.05}, "archetype": "phaseweave", "archetype_name": "Фазовая ткань", "archetype_description": "Тайная реликвия сада: корни смягчают удар, а живой импульс поддерживает героя.", "set_id": "phasebound", "stats": {"defense": 1, "hp": 10, "kill_heal": 2, "dodge_chance": 0.045, "lifesteal": 0.025}},
	"bone_impulse_edge": {"name": "Клинок костяного импульса", "slot": "weapon", "landscape_affinity": "bone_orchard", "affinity_name": "Костяной сад", "affinity_effect": {"reward_bonus": 0.06, "enemy_bonus": -0.05}, "archetype": "leech", "archetype_name": "Живой клинок", "archetype_description": "Тайная реликвия костяного сада: усиливает удар и возвращает часть здоровья при попадании.", "set_id": "vanguard", "stats": {"attack": 3, "crit": 0.025, "bleed_chance": 0.08, "bleed_damage": 2, "lifesteal": 0.05}}
}

# Prefix/suffix affixes make rare drops differ beyond a single rarity multiplier.
# Affix effects use the same stat keys as equipment archetypes and are applied centrally.
const ITEM_AFFIXES := {
	"keen_edge": {"name": "Точная грань", "description": "+1 атака и +1,5% к критическому шансу.", "slot": "weapon", "position": "prefix", "stats": {"attack": 1, "crit": 0.015}},
	"barbed_edge": {"name": "Зубчатая кромка", "description": "+7% к шансу кровотечения и +1 к его урону.", "slot": "weapon", "position": "prefix", "stats": {"bleed_chance": 0.07, "bleed_damage": 1}},
	"hungry_steel": {"name": "Голодная сталь", "description": "+1 атака и +1 лечение после победы.", "slot": "weapon", "position": "prefix", "stats": {"attack": 1, "kill_heal": 1}},
	"deep_mark": {"name": "Клеймо глубин", "description": "+2,5% к критическому шансу и +2% к награде.", "slot": "weapon", "position": "suffix", "stats": {"crit": 0.025, "reward_bonus": 0.02}},
	"bleeding_grooves": {"name": "Кровавые насечки", "description": "+6% к шансу кровотечения и +1 к его урону.", "slot": "weapon", "position": "suffix", "stats": {"bleed_chance": 0.06, "bleed_damage": 1}},
	"reaping_echo": {"name": "Эхо жатвы", "description": "+1 лечение после победы.", "slot": "weapon", "position": "suffix", "stats": {"kill_heal": 1}},
	"reinforced_plate": {"name": "Усиленная пластина", "description": "+1 защита и +4 здоровья.", "slot": "armor", "position": "prefix", "stats": {"defense": 1, "hp": 4}},
	"hard_shell_helm": {"name": "Костяная накладка", "description": "+4 здоровья и +1% уклонения.", "slot": "helmet", "position": "prefix", "stats": {"hp": 4, "dodge_chance": 0.01}},
	"deep_focus": {"name": "Фокус глубины", "description": "+2,5% критического шанса и +2% к награде.", "slot": "helmet", "position": "suffix", "stats": {"crit": 0.025, "reward_bonus": 0.02}},
	"crystal_brace": {"name": "Кристальный упор", "description": "+1 защита и +2 к барьеру в начале боя.", "slot": "shield", "position": "prefix", "stats": {"defense": 1, "barrier_on_encounter": 2}},
	"root_latch": {"name": "Корневая защёлка", "description": "+1 лечение после победы.", "slot": "shield", "position": "suffix", "stats": {"kill_heal": 1}},
	"whisper_thread": {"name": "Нить шёпота", "description": "−2 п.п. к шансу встречи и +2% к награде.", "slot": "amulet", "position": "prefix", "stats": {"tile_spawn_bonus": -0.02, "reward_bonus": 0.02}},
	"echo_pendant": {"name": "Подвеска эха", "description": "+2% скорости и +2% вампиризма.", "slot": "amulet", "position": "suffix", "stats": {"speed": 0.02, "lifesteal": 0.02}},
	"trophy_compass": {"name": "Око собирателя", "description": "+8 процентных пунктов к шансу трофея биома при экипировке.", "slot": "amulet", "position": "prefix", "stats": {"trophy_find_bonus": 0.08}},
	"bossproof_ridge": {"name": "Гребень предвестника", "description": "Ослабляет особые атаки элиты и боссов на 3%.", "slot": "helmet", "position": "suffix", "stats": {"special_damage_reduction": 0.03}},
	"phase_catching_brace": {"name": "Ловец импульса", "description": "Ослабляет телеграфированные особые атаки на 4%.", "slot": "shield", "position": "prefix", "stats": {"special_damage_reduction": 0.04}},
	"boss_lens": {"name": "Линза охотника", "description": "+4% урона элите и боссам.", "slot": "amulet", "position": "suffix", "stats": {"elite_boss_damage_bonus": 0.04}},
	"moss_lining": {"name": "Моховая подкладка", "description": "+8 здоровья и +2 лечения после события.", "slot": "armor", "position": "prefix", "stats": {"hp": 8, "event_heal": 2}},
	"phase_guard": {"name": "Фазовый щит", "description": "+1 защита и +3 барьера в начале боя.", "slot": "armor", "position": "prefix", "stats": {"defense": 1, "barrier_on_encounter": 3}},
	"quiet_march": {"name": "Тихий переход", "description": "−4 п.п. к шансу встречи и +3 здоровья.", "slot": "armor", "position": "suffix", "stats": {"tile_spawn_bonus": -0.04, "hp": 3}},
	"cartographer_stitch": {"name": "Картографский шов", "description": "+1 материал при посещении тайла и +2% к награде.", "slot": "armor", "position": "suffix", "stats": {"tile_scrap": 1, "reward_bonus": 0.02}},
	"after_event_patch": {"name": "Запасная заплата", "description": "+3 лечения после события и +1 после победы.", "slot": "armor", "position": "suffix", "stats": {"event_heal": 3, "kill_heal": 1}},
	"resonant_coil": {"name": "Резонансная катушка", "description": "+2% к скорости и +2% к критическому шансу.", "slot": "core", "position": "prefix", "stats": {"speed": 0.02, "crit": 0.02}},
	"volatile_cell": {"name": "Нестабильная ячейка", "description": "+3% к скорости, но встречи вероятнее на 4 п.п.", "slot": "core", "position": "prefix", "stats": {"speed": 0.03, "tile_spawn_bonus": 0.04}},
	"steady_heart": {"name": "Сердце ритма", "description": "+5 здоровья и +1% к скорости.", "slot": "core", "position": "prefix", "stats": {"hp": 5, "speed": 0.01}},
	"route_echo": {"name": "Эхо маршрута", "description": "+5% к награде и +1% к критическому шансу.", "slot": "core", "position": "suffix", "stats": {"reward_bonus": 0.05, "crit": 0.01}},
	"pathfinder_calibration": {"name": "Калибратор пути", "description": "−4 п.п. к шансу встречи и +3% к награде.", "slot": "core", "position": "suffix", "stats": {"tile_spawn_bonus": -0.04, "reward_bonus": 0.03}},
	"road_formation_etching": {"name": "Гравировка дорожных узлов", "description": "Увеличивает на 6% полезную боевую награду от трёхузловых формаций дороги.", "slot": "amulet", "position": "suffix", "stats": {"road_formation_bonus": 0.06}},
	"deep_catalogue": {"name": "Глубокий каталог", "description": "Повышает шкалу редкости следующей найденной экипировки на 7 п.п. при экипировке амулета.", "slot": "amulet", "position": "suffix", "stats": {"rare_find_bonus": 0.07}},
	"impulse_overload": {"name": "Контур импульса", "description": "+1 атака и +1,5% к скорости.", "slot": "core", "position": "suffix", "stats": {"attack": 1, "speed": 0.015}},
	"echovore": {"name": "Эхоед", "description": "+6% вампиризма: часть урона возвращается здоровьем.", "slot": "weapon", "position": "prefix", "stats": {"lifesteal": 0.06}},
	"phase_silk": {"name": "Фазовый шёлк", "description": "+5% шанса уклониться от атаки.", "slot": "armor", "position": "prefix", "stats": {"dodge_chance": 0.05}},
	"hollow_lining": {"name": "Полая подкладка", "description": "+4% вампиризма и +2 здоровья.", "slot": "armor", "position": "suffix", "stats": {"lifesteal": 0.04, "hp": 2}},
	"phantom_coil": {"name": "Катушка фантома", "description": "+4,5% уклонения и +1% скорости.", "slot": "core", "position": "prefix", "stats": {"dodge_chance": 0.045, "speed": 0.01}},
	"life_resonance": {"name": "Жизненный резонанс", "description": "+5% вампиризма и +2% награды.", "slot": "core", "position": "suffix", "stats": {"lifesteal": 0.05, "reward_bonus": 0.02}},
	"spore_bane": {"name": "Споровый жнец", "description": "+8% урона споровым существам и +6 п.п. к шансу их трофея.", "slot": "weapon", "position": "prefix", "stats": {"spore_damage_bonus": 0.08, "spore_trophy_bonus": 0.06}},
	"bone_splitter": {"name": "Раскалыватель костей", "description": "+8% урона костяным существам и +6 п.п. к шансу их трофея.", "slot": "weapon", "position": "suffix", "stats": {"bone_damage_bonus": 0.08, "bone_trophy_bonus": 0.06}},
	"prism_sunder": {"name": "Призматический раскол", "description": "+8% урона кристаллическим существам и +6 п.п. к шансу их трофея.", "slot": "weapon", "position": "suffix", "stats": {"crystal_damage_bonus": 0.08, "crystal_trophy_bonus": 0.06}},
	"echo_cutter": {"name": "Резонансный резец", "description": "+8% урона эхо-сущностям и +6 п.п. к шансу их трофея.", "slot": "weapon", "position": "prefix", "stats": {"echo_damage_bonus": 0.08, "echo_trophy_bonus": 0.06}},
	"spore_filter": {"name": "Фильтр спор", "description": "Снижает урон споровых существ на 6% и даёт 12% шанс подавить яд.", "slot": "helmet", "position": "prefix", "stats": {"spore_resistance": 0.06, "poison_resistance": 0.12}},
	"echo_dampener": {"name": "Глушитель фантома", "description": "Снижает урон эхо-сущностей на 6% и даёт 12% шанс подавить искажение.", "slot": "helmet", "position": "suffix", "stats": {"echo_resistance": 0.06, "distortion_resistance": 0.12}},
	"crystal_grounding": {"name": "Заземлитель улья", "description": "Снижает урон кристаллических существ на 8% и даёт 12% шанс подавить кровотечение.", "slot": "shield", "position": "prefix", "stats": {"crystal_resistance": 0.08, "bleed_resistance": 0.12}},
	"bone_sieve": {"name": "Костяная прослойка", "description": "Снижает урон костяных существ на 6% и даёт 12% шанс подавить рану.", "slot": "armor", "position": "suffix", "stats": {"bone_resistance": 0.06, "wound_resistance": 0.12}},
	"clear_tone": {"name": "Чистый тон", "description": "Даёт 12% шанс подавить ослабление от резонансных атак.", "slot": "amulet", "position": "suffix", "stats": {"weakness_resistance": 0.12}}
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
	},
	"living_phase": {
		"name": "Живой фантом",
		"description": "Живой клинок + Фазовая ткань: +4% вампиризма и +2% уклонения.",
		"requirements": {"weapon": ["leech"], "armor": ["phaseweave"]},
		"effects": {"lifesteal": 0.04, "dodge_chance": 0.02}
	},
	"echo_guard": {
		"name": "Глухая защита",
		"description": "Наблюдатель + Призматический отражатель: особые атаки элиты и боссов слабее на 5%.",
		"requirements": {"helmet": ["observer"], "shield": ["reflector"]},
		"effects": {"special_damage_reduction": 0.05}
	},
	"deep_hunter": {
		"name": "Охотник на глубине",
		"description": "Глубинное зрение + Слухач событий: +4% урона элите и боссам и +3% к награде.",
		"requirements": {"helmet": ["deep_sight"], "amulet": ["event_reader"]},
		"effects": {"elite_boss_damage_bonus": 0.04, "reward_bonus": 0.03}
	},
	"quiet_cartography": {
		"name": "Тихая картография",
		"description": "Глушитель эха + Нить проводника: ниже шанс встречи, больше материалов на тайлах.",
		"requirements": {"helmet": ["echo_hood"], "amulet": ["wayfinder"]},
		"effects": {"tile_spawn_bonus": -0.03, "tile_scrap": 1}
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
	"event_heal": {"min": 0, "max": 10},
	"lifesteal": {"min": 0.0, "max": 0.25},
	"dodge_chance": {"min": 0.0, "max": 0.25},
	"special_damage_reduction": {"min": 0.0, "max": 0.35},
	"elite_boss_damage_bonus": {"min": 0.0, "max": 0.25},
	"biome_damage_bonus": {"min": 0.0, "max": 0.20},
	"biome_resistance": {"min": 0.0, "max": 0.20},
	"spore_damage_bonus": {"min": 0.0, "max": 0.25},
	"spore_trophy_bonus": {"min": 0.0, "max": 0.12},
	"crystal_damage_bonus": {"min": 0.0, "max": 0.25},
	"crystal_trophy_bonus": {"min": 0.0, "max": 0.12},
	"bone_damage_bonus": {"min": 0.0, "max": 0.25},
	"bone_trophy_bonus": {"min": 0.0, "max": 0.12},
	"echo_damage_bonus": {"min": 0.0, "max": 0.25},
	"echo_trophy_bonus": {"min": 0.0, "max": 0.12},
	"spore_resistance": {"min": 0.0, "max": 0.20},
	"crystal_resistance": {"min": 0.0, "max": 0.20},
	"bone_resistance": {"min": 0.0, "max": 0.20},
	"echo_resistance": {"min": 0.0, "max": 0.20},
	"trophy_find_bonus": {"min": 0.0, "max": 0.25},
	"road_formation_bonus": {"min": 0.0, "max": 0.25},
	"rare_find_bonus": {"min": 0.0, "max": 0.12},
	"poison_resistance": {"min": 0.0, "max": 0.25},
	"bleed_resistance": {"min": 0.0, "max": 0.25},
	"wound_resistance": {"min": 0.0, "max": 0.25},
	"distortion_resistance": {"min": 0.0, "max": 0.25},
	"weakness_resistance": {"min": 0.0, "max": 0.25}
}

const RARITY_ORDER: Array[String] = ["Обычный", "Редкий", "Эпический", "Реликтовый"]
const RARITY_BASE_WEIGHTS := {"Обычный": 0.70, "Редкий": 0.24, "Эпический": 0.052, "Реликтовый": 0.008}

func get_effective_rarity_bonus(equipped_bonus: float = 0.0, prepared_bonus: float = 0.0, source_bonus: float = 0.0) -> float:
	# Gear, prepared road-card bonus, and source-specific quality nudges are
	# additive inputs; the combined influence is capped at +25 pp.
	return clampf(clampf(equipped_bonus, 0.0, 0.12) + clampf(prepared_bonus, 0.0, 0.18) + clampf(source_bonus, 0.0, 0.06), 0.0, 0.25)

func get_rarity_distribution(rarity_bonus: float = 0.0) -> Dictionary:
	# Preserve a strictly descending rarity order at every bonus value. Unlike
	# adding a bonus directly to a uniform roll, this cannot inflate relic odds
	# from 0.8% to 25.8% at the bonus cap.
	var bias := clampf(rarity_bonus, 0.0, 0.25)
	var weights := {
		"Обычный": float(RARITY_BASE_WEIGHTS["Обычный"]) * (1.0 - 0.8 * bias),
		"Редкий": float(RARITY_BASE_WEIGHTS["Редкий"]) * (1.0 + 1.4 * bias),
		"Эпический": float(RARITY_BASE_WEIGHTS["Эпический"]) * (1.0 + 4.0 * bias),
		"Реликтовый": float(RARITY_BASE_WEIGHTS["Реликтовый"]) * (1.0 + 12.0 * bias)
	}
	var total_weight := 0.0
	for rarity_name in RARITY_ORDER:
		total_weight += float(weights.get(rarity_name, 0.0))
	var distribution: Dictionary = {}
	if total_weight <= 0.0:
		return {"Обычный": 0.70, "Редкий": 0.24, "Эпический": 0.052, "Реликтовый": 0.008}
	for rarity_name in RARITY_ORDER:
		distribution[rarity_name] = float(weights.get(rarity_name, 0.0)) / total_weight
	return distribution

func roll_rarity(rng: RandomNumberGenerator, rarity_bonus: float = 0.0) -> String:
	var rarity_distribution := get_rarity_distribution(rarity_bonus)
	var rarity_roll := rng.randf()
	var cumulative_rarity_chance := 0.0
	for rarity_name in RARITY_ORDER:
		cumulative_rarity_chance += float(rarity_distribution.get(rarity_name, 0.0))
		if rarity_roll < cumulative_rarity_chance:
			return rarity_name
	return "Реликтовый"

func roll_item(rng: RandomNumberGenerator, loop_count: int, hero_level: int, rarity_bonus: float = 0.0) -> Dictionary:
	var slots: Array = EQUIPMENT_SLOTS.duplicate()
	var slot: String = str(slots[rng.randi_range(0, slots.size() - 1)])
	# The caller applies gear and route preparation bonuses only on a successful drop.
	# A single weighted distribution is shared by combat drops and caches.
	var rarity := roll_rarity(rng, rarity_bonus)
	var multiplier := 1.0
	match rarity:
		"Редкий": multiplier = 1.35
		"Эпический": multiplier = 1.8
		"Реликтовый": multiplier = 2.15
		_: multiplier = 1.0
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
		"barrier_on_encounter": 0,
		"lifesteal": 0.0,
		"dodge_chance": 0.0,
		"special_damage_reduction": 0.0,
		"elite_boss_damage_bonus": 0.0,
		"biome_damage_bonus": 0.0, "biome_resistance": 0.0,
		"spore_damage_bonus": 0.0, "crystal_damage_bonus": 0.0, "bone_damage_bonus": 0.0, "echo_damage_bonus": 0.0,
		"spore_trophy_bonus": 0.0, "crystal_trophy_bonus": 0.0, "bone_trophy_bonus": 0.0, "echo_trophy_bonus": 0.0,
		"spore_resistance": 0.0, "crystal_resistance": 0.0, "bone_resistance": 0.0, "echo_resistance": 0.0,
		"trophy_find_bonus": 0.0, "road_formation_bonus": 0.0, "rare_find_bonus": 0.0,
		"poison_resistance": 0.0, "bleed_resistance": 0.0, "wound_resistance": 0.0, "distortion_resistance": 0.0, "weakness_resistance": 0.0
	}
	match slot:
		"weapon":
			item.attack = maxi(1, int(round((1.0 + float(rank) * 0.5 + rng.randi_range(0, 1)) * multiplier)))
		"helmet":
			item.hp = int(round((2.0 + float(rank) * 1.0) * multiplier))
			item.crit = snappedf(0.015 + minf(0.08, float(rank) * 0.006), 0.005)
		"armor":
			item.defense = maxi(1, int(round((1.0 + float(rank) * 0.25) * multiplier)))
			item.hp = int(round((4.0 + float(rank) * 2.0) * multiplier))
		"shield":
			item.defense = maxi(1, int(round((1.0 + float(rank) * 0.3) * multiplier)))
			item.hp = int(round((2.0 + float(rank) * 1.25) * multiplier))
			item.barrier_on_encounter = maxi(0, int(round(float(rank) * 0.7)))
		"amulet":
			item.hp = int(round((2.0 + float(rank) * 1.0) * multiplier))
			item.speed = snappedf(0.015 + minf(0.08, float(rank) * 0.008), 0.005)
			item.reward_bonus = snappedf(minf(0.10, 0.01 + float(rank) * 0.006), 0.005)
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
	return apply_random_affixes(item, rng)

func _roll_item_affix(slot: String, position: String, rng: RandomNumberGenerator) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for affix_id_value in ITEM_AFFIXES.keys():
		var affix_id := str(affix_id_value)
		var affix: Dictionary = ITEM_AFFIXES[affix_id_value]
		if str(affix.get("slot", "")) != slot or str(affix.get("position", "")) != position:
			continue
		var candidate := affix.duplicate(true)
		candidate["id"] = affix_id
		candidates.append(candidate)
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)

func apply_random_affixes(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result := item.duplicate(true)
	result["affix_ids"] = []
	result["affix_names"] = []
	result["affix_description"] = ""
	var rarity := str(result.get("rarity", "Обычный"))
	if rarity not in ["Редкий", "Эпический", "Реликтовый"]:
		result["power"] = item_power(result)
		return result
	var slot := str(result.get("slot", ""))
	var prefix := _roll_item_affix(slot, "prefix", rng)
	var suffix: Dictionary = {}
	var selected: Array[Dictionary] = []
	if not prefix.is_empty():
		selected.append(prefix)
	if rarity in ["Эпический", "Реликтовый"]:
		suffix = _roll_item_affix(slot, "suffix", rng)
		if not suffix.is_empty():
			selected.append(suffix)
	var affix_ids: Array[String] = []
	var affix_names: Array[String] = []
	var affix_descriptions := PackedStringArray()
	for affix in selected:
		var affix_id := str(affix.get("id", ""))
		if affix_id.is_empty():
			continue
		affix_ids.append(affix_id)
		affix_names.append(str(affix.get("name", affix_id)))
		affix_descriptions.append(str(affix.get("description", "")))
		var stats_value: Variant = affix.get("stats", {})
		if typeof(stats_value) != TYPE_DICTIONARY:
			continue
		var stats: Dictionary = stats_value
		for stat_key_value in stats.keys():
			var stat_key := str(stat_key_value)
			if not result.has(stat_key):
				continue
			var delta_value: Variant = stats[stat_key_value]
			if stat_key in ["attack", "defense", "hp", "kill_heal", "tile_scrap", "event_heal", "bleed_damage", "barrier_on_encounter"]:
				result[stat_key] = int(result.get(stat_key, 0)) + int(delta_value)
			else:
				result[stat_key] = float(result.get(stat_key, 0.0)) + float(delta_value)
	result["affix_ids"] = affix_ids
	result["affix_names"] = affix_names
	result["affix_description"] = " ".join(affix_descriptions).strip_edges()
	if not selected.is_empty():
		var name_parts := PackedStringArray([str(SLOT_NAMES.get(slot, slot))])
		if not prefix.is_empty():
			name_parts.append(str(prefix.get("name", "")))
		name_parts.append(str(result.get("archetype_name", "Стандарт")))
		if not suffix.is_empty():
			name_parts.append(str(suffix.get("name", "")))
		name_parts.append(rarity)
		result["name"] = " · ".join(name_parts)
	_apply_build_stat_caps(result)
	result["power"] = item_power(result)
	return result

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
        "affix_ids": [], "affix_names": [], "affix_description": "",
		"attack": 0, "defense": 0, "hp": 0, "speed": 0.0, "crit": 0.0,
		"kill_heal": 0, "tile_scrap": 0, "event_heal": 0, "reward_bonus": 0.0,
		"tile_spawn_bonus": 0.0, "bleed_chance": 0.0, "bleed_damage": 0,
		"barrier_on_encounter": 0, "lifesteal": 0.0, "dodge_chance": 0.0, "special_damage_reduction": 0.0, "elite_boss_damage_bonus": 0.0,
		"poison_resistance": 0.0, "bleed_resistance": 0.0, "wound_resistance": 0.0, "distortion_resistance": 0.0, "weakness_resistance": 0.0
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
	if float(item.get("lifesteal", 0.0)) > 0.0:
		item["lifesteal"] = minf(0.25, float(item.get("lifesteal", 0.0)) + minf(0.04, float(rank_bonus) * 0.005))
	if float(item.get("dodge_chance", 0.0)) > 0.0:
		item["dodge_chance"] = minf(0.25, float(item.get("dodge_chance", 0.0)) + minf(0.04, float(rank_bonus) * 0.005))
	item["power"] = item_power(item)
	return item

func make_secret_relic(relic_id: String, loop_count: int, hero_level: int, run_seed: int = 0, run_nonce: int = 0) -> Dictionary:
	var template_value: Variant = SECRET_RELIC_TEMPLATES.get(relic_id, {})
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
		"id": "secret_%s_%d_%d_%d" % [relic_id, run_seed, run_nonce, loop_count],
		"unique_id": relic_id,
		"slot": slot,
		"name": str(template.get("name", "Тайная реликвия")),
		"rarity": "Тайная",
		"rank": rank,
		"upgrade_level": 0,
		"archetype": str(template.get("archetype", "standard")),
		"archetype_name": str(template.get("archetype_name", "Секрет")),
		"archetype_description": str(template.get("archetype_description", "Реликвия скрытого места.")),
		"set_id": set_id,
		"set_name": str(set_definition.get("name", set_id)),
		"is_secret_relic": true,
		"source_event": "landscape_secret",
		"landscape_affinity": str(template.get("landscape_affinity", "")),
		"affinity_name": str(template.get("affinity_name", "")),
		"affinity_effect": template.get("affinity_effect", {}).duplicate(true) if typeof(template.get("affinity_effect", {})) == TYPE_DICTIONARY else {},
        "affix_ids": [], "affix_names": [], "affix_description": "",
		"attack": 0, "defense": 0, "hp": 0,
		"speed": 0.0, "crit": 0.0, "kill_heal": 0, "tile_scrap": 0,
		"event_heal": 0, "reward_bonus": 0.0, "tile_spawn_bonus": 0.0,
		"bleed_chance": 0.0, "bleed_damage": 0, "barrier_on_encounter": 0, "lifesteal": 0.0, "dodge_chance": 0.0, "special_damage_reduction": 0.0, "elite_boss_damage_bonus": 0.0,
		"poison_resistance": 0.0, "bleed_resistance": 0.0, "wound_resistance": 0.0, "distortion_resistance": 0.0, "weakness_resistance": 0.0
	}
	var stats_value: Variant = template.get("stats", {})
	if typeof(stats_value) == TYPE_DICTIONARY:
		var stats: Dictionary = stats_value
		for key_value in stats.keys():
			var key := str(key_value)
			if item.has(key):
				item[key] = stats[key_value]
	var rank_bonus := mini(4, maxi(0, rank - 2))
	if int(item.get("attack", 0)) > 0:
		item["attack"] = int(item.get("attack", 0)) + rank_bonus
	if int(item.get("defense", 0)) > 0:
		item["defense"] = int(item.get("defense", 0)) + floori(float(rank_bonus) / 2.0)
	if int(item.get("hp", 0)) > 0:
		item["hp"] = int(item.get("hp", 0)) + rank_bonus * 2
	if float(item.get("speed", 0.0)) > 0.0:
		item["speed"] = minf(0.20, float(item.get("speed", 0.0)) + minf(0.03, float(rank_bonus) * 0.005))
	if float(item.get("crit", 0.0)) > 0.0:
		item["crit"] = minf(0.20, float(item.get("crit", 0.0)) + minf(0.025, float(rank_bonus) * 0.005))
	if int(item.get("bleed_damage", 0)) > 0:
		item["bleed_damage"] = int(item.get("bleed_damage", 0)) + floori(float(rank_bonus) / 3.0)
	if float(item.get("bleed_chance", 0.0)) > 0.0:
		item["bleed_chance"] = minf(0.5, float(item.get("bleed_chance", 0.0)) + float(rank_bonus) * 0.01)
	if float(item.get("reward_bonus", 0.0)) > 0.0:
		item["reward_bonus"] = minf(1.5, float(item.get("reward_bonus", 0.0)) + minf(0.05, float(rank_bonus) * 0.01))
	if float(item.get("lifesteal", 0.0)) > 0.0:
		item["lifesteal"] = minf(0.25, float(item.get("lifesteal", 0.0)) + minf(0.04, float(rank_bonus) * 0.005))
	if float(item.get("dodge_chance", 0.0)) > 0.0:
		item["dodge_chance"] = minf(0.25, float(item.get("dodge_chance", 0.0)) + minf(0.04, float(rank_bonus) * 0.005))
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
	score += clampf(float(item.get("lifesteal", 0.0)), 0.0, 0.25) * 30.0
	score += clampf(float(item.get("dodge_chance", 0.0)), 0.0, 0.25) * 26.0
	score += clampf(float(item.get("special_damage_reduction", 0.0)), 0.0, 0.35) * 22.0
	score += clampf(float(item.get("elite_boss_damage_bonus", 0.0)), 0.0, 0.25) * 20.0
	score += clampf(float(item.get("biome_damage_bonus", 0.0)), 0.0, 0.20) * 22.0
	score += clampf(float(item.get("biome_resistance", 0.0)), 0.0, 0.20) * 18.0
	score += clampf(float(item.get("trophy_find_bonus", 0.0)), 0.0, 0.25) * 24.0
	score += clampf(float(item.get("road_formation_bonus", 0.0)), 0.0, 0.25) * 20.0
	score += clampf(float(item.get("rare_find_bonus", 0.0)), 0.0, 0.12) * 24.0
	for biome_tag in ["spore", "crystal", "bone", "echo"]:
		score += clampf(float(item.get(biome_tag + "_trophy_bonus", 0.0)), 0.0, 0.12) * 16.0
	for status_id in ["poison", "bleed", "wound", "distortion", "weakness"]:
		score += clampf(float(item.get(status_id + "_resistance", 0.0)), 0.0, 0.25) * 24.0
	for tag in ["spore", "crystal", "bone", "echo"]:
		score += clampf(float(item.get(tag + "_damage_bonus", 0.0)), 0.0, 0.25) * 24.0
		score += clampf(float(item.get(tag + "_resistance", 0.0)), 0.0, 0.20) * 20.0
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
		"Реликтовый":
			rarity_multiplier = 2.25
			rarity_crystals = 4
		"Боссовая":
			rarity_multiplier = 2.0
			rarity_crystals = 3
		"Тайная":
			rarity_multiplier = 1.8
			rarity_crystals = 2
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
	var slot := str(item.get("slot", ""))
	match slot:
		"weapon":
			upgraded["attack"] = int(upgraded.get("attack", 0)) + primary_step
			if float(upgraded.get("lifesteal", 0.0)) > 0.0 and next_level % 3 == 0:
				upgraded["lifesteal"] = minf(0.25, float(upgraded.get("lifesteal", 0.0)) + 0.01)
		"armor", "shield":
			upgraded["defense"] = int(upgraded.get("defense", 0)) + primary_step
			if slot == "shield" and next_level % 2 == 0:
				upgraded["special_damage_reduction"] = minf(0.35, float(upgraded.get("special_damage_reduction", 0.0)) + 0.005)
			upgraded["hp"] = int(upgraded.get("hp", 0)) + 2 + next_level
			if float(upgraded.get("dodge_chance", 0.0)) > 0.0 and next_level % 2 == 0:
				upgraded["dodge_chance"] = minf(0.25, float(upgraded.get("dodge_chance", 0.0)) + 0.005)
			if int(upgraded.get("barrier_on_encounter", 0)) > 0 and next_level % 3 == 0:
				upgraded["barrier_on_encounter"] = int(upgraded.get("barrier_on_encounter", 0)) + 2
		"helmet":
			upgraded["hp"] = int(upgraded.get("hp", 0)) + 1 + next_level
			upgraded["crit"] = snappedf(minf(0.75, float(upgraded.get("crit", 0.0)) + 0.003), 0.005)
			if next_level % 2 == 0:
				upgraded["special_damage_reduction"] = minf(0.35, float(upgraded.get("special_damage_reduction", 0.0)) + 0.005)
			if next_level % 3 == 0:
				upgraded["elite_boss_damage_bonus"] = minf(0.25, float(upgraded.get("elite_boss_damage_bonus", 0.0)) + 0.005)
		"amulet":
			upgraded["hp"] = int(upgraded.get("hp", 0)) + 1 + next_level
			upgraded["speed"] = snappedf(minf(1.5, float(upgraded.get("speed", 0.0)) + 0.005), 0.005)
			if next_level % 3 == 0:
				upgraded["elite_boss_damage_bonus"] = minf(0.25, float(upgraded.get("elite_boss_damage_bonus", 0.0)) + 0.005)
			if next_level % 2 == 0:
				upgraded["reward_bonus"] = minf(1.5, float(upgraded.get("reward_bonus", 0.0)) + 0.01)
		"core":
			upgraded["speed"] = snappedf(minf(1.5, float(upgraded.get("speed", 0.0)) + 0.01), 0.005)
			upgraded["crit"] = snappedf(minf(0.75, float(upgraded.get("crit", 0.0)) + 0.005), 0.005)
			if next_level % 3 == 0:
				upgraded["attack"] = int(upgraded.get("attack", 0)) + 1
				if float(upgraded.get("lifesteal", 0.0)) > 0.0:
					upgraded["lifesteal"] = minf(0.25, float(upgraded.get("lifesteal", 0.0)) + 0.005)
				if float(upgraded.get("dodge_chance", 0.0)) > 0.0:
					upgraded["dodge_chance"] = minf(0.25, float(upgraded.get("dodge_chance", 0.0)) + 0.005)
		_:
			return {}
	upgraded["upgrade_level"] = next_level
	upgraded["power"] = item_power(upgraded)
	return upgraded

func get_ejection_echo_dust(item: Dictionary) -> int:
	# An overflowed item is not retained as gear. At settlement it is reduced to
	# Echo Dust, a separate meta-resource; better items yield more, with hard caps.
	if item.is_empty():
		return 0
	var rarity := str(item.get("rarity", "Обычный"))
	var rarity_value := 1
	match rarity:
		"Редкий":
			rarity_value = 2
		"Эпический":
			rarity_value = 4
		"Реликтовый":
			rarity_value = 6
		"Боссовая", "Тайная":
			rarity_value = 5
		"Элитная":
			rarity_value = 3
	var rank := clampi(int(item.get("rank", 1)), 1, 100)
	var upgrade_level := clampi(int(item.get("upgrade_level", 0)), 0, MAX_UPGRADE_LEVEL)
	var power := maxf(0.0, float(item.get("power", item_power(item))))
	var rank_bonus := clampi(floori(float(rank - 1) / 4.0), 0, 2)
	var upgrade_bonus := mini(2, upgrade_level)
	var power_bonus := clampi(floori(power / 35.0), 0, 2)
	return clampi(rarity_value + rank_bonus + upgrade_bonus + power_bonus, 1, 10)

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
		"Реликтовый":
			rarity_scrap = 18
			crystals = 4
		"Боссовая":
			rarity_scrap = 14
			crystals = 3
		"Тайная":
			rarity_scrap = 12
			crystals = 2
	var rank := maxi(1, int(item.get("rank", 1)))
	var upgrade_level := clampi(int(item.get("upgrade_level", 0)), 0, MAX_UPGRADE_LEVEL)
	return {"scrap": 8 + rank * 5 + upgrade_level * 7 + rarity_scrap, "crystals": crystals + floori(float(upgrade_level) / 3.0)}

func can_equip_item(item: Dictionary, slot: String = "") -> bool:
	if item.is_empty():
		return false
	var item_slot := str(item.get("slot", ""))
	var requested_slot := item_slot if slot.is_empty() else slot
	return EQUIPMENT_SLOTS.has(requested_slot) and item_slot == requested_slot and not str(item.get("id", "")).is_empty()

func slot_name(slot: String) -> String:
	return str(SLOT_NAMES.get(slot, "Неизвестный слот"))

func should_equip(candidate: Dictionary, current: Dictionary) -> bool:
	if current.is_empty():
		return true
	return item_power(candidate) > item_power(current)

func total_equipment_stats(equipment: Dictionary) -> Dictionary:
	var stats := _empty_stat_block()
	var set_counts: Dictionary = {}
	for slot_value in EQUIPMENT_SLOTS:
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
	for slot_value in EQUIPMENT_SLOTS:
		var item_value: Variant = equipment.get(str(slot_value), {})
		if typeof(item_value) == TYPE_DICTIONARY:
			stats["power"] = float(stats.get("power", 0.0)) + item_power(item_value)
	return stats

func get_landscape_affinity_effects(equipment: Dictionary, tile_id: String) -> Dictionary:
	var total := {"heal": 0, "scrap": 0, "crystals": 0, "spawn_bonus": 0.0, "enemy_bonus": 0.0, "reward_bonus": 0.0, "messages": []}
	if tile_id.is_empty():
		return total
	var names: Array[String] = []
	for slot in EQUIPMENT_SLOTS:
		var item_value: Variant = equipment.get(slot, {})
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		if str(item.get("landscape_affinity", "")) != tile_id:
			continue
		var effect_value: Variant = item.get("affinity_effect", {})
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value
		for key in ["heal", "scrap", "crystals"]:
			total[key] = int(total.get(key, 0)) + maxi(0, int(effect.get(key, 0)))
		for key in ["spawn_bonus", "enemy_bonus", "reward_bonus"]:
			total[key] = float(total.get(key, 0.0)) + float(effect.get(key, 0.0))
		names.append(str(item.get("name", "Экипировка")))
	if not names.is_empty():
		total["messages"] = ["Сработала связь %s с ландшафтом «%s»." % [", ".join(names), tile_id]]
	return total


func get_landscape_combat_bonus(equipment: Dictionary, active_tile_ids: Array[String], enemy_data: Dictionary) -> Dictionary:
	var tag := str(enemy_data.get("biome_tag", ""))
	if tag.is_empty():
		return {"bonus": 0.0, "items": []}
	var affinity_tags := {
		"spore_garden": "spore", "nursery": "spore",
		"crystal_hive": "crystal", "bone_orchard": "bone",
		"echo_obelisk": "echo", "fault_line": "echo"
	}
	var total := 0.0
	var names: Array[String] = []
	for slot_value in EQUIPMENT_SLOTS:
		var item_value: Variant = equipment.get(str(slot_value), {})
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		var affinity := str(item.get("landscape_affinity", ""))
		if affinity.is_empty() or not active_tile_ids.has(affinity):
			continue
		if str(affinity_tags.get(affinity, "")) != tag:
			continue
		var item_bonus := clampf(float(item.get("affinity_combat_bonus", 0.06)), 0.0, 0.12)
		if item_bonus <= 0.0:
			continue
		total += item_bonus
		names.append(str(item.get("name", "Реликвия")))
	return {"bonus": clampf(total, 0.0, 0.18), "items": names}

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
		"bleed_damage": 0, "barrier_on_encounter": 0, "lifesteal": 0.0, "dodge_chance": 0.0, "special_damage_reduction": 0.0, "elite_boss_damage_bonus": 0.0,
		"biome_damage_bonus": 0.0, "biome_resistance": 0.0,
		"spore_damage_bonus": 0.0, "crystal_damage_bonus": 0.0, "bone_damage_bonus": 0.0, "echo_damage_bonus": 0.0,
		"spore_trophy_bonus": 0.0, "crystal_trophy_bonus": 0.0, "bone_trophy_bonus": 0.0, "echo_trophy_bonus": 0.0,
		"spore_resistance": 0.0, "crystal_resistance": 0.0, "bone_resistance": 0.0, "echo_resistance": 0.0,
		"trophy_find_bonus": 0.0, "road_formation_bonus": 0.0, "rare_find_bonus": 0.0,
		"poison_resistance": 0.0, "bleed_resistance": 0.0, "wound_resistance": 0.0, "distortion_resistance": 0.0, "weakness_resistance": 0.0,
		"active_sets": [], "active_synergies": [], "power": 0.0
	}

func _numeric_stat_keys() -> Array[String]:
	return ["attack", "defense", "hp", "speed", "crit", "kill_heal", "tile_scrap", "event_heal", "reward_bonus", "tile_spawn_bonus", "bleed_chance", "bleed_damage", "barrier_on_encounter", "lifesteal", "dodge_chance", "special_damage_reduction", "elite_boss_damage_bonus", "biome_damage_bonus", "biome_resistance", "spore_damage_bonus", "crystal_damage_bonus", "bone_damage_bonus", "echo_damage_bonus", "spore_trophy_bonus", "crystal_trophy_bonus", "bone_trophy_bonus", "echo_trophy_bonus", "spore_resistance", "crystal_resistance", "bone_resistance", "echo_resistance", "trophy_find_bonus", "road_formation_bonus", "rare_find_bonus", "poison_resistance", "bleed_resistance", "wound_resistance", "distortion_resistance", "weakness_resistance"]

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
