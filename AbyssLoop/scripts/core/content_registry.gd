extends Node

func _ready() -> void:
	var issues := validate_content_registry()
	if not issues.is_empty():
		for issue in issues:
			push_error("ContentRegistry: %s" % issue)

# Single source of truth for temporary content and tuning values.
const BALANCE := {
	"route_cells": 34,
	"safe_intro_route_nodes": 3,
	"first_run_min_starting_tiles": 3,
	"autosave_interval_seconds": 2.0,
	"manager_refresh_interval": 0.16,
	"max_event_log_entries": 8,
	"max_event_history": 100,
	"max_feedback_tones": 4,
	"feedback_damage_cooldown": 0.22,
	"move_speed": 0.82,
	"base_hp": 76,
	"base_attack": 8,
	"base_defense": 2,
	"hero_attack_interval": 0.88,
	"enemy_attack_interval": 1.12,
	"critical_multiplier": 1.7,
	"defeat_keep_ratio": 0.40,
	"max_tile_hand": 4,
	"loot_crystal_chance": 0.22,
	"loot_item_chance": 0.18,
	"cache_item_drop_chance": 0.35,
	"loot_item_bonus_cap": 0.15,
	"loot_item_bonus_multiplier": 0.15,
	"route_reward_scrap": 4,
	"shelter_loop_scrap_bonus_cap": 6,
	"boss_loop_interval": 3,
	"max_encounter_enemies": 3,
	"boss_special_multiplier": 1.65,
	"loop_danger_growth": 0.18,
	"loop_crystal_interval": 2,
	"loop_heal_base": 5,
	"encounter_chance_base": 0.22,
	"encounter_chance_per_loop": 0.04,
	"encounter_chance_min": 0.08,
	"encounter_chance_max": 0.96,
	"max_danger": 6.0,
	"enemy_loop_scaling": 0.18,
	"enemy_danger_scaling": 0.32,
	"enemy_attack_scaling": 0.7,
	"boss_cycle_scaling": 0.28,
	"boss_danger_scaling": 0.22,
	"boss_attack_scaling": 0.5,
	"three_enemy_pack_chance": 0.18,
	"loot_crystal_loop_step": 0.025,
	"loot_crystal_loop_cap": 0.18,
	"boss_reward_bonus": 0.60,
	"enemy_caster_debuff": 0.18,
	"enemy_caster_debuff_duration": 3.5,
	"elite_min_loop": 2,
	"elite_loop_interval": 4,
	"elite_hp_multiplier": 1.40,
	"elite_attack_multiplier": 1.22,
	"elite_defense_bonus": 1,
	"elite_special_every": 3,
	"elite_special_multiplier": 1.50,
	"elite_reward_bonus": 0.40,
	"elite_item_chance": 0.45
}

# Temporary combat effects. Durations use active combat time and are persisted in the run snapshot.
const STATUS_EFFECTS := {
	"distortion": {"name": "Искажение", "description": "Замедляет атаки героя", "kind": "modifier", "duration": 3.5, "max_stacks": 1, "stack_mode": "refresh", "attack_speed_penalty": 0.18, "max_magnitude": 0.65, "tick_interval": 0.0, "tick_damage": 0.0},
	"poison": {"name": "Отравление", "description": "Наносит периодический урон", "kind": "damage_over_time", "duration": 4.0, "max_stacks": 3, "stack_mode": "stack", "tick_interval": 1.0, "tick_damage": 2.0, "max_magnitude": 20.0},
	"exposed": {"name": "Уязвимость", "description": "Временно снижает защиту цели", "kind": "modifier", "duration": 3.0, "max_stacks": 1, "stack_mode": "refresh", "defense_penalty": 1.0, "max_magnitude": 10.0, "tick_interval": 0.0, "tick_damage": 0.0},
	"barrier": {"name": "Защитный барьер", "description": "Поглощает ближайший входящий урон; повторное применение обновляет эффект без накопления щита", "kind": "barrier", "duration": 5.0, "max_stacks": 1, "stack_mode": "refresh", "barrier_amount": 8.0, "max_magnitude": 40.0, "tick_interval": 0.0, "tick_damage": 0.0},
	"wound": {"name": "Рана", "description": "Увеличивает получаемый урон", "kind": "modifier", "duration": 4.0, "max_stacks": 2, "stack_mode": "stack", "damage_taken_penalty": 0.12, "max_magnitude": 0.40, "tick_interval": 0.0, "tick_damage": 0.0},
	"weakness": {"name": "Ослабление", "description": "Снижает наносимый урон", "kind": "modifier", "duration": 3.0, "max_stacks": 1, "stack_mode": "refresh", "attack_penalty": 0.18, "max_magnitude": 0.65, "tick_interval": 0.0, "tick_damage": 0.0},
	"bleed": {"name": "Кровотечение", "description": "Наносит периодический урон", "kind": "damage_over_time", "duration": 4.0, "max_stacks": 3, "stack_mode": "stack", "tick_interval": 1.0, "tick_damage": 2.0, "max_magnitude": 8.0},
	"regeneration": {"name": "Регенерация", "description": "Периодически восстанавливает здоровье", "kind": "healing_over_time", "duration": 3.0, "max_stacks": 1, "stack_mode": "refresh", "tick_interval": 1.0, "tick_heal": 3.0, "max_magnitude": 20.0}
}

const DIFFICULTY_PRESETS := {
	"standard": {"name": "Стандарт", "description": "Базовые правила и обычное восстановление. Подходит для освоения механик.", "enemy_attack_multiplier": 1.0, "enemy_health_multiplier": 1.0, "enemy_defense_multiplier": 1.0, "reward_multiplier": 1.0, "encounter_chance_delta": 0.0, "danger_growth_multiplier": 1.0, "event_damage_multiplier": 1.0, "healing_multiplier": 1.0, "defeat_keep_ratio": 0.40, "starting_danger": 1.0, "challenge_score_multiplier": 1.0, "extra_group_members": 0},
	"volatile": {"name": "Нестабильный", "description": "Чаще столкновения и быстрее растёт опасность; добыча выше.", "enemy_attack_multiplier": 1.08, "enemy_health_multiplier": 1.0, "enemy_defense_multiplier": 1.0, "reward_multiplier": 1.35, "encounter_chance_delta": 0.12, "danger_growth_multiplier": 1.25, "event_damage_multiplier": 1.0, "healing_multiplier": 0.90, "defeat_keep_ratio": 0.40, "starting_danger": 1.0, "challenge_score_multiplier": 1.15, "extra_group_members": 1},
	"attrition": {"name": "Изнуряющий", "description": "Сильнее враги и болезненнее события; лечение ограничено.", "enemy_attack_multiplier": 1.20, "enemy_health_multiplier": 1.15, "enemy_defense_multiplier": 1.15, "reward_multiplier": 1.30, "encounter_chance_delta": 0.03, "danger_growth_multiplier": 1.15, "event_damage_multiplier": 1.25, "healing_multiplier": 0.70, "defeat_keep_ratio": 0.35, "starting_danger": 1.0, "challenge_score_multiplier": 1.30, "extra_group_members": 0},
	"abyssal": {"name": "Бездна", "description": "Для подготовленных героев: сильные группы, мало лечения и лишь четверть добычи при поражении. Максимальный счёт испытания.", "enemy_attack_multiplier": 1.30, "enemy_health_multiplier": 1.22, "enemy_defense_multiplier": 1.18, "reward_multiplier": 1.65, "encounter_chance_delta": 0.08, "danger_growth_multiplier": 1.30, "event_damage_multiplier": 1.30, "healing_multiplier": 0.55, "defeat_keep_ratio": 0.25, "starting_danger": 1.15, "challenge_score_multiplier": 1.75, "extra_group_members": 1}
}

# Main campaign progression: each floor has its own enemy pool and guardian.
# These are progression stages, not selectable difficulty modes.
const FLOOR_COUNT: int = 8
const FLOOR_DEFS: Array[Dictionary] = [
	{"floor": 1, "name": "Порог бездны", "biome": "Мшистый край", "description": "Первые следы жизни в глубине. Освой маршрут и подготовься к Стражу древнего узла.", "boss_id": "warden", "boss_loop": 3, "enemy_pool": ["scout", "brute", "hexer", "medic", "hunter"], "enemy_attack_multiplier": 1.00, "enemy_health_multiplier": 1.00, "enemy_defense_multiplier": 1.00, "reward_multiplier": 1.00, "encounter_chance_delta": 0.000, "danger_growth_multiplier": 1.00, "event_damage_multiplier": 1.00, "healing_multiplier": 1.00, "defeat_keep_ratio": 0.40, "starting_danger": 1.00, "extra_group_members": 0},
	{"floor": 2, "name": "Споровая низина", "biome": "Споровые заросли", "description": "Токсичные заросли лечат и истощают. Матриарх мшистой гнили охраняет выход.", "boss_id": "matriarch", "boss_loop": 3, "enemy_pool": ["scout", "medic", "hunter", "sporeling"], "enemy_attack_multiplier": 1.04, "enemy_health_multiplier": 1.05, "enemy_defense_multiplier": 1.02, "reward_multiplier": 1.06, "encounter_chance_delta": 0.010, "danger_growth_multiplier": 1.03, "event_damage_multiplier": 1.05, "healing_multiplier": 0.98, "defeat_keep_ratio": 0.40, "starting_danger": 1.04, "extra_group_members": 0},
	{"floor": 3, "name": "Кристальный карьер", "biome": "Призматические жилы", "description": "Частые атаки призматических клещей карают за слабую защиту. Впереди — Сборщик импульсов.", "boss_id": "harvester", "boss_loop": 3, "enemy_pool": ["scout", "hexer", "prism_mite", "hunter"], "enemy_attack_multiplier": 1.10, "enemy_health_multiplier": 1.10, "enemy_defense_multiplier": 1.04, "reward_multiplier": 1.10, "encounter_chance_delta": 0.020, "danger_growth_multiplier": 1.05, "event_damage_multiplier": 1.08, "healing_multiplier": 0.95, "defeat_keep_ratio": 0.40, "starting_danger": 1.07, "extra_group_members": 0},
	{"floor": 4, "name": "Костяная чаща", "biome": "Погребённые останки", "description": "Бронированные дозорные держат проход. Глашатай пустого колокола завершает этот рубеж.", "boss_id": "bellkeeper", "boss_loop": 3, "enemy_pool": ["brute", "hunter", "bone_warden", "medic"], "enemy_attack_multiplier": 1.18, "enemy_health_multiplier": 1.16, "enemy_defense_multiplier": 1.07, "reward_multiplier": 1.16, "encounter_chance_delta": 0.035, "danger_growth_multiplier": 1.10, "event_damage_multiplier": 1.13, "healing_multiplier": 0.90, "defeat_keep_ratio": 0.40, "starting_danger": 1.12, "extra_group_members": 0},
	{"floor": 5, "name": "Затонувший архив", "biome": "Архивное эхо", "description": "Искажения и спектральные враги проверят сборку героя. Страж возвращается усиленным глубиной.", "boss_id": "warden", "boss_loop": 3, "enemy_pool": ["hexer", "echo_wisp", "medic", "hunter"], "enemy_attack_multiplier": 1.25, "enemy_health_multiplier": 1.22, "enemy_defense_multiplier": 1.10, "reward_multiplier": 1.25, "encounter_chance_delta": 0.050, "danger_growth_multiplier": 1.16, "event_damage_multiplier": 1.18, "healing_multiplier": 0.84, "defeat_keep_ratio": 0.40, "starting_danger": 1.16, "extra_group_members": 1},
	{"floor": 6, "name": "Корневая гробница", "biome": "Смешанные споры и кости", "description": "Враги поддерживают и прикрывают друг друга. Матриарх усилила споровую корону.", "boss_id": "matriarch", "boss_loop": 3, "enemy_pool": ["bone_warden", "brute", "sporeling", "hunter"], "enemy_attack_multiplier": 1.33, "enemy_health_multiplier": 1.28, "enemy_defense_multiplier": 1.13, "reward_multiplier": 1.35, "encounter_chance_delta": 0.065, "danger_growth_multiplier": 1.23, "event_damage_multiplier": 1.25, "healing_multiplier": 0.78, "defeat_keep_ratio": 0.40, "starting_danger": 1.22, "extra_group_members": 1},
	{"floor": 7, "name": "Разлом забытых", "biome": "Искажённое эхо", "description": "Встречи опаснее и чаще. Сборщик импульсов защищает путь к сердцу бездны.", "boss_id": "harvester", "boss_loop": 3, "enemy_pool": ["echo_wisp", "bone_warden", "prism_mite", "hexer"], "enemy_attack_multiplier": 1.43, "enemy_health_multiplier": 1.35, "enemy_defense_multiplier": 1.17, "reward_multiplier": 1.48, "encounter_chance_delta": 0.080, "danger_growth_multiplier": 1.32, "event_damage_multiplier": 1.35, "healing_multiplier": 0.70, "defeat_keep_ratio": 0.40, "starting_danger": 1.30, "extra_group_members": 1},
	{"floor": 8, "name": "Сердце бездны", "biome": "Первозданная бездна", "description": "Последний рубеж объединяет все угрозы глубины. Победи Глашатая и заверши спуск.", "boss_id": "bellkeeper", "boss_loop": 3, "enemy_pool": ["brute", "hunter", "bone_warden", "echo_wisp", "hexer"], "enemy_attack_multiplier": 1.55, "enemy_health_multiplier": 1.42, "enemy_defense_multiplier": 1.20, "reward_multiplier": 1.62, "encounter_chance_delta": 0.100, "danger_growth_multiplier": 1.42, "event_damage_multiplier": 1.45, "healing_multiplier": 0.62, "defeat_keep_ratio": 0.40, "starting_danger": 1.38, "extra_group_members": 2}
]

# Expedition mode controls the overall contract of a run. It remains separate from difficulty
# (enemy pressure) and route modifiers (shape/tactical twist).
const EXPEDITION_MODES := {
	"standard": {"name": "Обычная экспедиция", "description": "Свободный забег: возвращайтесь, когда сочтёте добычу достаточной.", "goal_loops": 0, "goal_bosses": 0, "danger_growth_multiplier": 1.0, "max_danger": 999.0, "max_scaling_loop": 999, "reward_multiplier_cap": 99.0},
	"long_expedition": {"name": "Длинная экспедиция", "description": "Пройдите 12 циклов и победите финального босса. Контрольные точки: циклы 3, 6, 9 и 12. Можно вернуться раньше с обычным риском.", "goal_loops": 12, "goal_bosses": 4, "danger_growth_multiplier": 0.72, "max_danger": 6.0, "max_scaling_loop": 12, "reward_multiplier_cap": 1.80}
}

# Optional expedition modifiers change both the tactical risk and the shape of the
# visual route, but every shape remains one continuous closed loop. These are not
# towers or tower-defense modes: enemies are fought only by the automated hero.
const RUN_MODIFIERS := {
	"standard": {
		"name": "Обычная экспедиция", "description": "Обычная разведка без дополнительных ограничений.",
		"route_shape": "classic_ring", "enemy_attack_multiplier": 1.0, "enemy_health_multiplier": 1.0,
		"enemy_defense_multiplier": 1.0, "encounter_chance_delta": 0.0, "danger_growth_multiplier": 1.0,
		"event_damage_multiplier": 1.0, "reward_multiplier": 1.0, "extra_group_members": 0,
		"starting_tile_delta": 0, "challenge": {}
	},
	"resonance": {
		"name": "Эхо резонанса", "description": "Больше встреч и усиленные враги, но добыча за победы выше.",
		"route_shape": "deep_descent", "enemy_attack_multiplier": 1.04, "enemy_health_multiplier": 1.08,
		"enemy_defense_multiplier": 1.0, "encounter_chance_delta": 0.05, "danger_growth_multiplier": 1.10,
		"event_damage_multiplier": 1.0, "reward_multiplier": 1.25, "extra_group_members": 0,
		"starting_tile_delta": 0,
		"challenge": {"id": "resonance_boss", "name": "Победить босса", "kind": "bosses", "target": 1, "scrap_reward": 24, "crystal_reward": 3}
	},
	"scarce": {
		"name": "Сухой паёк", "description": "На один стартовый тайл меньше. Награда за цикл и бой повышена.",
		"route_shape": "narrow_ring", "enemy_attack_multiplier": 1.0, "enemy_health_multiplier": 1.05,
		"enemy_defense_multiplier": 1.0, "encounter_chance_delta": 0.0, "danger_growth_multiplier": 1.0,
		"event_damage_multiplier": 1.0, "reward_multiplier": 1.20, "extra_group_members": 0,
		"starting_tile_delta": -1,
		"challenge": {"id": "scarce_two_loops", "name": "Пройти два цикла", "kind": "loops", "target": 2, "scrap_reward": 22, "crystal_reward": 2}
	},
	"unstable": {
		"name": "Нестабильная бездна", "description": "Опасные группы и болезненные события. Самая высокая дополнительная награда.",
		"route_shape": "fractured_loop", "enemy_attack_multiplier": 1.10, "enemy_health_multiplier": 1.08,
		"enemy_defense_multiplier": 1.0, "encounter_chance_delta": 0.08, "danger_growth_multiplier": 1.18,
		"event_damage_multiplier": 1.10, "reward_multiplier": 1.35, "extra_group_members": 1,
		"starting_tile_delta": 0,
		"challenge": {"id": "unstable_events", "name": "Решить два события", "kind": "events", "target": 2, "scrap_reward": 28, "crystal_reward": 3}
	}
}

const TILE_DEFS := {
	"cache": {
		"name": "Геодезический тайник", "short": "ТАЙНИК", "kind": "economy", "placement_zone": "any",
		"color": "#d9b45e", "description": "Даёт дополнительные материалы при посещении."
	},
	"hunt": {
		"name": "Место следопыта", "short": "СЛЕД", "kind": "danger", "placement_zone": "any",
		"color": "#d97963", "description": "Повышает шанс встречи и награды за победу."
	},
	"ward": {
		"name": "Корневой оберег", "short": "ОБЕРЕГ", "kind": "support", "placement_zone": "any",
		"color": "#a0dc79", "description": "Постепенно восстанавливает здоровье героя."
	},
	"rift": {
		"name": "Глубинный разлом", "short": "РАЗЛОМ", "kind": "danger", "placement_zone": "any",
		"color": "#b79de8", "description": "Опасная клетка с усиленными противниками и добычей."
	},
	"snare": {
		"name": "Сеть резонанса", "short": "СЕТЬ", "kind": "control", "placement_zone": "any",
		"color": "#78c4c9", "description": "Снижает вероятность боя и ослабляет противников, если столкновение всё же начнётся."
	},
	"signal": {
		"name": "Кристалл-резонатор", "short": "КРИСТАЛЛ", "kind": "rare", "placement_zone": "any",
		"color": "#d8b4ee", "description": "Редкий рискованный тайл: увеличивает награду и немного повышает вероятность столкновения."
	},
	"archive": {
		"name": "Архив старой экспедиции", "short": "АРХИВ", "kind": "knowledge", "placement_zone": "landscape",
		"color": "#76a8da", "description": "Редкая постройка в стороне от дороги: на каждом проходе приносит кристалл и повышает боевую награду."
	},
	"nursery": {
		"name": "Питомник бездны", "short": "ПИТОМНИК", "kind": "danger", "placement_zone": "landscape",
		"color": "#a7c96b", "description": "Редкая постройка, где опасность растёт вместе с добычей: враги сильнее, но награда заметно выше.", "enemy_pool": ["sporeling"]
	},
	"echo_spring": {"name": "Источник тихого эха", "short": "ИСТОЧНИК", "kind": "support", "placement_zone": "road", "color": "#78cdbd", "description": "Дорожный источник восстанавливает здоровье и снижает риск на узле."},
	"fault_line": {"name": "Трещина живой породы", "short": "ТРЕЩИНА", "kind": "danger", "placement_zone": "road", "color": "#d47aa7", "description": "Опасная трещина привлекает эхо-огоньков; риск выше, но растёт добыча.", "enemy_pool": ["echo_wisp"]},
	"spore_garden": {"name": "Сад спороносных колокольчиков", "short": "СПОРЫ", "kind": "support", "placement_zone": "landscape", "color": "#91b85f", "description": "Сад медленно лечит героя, но привлекает споровиков.", "enemy_pool": ["sporeling"]},
	"crystal_hive": {"name": "Кристальный улей", "short": "УЛЕЙ", "kind": "rare", "placement_zone": "landscape", "color": "#74b8e7", "description": "Улей приносит кристаллы, но его охраняют призматические клещи.", "enemy_pool": ["prism_mite"]},
	"bone_orchard": {"name": "Костяной сад", "short": "КОСТИ", "kind": "danger", "placement_zone": "landscape", "color": "#c6b69a", "description": "Костяные деревья обещают богатые трофеи, но пробуждают дозорных.", "enemy_pool": ["bone_warden"]},
	"echo_obelisk": {"name": "Обелиск немого сигнала", "short": "ОБЕЛИСК", "kind": "knowledge", "placement_zone": "landscape", "color": "#bf9be7", "description": "Обелиск усиливает редкую добычу и зовёт эхо-огоньков.", "enemy_pool": ["echo_wisp"]},
	"lost_convoy": {"name": "Обоз забытых исследователей", "short": "ОБОЗ", "kind": "rare", "placement_zone": "road", "color": "#d4a86b", "description": "Даёт материалы и подготавливает следующую находку: выше шанс получить редкую экипировку. На маршруте остаётся опасный след."},
	"hunter_marker": {"name": "Охотничья веха", "short": "ВЕХА", "kind": "danger", "placement_zone": "road", "color": "#d97a70", "description": "Помечает будущую встречу: повышает шанс выпадения экипировки до первой успешной находки. Противники сильнее и чаще выходят на след героя."}
}

# A synergy is evaluated when its trigger tile is visited and one or more adjacent
# nodes contain neighbor_tile. Effect names are interpreted by TileSystem and do
# not depend on UI text or art assets.
const TILE_SYNERGIES := [
	{"id": "supply_ward", "name": "Контур снабжения", "trigger_tile": "cache", "neighbor_tile": "ward", "effects": {"scrap": 4}, "description": "Узел снабжения рядом с защитным маяком даёт +4 материала."},
	{"id": "double_cache", "name": "Двойной склад", "trigger_tile": "cache", "neighbor_tile": "cache", "effects": {"scrap": 2}, "description": "Соседние узлы снабжения дают ещё +2 материала каждый при посещении."},
	{"id": "ward_hunt", "name": "Безопасная охота", "trigger_tile": "ward", "neighbor_tile": "hunt", "effects": {"heal": 4}, "description": "Защитный маяк рядом с зоной охоты дополнительно лечит на 4 здоровья."},
	{"id": "ward_pair", "name": "Защитный контур", "trigger_tile": "ward", "neighbor_tile": "ward", "effects": {"spawn_bonus": -0.10}, "description": "Соседний защитный маяк снижает вероятность столкновения на 10 процентных пунктов."},
	{"id": "hunt_rift", "name": "Охота на разломе", "trigger_tile": "hunt", "neighbor_tile": "rift", "effects": {"reward_bonus": 0.25, "enemy_bonus": 0.05}, "description": "Зона охоты рядом с разломом повышает награду на 25%, но усиливает врага."},
	{"id": "signal_cache", "name": "Резонанс снабжения", "trigger_tile": "signal", "neighbor_tile": "cache", "effects": {"scrap": 3, "reward_bonus": 0.10}, "description": "Резонатор рядом с узлом снабжения даёт +3 материала и повышает награду за бой на 10%."},
	{"id": "cache_hunt", "name": "Трофейный тайник", "trigger_tile": "cache", "neighbor_tile": "hunt", "effects": {"scrap": 2, "reward_bonus": 0.08}, "description": "Тайник у зоны охоты даёт +2 материала и повышает награду за победу на 8%."},
	{"id": "snare_hunt", "name": "Подготовленная засада", "trigger_tile": "snare", "neighbor_tile": "hunt", "effects": {"reward_bonus": 0.12, "spawn_bonus": -0.06}, "description": "Сеть помогает выбрать цель: шанс столкновения снижен, но награда за победу выше."},
	{"id": "signal_ward", "name": "Безопасный резонатор", "trigger_tile": "signal", "neighbor_tile": "ward", "effects": {"heal": 5, "reward_bonus": 0.05}, "description": "Оберег стабилизирует резонатор: +5 здоровья и +5% к награде следующего боя."},
	{"id": "rift_signal", "name": "Питание разлома", "trigger_tile": "rift", "neighbor_tile": "signal", "effects": {"reward_bonus": 0.20, "enemy_bonus": 0.08}, "description": "Резонатор усиливает разлом: награда выше на 20%, но противники сильнее на 8%."},
	{"id": "archive_cache", "name": "Каталог находок", "trigger_tile": "archive", "neighbor_tile": "cache", "effects": {"scrap": 4, "reward_bonus": 0.08}, "description": "Архив сортирует находки тайника: +4 материала и +8% к боевой награде."},
	{"id": "archive_ward", "name": "Тихий читальный зал", "trigger_tile": "archive", "neighbor_tile": "ward", "effects": {"heal": 3, "spawn_bonus": -0.05}, "description": "Оберег стабилизирует архив: +3 здоровья и ниже шанс столкновения."},
	{"id": "nursery_rift", "name": "Инкубатор разлома", "trigger_tile": "nursery", "neighbor_tile": "rift", "effects": {"reward_bonus": 0.25, "enemy_bonus": 0.10}, "description": "Разлом подпитывает питомник: сильные враги несут на 25% больше награды."},
	{"id": "nursery_snare", "name": "Сдержанный выводок", "trigger_tile": "nursery", "neighbor_tile": "snare", "effects": {"spawn_bonus": -0.10, "enemy_bonus": -0.05}, "description": "Сеть перехвата удерживает выводок: вероятность боя и сила врагов снижены."},
	{"id": "spore_ward", "name": "Корневой симбиоз", "trigger_tile": "spore_garden", "neighbor_tile": "ward", "effects": {"heal": 5, "spawn_bonus": -0.04}, "description": "Корневой оберег стабилизирует споровый сад и возвращает 5 здоровья."},
	{"id": "crystal_archive", "name": "Каталог улья", "trigger_tile": "crystal_hive", "neighbor_tile": "archive", "effects": {"scrap": 3, "reward_bonus": 0.12}, "description": "Архив расшифровывает кристаллы улья: +3 материала и +12% к боевой награде."},
	{"id": "bone_rift", "name": "Кладбище разлома", "trigger_tile": "bone_orchard", "neighbor_tile": "rift", "effects": {"reward_bonus": 0.25, "enemy_bonus": 0.08}, "description": "Разлом будит костяного дозорного: добыча выше на 25%, враги сильнее на 8%."},
	{"id": "obelisk_snare", "name": "Заглушённый маяк", "trigger_tile": "echo_obelisk", "neighbor_tile": "snare", "effects": {"spawn_bonus": -0.08, "heal": 2, "reward_bonus": 0.05}, "description": "Сеть глушит сигнал обелиска: +2 здоровья и меньше случайных встреч."},
	{"id": "fault_hunt", "name": "Охота в трещине", "trigger_tile": "fault_line", "neighbor_tile": "hunt", "effects": {"reward_bonus": 0.16, "enemy_bonus": 0.06}, "description": "Следопыт использует трещину как ловушку: добыча выше, но цель опаснее."},
	{"id": "convoy_ward", "name": "Сторожевой привал", "trigger_tile": "lost_convoy", "neighbor_tile": "ward", "effects": {"scrap": 2, "reward_bonus": 0.05, "enemy_bonus": -0.02}, "description": "Оберег позволяет разобрать обоз спокойнее: +2 материала и небольшой бонус добычи с ослаблением угрозы."},
	{"id": "convoy_hunt", "name": "След контрабандистов", "trigger_tile": "lost_convoy", "neighbor_tile": "hunt", "effects": {"scrap": 2, "reward_bonus": 0.10, "enemy_bonus": 0.04}, "description": "Охота на следе обоза приносит +2 материала и +10% награды, но усиливает встречу."},
	{"id": "marker_snare", "name": "Контролируемая охота", "trigger_tile": "hunter_marker", "neighbor_tile": "snare", "effects": {"spawn_bonus": -0.08, "reward_bonus": 0.10, "enemy_bonus": -0.04}, "description": "Сеть стабилизирует охотничью веху: меньше случайных столкновений, слабее цель, но выше награда за подготовленную охоту."},
	{"id": "spore_hunt", "name": "Цветение приманки", "trigger_tile": "spore_garden", "neighbor_tile": "hunt", "effects": {"heal": 2, "reward_bonus": 0.10, "enemy_bonus": 0.03}, "description": "Следопыт собирает спороносные трофеи: +2 здоровья и +10% награды, но противник немного сильнее."},
	{"id": "crystal_snare", "name": "Улей под сетью", "trigger_tile": "crystal_hive", "neighbor_tile": "snare", "effects": {"spawn_bonus": -0.06, "reward_bonus": 0.08, "enemy_bonus": -0.02}, "description": "Сеть удерживает клещей в кристальном проходе: риск и сила встреч немного снижены, награда выше на 8%."},
	{"id": "bone_archive", "name": "Каталог костей", "trigger_tile": "bone_orchard", "neighbor_tile": "archive", "effects": {"scrap": 2, "reward_bonus": 0.10, "enemy_bonus": 0.04}, "description": "Архив расшифровывает костяные реликты: +2 материала и +10% награды за более опасный бой."},
	{"id": "echo_ward", "name": "Тихая линза", "trigger_tile": "echo_obelisk", "neighbor_tile": "ward", "effects": {"heal": 3, "spawn_bonus": -0.05, "reward_bonus": 0.04}, "description": "Оберег глушит сигнал обелиска, сохраняя +3 здоровья и небольшую прибавку к добыче."},
	{"id": "spore_archive", "name": "Гербарий охотника", "trigger_tile": "spore_garden", "neighbor_tile": "archive", "effects": {"scrap": 2, "reward_bonus": 0.06, "enemy_bonus": 0.02}, "description": "Архив сохраняет споры как боевой реагент: +2 материала и +6% добычи, но существа становятся чуть опаснее."},
	{"id": "crystal_hunt", "name": "Призматическая засада", "trigger_tile": "crystal_hive", "neighbor_tile": "hunt", "effects": {"reward_bonus": 0.12, "enemy_bonus": 0.04}, "description": "Следопыт помечает уязвимые грани клещей: добыча выше на 12%, но враги сильнее на 4%."},
	{"id": "bone_ward", "name": "Усыпальница под корнями", "trigger_tile": "bone_orchard", "neighbor_tile": "ward", "effects": {"heal": 4, "spawn_bonus": -0.02, "enemy_bonus": -0.03}, "description": "Оберег удерживает дозорных в пределах сада: +4 здоровья, немного ниже риск и сила встреч."},
	{"id": "echo_signal", "name": "Резонансный след", "trigger_tile": "echo_obelisk", "neighbor_tile": "signal", "effects": {"reward_bonus": 0.10, "spawn_bonus": 0.03, "enemy_bonus": 0.04}, "description": "Резонатор усиливает сигнал обелиска: награда выше на 10%, но встреча вероятнее и опаснее."},
]

# Three-node road formations reward route planning beyond simple pairwise adjacency.
# A formation resolves only when its center node is visited; the closed-loop route
# means the last and first placeable card slots can complete a pattern without occupying the immutable start node.
const ROAD_FORMATIONS := [
    {"id": "supply_patrol", "name": "Маршрут снабженческого дозора", "previous_tile": "ward", "center_tile": "cache", "next_tile": "hunt", "effects": {"scrap": 4, "reward_bonus": 0.08}, "description": "Оберег направляет следопыта к тайнику: +4 материала и +8% боевой награды при посещении центра."},
    {"id": "quiet_trap", "name": "Тихая ловушка", "previous_tile": "snare", "center_tile": "hunt", "next_tile": "snare", "effects": {"spawn_bonus": -0.12, "enemy_bonus": -0.05, "reward_bonus": 0.10}, "description": "Две сети сдерживают охоту: вероятность встречи ниже на 12 п.п., враги слабее на 5%, награда выше на 10%."},
    {"id": "stabilized_rift", "name": "Стабилизированный разлом", "previous_tile": "ward", "center_tile": "rift", "next_tile": "ward", "effects": {"heal": 5, "enemy_bonus": -0.06, "reward_bonus": 0.08}, "description": "Обереги ограничивают разлом: +5 здоровья, сила врагов ниже на 6%, награда выше на 8%."},
    {"id": "echo_ambush", "name": "Засада на резонансе", "previous_tile": "fault_line", "center_tile": "signal", "next_tile": "hunt", "effects": {"scrap": 2, "spawn_bonus": 0.04, "enemy_bonus": 0.04, "reward_bonus": 0.18}, "description": "Следопыт использует сигнал трещины: +2 материала и +18% награды, но риск встречи и сила врагов выше на 4%."},
    {"id": "healing_stride", "name": "Шаги тихого источника", "previous_tile": "echo_spring", "center_tile": "ward", "next_tile": "echo_spring", "effects": {"heal": 6, "spawn_bonus": -0.06}, "description": "Два источника питают оберег: +6 здоровья и риск случайной встречи ниже на 6 п.п."},
    {"id": "salvage_route", "name": "Разграбленный маршрут", "previous_tile": "cache", "center_tile": "lost_convoy", "next_tile": "hunt", "effects": {"scrap": 3, "reward_bonus": 0.12, "enemy_bonus": 0.05}, "description": "Тайник и охота помогают разобрать обоз: +3 материала и +12% боевой награды, но противники опаснее. Веха обоза отдельно готовит следующую редкую находку."},
    {"id": "marked_ambush", "name": "Засада по метке", "previous_tile": "snare", "center_tile": "hunter_marker", "next_tile": "hunt", "effects": {"scrap": 1, "spawn_bonus": -0.06, "enemy_bonus": -0.04, "reward_bonus": 0.12}, "description": "Сеть позволяет выбрать момент охоты: +1 материал, риск и сила врага ниже, а награда выше на 12%. Веха усиливает шанс получить экипировку в будущей встрече."}
]

# Discovery recipes are content data because they create flags used by one-time events.
const LANDSCAPE_SECRET_RECIPES := [
	{"first_tile": "archive", "second_tile": "rift", "flag": "secret_archive_rift_found", "title": "Архив и разлом", "clue": "Архивная карта сошлась с глубинным разломом."},
	{"first_tile": "nursery", "second_tile": "snare", "flag": "secret_nursery_snare_found", "title": "Питомник и сеть", "clue": "Сеть резонанса удерживает скрытое гнездо в питомнике."},
	{"first_tile": "crystal_hive", "second_tile": "echo_obelisk", "flag": "secret_prism_echo_found", "title": "Кристальный улей и обелиск", "clue": "Внутри кристаллов проступил немой ритм — две постройки связаны древним сигналом."},
	{"first_tile": "spore_garden", "second_tile": "bone_orchard", "flag": "secret_root_bone_found", "title": "Споровый сад и костяной сад", "clue": "Корни проросли сквозь кости и открыли след давно погибшего хранителя."}
]

const ENEMIES := {
	"scout": {
		"name": "Щелкун-ползун", "hp": 16, "attack": 4, "defense": 0,
		"attack_interval": 1.00, "xp": 6, "scrap": 3, "crystal": 0, "role": "fast",
		"behavior_hint": "Быстрые частые атаки", "ability_text": "частая атака"
	},
	"brute": {
		"name": "Сланцевый громила", "hp": 26, "attack": 7, "defense": 2,
		"attack_interval": 1.35, "xp": 9, "scrap": 5, "crystal": 0, "role": "tank", "defense_bonus_after_loop": 3,
		"behavior_hint": "Высокая защита и сильный удар", "ability_text": "защита"
	},
	"hexer": {
		"name": "Шёпотник глубин", "hp": 20, "attack": 6, "defense": 1,
		"attack_interval": 1.15, "xp": 8, "scrap": 4, "crystal": 1, "role": "caster",
		"behavior_hint": "Каждая третья атака замедляет героя", "ability_text": "ослабление"
	},
	"medic": {
		"name": "Споровик-проводник", "hp": 19, "attack": 4, "defense": 1,
		"attack_interval": 1.55, "xp": 10, "scrap": 5, "crystal": 1, "role": "support",
		"behavior_hint": "В группе лечит союзника с самым низким здоровьем", "ability_text": "поддержка"
	},
	"hunter": {
		"name": "Глубинный выслеживатель", "hp": 21, "attack": 6, "defense": 1,
		"attack_interval": 1.20, "xp": 10, "scrap": 6, "crystal": 1, "role": "hunter",
		"behavior_hint": "Усиливает удар против героя с низким здоровьем", "ability_text": "добивание"
	},
	"sporeling": {"name": "Споровик-бубенчик", "hp": 23, "attack": 4, "defense": 1, "attack_interval": 1.38, "xp": 11, "scrap": 5, "crystal": 1, "role": "support", "landscape_only": true, "biome_tag": "spore", "tags": ["spore", "support"], "behavior_hint": "Поддерживает споровых союзников", "ability_text": "споровая поддержка"},
	"prism_mite": {"name": "Призматический клещ", "hp": 18, "attack": 5, "defense": 0, "attack_interval": 0.82, "xp": 9, "scrap": 5, "crystal": 2, "role": "fast", "landscape_only": true, "biome_tag": "crystal", "tags": ["crystal", "insect", "fast"], "behavior_hint": "Часто атакует и несёт кристаллы", "ability_text": "частая атака"},
	"bone_warden": {"name": "Костяной дозорный", "hp": 34, "attack": 7, "defense": 3, "attack_interval": 1.52, "xp": 14, "scrap": 8, "crystal": 1, "role": "tank", "defense_bonus_after_loop": 2, "landscape_only": true, "biome_tag": "bone", "tags": ["bone", "undead", "armored"], "behavior_hint": "Медленный и крепкий охранник сада", "ability_text": "костяная защита"},
	"echo_wisp": {"name": "Эхо-огонёк", "hp": 20, "attack": 7, "defense": 0, "attack_interval": 1.05, "xp": 12, "scrap": 6, "crystal": 2, "role": "caster", "landscape_only": true, "biome_tag": "echo", "tags": ["echo", "spectral", "caster"], "behavior_hint": "Хрупкий, но наносит сильные импульсные удары", "ability_text": "импульс эха"}
}

# Elite abilities are role-based and data-driven. They affect the hero through
# the shared status system; elites never summon towers or alter the closed route.
const ELITE_ROLE_ABILITIES := {
	"fast": {"name": "Рваный рывок", "telegraph": "Элитный ползун готовит кровоточащий рывок.", "effect_id": "bleed", "duration": 4.0, "magnitude": 2.0},
	"tank": {"name": "Пробивающий удар", "telegraph": "Элитный громила готовит пробивающий удар.", "effect_id": "wound", "duration": 4.0, "magnitude": 0.12},
	"caster": {"name": "Волна искажения", "telegraph": "Элитный шёпотник собирает волну искажения.", "effect_id": "distortion", "duration": 3.5, "magnitude": 0.18},
	"support": {"name": "Споровый выброс", "telegraph": "Элитный споровик готовит отравляющий выброс.", "effect_id": "poison", "duration": 4.0, "magnitude": 2.0},
	"hunter": {"name": "Ослабляющий выпад", "telegraph": "Элитный выслеживатель готовит ослабляющий выпад.", "effect_id": "weakness", "duration": 3.0, "magnitude": 0.18}
}

# Neutral prototype bosses. Combat rules refer to IDs and parameters, never UI or art.
const BOSSES := {
	"warden": {
		"name": "Страж древнего узла", "hp": 92, "attack": 10, "defense": 3,
		"attack_interval": 1.42, "xp": 28, "scrap": 18, "crystal": 4,
		"role": "boss", "special_name": "Перегрузка",
		"phases": [
			{"threshold": 1.0, "name": "Наблюдение", "attack_multiplier": 1.0, "defense_bonus": 0, "attack_interval": 1.42, "special_every": 3, "telegraph": "Страж накапливает Перегрузку."},
			{"threshold": 0.66, "name": "Перегрузка", "attack_multiplier": 1.12, "defense_bonus": 1, "attack_interval": 1.25, "special_every": 3, "telegraph": "Страж собирает заряд для Перегрузки.", "status_on_enter": {"target": "boss", "id": "barrier", "duration": 5.0, "magnitude": 10.0}},
			{"threshold": 0.33, "name": "Критический режим", "attack_multiplier": 1.25, "defense_bonus": 0, "attack_interval": 1.05, "special_every": 2, "telegraph": "Страж собирается высвободить критический заряд.", "status_on_enter": {"target": "boss", "id": "regeneration", "duration": 3.0, "magnitude": 4.0}}
		]
	},
	"harvester": {
		"name": "Светожор — сборщик импульсов", "hp": 104, "attack": 9, "defense": 2,
		"attack_interval": 1.18, "xp": 32, "scrap": 21, "crystal": 5,
		"role": "boss", "special_name": "Импульсный разряд",
		"special_effect_id": "distortion", "special_effect_duration": 3.5, "special_effect_magnitude": 0.18,
		"special_effect_log": "Импульсный разряд замедляет атаки героя.",
		"phases": [
			{"threshold": 1.0, "name": "Сбор", "attack_multiplier": 1.0, "defense_bonus": 0, "attack_interval": 1.18, "special_every": 3, "telegraph": "Сборщик собирает импульсный заряд."},
			{"threshold": 0.66, "name": "Перегрузка контура", "attack_multiplier": 1.15, "defense_bonus": 0, "attack_interval": 1.02, "special_every": 3, "telegraph": "Сборщик начинает нестабильную перезарядку.", "status_on_enter": {"target": "boss", "id": "regeneration", "duration": 3.0, "magnitude": 3.0}},
			{"threshold": 0.33, "name": "Разряд ядра", "attack_multiplier": 1.30, "defense_bonus": 1, "attack_interval": 0.92, "special_every": 2, "telegraph": "Сборщик готовит мощный импульсный разряд.", "status_on_enter": {"target": "boss", "id": "barrier", "duration": 4.0, "magnitude": 14.0}}
		]
	},
	"matriarch": {
		"name": "Матриарх мшистой гнили", "hp": 118, "attack": 8, "defense": 2,
		"attack_interval": 1.48, "xp": 35, "scrap": 24, "crystal": 5,
		"role": "boss", "special_name": "Споровая корона",
		"special_effect_id": "poison", "special_effect_duration": 4.0, "special_effect_magnitude": 2.0,
		"special_effect_log": "Споры Матриарха отравляют героя и продолжают наносить урон после удара.",
		"phases": [
			{"threshold": 1.0, "name": "Пробуждение корней", "attack_multiplier": 1.0, "defense_bonus": 0, "attack_interval": 1.48, "special_every": 3, "telegraph": "Матриарх собирает облако спор."},
			{"threshold": 0.66, "name": "Живые корни", "attack_multiplier": 1.12, "defense_bonus": 1, "attack_interval": 1.28, "special_every": 3, "telegraph": "Корни Матриарха стягиваются вокруг ядра.", "status_on_enter": {"target": "boss", "id": "regeneration", "duration": 4.0, "magnitude": 5.0}},
			{"threshold": 0.33, "name": "Споровый шторм", "attack_multiplier": 1.32, "defense_bonus": 0, "attack_interval": 1.03, "special_every": 2, "telegraph": "Матриарх выпускает смертельный спороносный поток.", "status_on_enter": {"target": "hero", "id": "poison", "duration": 4.0, "magnitude": 2.0}}
		]
	},
	"bellkeeper": {
		"name": "Глашатай пустого колокола", "hp": 112, "attack": 11, "defense": 2,
		"attack_interval": 1.30, "xp": 38, "scrap": 25, "crystal": 6,
		"role": "boss", "special_name": "Резонанс тишины",
		"special_effect_id": "weakness", "special_effect_duration": 3.0, "special_effect_magnitude": 0.18,
		"special_effect_log": "Звон пустого колокола ослабляет следующий ответный удар героя.",
		"phases": [
			{"threshold": 1.0, "name": "Первый звон", "attack_multiplier": 1.0, "defense_bonus": 0, "attack_interval": 1.30, "special_every": 3, "telegraph": "Глашатай настраивает пустой колокол."},
			{"threshold": 0.66, "name": "Эхо в костях", "attack_multiplier": 1.18, "defense_bonus": 1, "attack_interval": 1.14, "special_every": 3, "telegraph": "Звон возвращается с искажённой частотой.", "status_on_enter": {"target": "hero", "id": "weakness", "duration": 3.0, "magnitude": 0.18}},
			{"threshold": 0.33, "name": "Последняя тишина", "attack_multiplier": 1.36, "defense_bonus": 0, "attack_interval": 0.96, "special_every": 2, "telegraph": "Глашатай готовит резонанс, который гасит ответный удар.", "status_on_enter": {"target": "boss", "id": "barrier", "duration": 4.0, "magnitude": 16.0}}
		]
	}
}

const BUILDINGS := {
	"forge": {
		"name": "Мастерская снаряжения", "description": "Усиливает базовую атаку героя.",
		"base_scrap": 24, "base_crystal": 0, "scrap_step": 14, "crystal_step": 2,
		"max_level": 5, "effect": "+2 к атаке за уровень", "attack_per_level": 2,
		"hp_per_level": 0, "defense_per_level": 0, "loop_scrap_per_level": 0
	},
	"infirmary": {
		"name": "Станция первой помощи", "description": "Увеличивает запас здоровья и защиту.",
		"base_scrap": 20, "base_crystal": 5, "scrap_step": 13, "crystal_step": 3,
		"max_level": 5, "effect": "+12 здоровья за уровень", "attack_per_level": 0,
		"hp_per_level": 12, "defense_per_level": 1, "loop_scrap_per_level": 0
	},
	"salvage": {
		"name": "Переработчик минералов", "description": "Повышает добычу за завершённые циклы. Улучшения требуют пыль утраченных вещей из переполненного рюкзака.",
		"base_scrap": 28, "base_crystal": 7, "scrap_step": 17, "crystal_step": 4,
		"echo_dust_base": 3, "echo_dust_step": 2,
		"max_level": 5, "effect": "+1 материал за цикл за уровень; принимает пыль утраченных вещей", "attack_per_level": 0,
		"hp_per_level": 0, "defense_per_level": 0, "loop_scrap_per_level": 1
	},
	"cartographer": {
		"name": "Обсерватория картографов", "description": "Помогает находить редкие структуры и стратегические карты в потоке тайлов.",
		"base_scrap": 32, "base_crystal": 4, "scrap_step": 18, "crystal_step": 3,
		"max_level": 5, "effect": "+10% к весу редких карт за уровень (до +50%)", "attack_per_level": 0,
		"hp_per_level": 0, "defense_per_level": 0, "loop_scrap_per_level": 0
	}
}

# Permanent shelter development is split into four genuinely independent entry paths.
# Branch membership is presentation metadata; research IDs and save compatibility stay stable.
const RESEARCH_BRANCHES := {
	"tactics": {
		"name": "01 · Тактика поля",
		"summary": "Больше вариантов раскладки и ранний доступ к редким структурам.",
		"style": "Гибкость тайлов",
		"nodes": ["route_archive", "rare_survey"],
		"entry_node": "route_archive"
	},
	"preparation": {
		"name": "02 · Подготовка героя",
		"summary": "Усильте героя перед выходом и улучшите восстановление между циклами.",
		"style": "Бой и выживание",
		"nodes": ["field_training", "medical_relay"],
		"entry_node": "field_training"
	},
	"scouting": {
		"name": "03 · Разведка и угрозы",
		"summary": "Лучше изучайте опасные атаки и уменьшайте цену неудачных решений.",
		"style": "Контроль риска",
		"nodes": ["boss_analysis", "event_forecasting"],
		"entry_node": "boss_analysis"
	},
	"economy": {
		"name": "04 · Экономика убежища",
		"summary": "Инвестируйте в доход за циклы и откройте дальнейшее развитие редких ресурсов.",
		"style": "Материалы и кристаллы",
		"nodes": ["supply_contracts", "advanced_salvage", "crystal_study"],
		"entry_node": "supply_contracts"
	}
}

# Permanent research tree. Prerequisites and effects are data-driven so the tree
# can be extended without coupling research rules to the UI.
# Historical ID -> current stable ID migrations go here if a research node is ever renamed.
# Keep these IDs stable whenever possible; aliases avoid silently losing unlocks in old profiles.
const BASE_RESEARCH_ID_ALIASES := {}

func canonical_research_id(research_id: String) -> String:
	var canonical := research_id
	var visited: Array[String] = []
	while BASE_RESEARCH_ID_ALIASES.has(canonical) and not visited.has(canonical):
		visited.append(canonical)
		canonical = str(BASE_RESEARCH_ID_ALIASES[canonical])
	return canonical

const BASE_RESEARCH := {
	"route_archive": {
		"branch": "tactics",
		"name": "Картографический архив",
		"description": "Расширяет подготовку к экспедиции: герой начинает забег с дополнительным тайлом.",
		"effect_text": "+1 стартовый тактический тайл",
		"scrap_cost": 32, "crystal_cost": 3,
		"prerequisites": [],
		"effects": {"starting_tiles": 1}
	},
	"medical_relay": {
		"branch": "preparation",
		"name": "Медицинский ретранслятор",
		"description": "Позволяет эффективнее восстанавливаться при прохождении границы цикла.",
		"effect_text": "+4 дополнительного лечения за цикл",
		"scrap_cost": 48, "crystal_cost": 5,
		"prerequisites": ["field_training"],
		"effects": {"loop_heal_bonus": 4}
	},
	"boss_analysis": {
		"branch": "scouting",
		"name": "Протокол анализа угроз",
		"description": "Сканирует повторяющиеся сигнатуры особых атак боссов и даёт герою больше времени на ответ.",
		"effect_text": "Особая атака босса раз в 4 удара вместо 3",
		"scrap_cost": 55, "crystal_cost": 8,
		"prerequisites": [],
		"effects": {"boss_special_cadence_bonus": 1}
	},
	"advanced_salvage": {
		"branch": "economy",
		"name": "Расширенный переработчик",
		"description": "Собирает остаточные материалы с маршрута. Требует контракты снабжения.",
		"effect_text": "+2 материала за каждый завершённый цикл",
		"scrap_cost": 70, "crystal_cost": 9,
		"prerequisites": ["supply_contracts"],
		"effects": {"loop_scrap_bonus": 2}
	},
	"rare_survey": {
		"branch": "tactics",
		"name": "Разведка редких узлов",
		"description": "Открывает редкие тактические структуры раньше в забеге.",
		"effect_text": "Разломы и резонаторы могут появляться в награде раньше",
		"scrap_cost": 44, "crystal_cost": 5,
		"prerequisites": ["route_archive"],
		"effects": {"unlock_rare_tiles": 1}
	},
	"field_training": {
		"branch": "preparation",
		"name": "Полевые упражнения",
		"description": "Постоянно улучшает стартовую боевую подготовку героя.",
		"effect_text": "+2 к базовой атаке в каждой экспедиции",
		"scrap_cost": 42, "crystal_cost": 4,
		"prerequisites": [],
		"effects": {"field_training_attack": 2}
	},
	"event_forecasting": {
		"branch": "scouting",
		"name": "Прогнозирование событий",
		"description": "Анализ опасных сценариев помогает снизить урон от решений событий.",
		"effect_text": "−20% урона от негативных эффектов событий",
		"scrap_cost": 56, "crystal_cost": 7,
		"prerequisites": ["boss_analysis"],
		"effects": {"event_damage_reduction": 0.20}
	},
	"supply_contracts": {
		"branch": "economy",
		"name": "Контракты снабжения",
		"description": "Договоры с мастерскими приносят припасы на каждом завершённом цикле.",
		"effect_text": "+2 материала за цикл",
		"scrap_cost": 40, "crystal_cost": 4,
		"prerequisites": [],
		"effects": {"route_reward_bonus": 2}
	},
	"crystal_study": {
		"branch": "economy",
		"name": "Исследование кристаллического цикла",
		"description": "Стабилизирует добычу редких ресурсов на регулярных рубежах маршрута после развития переработки.",
		"effect_text": "+1 редкий ресурс при каждом штатном кристаллическом рубеже",
		"scrap_cost": 74, "crystal_cost": 10,
		"prerequisites": ["advanced_salvage"],
		"effects": {"loop_crystal_bonus": 1}
	}
}

const PERKS := {
	"power": {"name": "Силовой импульс", "description": "+2 к атаке", "category": "Атака", "max_stacks": 3, "attack": 2},
	"vitality": {"name": "Усиленный каркас", "description": "+14 к максимальному здоровью и лечение", "category": "Защита", "max_stacks": 3, "hp": 14},
	"tempo": {"name": "Ускоренный цикл", "description": "+12% к скорости атак", "category": "Темп", "max_stacks": 3, "speed": 0.12},
	"precision": {"name": "Точная настройка", "description": "+5% к шансу критического удара", "category": "Атака", "max_stacks": 3, "crit": 0.05},
	"bulwark": {"name": "Фазовый барьер", "description": "+1 к защите", "category": "Защита", "max_stacks": 3, "defense": 1},
	"vampirism": {"name": "Возврат импульса", "description": "+2 здоровья после победы", "category": "Восстановление", "max_stacks": 2, "kill_heal": 2},
	"scavenger": {"name": "Сбор остаточного заряда", "description": "+1 материал при посещении размещённого тайла", "category": "Экономика", "max_stacks": 2, "tile_scrap": 1},
	"fortune": {"name": "Калибровка награды", "description": "+8% к добыче с победы", "category": "Экономика", "max_stacks": 3, "reward_bonus": 0.08},
	"ambush": {"name": "Тихий проход", "description": "−4 процентных пункта к шансу встречи на маршруте", "category": "Контроль", "max_stacks": 2, "tile_spawn_bonus": -0.04},
	"field_medic": {"name": "Первая помощь", "description": "+2 здоровья после решения события", "category": "Восстановление", "max_stacks": 2, "event_heal": 2}
}

const EXPEDITION_EVENTS := {
	"sealed_cache": {
		"name": "Старый тайник",
		"narrative": "Под зарослями мха обнаружен старый геодезический тайник. Внутри что-то тихо звенит, а каменная защёлка покрыта светящимися прожилками.",
		"weight": 1.2, "min_loop": 0,
		"choices": [
			{"id": "open_carefully", "title": "Открыть осторожно", "description": "+5 материалов и +4 здоровья", "effects": {"scrap": 5, "heal": 4, "set_flags": ["cache_opened"]}},
			{"id": "force_lock", "title": "Сорвать замок силой", "description": "+11 материалов, но −10 здоровья; шум привлекает угрозу", "effects": {"scrap": 11, "damage": 10, "spawn_bonus": 0.14, "reward_bonus": 0.12, "set_flags": ["cache_opened", "signal_debt"]}}
		]
	},
	"damaged_beacon": {
		"name": "Обрушенный маяк",
		"narrative": "На уступе стоит сломанный маяк старой экспедиции. Его кристалл ещё светится: заряд можно направить на лечение или осторожно извлечь.",
		"weight": 1.0, "min_loop": 0,
		"choices": [
			{"id": "attune_beacon", "title": "Настроить маяк", "description": "Восстановить до 16 здоровья и получить 1 редкий ресурс", "effects": {"heal": 16, "crystals": 1, "set_flags": ["beacon_attuned"]}},
			{"id": "extract_core", "title": "Извлечь ядро", "description": "+4 редких ресурса, но −16 здоровья и выше опасность", "effects": {"crystals": 4, "damage": 16, "danger_delta": 0.12, "reward_bonus": 0.1, "set_flags": ["signal_debt"]}}
		]
	},
	"lost_trader": {
		"name": "Брошенная стоянка",
		"narrative": "У дороги остались упаковки и полевой обменный модуль. Одни детали ещё пригодны, другие можно обменять на редкий материал.",
		"weight": 0.9, "min_loop": 0,
		"choices": [
			{"id": "trade_crystals", "title": "Обменять 8 материалов", "description": "Потратить 8 материалов из добычи и получить 2 редких ресурса", "effects": {"cost_scrap": 8, "crystals": 2, "set_flags": ["trader_mark"]}},
			{"id": "search_camp", "title": "Обыскать стоянку", "description": "+6 материалов, но мелкие обломки наносят 5 урона", "effects": {"scrap": 6, "damage": 5, "set_flags": ["cache_opened"]}}
		]
	},
	"unstable_anomaly": {
		"name": "Светящаяся аномалия",
		"narrative": "Воздух над трещиной дрожит, а из глубины пульсирует голубой свет. Можно стабилизировать разлом или рискнуть ради выброса редких кристаллов.",
		"weight": 0.7, "min_loop": 1,
		"choices": [
			{"id": "stabilize_anomaly", "title": "Стабилизировать", "description": "Потратить 5 материалов, восстановить 8 здоровья и снизить опасность", "effects": {"cost_scrap": 5, "heal": 8, "danger_delta": -0.12, "set_flags": ["anomaly_stabilized"], "clear_flags": ["signal_debt"]}},
			{"id": "absorb_anomaly", "title": "Поглотить импульс", "description": "+7 материалов и +3 редких ресурса, но −12 здоровья; встреча станет вероятнее", "effects": {"scrap": 7, "crystals": 3, "damage": 12, "danger_delta": 0.14, "spawn_bonus": 0.1, "reward_bonus": 0.2, "set_flags": ["signal_debt"]}}
		]
	},
	"beacon_echo": {
		"name": "Эхо маяка",
		"narrative": "Настроенный ранее маяк отвечает коротким импульсом. Теперь можно направить его на восстановление или на следующую награду.",
		"weight": 0.8, "min_loop": 1, "requires_flag": "beacon_attuned", "excludes_flag": "beacon_echo_resolved", "resolved_flag": "beacon_echo_resolved", "chain_weight_multiplier": 2.5,
		"choices": [
			{"id": "recall_charge", "title": "Вернуть заряд", "description": "+1 редкий ресурс и восстановить 6 здоровья", "effects": {"crystals": 1, "heal": 6, "set_flags": ["beacon_echo_resolved"]}},
			{"id": "route_pulse", "title": "Направить импульс в путь", "description": "+5 материалов; следующая победа получит бонус к награде", "effects": {"scrap": 5, "set_flags": ["beacon_echo_resolved", "route_pulse"]}}
		]
	},
	"cache_echo": {
		"name": "След контейнера",
		"narrative": "Механизм из найденного контейнера реагирует на окружающие узлы и открывает спрятанный отсек.",
		"weight": 0.7, "min_loop": 1, "requires_flag": "cache_opened", "excludes_flag": "cache_echo_resolved", "resolved_flag": "cache_echo_resolved", "chain_weight_multiplier": 2.2,
		"choices": [
			{"id": "take_cache_reward", "title": "Забрать материалы", "description": "+8 материалов", "effects": {"scrap": 8, "set_flags": ["cache_echo_resolved"]}},
			{"id": "study_cache", "title": "Изучить механизм", "description": "+2 редких ресурса и слегка повысить опасность ради будущей награды", "effects": {"crystals": 2, "danger_delta": 0.05, "reward_bonus": 0.08, "set_flags": ["cache_echo_resolved", "route_pulse"]}}
		]
	},
	"signal_pursuit": {
		"name": "Охота по следу сигнала",
		"narrative": "Шум предыдущего решения привлёк преследователей. Можно потратить материалы на маскировку или рискнуть и попытаться обмануть их.",
		"weight": 0.9, "min_loop": 1, "requires_flag": "signal_debt", "excludes_flag": "signal_pursuit_resolved", "resolved_flag": "signal_pursuit_resolved", "chain_weight_multiplier": 3.0,
		"choices": [
			{"id": "hide_signal", "title": "Замаскировать след", "description": "Потратить 7 материалов, снизить опасность и убрать долг сигнала", "effects": {"cost_scrap": 7, "danger_delta": -0.18, "clear_flags": ["signal_debt"], "set_flags": ["signal_pursuit_resolved"]}},
			{"id": "bait_pursuers", "title": "Увести преследователей", "description": "+7 материалов и +15% к награде, но бой станет вероятнее", "effects": {"scrap": 7, "spawn_bonus": 0.15, "reward_bonus": 0.15, "clear_flags": ["signal_debt"], "set_flags": ["signal_pursuit_resolved", "route_pulse"]}}
		]
	},
	"archive_rift_echo": {
		"name": "Эхо за закрытой картой",
		"narrative": "Когда архив и разлом оказались рядом, на старой карте проступили координаты комнаты, которой нет на плане. За стеной слышно сердцебиение глубины.",
		"weight": 1.0, "min_loop": 1, "requires_flag": "secret_archive_rift_found", "excludes_flag": "secret_archive_rift_claimed", "resolved_flag": "secret_archive_rift_claimed", "guaranteed_when_flag": true,
		"choices": [
			{"id": "seal_echo", "title": "Запечатать эхо", "description": "Тайный Компас за закрытой картой, +2 редких ресурса и до 8 здоровья", "effects": {"crystals": 2, "heal": 8, "grant_item_id": "echo_chart_core", "set_flags": ["secret_echo_sealed", "secret_archive_rift_claimed"]}},
			{"id": "follow_echo", "title": "Проследить за пульсом", "description": "Клинок незамкнутого разлома и +5 редких ресурсов; −18 здоровья, опасность и награда вырастут", "effects": {"crystals": 5, "damage": 18, "danger_delta": 0.15, "reward_bonus": 0.20, "grant_item_id": "riftwalker_edge", "set_flags": ["secret_echo_followed", "secret_archive_rift_claimed"]}}
		]
	},
	"sealed_brood": {
		"name": "Гнездо за сетью",
		"narrative": "Сеть резонанса удерживала не обычную угрозу, а целое гнездо. Питомник бездны реагирует на ловушку, и теперь можно решить судьбу выводка.",
		"weight": 1.0, "min_loop": 1, "requires_flag": "secret_nursery_snare_found", "excludes_flag": "secret_nursery_snare_claimed", "resolved_flag": "secret_nursery_snare_claimed", "guaranteed_when_flag": true,
		"choices": [
			{"id": "spare_brood", "title": "Усыпить выводок", "description": "Панцирь тихого выводка, +3 редких ресурса, +4 материала и до 12 здоровья", "effects": {"crystals": 3, "scrap": 4, "heal": 12, "grant_item_id": "brood_shell", "set_flags": ["secret_brood_spared", "secret_nursery_snare_claimed"]}},
			{"id": "hunt_brood", "title": "Использовать гнездо как приманку", "description": "Ядро приманивающего импульса, +7 материалов и +2 редких ресурса; −10 здоровья и повышенный шанс боя", "effects": {"scrap": 7, "crystals": 2, "damage": 10, "spawn_bonus": 0.16, "reward_bonus": 0.20, "grant_item_id": "snare_hunter_core", "set_flags": ["secret_brood_hunted", "secret_nursery_snare_claimed"]}}
		]
	},
	"prism_echo": {
		"name": "Сердце кристального эха",
		"narrative": "Кристальный улей и обелиск складываются в единый резонатор. В его сердцевине бьётся призматический импульс: его можно принять или направить в бездну, усилив будущую добычу.",
		"weight": 1.0, "min_loop": 1, "requires_flag": "secret_prism_echo_found", "excludes_flag": "secret_prism_echo_claimed", "resolved_flag": "secret_prism_echo_claimed", "guaranteed_when_flag": true,
		"choices": [
			{"id": "bind_prism", "title": "Закрепить сердцевину", "description": "Тайное ядро: +6% уклонения, +4% вампиризма и +8% награды; +3 кристалла и до 8 здоровья", "effects": {"crystals": 3, "heal": 8, "grant_item_id": "prism_heart", "set_flags": ["secret_prism_bound", "secret_prism_echo_claimed"]}},
			{"id": "feed_prism", "title": "Накормить немой сигнал", "description": "Тайная вуаль эха, +8 материалов и +2 кристалла; −8 здоровья, опасность и будущая награда выше", "effects": {"scrap": 8, "crystals": 2, "damage": 8, "danger_delta": 0.10, "reward_bonus": 0.20, "grant_item_id": "echo_veil", "set_flags": ["secret_prism_fed", "secret_prism_echo_claimed"]}}
		]
	},
	"root_bone_memory": {
		"name": "Память корня и кости",
		"narrative": "Споры проросли сквозь костяной сад и разбудили отголосок его хранителя. Можно забрать защитную мантию или превратить древний импульс в клинок, заплатив собственным здоровьем.",
		"weight": 1.0, "min_loop": 1, "requires_flag": "secret_root_bone_found", "excludes_flag": "secret_root_bone_claimed", "resolved_flag": "secret_root_bone_claimed", "guaranteed_when_flag": true,
		"choices": [
			{"id": "quiet_root", "title": "Успокоить корни", "description": "Мантия хранителя, +4 материала и до 12 здоровья", "effects": {"scrap": 4, "heal": 12, "grant_item_id": "rootwatch_mantle", "set_flags": ["secret_root_restored", "secret_root_bone_claimed"]}},
			{"id": "wake_bone_edge", "title": "Разбудить костяной импульс", "description": "Клинок дозорного, +3 кристалла и +18% награды, но −10 здоровья и больше столкновений", "effects": {"crystals": 3, "damage": 10, "spawn_bonus": 0.14, "reward_bonus": 0.18, "grant_item_id": "bone_impulse_edge", "set_flags": ["secret_root_awakened", "secret_root_bone_claimed"]}}
		]
	}
}

const EXPEDITION_OBJECTIVES := {
	"cycle_milestone": {"name": "Проверка маршрута", "description": "Завершите 2 полных цикла.", "kind": "loops", "target": 2, "scrap_reward": 18, "crystal_reward": 1},
	"boss_contract": {"name": "Контракт на босса", "description": "Победите одного босса.", "kind": "bosses", "target": 1, "scrap_reward": 16, "crystal_reward": 2},
	"combat_record": {"name": "Боевой журнал", "description": "Одержите 5 побед в сражениях.", "kind": "victories", "target": 5, "scrap_reward": 14, "crystal_reward": 1},
	"event_research": {"name": "Исследователь событий", "description": "Примите решения в 2 событиях.", "kind": "events", "target": 2, "scrap_reward": 12, "crystal_reward": 2},
	"material_survey": {"name": "Сбор снабжения", "description": "Соберите не менее 300 материалов в текущей добыче.", "kind": "scrap", "target": 300, "scrap_reward": 30, "crystal_reward": 3}
}

# Optional run contracts are chosen before an expedition. They are independent
# from the random expedition objective and the modifier-specific challenge.
const EXPEDITION_CONTRACTS := {
    "none": {"name": "Без контракта", "description": "Свободная экспедиция без платы и дополнительных условий.", "kind": "none", "target": 0, "deadline_loops": 0, "scrap_cost": 0, "crystal_cost": 0, "scrap_reward": 0, "crystal_reward": 0},
    "landscape_survey": {"name": "Картографическая съёмка", "description": "Разместите 3 карты ландшафта не позднее конца 3-го цикла.", "kind": "world_tiles", "target": 3, "deadline_loops": 3, "scrap_cost": 5, "crystal_cost": 0, "scrap_reward": 18, "crystal_reward": 1},
    "bounty_hunter": {"name": "Охота по следу", "description": "Победите 5 противников не позднее конца 2-го цикла.", "kind": "victories", "target": 5, "deadline_loops": 2, "scrap_cost": 4, "crystal_cost": 0, "scrap_reward": 20, "crystal_reward": 2},
    "event_archive": {"name": "Архив экспедиций", "description": "Решите 2 события не позднее конца 3-го цикла.", "kind": "events", "target": 2, "deadline_loops": 3, "scrap_cost": 3, "crystal_cost": 0, "scrap_reward": 14, "crystal_reward": 2},
    "boss_bounty": {"name": "Заказ на Стража", "description": "Победите босса не позднее конца 4-го цикла.", "kind": "bosses", "target": 1, "deadline_loops": 4, "scrap_cost": 8, "crystal_cost": 2, "scrap_reward": 28, "crystal_reward": 4},
    "salvage_quota": {"name": "Квота снабжения", "description": "Соберите 300 материалов в добыче не позднее конца 3-го цикла.", "kind": "scrap", "target": 300, "deadline_loops": 3, "scrap_cost": 0, "crystal_cost": 0, "scrap_reward": 24, "crystal_reward": 2}
}

const ROUTE_CELL_TYPES := {
	"plain": {"name": "Каменный уступ", "color": "#6e9970"},
	"cache": {"name": "Минеральная жила", "color": "#d1ac5a"},
	"event": {"name": "След старой экспедиции", "color": "#78c4c9"},
	"danger": {"name": "Нестабильный уступ", "color": "#d97963"},
	"shrine": {"name": "Светлая ниша", "color": "#b79de8"}
}


# Validate all authored game data before a release. Errors are returned as data so
# automated tests and in-editor diagnostics can report them without crashing a run.
func validate_content_registry() -> Array[String]:
	var issues: Array[String] = []
	for legacy_id_value in BASE_RESEARCH_ID_ALIASES.keys():
		var legacy_id := str(legacy_id_value)
		var canonical_id := canonical_research_id(legacy_id)
		if legacy_id.is_empty() or str(BASE_RESEARCH_ID_ALIASES[legacy_id_value]).is_empty():
			issues.append("research alias has an empty ID or target")
		if BASE_RESEARCH.has(legacy_id):
			issues.append("research alias %s shadows an active stable ID" % legacy_id)
		if not BASE_RESEARCH.has(canonical_id):
			issues.append("research alias %s resolves to unknown/cyclic target %s" % [legacy_id, canonical_id])
	for tile_id_value in TILE_DEFS.keys():
		var tile_id := str(tile_id_value)
		var tile: Dictionary = TILE_DEFS[tile_id_value]
		for field in ["name", "short", "kind", "color", "description", "placement_zone"]:
			if not tile.has(field) or str(tile.get(field, "")).strip_edges().is_empty():
				issues.append("tile:%s missing %s" % [tile_id, field])
		if str(tile.get("placement_zone", "")) not in ["any", "road", "roadside", "landscape"]:
			issues.append("tile:%s has an unknown placement_zone" % tile_id)
		var enemy_pool_value: Variant = tile.get("enemy_pool", [])
		if typeof(enemy_pool_value) != TYPE_ARRAY:
			issues.append("tile:%s has a malformed enemy_pool" % tile_id)
		else:
			for pooled_enemy_value in enemy_pool_value:
				if not ENEMIES.has(str(pooled_enemy_value)):
					issues.append("tile:%s references unknown biome enemy %s" % [tile_id, str(pooled_enemy_value)])
	for recipe_value in LANDSCAPE_SECRET_RECIPES:
		if typeof(recipe_value) != TYPE_DICTIONARY:
			issues.append("landscape secret recipe is malformed")
			continue
		var secret_recipe: Dictionary = recipe_value
		for tile_field in ["first_tile", "second_tile"]:
			if not TILE_DEFS.has(str(secret_recipe.get(tile_field, ""))):
				issues.append("landscape secret recipe references unknown tile %s" % str(secret_recipe.get(tile_field, "")))
		if str(secret_recipe.get("flag", "")).is_empty() or str(secret_recipe.get("title", "")).is_empty():
			issues.append("landscape secret recipe is missing its discovery flag or title")
	for enemy_id_value in ENEMIES.keys():
		var enemy_id := str(enemy_id_value)
		var enemy: Dictionary = ENEMIES[enemy_id_value]
		for field in ["name", "role", "behavior_hint"]:
			if str(enemy.get(field, "")).strip_edges().is_empty():
				issues.append("enemy:%s missing %s" % [enemy_id, field])
		for field in ["hp", "attack", "attack_interval", "xp", "scrap"]:
			if not enemy.has(field) or float(enemy.get(field, 0)) <= 0.0:
				issues.append("enemy:%s invalid %s" % [enemy_id, field])
	for elite_role_value in ELITE_ROLE_ABILITIES.keys():
		var elite_role := str(elite_role_value)
		var elite_ability: Dictionary = ELITE_ROLE_ABILITIES[elite_role_value]
		var matching_enemy_role := false
		for enemy_definition_value in ENEMIES.values():
			if typeof(enemy_definition_value) == TYPE_DICTIONARY and str(enemy_definition_value.get("role", "")) == elite_role:
				matching_enemy_role = true
				break
		if not matching_enemy_role:
			issues.append("elite ability:%s has no matching enemy role" % elite_role)
		for required_field in ["name", "telegraph", "effect_id", "duration", "magnitude"]:
			if not elite_ability.has(required_field):
				issues.append("elite ability:%s missing %s" % [elite_role, required_field])
		if not STATUS_EFFECTS.has(str(elite_ability.get("effect_id", ""))) or float(elite_ability.get("duration", 0.0)) <= 0.0 or float(elite_ability.get("magnitude", -1.0)) < 0.0:
			issues.append("elite ability:%s has invalid effect parameters" % elite_role)
	var shelter_scrap_bonus_cap := int(BALANCE.get("shelter_loop_scrap_bonus_cap", -1))
	if shelter_scrap_bonus_cap < 0 or shelter_scrap_bonus_cap > 8:
		issues.append("shelter loop scrap bonus cap must stay between 0 and 8")
	if int(BALANCE.get("elite_min_loop", 0)) < 1 or int(BALANCE.get("elite_loop_interval", 0)) < 1:
		issues.append("elite schedule requires positive loop values")
	if float(BALANCE.get("elite_hp_multiplier", 0.0)) < 1.0 or float(BALANCE.get("elite_attack_multiplier", 0.0)) < 1.0 or float(BALANCE.get("elite_item_chance", 0.0)) < 0.0 or float(BALANCE.get("elite_item_chance", 1.0)) > 1.0:
		issues.append("elite tuning values are outside safe ranges")
	for boss_id_value in BOSSES.keys():
		var boss_id := str(boss_id_value)
		var boss: Dictionary = BOSSES[boss_id_value]
		var phases_value: Variant = boss.get("phases", [])
		for required_boss_field in ["name", "hp", "attack", "defense", "attack_interval", "xp", "scrap", "crystal", "special_name", "phases"]:
			if not boss.has(required_boss_field):
				issues.append("boss:%s missing %s" % [boss_id, required_boss_field])
		for positive_boss_field in ["hp", "attack", "attack_interval", "xp", "scrap"]:
			if float(boss.get(positive_boss_field, 0.0)) <= 0.0:
				issues.append("boss:%s has invalid %s" % [boss_id, positive_boss_field])
		if int(boss.get("defense", -1)) < 0 or int(boss.get("crystal", -1)) < 0:
			issues.append("boss:%s has negative defense/reward" % boss_id)
		if typeof(phases_value) != TYPE_ARRAY or phases_value.size() < 2:
			issues.append("boss:%s requires at least two phases" % boss_id)
		var previous_threshold := 1.01
		var phase_index := 0
		if typeof(phases_value) == TYPE_ARRAY:
			for phase_value in phases_value:
				if typeof(phase_value) != TYPE_DICTIONARY:
					issues.append("boss:%s has a malformed phase" % boss_id)
					phase_index += 1
					continue
				var phase: Dictionary = phase_value
				for required_phase_field in ["name", "threshold", "attack_multiplier", "defense_bonus", "attack_interval", "special_every", "telegraph"]:
					if not phase.has(required_phase_field):
						issues.append("boss:%s phase %d missing %s" % [boss_id, phase_index, required_phase_field])
				if str(phase.get("name", "")).strip_edges().is_empty() or str(phase.get("telegraph", "")).strip_edges().is_empty():
					issues.append("boss:%s phase %d needs a visible name and telegraph" % [boss_id, phase_index])
				if float(phase.get("attack_multiplier", 0.0)) <= 0.0 or float(phase.get("attack_interval", 0.0)) <= 0.0 or int(phase.get("special_every", 0)) < 1:
					issues.append("boss:%s phase %d has invalid combat values" % [boss_id, phase_index])
				var status_on_enter: Variant = phase.get("status_on_enter", {})
				if typeof(status_on_enter) == TYPE_DICTIONARY and not status_on_enter.is_empty() and not STATUS_EFFECTS.has(str(status_on_enter.get("id", ""))):
					issues.append("boss:%s phase %d references an unknown status effect" % [boss_id, phase_index])
				var threshold := float(phase.get("threshold", -1.0))
				if threshold < 0.0 or threshold > 1.0 or threshold >= previous_threshold:
					# The first phase starts at 1.0; duplicate initial boundary is allowed once.
					if not (previous_threshold > 1.0 and is_equal_approx(threshold, 1.0)):
						issues.append("boss:%s phase thresholds must descend" % boss_id)
				previous_threshold = threshold
				phase_index += 1
	if FLOOR_DEFS.size() != FLOOR_COUNT:
		issues.append("campaign must define exactly %d floors" % FLOOR_COUNT)
	var seen_floor_numbers: Dictionary = {}
	for floor_index in range(FLOOR_DEFS.size()):
		var floor_value: Variant = FLOOR_DEFS[floor_index]
		if typeof(floor_value) != TYPE_DICTIONARY:
			issues.append("floor %d definition is malformed" % (floor_index + 1))
			continue
		var floor_definition: Dictionary = floor_value
		var floor_number := int(floor_definition.get("floor", 0))
		if floor_number != floor_index + 1 or seen_floor_numbers.has(floor_number):
			issues.append("floor IDs must be unique and ordered from 1 to %d" % FLOOR_COUNT)
		seen_floor_numbers[floor_number] = true
		for field in ["name", "biome", "description", "boss_id"]:
			if str(floor_definition.get(field, "")).strip_edges().is_empty():
				issues.append("floor:%d missing %s" % [floor_number, field])
		if not BOSSES.has(str(floor_definition.get("boss_id", ""))):
			issues.append("floor:%d references unknown boss %s" % [floor_number, str(floor_definition.get("boss_id", ""))])
		if int(floor_definition.get("boss_loop", 0)) < 1:
			issues.append("floor:%d requires a positive boss loop" % floor_number)
		var floor_enemies_value: Variant = floor_definition.get("enemy_pool", [])
		if typeof(floor_enemies_value) != TYPE_ARRAY or floor_enemies_value.is_empty():
			issues.append("floor:%d requires a non-empty enemy pool" % floor_number)
		elif typeof(floor_enemies_value) == TYPE_ARRAY:
			for floor_enemy_value in floor_enemies_value:
				if not ENEMIES.has(str(floor_enemy_value)):
					issues.append("floor:%d references unknown enemy %s" % [floor_number, str(floor_enemy_value)])
		for multiplier_field in ["enemy_attack_multiplier", "enemy_health_multiplier", "enemy_defense_multiplier", "reward_multiplier", "danger_growth_multiplier", "event_damage_multiplier", "healing_multiplier", "starting_danger"]:
			var multiplier := float(floor_definition.get(multiplier_field, 0.0))
			if not is_finite(multiplier) or multiplier <= 0.0 or multiplier > 3.0:
				issues.append("floor:%d has invalid %s" % [floor_number, multiplier_field])
		var keep_ratio := float(floor_definition.get("defeat_keep_ratio", -1.0))
		if keep_ratio < 0.0 or keep_ratio > 1.0:
			issues.append("floor:%d has invalid defeat retention ratio" % floor_number)
	var seen_synergy_ids: Dictionary = {}
	var supported_tile_effects: Array[String] = ["scrap", "heal", "reward_bonus", "spawn_bonus", "enemy_bonus"]
	for synergy_value in TILE_SYNERGIES:
		if typeof(synergy_value) != TYPE_DICTIONARY:
			issues.append("tile synergy entry must be a dictionary")
			continue
		var synergy: Dictionary = synergy_value
		for field in ["id", "name", "trigger_tile", "neighbor_tile", "effects", "description"]:
			if not synergy.has(field) or str(synergy.get(field, "")).strip_edges().is_empty():
				issues.append("tile synergy missing %s" % field)
		var synergy_id := str(synergy.get("id", ""))
		if synergy_id.is_empty() or seen_synergy_ids.has(synergy_id):
			issues.append("tile synergy ID is empty or duplicated: %s" % synergy_id)
		seen_synergy_ids[synergy_id] = true
		if not TILE_DEFS.has(str(synergy.get("trigger_tile", ""))) or not TILE_DEFS.has(str(synergy.get("neighbor_tile", ""))):
			issues.append("tile synergy %s refers to an unknown tile" % synergy_id)
		var synergy_effects: Variant = synergy.get("effects", {})
		if typeof(synergy_effects) != TYPE_DICTIONARY or (synergy_effects is Dictionary and synergy_effects.is_empty()):
			issues.append("tile synergy %s has invalid or empty effects" % synergy_id)
		elif typeof(synergy_effects) == TYPE_DICTIONARY:
			for effect_key_value in synergy_effects.keys():
				if not supported_tile_effects.has(str(effect_key_value)):
					issues.append("tile synergy %s uses unsupported effect %s" % [synergy_id, str(effect_key_value)])
	var seen_road_formation_ids: Dictionary = {}
	for formation_value in ROAD_FORMATIONS:
		if typeof(formation_value) != TYPE_DICTIONARY:
			issues.append("road formation entry must be a dictionary")
			continue
		var formation: Dictionary = formation_value
		var formation_id := str(formation.get("id", ""))
		for field in ["id", "name", "previous_tile", "center_tile", "next_tile", "effects", "description"]:
			if not formation.has(field) or str(formation.get(field, "")).strip_edges().is_empty():
				issues.append("road formation missing %s" % field)
		if formation_id.is_empty() or seen_road_formation_ids.has(formation_id):
			issues.append("road formation ID is empty or duplicated: %s" % formation_id)
		seen_road_formation_ids[formation_id] = true
		for field in ["previous_tile", "center_tile", "next_tile"]:
			var formation_tile_id := str(formation.get(field, ""))
			if not TILE_DEFS.has(formation_tile_id):
				issues.append("road formation %s references unknown tile %s" % [formation_id, formation_tile_id])
			elif str(TILE_DEFS[formation_tile_id].get("placement_zone", "any")) == "landscape":
				issues.append("road formation %s uses landscape-only tile %s" % [formation_id, formation_tile_id])
		var formation_effects_value: Variant = formation.get("effects", {})
		if typeof(formation_effects_value) != TYPE_DICTIONARY or (formation_effects_value is Dictionary and formation_effects_value.is_empty()):
			issues.append("road formation %s has invalid or empty effects" % formation_id)
		elif typeof(formation_effects_value) == TYPE_DICTIONARY:
			for effect_key_value in formation_effects_value.keys():
				var effect_key := str(effect_key_value)
				var effect_amount: Variant = formation_effects_value[effect_key_value]
				if not supported_tile_effects.has(effect_key):
					issues.append("road formation %s uses unsupported effect %s" % [formation_id, effect_key])
					continue
				if typeof(effect_amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(effect_amount)):
					issues.append("road formation %s has non-numeric/non-finite effect %s" % [formation_id, effect_key])
					continue
				var numeric_amount := float(effect_amount)
				match effect_key:
					"scrap", "heal":
						if numeric_amount < 0.0 or numeric_amount > 12.0 or not is_equal_approx(numeric_amount, round(numeric_amount)):
							issues.append("road formation %s has unsafe integer effect %s" % [formation_id, effect_key])
					"reward_bonus":
						if numeric_amount < -0.50 or numeric_amount > 0.50:
							issues.append("road formation %s reward effect is out of bounds" % formation_id)
					"spawn_bonus":
						if numeric_amount < -0.50 or numeric_amount > 0.75:
							issues.append("road formation %s spawn effect is out of bounds" % formation_id)
					"enemy_bonus":
						if numeric_amount < -0.35 or numeric_amount > 0.75:
							issues.append("road formation %s enemy effect is out of bounds" % formation_id)
	for building_id_value in BUILDINGS.keys():
		var building_id := str(building_id_value)
		var building: Dictionary = BUILDINGS[building_id_value]
		for field in ["name", "description", "effect", "max_level", "base_scrap", "base_crystal", "scrap_step", "crystal_step"]:
			if not building.has(field):
				issues.append("building:%s missing %s" % [building_id, field])
		if int(building.get("max_level", 0)) < 1 or int(building.get("base_scrap", -1)) < 0 or int(building.get("base_crystal", -1)) < 0 or int(building.get("scrap_step", -1)) < 0 or int(building.get("crystal_step", -1)) < 0:
			issues.append("building:%s has invalid level or cost" % building_id)
	for mode_id_value in EXPEDITION_MODES.keys():
		var mode_id := str(mode_id_value)
		var mode: Dictionary = EXPEDITION_MODES[mode_id_value]
		for field in ["name", "description", "goal_loops", "goal_bosses", "max_danger", "max_scaling_loop", "reward_multiplier_cap"]:
			if not mode.has(field):
				issues.append("expedition mode:%s missing %s" % [mode_id, field])
		if int(mode.get("goal_loops", -1)) < 0 or int(mode.get("goal_bosses", -1)) < 0 or float(mode.get("max_danger", 0.0)) <= 0.0 or float(mode.get("reward_multiplier_cap", 0.0)) <= 0.0:
			issues.append("expedition mode:%s has invalid endgame bounds" % mode_id)
	var valid_route_shapes: Array[String] = ["classic_ring", "deep_descent", "narrow_ring", "fractured_loop"]
	for modifier_id_value in RUN_MODIFIERS.keys():
		var modifier_id := str(modifier_id_value)
		var modifier: Dictionary = RUN_MODIFIERS[modifier_id_value]
		if not valid_route_shapes.has(str(modifier.get("route_shape", ""))):
			issues.append("modifier:%s references an unknown route shape" % modifier_id)
	for event_id_value in EXPEDITION_EVENTS.keys():
		var event_id := str(event_id_value)
		var event: Dictionary = EXPEDITION_EVENTS[event_id_value]
		var choices_value: Variant = event.get("choices", [])
		if str(event.get("name", "")).strip_edges().is_empty() or typeof(choices_value) != TYPE_ARRAY or choices_value.size() < 2:
			issues.append("event:%s needs a name and at least two choices" % event_id)
		var seen_choice_ids: Dictionary = {}
		if typeof(choices_value) == TYPE_ARRAY:
			for choice_value in choices_value:
				if typeof(choice_value) != TYPE_DICTIONARY:
					issues.append("event:%s has a malformed choice" % event_id)
					continue
				var choice: Dictionary = choice_value
				var choice_id := str(choice.get("id", ""))
				if choice_id.is_empty() or seen_choice_ids.has(choice_id):
					issues.append("event:%s choice id is empty or duplicated" % event_id)
				seen_choice_ids[choice_id] = true
				if typeof(choice.get("effects", {})) != TYPE_DICTIONARY:
					issues.append("event:%s choice %s has invalid effects" % [event_id, choice_id])
	for research_id_value in BASE_RESEARCH.keys():
		var research_id := str(research_id_value)
		var research: Dictionary = BASE_RESEARCH[research_id_value]
		if float(research.get("scrap_cost", -1)) < 0.0 or float(research.get("crystal_cost", -1)) < 0.0:
			issues.append("research:%s has invalid cost" % research_id)
		if typeof(research.get("effects", {})) != TYPE_DICTIONARY:
			issues.append("research:%s has invalid effects" % research_id)
		var prerequisites_value: Variant = research.get("prerequisites", [])
		if typeof(prerequisites_value) != TYPE_ARRAY:
			issues.append("research:%s has invalid prerequisites" % research_id)
		else:
			for prerequisite_value in prerequisites_value:
				if not BASE_RESEARCH.has(str(prerequisite_value)):
					issues.append("research:%s references unknown prerequisite %s" % [research_id, str(prerequisite_value)])
	var branch_node_owners: Dictionary = {}
	for branch_id_value in RESEARCH_BRANCHES.keys():
		var branch_id := str(branch_id_value)
		var branch: Dictionary = RESEARCH_BRANCHES[branch_id_value]
		var branch_nodes_value: Variant = branch.get("nodes", [])
		if str(branch.get("name", "")).strip_edges().is_empty() or str(branch.get("summary", "")).strip_edges().is_empty():
			issues.append("research branch:%s is missing its name or summary" % branch_id)
		if typeof(branch_nodes_value) != TYPE_ARRAY or branch_nodes_value.is_empty():
			issues.append("research branch:%s has no node list" % branch_id)
			continue
		var entry_node := str(branch.get("entry_node", ""))
		if not branch_nodes_value.has(entry_node):
			issues.append("research branch:%s entry node is not in its node list" % branch_id)
		for node_value in branch_nodes_value:
			var node_id := str(node_value)
			if not BASE_RESEARCH.has(node_id):
				issues.append("research branch:%s references unknown node %s" % [branch_id, node_id])
				continue
			if branch_node_owners.has(node_id):
				issues.append("research node %s belongs to more than one branch" % node_id)
			branch_node_owners[node_id] = branch_id
			if str(BASE_RESEARCH[node_id].get("branch", "")) != branch_id:
				issues.append("research node %s branch metadata disagrees with branch list" % node_id)
		var entry_definition: Dictionary = BASE_RESEARCH.get(entry_node, {})
		var entry_prerequisites: Variant = entry_definition.get("prerequisites", [])
		if typeof(entry_prerequisites) == TYPE_ARRAY and not entry_prerequisites.is_empty():
			issues.append("research branch:%s entry must be independently unlockable" % branch_id)
	for research_id_value in BASE_RESEARCH.keys():
		var node_id := str(research_id_value)
		var research: Dictionary = BASE_RESEARCH[research_id_value]
		var branch_id := str(research.get("branch", ""))
		if not RESEARCH_BRANCHES.has(branch_id):
			issues.append("research:%s references unknown branch %s" % [node_id, branch_id])
		elif not branch_node_owners.has(node_id):
			issues.append("research:%s is absent from its declared branch" % node_id)
		var prerequisites_value: Variant = research.get("prerequisites", [])
		if typeof(prerequisites_value) == TYPE_ARRAY:
			for prerequisite_value in prerequisites_value:
				var prerequisite_id := str(prerequisite_value)
				if BASE_RESEARCH.has(prerequisite_id) and str(BASE_RESEARCH[prerequisite_id].get("branch", "")) != branch_id:
					issues.append("research:%s crosses from branch %s to %s" % [node_id, branch_id, str(BASE_RESEARCH[prerequisite_id].get("branch", ""))])
	for perk_id_value in PERKS.keys():
		var perk_id := str(perk_id_value)
		var perk: Dictionary = PERKS[perk_id_value]
		if int(perk.get("max_stacks", 0)) < 1 or str(perk.get("name", "")).strip_edges().is_empty():
			issues.append("perk:%s has invalid name or stack limit" % perk_id)
	for preset_id in ["standard", "volatile", "attrition", "abyssal"]:
		if not DIFFICULTY_PRESETS.has(preset_id):
			issues.append("missing difficulty preset %s" % preset_id)
			continue
		var preset: Dictionary = DIFFICULTY_PRESETS[preset_id]
		for field in ["name", "description", "healing_multiplier", "defeat_keep_ratio", "starting_danger", "challenge_score_multiplier"]:
			if not preset.has(field):
				issues.append("difficulty:%s missing %s" % [preset_id, field])
		if float(preset.get("healing_multiplier", 0.0)) <= 0.0 or float(preset.get("defeat_keep_ratio", -1.0)) < 0.0 or float(preset.get("defeat_keep_ratio", 1.0)) > 1.0 or float(preset.get("challenge_score_multiplier", 0.0)) < 1.0:
			issues.append("difficulty:%s has invalid risk/reward fields" % preset_id)
	for modifier_id_value in RUN_MODIFIERS.keys():
		var modifier_id := str(modifier_id_value)
		var modifier: Dictionary = RUN_MODIFIERS[modifier_id_value]
		for field in ["name", "description", "route_shape"]:
			if str(modifier.get(field, "")).strip_edges().is_empty():
				issues.append("modifier:%s missing %s" % [modifier_id, field])
		for multiplier_field in ["enemy_attack_multiplier", "enemy_health_multiplier", "enemy_defense_multiplier", "danger_growth_multiplier", "event_damage_multiplier", "reward_multiplier"]:
			if float(modifier.get(multiplier_field, 0.0)) <= 0.0:
				issues.append("modifier:%s has invalid %s" % [modifier_id, multiplier_field])
		if int(modifier.get("extra_group_members", -1)) < 0 or int(modifier.get("starting_tile_delta", 0)) < -3:
			issues.append("modifier:%s has invalid group or starting-hand delta" % modifier_id)
		var challenge_value: Variant = modifier.get("challenge", {})
		if typeof(challenge_value) != TYPE_DICTIONARY:
			issues.append("modifier:%s has malformed challenge" % modifier_id)
		elif not challenge_value.is_empty():
			for field in ["id", "name", "kind", "target", "scrap_reward", "crystal_reward"]:
				if not challenge_value.has(field):
					issues.append("modifier:%s challenge missing %s" % [modifier_id, field])
			if int(challenge_value.get("target", 0)) < 1 or int(challenge_value.get("scrap_reward", -1)) < 0 or int(challenge_value.get("crystal_reward", -1)) < 0:
				issues.append("modifier:%s has invalid challenge target or reward" % modifier_id)
	for status_id_value in STATUS_EFFECTS.keys():
		var status_id := str(status_id_value)
		var status: Dictionary = STATUS_EFFECTS[status_id_value]
		for field in ["name", "description", "kind", "stack_mode"]:
			if str(status.get(field, "")).strip_edges().is_empty():
				issues.append("status:%s missing %s" % [status_id, field])
		if float(status.get("duration", 0.0)) <= 0.0 or int(status.get("max_stacks", 0)) < 1:
			issues.append("status:%s has invalid duration or stack limit" % status_id)
		if float(status.get("max_magnitude", 0.0)) <= 0.0:
			issues.append("status:%s has invalid magnitude cap" % status_id)
		if str(status.get("kind", "")) not in ["modifier", "damage_over_time", "healing_over_time", "barrier"] or str(status.get("stack_mode", "")) not in ["refresh", "stack", "add"]:
			issues.append("status:%s has unsupported behavior" % status_id)
		if float(status.get("tick_interval", 0.0)) < 0.0 or float(status.get("tick_damage", 0.0)) < 0.0 or float(status.get("tick_heal", 0.0)) < 0.0:
			issues.append("status:%s has invalid tick values" % status_id)
		if str(status.get("kind", "")) in ["damage_over_time", "healing_over_time"] and float(status.get("tick_interval", 0.0)) <= 0.0:
			issues.append("status:%s periodic effects require a positive tick interval" % status_id)
	var supported_contract_kinds := ["none", "world_tiles", "victories", "events", "bosses", "scrap"]
	for contract_id_value in EXPEDITION_CONTRACTS.keys():
		var contract_id := str(contract_id_value)
		var contract: Dictionary = EXPEDITION_CONTRACTS[contract_id_value]
		for field in ["name", "description", "kind", "target", "deadline_loops", "scrap_cost", "crystal_cost", "scrap_reward", "crystal_reward"]:
			if not contract.has(field):
				issues.append("contract:%s missing %s" % [contract_id, field])
		if str(contract.get("kind", "")) not in supported_contract_kinds:
			issues.append("contract:%s uses unsupported progress kind" % contract_id)
		if int(contract.get("target", 0)) < 0 or int(contract.get("target", 0)) > 1000 or int(contract.get("deadline_loops", 0)) < 0:
			issues.append("contract:%s has invalid target or deadline" % contract_id)
		for cost_field in ["scrap_cost", "crystal_cost", "scrap_reward", "crystal_reward"]:
			if int(contract.get(cost_field, -1)) < 0:
				issues.append("contract:%s has invalid %s" % [contract_id, cost_field])
		if str(contract.get("name", "")).strip_edges().is_empty() or str(contract.get("description", "")).strip_edges().is_empty():
			issues.append("contract:%s needs readable instructions" % contract_id)
		if contract_id == "none" and (int(contract.get("scrap_cost", 1)) != 0 or int(contract.get("crystal_cost", 1)) != 0):
			issues.append("contract:none must be free")
	var supported_objective_kinds := ["loops", "bosses", "victories", "events", "scrap"]
	for objective_id_value in EXPEDITION_OBJECTIVES.keys():
		var objective_id := str(objective_id_value)
		var objective: Dictionary = EXPEDITION_OBJECTIVES[objective_id_value]
		for field in ["name", "description", "kind", "target", "scrap_reward", "crystal_reward"]:
			if not objective.has(field):
				issues.append("objective:%s missing %s" % [objective_id, field])
		if str(objective.get("kind", "")) not in supported_objective_kinds:
			issues.append("objective:%s uses unsupported progress kind" % objective_id)
		if int(objective.get("target", 0)) < 1 or int(objective.get("target", 0)) > 1000 or int(objective.get("scrap_reward", -1)) < 0 or int(objective.get("crystal_reward", -1)) < 0:
			issues.append("objective:%s has invalid target or reward" % objective_id)
		if str(objective.get("name", "")).strip_edges().is_empty() or str(objective.get("description", "")).strip_edges().is_empty():
			issues.append("objective:%s requires readable condition text" % objective_id)
	var research_visit_state: Dictionary = {}
	for research_id_value in BASE_RESEARCH.keys():
		if _research_dependency_cycle(str(research_id_value), research_visit_state):
			issues.append("research graph contains a prerequisite cycle")
			break
	return issues


func _research_dependency_cycle(research_id: String, states: Dictionary) -> bool:
	var state := int(states.get(research_id, 0))
	if state == 1:
		return true
	if state == 2:
		return false
	states[research_id] = 1
	var research: Dictionary = BASE_RESEARCH.get(research_id, {})
	var prerequisites: Variant = research.get("prerequisites", [])
	if typeof(prerequisites) == TYPE_ARRAY:
		for prerequisite_value in prerequisites:
			var prerequisite_id := str(prerequisite_value)
			if BASE_RESEARCH.has(prerequisite_id) and _research_dependency_cycle(prerequisite_id, states):
				return true
	states[research_id] = 2
	return false
